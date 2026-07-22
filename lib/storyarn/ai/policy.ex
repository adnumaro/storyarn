defmodule Storyarn.AI.Policy do
  @moduledoc "Read and owner-only mutation boundary for workspace AI policy."

  import Ecto.Query

  alias Storyarn.Accounts.Scope
  alias Storyarn.AI.WorkspacePolicy
  alias Storyarn.AI.WorkspacePolicyAudit
  alias Storyarn.Repo
  alias Storyarn.Workspaces

  @lock_namespace 981_004

  @spec get(Scope.t(), pos_integer()) :: {:ok, WorkspacePolicy.t()} | {:error, :unauthorized}
  def get(%Scope{user: nil}, _workspace_id), do: {:error, :unauthorized}

  def get(%Scope{} = scope, workspace_id) when is_integer(workspace_id) and workspace_id > 0 do
    case Workspaces.get_workspace(scope, workspace_id) do
      {:ok, workspace, _membership} -> {:ok, get_effective(workspace.id)}
      _error -> {:error, :unauthorized}
    end
  end

  @spec update(Scope.t(), pos_integer(), [String.t()]) ::
          {:ok, WorkspacePolicy.t()} | {:error, :unauthorized | :invalid_policy | Ecto.Changeset.t()}
  def update(%Scope{user: nil}, _workspace_id, _lanes), do: {:error, :unauthorized}

  def update(%Scope{user: user} = scope, workspace_id, lanes)
      when is_integer(workspace_id) and workspace_id > 0 and is_list(lanes) do
    normalized_lanes = lanes |> Enum.uniq() |> Enum.sort()

    if Enum.all?(normalized_lanes, &(&1 in WorkspacePolicy.initial_lanes())) do
      update_authorized(scope, workspace_id, user.id, normalized_lanes)
    else
      {:error, :invalid_policy}
    end
  end

  def update(%Scope{}, _workspace_id, _lanes), do: {:error, :invalid_policy}

  defp update_authorized(scope, workspace_id, user_id, lanes) do
    with {:ok, workspace, membership} <- Workspaces.get_workspace(scope, workspace_id),
         true <- Workspaces.can?(membership.role, :manage_workspace) do
      Repo.transaction(fn -> update_locked(workspace.id, user_id, lanes) end)
    else
      false -> {:error, :unauthorized}
      {:error, _reason} -> {:error, :unauthorized}
    end
  end

  @doc false
  @spec get_effective(pos_integer(), keyword()) :: WorkspacePolicy.t()
  def get_effective(workspace_id, opts \\ []) do
    query = from(policy in WorkspacePolicy, where: policy.workspace_id == ^workspace_id)
    query = if Keyword.get(opts, :lock, false), do: lock(query, "FOR UPDATE"), else: query

    Repo.one(query) || %WorkspacePolicy{workspace_id: workspace_id, allowed_lanes: [], version: 1}
  end

  defp update_locked(workspace_id, user_id, lanes) do
    lock_workspace_policy!(workspace_id)
    current = get_effective(workspace_id, lock: true)

    if current.allowed_lanes == lanes do
      current
    else
      next_version = current.version + 1

      policy =
        current
        |> WorkspacePolicy.changeset(%{
          allowed_lanes: lanes,
          version: next_version,
          updated_by_id: user_id
        })
        |> Repo.insert_or_update!()

      %WorkspacePolicyAudit{}
      |> WorkspacePolicyAudit.changeset(%{
        workspace_id: workspace_id,
        workspace_id_snapshot: workspace_id,
        user_id: user_id,
        actor_id: user_id,
        from_lanes: current.allowed_lanes,
        to_lanes: lanes,
        from_version: current.version,
        to_version: next_version
      })
      |> Repo.insert!()

      policy
    end
  end

  defp lock_workspace_policy!(workspace_id) do
    Repo.query!("SELECT pg_advisory_xact_lock($1, $2)", [@lock_namespace, workspace_id])
  end
end
