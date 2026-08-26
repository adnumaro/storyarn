defmodule Storyarn.AI.ManagedSpend do
  @moduledoc """
  Public boundary for managed AI allowance and provider-cost settlement.

  Reads are exposed as summaries or projections. Mutations retain the existing
  database transaction and advisory-lock domains in their command modules.
  """

  alias Ecto.Changeset
  alias Storyarn.AI.AllowanceAccount
  alias Storyarn.AI.AllowanceGrant
  alias Storyarn.AI.ManagedSpend.Commands.Allowance, as: AllowanceCommands
  alias Storyarn.AI.ManagedSpend.Execution.AllowanceSummary
  alias Storyarn.AI.ManagedSpend.Queries.Allowance, as: AllowanceQueries
  alias Storyarn.AI.Operation
  alias Storyarn.AI.Settlement

  @type summary :: AllowanceQueries.summary()
  @type scope :: %{required(:user) => %{required(:id) => pos_integer(), optional(atom()) => term()}}

  @spec summary(scope(), pos_integer()) :: {:ok, summary()} | {:error, :unauthorized}
  defdelegate summary(scope, workspace_id), to: AllowanceSummary, as: :run

  @spec projection(pos_integer()) :: summary()
  defdelegate projection(workspace_id), to: AllowanceQueries

  @spec grant(pos_integer(), pos_integer(), map()) ::
          {:ok, AllowanceGrant.t()} | {:error, atom() | Changeset.t()}
  defdelegate grant(workspace_id, actor_id, attrs), to: AllowanceCommands

  @spec set_status(pos_integer(), String.t()) :: {:ok, AllowanceAccount.t()} | {:error, atom()}
  defdelegate set_status(workspace_id, status), to: AllowanceCommands

  @spec expire_due() :: map()
  def expire_due, do: AllowanceCommands.expire_due()

  @spec expire_due(DateTime.t()) :: map()
  def expire_due(now), do: AllowanceCommands.expire_due(now)

  @spec expire_due(DateTime.t(), keyword()) :: map()
  defdelegate expire_due(now, opts), to: AllowanceCommands

  @spec available?(atom()) :: boolean()
  defdelegate available?(lane), to: Settlement

  @spec preflight_status(atom(), pos_integer(), pos_integer()) :: :ok | {:error, atom()}
  defdelegate preflight_status(lane, workspace_id, units), to: Settlement

  @spec reserve(Operation.t()) :: :ok | {:error, atom()}
  defdelegate reserve(operation), to: Settlement

  @spec commit(Operation.t()) :: :ok | {:error, atom()}
  defdelegate commit(operation), to: Settlement

  @spec release(Operation.t()) :: :ok | {:error, atom()}
  defdelegate release(operation), to: Settlement
end
