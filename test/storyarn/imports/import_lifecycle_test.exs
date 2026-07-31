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
  alias Storyarn.Projects.ProjectMembership
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Sheets

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

  test "persists draft review, confirms an exact revision, and materializes an explicit alias mapping", ctx do
    source = alias_yarn()

    assert {:ok, ready, preview} =
             Imports.prepare_import(ctx.scope, ctx.project, "alias-review.yarn", source)

    initial_key = ready.plan_storage_key
    review = preview.import_review
    assert review["compatibility_warning_count"] == 1
    assert preview.issue_summary.warning_count == 1

    draft_decisions = [
      %{"speaker" => "Capsley", "action" => "create_sheet"}
    ]

    assert {:ok, drafted, draft_preview} =
             Imports.save_import_review(ctx.scope, ready.id, draft_decisions)

    refute drafted.plan_storage_key == initial_key
    assert draft_preview.import_review_draft["decisions"] == draft_decisions
    assert {:error, :import_plan_unavailable} = PlanStorage.load(initial_key)
    assert {:ok, drafted_plan} = PlanStorage.load(drafted.plan_storage_key)
    assert drafted_plan.data["import_review_draft"]["decisions"] == draft_decisions
    assert drafted_plan.metadata.warning_count == 1

    assert {:ok, resumed, resumed_preview} =
             Imports.resume_import(ctx.scope, ctx.project, ready.id)

    assert resumed.plan_storage_key == drafted.plan_storage_key
    assert resumed_preview.import_review_draft["decisions"] == draft_decisions
    assert resumed_preview.issue_summary.warning_count == 1

    decisions = [
      %{"speaker" => "Capsley", "action" => "create_sheet"},
      %{
        "speaker" => "Capsely",
        "action" => "map_to_sheet",
        "target_speaker" => "Capsley"
      }
    ]

    assert {:ok, resolved, resolved_preview, fingerprint} =
             Imports.resolve_import_review(ctx.scope, ready.id, true, decisions)

    refute resolved.plan_storage_key == drafted.plan_storage_key
    assert resolved_preview.counts.sheets == 1
    assert resolved_preview.issue_summary.warning_count == 1
    assert is_binary(fingerprint)
    assert {:error, :import_plan_unavailable} = PlanStorage.load(drafted.plan_storage_key)

    persisted = Repo.get!(ProjectImportAttempt, ready.id)
    persisted_text = inspect(Map.from_struct(persisted))
    refute persisted_text =~ "Capsley"
    refute persisted_text =~ "Capsely"
    refute persisted_text =~ "private"

    assert {:error, :invalid_import_review_selection} =
             Imports.enqueue_import(ctx.scope, ready.id, :rename,
               review_confirmation_fingerprint: "stale-browser-fingerprint"
             )

    assert Repo.get!(ProjectImportAttempt, ready.id).status == "ready"
    assert {:ok, _plan} = PlanStorage.load(resolved.plan_storage_key)

    assert {:ok, queued} =
             Imports.enqueue_import(ctx.scope, ready.id, :rename, review_confirmation_fingerprint: fingerprint)

    assert {:ok, completed} =
             Imports.perform_import(queued.id, attempt: 1, max_attempts: 3)

    assert completed.status == "completed"
    assert Enum.map(Sheets.list_all_sheets(ctx.project.id), & &1.name) == ["Capsley"]

    imported_nodes =
      ctx.project.id
      |> Flows.list_flows()
      |> Enum.flat_map(&Flows.list_nodes(&1.id))

    refute Enum.any?(imported_nodes, fn node ->
             Map.has_key?(node.data, "import_yarn_speaker") or
               Map.has_key?(node.data, "import_yarn_literal_text")
           end)
  end

  test "cleans a stored review revision when import access is revoked before pointer swap", ctx do
    co_owner = user_fixture()
    membership = membership_fixture(ctx.project, co_owner, "owner")
    co_owner_scope = Scope.for_user(co_owner)

    assert {:ok, ready, _preview} =
             Imports.prepare_import(
               co_owner_scope,
               ctx.project,
               "authorization-race.yarn",
               alias_yarn()
             )

    original_key = ready.plan_storage_key
    test_pid = self()

    decisions = [
      %{"speaker" => "Capsley", "action" => "create_sheet"},
      %{
        "speaker" => "Capsely",
        "action" => "map_to_sheet",
        "target_speaker" => "Capsley"
      }
    ]

    assert {:error, :unauthorized} =
             Imports.resolve_import_review(
               co_owner_scope,
               ready.id,
               true,
               decisions,
               plan_store: fn storage_key, plan ->
                 result = PlanStorage.store_at(storage_key, plan)
                 send(test_pid, {:stored_review_revision, storage_key})
                 Repo.delete!(membership)
                 result
               end
             )

    assert_receive {:stored_review_revision, rejected_key}
    refute rejected_key == original_key
    assert Repo.get!(ProjectImportAttempt, ready.id).plan_storage_key == original_key
    assert {:ok, _original_plan} = PlanStorage.load(original_key)
    assert {:error, :import_plan_unavailable} = PlanStorage.load(rejected_key)
  end

  test "resumes a ready import by rebuilding its preview and returns no preview after enqueue", ctx do
    assert {:ok, ready, original_preview} =
             Imports.prepare_import(ctx.scope, ctx.project, "project.yarn", yarn("Hello"))

    assert {:ok, resumed_ready, resumed_preview} =
             Imports.resume_import(ctx.scope, ctx.project, ready.id)

    assert resumed_ready.id == ready.id
    assert resumed_ready.status == "ready"
    assert resumed_preview == original_preview

    assert {:ok, queued} = Imports.enqueue_import(ctx.scope, ready.id, :rename)

    test_pid = self()

    assert {:ok, resumed_without_wake, nil} =
             Imports.resume_import(ctx.scope, ctx.project, queued.id,
               queue_notifier: fn payload ->
                 send(test_pid, {:unexpected_resume_queue_wakeup, payload})
                 :ok
               end
             )

    assert resumed_without_wake.id == queued.id
    refute_receive {:unexpected_resume_queue_wakeup, _payload}

    assert {:ok, resumed_queued, nil} =
             Imports.resume_import(ctx.scope, ctx.project, queued.id,
               wake_queue: true,
               queue_notifier: fn payload ->
                 send(test_pid, {:resume_queue_wakeup, payload})
                 :ok
               end
             )

    assert resumed_queued.id == queued.id
    assert resumed_queued.status == "queued"
    assert_receive {:resume_queue_wakeup, %{queue: "imports"}}
  end

  test "recovers the latest active attempt scoped to the current project and user", ctx do
    assert {:ok, _older, _preview} =
             Imports.prepare_import(ctx.scope, ctx.project, "older.yarn", yarn("Older"))

    assert {:ok, expected, expected_preview} =
             Imports.prepare_import(ctx.scope, ctx.project, "latest.yarn", yarn("Latest"))

    other_user = user_fixture()
    membership_fixture(ctx.project, other_user, "owner")

    assert {:ok, _other_user_attempt, _preview} =
             Imports.prepare_import(
               Scope.for_user(other_user),
               ctx.project,
               "other-user.yarn",
               yarn("Other user")
             )

    other_project = project_fixture(ctx.user)

    assert {:ok, _other_project_attempt, _preview} =
             Imports.prepare_import(
               ctx.scope,
               other_project,
               "other-project.yarn",
               yarn("Other project")
             )

    assert {:ok, recovered, recovered_preview} =
             Imports.resume_latest_active_import(ctx.scope, ctx.project)

    assert recovered.id == expected.id
    assert recovered.user_id == ctx.user.id
    assert recovered.project_id == ctx.project.id
    assert recovered_preview == expected_preview
  end

  test "latest active recovery returns no attempt and masks missing import access", ctx do
    assert {:ok, nil} = Imports.resume_latest_active_import(ctx.scope, ctx.project)

    viewer = user_fixture()
    membership_fixture(ctx.project, viewer, "viewer")

    assert {:error, :not_found} =
             Imports.resume_latest_active_import(Scope.for_user(viewer), ctx.project)
  end

  test "latest active recovery rechecks import access after loading the preview", ctx do
    co_owner = user_fixture()
    membership = membership_fixture(ctx.project, co_owner, "owner")
    co_owner_scope = Scope.for_user(co_owner)

    assert {:ok, ready, _preview} =
             Imports.prepare_import(co_owner_scope, ctx.project, "project.yarn", yarn("Hello"))

    assert {:error, :not_found} =
             Imports.resume_latest_active_import(co_owner_scope, ctx.project,
               plan_load: fn storage_key ->
                 result = PlanStorage.load(storage_key)
                 Repo.delete!(membership)
                 result
               end
             )

    assert Repo.get!(ProjectImportAttempt, ready.id).status == "ready"
  end

  test "resume plan loading failures are contained and reported without PII", ctx do
    handler_id = "import-resume-#{System.unique_integer([:positive])}"
    parser_version = "resume-#{System.unique_integer([:positive])}"
    test_pid = self()

    assert {:ok, ready, _preview} =
             Imports.prepare_import(
               ctx.scope,
               ctx.project,
               @private_filename,
               yarn(@private_content)
             )

    Repo.update_all(
      from(attempt in ProjectImportAttempt, where: attempt.id == ^ready.id),
      set: [parser_version: parser_version]
    )

    :ok =
      :telemetry.attach(
        handler_id,
        [:storyarn, :import, :error],
        fn _event, measurements, metadata, _config ->
          send(test_pid, {:resume_error, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    assert {:error, :import_plan_unavailable} =
             Imports.resume_latest_active_import(ctx.scope, ctx.project,
               plan_load: fn _storage_key -> raise @private_content end
             )

    assert_receive {:resume_error, %{count: 1}, %{phase: "resume", parser_version: ^parser_version} = metadata}

    assert metadata.error_code == "import_plan_unavailable"
    assert metadata.exception_module == "none"
    refute inspect(metadata) =~ @private_filename
    refute inspect(metadata) =~ @private_content
    refute Map.has_key?(metadata, :attempt_id)
    refute Map.has_key?(metadata, :project_id)
    refute Map.has_key?(metadata, :user_id)
  end

  test "resuming a completed import replays idempotent cache and PubSub side effects", ctx do
    assert {:ok, ready, _preview} =
             Imports.prepare_import(ctx.scope, ctx.project, "project.yarn", yarn("Hello"))

    assert {:ok, queued} = Imports.enqueue_import(ctx.scope, ready.id, :rename)
    assert {:ok, completed} = Imports.perform_import(queued.id, attempt: 1, max_attempts: 3)

    :ok = Collaboration.subscribe_dashboard(ctx.project.id)
    :ok = Imports.subscribe_project_imports(ctx.project)

    assert {:ok, resumed, nil} =
             Imports.resume_import(ctx.scope, ctx.project, completed.id)

    assert resumed.status == "completed"
    assert_received {:dashboard_invalidate, :all}
    assert_received {:project_import_updated, broadcast}
    assert broadcast.id == completed.id
    assert broadcast.status == "completed"
  end

  test "preserves a transient plan storage failure while resuming a ready import", ctx do
    assert {:ok, ready, _preview} =
             Imports.prepare_import(ctx.scope, ctx.project, "project.yarn", yarn("Hello"))

    assert :ok = PlanStorage.delete(ready.plan_storage_key)

    assert {:error, :import_plan_unavailable} =
             Imports.resume_import(ctx.scope, ctx.project, ready.id)
  end

  test "does not resurrect a ready preview after its retention deadline", ctx do
    assert {:ok, ready, _preview} =
             Imports.prepare_import(ctx.scope, ctx.project, "project.yarn", yarn("Hello"))

    ready
    |> Ecto.Changeset.change(expires_at: DateTime.add(TimeHelpers.now(), -60, :second))
    |> Repo.update!()

    assert {:ok, expired, nil} = Imports.resume_import(ctx.scope, ctx.project, ready.id)
    assert expired.status == "expired"
    assert {:error, :import_plan_unavailable} = PlanStorage.load(ready.plan_storage_key)
  end

  test "returns the current queued state when enqueue wins while a ready preview is loading", ctx do
    assert {:ok, ready, _preview} =
             Imports.prepare_import(ctx.scope, ctx.project, "project.yarn", yarn("Hello"))

    assert {:ok, resumed, nil} =
             Imports.resume_import(ctx.scope, ctx.project, ready.id,
               plan_load: fn storage_key ->
                 assert {:ok, queued} = Imports.enqueue_import(ctx.scope, ready.id, :rename)
                 assert queued.status == "queued"
                 PlanStorage.load(storage_key)
               end
             )

    assert resumed.status == "queued"
    assert resumed.oban_job_id
  end

  test "rechecks edit access after loading a ready preview", ctx do
    assert {:ok, ready, _preview} =
             Imports.prepare_import(ctx.scope, ctx.project, "project.yarn", yarn("Hello"))

    assert {:error, :not_found} =
             Imports.resume_import(ctx.scope, ctx.project, ready.id,
               plan_load: fn storage_key ->
                 result = PlanStorage.load(storage_key)

                 membership =
                   Repo.get_by!(ProjectMembership,
                     project_id: ctx.project.id,
                     user_id: ctx.user.id
                   )

                 Repo.delete!(membership)

                 result
               end
             )
  end

  test "expires and cleans an accepted attempt immediately when its Oban job is terminal", ctx do
    assert {:ok, ready, _preview} =
             Imports.prepare_import(ctx.scope, ctx.project, "project.yarn", yarn("Hello"))

    assert {:ok, queued} = Imports.enqueue_import(ctx.scope, ready.id, :rename)

    queued.oban_job_id
    |> then(&Repo.get!(Oban.Job, &1))
    |> Ecto.Changeset.change(state: "discarded", discarded_at: DateTime.utc_now())
    |> Repo.update!()

    assert {:ok, expired, nil} = Imports.resume_import(ctx.scope, ctx.project, queued.id)
    assert expired.status == "expired"
    assert {:error, :import_plan_unavailable} = PlanStorage.load(queued.plan_storage_key)
    assert Repo.get!(PlanCleanupRequest, queued.plan_cleanup_request_id).state == "completed"
  end

  test "expires and cleans an accepted attempt immediately when its Oban job is absent", ctx do
    assert {:ok, ready, _preview} =
             Imports.prepare_import(ctx.scope, ctx.project, "project.yarn", yarn("Hello"))

    assert {:ok, queued} = Imports.enqueue_import(ctx.scope, ready.id, :rename)
    queued.oban_job_id |> then(&Repo.get!(Oban.Job, &1)) |> Repo.delete!()

    assert {:ok, expired, nil} = Imports.resume_import(ctx.scope, ctx.project, queued.id)
    assert expired.status == "expired"
    assert {:error, :import_plan_unavailable} = PlanStorage.load(queued.plan_storage_key)
  end

  test "resume requires edit access and never returns an attempt from another project", ctx do
    other_project = project_fixture(ctx.user)

    assert {:ok, other_attempt, _preview} =
             Imports.prepare_import(ctx.scope, other_project, "other.yarn", yarn("Other"))

    assert {:error, :not_found} =
             Imports.resume_import(ctx.scope, ctx.project, other_attempt.id)

    assert {:error, :not_found} =
             Imports.resume_import(ctx.scope, ctx.project, -1)

    viewer = user_fixture()
    membership_fixture(ctx.project, viewer, "viewer")

    assert {:error, :not_found} =
             Imports.resume_import(Scope.for_user(viewer), ctx.project, other_attempt.id)

    assert {:error, :not_found} =
             Imports.resume_import(
               ctx.scope,
               ctx.project,
               9_007_199_254_740_992
             )
  end

  test "wakes the imports queue only after the durable enqueue transaction commits", ctx do
    assert {:ok, ready, _preview} =
             Imports.prepare_import(ctx.scope, ctx.project, "project.yarn", yarn("Hello"))

    test_pid = self()

    queue_notifier = fn payload ->
      persisted = Repo.get!(ProjectImportAttempt, ready.id)
      job = Repo.get!(Oban.Job, persisted.oban_job_id)

      send(
        test_pid,
        {:queue_wakeup, payload, Repo.in_transaction?(), persisted.status, job.state}
      )

      :ok
    end

    assert {:ok, queued} =
             Imports.enqueue_import(ctx.scope, ready.id, :rename, queue_notifier: queue_notifier)

    assert queued.status == "queued"
    assert_receive {:queue_wakeup, %{queue: "imports"}, false, "queued", "available"}
  end

  test "a queue wake-up failure never invalidates the durable job or leaks identifiers", ctx do
    handler_id = "import-queue-wakeup-#{System.unique_integer([:positive])}"
    test_pid = self()

    :ok =
      :telemetry.attach(
        handler_id,
        [:storyarn, :import, :error],
        fn _event, measurements, metadata, _config ->
          send(test_pid, {:queue_wakeup_error, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    notifiers = [
      fn _payload -> {:error, RuntimeError.exception(@private_content)} end,
      fn _payload -> raise @private_content end,
      fn _payload -> exit(@private_content) end
    ]

    queued_attempts =
      notifiers
      |> Enum.with_index(1)
      |> Enum.map(fn {notifier, index} ->
        assert {:ok, ready, _preview} =
                 Imports.prepare_import(
                   ctx.scope,
                   ctx.project,
                   "#{index}-#{@private_filename}",
                   yarn(@private_content)
                 )

        assert {:ok, queued} =
                 Imports.enqueue_import(ctx.scope, ready.id, :rename, queue_notifier: notifier)

        queued
      end)

    Enum.each(queued_attempts, fn queued ->
      assert Repo.get!(Oban.Job, queued.oban_job_id).state == "available"
      assert Repo.get!(ProjectImportAttempt, queued.id).status == "queued"
    end)

    assert_receive {:queue_wakeup_error, %{count: 1}, metadata}
    assert metadata.phase == "queue_wakeup"
    assert metadata.error_code == "queue_wakeup_failed"
    refute Map.has_key?(metadata, :project_id)
    refute Map.has_key?(metadata, :user_id)
    refute inspect(metadata) =~ @private_content
    refute inspect(metadata) =~ @private_filename
  end

  test "queues only the attempt id and materializes the encrypted plan idempotently", ctx do
    assert {:ok, ready, _preview} =
             Imports.prepare_import(ctx.scope, ctx.project, "project.yarn", yarn("Hello"))

    assert {:ok, queued} = Imports.enqueue_import(ctx.scope, ready.id, :rename)
    assert queued.status == "queued"

    job = Repo.get!(Oban.Job, queued.oban_job_id)
    assert job.args == %{"attempt_id" => ready.id}

    :ok = Collaboration.subscribe_dashboard(ctx.project.id)
    :ok = Imports.subscribe_project_imports(ctx.project)

    assert {:ok, completed} = Imports.perform_import(ready.id, attempt: 1, max_attempts: 3)
    assert completed.status == "completed"
    assert completed.stage == "completed"
    refute completed.user_id
    refute completed.idempotency_key
    assert {:error, :import_plan_unavailable} = PlanStorage.load(ready.plan_storage_key)
    assert Repo.get_by!(PlanCleanupRequest, plan_storage_key: ready.plan_storage_key).state == "completed"
    assert Enum.any?(Flows.list_flows(ctx.project.id), &(&1.name == "Start"))
    assert_received {:dashboard_invalidate, :all}
    assert_received {:project_import_updated, first_broadcast}
    assert first_broadcast.id == completed.id
    assert first_broadcast.status == "completed"

    assert {:ok, same_completed} = Imports.perform_import(ready.id, attempt: 2, max_attempts: 3)
    assert same_completed.id == completed.id
    assert Enum.count(Flows.list_flows(ctx.project.id), &(&1.name == "Start")) == 1
    assert_received {:dashboard_invalidate, :all}
    assert_received {:project_import_updated, second_broadcast}
    assert second_broadcast.id == completed.id
    assert second_broadcast.status == "completed"
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

  test "execution-error recovery replays side effects when a concurrent delivery already completed", ctx do
    assert {:ok, ready, _preview} =
             Imports.prepare_import(ctx.scope, ctx.project, "project.yarn", yarn("Hello"))

    assert {:ok, queued} = Imports.enqueue_import(ctx.scope, ready.id, :rename)

    :ok = Collaboration.subscribe_dashboard(ctx.project.id)
    :ok = Imports.subscribe_project_imports(ctx.project)

    result =
      Imports.perform_import(queued.id,
        attempt: 1,
        max_attempts: 3,
        before_materialization_transaction: fn ->
          completed =
            queued
            |> ProjectImportAttempt.running_changeset(TimeHelpers.now())
            |> Repo.update!()
            |> ProjectImportAttempt.completed_changeset(TimeHelpers.now(), %{})
            |> Repo.update!()

          send(self(), {:concurrent_completion, completed.status})
          raise "simulated late failure after concurrent completion"
        end
      )

    assert_received {:concurrent_completion, "completed"}
    assert {:ok, completed} = result

    assert completed.status == "completed"
    assert_received {:dashboard_invalidate, :all}
    assert_received {:project_import_updated, broadcast}
    assert broadcast.id == completed.id
    assert broadcast.status == "completed"
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
                String.contains?(query, ~s(FROM "projects")) and
                    String.contains?(query, "FOR UPDATE") ->
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

  test "locks the job before the attempt when cancelling a queued import", ctx do
    # `Oban.cancel_job/1` dispatches onto the caller's connection inside the
    # cancel transaction, so the job row must be locked before the attempt —
    # the order resume and the expiry sweep take. Attempt-then-job is an ABBA
    # inversion that can deadlock a concurrent resume, crashing its mount.
    assert {:ok, ready, _preview} =
             Imports.prepare_import(ctx.scope, ctx.project, "project.yarn", yarn("Hello"))

    assert {:ok, queued} = Imports.enqueue_import(ctx.scope, ready.id, :rename)

    handler_id = "import-cancel-queued-lock-order-#{System.unique_integer([:positive])}"
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
                String.contains?(query, ~s("oban_jobs")) and String.contains?(query, "FOR UPDATE") ->
                  :job

                String.contains?(query, ~s("project_import_attempts")) and
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

    assert {:ok, expired} = Imports.cancel_import(ctx.scope, queued.id)
    assert expired.status == "expired"

    lock_order =
      Enum.map(1..2, fn _index ->
        assert_receive {^marker, lock}
        lock
      end)

    assert lock_order == [:job, :attempt]
    refute_receive {^marker, _unexpected_lock}
  end

  test "refuses to cancel when the job binding moved after the pre-transaction read", ctx do
    assert {:ok, ready, _preview} =
             Imports.prepare_import(ctx.scope, ctx.project, "project.yarn", yarn("Hello"))

    # A reset racing an accept in another tab: the attempt gains its job after
    # `cancel_import` read it but before the transaction locked it. The row
    # locked up front is not this attempt's job, so the cancel must refuse
    # rather than cancel a job the transaction does not hold.
    assert {:error, :import_not_cancellable} =
             Imports.cancel_import(ctx.scope, ready.id,
               before_cancel_transaction: fn ->
                 assert {:ok, _queued} = Imports.enqueue_import(ctx.scope, ready.id, :rename)
               end
             )

    reloaded = Repo.get!(ProjectImportAttempt, ready.id)
    assert reloaded.status == "queued"
    assert reloaded.oban_job_id
  end

  test "rechecks import authorization at the cancellation boundary", ctx do
    co_owner = user_fixture()
    membership = membership_fixture(ctx.project, co_owner, "owner")
    co_owner_scope = Scope.for_user(co_owner)

    assert {:ok, ready, _preview} =
             Imports.prepare_import(co_owner_scope, ctx.project, "project.yarn", yarn("Hello"))

    assert {:error, :unauthorized} =
             Imports.cancel_import(co_owner_scope, ready.id,
               before_cancel_transaction: fn ->
                 # Demoted rather than removed: `remove_member/1` refuses to drop
                 # an owner, and a role change is the realistic way import access
                 # disappears mid-flight.
                 Repo.update!(Ecto.Changeset.change(membership, role: "viewer"))
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
    co_owner = user_fixture()
    membership = membership_fixture(ctx.project, co_owner, "owner")
    co_owner_scope = Scope.for_user(co_owner)

    assert {:ok, ready, _preview} =
             Imports.prepare_import(co_owner_scope, ctx.project, "project.yarn", yarn("Hello"))

    assert {:ok, queued} = Imports.enqueue_import(co_owner_scope, ready.id, :rename)

    assert {:ok, failed} =
             Imports.perform_import(queued.id,
               attempt: 1,
               max_attempts: 3,
               before_materialization_transaction: fn ->
                 Repo.update!(Ecto.Changeset.change(membership, role: "viewer"))
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

    mark_stale_for_sweep(queued, 60)

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

  test "reports an expiration transition failure without exposing import identifiers or source", ctx do
    handler_id = "import-expiration-#{System.unique_integer([:positive])}"
    test_pid = self()

    :ok =
      :telemetry.attach(
        handler_id,
        [:storyarn, :import, :error],
        fn _event, measurements, metadata, _config ->
          send(test_pid, {:expiration_error, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    assert {:ok, ready, _preview} =
             Imports.prepare_import(
               ctx.scope,
               ctx.project,
               @private_filename,
               yarn(@private_content)
             )

    parser_version = "expiration-#{System.unique_integer([:positive])}"

    Repo.update_all(
      from(attempt in ProjectImportAttempt, where: attempt.id == ^ready.id),
      set: [parser_version: parser_version]
    )

    on_exit(fn -> PlanStorage.delete(ready.plan_storage_key) end)

    mark_stale_for_sweep(ready, 60)

    ready.plan_cleanup_request_id
    |> then(&Repo.get!(PlanCleanupRequest, &1))
    |> Repo.delete!()

    assert {:ok, 0, 1} = Imports.expire_stale_imports()
    assert Repo.get!(ProjectImportAttempt, ready.id).status == "ready"

    assert_receive {:expiration_error, %{count: 1}, metadata}
    assert metadata.phase == "expiration"
    assert metadata.error_code == "plan_cleanup_request_unavailable"
    assert metadata.parser_version == parser_version
    refute Map.has_key?(metadata, :attempt_id)
    refute Map.has_key?(metadata, :project_id)
    refute Map.has_key?(metadata, :user_id)
    refute inspect(metadata) =~ @private_content
    refute inspect(metadata) =~ @private_filename
  end

  test "a poison expiration row backs off so a later row progresses with batch size one", ctx do
    assert {:ok, poison, _preview} =
             Imports.prepare_import(ctx.scope, ctx.project, "poison.yarn", yarn("Poison"))

    assert {:ok, valid, _preview} =
             Imports.prepare_import(ctx.scope, ctx.project, "valid.yarn", yarn("Valid"))

    mark_stale_for_sweep(poison, 120)
    mark_stale_for_sweep(valid, 60)

    poison.plan_cleanup_request_id
    |> then(&Repo.get!(PlanCleanupRequest, &1))
    |> Repo.delete!()

    on_exit(fn -> PlanStorage.delete(poison.plan_storage_key) end)

    assert {:ok, 0, 1} = Imports.expire_stale_imports(stale_batch_size: 1)

    deferred = Repo.get!(ProjectImportAttempt, poison.id)
    assert deferred.status == "ready"
    refute DateTime.after?(deferred.expires_at, TimeHelpers.now())
    assert DateTime.diff(TimeHelpers.now(), deferred.updated_at, :second) in 0..2

    assert {:ok, 1} = Imports.expire_stale_imports(stale_batch_size: 1)

    assert Repo.get!(ProjectImportAttempt, valid.id).status == "expired"
    assert {:error, :import_plan_unavailable} = PlanStorage.load(valid.plan_storage_key)
  end

  test "does not expire accepted attempts while their Oban jobs remain executable", ctx do
    past = DateTime.add(TimeHelpers.now(), -60, :second)
    now = TimeHelpers.now()
    oban_now = DateTime.utc_now()

    attempts =
      Enum.map(
        [
          {"queued", "available"},
          {"running", "executing"},
          {"retrying", "retryable"}
        ],
        fn {attempt_status, job_state} ->
          assert {:ok, ready, _preview} =
                   Imports.prepare_import(
                     ctx.scope,
                     ctx.project,
                     "#{attempt_status}.yarn",
                     yarn("Hello #{attempt_status}")
                   )

          assert {:ok, queued} = Imports.enqueue_import(ctx.scope, ready.id, :rename)

          attempt =
            case attempt_status do
              "queued" ->
                queued

              "running" ->
                queued
                |> ProjectImportAttempt.running_changeset(now)
                |> Repo.update!()

              "retrying" ->
                queued
                |> ProjectImportAttempt.retrying_changeset(%{
                  status: "retrying",
                  stage: "retrying",
                  error_code: "temporary_failure",
                  error_message: "The import will be retried automatically.",
                  error_report: %{"attempt" => 1, "max_attempts" => 3},
                  started_at: now,
                  expires_at: past
                })
                |> Repo.update!()
            end

          attempt =
            attempt
            |> Ecto.Changeset.change(expires_at: past)
            |> Repo.update!()

          job_changes =
            case job_state do
              "available" ->
                [state: "available"]

              "executing" ->
                [state: "executing", attempt: 1, attempted_at: oban_now]

              "retryable" ->
                [state: "retryable", attempt: 1, attempted_at: oban_now, scheduled_at: oban_now]
            end

          attempt.oban_job_id
          |> then(&Repo.get!(Oban.Job, &1))
          |> Ecto.Changeset.change(job_changes)
          |> Repo.update!()

          attempt
        end
      )

    assert {:ok, 0} =
             Imports.expire_stale_imports(queue_notifier: fn _payload -> :ok end)

    Enum.each(attempts, fn attempt ->
      persisted = Repo.get!(ProjectImportAttempt, attempt.id)
      assert persisted.status == attempt.status
      assert {:ok, _plan} = PlanStorage.load(attempt.plan_storage_key)
    end)
  end

  test "caps accepted-plan retention at the absolute deadline", ctx do
    assert {:ok, ready, _preview} =
             Imports.prepare_import(ctx.scope, ctx.project, "project.yarn", yarn("Hello"))

    inserted_at = DateTime.add(TimeHelpers.now(), -(47 * 60 * 60), :second)

    Repo.update_all(
      from(attempt in ProjectImportAttempt, where: attempt.id == ^ready.id),
      set: [inserted_at: inserted_at, updated_at: inserted_at]
    )

    assert {:ok, queued} = Imports.enqueue_import(ctx.scope, ready.id, :rename)

    seconds_until_expiration = DateTime.diff(queued.expires_at, TimeHelpers.now(), :second)
    assert seconds_until_expiration in 3_500..3_600

    on_exit(fn -> PlanStorage.delete(queued.plan_storage_key) end)
  end

  test "cancels an executable job and deletes its plan after the absolute deadline", ctx do
    assert {:ok, ready, _preview} =
             Imports.prepare_import(ctx.scope, ctx.project, "project.yarn", yarn("Hello"))

    assert {:ok, queued} = Imports.enqueue_import(ctx.scope, ready.id, :rename)

    overdue_at = DateTime.add(TimeHelpers.now(), -(3 * 24 * 60 * 60), :second)
    rolling_expiration = DateTime.add(TimeHelpers.now(), 24 * 60 * 60, :second)

    Repo.update_all(
      from(attempt in ProjectImportAttempt, where: attempt.id == ^queued.id),
      set: [
        inserted_at: overdue_at,
        updated_at: overdue_at,
        expires_at: rolling_expiration
      ]
    )

    assert Repo.get!(Oban.Job, queued.oban_job_id).state == "available"
    assert {:ok, 1} = Imports.expire_stale_imports()

    assert Repo.get!(Oban.Job, queued.oban_job_id).state == "cancelled"

    expired = Repo.get!(ProjectImportAttempt, queued.id)
    assert expired.status == "expired"
    refute expired.user_id
    refute expired.idempotency_key
    assert {:error, :import_plan_unavailable} = PlanStorage.load(queued.plan_storage_key)
    assert Repo.get!(PlanCleanupRequest, queued.plan_cleanup_request_id).state == "completed"
  end

  test "an absolute-deadline cancellation failure backs off without deleting the plan", ctx do
    handler_id = "import-cancellation-#{System.unique_integer([:positive])}"
    parser_version = "cancel-#{System.unique_integer([:positive])}"
    test_pid = self()

    :ok =
      :telemetry.attach(
        handler_id,
        [:storyarn, :import, :error],
        fn _event, measurements, metadata, _config ->
          send(test_pid, {:cancellation_error, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    assert {:ok, ready, _preview} =
             Imports.prepare_import(ctx.scope, ctx.project, "project.yarn", yarn("Hello"))

    assert {:ok, queued} = Imports.enqueue_import(ctx.scope, ready.id, :rename)

    overdue_at = DateTime.add(TimeHelpers.now(), -(3 * 24 * 60 * 60), :second)

    Repo.update_all(
      from(attempt in ProjectImportAttempt, where: attempt.id == ^queued.id),
      set: [
        parser_version: parser_version,
        inserted_at: overdue_at,
        updated_at: overdue_at,
        expires_at: DateTime.add(TimeHelpers.now(), 24 * 60 * 60, :second)
      ]
    )

    on_exit(fn -> PlanStorage.delete(queued.plan_storage_key) end)

    assert {:ok, 0, 1} =
             Imports.expire_stale_imports(job_cancel: fn _job_id -> {:error, @private_content} end)

    deferred = Repo.get!(ProjectImportAttempt, queued.id)
    assert deferred.status == "queued"
    assert DateTime.after?(deferred.expires_at, TimeHelpers.now())
    assert Repo.get!(Oban.Job, queued.oban_job_id).state == "available"
    assert {:ok, _plan} = PlanStorage.load(queued.plan_storage_key)

    assert_receive {:cancellation_error, %{count: 1}, metadata}
    assert metadata.phase == "expiration"
    assert metadata.error_code == "import_job_cancellation_failed"
    assert metadata.parser_version == parser_version
    refute inspect(metadata) =~ @private_content
    refute Map.has_key?(metadata, :attempt_id)
    refute Map.has_key?(metadata, :project_id)
    refute Map.has_key?(metadata, :user_id)
  end

  test "expires an orphaned accepted attempt whose Oban job is already terminal", ctx do
    assert {:ok, ready, _preview} =
             Imports.prepare_import(ctx.scope, ctx.project, "project.yarn", yarn("Hello"))

    assert {:ok, queued} = Imports.enqueue_import(ctx.scope, ready.id, :rename)

    mark_stale_for_sweep(queued, 60)

    queued.oban_job_id
    |> then(&Repo.get!(Oban.Job, &1))
    |> Ecto.Changeset.change(
      state: "completed",
      attempt: 1,
      attempted_at: DateTime.utc_now(),
      completed_at: DateTime.utc_now()
    )
    |> Repo.update!()

    assert {:ok, 1} =
             Imports.expire_stale_imports(queue_notifier: fn _payload -> :ok end)

    expired = Repo.get!(ProjectImportAttempt, queued.id)
    assert expired.status == "expired"
    refute Enum.any?(Flows.list_flows(ctx.project.id), &(&1.name == "Start"))
    assert {:error, :import_plan_unavailable} = PlanStorage.load(queued.plan_storage_key)
    assert Repo.get!(PlanCleanupRequest, queued.plan_cleanup_request_id).state == "completed"
  end

  test "executable attempts cannot starve later terminal attempts from the expiration batch", ctx do
    assert {:ok, ready_executable, _preview} =
             Imports.prepare_import(ctx.scope, ctx.project, "executable.yarn", yarn("Executable"))

    assert {:ok, executable} = Imports.enqueue_import(ctx.scope, ready_executable.id, :rename)

    mark_stale_for_sweep(executable, 120)

    assert {:ok, ready_terminal, _preview} =
             Imports.prepare_import(ctx.scope, ctx.project, "terminal.yarn", yarn("Terminal"))

    assert {:ok, terminal} = Imports.enqueue_import(ctx.scope, ready_terminal.id, :rename)

    mark_stale_for_sweep(terminal, 60)

    terminal.oban_job_id
    |> then(&Repo.get!(Oban.Job, &1))
    |> Ecto.Changeset.change(
      state: "completed",
      attempt: 1,
      attempted_at: DateTime.utc_now(),
      completed_at: DateTime.utc_now()
    )
    |> Repo.update!()

    assert {:ok, 1} =
             Imports.expire_stale_imports(
               stale_batch_size: 1,
               queue_notifier: fn _payload -> :ok end
             )

    assert Repo.get!(ProjectImportAttempt, executable.id).status == "queued"
    assert Repo.get!(ProjectImportAttempt, terminal.id).status == "expired"
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

    assert {:ok, 0, 100} =
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

  test "cleanup deletion failures are counted and reported without PII", _ctx do
    handler_id = "import-cleanup-#{System.unique_integer([:positive])}"
    parser_version = "cleanup-#{System.unique_integer([:positive])}"
    test_pid = self()

    :ok =
      :telemetry.attach(
        handler_id,
        [:storyarn, :import, :error],
        fn _event, measurements, metadata, _config ->
          send(test_pid, {:cleanup_error, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    now = TimeHelpers.now()

    %PlanCleanupRequest{}
    |> PlanCleanupRequest.reservation_changeset(%{
      plan_storage_key: "imports/plans/#{Ecto.UUID.generate()}.plan.enc",
      format: "yarn",
      parser_version: parser_version,
      state: "pending",
      cleanup_after: DateTime.add(now, -60, :second)
    })
    |> Repo.insert!()

    assert {:ok, 0, 1} =
             Imports.expire_stale_imports(plan_delete: fn _storage_key -> {:error, @private_content} end)

    assert_receive {:cleanup_error, %{count: 1}, metadata}

    assert metadata == %{
             format: "yarn",
             parser_version: parser_version,
             phase: "cleanup",
             error_code: "plan_cleanup_failed",
             exception_module: "none"
           }

    refute inspect(metadata) =~ @private_content
    refute inspect(metadata) =~ @private_filename
    refute Map.has_key?(metadata, :project_id)
    refute Map.has_key?(metadata, :user_id)
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

    mark_stale_for_sweep(attempt, 60)

    assert {:ok, 1} = Imports.expire_stale_imports()

    expired = Repo.get!(ProjectImportAttempt, attempt.id)
    assert expired.status == "expired"
    assert expired.stage == "expired"
    assert Repo.get_by!(PlanCleanupRequest, plan_storage_key: attempt.plan_storage_key).state == "completed"
    assert {:error, :import_plan_unavailable} = PlanStorage.load(attempt.plan_storage_key)
  end

  describe "owner-only import authorization" do
    setup ctx do
      editor = user_fixture()
      membership_fixture(ctx.project, editor, "editor")
      %{editor_scope: Scope.for_user(editor)}
    end

    test "an editor cannot prepare an import", ctx do
      assert {:error, :unauthorized} =
               Imports.prepare_import(ctx.editor_scope, ctx.project, "p.yarn", yarn("Hello"))
    end

    test "an editor cannot enqueue, resume or cancel an owner's import", ctx do
      assert {:ok, ready, _preview} =
               Imports.prepare_import(ctx.scope, ctx.project, "p.yarn", yarn("Hello"))

      assert {:error, :unauthorized} = Imports.enqueue_import(ctx.editor_scope, ready.id, :rename)
      # Both resume paths mask the missing permission as `:not_found` rather
      # than confirming an import exists.
      assert {:error, :not_found} = Imports.resume_import(ctx.editor_scope, ctx.project, ready.id)

      assert {:error, :not_found} =
               Imports.resume_latest_active_import(ctx.editor_scope, ctx.project)

      assert {:error, :unauthorized} = Imports.cancel_import(ctx.editor_scope, ready.id)

      assert Repo.get!(ProjectImportAttempt, ready.id).status == "ready"
    end
  end

  describe "cancelling an accepted import" do
    test "a queued attempt is cancellable and releases its plan", ctx do
      assert {:ok, ready, _preview} =
               Imports.prepare_import(ctx.scope, ctx.project, "p.yarn", yarn("Hello"))

      assert {:ok, queued} = Imports.enqueue_import(ctx.scope, ready.id, :rename)
      assert queued.status == "queued"

      assert {:ok, cancelled} = Imports.cancel_import(ctx.scope, queued.id)

      assert cancelled.status == "expired"
      assert cancelled.error_code == "import_cancelled"
      refute cancelled.user_id

      # No longer active, so `resume_latest_active_import/2` cannot bring it back
      # on the next mount — which is what made reset look like it had worked.
      assert {:ok, nil} = Imports.resume_latest_active_import(ctx.scope, ctx.project)
    end

    test "a cancelled queued import materializes nothing if its worker still runs", ctx do
      assert {:ok, ready, _preview} =
               Imports.prepare_import(ctx.scope, ctx.project, "p.yarn", yarn("Hello"))

      assert {:ok, queued} = Imports.enqueue_import(ctx.scope, ready.id, :rename)
      assert {:ok, _cancelled} = Imports.cancel_import(ctx.scope, queued.id)

      assert {:ok, terminal} = Imports.perform_import(queued.id, attempt: 1, max_attempts: 3)

      assert terminal.status == "expired"
      assert Flows.list_flows(ctx.project.id) == []
    end

    test "a running attempt is not cancellable", ctx do
      assert {:ok, ready, _preview} =
               Imports.prepare_import(ctx.scope, ctx.project, "p.yarn", yarn("Hello"))

      assert {:ok, queued} = Imports.enqueue_import(ctx.scope, ready.id, :rename)

      running =
        queued
        |> ProjectImportAttempt.running_changeset(TimeHelpers.now())
        |> Repo.update!()

      assert {:error, :import_not_cancellable} = Imports.cancel_import(ctx.scope, running.id)
      assert Repo.get!(ProjectImportAttempt, running.id).status == "running"
    end
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

  defp alias_yarn do
    """
    title: Start
    ---
    Capsley: First line.
    Capsley: Second line.
    Capsley: Third line.
    Capsely: Possible typo.
    <<stop>>
    ===
    """
  end

  defp mark_stale_for_sweep(attempt, seconds_ago) do
    now = TimeHelpers.now()
    expires_at = DateTime.add(now, -seconds_ago, :second)
    updated_at = DateTime.add(now, -600, :second)

    Repo.update_all(
      from(candidate in ProjectImportAttempt, where: candidate.id == ^attempt.id),
      set: [expires_at: expires_at, updated_at: updated_at]
    )

    Repo.get!(ProjectImportAttempt, attempt.id)
  end
end
