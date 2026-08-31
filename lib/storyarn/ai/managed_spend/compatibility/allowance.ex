defmodule Storyarn.AI.Allowance do
  @moduledoc "Compatibility contract for callers migrating to `Storyarn.AI.ManagedSpend`."

  alias Ecto.Changeset
  alias Storyarn.AI.AllowanceAccount
  alias Storyarn.AI.AllowanceGrant
  alias Storyarn.AI.ManagedSpend
  alias Storyarn.AI.ManagedSpend.Commands.Allowance, as: AllowanceCommands
  alias Storyarn.AI.Operation
  alias Storyarn.Repo

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
  def reserve(operation), do: run_atomically(fn -> AllowanceCommands.reserve(operation) end)

  @spec commit(Operation.t()) :: :ok | {:error, atom()}
  def commit(operation), do: run_atomically(fn -> AllowanceCommands.commit(operation) end)

  @spec release(Operation.t()) :: :ok | {:error, atom()}
  def release(operation), do: run_atomically(fn -> AllowanceCommands.release(operation) end)

  @spec expire_due() :: map()
  def expire_due, do: AllowanceCommands.expire_due()

  @spec expire_due(DateTime.t()) :: map()
  def expire_due(now), do: AllowanceCommands.expire_due(now)

  @spec expire_due(DateTime.t(), keyword()) :: map()
  defdelegate expire_due(now, opts), to: AllowanceCommands

  defp run_atomically(fun) do
    if Repo.in_transaction?() do
      fun.()
    else
      case Repo.transaction(fn -> rollback_on_error(fun.()) end) do
        {:ok, result} -> result
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp rollback_on_error({:error, reason}), do: Repo.rollback(reason)
  defp rollback_on_error(result), do: result
end
