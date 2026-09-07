defmodule Storyarn.Ideation.Sessions.Queries.ProjectAccess do
  @moduledoc false

  alias Storyarn.Projects

  def authorize(scope, project_id) do
    case Projects.authorize(scope, project_id, :view) do
      {:ok, _project, _membership} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
