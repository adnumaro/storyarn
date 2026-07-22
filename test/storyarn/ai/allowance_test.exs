defmodule Storyarn.AI.AllowanceTest do
  use Storyarn.DataCase, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.AI
  alias Storyarn.AI.Allowance
  alias Storyarn.AI.AllowanceAllocation
  alias Storyarn.AI.AllowanceGrant
  alias Storyarn.AI.AllowanceLedgerEntry
  alias Storyarn.AI.AllowanceReservation
  alias Storyarn.AI.Operation
  alias Storyarn.AI.Operations
  alias Storyarn.AI.OperatorAlert
  alias Storyarn.AI.ProviderBudgetReservation
  alias Storyarn.AI.Settlement
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Workspaces
  alias StoryarnTest.AI.ContractTask

  setup do
    original_settlement = Application.get_env(:storyarn, Settlement)
    original_task = Application.get_env(:storyarn, ContractTask, [])
    Application.put_env(:storyarn, Settlement, Storyarn.AI.Settlement.Managed)
    Application.put_env(:storyarn, ContractTask, scenario: :success, execution_mode: :inline)

    owner = user_fixture()
    scope = user_scope_fixture(owner)
    workspace = workspace_fixture(owner)
    project = project_fixture(owner, %{workspace: workspace})
    FunWithFlags.enable(:ai_integrations, for_actor: owner)
    assert {:ok, _policy} = AI.update_workspace_policy(scope, workspace.id, ["managed"])

    on_exit(fn ->
      Application.put_env(:storyarn, Settlement, original_settlement)
      Application.put_env(:storyarn, ContractTask, original_task)
      FunWithFlags.disable(:ai_integrations, for_actor: owner)
    end)

    %{owner: owner, scope: scope, workspace: workspace, project: project}
  end

  test "reserves and commits the exact fixed task price", ctx do
    configure_price(2)
    grant!(ctx, 5, "exact-price")

    assert {:ok, operation} = execute(ctx, "exact", "exact-operation")
    assert operation.execution_status == "succeeded"
    assert operation.settlement_status == "committed"

    assert {:ok, summary} = AI.allowance_summary(ctx.scope, ctx.workspace.id)
    assert summary == %{status: "active", available_units: 3, reserved_units: 0, committed_units: 2}

    assert %AllowanceReservation{units: 2, status: "committed", price_version: 1} =
             Repo.get_by!(AllowanceReservation, operation_id: operation.id)

    assert ["grant", "reserve", "commit"] == ledger_kinds(ctx.workspace.id)

    assert %ProviderBudgetReservation{status: "settled", actual_cost: actual_cost} =
             Repo.get_by!(ProviderBudgetReservation, operation_id: operation.id)

    assert Decimal.equal?(actual_cost, Decimal.new(0))
  end

  test "managed accounting changesets reject incomplete terminal records" do
    refute %AllowanceReservation{}
           |> AllowanceReservation.create_changeset(%{
             operation_id: 1,
             workspace_id: 1,
             workspace_id_snapshot: 1,
             price_id: "beta",
             price_version: 1,
             units: 1,
             status: "committed"
           })
           |> Map.fetch!(:valid?)

    refute %ProviderBudgetReservation{}
           |> ProviderBudgetReservation.create_changeset(%{
             operation_id: 1,
             workspace_id: 1,
             workspace_id_snapshot: 1,
             provider: "fake",
             model: "fake",
             price_snapshot: %{},
             estimated_cost: 0,
             currency: "USD",
             status: "settled"
           })
           |> Map.fetch!(:valid?)

    refute %AllowanceAllocation{units: 1}
           |> AllowanceAllocation.restore_changeset(nil)
           |> Map.fetch!(:valid?)

    refute %OperatorAlert{}
           |> OperatorAlert.create_changeset(%{
             dedupe_key: "missing-workspace",
             kind: "allowance_anomaly",
             severity: "warning"
           })
           |> Map.fetch!(:valid?)
  end

  test "known, validation and unknown failures release the workspace allowance", ctx do
    for {scenario, expected_status} <- [failure: "failed", invalid_metrics: "failed", unknown: "unknown"] do
      Application.put_env(:storyarn, ContractTask,
        scenario: scenario,
        execution_mode: :inline,
        managed_price: %{id: "contract-beta", version: 1, units: 2}
      )

      grant!(ctx, 2, "release-#{scenario}")
      assert {:ok, operation} = execute(ctx, Atom.to_string(scenario), "release-operation-#{scenario}")
      assert operation.execution_status == expected_status
      assert operation.settlement_status == "released"
    end

    assert {:ok, summary} = AI.allowance_summary(ctx.scope, ctx.workspace.id)
    assert summary.available_units == 6
    assert summary.reserved_units == 0
    assert summary.committed_units == 0
    assert Enum.count(ledger_kinds(ctx.workspace.id), &(&1 == "release")) == 3
  end

  test "a dismissed valid result remains charged", ctx do
    configure_price(2)
    grant!(ctx, 2, "dismissed-result")

    assert {:ok, operation} = execute(ctx, "dismiss", "dismiss-operation")
    assert {:ok, dismissed} = AI.dismiss_result(ctx.scope, operation.id)
    assert dismissed.user_disposition == "dismissed"

    assert {:ok, summary} = AI.allowance_summary(ctx.scope, ctx.workspace.id)
    assert summary.available_units == 0
    assert summary.committed_units == 2
    refute "release" in ledger_kinds(ctx.workspace.id)
  end

  test "grant issuance is idempotent and conflicting reuse is rejected", ctx do
    attrs = %{grant_key: "invite-wave-1", kind: "one_time", units: 10}
    assert {:ok, first} = Allowance.grant(ctx.workspace.id, ctx.owner.id, attrs)
    assert {:ok, replayed} = Allowance.grant(ctx.workspace.id, ctx.owner.id, attrs)
    assert replayed.id == first.id

    assert {:error, :grant_conflict} =
             Allowance.grant(ctx.workspace.id, ctx.owner.id, %{attrs | units: 11})

    assert Repo.aggregate(AllowanceGrant, :count) == 1
    assert Repo.aggregate(AllowanceLedgerEntry, :count) == 1
  end

  test "grant metadata supplied by an operator is not retained", ctx do
    assert {:ok, grant} =
             Allowance.grant(ctx.workspace.id, ctx.owner.id, %{
               grant_key: "metadata-sanitized",
               kind: "one_time",
               units: 1,
               metadata: %{"note" => "must not be persisted"}
             })

    assert grant.metadata == %{}
  end

  test "invalid grants fail closed without creating non-expiring allowance", ctx do
    assert {:error, :invalid_grant_expiry} =
             Allowance.grant(ctx.workspace.id, ctx.owner.id, %{
               grant_key: "invalid-expiry",
               kind: "one_time",
               units: 10,
               expires_at: "not-a-datetime"
             })

    assert {:error, %Ecto.Changeset{valid?: false}} =
             Allowance.grant(ctx.workspace.id, ctx.owner.id, %{
               grant_key: "invalid-units",
               kind: "one_time",
               units: 0
             })

    assert Repo.aggregate(AllowanceGrant, :count) == 0
    assert {:ok, summary} = AI.allowance_summary(ctx.scope, ctx.workspace.id)
    assert summary.available_units == 0
  end

  test "expired grants cannot be spent and expiry is recorded", ctx do
    assert {:ok, _grant} =
             Allowance.grant(ctx.workspace.id, ctx.owner.id, %{
               grant_key: "expired-invite",
               kind: "one_time",
               units: 3,
               expires_at: DateTime.add(TimeHelpers.now(), -1, :second)
             })

    assert {:ok, summary} = AI.allowance_summary(ctx.scope, ctx.workspace.id)
    assert summary.available_units == 0
    assert ledger_kinds(ctx.workspace.id) == ["grant", "expiry"]

    assert {:error, :allowance_exhausted} = execute(ctx, "expired", "expired-operation")
    assert Repo.aggregate(Operation, :count) == 0
  end

  test "concurrent execution cannot overspend one remaining unit", ctx do
    configure_price(1)
    grant!(ctx, 1, "concurrent-unit")

    intents =
      Enum.map(1..2, fn index ->
        execution_intent(ctx, "concurrent-#{index}", "concurrent-operation-#{index}")
      end)

    results = intents |> Enum.map(&Task.async(fn -> AI.execute(&1) end)) |> Task.await_many(5_000)

    assert Enum.count(results, &match?({:ok, _operation}, &1)) == 1
    assert Enum.count(results, &(&1 == {:error, :allowance_exhausted})) == 1
    assert Repo.aggregate(AllowanceReservation, :count) == 1

    assert {:ok, summary} = AI.allowance_summary(ctx.scope, ctx.workspace.id)
    assert summary.available_units == 0
    assert summary.reserved_units == 0
    assert summary.committed_units == 1
  end

  test "the ledger rejects mutation", ctx do
    grant!(ctx, 1, "append-only")
    entry = Repo.one!(AllowanceLedgerEntry)

    assert_raise Postgrex.Error, fn ->
      Repo.transaction(fn ->
        Repo.update_all(
          from(item in AllowanceLedgerEntry, where: item.id == ^entry.id),
          [set: [available_delta: 99]],
          mode: :savepoint
        )
      end)
    end
  end

  test "workspace deletion pseudonymizes but retains managed allowance history", ctx do
    grant!(ctx, 1, "retained-history")
    assert {:ok, operation} = execute(ctx, "retained", "retained-operation")
    entry_ids = Repo.all(from(entry in AllowanceLedgerEntry, select: entry.id))

    assert {:ok, _workspace} = Workspaces.delete_workspace(ctx.workspace)

    assert Repo.get!(Operation, operation.id).workspace_id == nil

    retained_entries =
      Repo.all(from(entry in AllowanceLedgerEntry, where: entry.id in ^entry_ids, order_by: entry.id))

    assert Enum.all?(retained_entries, &is_nil(&1.workspace_id))
    assert Enum.all?(retained_entries, &(&1.workspace_id_snapshot == ctx.workspace.id))
    assert Enum.map(retained_entries, & &1.kind) == ["grant", "reserve", "commit"]
  end

  test "workspace deletion does not strand a queued managed reservation", ctx do
    Application.put_env(:storyarn, ContractTask,
      scenario: :success,
      execution_mode: :background,
      managed_price: %{id: "contract-beta", version: 1, units: 2}
    )

    grant!(ctx, 2, "delete-while-queued")
    assert {:ok, queued} = execute(ctx, "queued", "delete-while-queued-operation")
    assert queued.execution_status == "queued"
    assert queued.settlement_status == "reserved"

    assert {:ok, _workspace} = Workspaces.delete_workspace(ctx.workspace)
    assert :ok = Operations.fail_queued_after_retries(queued.id, :workspace_deleted)

    failed = Repo.get!(Operation, queued.id)
    assert failed.workspace_id == nil
    assert failed.execution_status == "failed"
    assert failed.settlement_status == "released"

    reservation = Repo.get_by!(AllowanceReservation, operation_id: queued.id)
    assert reservation.status == "released"
    assert reservation.workspace_id == nil

    provider_reservation = Repo.get_by!(ProviderBudgetReservation, operation_id: queued.id)
    assert provider_reservation.status == "settled"
    assert Decimal.equal?(provider_reservation.actual_cost, Decimal.new(0))

    entries =
      Repo.all(
        from(entry in AllowanceLedgerEntry,
          where: entry.workspace_id_snapshot == ^ctx.workspace.id,
          order_by: entry.id
        )
      )

    assert Enum.all?(entries, &is_nil(&1.workspace_id))
    assert Enum.map(entries, & &1.kind) == ["grant", "reserve", "release", "expiry"]
  end

  defp configure_price(units) do
    Application.put_env(:storyarn, ContractTask,
      scenario: :success,
      execution_mode: :inline,
      managed_price: %{id: "contract-beta", version: 1, units: units}
    )
  end

  defp grant!(ctx, units, key) do
    assert {:ok, grant} =
             Allowance.grant(ctx.workspace.id, ctx.owner.id, %{
               grant_key: key,
               kind: "one_time",
               units: units
             })

    grant
  end

  defp execute(ctx, text, idempotency_key) do
    ctx
    |> execution_intent(text, idempotency_key)
    |> AI.execute()
  end

  defp execution_intent(ctx, text, idempotency_key) do
    assert {:ok, preflight_intent} =
             AI.new_intent(ctx.scope, %{
               workspace_id: ctx.workspace.id,
               project_id: ctx.project.id,
               task_id: "contract.echo",
               input: %{"text" => text}
             })

    assert {:ok, %{route_options: [%{requested_route_ref: route_ref}]}} = AI.preflight(preflight_intent)

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

  defp ledger_kinds(workspace_id) do
    Repo.all(
      from(entry in AllowanceLedgerEntry,
        where: entry.workspace_id_snapshot == ^workspace_id,
        order_by: [asc: entry.id],
        select: entry.kind
      )
    )
  end
end
