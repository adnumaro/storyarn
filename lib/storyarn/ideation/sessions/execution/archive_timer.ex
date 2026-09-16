defmodule Storyarn.Ideation.Sessions.Execution.ArchiveTimer do
  @moduledoc false
  import Ecto.Changeset
  import Ecto.Query

  alias Storyarn.Ideation.Sessions.Execution.TimerMutation
  alias Storyarn.Ideation.Sessions.Timer
  alias Storyarn.Repo

  # Stops the session's live clock, whichever round holds it; stopped clocks stay as they are.
  def cancel(session_id) do
    case Repo.one(from t in Timer, where: t.session_id == ^session_id and t.status in [:running, :paused]) do
      nil -> {:ok, nil}
      timer -> timer |> change(TimerMutation.cancel_attrs(timer)) |> Repo.update()
    end
  end
end
