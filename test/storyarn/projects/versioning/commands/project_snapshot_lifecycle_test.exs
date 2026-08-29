defmodule Storyarn.Projects.Versioning.ProjectSnapshotLifecycleTest do
  use Storyarn.DataCase, async: false
  use Oban.Testing, repo: Storyarn.Repo

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Commercial.Billing
  alias Storyarn.Commercial.Billing.StorageReservation
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Projects
  alias Storyarn.Projects.Assets.Storage
  alias Storyarn.Projects.Assets.StorageCleanupRequest
  alias Storyarn.Projects.Assets.StorageCompensation
  alias Storyarn.Projects.Versioning
  alias Storyarn.Projects.Versioning.ProjectSnapshot
  alias Storyarn.Projects.Versioning.ProjectSnapshotBuild
  alias Storyarn.Projects.Versioning.ProjectSnapshotLifecycle
  alias Storyarn.Projects.Versioning.ProjectSnapshotRestore
  alias Storyarn.Projects.Versioning.SnapshotArchiveStorage
  alias Storyarn.Projects.Versioning.SnapshotCleanupIntent
  alias Storyarn.Projects.Versioning.SnapshotObjectFormat
  alias Storyarn.Projects.Versioning.SnapshotObjectPublicationClaim
  alias Storyarn.Workers.BuildProjectSnapshotWorker
  alias Storyarn.Workers.ProjectSnapshotRetentionWorker
  alias Storyarn.Workspaces

  describe "delete_project_snapshot/3" do
    test "settles an expired download lease and deletes without waiting for the reaper" do
      user = user_fixture()
      project = project_fixture(user)
      ready = create_ready_snapshot(user, project)

      assert {:ok, lease} =
               Billing.acquire_snapshot_export_lease(%{
                 workspace_id: project.workspace_id,
                 project_id: project.id,
                 project_snapshot_id: ready.id
               })

      now = database_clock_now()

      lease
      |> Ecto.Changeset.change(
        accounting_measured_at: DateTime.add(now, -120, :second),
        expires_at: DateTime.add(now, -60, :second)
      )
      |> Repo.update!()

      Phoenix.PubSub.subscribe(Storyarn.PubSub, "project_snapshots:#{project.id}")

      assert {:ok, intent} =
               Versioning.delete_project_snapshot(user_scope_fixture(user), project, ready.id)

      assert intent.reason == "user_delete"
      refute Repo.get(ProjectSnapshot, ready.id)

      assert %StorageReservation{
               status: "released",
               release_reason: "expired_snapshot_export_lease",
               cleanup_status: "not_required",
               cleanup_reference: cleanup_reference
             } = Repo.get!(StorageReservation, lease.id)

      assert cleanup_reference == "storage_not_started:#{lease.storage_namespace}"
      assert_receive {:project_snapshot_updated, snapshot_id}
      assert snapshot_id == ready.id
      refute_receive {:project_snapshot_updated, _snapshot_id}
    end

    test "keeps an unexpired download lease as an active deletion fence" do
      user = user_fixture()
      project = project_fixture(user)
      ready = create_ready_snapshot(user, project)

      assert {:ok, lease} =
               Billing.acquire_snapshot_export_lease(%{
                 workspace_id: project.workspace_id,
                 project_id: project.id,
                 project_snapshot_id: ready.id
               })

      Phoenix.PubSub.subscribe(Storyarn.PubSub, "project_snapshots:#{project.id}")

      assert {:error, :snapshot_active_operation_blocks_deletion} =
               Versioning.delete_project_snapshot(user_scope_fixture(user), project, ready.id)

      assert Repo.get!(ProjectSnapshot, ready.id).lifecycle_state == "ready"
      assert %StorageReservation{status: "active", generation: generation} = Repo.get!(StorageReservation, lease.id)
      assert generation == lease.generation
      refute Repo.exists?(SnapshotCleanupIntent)
      refute_receive {:project_snapshot_updated, _snapshot_id}
    end

    test "keeps a queued exact restore without a reservation as an active deletion fence" do
      user = user_fixture()
      project = project_fixture(user)
      ready = create_ready_snapshot(user, project)

      assert {:ok, restore} =
               Versioning.request_project_snapshot_restore(user_scope_fixture(user), project, ready.id, %{
                 idempotency_key: Ecto.UUID.generate()
               })

      assert %ProjectSnapshotRestore{status: "queued", storage_reservation_id: nil} = restore

      assert {:error, :snapshot_active_operation_blocks_deletion} =
               Versioning.delete_project_snapshot(user_scope_fixture(user), project, ready.id)

      assert Repo.get!(ProjectSnapshot, ready.id).lifecycle_state == "ready"
      assert Repo.get!(ProjectSnapshotRestore, restore.id).project_snapshot_id == ready.id
      refute Repo.exists?(SnapshotCleanupIntent)
    end

    test "records exact immutable ownership before dropping quota and cleans idempotently" do
      user = user_fixture()
      project = project_fixture(user)
      ready = create_ready_snapshot(user, project)
      expected_bytes = ready.accounted_size_bytes

      assert Billing.workspace_storage_usage(project.workspace_id).full_snapshots == %{
               bytes: expected_bytes,
               count: 1
             }

      assert {:ok, intent} =
               Versioning.delete_project_snapshot(user_scope_fixture(user), project, ready.id)

      refute Repo.get(ProjectSnapshot, ready.id)
      assert intent.project_snapshot_id_snapshot == ready.id
      assert intent.deletion_generation == ready.lifecycle_generation + 1
      assert intent.reason == "user_delete"
      assert intent.authority_kind == "user"
      assert intent.authority_actor_id == user.id
      assert intent.storage_keys == Enum.uniq(intent.storage_keys)
      assert intent.object_count == length(intent.storage_keys)
      assert ready.manifest_storage_key in intent.storage_keys
      assert ready.archive_storage_key in intent.storage_keys
      assert Enum.any?(intent.storage_keys, &String.contains?(&1, "/staging/"))
      assert {:ok, provider_namespace_fingerprint} = Storage.namespace_fingerprint()
      assert intent.provider_namespace_fingerprint == provider_namespace_fingerprint

      assert %StorageCleanupRequest{
               owner_kind: "snapshot_lifecycle",
               storage_keys: request_storage_keys,
               provider_namespace_fingerprint: ^provider_namespace_fingerprint
             } = Repo.get!(StorageCleanupRequest, intent.cleanup_request_id)

      assert request_storage_keys == intent.storage_keys
      assert Billing.workspace_storage_usage(project.workspace_id).full_snapshots == %{bytes: 0, count: 0}

      assert {:ok, {:deferred, seconds}} = Versioning.process_project_snapshot_cleanup_intent(intent.id)
      assert seconds == Storage.multipart_cleanup_quiescence_seconds()
      expire_multipart_quiescence!(intent.cleanup_request_id)

      assert {:ok, :completed} = Versioning.process_project_snapshot_cleanup_intent(intent.id)
      assert {:error, _reason} = Storage.stat(ready.manifest_storage_key)
      assert {:error, _reason} = Storage.stat(ready.archive_storage_key)
      assert {:ok, :already_completed} = Versioning.process_project_snapshot_cleanup_intent(intent.id)
    end

    test "deletes a v2 request cancelled before capture with an empty canonical provider scope" do
      user = user_fixture()
      project = project_fixture(user)
      scope = user_scope_fixture(user)
      assert {:ok, requested} = request_snapshot(user, project)
      assert {:ok, cancelled} = Versioning.cancel_project_snapshot(scope, project, requested.id)

      assert cancelled.lifecycle_state == "cancelled"
      assert is_nil(cancelled.capture_digest)
      assert is_nil(cancelled.archive_size_bytes)
      assert is_nil(cancelled.manifest_size_bytes)

      assert {:ok, expected_scope} =
               SnapshotArchiveStorage.cleanup_scope(cancelled.project_id, cancelled.object_prefix)

      Enum.each(expected_scope.storage_keys, fn storage_key ->
        assert {:error, :enoent} = Storage.stat(storage_key)
      end)

      assert {:ok, intent} = Versioning.delete_project_snapshot(scope, project, cancelled.id)

      assert intent.estimated_cleanup_bytes == 0
      assert intent.storage_keys == expected_scope.storage_keys
      assert intent.object_count == 4
      refute Repo.get(ProjectSnapshot, cancelled.id)

      Enum.each(intent.storage_keys, fn storage_key ->
        assert {:error, :enoent} = Storage.stat(storage_key)
      end)
    end

    test "restarts lifecycle quiescence when delete observes a multipart upload after empty inventory" do
      user = user_fixture()
      project = project_fixture(user)
      ready = create_ready_snapshot(user, project)
      assert {:ok, intent} = Versioning.delete_project_snapshot(user_scope_fixture(user), project, ready.id)

      assert {:ok, {:deferred, _seconds}} = Versioning.process_project_snapshot_cleanup_intent(intent.id)
      expire_multipart_quiescence!(intent.cleanup_request_id)

      before_reset = Repo.get!(StorageCleanupRequest, intent.cleanup_request_id)

      assert {:ok, {:deferred, _seconds}} =
               Versioning.process_project_snapshot_cleanup_intent(intent.id,
                 delete_fun: fn _keys -> {:ok, %{aborted_count: 1}} end
               )

      after_reset = Repo.get!(StorageCleanupRequest, intent.cleanup_request_id)
      refute after_reset.multipart_quiescence_started_at == before_reset.multipart_quiescence_started_at
      refute after_reset.multipart_quiescence_not_before == before_reset.multipart_quiescence_not_before

      assert Repo.get!(SnapshotCleanupIntent, intent.id).remaining_storage_keys == intent.storage_keys

      expire_multipart_quiescence!(intent.cleanup_request_id)
      assert {:ok, :completed} = Versioning.process_project_snapshot_cleanup_intent(intent.id)
    end

    test "keeps deletion available after runtime manifest limits are lowered" do
      user = user_fixture()
      project = project_fixture(user)
      ready = create_ready_snapshot(user, project)
      original_limits = Application.get_env(:storyarn, SnapshotObjectFormat, [])

      Application.put_env(
        :storyarn,
        SnapshotObjectFormat,
        Keyword.put(original_limits, :max_manifest_bytes, 1)
      )

      on_exit(fn -> Application.put_env(:storyarn, SnapshotObjectFormat, original_limits) end)

      assert {:ok, intent} =
               Versioning.delete_project_snapshot(user_scope_fixture(user), project, ready.id)

      assert intent.project_snapshot_id_snapshot == ready.id
      refute Repo.get(ProjectSnapshot, ready.id)
    end

    test "rejects an actor without project management authority" do
      owner = user_fixture()
      outsider = user_fixture()
      project = project_fixture(owner)
      ready = create_ready_snapshot(owner, project)

      assert {:error, :unauthorized} =
               Versioning.delete_project_snapshot(user_scope_fixture(outsider), project, ready.id)

      assert Repo.get!(ProjectSnapshot, ready.id).lifecycle_state == "ready"
      refute Repo.exists?(SnapshotCleanupIntent)
    end

    test "keeps the full v2 inventory pending when one provider delete fails" do
      user = user_fixture()
      project = project_fixture(user)
      ready = create_ready_snapshot(user, project)
      assert {:ok, intent} = Versioning.delete_project_snapshot(user_scope_fixture(user), project, ready.id)
      failed_key = ready.manifest_storage_key

      delete_with_one_failure = fn keys ->
        successful = Enum.reject(keys, &(&1 == failed_key))
        assert :ok = StorageCompensation.delete_storage_keys(successful)
        {:error, [failed_key]}
      end

      assert {:error, :storage_provider_failure} =
               Versioning.process_project_snapshot_cleanup_intent(intent.id,
                 delete_fun: delete_with_one_failure
               )

      retrying = Repo.get!(SnapshotCleanupIntent, intent.id)
      assert retrying.status == "retrying"
      assert retrying.remaining_storage_keys == intent.storage_keys
      assert retrying.retry_count == 1

      assert {:ok, {:deferred, _seconds}} = Versioning.process_project_snapshot_cleanup_intent(intent.id)
      expire_multipart_quiescence!(intent.cleanup_request_id)

      assert {:ok, :completed} = Versioning.process_project_snapshot_cleanup_intent(intent.id)
      assert Repo.get!(SnapshotCleanupIntent, intent.id).remaining_storage_keys == []
    end

    test "preserves a terminal failure inventory for operator recovery" do
      user = user_fixture()
      project = project_fixture(user)
      ready = create_ready_snapshot(user, project)
      assert {:ok, intent} = Versioning.delete_project_snapshot(user_scope_fixture(user), project, ready.id)

      assert {:ok, :terminal} =
               Versioning.process_project_snapshot_cleanup_intent(intent.id,
                 delete_fun: fn keys -> {:error, keys} end,
                 final_attempt?: true
               )

      terminal = Repo.get!(SnapshotCleanupIntent, intent.id)
      assert terminal.status == "terminal"
      assert terminal.remaining_storage_keys == intent.storage_keys
      assert terminal.terminal_at

      assert %{
               backlog_count: 0,
               retry_count: 0,
               terminal_failures: 1,
               terminal_retry_count: 1,
               repeated_terminal_failures: 0
             } =
               Versioning.project_snapshot_cleanup_backlog()
    end

    test "operator replay safely reopens a terminal intent and emits one replay event" do
      user = user_fixture()
      project = project_fixture(user)
      ready = create_ready_snapshot(user, project)
      assert {:ok, intent} = Versioning.delete_project_snapshot(user_scope_fixture(user), project, ready.id)

      assert {:ok, :terminal} =
               Versioning.process_project_snapshot_cleanup_intent(intent.id,
                 delete_fun: fn keys -> {:error, keys} end,
                 final_attempt?: true
               )

      handler_id = "snapshot-cleanup-replay-#{System.unique_integer([:positive])}"
      parent = self()

      :ok =
        :telemetry.attach(
          handler_id,
          [:storyarn, :snapshot, :cleanup, :replay],
          fn event, measurements, metadata, pid -> send(pid, {event, measurements, metadata}) end,
          parent
        )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      assert {:ok, %SnapshotCleanupIntent{status: "retrying", terminal_at: nil}} =
               Versioning.replay_terminal_project_snapshot_cleanup(intent.id)

      replay_jobs =
        Storyarn.Workers.CleanupProjectSnapshotWorker
        |> then(&all_enqueued(worker: &1))
        |> Enum.filter(&is_binary(&1.args["replay_token"]))

      assert [%Oban.Job{args: replay_args, conflict?: false}] = replay_jobs

      assert is_binary(replay_args["replay_token"])

      assert_receive {
        [:storyarn, :snapshot, :cleanup, :replay],
        %{count: 1},
        %{status: :enqueued, reason: "user_delete"}
      }

      assert {:ok, :already_active} =
               Versioning.replay_terminal_project_snapshot_cleanup(intent.id)

      refute_receive {[:storyarn, :snapshot, :cleanup, :replay], _, _}
    end

    test "finding replay requires every exact terminal intent expectation" do
      user = user_fixture()
      project = project_fixture(user)
      ready = create_ready_snapshot(user, project)
      assert {:ok, intent} = Versioning.delete_project_snapshot(user_scope_fixture(user), project, ready.id)

      assert {:ok, :terminal} =
               Versioning.process_project_snapshot_cleanup_intent(intent.id,
                 delete_fun: fn keys -> {:error, keys} end,
                 final_attempt?: true
               )

      terminal = Repo.get!(SnapshotCleanupIntent, intent.id)
      expectations = cleanup_replay_expectations(terminal)

      Enum.each(Map.keys(expectations), fn field ->
        changed = Map.update!(expectations, field, &different_expectation/1)

        assert {:error, :snapshot_cleanup_intent_changed} =
                 ProjectSnapshotLifecycle.replay_terminal_cleanup_intent(intent.id, changed)

        assert Repo.get!(SnapshotCleanupIntent, intent.id).status == "terminal"
      end)

      assert {:error, :invalid_snapshot_cleanup_replay_expectations} =
               ProjectSnapshotLifecycle.replay_terminal_cleanup_intent(
                 intent.id,
                 Map.delete(expectations, :processing_generation)
               )

      assert {:ok, %SnapshotCleanupIntent{status: "retrying"}} =
               ProjectSnapshotLifecycle.replay_terminal_cleanup_intent(intent.id, expectations)

      assert {:ok, :already_active} =
               ProjectSnapshotLifecycle.replay_terminal_cleanup_intent(intent.id, expectations)

      for counter <- [:retry_count, :processing_generation] do
        regressed = Map.update!(expectations, counter, &(&1 + 1))

        assert {:error, :snapshot_cleanup_intent_changed} =
                 ProjectSnapshotLifecycle.replay_terminal_cleanup_intent(intent.id, regressed)
      end
    end

    @tag :tmp_dir
    test "provider namespace drift blocks cleanup and operator replay before deletion", %{tmp_dir: tmp_dir} do
      user = user_fixture()
      project = project_fixture(user)
      ready = create_ready_snapshot(user, project)
      assert {:ok, intent} = Versioning.delete_project_snapshot(user_scope_fixture(user), project, ready.id)

      use_alternate_storage_namespace!(tmp_dir)
      parent = self()

      assert {:ok, :terminal} =
               Versioning.process_project_snapshot_cleanup_intent(intent.id,
                 delete_fun: fn keys ->
                   send(parent, {:deleted, keys})
                   :ok
                 end,
                 final_attempt?: true
               )

      refute_receive {:deleted, _keys}

      assert %SnapshotCleanupIntent{
               status: "terminal",
               last_error_code: "provider_namespace_changed",
               remaining_storage_keys: remaining_storage_keys
             } = Repo.get!(SnapshotCleanupIntent, intent.id)

      assert remaining_storage_keys == intent.storage_keys

      assert {:error, :snapshot_cleanup_provider_namespace_changed} =
               ProjectSnapshotLifecycle.replay_terminal_cleanup_intent(intent.id)

      assert Repo.get!(SnapshotCleanupIntent, intent.id).status == "terminal"
    end

    test "cleanup request provider namespace cannot drift from its intent" do
      user = user_fixture()
      project = project_fixture(user)
      ready = create_ready_snapshot(user, project)
      assert {:ok, intent} = Versioning.delete_project_snapshot(user_scope_fixture(user), project, ready.id)

      assert {:ok, :terminal} =
               Versioning.process_project_snapshot_cleanup_intent(intent.id,
                 delete_fun: fn keys -> {:error, keys} end,
                 final_attempt?: true
               )

      different_fingerprint = different_expectation(intent.provider_namespace_fingerprint)

      request = Repo.get!(StorageCleanupRequest, intent.cleanup_request_id)

      assert_raise Postgrex.Error, ~r/snapshot cleanup provider namespace is immutable/, fn ->
        Repo.transaction(fn ->
          request
          |> Ecto.Changeset.change(provider_namespace_fingerprint: different_fingerprint)
          |> Repo.update!()
        end)
      end

      assert Repo.get!(SnapshotCleanupIntent, intent.id).status == "terminal"

      assert Repo.get!(StorageCleanupRequest, request.id).provider_namespace_fingerprint ==
               intent.provider_namespace_fingerprint
    end

    test "counts retries retained by repeatedly terminal cleanup intents" do
      user = user_fixture()
      project = project_fixture(user)
      ready = create_ready_snapshot(user, project)
      assert {:ok, intent} = Versioning.delete_project_snapshot(user_scope_fixture(user), project, ready.id)

      fail_all = fn keys -> {:error, keys} end

      assert {:ok, :terminal} =
               Versioning.process_project_snapshot_cleanup_intent(intent.id,
                 delete_fun: fail_all,
                 final_attempt?: true
               )

      assert {:ok, %SnapshotCleanupIntent{status: "retrying"}} =
               Versioning.replay_terminal_project_snapshot_cleanup(intent.id)

      assert {:ok, :terminal} =
               Versioning.process_project_snapshot_cleanup_intent(intent.id,
                 delete_fun: fail_all,
                 final_attempt?: true
               )

      assert %{
               backlog_count: 0,
               terminal_failures: 1,
               terminal_retry_count: 2,
               repeated_terminal_failures: 1
             } = Versioning.project_snapshot_cleanup_backlog()
    end

    test "emits an intent once even when a user deletion is redelivered" do
      user = user_fixture()
      project = project_fixture(user)
      ready = create_ready_snapshot(user, project)
      handler_id = "snapshot-cleanup-intent-#{System.unique_integer([:positive])}"
      parent = self()

      :ok =
        :telemetry.attach(
          handler_id,
          [:storyarn, :snapshot, :cleanup, :intent],
          fn event, measurements, metadata, pid -> send(pid, {event, measurements, metadata}) end,
          parent
        )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      scope = user_scope_fixture(user)
      assert {:ok, intent} = Versioning.delete_project_snapshot(scope, project, ready.id)
      assert {:ok, redelivered} = Versioning.delete_project_snapshot(scope, project, ready.id)
      assert redelivered.id == intent.id

      assert_receive {
        [:storyarn, :snapshot, :cleanup, :intent],
        %{count: 1, object_count: object_count},
        %{reason: "user_delete", authority_kind: "user"}
      }

      assert object_count == intent.object_count
      refute_receive {[:storyarn, :snapshot, :cleanup, :intent], _, _}
    end
  end

  describe "database lifecycle fence" do
    test "retry changeset rejects a terminal source state before reaching the database" do
      user = user_fixture()
      project = project_fixture(user)
      ready = create_ready_snapshot(user, project)

      changeset =
        ProjectSnapshot.retry_state_changeset(ready, %{
          lifecycle_state: "pending",
          state_updated_at: TimeHelpers.now()
        })

      refute changeset.valid?

      assert {"cannot retry from the current lifecycle state", []} in Keyword.get_values(
               changeset.errors,
               :lifecycle_state
             )
    end

    test "rejects a generation jump even when the lifecycle state is unchanged" do
      user = user_fixture()
      project = project_fixture(user)
      ready = create_ready_snapshot(user, project)

      assert_raise Postgrex.Error, ~r/project snapshot lifecycle transition is stale or invalid/, fn ->
        Repo.query!(
          "UPDATE project_snapshots SET lifecycle_generation = lifecycle_generation + 2 WHERE id = $1",
          [ready.id]
        )
      end
    end
  end

  describe "retention" do
    test "does not delete a queued exact restore target before staging reserves capacity" do
      user = user_fixture()
      project = project_fixture(user)
      ready = create_ready_snapshot(user, project)
      now = TimeHelpers.now()

      ready
      |> Ecto.Changeset.change(origin: "daily", expires_at: DateTime.add(now, -60, :second))
      |> Repo.update!()

      assert [candidate] = Versioning.list_project_snapshot_retention_candidates(now)

      assert {:ok, restore} =
               Versioning.request_project_snapshot_restore(user_scope_fixture(user), project, ready.id, %{
                 idempotency_key: Ecto.UUID.generate()
               })

      assert %ProjectSnapshotRestore{status: "queued", storage_reservation_id: nil} = restore

      assert {:error, :snapshot_active_operation_blocks_deletion} =
               Versioning.delete_project_snapshot_retention_candidate(candidate)

      assert Repo.get!(ProjectSnapshot, ready.id).lifecycle_state == "ready"
      assert Repo.get!(ProjectSnapshotRestore, restore.id).project_snapshot_id == ready.id
      refute Repo.exists?(SnapshotCleanupIntent)
    end

    test "revalidates every candidate fact under lock before deletion" do
      user = user_fixture()
      project = project_fixture(user)
      ready = create_ready_snapshot(user, project)
      now = TimeHelpers.now()
      expires_at = DateTime.add(now, -60, :second)

      ready
      |> Ecto.Changeset.change(origin: "daily", expires_at: expires_at)
      |> Repo.update!()

      assert [candidate] = Versioning.list_project_snapshot_retention_candidates(now)

      ProjectSnapshot
      |> Repo.get!(ready.id)
      |> Ecto.Changeset.change(expires_at: DateTime.add(now, 3_600, :second))
      |> Repo.update!()

      assert {:error, :retention_candidate_changed} =
               Versioning.delete_project_snapshot_retention_candidate(candidate)

      assert Repo.get!(ProjectSnapshot, ready.id).lifecycle_state == "ready"
      refute Repo.exists?(SnapshotCleanupIntent)
    end

    test "a future advisory clock cannot delete a snapshot before its retention deadline" do
      user = user_fixture()
      project = project_fixture(user)
      ready = create_ready_snapshot(user, project)
      now = TimeHelpers.now()
      expires_at = DateTime.add(now, 3_600, :second)

      ready
      |> Ecto.Changeset.change(origin: "daily", expires_at: expires_at)
      |> Repo.update!()

      assert [candidate] =
               Versioning.list_project_snapshot_retention_candidates(DateTime.add(expires_at, 1, :second))

      assert {:error, :retention_candidate_changed} =
               Versioning.delete_project_snapshot_retention_candidate(candidate)

      assert Repo.get!(ProjectSnapshot, ready.id).lifecycle_state == "ready"
      refute Repo.exists?(SnapshotCleanupIntent)
    end

    test "scheduled worker deletes through the lifecycle context and reports its batch" do
      user = user_fixture()
      project = project_fixture(user)
      ready = create_ready_snapshot(user, project)
      lease = expired_snapshot_export_lease!(project, ready)

      ready
      |> Ecto.Changeset.change(
        origin: "daily",
        expires_at: DateTime.add(TimeHelpers.now(), -60, :second)
      )
      |> Repo.update!()

      handler_id = "snapshot-retention-test-#{System.unique_integer([:positive])}"
      parent = self()
      Phoenix.PubSub.subscribe(Storyarn.PubSub, "project_snapshots:#{project.id}")

      :ok =
        :telemetry.attach_many(
          handler_id,
          [
            [:storyarn, :snapshot, :retention, :stop],
            [:storyarn, :snapshot, :cleanup, :intent]
          ],
          fn event, measurements, metadata, pid -> send(pid, {event, measurements, metadata}) end,
          parent
        )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      assert :ok = ProjectSnapshotRetentionWorker.perform(%Oban.Job{args: %{}})
      refute Repo.get(ProjectSnapshot, ready.id)

      assert %SnapshotCleanupIntent{reason: "retention"} =
               Repo.get_by!(SnapshotCleanupIntent, project_snapshot_id_snapshot: ready.id)

      assert %StorageReservation{
               status: "released",
               release_reason: "expired_snapshot_export_lease"
             } = Repo.get!(StorageReservation, lease.id)

      assert_receive {:project_snapshot_updated, snapshot_id}
      assert snapshot_id == ready.id

      assert_receive {
        [:storyarn, :snapshot, :cleanup, :intent],
        %{count: 1},
        %{reason: "retention", authority_kind: "system"}
      }

      assert_receive {
        [:storyarn, :snapshot, :retention, :stop],
        %{deleted_count: 1, failure_count: 0},
        %{status: :ok}
      }
    end

    test "candidate reads stop at the run high-watermark" do
      user = user_fixture()
      project = project_fixture(user)
      first = create_ready_snapshot(user, project)
      second = create_ready_snapshot(user, project)
      expires_at = DateTime.add(TimeHelpers.now(), -60, :second)

      Enum.each([first, second], fn snapshot ->
        snapshot
        |> Ecto.Changeset.change(origin: "daily", expires_at: expires_at)
        |> Repo.update!()
      end)

      assert [candidate] =
               Versioning.list_project_snapshot_retention_candidates(TimeHelpers.now(),
                 through_id: first.id
               )

      assert candidate.snapshot_id == first.id
    end

    test "continuation preserves an exhausted stream cursor and the starting high-watermark" do
      user = user_fixture()
      project = project_fixture(user)
      ready = create_ready_snapshot(user, project)
      expires_at = DateTime.add(TimeHelpers.now(), -60, :second)

      ready =
        ready
        |> Ecto.Changeset.change(origin: "daily", expires_at: expires_at)
        |> Repo.update!()

      insert_retention_snapshot_clones!(ready, 50, expires_at)
      through_id = Versioning.project_snapshot_lifecycle_high_watermark()

      assert :ok =
               ProjectSnapshotRetentionWorker.perform(%Oban.Job{
                 args: %{"expired_build_after_id" => 41}
               })

      assert [%Oban.Job{state: "available", args: continuation_args}] =
               all_enqueued(worker: ProjectSnapshotRetentionWorker)

      assert continuation_args["retention_after_id"] > 0
      assert continuation_args["expired_build_after_id"] == 41
      assert continuation_args["through_id"] == through_id
    end
  end

  describe "expired builds" do
    setup do
      set_stale_build_heartbeat_seconds(0)
      :ok
    end

    test "reclaims a crashed executing build only after its heartbeat and reservation are stale" do
      user = user_fixture()
      project = project_fixture(user)
      assert {:ok, snapshot} = request_snapshot(user, project)
      now = TimeHelpers.now()
      stale_at = DateTime.add(now, -16 * 60, :second)
      {_building, job, reservation} = stale_executing_build!(snapshot, stale_at)

      assert %{failure_count: 0, orphaned_count: 1, settled_count: 0} =
               Versioning.reconcile_stale_project_snapshot_builds()

      assert Repo.get!(Oban.Job, job.id).state == "discarded"
      assert Repo.get!(StorageReservation, reservation.id).status == "active"
      assert Versioning.list_expired_project_snapshot_build_candidates(now) == []

      discard_job!(job.id, stale_at)
      assert [candidate] = Versioning.list_expired_project_snapshot_build_candidates(now)

      assert {:ok, intent} =
               Versioning.delete_expired_project_snapshot_build_candidate(candidate)

      refute Repo.get(ProjectSnapshot, snapshot.id)

      assert intent.reason == "expired_build"
      assert intent.required_delete_passes == 2
      assert intent.completed_delete_passes == 0

      assert {:ok, {:deferred, defer_seconds}} =
               Versioning.process_project_snapshot_cleanup_intent(intent.id)

      assert defer_seconds == Storage.multipart_cleanup_quiescence_seconds()

      awaiting_quiescence = Repo.get!(SnapshotCleanupIntent, intent.id)
      assert awaiting_quiescence.completed_delete_passes == 0
      assert awaiting_quiescence.remaining_storage_keys == awaiting_quiescence.storage_keys
      expire_multipart_quiescence!(intent.cleanup_request_id)

      assert {:ok, {:deferred, defer_seconds}} =
               Versioning.process_project_snapshot_cleanup_intent(intent.id)

      quarantine_seconds = Versioning.project_snapshot_build_recovery_quarantine_seconds()
      assert defer_seconds in quarantine_seconds..(quarantine_seconds + 1)

      awaiting_verification = Repo.get!(SnapshotCleanupIntent, intent.id)
      assert awaiting_verification.status == "retrying"
      assert awaiting_verification.completed_delete_passes == 1
      assert awaiting_verification.remaining_storage_keys == awaiting_verification.storage_keys

      late_key = List.first(awaiting_verification.storage_keys)
      assert {:ok, _url} = Storage.upload(late_key, "late split-brain write", "application/json")

      assert {:ok, {:deferred, _seconds}} =
               Versioning.process_project_snapshot_cleanup_intent(intent.id)

      assert {:ok, _stat} = Storage.stat(late_key)

      assert Repo.get!(StorageReservation, reservation.id).status == "released"
    end

    test "returns a domain fence for an active restore on an expired build" do
      user = user_fixture()
      project = project_fixture(user)
      assert {:ok, snapshot} = request_snapshot(user, project)
      now = TimeHelpers.now()
      stale_at = DateTime.add(now, -16 * 60, :second)
      {_building, job, _reservation} = stale_executing_build!(snapshot, stale_at)

      assert %{failure_count: 0, orphaned_count: 1, settled_count: 0} =
               Versioning.reconcile_stale_project_snapshot_builds()

      discard_job!(job.id, stale_at)
      assert [candidate] = Versioning.list_expired_project_snapshot_build_candidates(now)

      restore = insert_active_restore!(user, project, Repo.get!(ProjectSnapshot, snapshot.id))

      assert {:error, :snapshot_active_operation_blocks_deletion} =
               Versioning.delete_expired_project_snapshot_build_candidate(candidate)

      assert Repo.get!(ProjectSnapshot, snapshot.id)
      assert Repo.get!(ProjectSnapshotRestore, restore.id).project_snapshot_id == snapshot.id
      refute Repo.exists?(SnapshotCleanupIntent)
    end

    test "reclaims a crashed cancelled build through the same durable cleanup path" do
      user = user_fixture()
      project = project_fixture(user)
      assert {:ok, snapshot} = request_snapshot(user, project)
      now = TimeHelpers.now()
      stale_at = DateTime.add(now, -16 * 60, :second)
      {building, job, reservation} = stale_executing_build!(snapshot, stale_at)
      {started, claim} = start_snapshot_storage!(project, building, reservation, now)

      started =
        started
        |> Ecto.Changeset.change(
          accounting_measured_at: DateTime.add(now, -120, :second),
          expires_at: DateTime.add(now, -60, :second)
        )
        |> Repo.update!()

      assert {:ok, cancellation_requested} =
               Versioning.cancel_project_snapshot(user_scope_fixture(user), project, snapshot.id)

      assert cancellation_requested.cancel_requested_at

      assert %{failure_count: 0, orphaned_count: 1, settled_count: 0} =
               Versioning.reconcile_stale_project_snapshot_builds()

      assert Repo.get!(Oban.Job, job.id).state == "discarded"
      assert Repo.get!(SnapshotObjectPublicationClaim, claim.object_prefix).status == "poisoned"
      assert Versioning.list_expired_project_snapshot_build_candidates(now) == []

      discard_job!(job.id, stale_at)
      assert [candidate] = Versioning.list_expired_project_snapshot_build_candidates(now)

      assert {:ok, _intent} =
               Versioning.delete_expired_project_snapshot_build_candidate(candidate)

      refute Repo.get(ProjectSnapshot, snapshot.id)

      assert %StorageReservation{status: "released", cleanup_status: "owned"} =
               Repo.get!(StorageReservation, started.id)
    end

    test "does not reclaim a writer with an active publication lease or a foreign job" do
      user = user_fixture()
      project = project_fixture(user)
      assert {:ok, active_snapshot} = request_snapshot(user, project)
      now = TimeHelpers.now()
      stale_at = DateTime.add(now, -16 * 60, :second)

      {active_build, active_job, active_reservation} =
        stale_executing_build!(active_snapshot, stale_at)

      {started, _claim} =
        start_snapshot_storage!(project, active_build, active_reservation, now,
          claim_status: "staging",
          claim_expires_at: DateTime.add(now, 2 * 60 * 60, :second)
        )

      started
      |> Ecto.Changeset.change(
        accounting_measured_at: DateTime.add(now, -120, :second),
        expires_at: DateTime.add(now, -60, :second)
      )
      |> Repo.update!()

      assert %{failure_count: 0, orphaned_count: 0, settled_count: 0} =
               Versioning.reconcile_stale_project_snapshot_builds()

      assert Repo.get!(Oban.Job, active_job.id).state == "executing"
      assert Repo.get!(StorageReservation, started.id).status == "active"

      assert {:ok, foreign_snapshot} = request_snapshot(user, project)

      {_foreign_build, foreign_job, foreign_reservation} =
        stale_executing_build!(foreign_snapshot, stale_at)

      foreign_job
      |> Ecto.Changeset.change(worker: "Storyarn.Workers.ForeignSnapshotWriter")
      |> Repo.update!()

      assert %{failure_count: 0, orphaned_count: 0, settled_count: 0} =
               Versioning.reconcile_stale_project_snapshot_builds()

      assert Repo.get!(Oban.Job, foreign_job.id).state == "executing"
      assert Repo.get!(StorageReservation, foreign_reservation.id).status == "active"
    end

    test "terminalizes a released retryable job without waiting for another delivery" do
      user = user_fixture()
      project = project_fixture(user)
      assert {:ok, snapshot} = request_snapshot(user, project)
      snapshot = materialize_snapshot_capture!(snapshot)
      now = TimeHelpers.now()

      building =
        snapshot
        |> ProjectSnapshot.build_state_changeset(%{
          lifecycle_state: "building",
          progress_phase: "copying",
          building_started_at: now,
          state_updated_at: now
        })
        |> Repo.update!()

      job =
        building.build_job_id
        |> then(&Repo.get!(Oban.Job, &1))
        |> Ecto.Changeset.change(state: "retryable")
        |> Repo.update!()

      reservation = Repo.get!(StorageReservation, building.storage_reservation_id)

      assert {:ok, %StorageReservation{status: "released"}} =
               Billing.release_storage_reservation(
                 reservation.id,
                 reservation.lease_token,
                 reservation.generation,
                 %{
                   reason: "build_failed",
                   cleanup_status: "not_required",
                   cleanup_proof: %{
                     type: "storage_not_started",
                     storage_namespace: reservation.storage_namespace
                   }
                 }
               )

      assert %{failure_count: 0, orphaned_count: 0, settled_count: 1} =
               Versioning.reconcile_stale_project_snapshot_builds()

      assert Repo.get!(Oban.Job, job.id).state == "discarded"

      assert %ProjectSnapshot{
               lifecycle_state: "failed",
               failure_code: "build_failed",
               integrity_state: "incomplete"
             } = Repo.get!(ProjectSnapshot, snapshot.id)
    end

    test "requires both reservation expiry and a terminal owning job before cleanup" do
      user = user_fixture()
      project = project_fixture(user)

      assert {:ok, snapshot} =
               Versioning.request_full_project_snapshot(user_scope_fixture(user), project, %{
                 idempotency_key: Ecto.UUID.generate()
               })

      now = TimeHelpers.now()
      expired_at = DateTime.add(now, -60, :second)

      reservation =
        Repo.get_by!(StorageReservation,
          project_snapshot_id_snapshot: snapshot.id,
          status: "active"
        )

      reservation
      |> Ecto.Changeset.change(
        accounting_measured_at: DateTime.add(now, -120, :second),
        expires_at: expired_at
      )
      |> Repo.update!()

      assert Versioning.list_expired_project_snapshot_build_candidates(now) == []

      discard_job!(snapshot.build_job_id, now)

      assert Versioning.list_expired_project_snapshot_build_candidates(now) == []

      future_advisory_now = build_cleanup_quiesced_at(now)
      assert [premature_candidate] = Versioning.list_expired_project_snapshot_build_candidates(future_advisory_now)

      assert {:error, :expired_build_candidate_changed} =
               Versioning.delete_expired_project_snapshot_build_candidate(premature_candidate)

      assert Repo.get!(ProjectSnapshot, snapshot.id).lifecycle_state == "pending"
      discard_job!(snapshot.build_job_id, DateTime.add(now, -16 * 60, :second))

      snapshot.build_job_id
      |> then(&Repo.get!(Oban.Job, &1))
      |> Ecto.Changeset.change(queue: "default")
      |> Repo.update!()

      assert Versioning.list_expired_project_snapshot_build_candidates(now) == []

      snapshot.build_job_id
      |> then(&Repo.get!(Oban.Job, &1))
      |> Ecto.Changeset.change(queue: "snapshot_archives")
      |> Repo.update!()

      assert [candidate] = Versioning.list_expired_project_snapshot_build_candidates(now)

      assert {:ok, intent} =
               Versioning.delete_expired_project_snapshot_build_candidate(candidate)

      assert intent.reason == "expired_build"
      assert intent.authority_kind == "system"
      refute Repo.get(ProjectSnapshot, snapshot.id)
      assert Repo.get!(StorageReservation, reservation.id).status == "released"
    end

    test "recovers an expired failed build whose active reservation never gained cleanup ownership" do
      user = user_fixture()
      project = project_fixture(user)

      assert {:ok, snapshot} = request_snapshot(user, project)
      snapshot = materialize_snapshot_capture!(snapshot)

      reservation = Repo.get!(StorageReservation, snapshot.storage_reservation_id)
      now = TimeHelpers.now()
      {started, _claim} = start_snapshot_storage!(project, snapshot, reservation, now)

      failed =
        snapshot
        |> ProjectSnapshot.build_state_changeset(%{
          lifecycle_state: "building",
          progress_phase: "copying",
          building_started_at: now,
          state_updated_at: now
        })
        |> Repo.update!()
        |> ProjectSnapshot.build_state_changeset(%{
          lifecycle_state: "failed",
          integrity_state: "incomplete",
          progress_phase: "failed",
          failure_code: "cleanup_unowned",
          failure_message: "Cleanup ownership was not persisted.",
          failed_at: now,
          state_updated_at: now
        })
        |> Repo.update!()

      started
      |> Ecto.Changeset.change(
        accounting_measured_at: DateTime.add(now, -120, :second),
        expires_at: DateTime.add(now, -60, :second)
      )
      |> Repo.update!()

      discard_job!(failed.build_job_id, DateTime.add(now, -16 * 60, :second))

      assert [candidate] = Versioning.list_expired_project_snapshot_build_candidates(now)
      assert candidate.lifecycle_state == "failed"

      assert {:ok, intent} =
               Versioning.delete_expired_project_snapshot_build_candidate(candidate)

      assert intent.reason == "expired_build"
      refute Repo.get(ProjectSnapshot, failed.id)

      assert %StorageReservation{status: "released", cleanup_status: "owned"} =
               Repo.get!(StorageReservation, started.id)
    end

    test "revalidates owning job state under lock" do
      user = user_fixture()
      project = project_fixture(user)

      assert {:ok, snapshot} =
               Versioning.request_full_project_snapshot(user_scope_fixture(user), project, %{
                 idempotency_key: Ecto.UUID.generate()
               })

      now = TimeHelpers.now()

      reservation =
        Repo.get_by!(StorageReservation,
          project_snapshot_id_snapshot: snapshot.id,
          status: "active"
        )

      reservation
      |> Ecto.Changeset.change(
        accounting_measured_at: DateTime.add(now, -120, :second),
        expires_at: DateTime.add(now, -60, :second)
      )
      |> Repo.update!()

      job = Repo.get!(Oban.Job, snapshot.build_job_id)
      discarded_job = discard_job!(job.id, DateTime.add(now, -16 * 60, :second))
      assert [candidate] = Versioning.list_expired_project_snapshot_build_candidates(now)
      discarded_job |> Ecto.Changeset.change(state: "available") |> Repo.update!()

      assert {:error, :expired_build_candidate_changed} =
               Versioning.delete_expired_project_snapshot_build_candidate(candidate)

      assert Repo.get!(ProjectSnapshot, snapshot.id).lifecycle_state == "pending"
      assert Repo.get!(StorageReservation, reservation.id).status == "active"
    end

    test "database assigns the quarantine and rejects an early second-pass claim" do
      user = user_fixture()
      project = project_fixture(user)
      assert {:ok, snapshot} = request_snapshot(user, project)
      now = TimeHelpers.now()

      snapshot.storage_reservation_id
      |> then(&Repo.get!(StorageReservation, &1))
      |> Ecto.Changeset.change(
        accounting_measured_at: DateTime.add(now, -120, :second),
        expires_at: DateTime.add(now, -60, :second)
      )
      |> Repo.update!()

      discard_job!(snapshot.build_job_id, DateTime.add(now, -16 * 60, :second))
      assert [candidate] = Versioning.list_expired_project_snapshot_build_candidates(now)

      assert {:ok, intent} =
               Versioning.delete_expired_project_snapshot_build_candidate(candidate)

      assert {:error, :invalid_snapshot_cleanup_options} =
               Versioning.process_project_snapshot_cleanup_intent(intent.id,
                 now: DateTime.add(now, 3_600, :second)
               )

      assert Repo.get!(SnapshotCleanupIntent, intent.id).status == "pending"

      processing =
        intent
        |> SnapshotCleanupIntent.processing_changeset(now)
        |> Repo.update!()

      before_boundary = database_clock_now()

      _stale_returning_value =
        processing
        |> SnapshotCleanupIntent.next_delete_pass_changeset()
        |> Repo.update!()

      awaiting_second_pass = Repo.get!(SnapshotCleanupIntent, intent.id)

      assert DateTime.diff(awaiting_second_pass.next_delete_pass_at, before_boundary, :second) >=
               Versioning.project_snapshot_build_recovery_quarantine_seconds()

      assert_raise Postgrex.Error, ~r/next delete pass is not eligible yet/, fn ->
        awaiting_second_pass
        |> SnapshotCleanupIntent.processing_changeset(DateTime.add(now, 3_600, :second))
        |> Ecto.Changeset.put_change(:updated_at, DateTime.add(now, -3_600, :second))
        |> Repo.update!()
      end
    end
  end

  describe "parent hard deletion" do
    test "project deletion leaves exact snapshot cleanup intent after the cascade" do
      user = user_fixture()
      project = project_fixture(user)
      ready = create_ready_snapshot(user, project)
      lease = expired_snapshot_export_lease!(project, ready)
      assert {:ok, deleted} = Projects.delete_project(project, user.id)
      parent = self()
      handler_id = "snapshot-hard-delete-intent-#{System.unique_integer([:positive])}"

      Phoenix.PubSub.subscribe(Storyarn.PubSub, "project_snapshots:#{project.id}")

      :ok =
        :telemetry.attach(
          handler_id,
          [:storyarn, :snapshot, :cleanup, :intent],
          fn event, measurements, metadata, pid -> send(pid, {event, measurements, metadata}) end,
          parent
        )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      assert {:ok, _project} = Projects.permanently_delete_project(deleted)

      refute Repo.get(Projects.Project, project.id)
      refute Repo.get(ProjectSnapshot, ready.id)

      intent = Repo.get_by!(SnapshotCleanupIntent, project_snapshot_id_snapshot: ready.id)
      assert intent.reason == "project_hard_delete"
      assert intent.authority_kind == "system"
      assert ready.manifest_storage_key in intent.storage_keys

      assert %StorageReservation{
               status: "released",
               release_reason: "expired_snapshot_export_lease"
             } = Repo.get!(StorageReservation, lease.id)

      assert_receive {:project_snapshot_updated, snapshot_id}
      assert snapshot_id == ready.id

      assert_receive {
        [:storyarn, :snapshot, :cleanup, :intent],
        %{count: 1},
        %{reason: "project_hard_delete", authority_kind: "system"}
      }
    end

    test "project hard deletion owns the empty namespace of a request cancelled before capture" do
      user = user_fixture()
      project = project_fixture(user)
      assert {:ok, requested} = request_snapshot(user, project)

      assert {:ok, cancelled} =
               Versioning.cancel_project_snapshot(user_scope_fixture(user), project, requested.id)

      assert cancelled.lifecycle_state == "cancelled"
      assert is_nil(cancelled.capture_digest)

      assert {:ok, expected_scope} =
               SnapshotArchiveStorage.cleanup_scope(cancelled.project_id, cancelled.object_prefix)

      Enum.each(expected_scope.storage_keys, fn storage_key ->
        assert {:error, :enoent} = Storage.stat(storage_key)
      end)

      assert {:ok, deleted} = Projects.delete_project(project, user.id)
      assert {:ok, _project} = Projects.permanently_delete_project(deleted)

      refute Repo.get(ProjectSnapshot, cancelled.id)

      intent = Repo.get_by!(SnapshotCleanupIntent, project_snapshot_id_snapshot: cancelled.id)
      assert intent.reason == "project_hard_delete"
      assert intent.estimated_cleanup_bytes == 0
      assert intent.storage_keys == expected_scope.storage_keys
      assert intent.object_count == 4

      Enum.each(intent.storage_keys, fn storage_key ->
        assert {:error, :enoent} = Storage.stat(storage_key)
      end)
    end

    test "workspace deletion records cleanup before deleting every project" do
      user = user_fixture()
      project = project_fixture(user)
      workspace = Repo.preload(project, :workspace).workspace
      ready = create_ready_snapshot(user, project)

      assert {:ok, _workspace} = Workspaces.delete_workspace(workspace)

      refute Repo.get(Workspaces.Workspace, workspace.id)
      intent = Repo.get_by!(SnapshotCleanupIntent, project_snapshot_id_snapshot: ready.id)
      assert intent.reason == "workspace_hard_delete"
      assert intent.workspace_id_snapshot == workspace.id
    end

    test "project hard deletion reports a domain fence for a queued restore without a reservation" do
      user = user_fixture()
      project = project_fixture(user)
      ready = create_ready_snapshot(user, project)

      assert {:ok, restore} =
               Versioning.request_project_snapshot_restore(user_scope_fixture(user), project, ready.id, %{
                 idempotency_key: Ecto.UUID.generate()
               })

      job = Repo.get!(Oban.Job, restore.oban_job_id)
      assert %ProjectSnapshotRestore{status: "queued", storage_reservation_id: nil} = restore
      assert {:ok, deleted} = Projects.delete_project(project, user.id)

      assert {:error, :snapshot_active_operation_blocks_deletion} =
               Projects.permanently_delete_project(deleted)

      assert Repo.get!(Projects.Project, project.id).deleted_at
      assert Repo.get!(ProjectSnapshot, ready.id)
      assert Repo.get!(ProjectSnapshotRestore, restore.id).project_snapshot_id == ready.id
      assert Repo.get!(Oban.Job, job.id).state == job.state
      refute Repo.exists?(SnapshotCleanupIntent)
    end

    test "workspace hard deletion reports a domain fence for a queued restore without a reservation" do
      user = user_fixture()
      project = project_fixture(user)
      workspace = Repo.preload(project, :workspace).workspace
      ready = create_ready_snapshot(user, project)

      assert {:ok, restore} =
               Versioning.request_project_snapshot_restore(user_scope_fixture(user), project, ready.id, %{
                 idempotency_key: Ecto.UUID.generate()
               })

      job = Repo.get!(Oban.Job, restore.oban_job_id)
      assert %ProjectSnapshotRestore{status: "queued", storage_reservation_id: nil} = restore

      assert {:error, :snapshot_active_operation_blocks_deletion} =
               Workspaces.delete_workspace(workspace)

      assert Repo.get!(Workspaces.Workspace, workspace.id)
      assert Repo.get!(Projects.Project, project.id)
      assert Repo.get!(ProjectSnapshot, ready.id)
      assert Repo.get!(ProjectSnapshotRestore, restore.id).project_snapshot_id == ready.id
      assert Repo.get!(Oban.Job, job.id).state == job.state
      refute Repo.exists?(SnapshotCleanupIntent)
    end

    test "project deletion fails closed while a build job can still write" do
      user = user_fixture()
      project = project_fixture(user)

      assert {:ok, snapshot} =
               Versioning.request_full_project_snapshot(user_scope_fixture(user), project, %{
                 idempotency_key: Ecto.UUID.generate()
               })

      assert Repo.get!(Oban.Job, snapshot.build_job_id).state == "available"
      assert {:ok, deleted} = Projects.delete_project(project, user.id)
      Phoenix.PubSub.subscribe(Storyarn.PubSub, "project_snapshots:#{project.id}")

      assert {:error, :snapshot_active_operation_blocks_deletion} =
               Projects.permanently_delete_project(deleted)

      assert Repo.get!(Projects.Project, project.id)
      assert Repo.get!(ProjectSnapshot, snapshot.id)
      assert Repo.get_by!(StorageReservation, project_snapshot_id_snapshot: snapshot.id).status == "active"
      refute Repo.exists?(SnapshotCleanupIntent)
      refute_receive {:project_snapshot_updated, _snapshot_id}
    end

    test "stale build recovery lets a soft-deleted project converge to hard deletion" do
      set_stale_build_heartbeat_seconds(0)
      user = user_fixture()
      project = project_fixture(user)
      assert {:ok, snapshot} = request_snapshot(user, project)
      now = database_clock_now()
      stale_at = DateTime.add(now, -16 * 60, :second)
      {_building, job, reservation} = stale_executing_build!(snapshot, stale_at)

      assert {:ok, deleted} = Projects.delete_project(project, user.id)

      assert {:error, :snapshot_active_operation_blocks_deletion} =
               Projects.permanently_delete_project(deleted)

      assert %{failure_count: 0, orphaned_count: 1, settled_count: 0} =
               Versioning.reconcile_stale_project_snapshot_builds()

      assert Repo.get!(Oban.Job, job.id).state == "discarded"
      assert Repo.get!(StorageReservation, reservation.id).status == "active"

      discard_job!(job.id, stale_at)

      candidate =
        stale_at
        |> build_cleanup_quiesced_at()
        |> Versioning.list_expired_project_snapshot_build_candidates()
        |> Enum.find(&(&1.snapshot_id == snapshot.id))

      assert candidate

      assert {:ok, intent} =
               Versioning.delete_expired_project_snapshot_build_candidate(candidate)

      assert intent.reason == "expired_build"
      refute Repo.get(ProjectSnapshot, snapshot.id)
      assert Repo.get!(StorageReservation, reservation.id).status == "released"

      assert {:ok, _project} = Projects.permanently_delete_project(deleted)

      refute Repo.get(Projects.Project, project.id)
      assert Repo.get!(SnapshotCleanupIntent, intent.id)
    end

    test "rolled-back parent cleanup does not publish intents from earlier snapshots" do
      user = user_fixture()
      project = project_fixture(user)
      ready = create_ready_snapshot(user, project)
      lease = expired_snapshot_export_lease!(project, ready)

      assert {:ok, active} =
               Versioning.request_full_project_snapshot(user_scope_fixture(user), project, %{
                 idempotency_key: Ecto.UUID.generate()
               })

      assert ready.id < active.id
      assert {:ok, deleted} = Projects.delete_project(project, user.id)
      parent = self()
      handler_id = "snapshot-rollback-intent-#{System.unique_integer([:positive])}"

      :ok =
        :telemetry.attach(
          handler_id,
          [:storyarn, :snapshot, :cleanup, :intent],
          fn event, measurements, metadata, pid -> send(pid, {event, measurements, metadata}) end,
          parent
        )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      assert {:error, :snapshot_active_operation_blocks_deletion} =
               Projects.permanently_delete_project(deleted)

      refute_receive {[:storyarn, :snapshot, :cleanup, :intent], _, _}
      refute Repo.exists?(SnapshotCleanupIntent)
      assert Repo.get!(ProjectSnapshot, ready.id)
      assert Repo.get!(ProjectSnapshot, active.id)
      assert Repo.get!(StorageReservation, lease.id).status == "active"
    end

    test "project deletion fails closed before loading an oversized snapshot inventory" do
      set_hard_delete_snapshot_limit(1)
      user = user_fixture()
      project = project_fixture(user)
      first = create_ready_snapshot(user, project)
      second = create_ready_snapshot(user, project)
      assert {:ok, deleted} = Projects.delete_project(project, user.id)

      assert {:error, :snapshot_parent_cleanup_limit_exceeded} =
               Projects.permanently_delete_project(deleted)

      assert Repo.get!(Projects.Project, project.id)
      assert Repo.get!(ProjectSnapshot, first.id)
      assert Repo.get!(ProjectSnapshot, second.id)
      refute Repo.exists?(SnapshotCleanupIntent)
    end

    test "workspace deletion fails closed before partially recording oversized cleanup" do
      set_hard_delete_snapshot_limit(1)
      user = user_fixture()
      first_project = project_fixture(user)
      workspace = Repo.preload(first_project, :workspace).workspace
      second_project = project_fixture(user, %{workspace: workspace})
      first = create_ready_snapshot(user, first_project)
      second = create_ready_snapshot(user, second_project)

      assert {:error, :snapshot_parent_cleanup_limit_exceeded} =
               Workspaces.delete_workspace(workspace)

      assert Repo.get!(Workspaces.Workspace, workspace.id)
      assert Repo.get!(ProjectSnapshot, first.id)
      assert Repo.get!(ProjectSnapshot, second.id)
      refute Repo.exists?(SnapshotCleanupIntent)
    end
  end

  defp create_ready_snapshot(user, project) do
    assert {:ok, requested} =
             Versioning.request_full_project_snapshot(user_scope_fixture(user), project, %{
               idempotency_key: Ecto.UUID.generate()
             })

    job =
      requested.build_job_id
      |> then(&Repo.get!(Oban.Job, &1))
      |> Ecto.Changeset.change(
        state: "executing",
        attempt: 1,
        attempted_at: %{TimeHelpers.now() | microsecond: {0, 6}}
      )
      |> Repo.update!()

    assert :ok = BuildProjectSnapshotWorker.perform(job)
    Repo.get!(ProjectSnapshot, requested.id)
  end

  defp request_snapshot(user, project) do
    Versioning.request_full_project_snapshot(user_scope_fixture(user), project, %{
      idempotency_key: Ecto.UUID.generate()
    })
  end

  defp build_cleanup_quiesced_at(timestamp) do
    DateTime.add(
      timestamp,
      Versioning.project_snapshot_build_recovery_quarantine_seconds() + 1,
      :second
    )
  end

  defp database_clock_now do
    %Postgrex.Result{rows: [[now]]} = Repo.query!("SELECT clock_timestamp()")
    DateTime.truncate(now, :second)
  end

  defp discard_job!(job_id, timestamp) do
    job_id
    |> then(&Repo.get!(Oban.Job, &1))
    |> Ecto.Changeset.change(
      state: "discarded",
      discarded_at: %{timestamp | microsecond: {0, 6}}
    )
    |> Repo.update!()
  end

  defp insert_active_restore!(user, project, snapshot) do
    %ProjectSnapshotRestore{}
    |> ProjectSnapshotRestore.request_changeset(%{
      workspace_id: project.workspace_id,
      project_id: project.id,
      project_snapshot_id: snapshot.id,
      requested_by_id: user.id,
      idempotency_key: Ecto.UUID.generate(),
      snapshot_lifecycle_generation: snapshot.lifecycle_generation,
      snapshot_accounting_generation: snapshot.accounting_generation || 1,
      archive_storage_key: "active/archive",
      archive_size_bytes: 1,
      archive_checksum: String.duplicate("a", 64),
      manifest_storage_key: "active/manifest",
      manifest_size_bytes: 1,
      manifest_checksum: String.duplicate("b", 64),
      requested_at: TimeHelpers.now()
    })
    |> Repo.insert!()
  end

  defp stale_executing_build!(snapshot, now) do
    snapshot = materialize_snapshot_capture!(snapshot)
    database_now = database_clock_now()

    state_now =
      case DateTime.compare(snapshot.state_updated_at, database_now) do
        :gt -> snapshot.state_updated_at
        _not_ahead -> database_now
      end

    building =
      snapshot
      |> ProjectSnapshot.build_state_changeset(%{
        lifecycle_state: "building",
        progress_phase: "copying",
        building_started_at: state_now,
        state_updated_at: state_now
      })
      |> Repo.update!()

    job =
      building.build_job_id
      |> then(&Repo.get!(Oban.Job, &1))
      |> Ecto.Changeset.change(
        state: "executing",
        attempt: 1,
        attempted_at: %{now | microsecond: {0, 6}}
      )
      |> Repo.update!()

    reservation =
      building.storage_reservation_id
      |> then(&Repo.get!(StorageReservation, &1))
      |> Ecto.Changeset.change(
        accounting_measured_at: DateTime.add(now, -120, :second),
        expires_at: DateTime.add(now, -60, :second)
      )
      |> Repo.update!()

    {building, job, reservation}
  end

  defp materialize_snapshot_capture!(snapshot) do
    job =
      snapshot.build_job_id
      |> then(&Repo.get!(Oban.Job, &1))
      |> Ecto.Changeset.change(
        state: "executing",
        attempt: 1,
        attempted_at: %{TimeHelpers.now() | microsecond: {0, 6}}
      )
      |> Repo.update!()

    assert {:ok, state} = ProjectSnapshotBuild.materialize_capture(snapshot.id, job.id)
    assert state in [:captured, :already_captured]

    Repo.get!(ProjectSnapshot, snapshot.id)
  end

  defp start_snapshot_storage!(project, snapshot, reservation, now, opts \\ []) do
    reservation =
      reservation
      |> Ecto.Changeset.change(expires_at: DateTime.add(now, 60 * 60, :second))
      |> Repo.update!()

    assert {:ok, cleanup_scope} =
             snapshot_cleanup_scope(snapshot, project.id)

    assert {:ok, started} =
             Billing.mark_storage_reservation_started(
               reservation.id,
               reservation.lease_token,
               reservation.generation,
               cleanup_scope
             )

    claim =
      snapshot.object_prefix
      |> SnapshotObjectPublicationClaim.create_changeset(
        String.duplicate("a", 64),
        Ecto.UUID.generate(),
        Keyword.get(opts, :claim_expires_at, DateTime.add(now, 60 * 60, :second)),
        started.id,
        started.lease_token
      )
      |> Repo.insert!()

    claim =
      case Keyword.get(opts, :claim_status, "poisoned") do
        "staging" -> claim
        status -> claim |> SnapshotObjectPublicationClaim.status_changeset(status) |> Repo.update!()
      end

    {started, claim}
  end

  defp set_hard_delete_snapshot_limit(limit) do
    original = Application.fetch_env!(:storyarn, :snapshot_lifecycle)

    Application.put_env(
      :storyarn,
      :snapshot_lifecycle,
      Keyword.put(original, :hard_delete_snapshot_limit, limit)
    )

    on_exit(fn -> Application.put_env(:storyarn, :snapshot_lifecycle, original) end)
  end

  defp set_stale_build_heartbeat_seconds(seconds) do
    original = Application.fetch_env!(:storyarn, :snapshot_lifecycle)

    Application.put_env(
      :storyarn,
      :snapshot_lifecycle,
      Keyword.put(original, :stale_build_heartbeat_seconds, seconds)
    )

    on_exit(fn -> Application.put_env(:storyarn, :snapshot_lifecycle, original) end)
  end

  defp expire_multipart_quiescence!(cleanup_request_id) do
    now = TimeHelpers.now()

    {1, nil} =
      Repo.update_all(
        from(request in StorageCleanupRequest, where: request.id == ^cleanup_request_id),
        set: [
          multipart_quiescence_started_at: DateTime.add(now, -2, :second),
          multipart_quiescence_not_before: DateTime.add(now, -1, :second)
        ]
      )

    :ok
  end

  defp expired_snapshot_export_lease!(project, snapshot) do
    assert {:ok, lease} =
             Billing.acquire_snapshot_export_lease(%{
               workspace_id: project.workspace_id,
               project_id: project.id,
               project_snapshot_id: snapshot.id
             })

    now = database_clock_now()

    lease
    |> Ecto.Changeset.change(
      accounting_measured_at: DateTime.add(now, -120, :second),
      expires_at: DateTime.add(now, -60, :second)
    )
    |> Repo.update!()
  end

  defp insert_retention_snapshot_clones!(snapshot, count, expires_at) do
    fields = ProjectSnapshot.__schema__(:fields) -- [:id]
    base = snapshot |> Map.from_struct() |> Map.take(fields)

    rows =
      Enum.map(1..count, fn index ->
        token = index |> Integer.to_string() |> String.pad_leading(16, "0")
        prefix = SnapshotArchiveStorage.ready_prefix(snapshot.project_id, token)

        Map.merge(base, %{
          version_number: snapshot.version_number + index,
          format_version: 2,
          object_prefix: prefix,
          archive_storage_key: SnapshotArchiveStorage.archive_key(prefix),
          manifest_storage_key: SnapshotArchiveStorage.manifest_key(prefix),
          idempotency_key: Ecto.UUID.generate(),
          capture_boundary: Ecto.UUID.generate(),
          origin: "daily",
          expires_at: expires_at
        })
      end)

    {^count, nil} = Repo.insert_all(ProjectSnapshot, rows)
  end

  defp snapshot_cleanup_scope(%ProjectSnapshot{format_version: 2} = snapshot, _project_id) do
    SnapshotArchiveStorage.cleanup_scope_from_snapshot(snapshot)
  end

  defp cleanup_replay_expectations(intent) do
    %{
      cleanup_intent_id_snapshot: intent.id,
      workspace_id_snapshot: intent.workspace_id_snapshot,
      project_id_snapshot: intent.project_id_snapshot,
      project_snapshot_id_snapshot: intent.project_snapshot_id_snapshot,
      lifecycle_generation: intent.deletion_generation,
      object_prefix: intent.ready_prefix,
      expected_size_bytes: intent.estimated_cleanup_bytes,
      error_code: intent.last_error_code,
      reason: intent.reason,
      retry_count: intent.retry_count,
      processing_generation: intent.processing_generation
    }
  end

  defp different_expectation(value) when is_integer(value), do: value + 1

  defp different_expectation(<<first, rest::binary>>) do
    replacement = if first == ?0, do: "1", else: "0"
    replacement <> rest
  end

  defp use_alternate_storage_namespace!(upload_dir) do
    original = Application.fetch_env!(:storyarn, :storage)
    Application.put_env(:storyarn, :storage, Keyword.put(original, :upload_dir, upload_dir))
    on_exit(fn -> Application.put_env(:storyarn, :storage, original) end)
  end
end
