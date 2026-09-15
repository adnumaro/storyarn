defmodule Storyarn.Ideation.Decisions.Queries.Access do
  @moduledoc false

  alias Storyarn.Ideation.Sessions
  alias Storyarn.Projects

  def read(scope, project_id, session_id) do
    with {:ok, project, membership} <- Projects.authorize(scope, project_id, :view),
         {:ok, session} <- Sessions.get_session(scope, project_id, session_id) do
      {:ok,
       %{
         session_id: session.id,
         user_id: scope.user.id,
         open?: session.status == :open,
         editor?: Projects.can?(membership.role, :edit_content),
         owner?: project.owner_id == scope.user.id
       }}
    end
  end
end
