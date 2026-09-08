defmodule Storyarn.Ideation.Groups.Events.Invalidation do
  @moduledoc false

  def broadcast(project_id, session_id) do
    Phoenix.PubSub.broadcast(
      Storyarn.PubSub,
      "ideation:#{project_id}:#{session_id}:shared",
      {:ideation_changed, session_id}
    )
  end
end
