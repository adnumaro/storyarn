defmodule Storyarn.Ideation.Sessions.Adapters.ProjectAccess do
  @moduledoc false

  alias Storyarn.Projects

  defdelegate lock_background_write(project_id), to: Projects

  def exclusive_write(scope, project_id), do: write(scope, project_id, :update)

  def eligible_delegate?(scope, project_id, user_id) do
    case Projects.check_editor_candidate_locked(scope, project_id, user_id) do
      {:ok, eligible?} -> eligible?
      {:error, _reason} -> false
    end
  end

  def write(scope, project_id, lock_mode \\ :share) do
    case Projects.authorize_locked(scope, project_id, :edit_content, lock_mode) do
      {:ok, project, membership} ->
        {:ok, %{project_id: project.id, user_id: membership.user_id, owner?: project.owner_id == membership.user_id}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
