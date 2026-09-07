defmodule Storyarn.Ideation.Sessions.Adapters.ProjectAccess do
  @moduledoc false

  alias Storyarn.Projects

  def read(scope, project_id), do: authorize(scope, project_id, :view, false)
  def write(scope, project_id), do: authorize(scope, project_id, :edit_content, true)

  def eligible_delegate?(project_id, user_id) when is_integer(user_id) and user_id > 0 do
    case write(%{user: %{id: user_id}}, project_id) do
      {:ok, _access} -> true
      {:error, _reason} -> false
    end
  end

  def eligible_delegate?(_project_id, _user_id), do: false

  defp authorize(scope, project_id, action, locked?) do
    result =
      if locked?,
        do: Projects.authorize_locked(scope, project_id, action),
        else: Projects.authorize(scope, project_id, action)

    case result do
      {:ok, project, membership} ->
        {:ok, %{project_id: project.id, user_id: membership.user_id, owner?: project.owner_id == membership.user_id}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
