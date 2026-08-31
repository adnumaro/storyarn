defmodule Storyarn.AI.ManagedSpend.AllowanceLockOrderTest do
  use ExUnit.Case, async: false

  import Ecto.Query, warn: false
  import Storyarn.AccountsFixtures
  import Storyarn.WorkspacesFixtures

  alias Ecto.Adapters.SQL.Sandbox
  alias Storyarn.Accounts.User
  alias Storyarn.AI.AllowanceAccount
  alias Storyarn.AI.AllowanceGrant
  alias Storyarn.AI.ManagedSpend
  alias Storyarn.AI.ManagedSpend.Commands.Allowance, as: AllowanceCommands
  alias Storyarn.AI.Operation
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Repo
  alias Storyarn.Workspaces.Workspace

  @timeout 15_000
  @blocked_timeout 5_000

  test "grant retains Workspace before waiting on AllowanceAccount" do
    with_context(fn ctx ->
      assert :blocked_with_expected_root =
               run_behind_account_gate(ctx, :grant, :lock_unavailable, fn ->
                 ManagedSpend.grant(ctx.workspace.id, ctx.owner.id, %{
                   grant_key: "lock-order-grant",
                   kind: "one_time",
                   units: 1
                 })
               end)
    end)
  end

  test "refresh_account retains Workspace before waiting on AllowanceAccount" do
    with_context(fn ctx ->
      insert_expired_grant!(ctx)

      assert :blocked_with_expected_root =
               run_behind_account_gate(ctx, :refresh_account, :lock_unavailable, fn ->
                 AllowanceCommands.refresh_account(ctx.workspace.id)
               end)
    end)
  end

  test "expire_due snapshots identity then retains Workspace before waiting on AllowanceAccount" do
    with_context(fn ctx ->
      insert_expired_grant!(ctx)

      assert :blocked_with_expected_root =
               run_behind_account_gate(ctx, :expire_due, :lock_unavailable, fn ->
                 ManagedSpend.expire_due(TimeHelpers.now(),
                   batch_size: 1,
                   after_account_id: ctx.account.id - 1
                 )
               end)
    end)
  end

  test "managed reservation retains Workspace before waiting on AllowanceAccount" do
    with_context(fn ctx ->
      operation = managed_operation(ctx.workspace.id)

      assert :blocked_with_expected_root =
               run_behind_account_gate(ctx, :reserve, :lock_unavailable, fn ->
                 Repo.transaction(fn -> AllowanceCommands.reserve(operation) end)
               end)
    end)
  end

  test "set_status stays downstream-only and does not retain Workspace" do
    with_context(fn ctx ->
      assert :blocked_with_expected_root =
               run_behind_account_gate(ctx, :set_status, :available, fn ->
                 ManagedSpend.set_status(ctx.workspace.id, "paused")
               end)
    end)
  end

  defp with_context(test_fun) do
    Sandbox.unboxed_run(Repo, fn ->
      owner = user_fixture(%{email: "ai-allowance-lock-order-#{Ecto.UUID.generate()}@example.com"})
      workspace = workspace_fixture(owner)

      account =
        %AllowanceAccount{}
        |> AllowanceAccount.create_changeset(workspace.id)
        |> Repo.insert!()

      try do
        test_fun.(%{owner: owner, workspace: workspace, account: account})
      after
        cleanup(workspace.id, owner.id)
      end
    end)
  end

  defp run_behind_account_gate(ctx, label, expected_workspace_lock, mutation_fun) do
    parent = self()
    barrier = make_ref()
    gate = start_account_gate(ctx.account.id, parent, barrier, label)

    try do
      assert_receive {^barrier, {:account_locked, ^label}, gate_backend_pid}, @timeout

      run_writer_behind_gate(
        ctx,
        gate,
        gate_backend_pid,
        mutation_fun,
        %{parent: parent, barrier: barrier, label: label, expected_workspace_lock: expected_workspace_lock}
      )
    after
      send(gate.pid, {barrier, {:release_account, label}})
      finish_task(gate)
    end
  end

  defp run_writer_behind_gate(ctx, gate, gate_backend_pid, mutation_fun, run) do
    %{
      parent: parent,
      barrier: barrier,
      label: label,
      expected_workspace_lock: expected_workspace_lock
    } = run

    writer = start_writer(mutation_fun, parent, barrier, label)

    try do
      assert_receive {^barrier, {:writer_ready, ^label}, writer_backend_pid}, @timeout

      assert wait_until_blocked_by(writer_backend_pid, gate_backend_pid),
             "#{label} did not block behind AllowanceAccount"

      assert expected_workspace_lock == update_workspace_lock_nowait(ctx.workspace.id)

      Task.shutdown(writer, :brutal_kill)
      send(gate.pid, {barrier, {:release_account, label}})
      assert {:ok, :released} = Task.await(gate, @timeout)
      :blocked_with_expected_root
    after
      finish_task(writer)
    end
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

  defp start_account_gate(account_id, parent, barrier, label) do
    Task.async(fn -> run_account_gate(account_id, parent, barrier, label) end)
  end

  defp run_account_gate(account_id, parent, barrier, label) do
    Sandbox.unboxed_run(Repo, fn -> hold_account_gate(account_id, parent, barrier, label) end)
  end

  defp hold_account_gate(account_id, parent, barrier, label) do
    Repo.transaction(fn ->
      [[backend_pid]] = Repo.query!("SELECT pg_backend_pid()").rows

      %{num_rows: 1} =
        Repo.query!("SELECT id FROM ai_allowance_accounts WHERE id = $1 FOR UPDATE", [account_id])

      send(parent, {barrier, {:account_locked, label}, backend_pid})
      await_account_release(barrier, label)
    end)
  end

  defp await_account_release(barrier, label) do
    receive do
      {^barrier, {:release_account, ^label}} -> :released
    after
      @timeout -> exit({:account_gate_release_timeout, label})
    end
  end

  defp update_workspace_lock_nowait(workspace_id) do
    fn -> Sandbox.unboxed_run(Repo, fn -> attempt_workspace_lock_nowait(workspace_id) end) end
    |> Task.async()
    |> Task.await(@timeout)
  end

  defp attempt_workspace_lock_nowait(workspace_id) do
    Repo.transaction(fn ->
      %{num_rows: 1} =
        Repo.query!("SELECT id FROM workspaces WHERE id = $1 FOR UPDATE NOWAIT", [workspace_id])
    end)

    :available
  rescue
    error in Postgrex.Error -> handle_workspace_lock_error(error, __STACKTRACE__)
  end

  defp handle_workspace_lock_error(%Postgrex.Error{postgres: %{code: :lock_not_available}}, _stacktrace),
    do: :lock_unavailable

  defp handle_workspace_lock_error(error, stacktrace), do: reraise(error, stacktrace)

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
        Process.sleep(10)
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

  defp insert_expired_grant!(ctx) do
    now = TimeHelpers.now()

    ctx.account
    |> AllowanceAccount.balance_changeset(%{available_units: 1})
    |> Repo.update!()

    %AllowanceGrant{}
    |> AllowanceGrant.create_changeset(%{
      account_id: ctx.account.id,
      workspace_id: ctx.workspace.id,
      workspace_id_snapshot: ctx.workspace.id,
      grant_key: "expired-lock-order-#{Ecto.UUID.generate()}",
      kind: "one_time",
      units: 1,
      remaining_units: 1,
      expires_at: DateTime.add(now, -60, :second),
      granted_by_id: ctx.owner.id,
      actor_id: ctx.owner.id,
      metadata: %{}
    })
    |> Repo.insert!()
  end

  defp managed_operation(workspace_id) do
    %Operation{
      id: 9_000_000_000_000 + System.unique_integer([:positive]),
      workspace_id: workspace_id,
      workspace_id_snapshot: workspace_id,
      execution_route: %{
        "lane" => "managed",
        "provider" => "lock-order-provider",
        "model" => "lock-order-model",
        "credential_ref" => %{"kind" => "managed", "reference" => "lock-order-credential"},
        "payer" => "storyarn",
        "assignment_source" => "managed_catalog",
        "consent_basis" => "workspace_allowance",
        "policy_version" => 1,
        "price_id" => "lock-order-price",
        "price_version" => 1,
        "price_units" => 1,
        "provider_configuration" => %{}
      }
    }
  end

  defp finish_task(%Task{} = task) do
    if Process.alive?(task.pid) do
      Task.shutdown(task, :brutal_kill)
    end

    :ok
  end

  defp cleanup(workspace_id, user_id) do
    Repo.delete_all(from(grant in AllowanceGrant, where: grant.workspace_id_snapshot == ^workspace_id))
    Repo.delete_all(from(account in AllowanceAccount, where: account.workspace_id == ^workspace_id))
    Repo.delete_all(from(workspace in Workspace, where: workspace.id == ^workspace_id))
    Repo.delete_all(from(user in User, where: user.id == ^user_id))
  end
end
