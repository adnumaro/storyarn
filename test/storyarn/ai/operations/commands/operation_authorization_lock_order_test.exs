defmodule Storyarn.AI.Operations.Commands.OperationAuthorizationLockOrderTest do
  use ExUnit.Case, async: false

  import Ecto.Query, warn: false
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.WorkspacesFixtures

  alias Ecto.Adapters.SQL.Sandbox
  alias Storyarn.Accounts.User
  alias Storyarn.AI
  alias Storyarn.AI.CredentialRef
  alias Storyarn.AI.ExecutionRoute
  alias Storyarn.AI.Governance
  alias Storyarn.AI.Operation
  alias Storyarn.AI.Operations
  alias Storyarn.AI.OperatorAlert
  alias Storyarn.AI.Result
  alias Storyarn.AI.RouteOption
  alias Storyarn.AI.Task, as: AITask
  alias Storyarn.AI.UsageEvent
  alias Storyarn.AI.WorkspacePolicy
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Projects.Project
  alias Storyarn.Projects.ProjectMembership
  alias Storyarn.Repo
  alias Storyarn.Workspaces.Workspace
  alias Storyarn.Workspaces.WorkspaceMembership
  alias StoryarnTest.AI.ContractTask

  @timeout 15_000
  @blocked_timeout 5_000

  test "execute retains Workspace -> Project -> memberships before waiting on RouteOption" do
    with_queued_operation(fn ctx ->
      assert {:ok, base_intent} =
               AI.new_intent(ctx.scope, %{
                 workspace_id: ctx.workspace.id,
                 project_id: ctx.project.id,
                 task_id: "contract.echo",
                 input: %{"text" => "route option lock order"}
               })

      assert {:ok, %{route_options: [%{requested_route_ref: route_ref}]}} =
               AI.preflight(base_intent)

      assert {:ok, execute_intent} =
               AI.new_intent(ctx.scope, %{
                 workspace_id: ctx.workspace.id,
                 project_id: ctx.project.id,
                 task_id: "contract.echo",
                 input: %{"text" => "route option lock order"},
                 requested_route_ref: route_ref,
                 idempotency_key: "route-lock-order-#{Ecto.UUID.generate()}"
               })

      route_option =
        Repo.one!(
          from(option in RouteOption,
            where:
              option.actor_id == ^ctx.user.id and
                option.input_hash == ^execute_intent.input_hash and
                is_nil(option.consumed_by_operation_id),
            order_by: [desc: option.id],
            limit: 1
          )
        )

      result =
        run_behind_route_option_gate(ctx, route_option.id, :execute, fn ->
          AI.execute(execute_intent)
        end)

      assert {:ok, %Operation{execution_status: "queued"} = operation} = result
      assert Repo.get!(RouteOption, route_option.id).consumed_by_operation_id == operation.id
    end)
  end

  test "execute rejects a feature flag disabled while it waits on RouteOption" do
    with_queued_operation(fn ctx ->
      {execute_intent, route_option} = execution_intent_with_route_option(ctx, "volatile route authorization")

      result =
        run_behind_route_option_gate(
          ctx,
          route_option.id,
          :volatile_execute,
          fn ->
            AI.execute(execute_intent)
          end,
          while_blocked: fn -> FunWithFlags.disable(:ai_integrations, for_actor: ctx.user) end
        )

      assert {:error, :feature_disabled} = result
      refute Repo.get_by(Operation, idempotency_key: execute_intent.idempotency_key)
      refute Repo.get!(RouteOption, route_option.id).consumed_by_operation_id
    end)
  end

  test "execute preserves invalid-reference semantics when RouteOption disappears while waiting" do
    with_queued_operation(fn ctx ->
      {execute_intent, route_option} = execution_intent_with_route_option(ctx, "deleted route option")

      result =
        run_behind_route_option_gate(
          ctx,
          route_option.id,
          :deleted_route_option,
          fn -> AI.execute(execute_intent) end,
          release: :delete
        )

      assert {:error, :route_ref_invalid} = result
      refute Repo.get(RouteOption, route_option.id)
      refute Repo.get_by(Operation, idempotency_key: execute_intent.idempotency_key)
    end)
  end

  test "claim retains Workspace -> Project -> memberships before waiting on Operation" do
    with_queued_operation(fn ctx ->
      result =
        run_behind_operation_gate(ctx, :claim, fn ->
          Operations.claim(ctx.operation.id)
        end)

      assert {:ok, %Operation{execution_status: "running"}, %AITask{}, %ExecutionRoute{}} = result
    end)
  end

  test "feature-denied claim still retains Workspace before waiting on Operation" do
    with_queued_operation(fn ctx ->
      FunWithFlags.disable(:ai_integrations, for_actor: ctx.user)

      result =
        run_behind_operation_gate(
          ctx,
          :feature_denied_claim,
          fn -> Operations.claim(ctx.operation.id) end,
          locks: :workspace
        )

      assert {:cancelled, %Operation{error_classification: "feature_disabled"}} = result
    end)
  end

  test "claim rejects a feature flag disabled while it waits on Operation" do
    with_queued_operation(fn ctx ->
      result =
        run_behind_operation_gate(
          ctx,
          :feature_disabled_while_claim_waited,
          fn -> Operations.claim(ctx.operation.id) end,
          while_blocked: fn -> FunWithFlags.disable(:ai_integrations, for_actor: ctx.user) end
        )

      assert {:cancelled, %Operation{error_classification: "feature_disabled"}} = result
    end)
  end

  test "claim re-fetches the task contract after acquiring Operation" do
    with_queued_operation(fn ctx ->
      result =
        run_behind_operation_gate(
          ctx,
          :changed_task_claim,
          fn -> Operations.claim(ctx.operation.id) end,
          while_blocked: fn ->
            Application.put_env(:storyarn, ContractTask,
              scenario: :success,
              execution_mode: :background,
              context_version: "changed-while-claim-waited"
            )
          end
        )

      assert {:cancelled, %Operation{error_classification: "task_contract_changed"}} = result
    end)
  end

  test "start_attempt retains Workspace -> Project -> memberships before waiting on Operation" do
    with_queued_operation(fn ctx ->
      assert {:ok, running, task, route} = Operations.claim(ctx.operation.id)

      result =
        run_behind_operation_gate(%{ctx | operation: running}, :start_attempt, fn ->
          Operations.start_attempt(running, task, route)
        end)

      assert {:ok, %UsageEvent{}, _credential} = result
    end)
  end

  test "start_attempt rejects task or route arguments that do not match the claimed operation" do
    with_queued_operation(fn ctx ->
      assert {:ok, running, task, route} = Operations.claim(ctx.operation.id)
      mismatched_task = %{task | context_version: "#{task.context_version}-mismatched"}
      mismatched_route = %{route | model: "#{route.model}-mismatched"}

      assert {:error, :attempt_contract_mismatch} =
               Operations.start_attempt(running, mismatched_task, route)

      assert {:error, :attempt_contract_mismatch} =
               Operations.start_attempt(running, task, mismatched_route)

      assert %Operation{
               execution_status: "running",
               external_attempt_started_at: nil,
               settlement_status: "reserved"
             } = Repo.get!(Operation, running.id)

      refute Repo.get_by(UsageEvent, operation_id: running.id)
    end)
  end

  test "finish_success retains upstream authorization locks before waiting on Operation" do
    with_queued_operation(fn ctx ->
      assert {:ok, running, task, route} = Operations.claim(ctx.operation.id)
      assert {:ok, usage, _credential} = Operations.start_attempt(running, task, route)

      result =
        run_behind_operation_gate(%{ctx | operation: running}, :finish_success, fn ->
          Operations.finish_success(running, usage, %{"echo" => %{"text" => "lock order"}}, %{})
        end)

      assert :ok = result
      assert Repo.get!(Operation, running.id).execution_status == "succeeded"
    end)
  end

  test "already non-deliverable finish retains technical Workspace before waiting on Operation" do
    with_queued_operation(fn ctx ->
      assert {:ok, running, task, route} = Operations.claim(ctx.operation.id)
      assert {:ok, usage, _credential} = Operations.start_attempt(running, task, route)

      Application.put_env(:storyarn, ContractTask,
        scenario: :success,
        execution_mode: :background,
        context_version: "changed-before-finish"
      )

      result =
        run_behind_operation_gate(
          %{ctx | operation: running},
          :already_non_deliverable_finish,
          fn -> Operations.finish_success(running, usage, %{"echo" => %{"text" => "discarded"}}, %{}) end,
          locks: :workspace
        )

      assert_discarded_success(result, running.id)
    end)
  end

  test "finish re-fetches the task contract after acquiring Operation" do
    with_queued_operation(fn ctx ->
      assert {:ok, running, task, route} = Operations.claim(ctx.operation.id)
      assert {:ok, usage, _credential} = Operations.start_attempt(running, task, route)

      result =
        run_behind_operation_gate(
          %{ctx | operation: running},
          :non_deliverable_finish,
          fn -> Operations.finish_success(running, usage, %{"echo" => %{"text" => "discarded"}}, %{}) end,
          while_blocked: fn ->
            Application.put_env(:storyarn, ContractTask,
              scenario: :success,
              execution_mode: :background,
              context_version: "changed-while-finish-waited"
            )
          end
        )

      assert_discarded_success(result, running.id)
    end)
  end

  test "failure before an attempt retains technical Workspace before waiting on Operation" do
    with_queued_operation(fn ctx ->
      assert {:ok, running, _task, _route} = Operations.claim(ctx.operation.id)

      result =
        run_behind_operation_gate(
          %{ctx | operation: running},
          :fail_before_attempt,
          fn ->
            Operations.fail_before_attempt(running, :provider_unavailable)
          end,
          locks: :workspace
        )

      assert :ok = result
      assert Repo.get!(Operation, running.id).execution_status == "failed"
    end)
  end

  test "finish_failure retains technical Workspace before waiting on Operation" do
    with_queued_operation(fn ctx ->
      assert {:ok, running, task, route} = Operations.claim(ctx.operation.id)
      assert {:ok, usage, _credential} = Operations.start_attempt(running, task, route)

      result =
        run_behind_operation_gate(
          %{ctx | operation: running},
          :finish_failure,
          fn ->
            Operations.finish_failure(running, usage, :provider_error)
          end,
          locks: :workspace
        )

      assert :ok = result
      assert Repo.get!(Operation, running.id).execution_status == "failed"
      assert Repo.get!(UsageEvent, usage.id).status == "failed"
    end)
  end

  test "finish_unknown retains technical Workspace before waiting on Operation" do
    with_queued_operation(fn ctx ->
      assert {:ok, running, task, route} = Operations.claim(ctx.operation.id)
      assert {:ok, usage, _credential} = Operations.start_attempt(running, task, route)

      result =
        run_behind_operation_gate(
          %{ctx | operation: running},
          :finish_unknown,
          fn ->
            Operations.finish_unknown(running, usage, :provider_timeout)
          end,
          locks: :workspace
        )

      assert :ok = result
      assert Repo.get!(Operation, running.id).execution_status == "unknown"
      assert Repo.get!(UsageEvent, usage.id).status == "unknown"
    end)
  end

  test "interrupted recovery retains technical Workspace before waiting on Operation" do
    with_queued_operation(fn ctx ->
      assert {:ok, running, task, route} = Operations.claim(ctx.operation.id)
      assert {:ok, usage, _credential} = Operations.start_attempt(running, task, route)

      result =
        run_behind_operation_gate(
          %{ctx | operation: running},
          :recover_interrupted,
          fn ->
            Operations.recover_interrupted(running.id)
          end,
          locks: :workspace
        )

      assert :ok = result
      assert Repo.get!(Operation, running.id).execution_status == "unknown"
      assert Repo.get!(UsageEvent, usage.id).status == "unknown"
    end)
  end

  test "queued retry exhaustion retains technical Workspace before waiting on Operation" do
    with_queued_operation(fn ctx ->
      result =
        run_behind_operation_gate(
          ctx,
          :fail_queued_after_retries,
          fn ->
            Operations.fail_queued_after_retries(ctx.operation.id, :worker_retries_exhausted)
          end,
          locks: :workspace
        )

      assert :ok = result
      assert Repo.get!(Operation, ctx.operation.id).execution_status == "failed"
    end)
  end

  test "queued cancellation retains technical Workspace before waiting on Operation" do
    with_queued_operation(fn ctx ->
      result =
        run_behind_operation_gate(
          ctx,
          :request_cancellation,
          fn ->
            AI.cancel(ctx.scope, ctx.operation.id)
          end,
          locks: :workspace
        )

      assert {:ok, %Operation{execution_status: "cancelled"}} = result
    end)
  end

  test "free release retains technical Workspace before waiting on Operation" do
    with_queued_operation(fn ctx ->
      result =
        run_behind_operation_gate(
          ctx,
          :release_if_unstarted,
          fn ->
            AI.release_if_unstarted(ctx.scope, ctx.operation.id)
          end,
          locks: :workspace
        )

      assert {:ok, :released} = result
      assert Repo.get!(Operation, ctx.operation.id).execution_status == "cancelled"
    end)
  end

  test "result dismissal retains technical Workspace before waiting on Operation" do
    with_queued_operation(fn ctx ->
      succeeded = succeed_operation(ctx)

      result =
        run_behind_operation_gate(
          %{ctx | operation: succeeded},
          :dismiss_result,
          fn ->
            AI.dismiss_result(ctx.scope, succeeded.id)
          end,
          locks: :workspace
        )

      assert {:ok, %Operation{user_disposition: "dismissed"}} = result
      refute Repo.get_by(Result, operation_id: succeeded.id)
    end)
  end

  test "result expiry retains technical Workspace before waiting on Operation" do
    with_queued_operation(fn ctx ->
      succeeded = succeed_operation(ctx)
      expired_at = DateTime.add(TimeHelpers.now(), -1, :second)

      succeeded.id
      |> then(&Repo.get_by!(Result, operation_id: &1))
      |> Ecto.Changeset.change(expires_at: expired_at)
      |> Repo.update!()

      result =
        run_behind_operation_gate(
          %{ctx | operation: succeeded},
          :expire_result,
          fn ->
            AI.expire_results()
          end,
          locks: :workspace
        )

      assert {:ok, %{expired_count: 1, failure_count: 0}} = result
      assert Repo.get!(Operation, succeeded.id).user_disposition == "abandoned"
      refute Repo.get_by(Result, operation_id: succeeded.id)
    end)
  end

  test "apply retains upstream authorization locks before waiting on Operation" do
    with_queued_operation(fn ctx ->
      assert {:ok, running, task, route} = Operations.claim(ctx.operation.id)
      assert {:ok, usage, _credential} = Operations.start_attempt(running, task, route)
      assert :ok = Operations.finish_success(running, usage, %{"echo" => %{"text" => "lock order"}}, %{})

      succeeded = Repo.get!(Operation, running.id)

      result =
        run_behind_operation_gate(%{ctx | operation: succeeded}, :apply, fn ->
          AI.apply_result(ctx.scope, succeeded.id, nil, fn _output, _provenance ->
            {:ok, :applied}
          end)
        end)

      assert {:ok, :applied} = result
      assert Repo.get!(Operation, succeeded.id).user_disposition == "accepted"
    end)
  end

  defp with_queued_operation(test_fun) do
    Sandbox.unboxed_run(Repo, fn ->
      original_config = Application.get_env(:storyarn, ContractTask, [])
      user = user_fixture()
      scope = user_scope_fixture(user)
      workspace = workspace_fixture(user)
      project = project_fixture(user, %{workspace: workspace})
      cleanup_ctx = %{user: user, workspace: workspace, project: project}

      try do
        Application.put_env(:storyarn, ContractTask, scenario: :success, execution_mode: :background)
        FunWithFlags.enable(:ai_integrations, for_actor: user)

        %WorkspacePolicy{workspace_id: workspace.id}
        |> WorkspacePolicy.changeset(%{
          allowed_lanes: ["managed"],
          version: 1,
          updated_by_id: user.id
        })
        |> Repo.insert!()

        ctx = build_operation_fixture(user, scope, workspace, project)

        test_fun.(ctx)
      after
        Application.put_env(:storyarn, ContractTask, original_config)
        FunWithFlags.disable(:ai_integrations, for_actor: user)
        cleanup(cleanup_ctx)
      end
    end)
  end

  defp build_operation_fixture(user, scope, workspace, project) do
    assert {:ok, task} = AI.get_task("contract.echo")

    assert {:ok, intent} =
             AI.new_intent(scope, %{
               workspace_id: workspace.id,
               project_id: project.id,
               task_id: task.id,
               input: %{"text" => "lock order"}
             })

    assert {:ok, %{route_options: [%{requested_route_ref: _route_ref}]}} = AI.preflight(intent)

    route_option =
      Repo.one!(
        from(option in RouteOption,
          where:
            option.actor_id == ^user.id and option.workspace_id == ^workspace.id and
              option.project_id == ^project.id and option.task_id == ^task.id,
          order_by: [desc: option.id],
          limit: 1
        )
      )

    route = route_from_option(route_option)

    assert {:ok, decision} =
             Governance.authorize(intent, task, :execute, lane: route.lane)

    operation =
      %Operation{}
      |> Operation.create_changeset(%{
        user_id: user.id,
        actor_id: user.id,
        workspace_id: workspace.id,
        workspace_id_snapshot: workspace.id,
        project_id: project.id,
        project_id_snapshot: project.id,
        route_option_id: route_option.id,
        task_id: task.id,
        task_contract_hash: AITask.contract_hash(task),
        capability: Atom.to_string(task.capability),
        idempotency_key: "lock-order-#{Ecto.UUID.generate()}",
        execution_status: "queued",
        settlement_status: "reserved",
        input_hash: intent.input_hash,
        input_schema_version: task.input_schema_version,
        output_schema_version: task.output_schema_version,
        prompt_version: task.prompt_version,
        context_version: task.context_version,
        result_type: task.result_type,
        result_destination: %{"type" => "panel", "id" => "contract-result"},
        policy_decision: Governance.decision_to_map(decision),
        execution_route: ExecutionRoute.to_map(route)
      })
      |> Repo.insert!()

    %Result{}
    |> Result.create_changeset(%{
      operation_id: operation.id,
      user_id: user.id,
      actor_id: user.id,
      workspace_id: workspace.id,
      project_id: project.id,
      input_encrypted: Jason.encode!(intent.input),
      input_hash: intent.input_hash,
      task_id: task.id,
      prompt_version: task.prompt_version,
      context_version: task.context_version,
      output_schema_version: task.output_schema_version
    })
    |> Repo.insert!()

    %{
      user: user,
      scope: scope,
      workspace: workspace,
      project: project,
      operation: operation,
      project_membership: Repo.get_by!(ProjectMembership, project_id: project.id, user_id: user.id),
      workspace_membership: Repo.get_by!(WorkspaceMembership, workspace_id: workspace.id, user_id: user.id)
    }
  end

  defp execution_intent_with_route_option(ctx, text) do
    attrs = %{
      workspace_id: ctx.workspace.id,
      project_id: ctx.project.id,
      task_id: "contract.echo",
      input: %{"text" => text}
    }

    assert {:ok, base_intent} = AI.new_intent(ctx.scope, attrs)

    assert {:ok, %{route_options: [%{requested_route_ref: route_ref}]}} =
             AI.preflight(base_intent)

    assert {:ok, execute_intent} =
             AI.new_intent(
               ctx.scope,
               Map.merge(attrs, %{
                 requested_route_ref: route_ref,
                 idempotency_key: "route-lock-order-#{Ecto.UUID.generate()}"
               })
             )

    route_option =
      Repo.one!(
        from(option in RouteOption,
          where:
            option.actor_id == ^ctx.user.id and
              option.input_hash == ^execute_intent.input_hash and
              is_nil(option.consumed_by_operation_id),
          order_by: [desc: option.id],
          limit: 1
        )
      )

    {execute_intent, route_option}
  end

  defp route_from_option(option) do
    assert {:ok, credential_ref} = CredentialRef.from_map(option.credential_ref)

    %ExecutionRoute{
      lane: :managed,
      provider: option.provider,
      model: option.model,
      credential_ref: credential_ref,
      payer: option.payer,
      assignment_source: option.assignment_source,
      consent_basis: option.consent_basis,
      policy_version: option.policy_version,
      price_id: option.price_id,
      price_version: option.price_version,
      price_units: option.price_units,
      provider_configuration: option.provider_configuration
    }
  end

  defp succeed_operation(ctx) do
    assert {:ok, running, task, route} = Operations.claim(ctx.operation.id)
    assert {:ok, usage, _credential} = Operations.start_attempt(running, task, route)
    assert :ok = Operations.finish_success(running, usage, %{"echo" => %{"text" => "lock order"}}, %{})
    Repo.get!(Operation, running.id)
  end

  defp assert_discarded_success(result, operation_id) do
    assert :ok = result

    assert %Operation{
             execution_status: "succeeded",
             cancellation_requested_at: %DateTime{}
           } = Repo.get!(Operation, operation_id)

    refute Repo.get_by(Result, operation_id: operation_id)
  end

  defp run_behind_operation_gate(ctx, label, command, opts \\ []) do
    parent = self()
    barrier = make_ref()
    gate = hold_operation_lock(ctx.operation.id, parent, barrier)
    locks = Keyword.get(opts, :locks, :all)
    while_blocked = Keyword.get(opts, :while_blocked, fn -> :ok end)

    try do
      assert_receive {^barrier, :operation_locked, gate_backend_pid}, @timeout

      contender = observed_command(label, command, parent, barrier)

      try do
        assert_receive {^barrier, :command_ready, ^label, contender_pid, contender_backend_pid}, @timeout
        send(contender_pid, {barrier, :start})

        assert wait_until_blocked_by(contender_backend_pid, gate_backend_pid),
               "#{label} did not reach the Operation gate"

        assert_upstream_locks_held(ctx, locks)
        while_blocked.()
        send(gate.pid, {barrier, :release_operation})
        assert {:ok, :released} = Task.await(gate, @timeout)
        Task.await(contender, @timeout)
      after
        send(gate.pid, {barrier, :release_operation})
        finish_task(contender)
      end
    after
      send(gate.pid, {barrier, :release_operation})
      finish_task(gate)
    end
  end

  defp run_behind_route_option_gate(ctx, route_option_id, label, command, opts \\ []) do
    parent = self()
    barrier = make_ref()
    gate = hold_route_option_lock(route_option_id, parent, barrier)
    while_blocked = Keyword.get(opts, :while_blocked, fn -> :ok end)
    release = Keyword.get(opts, :release, :unlock)

    try do
      assert_receive {^barrier, :route_option_locked, gate_backend_pid}, @timeout

      contender = observed_command(label, command, parent, barrier)

      try do
        assert_receive {^barrier, :command_ready, ^label, contender_pid, contender_backend_pid}, @timeout
        send(contender_pid, {barrier, :start})

        assert wait_until_blocked_by(contender_backend_pid, gate_backend_pid),
               "#{label} did not reach the RouteOption gate"

        assert_upstream_locks_held(ctx, :all)
        while_blocked.()
        send(gate.pid, {barrier, {:release_route_option, release}})
        expected_release = release_result(release)
        assert {:ok, ^expected_release} = Task.await(gate, @timeout)
        Task.await(contender, @timeout)
      after
        send(gate.pid, {barrier, :release_route_option})
        finish_task(contender)
      end
    after
      send(gate.pid, {barrier, :release_route_option})
      finish_task(gate)
    end
  end

  defp hold_operation_lock(operation_id, parent, barrier) do
    Task.async(fn -> run_operation_gate(operation_id, parent, barrier) end)
  end

  defp hold_route_option_lock(route_option_id, parent, barrier) do
    Task.async(fn -> run_route_option_gate(route_option_id, parent, barrier) end)
  end

  defp run_operation_gate(operation_id, parent, barrier) do
    Sandbox.unboxed_run(Repo, fn ->
      Repo.transaction(fn ->
        [[backend_pid]] = Repo.query!("SELECT pg_backend_pid()").rows
        %{num_rows: 1} = Repo.query!("SELECT id FROM ai_operations WHERE id = $1 FOR UPDATE", [operation_id])
        send(parent, {barrier, :operation_locked, backend_pid})

        receive do
          {^barrier, :release_operation} -> :released
        after
          @timeout -> exit(:operation_gate_timeout)
        end
      end)
    end)
  end

  defp run_route_option_gate(route_option_id, parent, barrier) do
    Sandbox.unboxed_run(Repo, fn ->
      Repo.transaction(fn ->
        [[backend_pid]] = Repo.query!("SELECT pg_backend_pid()").rows
        %{num_rows: 1} = Repo.query!("SELECT id FROM ai_route_options WHERE id = $1 FOR UPDATE", [route_option_id])
        send(parent, {barrier, :route_option_locked, backend_pid})

        receive do
          {^barrier, :release_route_option} ->
            :released

          {^barrier, {:release_route_option, :unlock}} ->
            :released

          {^barrier, {:release_route_option, :delete}} ->
            {1, _deleted} = Repo.delete_all(from(option in RouteOption, where: option.id == ^route_option_id))
            :deleted
        after
          @timeout -> exit(:route_option_gate_timeout)
        end
      end)
    end)
  end

  defp release_result(:unlock), do: :released
  defp release_result(:delete), do: :deleted

  defp observed_command(label, command, parent, barrier) do
    Task.async(fn ->
      Sandbox.unboxed_run(Repo, fn ->
        [[backend_pid]] = Repo.query!("SELECT pg_backend_pid()").rows
        send(parent, {barrier, :command_ready, label, self(), backend_pid})

        receive do
          {^barrier, :start} -> command.()
        after
          @timeout -> exit(:command_start_timeout)
        end
      end)
    end)
  end

  defp assert_upstream_locks_held(ctx, :workspace) do
    assert :lock_unavailable = update_lock_nowait(:workspace, ctx.workspace.id)
  end

  defp assert_upstream_locks_held(ctx, :all) do
    assert :lock_unavailable = update_lock_nowait(:workspace, ctx.workspace.id)
    assert :lock_unavailable = update_lock_nowait(:project, ctx.project.id)
    assert :lock_unavailable = update_lock_nowait(:workspace_membership, ctx.workspace_membership.id)
    assert :lock_unavailable = update_lock_nowait(:project_membership, ctx.project_membership.id)
  end

  defp update_lock_nowait(kind, row_id) do
    fn -> run_update_lock_nowait(kind, row_id) end
    |> Task.async()
    |> Task.await(@timeout)
  end

  defp run_update_lock_nowait(kind, row_id) do
    Sandbox.unboxed_run(Repo, fn -> attempt_update_lock_nowait(kind, row_id) end)
  end

  defp attempt_update_lock_nowait(kind, row_id) do
    Repo.transaction(fn -> lock_row_nowait!(kind, row_id) end)
    :available
  rescue
    error in Postgrex.Error ->
      case error do
        %Postgrex.Error{postgres: %{code: :lock_not_available}} -> :lock_unavailable
        _other -> reraise(error, __STACKTRACE__)
      end
  end

  defp lock_row_nowait!(:workspace, row_id) do
    %{num_rows: 1} = Repo.query!("SELECT id FROM workspaces WHERE id = $1 FOR UPDATE NOWAIT", [row_id])
  end

  defp lock_row_nowait!(:project, row_id) do
    %{num_rows: 1} = Repo.query!("SELECT id FROM projects WHERE id = $1 FOR UPDATE NOWAIT", [row_id])
  end

  defp lock_row_nowait!(:workspace_membership, row_id) do
    %{num_rows: 1} =
      Repo.query!("SELECT id FROM workspace_memberships WHERE id = $1 FOR UPDATE NOWAIT", [row_id])
  end

  defp lock_row_nowait!(:project_membership, row_id) do
    %{num_rows: 1} =
      Repo.query!("SELECT id FROM project_memberships WHERE id = $1 FOR UPDATE NOWAIT", [row_id])
  end

  defp wait_until_blocked_by(blocked_backend_pid, blocker_backend_pid) do
    deadline = System.monotonic_time(:millisecond) + @blocked_timeout
    do_wait_until_blocked_by(blocked_backend_pid, blocker_backend_pid, deadline)
  end

  defp do_wait_until_blocked_by(blocked_backend_pid, blocker_backend_pid, deadline) do
    if backend_blocked_by?(blocked_backend_pid, blocker_backend_pid) do
      true
    else
      if System.monotonic_time(:millisecond) >= deadline do
        false
      else
        :erlang.yield()
        do_wait_until_blocked_by(blocked_backend_pid, blocker_backend_pid, deadline)
      end
    end
  end

  defp backend_blocked_by?(blocked_backend_pid, blocker_backend_pid) do
    case Repo.query!(
           """
           SELECT wait_event_type,
                  $2::integer = ANY(pg_blocking_pids(pid)) AS blocked_by_gate
           FROM pg_stat_activity
           WHERE pid = $1::integer
           """,
           [blocked_backend_pid, blocker_backend_pid]
         ).rows do
      [["Lock", true]] -> true
      _other -> false
    end
  end

  defp finish_task(%Task{} = task) do
    if Process.alive?(task.pid) do
      Task.yield(task, @timeout) || Task.shutdown(task, :brutal_kill)
    end

    :ok
  end

  defp cleanup(ctx) do
    operation_ids =
      Repo.all(
        from(operation in Operation,
          where: operation.workspace_id_snapshot == ^ctx.workspace.id,
          select: operation.id
        )
      )

    Repo.delete_all(from(result in Result, where: result.operation_id in ^operation_ids))
    Repo.delete_all(from(event in UsageEvent, where: event.operation_id in ^operation_ids))
    Repo.delete_all(from(alert in OperatorAlert, where: alert.operation_id in ^operation_ids))
    Repo.delete_all(from(operation in Operation, where: operation.id in ^operation_ids))
    Repo.delete_all(from(option in RouteOption, where: option.workspace_id == ^ctx.workspace.id))
    Repo.delete_all(from(policy in WorkspacePolicy, where: policy.workspace_id == ^ctx.workspace.id))
    Repo.delete_all(from(project in Project, where: project.id == ^ctx.project.id))
    Repo.delete_all(from(workspace in Workspace, where: workspace.id == ^ctx.workspace.id))
    Repo.delete_all(from(user in User, where: user.id == ^ctx.user.id))
  end
end
