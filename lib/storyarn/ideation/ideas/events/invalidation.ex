defmodule Storyarn.Ideation.Ideas.Events.Invalidation do
  @moduledoc false
  alias Phoenix.PubSub

  def subscribe(project_id, session_id, actor_id) do
    with :ok <- PubSub.subscribe(Storyarn.PubSub, topic(project_id, session_id, :shared)) do
      PubSub.subscribe(Storyarn.PubSub, topic(project_id, session_id, actor_id))
    end
  end

  def broadcast(project_id, session_id, audience) do
    PubSub.broadcast(Storyarn.PubSub, topic(project_id, session_id, audience), {:ideation_changed, session_id})
  end

  defp topic(project_id, session_id, audience), do: "ideation:#{project_id}:#{session_id}:#{audience}"
end
