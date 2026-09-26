defmodule Storyarn.AI.Governance.Adapters.Commercial.WorkspaceReadOnly do
  @moduledoc """
  Commercial port for AI admission: a workspace whose owner's account is over
  its plan's limits is read-only and admits no new AI work.
  """

  alias Storyarn.Commercial

  @spec ensure_writable(pos_integer() | nil) :: :ok | {:error, :read_only}
  def ensure_writable(nil), do: :ok

  def ensure_writable(workspace_id) when is_integer(workspace_id) do
    case Commercial.workspace_read_only_reasons(workspace_id) do
      [] -> :ok
      _reasons -> {:error, :read_only}
    end
  end
end
