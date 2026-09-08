defmodule Storyarn.Ideation.Sessions.Commands.CancelTimer do
  @moduledoc false
  alias Storyarn.Ideation.Sessions.Execution.TimerMutation

  def run(scope, project_id, session_id, revision, version) do
    TimerMutation.run(scope, project_id, session_id, revision, fn session, access, timer ->
      with {:ok, timer} <- TimerMutation.current(timer, version), do: cancel(session, access, timer)
    end)
  end

  defp cancel(session, _access, %{status: :cancelled}), do: {:ok, session}
  defp cancel(_session, _access, %{status: :elapsed}), do: {:error, :timer_expired}

  defp cancel(session, access, timer) do
    TimerMutation.save(
      session,
      access,
      timer,
      %{
        version: timer.version + 1,
        status: :cancelled,
        deadline_at: nil,
        remaining_seconds: 0,
        completed_at: TimerMutation.completion_time(timer)
      },
      :timer_cancelled
    )
  end
end
