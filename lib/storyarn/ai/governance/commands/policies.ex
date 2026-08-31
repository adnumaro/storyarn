defmodule Storyarn.AI.Governance.Commands.Policies do
  @moduledoc "Owner-authorized, serialized workspace AI-policy transitions."

  import Ecto.Query

  alias Storyarn.AI.Governance.Adapters.Postgres.PolicyLock
  alias Storyarn.AI.Governance.Projections.WorkspaceMembershipRecord
  alias Storyarn.AI.Governance.Projections.WorkspaceRecord
  alias Storyarn.AI.Governance.Rules.PolicyLanes
  alias Storyarn.AI.WorkspacePolicy
  alias Storyarn.AI.WorkspacePolicyAudit
  alias Storyarn.Repo

  @spec update(Storyarn.AI.Governance.scope(), pos_integer(), [String.t()]) ::
          {:ok, WorkspacePolicy.t()}
          | {:error, :unauthorized | :invalid_policy | :ownership_invariant_violation | Ecto.Changeset.t()}
  def update(%{user: nil}, _workspace_id, _lanes), do: {:error, :unauthorized}

  def update(%{user: %{id: user_id}}, workspace_id, lanes)
      when is_integer(workspace_id) and workspace_id > 0 and is_list(lanes) do
    with {:ok, normalized_lanes} <- PolicyLanes.normalize(lanes) do
      update_authorized(workspace_id, user_id, normalized_lanes)
    end
  end

  def update(%{user: _user}, _workspace_id, _lanes), do: {:error, :invalid_policy}

  defp update_authorized(workspace_id, user_id, normalized_lanes) do
    Repo.transact(fn -> update_authorized_locked(workspace_id, user_id, normalized_lanes) end)
  end

  defp update_authorized_locked(workspace_id, user_id, normalized_lanes) do
    with :ok <- lock_authorized_owner(workspace_id, user_id) do
      {:ok, update_locked(workspace_id, user_id, normalized_lanes)}
    end
  end

  @doc "Returns the effective policy with a row lock. Call only inside an existing transaction."
  @spec lock_effective(pos_integer()) :: WorkspacePolicy.t()
  def lock_effective(workspace_id) when is_integer(workspace_id) and workspace_id > 0 do
    query = from(policy in WorkspacePolicy, where: policy.workspace_id == ^workspace_id, lock: "FOR UPDATE")
    Repo.one(query) || %WorkspacePolicy{workspace_id: workspace_id, allowed_lanes: [], version: 1}
  end

  defp lock_authorized_owner(workspace_id, user_id) do
    workspace_query =
      from(workspace in WorkspaceRecord,
        where: workspace.id == ^workspace_id,
        lock: "FOR UPDATE"
      )

    case Repo.one(workspace_query) do
      %WorkspaceRecord{} = workspace -> lock_and_authorize_owner(workspace, user_id)
      nil -> {:error, :unauthorized}
    end
  end

  defp lock_and_authorize_owner(%WorkspaceRecord{} = workspace, user_id) do
    membership_query =
      from(membership in WorkspaceMembershipRecord,
        where: membership.workspace_id == ^workspace.id and membership.role == "owner",
        order_by: [asc: membership.user_id, asc: membership.id],
        lock: "FOR UPDATE"
      )

    case Repo.all(membership_query) do
      [%WorkspaceMembershipRecord{user_id: owner_id}] when owner_id == workspace.owner_id ->
        if owner_id == user_id, do: :ok, else: {:error, :unauthorized}

      _missing_or_ambiguous_owner ->
        {:error, :ownership_invariant_violation}
    end
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
