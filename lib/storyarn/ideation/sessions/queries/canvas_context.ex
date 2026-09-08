defmodule Storyarn.Ideation.Sessions.Queries.CanvasContext do
  @moduledoc false

  alias Storyarn.Ideation.Sessions.Queries.Get
  alias Storyarn.Ideation.Sessions.Queries.RoundContext
  alias Storyarn.Ideation.Sessions.Timer
  alias Storyarn.Repo

  def run(scope, project_id, session_id, opts) do
    with {:ok, session} <- Get.run(scope, project_id, session_id),
         {:ok, rounds} <- RoundContext.for_session(session.id, opts) do
      {:ok, Map.put(rounds, :timer, Repo.get_by(Timer, session_id: session.id))}
    end
  end
end
