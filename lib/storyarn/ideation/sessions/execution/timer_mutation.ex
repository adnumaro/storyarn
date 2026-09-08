defmodule Storyarn.Ideation.Sessions.Execution.TimerMutation do
  @moduledoc false
  import Ecto.Changeset

  alias Storyarn.Ideation.Sessions.Events.TimerInvalidation
  alias Storyarn.Ideation.Sessions.Execution.Mutation
  alias Storyarn.Ideation.Sessions.Execution.TimerDelivery
  alias Storyarn.Ideation.Sessions.Timer
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Repo

  def run(scope, project_id, session_id, revision, callback) do
    scope
    |> Mutation.run(project_id, session_id, revision, fn
      %{status: :archived}, _ -> {:error, :session_archived}
      session, access -> callback.(session, access, Repo.get_by(Timer, session_id: session.id))
    end)
    |> TimerInvalidation.notify()
  end

  def current(nil, _), do: {:error, :timer_not_found}
  def current(%{version: version} = timer, version), do: {:ok, timer}
  def current(_, version) when is_integer(version) and version > 0, do: {:error, :stale_timer}
  def current(_, _), do: {:error, :invalid_timer_version}

  def active(%{status: :running} = timer) do
    case remaining(timer) do
      0 -> {:error, :timer_expired}
      seconds -> {:ok, seconds}
    end
  end

  def active(_), do: {:error, :timer_not_running}

  def remaining(%{status: :running, deadline_at: deadline}), do: max(DateTime.diff(deadline, now(), :second), 0)
  def remaining(timer), do: timer.remaining_seconds
  def now, do: %{TimeHelpers.now() | microsecond: {0, 6}}

  def reveal_allowed(%{configuration: %{private_mode: false}}, true), do: {:error, :timer_reveal_requires_private}
  def reveal_allowed(_, _), do: :ok

  def save(session, access, timer, attrs, action) do
    with {:ok, saved} <- timer |> change(attrs) |> Repo.insert_or_update(),
         :ok <- schedule(saved) do
      record(session, access.user_id, saved, action)
    end
  end

  defp schedule(%{status: :running} = timer), do: TimerDelivery.schedule(timer)
  defp schedule(_timer), do: :ok

  def record(session, actor_id, timer, action) do
    with {:ok, updated} <- session |> change(revision: session.revision + 1) |> Repo.update() do
      Mutation.record(updated, actor_id, action, %{
        "timer" => snapshot(timer)
      })
    end
  end

  def snapshot(timer),
    do: %{
      "version" => timer.version,
      "status" => Atom.to_string(timer.status),
      "duration_seconds" => timer.duration_seconds,
      "remaining_seconds" => timer.remaining_seconds,
      "reveal_on_expiry" => timer.reveal_on_expiry,
      "close_contributions_on_expiry" => timer.close_contributions_on_expiry,
      "expiry_outcome" => if(timer.expiry_outcome, do: Atom.to_string(timer.expiry_outcome))
    }
end
