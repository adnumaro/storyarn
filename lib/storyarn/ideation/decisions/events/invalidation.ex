defmodule Storyarn.Ideation.Decisions.Events.Invalidation do
  @moduledoc false

  def broadcast(project_id, session_id) do
    Phoenix.PubSub.broadcast(
      Storyarn.PubSub,
      "ideation:#{project_id}:#{session_id}:shared",
      {:ideation_decisions_changed, session_id}
    )

    # Content open in an editor shows decisions from any session of the project.
    Phoenix.PubSub.broadcast(
      Storyarn.PubSub,
      project_topic(project_id),
      {:ideation_project_decisions_changed, project_id}
    )
  end

  def subscribe(project_id), do: Phoenix.PubSub.subscribe(Storyarn.PubSub, project_topic(project_id))

  defp project_topic(project_id), do: "ideation:#{project_id}:decisions"
end
