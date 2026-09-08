defmodule Storyarn.Ideation.Sessions.Commands.ResumeTimer do
  @moduledoc false
  alias Storyarn.Ideation.Sessions.Execution.TimerMutation

  def run(scope, project_id, session_id, revision, version) do
    TimerMutation.run(scope, project_id, session_id, revision, fn session, access, timer ->
      with {:ok, timer} <- TimerMutation.current(timer, version),
           :ok <- paused(timer),
           :ok <- TimerMutation.reveal_allowed(session, timer.reveal_on_expiry) do
        TimerMutation.save(
          session,
          access,
          timer,
          %{
            version: timer.version + 1,
            actor_id: access.user_id,
            configuration_version: session.configuration_version,
            status: :running,
            deadline_at: DateTime.add(TimerMutation.now(), timer.remaining_seconds, :second)
          },
          :timer_resumed
        )
      end
    end)
  end

  defp paused(%{status: :paused}), do: :ok
  defp paused(_), do: {:error, :timer_not_paused}
end
