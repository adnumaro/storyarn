defmodule Storyarn.Ideation.Sessions.Commands.CloseRound do
  @moduledoc false

  alias Storyarn.Ideation.Sessions.Events.TimerInvalidation
  alias Storyarn.Ideation.Sessions.Execution.RoundMutation
  alias Storyarn.Platform.Shared.TimeHelpers

  def run(scope, project_id, session_id, round_id, revision) do
    scope
    |> RoundMutation.run(project_id, session_id, revision, fn session, access ->
      with {:ok, round} <- RoundMutation.get(session.id, round_id) do
        close(session, access, round)
      end
    end)
    |> TimerInvalidation.notify()
  end

  defp close(session, _access, %{status: :closed}), do: {:ok, session}

  defp close(session, access, round) do
    now = %{TimeHelpers.now() | microsecond: {0, 6}}

    with {:ok, session, closed} <- RoundMutation.close(session, access, round, now) do
      RoundMutation.record(session, access, closed, :round_closed)
    end
  end
end
