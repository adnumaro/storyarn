defmodule Storyarn.AI.ManagedSpend.PublicContractTest do
  use ExUnit.Case, async: true

  alias Storyarn.AI.ManagedSpend
  alias Storyarn.AI.ProviderBudget
  alias Storyarn.AI.SettlementAdapter

  @facade_api [
    available?: 1,
    preflight_status: 3,
    summary: 2,
    projection: 1,
    grant: 3,
    set_status: 2,
    expire_due: 0,
    expire_due: 1,
    expire_due: 2,
    reserve: 1,
    commit: 1,
    release: 1
  ]

  @compatibility_api [
    summary: 2,
    projection: 1,
    grant: 3,
    set_status: 2,
    reserve: 1,
    commit: 1,
    release: 1,
    expire_due: 0,
    expire_due: 1,
    expire_due: 2
  ]

  @stable_entities [
    Storyarn.AI.AllowanceAccount,
    Storyarn.AI.AllowanceAllocation,
    Storyarn.AI.AllowanceGrant,
    Storyarn.AI.AllowanceLedgerEntry,
    Storyarn.AI.AllowanceReservation,
    Storyarn.AI.ProviderBudgetReservation,
    Storyarn.AI.UsageEvent
  ]

  test "the capability facade keeps its intentional entry points" do
    assert exports(ManagedSpend) == Enum.sort(@facade_api)
  end

  test "rolling callers retain the former allowance contract" do
    assert Enum.all?(@compatibility_api, fn {name, arity} ->
             exported?(Storyarn.AI.Allowance, name, arity)
           end)

    assert exported?(ProviderBudget, :reserve, 2)
    assert exported?(ProviderBudget, :settle, 1)
  end

  test "persisted entity and configurable settlement identities remain stable" do
    assert Enum.all?(@stable_entities, &exported?(&1, :__schema__, 1))

    assert exported?(Storyarn.AI.Settlement, :reserve, 1)
    assert exported?(Storyarn.AI.Settlement.Managed, :reserve, 1)
    assert exported?(Storyarn.AI.Settlement.Unavailable, :reserve, 1)
    assert Code.ensure_loaded?(SettlementAdapter)
    assert SettlementAdapter.behaviour_info(:callbacks) != []
  end

  defp exports(module) do
    :functions
    |> module.__info__()
    |> Enum.reject(fn {name, _arity} -> name in [:__info__, :module_info] end)
    |> Enum.sort()
  end

  defp exported?(module, name, arity) do
    Code.ensure_loaded?(module) and function_exported?(module, name, arity)
  end
end
