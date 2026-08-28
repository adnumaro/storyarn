defmodule Storyarn.AI.Governance.Queries.Policies do
  @moduledoc "Read-only workspace AI-policy queries. Missing rows mean AI disabled at version one."

  import Ecto.Query

  alias Storyarn.AI.Governance.Queries.WorkspaceAccess
  alias Storyarn.AI.WorkspacePolicy
  alias Storyarn.Repo

  @spec get(Storyarn.AI.Governance.scope(), pos_integer()) ::
          {:ok, WorkspacePolicy.t()} | {:error, :unauthorized}
  def get(%{user: nil}, _workspace_id), do: {:error, :unauthorized}

  def get(%{user: _user} = scope, workspace_id) when is_integer(workspace_id) and workspace_id > 0 do
    case WorkspaceAccess.get(scope, workspace_id) do
      {:ok, workspace, _membership} -> {:ok, get_effective(workspace.id)}
      _error -> {:error, :unauthorized}
    end
  end

  @spec get_effective(pos_integer()) :: WorkspacePolicy.t()
  def get_effective(workspace_id) when is_integer(workspace_id) and workspace_id > 0 do
    Repo.get_by(WorkspacePolicy, workspace_id: workspace_id) || default_policy(workspace_id)
  end

  @spec effective_by_workspace([pos_integer()]) :: %{optional(pos_integer()) => WorkspacePolicy.t()}
  def effective_by_workspace(workspace_ids) when is_list(workspace_ids) do
    workspace_ids = workspace_ids |> Enum.filter(&(is_integer(&1) and &1 > 0)) |> Enum.uniq()

    persisted =
      WorkspacePolicy
      |> where([policy], policy.workspace_id in ^workspace_ids)
      |> Repo.all()
      |> Map.new(&{&1.workspace_id, &1})

    Map.new(workspace_ids, fn workspace_id ->
      {workspace_id, Map.get(persisted, workspace_id, default_policy(workspace_id))}
    end)
  end

  defp default_policy(workspace_id) do
    %WorkspacePolicy{workspace_id: workspace_id, allowed_lanes: [], version: 1}
  end
end
