defmodule Storyarn.Ideation.Groups.Events.Invalidation do
  @moduledoc false

  def broadcast(project_id, session_id, operation) do
    if operation in ~w(delete restore) do
      Storyarn.Projects.invalidate_ideation_comment_sources(project_id)
    end

    Phoenix.PubSub.broadcast(
      Storyarn.PubSub,
      "ideation:#{project_id}:#{session_id}:shared",
      {:ideation_changed, session_id}
    )
  end
end
