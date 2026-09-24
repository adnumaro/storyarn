defmodule Storyarn.Ideation.Sessions.Commands.StartTimer do
  @moduledoc false
  alias Storyarn.Ideation.Sessions.Execution.TimerMutation
  alias Storyarn.Ideation.Sessions.Timer
  alias Storyarn.Platform.Kernel.MapAccess

  # A clock starts on the round in progress and stays with it.
  def run(scope, project_id, session_id, revision, attrs) when is_map(attrs) do
    TimerMutation.run(scope, project_id, session_id, revision, fn session, access, round, timer ->
      with {:ok, round} <- in_progress(round),
           :ok <- available(timer),
           {:ok, options} <- options(attrs) do
        now = TimerMutation.now()
        timer = timer || %Timer{session_id: session.id, round_id: round.id, version: 0}

        values =
          Map.merge(options, %{
            version: timer.version + 1,
            actor_id: access.user_id,
            configuration_version: session.configuration_version,
            status: :running,
            remaining_seconds: options.duration_seconds,
            deadline_at: DateTime.shift(now, second: options.duration_seconds),
            started_at: now,
            completed_at: nil,
            expiry_outcome: nil
          })

        TimerMutation.save(session, access, timer, values, :timer_started)
      end
    end)
  end

  def run(_, _, _, _, _), do: {:error, :invalid_timer_options}
  defp in_progress(nil), do: {:error, :round_not_active}
  defp in_progress(round), do: {:ok, round}
  defp available(%{status: status}) when status in [:running, :paused], do: {:error, :timer_already_running}
  defp available(_), do: :ok

  defp options(attrs) do
    duration = MapAccess.get_flexible(attrs, :seconds)
    close = option(attrs, :close_contributions_on_expiry)

    cond do
      not (is_integer(duration) and duration in 1..86_400) -> {:error, :invalid_timer_duration}
      not is_boolean(close) -> {:error, :invalid_timer_options}
      true -> {:ok, %{duration_seconds: duration, close_contributions_on_expiry: close}}
    end
  end

  defp option(attrs, field) do
    if Map.has_key?(attrs, field) or Map.has_key?(attrs, Atom.to_string(field)),
      do: MapAccess.get_flexible(attrs, field),
      else: false
  end
end
