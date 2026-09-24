defmodule Storyarn.Ideation.Sessions.Execution.TimerMutation do
  @moduledoc false
  import Ecto.Changeset
  import Ecto.Query

  alias Storyarn.Ideation.Sessions.Events.TimerInvalidation
  alias Storyarn.Ideation.Sessions.Execution.Mutation
  alias Storyarn.Ideation.Sessions.Execution.TimerDelivery
  alias Storyarn.Ideation.Sessions.Round
  alias Storyarn.Ideation.Sessions.Timer
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Repo

  # The clock belongs to the round in progress: every control reads that round
  # and its timer under the session lock. A closed round keeps its clock as history.
  def run(scope, project_id, session_id, revision, callback) do
    scope
    |> Mutation.run(project_id, session_id, revision, fn
      %{status: :archived}, _ ->
        {:error, :session_archived}

      session, access ->
        round = Repo.one(from r in Round, where: r.session_id == ^session.id and r.status == :active)
        callback.(session, access, round, timer_of(round))
    end)
    |> TimerInvalidation.notify()
  end

  def timer_of(nil), do: nil
  def timer_of(%Round{id: round_id}), do: Repo.get_by(Timer, round_id: round_id)

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

  def remaining(%{status: :running, deadline_at: deadline, duration_seconds: duration}) do
    deadline |> DateTime.diff(now(), :second) |> max(0) |> min(duration)
  end

  def remaining(timer), do: timer.remaining_seconds
  def now, do: %{TimeHelpers.now() | microsecond: {0, 6}}

  def completion_time(timer) do
    current = now()
    if DateTime.before?(current, timer.started_at), do: timer.started_at, else: current
  end

  # A stopped clock keeps its duration and the moment it stopped; nothing runs after it.
  def cancel_attrs(timer),
    do: %{
      version: timer.version + 1,
      status: :cancelled,
      deadline_at: nil,
      remaining_seconds: 0,
      completed_at: completion_time(timer)
    }

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

  # Audit names the round by number, like round snapshots: identities change on restore.
  def snapshot(timer),
    do: %{
      "round" => Repo.one!(from r in Round, where: r.id == ^timer.round_id, select: r.number),
      "version" => timer.version,
      "status" => Atom.to_string(timer.status),
      "duration_seconds" => timer.duration_seconds,
      "remaining_seconds" => timer.remaining_seconds,
      "close_contributions_on_expiry" => timer.close_contributions_on_expiry,
      "expiry_outcome" => if(timer.expiry_outcome, do: Atom.to_string(timer.expiry_outcome))
    }
end
