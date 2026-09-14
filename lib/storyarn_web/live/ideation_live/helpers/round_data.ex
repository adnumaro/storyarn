defmodule StoryarnWeb.IdeationLive.Helpers.RoundData do
  @moduledoc false
  alias Storyarn.Ideation
  alias StoryarnWeb.IdeationLive.Helpers.TimerData

  # The canvas draws every round as a band, so it always receives the whole list.
  def load(scope, project_id, session_id) do
    with {:ok, context} <- Ideation.get_canvas_context(scope, project_id, session_id) do
      {:ok,
       %{
         rounds: Enum.map(context.rounds, &round_view/1),
         active_round: if(context.active_round, do: round_view(context.active_round)),
         timer: TimerData.project(context.timer)
       }}
    end
  end

  def round_view(value),
    do:
      Map.take(value, [
        :id,
        :session_id,
        :number,
        :prompt,
        :status,
        :canvas_offset_y,
        :started_at,
        :closed_at,
        :inserted_at,
        :updated_at
      ])
end
