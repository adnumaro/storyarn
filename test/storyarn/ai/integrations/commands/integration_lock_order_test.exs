defmodule Storyarn.AI.Integrations.Commands.IntegrationLockOrderTest do
  use ExUnit.Case, async: false

  import Ecto.Query, warn: false
  import Storyarn.AccountsFixtures
  import Storyarn.WorkspacesFixtures

  alias Ecto.Adapters.SQL.Sandbox
  alias Storyarn.Accounts.User
  alias Storyarn.AI
  alias Storyarn.AI.Integration
  alias Storyarn.AI.IntegrationWorkspaceAssignment
  alias Storyarn.AI.PersonalPreference
  alias Storyarn.AI.WorkspacePolicy
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Repo
  alias Storyarn.Workspaces.Workspace
  alias Storyarn.Workspaces.WorkspaceMembership

  @timeout 15_000
  @blocked_timeout 5_000

  test "assignment retains Workspace -> Membership -> Policy before waiting on Integration" do
    with_context(fn ctx ->
      assert :blocked_with_upstream_locks =
               run_behind_row_gate(ctx, "ai_integrations", ctx.integration.id, :assign, fn ->
                 AI.assign_integration(ctx.scope, ctx.integration.id, ctx.workspace.id)
               end)
    end)
  end

  test "preference writes retain Workspace -> Membership -> Policy before waiting on Integration" do
    with_context(fn ctx ->
      insert_assignment!(ctx)

      assert :blocked_with_upstream_locks =
               run_behind_row_gate(ctx, "ai_integrations", ctx.integration.id, :put_preference, fn ->
                 AI.put_personal_preference(
                   ctx.scope,
                   ctx.workspace.id,
                   :general_assistant,
                   ctx.integration.id,
                   "not-reached-before-integration-lock"
                 )
               end)
    end)
  end

  test "unassignment retains Workspace -> Membership before waiting on Assignment" do
    with_context(fn ctx ->
      assignment = insert_assignment!(ctx)

      assert :blocked_with_upstream_locks =
               run_behind_row_gate(
                 ctx,
                 "ai_integration_workspace_assignments",
                 assignment.id,
                 :unassign,
                 fn -> AI.unassign_integration(ctx.scope, ctx.integration.id, ctx.workspace.id) end,
                 policy_lock?: false
               )
    end)
  end

  defp with_context(test_fun) do
    Sandbox.unboxed_run(Repo, fn ->
      owner = user_fixture(%{email: "ai-integration-lock-order-#{Ecto.UUID.generate()}@example.com"})
      scope = user_scope_fixture(owner)
      workspace = workspace_fixture(owner)
      membership = Repo.get_by!(WorkspaceMembership, workspace_id: workspace.id, user_id: owner.id)

      FunWithFlags.enable(:ai_integrations, for_actor: owner)

      policy = insert_policy!(workspace.id, owner.id)
      integration = insert_integration!(owner.id)

      try do
        test_fun.(%{
          owner: owner,
          scope: scope,
          workspace: workspace,
          membership: membership,
          policy: policy,
          integration: integration
        })
      after
        FunWithFlags.disable(:ai_integrations, for_actor: owner)
        cleanup(workspace.id, owner.id)
      end
    end)
  end

  defp run_behind_row_gate(ctx, table, row_id, label, mutation_fun, opts \\ []) do
    parent = self()
    barrier = make_ref()
    gate = start_row_gate(table, row_id, parent, barrier, label)

    try do
      assert_receive {^barrier, {:gate_locked, ^label}, gate_backend_pid}, @timeout

      run_writer_behind_gate(
        ctx,
        gate,
        gate_backend_pid,
        mutation_fun,
        %{parent: parent, barrier: barrier, label: label, opts: opts}
      )
    after
      send(gate.pid, {barrier, {:release_gate, label}})
      finish_task(gate)
    end
  end

  defp run_writer_behind_gate(ctx, gate, gate_backend_pid, mutation_fun, run) do
    %{parent: parent, barrier: barrier, label: label, opts: opts} = run
    writer = start_writer(mutation_fun, parent, barrier, label)

    try do
      assert_receive {^barrier, {:writer_ready, ^label}, writer_backend_pid}, @timeout

      assert wait_until_blocked_by(writer_backend_pid, gate_backend_pid),
             "#{label} did not block behind the downstream row gate"

      assert_upstream_locks(ctx, Keyword.get(opts, :policy_lock?, true))

      Task.shutdown(writer, :brutal_kill)
      send(gate.pid, {barrier, {:release_gate, label}})
      assert {:ok, :released} = Task.await(gate, @timeout)
      :blocked_with_upstream_locks
    after
      finish_task(writer)
    end
  end

  defp assert_upstream_locks(ctx, policy_lock?) do
    assert :lock_unavailable = update_lock_nowait("workspaces", ctx.workspace.id)
    assert :lock_unavailable = update_lock_nowait("workspace_memberships", ctx.membership.id)

    expected_policy_lock = if policy_lock?, do: :lock_unavailable, else: :available
    assert ^expected_policy_lock = update_lock_nowait("ai_workspace_policies", ctx.policy.id)
  end

  defp start_writer(mutation_fun, parent, barrier, label) do
    Task.async(fn ->
      Sandbox.unboxed_run(Repo, fn ->
        [[backend_pid]] = Repo.query!("SELECT pg_backend_pid()").rows
        send(parent, {barrier, {:writer_ready, label}, backend_pid})
        mutation_fun.()
      end)
    end)
  end

  defp start_row_gate(table, row_id, parent, barrier, label) do
    Task.async(fn -> run_row_gate(table, row_id, parent, barrier, label) end)
  end

  defp run_row_gate(table, row_id, parent, barrier, label) do
    Sandbox.unboxed_run(Repo, fn -> transact_row_gate(table, row_id, parent, barrier, label) end)
  end

  defp transact_row_gate(table, row_id, parent, barrier, label) do
    Repo.transaction(fn -> lock_and_hold_row_gate(table, row_id, parent, barrier, label) end)
  end

  defp lock_and_hold_row_gate(table, row_id, parent, barrier, label) do
    [[backend_pid]] = Repo.query!("SELECT pg_backend_pid()").rows
    lock_downstream_row!(table, row_id)
    send(parent, {barrier, {:gate_locked, label}, backend_pid})
    await_gate_release(barrier, label)
  end

  defp await_gate_release(barrier, label) do
    receive do
      {^barrier, {:release_gate, ^label}} -> :released
    after
      @timeout -> exit({:row_gate_release_timeout, label})
    end
  end

  defp lock_downstream_row!("ai_integrations", row_id) do
    %{num_rows: 1} = Repo.query!("SELECT id FROM ai_integrations WHERE id = $1 FOR UPDATE", [row_id])
  end

  defp lock_downstream_row!("ai_integration_workspace_assignments", row_id) do
    %{num_rows: 1} =
      Repo.query!(
        "SELECT id FROM ai_integration_workspace_assignments WHERE id = $1 FOR UPDATE",
        [row_id]
      )
  end

  defp update_lock_nowait(table, row_id) do
    fn -> Sandbox.unboxed_run(Repo, fn -> attempt_update_lock_nowait(table, row_id) end) end
    |> Task.async()
    |> Task.await(@timeout)
  end

  defp attempt_update_lock_nowait(table, row_id) do
    Repo.transaction(fn -> lock_upstream_row_nowait!(table, row_id) end)
    :available
  rescue
    error in Postgrex.Error -> handle_update_lock_error(error, __STACKTRACE__)
  end

  defp handle_update_lock_error(%Postgrex.Error{postgres: %{code: :lock_not_available}}, _stacktrace),
    do: :lock_unavailable

  defp handle_update_lock_error(error, stacktrace), do: reraise(error, stacktrace)

  defp lock_upstream_row_nowait!("workspaces", row_id) do
    %{num_rows: 1} = Repo.query!("SELECT id FROM workspaces WHERE id = $1 FOR UPDATE NOWAIT", [row_id])
  end

  defp lock_upstream_row_nowait!("workspace_memberships", row_id) do
    %{num_rows: 1} =
      Repo.query!("SELECT id FROM workspace_memberships WHERE id = $1 FOR UPDATE NOWAIT", [row_id])
  end

  defp lock_upstream_row_nowait!("ai_workspace_policies", row_id) do
    %{num_rows: 1} =
      Repo.query!("SELECT id FROM ai_workspace_policies WHERE id = $1 FOR UPDATE NOWAIT", [row_id])
  end

  defp wait_until_blocked_by(blocked_backend_pid, blocker_backend_pid) do
    deadline = System.monotonic_time(:millisecond) + @blocked_timeout
    do_wait_until_blocked_by(blocked_backend_pid, blocker_backend_pid, deadline)
  end

  defp do_wait_until_blocked_by(blocked_backend_pid, blocker_backend_pid, deadline) do
    cond do
      backend_blocked_by?(blocked_backend_pid, blocker_backend_pid) ->
        true

      System.monotonic_time(:millisecond) >= deadline ->
        false

      true ->
        do_wait_until_blocked_by(blocked_backend_pid, blocker_backend_pid, deadline)
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

  defp insert_policy!(workspace_id, owner_id) do
    %WorkspacePolicy{workspace_id: workspace_id}
    |> WorkspacePolicy.changeset(%{
      allowed_lanes: ["personal_byok"],
      version: 1,
      updated_by_id: owner_id
    })
    |> Repo.insert!()
  end

  defp insert_integration!(user_id) do
    now = TimeHelpers.now()

    %Integration{}
    |> Integration.connect_changeset(%{
      user_id: user_id,
      provider: "openai",
      api_key_encrypted: "sk-proj-lock-order-abcd",
      key_last_four: "abcd",
      available_models: ["personal-lock-order-v1"],
      connected_at: now,
      last_validated_at: now
    })
    |> Repo.insert!()
  end

  defp insert_assignment!(ctx) do
    %IntegrationWorkspaceAssignment{
      user_id: ctx.owner.id,
      workspace_id: ctx.workspace.id,
      integration_id: ctx.integration.id,
      provider: ctx.integration.provider
    }
    |> IntegrationWorkspaceAssignment.assign_changeset(TimeHelpers.now())
    |> Repo.insert!()
  end

  defp finish_task(%Task{} = task) do
    if Process.alive?(task.pid) do
      Task.shutdown(task, :brutal_kill)
    end

    :ok
  end

  defp cleanup(workspace_id, user_id) do
    Repo.delete_all(from(preference in PersonalPreference, where: preference.workspace_id == ^workspace_id))

    Repo.delete_all(from(assignment in IntegrationWorkspaceAssignment, where: assignment.workspace_id == ^workspace_id))

    Repo.delete_all(from(integration in Integration, where: integration.user_id == ^user_id))
    Repo.delete_all(from(workspace in Workspace, where: workspace.id == ^workspace_id))
    Repo.delete_all(from(user in User, where: user.id == ^user_id))
  end
end
