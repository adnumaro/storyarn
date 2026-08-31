defmodule Storyarn.AI.ManagedSpend.ReservationLockOrderTest do
  use ExUnit.Case, async: false

  import Ecto.Query, warn: false
  import Storyarn.AccountsFixtures
  import Storyarn.WorkspacesFixtures

  alias Ecto.Adapters.SQL.Sandbox
  alias Storyarn.Accounts.User
  alias Storyarn.AI.Allowance
  alias Storyarn.AI.AllowanceLedgerEntry
  alias Storyarn.AI.AllowanceReservation
  alias Storyarn.AI.CredentialRef
  alias Storyarn.AI.ExecutionRoute
  alias Storyarn.AI.ManagedSpend.Commands.Settlement
  alias Storyarn.AI.Operation
  alias Storyarn.AI.ProviderBudget
  alias Storyarn.AI.ProviderBudgetReservation
  alias Storyarn.Repo
  alias Storyarn.Workspaces.Workspace

  @timeout 15_000
  @blocked_timeout 5_000

  test "the public Allowance replay retains Workspace before waiting on its reservation" do
    with_context(fn ctx ->
      reservation = insert_allowance_reservation!(ctx)

      assert :blocked_with_workspace_retained =
               run_behind_row_gate(ctx, "ai_allowance_reservations", reservation.id, :allowance_replay, fn ->
                 Allowance.reserve(ctx.operation)
               end)
    end)
  end

  test "an aggregate partial replay retains Workspace before waiting on Allowance" do
    with_context(fn ctx ->
      reservation = insert_allowance_reservation!(ctx)

      assert :blocked_with_workspace_retained =
               run_behind_row_gate(ctx, "ai_allowance_reservations", reservation.id, :aggregate_replay, fn ->
                 Settlement.reserve(ctx.operation)
               end)
    end)
  end

  test "the public ProviderBudget reserve replay retains Workspace before waiting on its reservation" do
    with_context(fn ctx ->
      reservation = insert_provider_reservation!(ctx)

      assert :blocked_with_workspace_retained =
               run_behind_row_gate(ctx, "ai_provider_budget_reservations", reservation.id, :provider_reserve, fn ->
                 ProviderBudget.reserve(ctx.operation, ctx.route)
               end)
    end)
  end

  test "the public ProviderBudget settlement retains Workspace before waiting on its reservation" do
    with_context(fn ctx ->
      reservation = insert_provider_reservation!(ctx)

      assert :blocked_with_workspace_retained =
               run_behind_row_gate(ctx, "ai_provider_budget_reservations", reservation.id, :provider_settle, fn ->
                 ProviderBudget.settle(ctx.operation)
               end)
    end)
  end

  test "provider terminal replays survive hard delete and a missing reservation fails explicitly" do
    with_context(fn ctx ->
      missing_operation = insert_operation!(ctx.owner.id, ctx.workspace.id, ctx.route, "provider-missing")
      reservation = insert_provider_reservation!(ctx)

      Repo.delete!(ctx.workspace)

      assert :ok = ProviderBudget.reserve(ctx.operation, ctx.route)
      assert :ok = ProviderBudget.settle(ctx.operation)
      assert :ok = ProviderBudget.settle(ctx.operation)

      assert %ProviderBudgetReservation{status: "settled", workspace_id: nil} =
               Repo.get!(ProviderBudgetReservation, reservation.id)

      assert {:error, :provider_budget_reservation_missing} =
               ProviderBudget.reserve(missing_operation, ctx.route)

      assert {:error, :provider_budget_reservation_missing} = ProviderBudget.settle(missing_operation)
      refute Repo.get_by(ProviderBudgetReservation, operation_id: missing_operation.id)
    end)
  end

  test "the aggregate rolls Allowance back when ProviderBudget settlement is missing" do
    with_context(fn ctx ->
      reservation = insert_allowance_reservation!(ctx)

      assert {:error, :provider_budget_reservation_missing} = Settlement.commit(ctx.operation)

      assert %AllowanceReservation{status: "reserved", settled_at: nil} =
               Repo.get!(AllowanceReservation, reservation.id)

      refute Repo.exists?(from(entry in AllowanceLedgerEntry, where: entry.operation_id == ^ctx.operation.id))
    end)
  end

  defp with_context(test_fun) do
    Sandbox.unboxed_run(Repo, fn ->
      owner = user_fixture(%{email: "ai-reservation-lock-order-#{Ecto.UUID.generate()}@example.com"})
      workspace = workspace_fixture(owner)
      route = managed_route()
      operation = insert_operation!(owner.id, workspace.id, route, "primary")

      try do
        test_fun.(%{owner: owner, workspace: workspace, route: route, operation: operation})
      after
        cleanup(workspace.id, owner.id)
      end
    end)
  end

  defp run_behind_row_gate(ctx, table, row_id, label, mutation_fun) do
    parent = self()
    barrier = make_ref()
    gate = start_row_gate(table, row_id, parent, barrier, label)

    try do
      assert_receive {^barrier, {:gate_locked, ^label}, gate_backend_pid}, @timeout
      writer = start_writer(mutation_fun, parent, barrier, label)

      try do
        assert_receive {^barrier, {:writer_ready, ^label}, writer_backend_pid}, @timeout

        assert wait_until_blocked_by(writer_backend_pid, gate_backend_pid),
               "#{label} did not block behind the reservation row"

        assert :lock_unavailable = update_workspace_lock_nowait(ctx.workspace.id)

        Task.shutdown(writer, :brutal_kill)
        send(gate.pid, {barrier, {:release_gate, label}})
        assert {:ok, :released} = Task.await(gate, @timeout)
        :blocked_with_workspace_retained
      after
        finish_task(writer)
      end
    after
      send(gate.pid, {barrier, {:release_gate, label}})
      finish_task(gate)
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
    lock_reservation_row!(table, row_id)
    send(parent, {barrier, {:gate_locked, label}, backend_pid})
    await_row_gate_release(barrier, label)
  end

  defp await_row_gate_release(barrier, label) do
    receive do
      {^barrier, {:release_gate, ^label}} -> :released
    after
      @timeout -> exit({:row_gate_release_timeout, label})
    end
  end

  defp lock_reservation_row!("ai_allowance_reservations", row_id) do
    %{num_rows: 1} =
      Repo.query!("SELECT id FROM ai_allowance_reservations WHERE id = $1 FOR UPDATE", [row_id])
  end

  defp lock_reservation_row!("ai_provider_budget_reservations", row_id) do
    %{num_rows: 1} =
      Repo.query!("SELECT id FROM ai_provider_budget_reservations WHERE id = $1 FOR UPDATE", [row_id])
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

  defp managed_route do
    {:ok, credential_ref} = CredentialRef.new(:managed, "reservation-lock-order")

    %ExecutionRoute{
      lane: :managed,
      provider: "lock-order-provider",
      model: "lock-order-model",
      credential_ref: credential_ref,
      payer: "storyarn",
      assignment_source: "managed_catalog",
      consent_basis: "workspace_allowance",
      policy_version: 1,
      price_id: "lock-order-price",
      price_version: 1,
      price_units: 1,
      provider_configuration: %{
        "provider_price" => %{"max_estimated_cost" => "1", "currency" => "USD"},
        "budget" => %{
          "global_daily" => "100",
          "global_monthly" => "100",
          "workspace_daily" => "100"
        }
      }
    }
  end

  defp insert_operation!(owner_id, workspace_id, route, suffix) do
    Repo.insert!(%Operation{
      user_id: owner_id,
      actor_id: owner_id,
      workspace_id: workspace_id,
      workspace_id_snapshot: workspace_id,
      task_id: "lock-order.task",
      task_contract_hash: "lock-order-contract",
      capability: "lock_order",
      idempotency_key: "#{suffix}-#{Ecto.UUID.generate()}",
      execution_status: "queued",
      settlement_status: "reserved",
      input_hash: String.duplicate("a", 64),
      input_schema_version: "1",
      output_schema_version: "1",
      prompt_version: "1",
      context_version: "1",
      result_type: "lock_order",
      result_destination: %{"type" => "none"},
      policy_decision: %{},
      execution_route: ExecutionRoute.to_map(route)
    })
  end

  defp insert_allowance_reservation!(ctx) do
    %AllowanceReservation{}
    |> AllowanceReservation.create_changeset(%{
      operation_id: ctx.operation.id,
      workspace_id: ctx.workspace.id,
      workspace_id_snapshot: ctx.workspace.id,
      price_id: ctx.route.price_id,
      price_version: ctx.route.price_version,
      units: ctx.route.price_units,
      status: "reserved"
    })
    |> Repo.insert!()
  end

  defp insert_provider_reservation!(ctx) do
    %ProviderBudgetReservation{}
    |> ProviderBudgetReservation.create_changeset(%{
      operation_id: ctx.operation.id,
      workspace_id: ctx.workspace.id,
      workspace_id_snapshot: ctx.workspace.id,
      provider: ctx.route.provider,
      model: ctx.route.model,
      price_snapshot: ctx.route.provider_configuration["provider_price"],
      estimated_cost: Decimal.new(1),
      currency: "USD",
      status: "reserved"
    })
    |> Repo.insert!()
  end

  defp finish_task(%Task{} = task) do
    if Process.alive?(task.pid) do
      Task.shutdown(task, :brutal_kill)
    end

    :ok
  end

  defp cleanup(workspace_id, user_id) do
    operation_ids =
      Repo.all(
        from(operation in Operation, where: operation.workspace_id_snapshot == ^workspace_id, select: operation.id)
      )

    Repo.delete_all(from(reservation in ProviderBudgetReservation, where: reservation.operation_id in ^operation_ids))
    Repo.delete_all(from(reservation in AllowanceReservation, where: reservation.operation_id in ^operation_ids))
    Repo.delete_all(from(operation in Operation, where: operation.id in ^operation_ids))
    Repo.delete_all(from(workspace in Workspace, where: workspace.id == ^workspace_id))
    Repo.delete_all(from(user in User, where: user.id == ^user_id))
  end
end
