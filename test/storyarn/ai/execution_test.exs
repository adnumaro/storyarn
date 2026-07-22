defmodule Storyarn.AI.ExecutionTest do
  use Storyarn.DataCase, async: false

  import Ecto.Query
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.AI
  alias Storyarn.AI.Executor
  alias Storyarn.AI.Operation
  alias Storyarn.AI.Operations
  alias Storyarn.AI.Result
  alias Storyarn.AI.Results
  alias Storyarn.AI.RouteOption
  alias Storyarn.AI.RouteOptions
  alias Storyarn.AI.UsageEvent
  alias Storyarn.AI.WorkspacePolicyAudit
  alias Storyarn.Projects
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Workspaces
  alias StoryarnTest.AI.ContractTask
  alias StoryarnTest.AI.FakeSettlement

  setup do
    original_config = Application.get_env(:storyarn, ContractTask, [])
    Application.put_env(:storyarn, ContractTask, scenario: :success, execution_mode: :inline)

    user = user_fixture()
    scope = user_scope_fixture(user)
    workspace = workspace_fixture(user)
    project = project_fixture(user, %{workspace: workspace})

    FunWithFlags.enable(:ai_integrations, for_actor: user)
    assert {:ok, _policy} = AI.update_workspace_policy(scope, workspace.id, ["managed"])

    on_exit(fn ->
      Application.put_env(:storyarn, ContractTask, original_config)
      FunWithFlags.disable(:ai_integrations, for_actor: user)
    end)

    %{user: user, scope: scope, workspace: workspace, project: project}
  end

  test "preflight creates no operation and returns an opaque actor-bound route", ctx do
    intent = intent!(ctx, "preview only")

    assert {:ok, preflight} = AI.preflight(intent)
    assert preflight.operation_created == false
    assert [%{requested_route_ref: route_ref, lane: :managed, payer: "storyarn"}] = preflight.route_options
    assert is_binary(route_ref)
    assert Repo.aggregate(Operation, :count) == 0
    assert Repo.aggregate(Result, :count) == 0

    stored = Repo.one!(RouteOption)
    refute stored.token_hash == route_ref
    assert stored.actor_id == ctx.user.id
    assert stored.project_id == ctx.project.id
  end

  test "inline execution is durable, encrypted, actor-private and exactly-once", ctx do
    {operation, execute_intent} = execute_success!(ctx, "Private dialogue draft")

    assert operation.execution_status == "succeeded"
    assert operation.settlement_status == "committed"
    assert operation.user_disposition == nil
    assert Repo.aggregate(Operation, :count) == 1
    assert Repo.aggregate(UsageEvent, :count) == 1

    assert {:ok, %{"echo" => %{"text" => "Private dialogue draft"}}, fetched_operation} =
             AI.get_result(ctx.scope, operation.id)

    assert fetched_operation.id == operation.id

    raw =
      Repo.query!("SELECT input_encrypted, output_encrypted FROM ai_results WHERE operation_id = $1", [operation.id]).rows

    assert [[encrypted_input, encrypted_output]] = raw
    refute encrypted_input =~ "Private dialogue draft"
    refute encrypted_output =~ "Private dialogue draft"

    # The consumed route ref is safe to retry only through the same idempotency
    # key; operation lookup wins and the provider is not attempted again.
    assert {:ok, replayed} = AI.execute(execute_intent)
    assert replayed.id == operation.id
    assert Repo.aggregate(Operation, :count) == 1
    assert Repo.aggregate(UsageEvent, :count) == 1
  end

  test "route references reject another actor, changed input and policy drift", ctx do
    preflight_intent = intent!(ctx, "bound content")
    route_ref = route_ref!(preflight_intent)

    editor = user_fixture()
    membership_fixture(ctx.project, editor, "editor")
    FunWithFlags.enable(:ai_integrations, for_actor: editor)
    on_exit(fn -> FunWithFlags.disable(:ai_integrations, for_actor: editor) end)

    {:ok, actor_mismatch} =
      AI.new_intent(user_scope_fixture(editor), %{
        workspace_id: ctx.workspace.id,
        project_id: ctx.project.id,
        task_id: "contract.echo",
        input: %{"text" => "bound content"},
        requested_route_ref: route_ref,
        idempotency_key: "other-actor"
      })

    assert {:error, :route_ref_mismatch} = AI.execute(actor_mismatch)

    changed = execution_intent!(ctx, "changed content", route_ref, "changed-input")
    assert {:error, :route_ref_mismatch} = AI.execute(changed)

    assert {:ok, _policy} = AI.update_workspace_policy(ctx.scope, ctx.workspace.id, [])
    unchanged = execution_intent!(ctx, "bound content", route_ref, "stale-policy")
    assert {:error, :ai_disabled} = AI.execute(unchanged)
    assert Repo.aggregate(Operation, :count) == 0
  end

  test "expired route references never fall back", ctx do
    base = intent!(ctx, "expired")
    route_ref = route_ref!(base)
    Repo.update_all(RouteOption, set: [expires_at: DateTime.add(TimeHelpers.now(), -1, :second)])

    assert {:error, :route_ref_expired} =
             ctx |> execution_intent!("expired", route_ref, "expired-route") |> AI.execute()

    assert Repo.aggregate(Operation, :count) == 0
  end

  test "expired consumed route options are purged without deleting durable operation history", ctx do
    {operation, _intent} = execute_success!(ctx, "purge consumed route")
    route_option_id = operation.route_option_id

    Repo.update_all(
      from(option in RouteOption, where: option.id == ^route_option_id),
      set: [expires_at: DateTime.add(TimeHelpers.now(), -1, :second)]
    )

    assert RouteOptions.delete_expired() == 1
    refute Repo.get(RouteOption, route_option_id)

    retained = Repo.get!(Operation, operation.id)
    assert retained.route_option_id == nil
    assert retained.execution_status == "succeeded"
    assert retained.execution_route == operation.execution_route
    assert Repo.get_by(UsageEvent, operation_id: operation.id)
  end

  test "route references become stale when the registered price changes", ctx do
    route_ref = ctx |> intent!("price-bound") |> route_ref!()

    Application.put_env(:storyarn, ContractTask,
      scenario: :success,
      execution_mode: :inline,
      managed_price: %{id: "contract-free", version: 2, units: 1}
    )

    assert {:error, :route_ref_stale} =
             ctx |> execution_intent!("price-bound", route_ref, "stale-price") |> AI.execute()

    assert Repo.aggregate(Operation, :count) == 0
  end

  test "viewer and cross-workspace project access fail before any route or operation", ctx do
    viewer = user_fixture()
    membership_fixture(ctx.project, viewer, "viewer")
    FunWithFlags.enable(:ai_integrations, for_actor: viewer)
    on_exit(fn -> FunWithFlags.disable(:ai_integrations, for_actor: viewer) end)

    viewer_ctx = Map.put(ctx, :scope, user_scope_fixture(viewer))
    assert {:error, :missing_use_ai} = viewer_ctx |> intent!("no access") |> AI.preflight()

    foreign_owner = user_fixture()
    foreign_workspace = workspace_fixture(foreign_owner)
    foreign_project = project_fixture(foreign_owner, %{workspace: foreign_workspace})

    {:ok, forged} =
      AI.new_intent(ctx.scope, %{
        workspace_id: ctx.workspace.id,
        project_id: foreign_project.id,
        task_id: "contract.echo",
        input: %{"text" => "forged scope"}
      })

    assert {:error, :unauthorized} = AI.preflight(forged)
    assert Repo.aggregate(Operation, :count) == 0
  end

  test "classified provider failure releases settlement and stores no temporary content", ctx do
    Application.put_env(:storyarn, ContractTask, scenario: :failure, execution_mode: :inline)
    {operation, _intent} = execute!(ctx, "will fail")

    assert operation.execution_status == "failed"
    assert operation.settlement_status == "released"
    assert operation.error_classification == "provider_error"
    assert Repo.get_by(UsageEvent, operation_id: operation.id).status == "failed"
    refute Repo.get_by(Result, operation_id: operation.id)
  end

  test "unknown provider outcome is terminal, releases settlement and is never retried", ctx do
    Application.put_env(:storyarn, ContractTask, scenario: :unknown, execution_mode: :inline)
    {operation, execute_intent} = execute!(ctx, "unknown")

    assert operation.execution_status == "unknown"
    assert operation.settlement_status == "released"
    assert Repo.get_by(UsageEvent, operation_id: operation.id).status == "unknown"
    refute Repo.get_by(Result, operation_id: operation.id)

    assert {:ok, replayed} = AI.execute(execute_intent)
    assert replayed.id == operation.id
    assert replayed.execution_status == "unknown"
    assert Repo.aggregate(UsageEvent, :count) == 1
  end

  test "invalid provider metrics fail cleanly instead of stranding a running attempt", ctx do
    Application.put_env(:storyarn, ContractTask, scenario: :invalid_metrics, execution_mode: :inline)
    {operation, _intent} = execute!(ctx, "invalid metrics")

    assert operation.execution_status == "failed"
    assert operation.settlement_status == "released"
    assert operation.error_classification == "invalid_provider_response"
    assert Repo.get_by(UsageEvent, operation_id: operation.id).status == "failed"
    refute Repo.get_by(Result, operation_id: operation.id)
  end

  test "authorization is checked again before a queued provider call", ctx do
    Application.put_env(:storyarn, ContractTask, scenario: :success, execution_mode: :background)

    project_owner = user_fixture()
    foreign_workspace = workspace_fixture(project_owner)
    foreign_project = project_fixture(project_owner, %{workspace: foreign_workspace})
    membership = membership_fixture(foreign_project, ctx.user, "editor")
    owner_scope = user_scope_fixture(project_owner)
    assert {:ok, _policy} = AI.update_workspace_policy(owner_scope, foreign_workspace.id, ["managed"])

    foreign_ctx = %{ctx | workspace: foreign_workspace, project: foreign_project}
    {queued, _intent} = execute!(foreign_ctx, "queued")
    assert queued.execution_status == "queued"

    Repo.delete!(membership)
    assert :ok = Executor.run(queued.id)

    cancelled = Repo.get!(Operation, queued.id)
    assert cancelled.execution_status == "cancelled"
    assert cancelled.settlement_status == "released"
    refute Repo.get_by(UsageEvent, operation_id: queued.id)
    refute Repo.get_by(Result, operation_id: queued.id)
  end

  test "queued input does not expire before execution and result TTL starts on delivery", ctx do
    Application.put_env(:storyarn, ContractTask,
      scenario: :success,
      execution_mode: :background,
      result_ttl_seconds: 60
    )

    {queued, _intent} = execute!(ctx, "wait for worker")
    assert Repo.get_by!(Result, operation_id: queued.id).expires_at == nil

    before_execution = TimeHelpers.now()
    assert :ok = Executor.run(queued.id)

    result = Repo.get_by!(Result, operation_id: queued.id)
    assert DateTime.after?(result.expires_at, DateTime.add(before_execution, 55, :second))
  end

  test "exhausted worker retries terminalize a queued operation without provider usage", ctx do
    handler_id = "ai-operation-failed-#{System.unique_integer([:positive])}"
    test_pid = self()

    :ok =
      :telemetry.attach(
        handler_id,
        [:ai, :operation, :failed],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:operation_failed, event, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    Application.put_env(:storyarn, ContractTask, scenario: :success, execution_mode: :background)
    {queued, _intent} = execute!(ctx, "exhaust worker retries")

    assert :ok = Operations.fail_queued_after_retries(queued.id, :worker_retries_exhausted)

    failed = Repo.get!(Operation, queued.id)
    assert failed.execution_status == "failed"
    assert failed.settlement_status == "released"
    assert failed.error_classification == "worker_retries_exhausted"
    assert failed.completed_at
    refute Repo.get_by(UsageEvent, operation_id: queued.id)
    refute Repo.get_by(Result, operation_id: queued.id)

    assert_receive {:operation_failed, [:ai, :operation, :failed], %{count: 1}, metadata}
    assert metadata.task_id == "contract.echo"
    assert metadata.status == "failed"
    assert metadata.error_classification == "worker_retries_exhausted"
  end

  test "disabled and changed task contracts terminalize queued operations without provider access", ctx do
    Application.put_env(:storyarn, ContractTask, scenario: :success, execution_mode: :background)
    {disabled, _intent} = execute!(ctx, "disable queued task")

    Application.put_env(:storyarn, ContractTask, scenario: :success, execution_mode: :background, enabled: false)
    assert :ok = Executor.run(disabled.id)
    assert Repo.get!(Operation, disabled.id).execution_status == "cancelled"
    refute Repo.get_by(UsageEvent, operation_id: disabled.id)
    refute Repo.get_by(Result, operation_id: disabled.id)

    Application.put_env(:storyarn, ContractTask, scenario: :success, execution_mode: :background)
    {changed, _intent} = execute!(ctx, "change queued task")
    Application.put_env(:storyarn, ContractTask, scenario: :failure, execution_mode: :background)

    assert :ok = Executor.run(changed.id)
    changed = Repo.get!(Operation, changed.id)
    assert changed.execution_status == "cancelled"
    assert changed.error_classification == "task_contract_changed"
    refute Repo.get_by(UsageEvent, operation_id: changed.id)
  end

  test "provider process exits become terminal unknown outcomes", ctx do
    Application.put_env(:storyarn, ContractTask, scenario: :crash, execution_mode: :inline)
    {operation, _intent} = execute!(ctx, "provider exits")

    assert operation.execution_status == "unknown"
    assert operation.settlement_status == "released"
    assert Repo.get_by!(UsageEvent, operation_id: operation.id).status == "unknown"
    refute Repo.get_by(Result, operation_id: operation.id)
  end

  test "a cancellation requested during the provider attempt suppresses result delivery", ctx do
    Application.put_env(:storyarn, ContractTask, scenario: :success, execution_mode: :background)
    {queued, _intent} = execute!(ctx, "cancel during attempt")
    task = Enum.find(AI.registered_tasks(), &(&1.id == "contract.echo"))

    assert {:ok, running, ^task, route} = Operations.claim(queued.id)
    assert {:ok, usage} = Operations.start_attempt(running, task, route)
    assert {:ok, requested} = AI.cancel(ctx.scope, running.id)
    assert requested.cancellation_requested_at

    assert :ok = Operations.finish_success(running, usage, %{"echo" => %{"text" => "cancel during attempt"}}, %{})

    finished = Repo.get!(Operation, running.id)
    assert finished.execution_status == "succeeded"
    assert finished.settlement_status == "committed"
    assert finished.cancellation_requested_at
    refute Repo.get_by(Result, operation_id: running.id)
  end

  test "usage finalization rejects an event belonging to another operation", ctx do
    Application.put_env(:storyarn, ContractTask, scenario: :success, execution_mode: :background)
    {first, _intent} = execute!(ctx, "first operation")
    {second, _intent} = execute!(ctx, "second operation")
    task = Enum.find(AI.registered_tasks(), &(&1.id == "contract.echo"))

    assert {:ok, first, ^task, first_route} = Operations.claim(first.id)
    assert {:ok, first_usage} = Operations.start_attempt(first, task, first_route)
    assert {:ok, second, ^task, second_route} = Operations.claim(second.id)
    assert {:ok, second_usage} = Operations.start_attempt(second, task, second_route)

    assert {:error, :invalid_transition} = Operations.finish_failure(first, second_usage, :provider_error)
    assert :ok = Operations.finish_failure(first, first_usage, :provider_error)
    assert :ok = Operations.finish_failure(second, second_usage, :provider_error)
  end

  test "settlement failures are returned and roll finalization back", ctx do
    original = Application.get_env(:storyarn, FakeSettlement, [])
    on_exit(fn -> Application.put_env(:storyarn, FakeSettlement, original) end)

    Application.put_env(:storyarn, ContractTask, scenario: :success, execution_mode: :background)
    {queued, _intent} = execute!(ctx, "settlement failure")
    task = Enum.find(AI.registered_tasks(), &(&1.id == "contract.echo"))
    assert {:ok, running, ^task, route} = Operations.claim(queued.id)
    assert {:ok, usage} = Operations.start_attempt(running, task, route)

    Application.put_env(:storyarn, FakeSettlement, release: {:error, :ledger_unavailable})
    assert {:error, :ledger_unavailable} = Operations.finish_failure(running, usage, :provider_error)
    assert Repo.get!(Operation, running.id).execution_status == "running"
    assert Repo.get!(UsageEvent, usage.id).status == "running"
  end

  test "preflight and execution reject a mutated intent hash", ctx do
    intent = intent!(ctx, "hash-bound")
    tampered = %{intent | input_hash: String.duplicate("0", 64)}
    assert {:error, :input_hash_mismatch} = AI.preflight(tampered)

    route_ref = route_ref!(intent)
    execute_intent = execution_intent!(ctx, "hash-bound", route_ref, "tampered-hash")
    assert {:error, :input_hash_mismatch} = AI.execute(%{execute_intent | input_hash: String.duplicate("f", 64)})
    assert Repo.aggregate(Operation, :count) == 0
  end

  test "invalid route attempts do not consume accepted-operation rate allowance", ctx do
    original = Application.get_env(:storyarn, Storyarn.RateLimiter, [])
    on_exit(fn -> Application.put_env(:storyarn, Storyarn.RateLimiter, original) end)
    Application.put_env(:storyarn, Storyarn.RateLimiter, enabled: true)

    base = intent!(ctx, "rate-bound")
    route_ref = route_ref!(base)

    for index <- 1..25 do
      invalid = execution_intent!(ctx, "rate-bound", "invalid-route-#{index}", "invalid-route-#{index}")
      assert {:error, :route_ref_invalid} = AI.execute(invalid)
    end

    valid = execution_intent!(ctx, "rate-bound", route_ref, "valid-after-invalid-routes")
    assert {:ok, %Operation{execution_status: "succeeded"}} = AI.execute(valid)
  end

  test "a second external attempt is blocked before provider access", ctx do
    Application.put_env(:storyarn, ContractTask, scenario: :success, execution_mode: :background)
    {queued, _intent} = execute!(ctx, "attempt once")
    task = Enum.find(AI.registered_tasks(), &(&1.id == "contract.echo"))

    assert {:ok, running, ^task, route} = Operations.claim(queued.id)
    assert {:ok, usage} = Operations.start_attempt(running, task, route)
    assert {:error, :duplicate_external_attempt} = Operations.start_attempt(running, task, route)
    assert Repo.aggregate(UsageEvent, :count) == 1

    assert :ok = Operations.finish_failure(running, usage, :provider_error)
  end

  test "interrupted workers terminalize state without another external attempt", ctx do
    handler_id = "ai-operation-unknown-#{System.unique_integer([:positive])}"
    test_pid = self()

    :ok =
      :telemetry.attach(
        handler_id,
        [:ai, :operation, :unknown],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:operation_unknown, event, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    Application.put_env(:storyarn, ContractTask, scenario: :success, execution_mode: :background)
    {before_attempt, _intent} = execute!(ctx, "interrupt before attempt")
    task = Enum.find(AI.registered_tasks(), &(&1.id == "contract.echo"))
    assert {:ok, running_before, ^task, _route} = Operations.claim(before_attempt.id)

    assert :ok = Operations.recover_interrupted(running_before.id)
    recovered_before = Repo.get!(Operation, running_before.id)
    assert recovered_before.execution_status == "failed"
    assert recovered_before.settlement_status == "released"
    refute Repo.get_by(UsageEvent, operation_id: running_before.id)

    {after_attempt, _intent} = execute!(ctx, "interrupt after attempt")
    assert {:ok, running_after, ^task, route} = Operations.claim(after_attempt.id)
    assert {:ok, usage} = Operations.start_attempt(running_after, task, route)

    assert :ok = Operations.recover_interrupted(running_after.id)
    recovered_after = Repo.get!(Operation, running_after.id)
    assert recovered_after.execution_status == "unknown"
    assert recovered_after.settlement_status == "released"
    assert Repo.get!(UsageEvent, usage.id).status == "unknown"
    refute Repo.get_by(Result, operation_id: running_after.id)

    assert_receive {:operation_unknown, [:ai, :operation, :unknown], %{count: 1}, metadata}
    assert metadata.task_id == "contract.echo"
    assert metadata.status == "unknown"
    assert metadata.error_classification == "worker_interrupted"
  end

  test "cancellation after claim but before provider access releases without an attempt", ctx do
    Application.put_env(:storyarn, ContractTask, scenario: :success, execution_mode: :background)
    {queued, _intent} = execute!(ctx, "cancel before attempt")
    task = Enum.find(AI.registered_tasks(), &(&1.id == "contract.echo"))

    assert {:ok, running, ^task, route} = Operations.claim(queued.id)
    assert {:ok, cancelled} = AI.cancel(ctx.scope, running.id)
    assert cancelled.execution_status == "cancelled"
    assert cancelled.settlement_status == "released"
    assert {:error, :invalid_attempt_state} = Operations.start_attempt(running, task, route)
    refute Repo.get_by(UsageEvent, operation_id: running.id)
    refute Repo.get_by(Result, operation_id: running.id)
  end

  test "accept, dismiss and expiry are independent from execution status", ctx do
    {accepted, _intent} = execute_success!(ctx, "accept me")

    assert {:ok, :applied} =
             AI.apply_result(ctx.scope, accepted.id, nil, fn output, provenance ->
               assert output == %{"echo" => %{"text" => "accept me"}}
               assert provenance.operation_id == accepted.id
               {:ok, :applied}
             end)

    accepted = Repo.get!(Operation, accepted.id)
    assert accepted.execution_status == "succeeded"
    assert accepted.user_disposition == "accepted"
    refute Repo.get_by(Result, operation_id: accepted.id)

    {dismissed, _intent} = execute_success!(ctx, "dismiss me")
    assert {:ok, dismissed} = AI.dismiss_result(ctx.scope, dismissed.id)
    assert dismissed.user_disposition == "dismissed"

    {abandoned, _intent} = execute_success!(ctx, "expire me")

    Repo.update_all(from(result in Result, where: result.operation_id == ^abandoned.id),
      set: [expires_at: DateTime.add(TimeHelpers.now(), -1, :second)]
    )

    assert {:ok, %{expired_count: 1, failure_count: 0, more?: false}} = Results.expire()
    assert Repo.get!(Operation, abandoned.id).user_disposition == "abandoned"
  end

  test "result expiry is processed in bounded batches", ctx do
    {first, _intent} = execute_success!(ctx, "expire batch one")
    {second, _intent} = execute_success!(ctx, "expire batch two")
    expired_at = DateTime.add(TimeHelpers.now(), -1, :second)

    Repo.update_all(
      from(result in Result, where: result.operation_id in ^[first.id, second.id]),
      set: [expires_at: expired_at]
    )

    assert {:ok, %{expired_count: 1, failure_count: 0, more?: true}} =
             Results.expire(TimeHelpers.now(), batch_size: 1)

    assert Repo.aggregate(Result, :count) == 1

    assert {:ok, %{expired_count: 1, failure_count: 0, more?: false}} =
             Results.expire(TimeHelpers.now(), batch_size: 1)

    assert Repo.aggregate(Result, :count) == 0
  end

  test "project deletion purges encrypted content but preserves content-free operation and usage", ctx do
    {operation, _intent} = execute_success!(ctx, "temporary project content")
    assert Repo.get_by(Result, operation_id: operation.id)

    assert {:ok, deleted_project} = Projects.delete_project(ctx.project, ctx.user.id)
    refute Repo.get_by(Result, operation_id: operation.id)
    assert Repo.get!(Operation, operation.id).project_id == ctx.project.id
    assert Repo.get_by(UsageEvent, operation_id: operation.id)

    assert {:ok, _project} = Projects.permanently_delete_project(deleted_project)
    retained = Repo.get!(Operation, operation.id)
    assert retained.project_id == nil
    assert retained.project_id_snapshot == ctx.project.id
    assert Repo.get_by(UsageEvent, operation_id: operation.id)
  end

  test "workspace deletion purges temporary content and pseudonymizes retained audit", ctx do
    {operation, _intent} = execute_success!(ctx, "temporary workspace content")
    audit = Repo.get_by!(WorkspacePolicyAudit, workspace_id: ctx.workspace.id)

    assert {:ok, _workspace} = Workspaces.delete_workspace(ctx.workspace)
    refute Repo.get_by(Result, operation_id: operation.id)

    retained = Repo.get!(Operation, operation.id)
    assert retained.workspace_id == nil
    assert retained.project_id == nil
    assert retained.workspace_id_snapshot == ctx.workspace.id
    assert retained.project_id_snapshot == ctx.project.id
    assert Repo.get_by(UsageEvent, operation_id: operation.id)

    retained_audit = Repo.get!(WorkspacePolicyAudit, audit.id)
    assert retained_audit.workspace_id == nil
    assert retained_audit.workspace_id_snapshot == ctx.workspace.id
  end

  defp execute_success!(ctx, text) do
    {operation, intent} = execute!(ctx, text)
    assert operation.execution_status == "succeeded"
    {operation, intent}
  end

  defp execute!(ctx, text) do
    base = intent!(ctx, text)
    route_ref = route_ref!(base)
    execute_intent = execution_intent!(ctx, text, route_ref, "op-#{System.unique_integer([:positive])}")
    assert {:ok, operation} = AI.execute(execute_intent)
    {operation, execute_intent}
  end

  defp route_ref!(intent) do
    assert {:ok, %{route_options: [%{requested_route_ref: route_ref}]}} = AI.preflight(intent)
    route_ref
  end

  defp intent!(ctx, text) do
    assert {:ok, intent} =
             AI.new_intent(ctx.scope, %{
               workspace_id: ctx.workspace.id,
               project_id: ctx.project.id,
               task_id: "contract.echo",
               input: %{"text" => text}
             })

    intent
  end

  defp execution_intent!(ctx, text, route_ref, idempotency_key) do
    assert {:ok, intent} =
             AI.new_intent(ctx.scope, %{
               workspace_id: ctx.workspace.id,
               project_id: ctx.project.id,
               task_id: "contract.echo",
               input: %{"text" => text},
               requested_route_ref: route_ref,
               idempotency_key: idempotency_key
             })

    intent
  end
end
