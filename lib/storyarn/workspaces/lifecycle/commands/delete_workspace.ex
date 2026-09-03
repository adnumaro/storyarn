defmodule Storyarn.Workspaces.Lifecycle.Commands.DeleteWorkspace do
  @moduledoc false

  import Ecto.Query

  alias Storyarn.Commercial
  alias Storyarn.Projects
  alias Storyarn.Repo
  alias Storyarn.Workspaces.Banner
  alias Storyarn.Workspaces.Workspace
  alias Storyarn.Workspaces.WorkspaceMembership

  @max_pg_bigint 9_223_372_036_854_775_807

  defguardp valid_id(id)
            when is_integer(id) and id > 0 and id <= @max_pg_bigint

  @spec delete(map(), pos_integer()) :: {:ok, Workspace.t()} | {:error, term()}
  def delete(%{user: %{id: user_id}}, workspace_id) when is_integer(user_id) and user_id > 0 and valid_id(workspace_id) do
    result =
      Commercial.transact_with_workspace_lock(workspace_id, fn locked_workspace ->
        with :ok <- lock_and_authorize_owner(locked_workspace, user_id),
             {:ok, workspace} <- get_locked_workspace(workspace_id),
             {:ok, provider_namespace_fingerprint} <- Projects.storage_provider_namespace_fingerprint(),
             {:ok, project_cleanup} <-
               Projects.prepare_workspace_data_hard_delete(
                 locked_workspace.id,
                 provider_namespace_fingerprint
               ),
             :ok <- Banner.prepare_hard_delete(workspace),
             {:ok, deleted_workspace} <- Repo.delete(workspace) do
          {:ok, {deleted_workspace, project_cleanup}}
        end
      end)

    case result do
      {:ok, {deleted_workspace, project_cleanup}} ->
        :ok = Projects.publish_committed_workspace_data_hard_delete(project_cleanup)
        {:ok, deleted_workspace}

      error ->
        error
    end
  end

  def delete(_scope, _workspace_id), do: {:error, :unauthorized}

  defp lock_and_authorize_owner(%{id: workspace_id, owner_id: canonical_owner_id}, user_id) do
    query =
      from(membership in WorkspaceMembership,
        where: membership.workspace_id == ^workspace_id and membership.role == "owner",
        order_by: [asc: membership.user_id, asc: membership.id],
        lock: "FOR UPDATE"
      )

    case Repo.all(query) do
      [%WorkspaceMembership{user_id: owner_id}] when owner_id == canonical_owner_id ->
        if owner_id == user_id, do: :ok, else: {:error, :unauthorized}

      _missing_or_ambiguous_owner ->
        {:error, :ownership_invariant_violation}
    end
  end

  defp get_locked_workspace(workspace_id) do
    case Repo.get(Workspace, workspace_id) do
      %Workspace{} = workspace -> {:ok, workspace}
      nil -> {:error, :workspace_not_found}
    end
  end
end
