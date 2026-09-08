defmodule Storyarn.Ideation.Sessions.Commands.ExtendTimer do
  @moduledoc false
  alias Storyarn.Ideation.Sessions.Execution.TimerMutation

  def run(scope, project_id, session_id, revision, version, seconds)
      when is_integer(seconds) and seconds > 0 and seconds <= 86_400 do
    TimerMutation.run(scope, project_id, session_id, revision, fn session, access, timer ->
      with {:ok, timer} <- TimerMutation.current(timer, version),
           {:ok, current_remaining} <- extendable(timer),
           true <- timer.duration_seconds + seconds <= 86_400 || {:error, :invalid_timer_duration} do
        remaining = current_remaining + seconds

        TimerMutation.save(
          session,
          access,
          timer,
          %{
            version: timer.version + 1,
            duration_seconds: timer.duration_seconds + seconds,
            remaining_seconds: remaining,
            deadline_at: if(timer.status == :running, do: DateTime.add(TimerMutation.now(), remaining, :second))
          },
          :timer_extended
        )
      end
    end)
  end

  def run(_, _, _, _, _, _), do: {:error, :invalid_timer_duration}
  defp extendable(%{status: :paused, remaining_seconds: seconds}), do: {:ok, seconds}
  defp extendable(timer), do: TimerMutation.active(timer)
end
