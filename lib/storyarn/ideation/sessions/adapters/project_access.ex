defmodule Storyarn.Ideation.Sessions.Adapters.ProjectAccess do
  @moduledoc false

  alias Storyarn.Projects

  defdelegate lock_background_write(project_id), to: Projects

  def eligible_delegate?(scope, project_id, user_id) do
    case Projects.check_editor_candidate_locked(scope, project_id, user_id) do
      {:ok, eligible?} -> eligible?
      {:error, _reason} -> false
    end
  end

  def write(scope, project_id) do
    case Projects.authorize_locked(scope, project_id, :edit_content) do
      {:ok, project, membership} ->
        {:ok, %{project_id: project.id, user_id: membership.user_id, owner?: project.owner_id == membership.user_id}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
