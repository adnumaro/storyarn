defmodule Storyarn.Imports.ImportLifecycleTest do
  use Storyarn.DataCase, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Accounts.Scope
  alias Storyarn.Assets.Storage
  alias Storyarn.Collaboration
  alias Storyarn.Flows
  alias Storyarn.Imports
  alias Storyarn.Imports.ErrorDeduplicator
  alias Storyarn.Imports.PlanCleanupRequest
  alias Storyarn.Imports.PlanStorage
  alias Storyarn.Imports.ProjectImportAttempt
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers

  @private_filename "client-jane-doe-private-project.yarn"
  @private_content "Private dialogue about Jane Doe and account 12345"

  setup do
    user = user_fixture()
    project = project_fixture(user)
    %{scope: Scope.for_user(user), user: user, project: project}
  end

  test "persists an encrypted, previewable attempt without filename or content PII", ctx do
    source = yarn(@private_content)

    assert {:ok, attempt, preview} =
             Imports.prepare_import(ctx.scope, ctx.project, @private_filename, source)

    assert attempt.status == "ready"
    assert attempt.stage == "parsed"
    assert attempt.format == "yarn"
    assert attempt.source_kind == "file"
    assert preview.counts.flows == 1

    persisted = Repo.get!(ProjectImportAttempt, attempt.id)
    serialized = inspect(Map.from_struct(persisted))
    refute serialized =~ @private_filename
    refute serialized =~ @private_content

    assert {:ok, encrypted} = Storage.download(attempt.plan_storage_key)
    refute encrypted =~ @private_filename
    refute encrypted =~ @private_content
    assert String.starts_with?(attempt.plan_storage_key, "imports/plans/")

    cleanup = Repo.get!(PlanCleanupRequest, attempt.plan_cleanup_request_id)
    cleanup_serialized = inspect(Map.from_struct(cleanup))
    refute cleanup_serialized =~ @private_filename
    refute cleanup_serialized =~ @private_content
    refute Map.has_key?(Map.from_struct(cleanup), :user_id)

    assert {:ok, plan} = PlanStorage.load(attempt.plan_storage_key)
    assert plan.format == :yarn
    assert get_in(plan.data, ["flows", Access.at(0), "nodes"])
  end

  test "queues only the attempt id and materializes the encrypted plan idempotently", ctx do
    assert {:ok, ready, _preview} =
             Imports.prepare_import(ctx.scope, ctx.project, "project.yarn", yarn("Hello"))

    assert {:ok, queued} = Imports.enqueue_import(ctx.scope, ready.id, :rename)
    assert queued.status == "queued"

    job = Repo.get!(Oban.Job, queued.oban_job_id)
    assert job.args == %{"attempt_id" => ready.id}

    :ok = Collaboration.subscribe_dashboard(ctx.project.id)
    assert {:ok, completed} = Imports.perform_import(ready.id, attempt: 1, max_attempts: 3)
    assert completed.status == "completed"
    assert completed.stage == "completed"
    refute completed.user_id
    refute completed.idempotency_key
    assert {:error, :import_plan_unavailable} = PlanStorage.load(ready.plan_storage_key)
    assert Repo.get_by!(PlanCleanupRequest, plan_storage_key: ready.plan_storage_key).state == "completed"
    assert Enum.any?(Flows.list_flows(ctx.project.id), &(&1.name == "Start"))
    assert_received {:dashboard_invalidate, :all}

    assert {:ok, same_completed} = Imports.perform_import(ready.id, attempt: 2, max_attempts: 3)
    assert same_completed.id == completed.id
    assert Enum.count(Flows.list_flows(ctx.project.id), &(&1.name == "Start")) == 1
  end

  test "persists actual materialized counts after skip conflicts", ctx do
    _existing = Storyarn.FlowsFixtures.flow_fixture(ctx.project, %{name: "Start"})

    assert {:ok, ready, preview} =
             Imports.prepare_import(ctx.scope, ctx.project, "project.yarn", yarn("Hello"))

    assert preview.counts.flows == 1
    assert preview.counts.nodes > 0
    assert ready.counts["flows"] == 1

    assert {:ok, queued} = Imports.enqueue_import(ctx.scope, ready.id, :skip)
    assert {:ok, completed} = Imports.perform_import(queued.id, attempt: 1, max_attempts: 3)

    assert completed.counts == %{
             "assets" => 0,
             "flows" => 0,
             "nodes" => 0,
             "scenes" => 0,
             "screenplays" => 0,
             "sheets" => 0
           }

    assert Repo.get!(ProjectImportAttempt, completed.id).counts == completed.counts
    assert Enum.count(Flows.list_flows(ctx.project.id), &(&1.name == "Start")) == 1
  end

  test "rolls back materialization when the attempt cannot complete atomically", ctx do
    assert {:ok, ready, _preview} =
             Imports.prepare_import(ctx.scope, ctx.project, "project.yarn", yarn("Hello"))

    assert {:ok, queued} = Imports.enqueue_import(ctx.scope, ready.id, :rename)

    :ok = Collaboration.subscribe_dashboard(ctx.project.id)

    assert {:error, :retryable_import_error} =
             Imports.perform_import(queued.id,
               attempt: 1,
               max_attempts: 3,
               before_attempt_completion: fn -> raise "simulated process failure" end
             )

    retrying = Repo.get!(ProjectImportAttempt, queued.id)
    assert retrying.status == "retrying"
    refute Enum.any?(Flows.list_flows(ctx.project.id), &(&1.name == "Start"))
    refute_received {:dashboard_invalidate, :all}

    assert {:ok, completed} = Imports.perform_import(queued.id, attempt: 2, max_attempts: 3)
    assert completed.status == "completed"
    assert Enum.count(Flows.list_flows(ctx.project.id), &(&1.name == "Start")) == 1

    assert {:ok, same_completed} = Imports.perform_import(queued.id, attempt: 3, max_attempts: 3)
    assert same_completed.id == completed.id
    assert Enum.count(Flows.list_flows(ctx.project.id), &(&1.name == "Start")) == 1
  end

  test "serializes concurrent deliveries and materializes exactly once", ctx do
    assert {:ok, ready, _preview} =
             Imports.prepare_import(ctx.scope, ctx.project, "project.yarn", yarn("Hello"))

    assert {:ok, queued} = Imports.enqueue_import(ctx.scope, ready.id, :rename)
    parent = self()

    deliveries =
      Enum.map(1..2, fn _index ->
        Task.async(fn ->
          Imports.perform_import(queued.id,
            attempt: 1,
            max_attempts: 3,
            before_materialization_transaction: fn ->
              send(parent, {:delivery_ready, self()})

              receive do
                :continue_delivery -> :ok
              end
            end
          )
        end)
      end)

    delivery_pids =
      Enum.map(deliveries, fn _delivery ->
        assert_receive {:delivery_ready, delivery_pid}, 2_000
        delivery_pid
      end)

    Enum.each(delivery_pids, &send(&1, :continue_delivery))

    completed_attempts =
      Enum.map(deliveries, fn delivery ->
        assert {:ok, completed} = Task.await(delivery, 10_000)
        assert completed.status == "completed"
        completed
      end)

    assert completed_attempts |> Enum.map(& &1.id) |> Enum.uniq() == [queued.id]
    assert Enum.count(Flows.list_flows(ctx.project.id), &(&1.name == "Start")) == 1
  end

  test "locks project and membership before the attempt", ctx do
    assert {:ok, ready, _preview} =
             Imports.prepare_import(ctx.scope, ctx.project, "project.yarn", yarn("Hello"))

    assert {:ok, queued} = Imports.enqueue_import(ctx.scope, ready.id, :rename)

    handler_id = "import-lock-order-#{System.unique_integer([:positive])}"
    marker = make_ref()
    parent = self()

    :ok =
      :telemetry.attach(
        handler_id,
        [:storyarn, :repo, :query],
        fn _event, _measurements, %{query: query}, {pid, ref} ->
          if self() == pid do
            lock =
              cond do
                String.contains?(query, ~s(FROM "projects")) and String.contains?(query, "FOR SHARE") ->
                  :project

                String.contains?(query, ~s(FROM "project_memberships")) and
                    String.contains?(query, "FOR SHARE") ->
                  :membership

                String.contains?(query, ~s(FROM "project_import_attempts")) and
                    String.contains?(query, "FOR UPDATE") ->
                  :attempt

                true ->
                  nil
              end

            if lock, do: send(pid, {ref, lock})
          end
        end,
        {parent, marker}
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    assert {:ok, completed} = Imports.perform_import(queued.id, attempt: 1, max_attempts: 3)
    assert completed.status == "completed"

    lock_order =
      Enum.map(1..3, fn _index ->
        assert_receive {^marker, lock}
        lock
      end)

    assert lock_order == [:project, :membership, :attempt]
    refute_receive {^marker, _unexpected_lock}
  end

  test "locks authorization before the attempt when cancelling", ctx do
    assert {:ok, ready, _preview} =
             Imports.prepare_import(ctx.scope, ctx.project, "project.yarn", yarn("Hello"))

    handler_id = "import-cancel-lock-order-#{System.unique_integer([:positive])}"
    marker = make_ref()
    parent = self()

    :ok =
      :telemetry.attach(
        handler_id,
        [:storyarn, :repo, :query],
        fn _event, _measurements, %{query: query}, {pid, ref} ->
          if self() == pid do
            lock =
              cond do
                String.contains?(query, ~s(FROM "projects")) and String.contains?(query, "FOR SHARE") ->
                  :project

                String.contains?(query, ~s(FROM "project_memberships")) and
                    String.contains?(query, "FOR SHARE") ->
                  :membership

                String.contains?(query, ~s(FROM "project_import_attempts")) and
                    String.contains?(query, "FOR UPDATE") ->
                  :attempt

                true ->
                  nil
              end

            if lock, do: send(pid, {ref, lock})
          end
        end,
        {parent, marker}
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    assert {:ok, expired} = Imports.cancel_import(ctx.scope, ready.id)
    assert expired.status == "expired"

    lock_order =
      Enum.map(1..3, fn _index ->
        assert_receive {^marker, lock}
        lock
      end)

    assert lock_order == [:project, :membership, :attempt]
    refute_receive {^marker, _unexpected_lock}
  end

  test "rechecks edit authorization at the cancellation boundary", ctx do
    editor = user_fixture()
    membership = membership_fixture(ctx.project, editor, "editor")
    editor_scope = Scope.for_user(editor)

    assert {:ok, ready, _preview} =
             Imports.prepare_import(editor_scope, ctx.project, "project.yarn", yarn("Hello"))

    assert {:error, :unauthorized} =
             Imports.cancel_import(editor_scope, ready.id,
               before_cancel_transaction: fn ->
                 assert {:ok, _membership} = Storyarn.Projects.remove_member(membership)
               end
             )

    assert Repo.get!(ProjectImportAttempt, ready.id).status == "ready"
    assert {:ok, _plan} = PlanStorage.load(ready.plan_storage_key)
    assert {:ok, _expired} = Imports.cancel_import(ctx.scope, ready.id)
  end

  test "does not disclose cancellable attempts to project non-members", ctx do
    outsider_scope = Scope.for_user(user_fixture())

    assert {:ok, ready, _preview} =
             Imports.prepare_import(ctx.scope, ctx.project, "project.yarn", yarn("Hello"))

    assert {:error, :not_found} = Imports.cancel_import(outsider_scope, ready.id)
    assert Repo.get!(ProjectImportAttempt, ready.id).status == "ready"
    assert {:ok, _expired} = Imports.cancel_import(ctx.scope, ready.id)
  end

  test "rechecks and locks authorization at the materialization boundary", ctx do
    editor = user_fixture()
    membership = membership_fixture(ctx.project, editor, "editor")
    editor_scope = Scope.for_user(editor)

    assert {:ok, ready, _preview} =
             Imports.prepare_import(editor_scope, ctx.project, "project.yarn", yarn("Hello"))

    assert {:ok, queued} = Imports.enqueue_import(editor_scope, ready.id, :rename)

    assert {:ok, failed} =
             Imports.perform_import(queued.id,
               attempt: 1,
               max_attempts: 3,
               before_materialization_transaction: fn ->
                 assert {:ok, _membership} = Storyarn.Projects.remove_member(membership)
               end
             )

    assert failed.status == "failed"
    assert failed.error_code == "unauthorized"
    refute Enum.any?(Flows.list_flows(ctx.project.id), &(&1.name == "Start"))
  end

  test "does not materialize when the project is deleted at the transaction boundary", ctx do
    assert {:ok, ready, _preview} =
             Imports.prepare_import(ctx.scope, ctx.project, "project.yarn", yarn("Hello"))

    assert {:ok, queued} = Imports.enqueue_import(ctx.scope, ready.id, :rename)

    assert {:ok, failed} =
             Imports.perform_import(queued.id,
               attempt: 1,
               max_attempts: 3,
               before_materialization_transaction: fn ->
                 assert {:ok, _project} = Storyarn.Projects.delete_project(ctx.project, ctx.user.id)
               end
             )

    assert failed.status == "failed"
    assert failed.error_code == "unauthorized"
    refute Enum.any?(Flows.list_flows(ctx.project.id), &(&1.name == "Start"))
  end

  test "retains a cleanup tombstone when permanent deletion wins before the worker", ctx do
    assert {:ok, ready, _preview} =
             Imports.prepare_import(ctx.scope, ctx.project, "project.yarn", yarn("Hello"))

    assert {:ok, queued} = Imports.enqueue_import(ctx.scope, ready.id, :rename)
    cleanup = Repo.get_by!(PlanCleanupRequest, plan_storage_key: queued.plan_storage_key)
    assert cleanup.state == "retained"
    assert queued.plan_cleanup_request_id == cleanup.id

    assert {:ok, _project} = Storyarn.Projects.permanently_delete_project(ctx.project)

    refute Repo.get(ProjectImportAttempt, queued.id)
    orphaned_cleanup = Repo.get!(PlanCleanupRequest, cleanup.id)
    assert orphaned_cleanup.state == "retained"
    refute orphaned_cleanup.project_id
    assert {:ok, _encrypted} = Storage.download(queued.plan_storage_key)

    assert {:ok, :attempt_not_found} = Imports.perform_import(queued.id, attempt: 1, max_attempts: 3)
    assert {:ok, 0} = Imports.expire_stale_imports()

    assert {:error, :import_plan_unavailable} = PlanStorage.load(queued.plan_storage_key)
    completed_cleanup = Repo.get!(PlanCleanupRequest, cleanup.id)
    assert completed_cleanup.state == "completed"
    assert completed_cleanup.completed_at
  end

  test "retries plan cleanup after storage deletion fails following a project cascade", ctx do
    assert {:ok, ready, _preview} =
             Imports.prepare_import(ctx.scope, ctx.project, "project.yarn", yarn("Hello"))

    assert {:ok, queued} = Imports.enqueue_import(ctx.scope, ready.id, :rename)

    assert {:ok, :attempt_not_found} =
             Imports.perform_import(queued.id,
               attempt: 1,
               max_attempts: 3,
               before_materialization_transaction: fn ->
                 assert {:ok, _project} = Storyarn.Projects.permanently_delete_project(ctx.project)
               end,
               plan_delete: fn _storage_key -> {:error, :temporary_storage_failure} end
             )

    assert {:ok, _encrypted} = Storage.download(queued.plan_storage_key)

    pending_cleanup =
      Repo.get_by!(PlanCleanupRequest, plan_storage_key: queued.plan_storage_key)

    assert pending_cleanup.state == "pending"
    assert pending_cleanup.attempt_count == 1
    assert pending_cleanup.last_error_code == "plan_cleanup_failed"
    refute pending_cleanup.project_id

    pending_cleanup
    |> Ecto.Changeset.change(
      cleanup_after: DateTime.utc_now() |> DateTime.add(-60, :second) |> DateTime.truncate(:second)
    )
    |> Repo.update!()

    assert {:ok, 0} = Imports.expire_stale_imports()
    assert {:error, :import_plan_unavailable} = PlanStorage.load(queued.plan_storage_key)

    completed_cleanup = Repo.get!(PlanCleanupRequest, pending_cleanup.id)
    assert completed_cleanup.state == "completed"
    assert completed_cleanup.attempt_count == 1
    refute completed_cleanup.last_error_code
    refute completed_cleanup.project_id
  end

  test "a late upload reopens a completed cleanup generation and removes the new object", ctx do
    parent = self()

    preparer =
      Task.async(fn ->
        Imports.prepare_import(ctx.scope, ctx.project, "project.yarn", yarn("Hello"),
          plan_store: fn storage_key, plan ->
            send(parent, {:upload_waiting, self(), storage_key})

            receive do
              :finish_upload -> :ok
            end

            PlanStorage.store_at(storage_key, plan)
          end
        )
      end)

    assert_receive {:upload_waiting, upload_pid, storage_key}

    cleanup = Repo.get_by!(PlanCleanupRequest, plan_storage_key: storage_key)

    assert {:ok, _project} = Storyarn.Projects.permanently_delete_project(ctx.project)
    assert {:ok, 0} = Imports.expire_stale_imports()

    still_reserved = Repo.get!(PlanCleanupRequest, cleanup.id)
    assert still_reserved.state == "reserved"
    refute still_reserved.project_id

    still_reserved
    |> Ecto.Changeset.change(
      cleanup_after: DateTime.utc_now() |> DateTime.add(-60, :second) |> DateTime.truncate(:second)
    )
    |> Repo.update!()

    assert {:ok, 0} = Imports.expire_stale_imports()
    first_completion = Repo.get!(PlanCleanupRequest, cleanup.id)
    assert first_completion.state == "completed"
    assert first_completion.generation == 1

    send(upload_pid, :finish_upload)

    assert {:error, :unauthorized} = Task.await(preparer, 5_000)
    assert {:error, :import_plan_unavailable} = PlanStorage.load(storage_key)

    final_cleanup = Repo.get!(PlanCleanupRequest, cleanup.id)
    assert final_cleanup.state == "completed"
    assert final_cleanup.generation > first_completion.generation
    refute final_cleanup.project_id
    assert Repo.aggregate(ProjectImportAttempt, :count) == 0
  end

  test "defers cleanup after an ambiguous upload result until the settlement deadline", ctx do
    parent = self()

    assert {:error, :import_plan_storage_failed} =
             Imports.prepare_import(ctx.scope, ctx.project, "project.yarn", yarn("Hello"),
               plan_store: fn storage_key, plan ->
                 writer =
                   spawn(fn ->
                     receive do
                       :finish_late_upload ->
                         result = PlanStorage.store_at(storage_key, plan)
                         send(parent, {:late_upload_finished, self(), result})
                     end
                   end)

                 send(parent, {:ambiguous_upload, writer, storage_key})
                 {:error, :timeout}
               end
             )

    assert_receive {:ambiguous_upload, writer, storage_key}

    cleanup = Repo.get_by!(PlanCleanupRequest, plan_storage_key: storage_key)
    assert cleanup.state == "pending"
    assert cleanup.generation == 1
    assert cleanup.last_error_code == "upload_outcome_uncertain"
    assert DateTime.diff(cleanup.cleanup_after, TimeHelpers.now(), :second) > 86_000
    assert Repo.aggregate(ProjectImportAttempt, :count) == 0

    send(writer, :finish_late_upload)
    assert_receive {:late_upload_finished, ^writer, {:ok, ^storage_key}}, 5_000
    assert {:ok, _plan} = PlanStorage.load(storage_key)

    assert {:ok, 0} = Imports.expire_stale_imports()
    assert {:ok, _plan} = PlanStorage.load(storage_key)

    cleanup
    |> Ecto.Changeset.change(
      cleanup_after: DateTime.utc_now() |> DateTime.add(-60, :second) |> DateTime.truncate(:second)
    )
    |> Repo.update!()

    assert {:ok, 0} = Imports.expire_stale_imports()
    assert {:error, :import_plan_unavailable} = PlanStorage.load(storage_key)

    completed = Repo.get!(PlanCleanupRequest, cleanup.id)
    assert completed.state == "completed"
    assert completed.generation == 2
    refute completed.last_error_code
  end

  test "bounds a stalled plan store and leaves a durable deferred cleanup", ctx do
    parent = self()

    assert {:error, :import_plan_storage_failed} =
             Imports.prepare_import(ctx.scope, ctx.project, "project.yarn", yarn("Hello"),
               plan_store_timeout: 25,
               plan_store: fn storage_key, _plan ->
                 send(parent, {:stalled_store_started, self(), storage_key})

                 receive do
                   :never_sent -> {:ok, storage_key}
                 end
               end
             )

    assert_receive {:stalled_store_started, store_pid, storage_key}
    refute Process.alive?(store_pid)

    cleanup = Repo.get_by!(PlanCleanupRequest, plan_storage_key: storage_key)
    assert cleanup.state == "pending"
    assert cleanup.generation == 1
    assert cleanup.last_error_code == "upload_outcome_uncertain"
    assert DateTime.diff(cleanup.cleanup_after, TimeHelpers.now(), :second) > 86_000
    assert Repo.aggregate(ProjectImportAttempt, :count) == 0
  end

  test "a scanner cannot delete from a stale reserved snapshot after the uploader retains it", ctx do
    assert {:ok, ready, _preview} =
             Imports.prepare_import(ctx.scope, ctx.project, "project.yarn", yarn("Hello"))

    cleanup = Repo.get!(PlanCleanupRequest, ready.plan_cleanup_request_id)

    cleanup
    |> Ecto.Changeset.change(
      state: "reserved",
      cleanup_after: DateTime.utc_now() |> DateTime.add(-60, :second) |> DateTime.truncate(:second)
    )
    |> Repo.update!()

    parent = self()

    scanner =
      Task.async(fn ->
        Imports.expire_stale_imports(
          before_cleanup_claim: fn loaded ->
            if loaded.id == cleanup.id do
              send(parent, {:cleanup_loaded, self()})

              receive do
                :continue_cleanup -> :ok
              end
            end
          end
        )
      end)

    assert_receive {:cleanup_loaded, scanner_pid}

    PlanCleanupRequest
    |> Repo.get!(cleanup.id)
    |> Ecto.Changeset.change(state: "retained", cleanup_after: nil)
    |> Repo.update!()

    send(scanner_pid, :continue_cleanup)
    assert {:ok, 0} = Task.await(scanner, 5_000)

    retained = Repo.get!(PlanCleanupRequest, cleanup.id)
    assert retained.state == "retained"
    assert {:ok, _plan} = PlanStorage.load(ready.plan_storage_key)

    assert {:ok, _expired} = Imports.cancel_import(ctx.scope, ready.id)
  end

  test "two scanners acquire a single cleanup claim", ctx do
    assert {:ok, ready, _preview} =
             Imports.prepare_import(ctx.scope, ctx.project, "project.yarn", yarn("Hello"))

    assert {:ok, _expired} =
             ready
             |> ProjectImportAttempt.expired_changeset(TimeHelpers.now())
             |> Repo.update()

    cleanup = Repo.get!(PlanCleanupRequest, ready.plan_cleanup_request_id)

    cleanup
    |> Ecto.Changeset.change(
      state: "pending",
      cleanup_after: DateTime.utc_now() |> DateTime.add(-60, :second) |> DateTime.truncate(:second)
    )
    |> Repo.update!()

    parent = self()

    scan = fn ->
      Imports.expire_stale_imports(
        before_cleanup_claim: fn loaded ->
          if loaded.id == cleanup.id do
            send(parent, {:scanner_ready, self()})

            receive do
              :continue_cleanup -> :ok
            end
          end
        end,
        plan_delete: fn storage_key ->
          send(parent, {:plan_deleted, self(), storage_key})
          PlanStorage.delete(storage_key)
        end
      )
    end

    scanners = [Task.async(scan), Task.async(scan)]

    scanner_pids =
      Enum.map(scanners, fn _scanner ->
        assert_receive {:scanner_ready, scanner_pid}
        scanner_pid
      end)

    Enum.each(scanner_pids, &send(&1, :continue_cleanup))

    Enum.each(scanners, fn scanner ->
      assert {:ok, 0} = Task.await(scanner, 5_000)
    end)

    assert_receive {:plan_deleted, _scanner_pid, storage_key}
    assert storage_key == ready.plan_storage_key
    refute_receive {:plan_deleted, _scanner_pid, _storage_key}, 100

    completed = Repo.get!(PlanCleanupRequest, cleanup.id)
    assert completed.state == "completed"
    assert completed.generation == 1
  end

  test "recovers an abandoned deleting lease with a new generation", ctx do
    assert {:ok, ready, _preview} =
             Imports.prepare_import(ctx.scope, ctx.project, "project.yarn", yarn("Hello"))

    assert {:ok, _expired} =
             ready
             |> ProjectImportAttempt.expired_changeset(TimeHelpers.now())
             |> Repo.update()

    cleanup = Repo.get!(PlanCleanupRequest, ready.plan_cleanup_request_id)

    cleanup
    |> Ecto.Changeset.change(
      state: "deleting",
      generation: 4,
      cleanup_after: DateTime.utc_now() |> DateTime.add(-60, :second) |> DateTime.truncate(:second)
    )
    |> Repo.update!()

    assert {:ok, 0} = Imports.expire_stale_imports()

    completed = Repo.get!(PlanCleanupRequest, cleanup.id)
    assert completed.state == "completed"
    assert completed.generation == 5
    assert {:error, :import_plan_unavailable} = PlanStorage.load(ready.plan_storage_key)
  end

  test "expires an active attempt whose Oban job was discarded", ctx do
    assert {:ok, ready, _preview} =
             Imports.prepare_import(ctx.scope, ctx.project, "project.yarn", yarn("Hello"))

    assert {:ok, queued} = Imports.enqueue_import(ctx.scope, ready.id, :rename)

    queued
    |> Ecto.Changeset.change(expires_at: DateTime.utc_now() |> DateTime.add(-60, :second) |> DateTime.truncate(:second))
    |> Repo.update!()

    queued.oban_job_id
    |> then(&Repo.get!(Oban.Job, &1))
    |> Ecto.Changeset.change(state: "discarded", discarded_at: DateTime.utc_now())
    |> Repo.update!()

    assert {:ok, 1} = Imports.expire_stale_imports()

    expired = Repo.get!(ProjectImportAttempt, queued.id)
    assert expired.status == "expired"
    refute expired.user_id
    refute expired.idempotency_key
    assert {:error, :import_plan_unavailable} = PlanStorage.load(queued.plan_storage_key)
    assert Repo.get!(PlanCleanupRequest, queued.plan_cleanup_request_id).state == "completed"
  end

  test "cleanup backoff lets requests beyond the first batch make progress", _ctx do
    now = DateTime.truncate(DateTime.utc_now(), :second)
    due_at = DateTime.add(now, -60, :second)

    rows =
      Enum.map(1..101, fn _index ->
        %{
          plan_storage_key: "imports/plans/#{Ecto.UUID.generate()}.plan.enc",
          format: "yarn",
          parser_version: "2",
          state: "pending",
          cleanup_after: due_at,
          attempt_count: 0,
          generation: 0,
          inserted_at: now,
          updated_at: now
        }
      end)

    assert {101, nil} = Repo.insert_all(PlanCleanupRequest, rows)

    assert {:ok, 0} =
             Imports.expire_stale_imports(plan_delete: fn _storage_key -> {:error, :persistent_storage_failure} end)

    assert Repo.one(from(request in PlanCleanupRequest, select: count(request.id))) == 101

    assert Repo.one(from(request in PlanCleanupRequest, where: request.attempt_count == 1, select: count(request.id))) ==
             100

    assert {:ok, 0} = Imports.expire_stale_imports()

    assert Repo.one(from(request in PlanCleanupRequest, where: request.state == "completed", select: count(request.id))) ==
             1

    assert Repo.one(from(request in PlanCleanupRequest, where: request.state == "pending", select: count(request.id))) ==
             100
  end

  test "deduplicates simultaneous preparation of identical source", ctx do
    source = yarn("Hello")

    assert {:ok, first, _preview} =
             Imports.prepare_import(ctx.scope, ctx.project, "first.yarn", source)

    assert {:ok, second, _preview} =
             Imports.prepare_import(ctx.scope, ctx.project, "second.yarn", source)

    assert second.id == first.id
  end

  test "rechecks edit authorization in the context", %{project: project} do
    viewer = user_fixture()
    membership_fixture(project, viewer, "viewer")

    assert {:error, :unauthorized} =
             Imports.prepare_import(
               Scope.for_user(viewer),
               project,
               "project.yarn",
               yarn("Hello")
             )
  end

  test "rejects unsafe narrative semantics before persisting an attempt", ctx do
    source = yarn("<<if visited(\"PrivateNodeName\")>>\nHidden\n<<endif>>")

    assert {:error, :import_plan_has_errors} =
             Imports.prepare_import(ctx.scope, ctx.project, @private_filename, source)

    assert Repo.aggregate(ProjectImportAttempt, :count) == 0
    refute inspect(Repo.all(ProjectImportAttempt)) =~ "PrivateNodeName"
  end

  test "error fingerprints contain no caller identifiers or imported values" do
    metadata = %{
      format: "yarn",
      parser_version: "privacy-test",
      phase: "parse",
      error_code: "privacy_canary",
      exception_module: "none",
      filename: @private_filename,
      content: @private_content,
      user_id: 99,
      project_id: 88
    }

    assert ErrorDeduplicator.record(metadata)
    refute ErrorDeduplicator.record(metadata)

    changed_only_in_pii = %{metadata | filename: "another.yarn", content: "another person"}
    refute ErrorDeduplicator.record(changed_only_in_pii)
  end

  test "telemetry metadata never includes filenames, source content, or caller ids", ctx do
    handler_id = "import-privacy-#{System.unique_integer([:positive])}"
    test_pid = self()

    :ok =
      :telemetry.attach(
        handler_id,
        [:storyarn, :import, :prepare, :stop],
        fn _event, _measurements, metadata, _config ->
          send(test_pid, {:import_metadata, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    assert {:error, _reason} =
             Imports.prepare_import(
               ctx.scope,
               ctx.project,
               @private_filename,
               @private_content
             )

    assert_receive {:import_metadata, metadata}
    serialized = inspect(metadata)
    refute serialized =~ @private_filename
    refute serialized =~ @private_content
    refute Map.has_key?(metadata, :user_id)
    refute Map.has_key?(metadata, :project_id)
  end

  test "expires abandoned previews and removes their encrypted plans", ctx do
    assert {:ok, attempt, _preview} =
             Imports.prepare_import(ctx.scope, ctx.project, "project.yarn", yarn("Hello"))

    attempt
    |> Ecto.Changeset.change(expires_at: DateTime.utc_now() |> DateTime.add(-60, :second) |> DateTime.truncate(:second))
    |> Repo.update!()

    assert {:ok, 1} = Imports.expire_stale_imports()

    expired = Repo.get!(ProjectImportAttempt, attempt.id)
    assert expired.status == "expired"
    assert expired.stage == "expired"
    assert Repo.get_by!(PlanCleanupRequest, plan_storage_key: attempt.plan_storage_key).state == "completed"
    assert {:error, :import_plan_unavailable} = PlanStorage.load(attempt.plan_storage_key)
  end

  defp yarn(dialogue) do
    """
    title: Start
    ---
    #{dialogue}
    <<stop>>
    ===
    """
  end
end
