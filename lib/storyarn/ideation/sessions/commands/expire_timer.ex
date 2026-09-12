defmodule Storyarn.Ideation.Sessions.Commands.ExpireTimer do
  @moduledoc false
  import Ecto.Changeset
  import Ecto.Query

  alias Storyarn.Ideation.Ideas
  alias Storyarn.Ideation.Sessions.Adapters.ProjectAccess
  alias Storyarn.Ideation.Sessions.Adapters.TimerActor
  alias Storyarn.Ideation.Sessions.Events.Invalidation
  alias Storyarn.Ideation.Sessions.Events.TimerInvalidation
  alias Storyarn.Ideation.Sessions.Execution.ContributionAccess
  alias Storyarn.Ideation.Sessions.Execution.TimerMutation
  alias Storyarn.Ideation.Sessions.Session
  alias Storyarn.Ideation.Sessions.Timer
  alias Storyarn.Repo

  def run(timer_id, version)
      when is_integer(timer_id) and timer_id > 0 and timer_id <= 9_223_372_036_854_775_807 and is_integer(version) and
             version > 0 and version <= 9_223_372_036_854_775_807 do
    TimerInvalidation.wake()

    with %Timer{} = timer <- Repo.get(Timer, timer_id),
         %Session{} = session <- Repo.get(Session, timer.session_id) do
      result = Repo.transact(fn -> expire_locked(session, timer, version) end)
      notify(result)
    else
      nil -> {:ok, receipt(nil, nil, :not_found)}
    end
  end

  def run(_, _), do: {:error, :invalid_timer_version}

  defp expire_locked(original_session, original_timer, version) do
    case ProjectAccess.lock_background_write(original_session.project_id) do
      :ok -> expire_in_project(original_session, original_timer, version)
      {:error, :not_found} -> {:ok, receipt(nil, nil, :not_found)}
      error -> error
    end
  end

  defp expire_in_project(original_session, original_timer, version) do
    # Authorization locks project/membership first, before the same session lock
    # used by edits, timer controls, archive and publication. An unavailable actor
    # can only record an omitted effect; it cannot enter the publication port.
    authorization =
      with {:ok, scope} <- TimerActor.scope(original_timer.actor_id),
           do: ProjectAccess.write(scope, original_session.project_id)

    session = Repo.one(from s in Session, where: s.id == ^original_session.id, lock: "FOR UPDATE")
    timer = Repo.get(Timer, original_timer.id)

    cond do
      is_nil(session) or is_nil(timer) -> {:ok, receipt(nil, nil, :not_found)}
      timer.version != version or timer.status != :running -> {:ok, receipt(session, timer, :stale)}
      TimerMutation.remaining(timer) > 0 -> {:ok, receipt(session, timer, :not_due)}
      true -> finish(session, timer, authorization, original_timer.actor_id)
    end
  end

  defp finish(session, timer, authorization, original_actor_id) do
    outcome = outcome(session, timer, authorization, original_actor_id)
    original_session = session

    with {:ok, session} <- effects(session, timer, outcome, authorization),
         {:ok, elapsed} <-
           timer
           |> change(
             version: timer.version + 1,
             status: :elapsed,
             deadline_at: nil,
             remaining_seconds: 0,
             completed_at: TimerMutation.completion_time(timer),
             expiry_outcome: outcome
           )
           |> Repo.update(),
         {:ok, session} <- TimerMutation.record(session, elapsed.actor_id, elapsed, :timer_elapsed) do
      {:ok, {receipt(session, elapsed, outcome), Invalidation.comment_change(original_session, session)}}
    end
  end

  defp outcome(%{deleted_at: deleted, status: status}, _, _, _) when not is_nil(deleted) or status != :open,
    do: :skipped_session

  defp outcome(session, timer, {:ok, access}, actor_id) do
    cond do
      timer.actor_id != actor_id or not (access.owner? or session.facilitator_id == access.user_id) ->
        :skipped_authorization

      timer.configuration_version != session.configuration_version ->
        :skipped_configuration

      true ->
        :completed
    end
  end

  defp outcome(_, _, _, _), do: :skipped_authorization

  defp effects(session, timer, :completed, {:ok, access}) do
    with :ok <- reveal(session, timer, access) do
      current = Repo.get!(Session, session.id)

      if timer.close_contributions_on_expiry,
        do: current |> change(contributions_open: false) |> Repo.update(),
        else: {:ok, current}
    end
  end

  defp effects(session, _, _, _), do: {:ok, session}

  defp reveal(session, %{reveal_on_expiry: true}, access) do
    access = ContributionAccess.from_session(session, access)
    with {:ok, _} <- Ideas.set_private_mode_locked(access, session.revision, false), do: :ok
  end

  defp reveal(_, _, _), do: :ok

  defp receipt(session, timer, outcome),
    do: %{
      outcome: outcome,
      timer: timer,
      project_id: if(session, do: session.project_id),
      session_id: if(session, do: session.id)
    }

  defp notify({:ok, {%{outcome: outcome} = result, change}})
       when outcome in [:completed, :skipped_authorization, :skipped_configuration, :skipped_session] do
    response = {:ok, result}

    if !Repo.in_transaction?() do
      Invalidation.notify(response, result.project_id, change)
      TimerInvalidation.notify(response)

      if outcome == :completed and result.timer.reveal_on_expiry,
        do: Ideas.notify_timer_reveal(result.project_id, result.session_id)
    end

    response
  end

  defp notify(response), do: response
end
