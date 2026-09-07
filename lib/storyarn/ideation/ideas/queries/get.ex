defmodule Storyarn.Ideation.Ideas.Queries.Get do
  @moduledoc false
  alias Storyarn.Ideation.Ideas.Queries.Access
  alias Storyarn.Ideation.Ideas.Queries.Visible

  def run(scope, project_id, session_id, idea_id) do
    with {:ok, actor_id} <- Access.authorize(scope, project_id, session_id) do
      Visible.get(session_id, idea_id, actor_id)
    end
  end
end
