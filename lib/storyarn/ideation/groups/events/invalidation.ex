defmodule Storyarn.Ideation.Groups.Events.Invalidation do
  @moduledoc false

  def broadcast(project_id, session_id) do
    Phoenix.PubSub.broadcast(Storyarn.PubSub, "ideation:comment_sources", {:ideation_comment_sources_changed, project_id})

    Phoenix.PubSub.broadcast(
      Storyarn.PubSub,
      "ideation:#{project_id}:#{session_id}:shared",
      {:ideation_changed, session_id}
    )
  end
end
