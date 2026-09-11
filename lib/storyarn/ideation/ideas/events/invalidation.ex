defmodule Storyarn.Ideation.Ideas.Events.Invalidation do
  @moduledoc false
  alias Phoenix.PubSub

  def subscribe(project_id, session_id, actor_id) do
    with :ok <- PubSub.subscribe(Storyarn.PubSub, topic(project_id, session_id, :shared)) do
      PubSub.subscribe(Storyarn.PubSub, topic(project_id, session_id, actor_id))
    end
  end

  def broadcast(project_id, session_id, audience) do
    if audience == :shared do
      PubSub.broadcast(Storyarn.PubSub, "ideation:comment_sources", {:ideation_comment_sources_changed, project_id})
    end

    PubSub.broadcast(Storyarn.PubSub, topic(project_id, session_id, audience), {:ideation_changed, session_id})
  end

  def unsubscribe(project_id, session_id, actor_id) do
    PubSub.unsubscribe(Storyarn.PubSub, topic(project_id, session_id, :shared))
    PubSub.unsubscribe(Storyarn.PubSub, topic(project_id, session_id, actor_id))
  end

  defp topic(project_id, session_id, audience), do: "ideation:#{project_id}:#{session_id}:#{audience}"
end
