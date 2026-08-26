defmodule Storyarn.AI.Allowance do
  @moduledoc "Compatibility contract for callers migrating to `Storyarn.AI.ManagedSpend`."

  alias Ecto.Changeset
  alias Storyarn.AI.AllowanceAccount
  alias Storyarn.AI.AllowanceGrant
  alias Storyarn.AI.ManagedSpend
  alias Storyarn.AI.ManagedSpend.Commands.Allowance, as: AllowanceCommands
  alias Storyarn.AI.Operation

  @type summary :: ManagedSpend.summary()
  @type scope :: ManagedSpend.scope()

  @spec summary(scope(), pos_integer()) :: {:ok, summary()} | {:error, :unauthorized}
  defdelegate summary(scope, workspace_id), to: ManagedSpend

  @spec projection(pos_integer()) :: summary()
  defdelegate projection(workspace_id), to: ManagedSpend

  @spec grant(pos_integer(), pos_integer(), map()) ::
          {:ok, AllowanceGrant.t()} | {:error, atom() | Changeset.t()}
  defdelegate grant(workspace_id, actor_id, attrs), to: AllowanceCommands

  @spec set_status(pos_integer(), String.t()) :: {:ok, AllowanceAccount.t()} | {:error, atom()}
  defdelegate set_status(workspace_id, status), to: AllowanceCommands

  @spec reserve(Operation.t()) :: :ok | {:error, atom()}
  defdelegate reserve(operation), to: AllowanceCommands

  @spec commit(Operation.t()) :: :ok | {:error, atom()}
  defdelegate commit(operation), to: AllowanceCommands

  @spec release(Operation.t()) :: :ok | {:error, atom()}
  defdelegate release(operation), to: AllowanceCommands

  @spec expire_due() :: map()
  def expire_due, do: AllowanceCommands.expire_due()

  @spec expire_due(DateTime.t()) :: map()
  def expire_due(now), do: AllowanceCommands.expire_due(now)

  @spec expire_due(DateTime.t(), keyword()) :: map()
  defdelegate expire_due(now, opts), to: AllowanceCommands
end
