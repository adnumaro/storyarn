defmodule Storyarn.Ideation.Sessions.Commands.PauseTimer do
  @moduledoc false
  alias Storyarn.Ideation.Sessions.Execution.TimerMutation

  def run(scope, project_id, session_id, revision, version) do
    TimerMutation.run(scope, project_id, session_id, revision, fn session, access, timer ->
      with {:ok, timer} <- TimerMutation.current(timer, version),
           {:ok, remaining} <- TimerMutation.active(timer) do
        TimerMutation.save(
          session,
          access,
          timer,
          %{
            version: timer.version + 1,
            status: :paused,
            remaining_seconds: remaining,
            deadline_at: nil
          },
          :timer_paused
        )
      end
    end)
  end
end
