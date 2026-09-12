defmodule Storyarn.Ideation.Ideas.Events.Invalidation do
  @moduledoc false
  alias Phoenix.PubSub

  def subscribe(project_id, session_id, actor_id) do
    with :ok <- PubSub.subscribe(Storyarn.PubSub, topic(project_id, session_id, :shared)) do
      PubSub.subscribe(Storyarn.PubSub, topic(project_id, session_id, actor_id))
    end
  end

  # Only commands that change an existing discussion's audience add this
  # signal. Ordinary shared canvas activity must not invalidate inboxes.
  def broadcast(project_id, _session_id, :comment_sources),
    do: Storyarn.Projects.invalidate_ideation_comment_sources(project_id)

  def broadcast(project_id, session_id, audience) do
    PubSub.broadcast(Storyarn.PubSub, topic(project_id, session_id, audience), {:ideation_changed, session_id})
  end

  def unsubscribe(project_id, session_id, actor_id) do
    PubSub.unsubscribe(Storyarn.PubSub, topic(project_id, session_id, :shared))
    PubSub.unsubscribe(Storyarn.PubSub, topic(project_id, session_id, actor_id))
  end

  defp topic(project_id, session_id, audience), do: "ideation:#{project_id}:#{session_id}:#{audience}"
end
