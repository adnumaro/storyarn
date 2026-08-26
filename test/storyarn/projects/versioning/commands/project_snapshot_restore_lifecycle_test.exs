defmodule Storyarn.Projects.Versioning.ProjectSnapshotRestoreLifecycleTest do
  use Storyarn.DataCase, async: false
  use Oban.Testing, repo: Storyarn.Repo

  import Ecto.Query
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.VersioningFixtures

  alias Ecto.Adapters.SQL.Sandbox
  alias Storyarn.Platform.Billing
  alias Storyarn.Platform.Billing.StorageReservation
  alias Storyarn.Platform.Collaboration
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Projects.Assets.StorageCleanupRequest
  alias Storyarn.Projects.Assets.StorageKeyLock
  alias Storyarn.Projects.Versioning
  alias Storyarn.Projects.Versioning.ProjectSnapshotRestore
  alias Storyarn.Projects.Versioning.ProjectSnapshotRestoreExecutor
  alias Storyarn.Repo
  alias Storyarn.Workers.ProjectSnapshotRetentionWorker
  alias Storyarn.Workers.RestoreProjectSnapshotWorker

  defmodule RaisingArchiveReader do
    @moduledoc false
    def verify(_snapshot), do: raise("reader exploded before compensation context")
  end

  setup do
    user = user_fixture()
    project = project_fixture(user)

    %{
      user: user,
      scope: user_scope_fixture(user),
      project: project,
      snapshot: full_project_snapshot_fixture(project)
    }
  end

  describe "request_project_snapshot_restore/4" do
    test "persists immutable target identity and binds one worker atomically", context do
      idempotency_key = Ecto.UUID.generate()

      assert :ok = Versioning.subscribe_project_snapshot_restores(context.project.id)

      assert {:ok, restore} = request(context, idempotency_key)
      assert_receive {:project_snapshot_restore_updated, restore_id}
      assert restore_id == restore.id

      assert restore.workspace_id == context.project.workspace_id
      assert restore.project_id == context.project.id
      assert restore.project_snapshot_id == context.snapshot.id
      assert restore.requested_by_id == context.user.id
      assert restore.idempotency_key == idempotency_key
      assert restore.status == "queued"
      assert restore.phase == "queued"
      assert restore.generation == 1
      assert restore.attempt == 0
      assert restore.snapshot_lifecycle_generation == context.snapshot.lifecycle_generation
      assert restore.snapshot_accounting_generation == context.snapshot.accounting_generation
      assert restore.archive_storage_key == context.snapshot.archive_storage_key
      assert restore.archive_size_bytes == context.snapshot.archive_size_bytes
      assert restore.archive_checksum == context.snapshot.archive_checksum
      assert restore.manifest_storage_key == context.snapshot.manifest_storage_key
      assert restore.manifest_size_bytes == context.snapshot.manifest_size_bytes
      assert restore.manifest_checksum == context.snapshot.manifest_checksum
      assert is_integer(restore.oban_job_id)

      job = Repo.get!(Oban.Job, restore.oban_job_id)
      assert job.worker == inspect(RestoreProjectSnapshotWorker)
      assert job.queue == "snapshot_restores"
      assert job.args == %{"generation" => 1, "restore_id" => restore.id}

      assert {:ok, replayed} = request(context, idempotency_key)
      assert replayed.id == restore.id
      assert Repo.aggregate(ProjectSnapshotRestore, :count) == 1
      assert [listed] = Versioning.list_project_snapshot_restores(context.project.id)
      assert listed.id == restore.id
    end

    test "rejects invalid authorization, target ownership and target state", context do
      outsider = user_fixture()

      assert {:error, :unauthorized} =
               Versioning.request_project_snapshot_restore(
                 user_scope_fixture(outsider),
                 context.project,
                 context.snapshot,
                 %{idempotency_key: Ecto.UUID.generate()}
               )

      other_project =
        project_fixture(context.user, %{workspace: Repo.preload(context.project, :workspace).workspace})

      foreign_snapshot = full_project_snapshot_fixture(other_project)

      assert {:error, :project_snapshot_not_found} =
               Versioning.request_project_snapshot_restore(
                 context.scope,
                 context.project,
                 foreign_snapshot,
                 %{idempotency_key: Ecto.UUID.generate()}
               )

      pending = pending_project_snapshot_fixture(context.project)

      assert {:error, :project_snapshot_not_restorable} =
               Versioning.request_project_snapshot_restore(
                 context.scope,
                 context.project,
                 pending,
                 %{idempotency_key: Ecto.UUID.generate()}
               )

      legacy = full_project_snapshot_fixture(context.project, %{restore_contract_version: nil})

      assert {:error, :project_snapshot_not_restorable} =
               Versioning.request_project_snapshot_restore(
                 context.scope,
                 context.project,
                 legacy,
                 %{idempotency_key: Ecto.UUID.generate()}
               )

      assert {:error, :invalid_project_snapshot_restore_request} =
               Versioning.request_project_snapshot_restore(
                 context.scope,
                 context.project,
                 context.snapshot,
                 %{idempotency_key: "not-a-uuid"}
               )
    end

    test "returns clean conflicts for a reused key or another active restore", context do
      key = Ecto.UUID.generate()
      assert {:ok, _restore} = request(context, key)

      second_snapshot = full_project_snapshot_fixture(context.project)

      assert {:error, :project_snapshot_restore_idempotency_conflict} =
               Versioning.request_project_snapshot_restore(
                 context.scope,
                 context.project,
                 second_snapshot,
                 %{idempotency_key: key}
               )

      assert {:error, :project_snapshot_restore_in_progress} =
               Versioning.request_project_snapshot_restore(
                 context.scope,
                 context.project,
                 context.snapshot,
                 %{idempotency_key: Ecto.UUID.generate()}
               )
    end

    test "serializes concurrent different keys into one request and one clean conflict", context do
      parent = self()
      barrier = make_ref()

      tasks =
        for _index <- 1..2 do
          Task.async(fn ->
            send(parent, {barrier, :ready, self()})

            receive do
              {^barrier, :go} -> request(context, Ecto.UUID.generate())
            after
              5_000 -> {:error, :barrier_timeout}
            end
          end)
        end

      ready_pids =
        Enum.map(tasks, fn _task ->
          assert_receive {^barrier, :ready, task_pid}, 5_000
          task_pid
        end)

      assert MapSet.new(ready_pids) == MapSet.new(tasks, & &1.pid)

      Enum.each(tasks, &send(&1.pid, {barrier, :go}))
      results = Enum.map(tasks, &Task.await(&1, 10_000))

      assert Enum.count(results, &match?({:ok, %ProjectSnapshotRestore{}}, &1)) == 1
      assert Enum.count(results, &match?({:error, :project_snapshot_restore_in_progress}, &1)) == 1
      assert Repo.aggregate(ProjectSnapshotRestore, :count) == 1
    end
  end

  describe "generation-fenced lifecycle" do
    test "reservation creation and binding roll back together after a post-reserve failure", context do
      {:ok, restore} = request(context, Ecto.UUID.generate())
      job = executing_job!(restore, 1)

      assert {:ok, {:claimed, claimed}} =
               Versioning.claim_project_snapshot_restore(restore.id, 1,
                 job_id: job.id,
                 attempt: 1
               )

      assert {:ok, staged} =
               Versioning.advance_project_snapshot_restore_phase(claimed.id, claimed.generation, "staging")

      attrs = restore_reservation_attrs(staged)

      assert {:error, :injected_post_reserve_failure} =
               Versioning.reserve_and_bind_project_snapshot_restore(staged.id, staged.generation, attrs,
                 after_reserve: fn _locked_restore, _reservation ->
                   {:error, :injected_post_reserve_failure}
                 end
               )

      refute Repo.get_by(StorageReservation,
               workspace_id_snapshot: staged.workspace_id,
               idempotency_key: attrs.idempotency_key
             )

      refute Repo.get!(ProjectSnapshotRestore, staged.id).storage_reservation_id
    end

    test "an active bound reservation is replayed but can never be overwritten", context do
      {:ok, restore} = request(context, Ecto.UUID.generate())
      job = executing_job!(restore, 1)

      assert {:ok, {:claimed, claimed}} =
               Versioning.claim_project_snapshot_restore(restore.id, 1,
                 job_id: job.id,
                 attempt: 1
               )

      assert {:ok, staged} =
               Versioning.advance_project_snapshot_restore_phase(claimed.id, claimed.generation, "staging")

      attrs = restore_reservation_attrs(staged)

      assert {:ok, {bound, reservation}} =
               Versioning.reserve_and_bind_project_snapshot_restore(staged.id, staged.generation, attrs)

      assert bound.storage_reservation_id == reservation.id

      assert {:ok, {replayed, replayed_reservation}} =
               Versioning.reserve_and_bind_project_snapshot_restore(staged.id, staged.generation, attrs)

      assert replayed.storage_reservation_id == reservation.id
      assert replayed_reservation.id == reservation.id

      replacement_attrs = restore_reservation_attrs(staged)

      assert {:error, :project_snapshot_restore_reservation_requires_recovery} =
               Versioning.reserve_and_bind_project_snapshot_restore(
                 staged.id,
                 staged.generation,
                 replacement_attrs
               )

      assert Repo.aggregate(
               from(reservation in StorageReservation,
                 where:
                   reservation.workspace_id_snapshot == ^staged.workspace_id and
                     reservation.kind == "restore_staging" and reservation.status == "active"
               ),
               :count
             ) == 1

      assert Repo.get!(ProjectSnapshotRestore, staged.id).storage_reservation_id == reservation.id
    end

    test "claims once, completes once and replays the completed operation", context do
      {:ok, restore} = request(context, Ecto.UUID.generate())
      job = executing_job!(restore, 1)

      assert {:error, :stale_project_snapshot_restore_generation} =
               Versioning.claim_project_snapshot_restore(restore.id, 2,
                 job_id: job.id,
                 attempt: 1
               )

      assert {:ok, {:claimed, claimed}} =
               Versioning.claim_project_snapshot_restore(restore.id, 1,
                 job_id: job.id,
                 attempt: 1
               )

      assert claimed.status == "running"
      assert claimed.phase == "preflight"
      assert claimed.generation == 2
      assert claimed.attempt == 1

      assert :ok = Versioning.subscribe_project_snapshot_restores(context.project.id)

      assert {:ok, {:claimed, duplicate_claim}} =
               Versioning.claim_project_snapshot_restore(restore.id, 1,
                 job_id: job.id,
                 attempt: 1
               )

      assert duplicate_claim.id == claimed.id
      assert duplicate_claim.generation == 2

      assert {:error, :stale_project_snapshot_restore_generation} =
               Versioning.advance_project_snapshot_restore_phase(restore.id, 1, "staging")

      assert {:ok, staged} =
               Versioning.advance_project_snapshot_restore_phase(restore.id, 2, "staging")

      assert staged.phase == "staging"
      assert_receive {:project_snapshot_restore_updated, restore_id}
      assert restore_id == restore.id

      assert {:ok, replayed_stage} =
               Versioning.advance_project_snapshot_restore_phase(restore.id, 2, "staging")

      assert replayed_stage.id == staged.id
      assert replayed_stage.state_updated_at == staged.state_updated_at

      assert {:error, :invalid_project_snapshot_restore_phase_transition} =
               Versioning.advance_project_snapshot_restore_phase(restore.id, 2, "verifying")

      assert {:error, :invalid_project_snapshot_restore_phase} =
               Versioning.advance_project_snapshot_restore_phase(restore.id, 2, "unknown")

      result = %{result_digest: String.duplicate("a", 64), reservation_id: nil, restored_entities: 7}
      assert {:ok, completed} = Versioning.complete_project_snapshot_restore(restore.id, 2, result)
      assert completed.status == "completed"
      assert completed.phase == "completed"
      assert completed.generation == 3
      assert completed.result_digest == result.result_digest
      assert completed.result == %{"reservation_id" => nil, "restored_entities" => 7}
      assert_receive {:project_snapshot_restore_updated, completed_id}
      assert completed_id == completed.id

      other_result = %{result_digest: String.duplicate("b", 64), reservation_id: nil}

      assert {:ok, replayed} =
               Versioning.complete_project_snapshot_restore(restore.id, 999, other_result)

      assert replayed.id == completed.id
      assert replayed.result_digest == result.result_digest

      assert {:ok, request_replay} = request(context, restore.idempotency_key)
      assert request_replay.id == completed.id
      assert request_replay.status == "completed"
    end

    test "rejects missing or malformed replacement entity id lists without raising", context do
      {:ok, restore} = request(context, Ecto.UUID.generate())
      job = executing_job!(restore, 1)

      assert {:ok, {:claimed, claimed}} =
               Versioning.claim_project_snapshot_restore(restore.id, 1,
                 job_id: job.id,
                 attempt: 1
               )

      valid_result = %{
        result_digest: String.duplicate("a", 64),
        reservation_id: nil,
        content_replaced: true,
        replaced_sheet_ids: [],
        replaced_flow_ids: [],
        replaced_scene_ids: []
      }

      invalid_results = [
        Map.delete(valid_result, :replaced_sheet_ids),
        Map.put(valid_result, :replaced_flow_ids, nil),
        Map.put(valid_result, :replaced_scene_ids, %{})
      ]

      for invalid_result <- invalid_results do
        assert {:error, :invalid_project_snapshot_restore_result} =
                 Versioning.complete_project_snapshot_restore(
                   restore.id,
                   claimed.generation,
                   invalid_result
                 )
      end

      persisted = Repo.get!(ProjectSnapshotRestore, restore.id)
      assert persisted.status == "running"
      assert persisted.generation == claimed.generation
    end

    test "rejects a job that does not own the exact worker delivery", context do
      {:ok, restore} = request(context, Ecto.UUID.generate())
      job = executing_job!(restore, 1)

      assert {:error, :project_snapshot_restore_job_not_executing} =
               Versioning.claim_project_snapshot_restore(restore.id, 1,
                 job_id: job.id + 1,
                 attempt: 1
               )

      job
      |> Ecto.Changeset.change(queue: "default")
      |> Repo.update!()

      assert {:error, :project_snapshot_restore_job_not_executing} =
               Versioning.claim_project_snapshot_restore(restore.id, 1,
                 job_id: job.id,
                 attempt: 1
               )

      assert Repo.get!(ProjectSnapshotRestore, restore.id).status == "queued"
    end

    test "terminal failure is idempotent", context do
      {:ok, restore} = request(context, Ecto.UUID.generate())
      job = executing_job!(restore, 1)

      assert {:ok, {:claimed, claimed}} =
               Versioning.claim_project_snapshot_restore(restore.id, 1,
                 job_id: job.id,
                 attempt: 1
               )

      assert {:ok, failed} =
               Versioning.fail_project_snapshot_restore(
                 restore.id,
                 claimed.generation,
                 :project_snapshot_restore_preflight_failed
               )

      assert failed.status == "failed"
      assert failed.generation == 3
      assert failed.failure_code == "project_snapshot_restore_preflight_failed"

      assert {:ok, replayed} =
               Versioning.fail_project_snapshot_restore(restore.id, 999, :ignored)

      assert replayed.id == failed.id
      assert replayed.failure_code == failed.failure_code
    end

    test "terminal restore history survives source retention with immutable object identity", context do
      {:ok, restore} = request(context, Ecto.UUID.generate())
      job = executing_job!(restore, 1)

      assert {:ok, {:claimed, claimed}} =
               Versioning.claim_project_snapshot_restore(restore.id, 1,
                 job_id: job.id,
                 attempt: 1
               )

      result = %{result_digest: String.duplicate("d", 64), reservation_id: nil}
      assert {:ok, completed} = Versioning.complete_project_snapshot_restore(restore.id, claimed.generation, result)

      Repo.delete!(context.snapshot)

      retained = Repo.get!(ProjectSnapshotRestore, completed.id)
      assert is_nil(retained.project_snapshot_id)
      assert retained.archive_storage_key == context.snapshot.archive_storage_key
      assert retained.archive_checksum == context.snapshot.archive_checksum
      assert retained.manifest_storage_key == context.snapshot.manifest_storage_key
      assert retained.manifest_checksum == context.snapshot.manifest_checksum
      assert retained.result_digest == result.result_digest
    end

    test "source retention cannot delete the target of an active restore", context do
      {:ok, restore} = request(context, Ecto.UUID.generate())

      assert_raise Postgrex.Error, fn ->
        Repo.transaction(fn -> Repo.delete!(context.snapshot) end)
      end

      assert Repo.get!(ProjectSnapshotRestore, restore.id).project_snapshot_id == context.snapshot.id
      assert Repo.get!(Storyarn.Projects.Versioning.ProjectSnapshot, context.snapshot.id)
    end
  end

  describe "perform_project_snapshot_restore/3" do
    test "publishes durable content invalidations after completion and on completed replay", context do
      {:ok, restore} = request(context, Ecto.UUID.generate())
      job = executing_job!(restore, 1)
      subscribe_restore_invalidations(context.project.id)

      result = %{
        result_digest: String.duplicate("f", 64),
        reservation_id: nil,
        content_replaced: true,
        replaced_sheet_ids: [11, 12],
        replaced_flow_ids: [21],
        replaced_scene_ids: [31]
      }

      assert {:ok, completed} =
               Versioning.perform_project_snapshot_restore(restore.id, 1,
                 job_id: job.id,
                 attempt: 1,
                 max_attempts: 5,
                 executor: fn _claimed, _opts -> {:ok, result} end
               )

      assert completed.status == "completed"
      assert_restore_invalidation_events()

      parent = self()

      assert {:ok, replayed} =
               Versioning.perform_project_snapshot_restore(restore.id, 1,
                 job_id: job.id,
                 attempt: 1,
                 max_attempts: 5,
                 executor: fn _claimed, _opts ->
                   send(parent, :completed_replay_invoked_executor)
                   {:error, :unexpected_completed_replay}
                 end
               )

      assert replayed.id == completed.id
      refute_receive :completed_replay_invoked_executor
      assert_restore_invalidation_events()
    end

    test "never publishes content invalidations for a failed execution", context do
      {:ok, restore} = request(context, Ecto.UUID.generate())
      job = executing_job!(restore, 1)
      subscribe_restore_invalidations(context.project.id)

      assert {:discard, :injected_restore_failure} =
               Versioning.perform_project_snapshot_restore(restore.id, 1,
                 job_id: job.id,
                 attempt: 1,
                 max_attempts: 1,
                 executor: fn _claimed, _opts -> {:error, :injected_restore_failure} end
               )

      refute_receive {:dashboard_invalidate, :all}, 20
      refute_receive {:remote_change, :tree_changed, %{}}, 20
      refute_receive {:remote_change, :asset_library_restored, %{}}, 20
      refute_receive {:entities_deleted, _type, _ids}, 20
      refute_receive {:languages_changed, nil}, 20
    end

    test "never terminalizes any delivery family while bound reservation settlement fails" do
      cases = [
        {:reauthorization,
         fn context ->
           Repo.update_all(
             from(membership in Storyarn.Projects.ProjectMembership,
               where:
                 membership.project_id == ^context.project.id and
                   membership.user_id == ^context.user.id
             ),
             set: [role: "viewer"]
           )

           Repo.update_all(
             from(membership in Storyarn.Workspaces.WorkspaceMembership,
               where:
                 membership.workspace_id == ^context.project.workspace_id and
                   membership.user_id == ^context.user.id
             ),
             set: [role: "viewer"]
           )
         end, fn -> {:error, :must_not_execute} end},
        {:target_revalidation,
         fn context ->
           context.snapshot
           |> Ecto.Changeset.change(integrity_state: "corrupt")
           |> Repo.update!()
         end, fn -> {:error, :must_not_execute} end},
        {:final_retry, fn _context -> :ok end, fn -> {:retry, :temporary_restore_failure} end},
        {:returned_error, fn _context -> :ok end, fn -> {:error, :restore_failed} end},
        {:raised, fn _context -> :ok end, fn -> raise "restore exploded" end},
        {:invalid_result, fn _context -> :ok end, fn -> :invalid end}
      ]

      Enum.each(cases, fn {family, invalidate, executor_result} ->
        context = restore_context!()
        {restore, job, reservation} = claimed_restore_with_bound_reservation!(context)
        invalidate.(context)
        parent = self()

        assert {:snooze, 30} =
                 Versioning.perform_project_snapshot_restore(restore.id, 1,
                   job_id: job.id,
                   attempt: 1,
                   max_attempts: 1,
                   executor: fn _claimed, _opts -> executor_result.() end,
                   settle_bound_reservation: fn settling_restore, _opts ->
                     send(parent, {:settlement_attempted, family, settling_restore.id})
                     {:error, :storage_settlement_unavailable}
                   end
                 )

        assert_receive {:settlement_attempted, ^family, restore_id}
        assert restore_id == restore.id
        assert Repo.get!(ProjectSnapshotRestore, restore.id).status == "running"
        assert Repo.get!(StorageReservation, reservation.id).status == "active"
      end)
    end

    test "keeps retries non-terminal and fences duplicate delivery after completion", context do
      {:ok, restore} = request(context, Ecto.UUID.generate())
      job = executing_job!(restore, 1)

      assert {:retry, :temporary_restore_failure} =
               Versioning.perform_project_snapshot_restore(restore.id, 1,
                 job_id: job.id,
                 attempt: 1,
                 max_attempts: 3,
                 executor: fn claimed, opts ->
                   assert claimed.generation == 2
                   assert opts[:job_id] == job.id
                   {:retry, :temporary_restore_failure}
                 end
               )

      retrying = Repo.get!(ProjectSnapshotRestore, restore.id)
      assert retrying.status == "retrying"
      assert retrying.phase == "retrying"
      assert retrying.generation == 2

      executing_job!(retrying, 2)

      assert {:ok, completed} =
               Versioning.perform_project_snapshot_restore(restore.id, 1,
                 job_id: job.id,
                 attempt: 2,
                 max_attempts: 3,
                 executor: fn claimed, _opts ->
                   assert claimed.generation == 2
                   {:ok, %{result_digest: String.duplicate("c", 64), reservation_id: nil}}
                 end
               )

      assert completed.status == "completed"
      assert completed.generation == 3

      parent = self()

      assert {:ok, replayed} =
               Versioning.perform_project_snapshot_restore(restore.id, 1,
                 job_id: job.id,
                 attempt: 2,
                 max_attempts: 3,
                 executor: fn _claimed, _opts ->
                   send(parent, :duplicate_executor_called)
                   {:error, :must_not_run}
                 end
               )

      assert replayed.id == completed.id
      refute_receive :duplicate_executor_called
    end

    test "terminalizes executor errors with a bounded diagnostic", context do
      {:ok, restore} = request(context, Ecto.UUID.generate())
      job = executing_job!(restore, 1)

      assert {:discard, :injected_project_snapshot_restore_failure} =
               Versioning.perform_project_snapshot_restore(restore.id, 1,
                 job_id: job.id,
                 attempt: 1,
                 max_attempts: 5,
                 executor: fn _claimed, _opts ->
                   {:error, :injected_project_snapshot_restore_failure}
                 end
               )

      failed = Repo.get!(ProjectSnapshotRestore, restore.id)
      assert failed.status == "failed"
      assert failed.failure_code == "injected_project_snapshot_restore_failure"
      assert failed.failure_message == "The project snapshot restore could not be completed."
    end
  end

  describe "abandoned restore delivery recovery" do
    test "includes queued restores in the high watermark without skipping a lower abandoned id", context do
      {:ok, first} = request(context, Ecto.UUID.generate())
      first_job = Repo.get!(Oban.Job, first.oban_job_id)
      cancel_job!(first_job)

      second_context = restore_context!()
      {:ok, second} = request(second_context, Ecto.UUID.generate())

      assert Versioning.project_snapshot_restore_delivery_recovery_high_watermark() == second.id

      assert [candidate] =
               Versioning.list_abandoned_project_snapshot_restore_deliveries(
                 after_id: 0,
                 through_id: second.id,
                 limit: 1
               )

      assert candidate.restore_id == first.id
      assert candidate.restore_status == "queued"
      assert candidate.job_state == "cancelled"
    end

    test "terminalizes a queued restore whose job was pruned before claim", context do
      {:ok, restore} = request(context, Ecto.UUID.generate())
      Repo.delete!(Repo.get!(Oban.Job, restore.oban_job_id))

      assert %ProjectSnapshotRestore{oban_job_id: nil, status: "queued"} =
               Repo.get!(ProjectSnapshotRestore, restore.id)

      assert [candidate] = candidates_for(restore)
      assert candidate.job_id == nil
      assert candidate.reservation_id == nil

      assert {:ok, :recovered} =
               Versioning.recover_abandoned_project_snapshot_restore_delivery(candidate)

      failed = Repo.get!(ProjectSnapshotRestore, restore.id)
      assert failed.status == "failed"
      assert failed.failure_code == "project_snapshot_restore_delivery_abandoned"
      assert failed.attempt == 1

      assert {:ok, replacement} = request(context, Ecto.UUID.generate())
      assert replacement.status == "queued"
    end

    test "releases a no-write reservation before terminalizing a discarded delivery", context do
      {restore, job, reservation} = claimed_restore_with_bound_reservation!(context, 321)
      discard_job!(job)

      assert Billing.workspace_storage_usage(restore.workspace_id).active_reservations.bytes >= 321
      assert [candidate] = candidates_for(restore)

      assert {:ok, :recovered} =
               Versioning.recover_abandoned_project_snapshot_restore_delivery(candidate)

      released = Repo.get!(StorageReservation, reservation.id)
      assert released.status == "released"
      assert released.cleanup_status == "not_required"
      assert released.release_reason == "snapshot_restore_failed"
      assert Repo.get!(ProjectSnapshotRestore, restore.id).status == "failed"
      assert Billing.workspace_storage_usage(restore.workspace_id).active_reservations.bytes == 0
    end

    test "hands started cleanup ownership off durably before terminalizing", context do
      {restore, job, reservation} = claimed_restore_with_bound_reservation!(context, 80)
      cleanup_key = reservation.storage_namespace <> "/blobs/" <> String.duplicate("a", 64)

      assert {:ok, started} =
               Billing.mark_storage_reservation_started(
                 reservation.id,
                 reservation.lease_token,
                 reservation.generation,
                 %{temporary_prefix: reservation.storage_namespace, storage_keys: [cleanup_key]}
               )

      discard_job!(job)
      assert [candidate] = candidates_for(restore)
      assert candidate.reservation_generation == started.generation
      assert candidate.reservation_storage_started_at == started.storage_started_at

      assert {:ok, :recovered} =
               Versioning.recover_abandoned_project_snapshot_restore_delivery(candidate)

      released = Repo.get!(StorageReservation, reservation.id)
      assert released.status == "released"
      assert released.cleanup_status == "owned"
      assert "storage_cleanup_request:" <> request_id = released.cleanup_reference
      assert {cleanup_request_id, ""} = Integer.parse(request_id)
      assert Repo.get!(StorageCleanupRequest, cleanup_request_id).storage_keys == [cleanup_key]
      assert Repo.get!(ProjectSnapshotRestore, restore.id).status == "failed"
    end

    test "an early preflight exception settles an already-started bound reservation", context do
      {restore, _job, reservation} = claimed_restore_with_bound_reservation!(context, 80)
      cleanup_key = reservation.storage_namespace <> "/blobs/" <> String.duplicate("b", 64)

      assert {:ok, _started} =
               Billing.mark_storage_reservation_started(
                 reservation.id,
                 reservation.lease_token,
                 reservation.generation,
                 %{temporary_prefix: reservation.storage_namespace, storage_keys: [cleanup_key]}
               )

      assert {:retry, {:project_snapshot_restore_exception, message}} =
               ProjectSnapshotRestoreExecutor.execute(restore,
                 archive_reader: RaisingArchiveReader
               )

      assert message =~ "reader exploded before compensation context"

      released = Repo.get!(StorageReservation, reservation.id)
      assert released.status == "released"
      assert released.cleanup_status == "owned"
      assert "storage_cleanup_request:" <> request_id = released.cleanup_reference
      assert {cleanup_request_id, ""} = Integer.parse(request_id)
      assert Repo.get!(StorageCleanupRequest, cleanup_request_id).storage_keys == [cleanup_key]
    end

    test "stale executing delivery is fenced by the session lock, then cancelled and recovered", context do
      old = stale_delivery_time()
      {claimed, job} = stale_claimed_restore!(context, old)

      staged =
        claimed
        |> ProjectSnapshotRestore.phase_changeset("staging", old)
        |> Repo.update!()

      {:ok, {restore, reservation}} =
        Versioning.reserve_and_bind_project_snapshot_restore(
          staged.id,
          staged.generation,
          %{restore_reservation_attrs(staged) | reserved_bytes: 80}
        )

      cleanup_key = reservation.storage_namespace <> "/blobs/" <> String.duplicate("c", 64)

      assert {:ok, _started} =
               Billing.mark_storage_reservation_started(
                 reservation.id,
                 reservation.lease_token,
                 reservation.generation,
                 %{temporary_prefix: reservation.storage_namespace, storage_keys: [cleanup_key]}
               )

      assert [candidate] = candidates_for(claimed)
      parent = self()

      owner =
        Task.async(fn ->
          Sandbox.unboxed_run(Repo, fn ->
            StorageKeyLock.with_session_lock("project-snapshot-restore:#{restore.project_id}", fn ->
              send(parent, :restore_lock_held)

              receive do
                :release_restore_lock -> :ok
              end
            end)
          end)
        end)

      assert_receive :restore_lock_held

      assert {:error, :project_snapshot_restore_delivery_busy} =
               Sandbox.unboxed_run(Repo, fn ->
                 Versioning.recover_abandoned_project_snapshot_restore_delivery(candidate)
               end)

      assert Repo.get!(ProjectSnapshotRestore, restore.id).status == "running"
      assert Repo.get!(Oban.Job, job.id).state == "executing"
      assert Repo.get!(StorageReservation, reservation.id).status == "active"

      send(owner.pid, :release_restore_lock)
      assert :ok = Task.await(owner)

      assert {:ok, :recovered} =
               Versioning.recover_abandoned_project_snapshot_restore_delivery(candidate)

      assert Repo.get!(ProjectSnapshotRestore, restore.id).status == "failed"
      assert Repo.get!(Oban.Job, job.id).state == "cancelled"

      released = Repo.get!(StorageReservation, reservation.id)
      assert released.status == "released"
      assert released.cleanup_status == "owned"
      assert "storage_cleanup_request:" <> request_id = released.cleanup_reference
      assert {cleanup_request_id, ""} = Integer.parse(request_id)
      assert Repo.get!(StorageCleanupRequest, cleanup_request_id).storage_keys == [cleanup_key]
    end

    test "changed and completed candidates are stale and never mutate newer state", context do
      {:ok, restore} = request(context, Ecto.UUID.generate())
      job = Repo.get!(Oban.Job, restore.oban_job_id)
      cancel_job!(job)
      assert [candidate] = candidates_for(restore)

      job
      |> Ecto.Changeset.change(
        state: "completed",
        cancelled_at: nil,
        completed_at: %{TimeHelpers.now() | microsecond: {0, 6}}
      )
      |> Repo.update!()

      assert {:ok, :stale} =
               Versioning.recover_abandoned_project_snapshot_restore_delivery(candidate)

      assert Repo.get!(ProjectSnapshotRestore, restore.id).status == "queued"

      completed_candidate = hd(candidates_for(restore))

      restore
      |> ProjectSnapshotRestore.abandoned_changeset(
        %{failure_code: "operator_completed", failure_message: "Completed elsewhere", failure_details: %{}},
        TimeHelpers.now()
      )
      |> Repo.update!()

      assert {:ok, :stale} =
               Versioning.recover_abandoned_project_snapshot_restore_delivery(completed_candidate)
    end

    test "a candidate completed concurrently remains completed", context do
      {:ok, restore} = request(context, Ecto.UUID.generate())
      job = executing_job!(restore, 1)

      assert {:ok, {:claimed, claimed}} =
               Versioning.claim_project_snapshot_restore(restore.id, restore.generation,
                 job_id: job.id,
                 attempt: 1
               )

      discard_job!(job)
      assert [candidate] = candidates_for(claimed)

      result = %{result_digest: String.duplicate("e", 64), reservation_id: nil}

      assert {:ok, completed} =
               Versioning.complete_project_snapshot_restore(claimed.id, claimed.generation, result)

      assert {:ok, :stale} =
               Versioning.recover_abandoned_project_snapshot_restore_delivery(candidate)

      persisted = Repo.get!(ProjectSnapshotRestore, completed.id)
      assert persisted.status == "completed"
      assert persisted.result_digest == result.result_digest
      assert Repo.get!(Oban.Job, job.id).state == "discarded"
    end

    test "retention schedules a bounded continuation without skipping an active higher id", context do
      {:ok, abandoned} = request(context, Ecto.UUID.generate())
      cancel_job!(Repo.get!(Oban.Job, abandoned.oban_job_id))

      higher_context = restore_context!()
      {:ok, higher} = request(higher_context, Ecto.UUID.generate())
      assert abandoned.id < higher.id

      assert :ok = ProjectSnapshotRetentionWorker.perform(%Oban.Job{args: %{}})

      assert Repo.get!(ProjectSnapshotRestore, abandoned.id).status == "failed"
      assert Repo.get!(ProjectSnapshotRestore, higher.id).status == "queued"

      assert [%Oban.Job{args: args}] =
               [worker: ProjectSnapshotRetentionWorker]
               |> all_enqueued()
               |> Enum.filter(&Map.has_key?(&1.args, "restore_recovery_after_id"))

      assert args["restore_recovery_after_id"] == abandoned.id
      assert args["restore_recovery_through_id"] == higher.id
    end
  end

  defp request(context, idempotency_key) do
    Versioning.request_project_snapshot_restore(
      context.scope,
      context.project,
      context.snapshot,
      %{idempotency_key: idempotency_key}
    )
  end

  defp subscribe_restore_invalidations(project_id) do
    :ok = Collaboration.subscribe_dashboard(project_id)
    :ok = Collaboration.subscribe_changes({:project, project_id})
    :ok = Collaboration.subscribe_changes({:assets, project_id})
    :ok = Phoenix.PubSub.subscribe(Storyarn.PubSub, "project:#{project_id}:shell")
  end

  defp assert_restore_invalidation_events do
    assert_receive {:dashboard_invalidate, :all}
    assert_receive {:remote_change, :tree_changed, %{}}
    assert_receive {:remote_change, :asset_library_restored, %{}}
    assert_receive {:entities_deleted, :sheet, [11, 12]}
    assert_receive {:entities_deleted, :flow, [21]}
    assert_receive {:entities_deleted, :scene, [31]}
    assert_receive {:languages_changed, nil}
    assert_receive {:project_restored, _restore_id}
  end

  defp executing_job!(restore, attempt) do
    restore.oban_job_id
    |> then(&Repo.get!(Oban.Job, &1))
    |> Ecto.Changeset.change(
      state: "executing",
      attempt: attempt,
      attempted_at: %{TimeHelpers.now() | microsecond: {0, 6}}
    )
    |> Repo.update!()
  end

  defp restore_reservation_attrs(restore) do
    lease_token = Ecto.UUID.generate()

    %{
      workspace_id: restore.workspace_id,
      project_id: restore.project_id,
      project_snapshot_id: restore.project_snapshot_id,
      idempotency_key: "project-snapshot-restore:#{restore.id}:lease:#{lease_token}",
      kind: "restore_staging",
      reserved_bytes: 0,
      lease_token: lease_token
    }
  end

  defp restore_context! do
    user = user_fixture()
    project = project_fixture(user)

    %{
      user: user,
      scope: user_scope_fixture(user),
      project: project,
      snapshot: full_project_snapshot_fixture(project)
    }
  end

  defp claimed_restore_with_bound_reservation!(context, reserved_bytes \\ 0) do
    {:ok, restore} = request(context, Ecto.UUID.generate())
    job = executing_job!(restore, 1)

    {:ok, {:claimed, claimed}} =
      Versioning.claim_project_snapshot_restore(restore.id, 1,
        job_id: job.id,
        attempt: 1
      )

    {:ok, staged} =
      Versioning.advance_project_snapshot_restore_phase(claimed.id, claimed.generation, "staging")

    {:ok, {bound, reservation}} =
      Versioning.reserve_and_bind_project_snapshot_restore(
        staged.id,
        staged.generation,
        %{restore_reservation_attrs(staged) | reserved_bytes: reserved_bytes}
      )

    {bound, job, reservation}
  end

  defp candidates_for(restore) do
    Versioning.list_abandoned_project_snapshot_restore_deliveries(
      after_id: max(restore.id - 1, 0),
      through_id: restore.id,
      limit: 1
    )
  end

  defp cancel_job!(job) do
    job
    |> Ecto.Changeset.change(
      state: "cancelled",
      cancelled_at: %{TimeHelpers.now() | microsecond: {0, 6}}
    )
    |> Repo.update!()
  end

  defp discard_job!(job) do
    job
    |> Ecto.Changeset.change(
      state: "discarded",
      discarded_at: %{TimeHelpers.now() | microsecond: {0, 6}}
    )
    |> Repo.update!()
  end

  defp stale_delivery_time do
    TimeHelpers.now()
    |> DateTime.add(-Versioning.project_snapshot_restore_delivery_recovery_quarantine_seconds() - 5, :second)
    |> DateTime.truncate(:second)
  end

  defp stale_claimed_restore!(context, old) do
    restore =
      %ProjectSnapshotRestore{}
      |> ProjectSnapshotRestore.request_changeset(%{
        workspace_id: context.project.workspace_id,
        project_id: context.project.id,
        project_snapshot_id: context.snapshot.id,
        requested_by_id: context.user.id,
        idempotency_key: Ecto.UUID.generate(),
        snapshot_lifecycle_generation: context.snapshot.lifecycle_generation,
        snapshot_accounting_generation: context.snapshot.accounting_generation,
        archive_storage_key: context.snapshot.archive_storage_key,
        archive_size_bytes: context.snapshot.archive_size_bytes,
        archive_checksum: context.snapshot.archive_checksum,
        manifest_storage_key: context.snapshot.manifest_storage_key,
        manifest_size_bytes: context.snapshot.manifest_size_bytes,
        manifest_checksum: context.snapshot.manifest_checksum,
        requested_at: old
      })
      |> Repo.insert!()

    job =
      %{restore_id: restore.id, generation: restore.generation}
      |> RestoreProjectSnapshotWorker.new(queue: :snapshot_restores)
      |> Oban.insert!()
      |> Ecto.Changeset.change(
        state: "executing",
        attempt: 1,
        attempted_at: %{old | microsecond: {0, 6}}
      )
      |> Repo.update!()

    claimed =
      restore
      |> ProjectSnapshotRestore.bind_job_changeset(job.id)
      |> Repo.update!()
      |> ProjectSnapshotRestore.claim_changeset(1, old)
      |> Repo.update!()

    {claimed, job}
  end
end
