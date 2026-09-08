defmodule Storyarn.Ideation.Sessions.Execution.ArchiveTimer do
  @moduledoc false
  import Ecto.Changeset

  alias Storyarn.Ideation.Sessions.Execution.TimerMutation
  alias Storyarn.Ideation.Sessions.Timer
  alias Storyarn.Repo

  def cancel(session_id) do
    case Repo.get_by(Timer, session_id: session_id) do
      %{status: status} = timer when status in [:running, :paused] ->
        timer
        |> change(
          version: timer.version + 1,
          status: :cancelled,
          deadline_at: nil,
          remaining_seconds: 0,
          completed_at: TimerMutation.now()
        )
        |> Repo.update()

      timer ->
        {:ok, timer}
    end
  end
end
