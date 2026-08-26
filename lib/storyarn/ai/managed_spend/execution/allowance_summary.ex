defmodule Storyarn.AI.ManagedSpend.Execution.AllowanceSummary do
  @moduledoc """
  Authorizes an allowance summary and refreshes expired grant state first.

  This is deliberately an execution coordinator rather than a query: preserving
  the established summary contract requires expiring due grants under the
  allowance account lock before returning the balance.
  """

  alias Storyarn.AI.Governance
  alias Storyarn.AI.ManagedSpend.Commands.Allowance, as: AllowanceCommands
  alias Storyarn.AI.ManagedSpend.Queries.Allowance, as: AllowanceQueries

  @type scope :: %{required(:user) => %{required(:id) => pos_integer(), optional(atom()) => term()}}

  @spec run(scope(), pos_integer()) :: {:ok, AllowanceQueries.summary()} | {:error, :unauthorized}
  def run(%{user: _} = scope, workspace_id) do
    case Governance.get_workspace(scope, workspace_id) do
      {:ok, workspace, _membership} ->
        workspace.id
        |> AllowanceCommands.refresh_account()
        |> AllowanceQueries.account_summary()
        |> then(&{:ok, &1})

      _error ->
        {:error, :unauthorized}
    end
  end
end
