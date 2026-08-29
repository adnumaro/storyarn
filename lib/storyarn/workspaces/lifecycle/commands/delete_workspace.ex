defmodule Storyarn.Workspaces.Lifecycle.Commands.DeleteWorkspace do
  @moduledoc false

  alias Storyarn.Commercial
  alias Storyarn.Projects
  alias Storyarn.Repo
  alias Storyarn.Workspaces.Banner
  alias Storyarn.Workspaces.Workspace

  @spec delete(%{id: integer()}) :: {:ok, Workspace.t()} | {:error, term()}
  def delete(%{id: _} = workspace) do
    result =
      Commercial.transact_with_workspace_lock(workspace.id, fn locked_workspace ->
        with {:ok, workspace} <- get_locked_workspace(locked_workspace.id),
             {:ok, project_cleanup} <- Projects.prepare_workspace_data_hard_delete(locked_workspace.id),
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

  defp get_locked_workspace(workspace_id) do
    case Repo.get(Workspace, workspace_id) do
      %Workspace{} = workspace -> {:ok, workspace}
      nil -> {:error, :workspace_not_found}
    end
  end
end
