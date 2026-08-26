defmodule Storyarn.AI.Governance.Commands.Policies do
  @moduledoc "Owner-authorized, serialized workspace AI-policy transitions."

  import Ecto.Query

  alias Storyarn.AI.Governance.Adapters.Postgres.PolicyLock
  alias Storyarn.AI.Governance.Queries.WorkspaceAccess
  alias Storyarn.AI.Governance.Rules.PolicyLanes
  alias Storyarn.AI.WorkspacePolicy
  alias Storyarn.AI.WorkspacePolicyAudit
  alias Storyarn.Repo

  @spec update(Storyarn.AI.Governance.scope(), pos_integer(), [String.t()]) ::
          {:ok, WorkspacePolicy.t()} | {:error, :unauthorized | :invalid_policy | Ecto.Changeset.t()}
  def update(%{user: nil}, _workspace_id, _lanes), do: {:error, :unauthorized}

  def update(%{user: %{id: user_id}} = scope, workspace_id, lanes)
      when is_integer(workspace_id) and workspace_id > 0 and is_list(lanes) do
    with {:ok, normalized_lanes} <- PolicyLanes.normalize(lanes),
         {:ok, workspace, membership} <- WorkspaceAccess.get(scope, workspace_id),
         true <- WorkspaceAccess.can?(membership.role, :manage_workspace) do
      Repo.transaction(fn -> update_locked(workspace.id, user_id, normalized_lanes) end)
    else
      false -> {:error, :unauthorized}
      {:error, :not_found} -> {:error, :unauthorized}
      {:error, reason} -> {:error, reason}
    end
  end

  def update(%{user: _user}, _workspace_id, _lanes), do: {:error, :invalid_policy}

  @doc "Returns the effective policy with a row lock. Call only inside an existing transaction."
  @spec lock_effective(pos_integer()) :: WorkspacePolicy.t()
  def lock_effective(workspace_id) when is_integer(workspace_id) and workspace_id > 0 do
    query = from(policy in WorkspacePolicy, where: policy.workspace_id == ^workspace_id, lock: "FOR UPDATE")
    Repo.one(query) || %WorkspacePolicy{workspace_id: workspace_id, allowed_lanes: [], version: 1}
  end

  defp update_locked(workspace_id, user_id, lanes) do
    PolicyLock.lock!(workspace_id)
    current = lock_effective(workspace_id)

    if current.allowed_lanes == lanes do
      current
    else
      persist_transition(current, workspace_id, user_id, lanes)
    end
  end

  defp persist_transition(current, workspace_id, user_id, lanes) do
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
