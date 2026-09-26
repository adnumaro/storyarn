defmodule Storyarn.Workspaces.Memberships.Queries.ReadOnly do
  @moduledoc false

  alias Storyarn.Commercial
  alias Storyarn.Workspaces.Memberships.Rules.ReadOnlyActions

  @doc """
  Refuses an action a read-only workspace does not allow. The workspace is
  read-only while its owner's account is over its plan's limits.
  """
  @spec ensure_allowed(pos_integer(), atom()) :: :ok | {:error, :read_only}
  def ensure_allowed(workspace_id, action) do
    if ReadOnlyActions.allowed?(action), do: :ok, else: ensure_writable(workspace_id)
  end

  @spec ensure_writable(pos_integer()) :: :ok | {:error, :read_only}
  def ensure_writable(workspace_id) do
    workspace_id
    |> Commercial.workspace_read_only_reasons()
    |> refuse_when_read_only()
  end

  @doc "Refuses to add a workspace to an account that is over its plan's limits."
  @spec ensure_account_writable(pos_integer()) :: :ok | {:error, :read_only}
  def ensure_account_writable(user_id) do
    user_id
    |> Commercial.account_read_only_reasons()
    |> refuse_when_read_only()
  end

  defp refuse_when_read_only([]), do: :ok
  defp refuse_when_read_only(_reasons), do: {:error, :read_only}
end
