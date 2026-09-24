defmodule Storyarn.Ideation.Sessions.Execution.RoundMutation do
  @moduledoc false
  import Ecto.Changeset
  import Ecto.Query

  alias Storyarn.Ideation.Sessions.Execution.Mutation
  alias Storyarn.Ideation.Sessions.Execution.TimerMutation
  alias Storyarn.Ideation.Sessions.Round
  alias Storyarn.Ideation.Sessions.Timer
  alias Storyarn.Repo

  def run(scope, project_id, session_id, revision, callback) do
    Mutation.run(scope, project_id, session_id, revision, fn
      %{status: :archived}, _access -> {:error, :session_archived}
      session, access -> callback.(session, access)
    end)
  end

  def get(session_id, round_id) when is_integer(round_id) and round_id > 0 and round_id <= 9_223_372_036_854_775_807 do
    case Repo.one(from r in Round, where: r.session_id == ^session_id and r.id == ^round_id) do
      nil -> {:error, :round_not_found}
      round -> {:ok, round}
    end
  end

  def get(_session_id, _round_id), do: {:error, :invalid_round}

  # A round ends with its clock: a running or paused countdown is cancelled and
  # recorded first, so the audit reads the stop before the close.
  def close(session, access, round, now) do
    with {:ok, session} <- stop_clock(session, access, round),
         {:ok, closed} <- round |> Round.lifecycle_changeset(status: :closed, closed_at: now) |> Repo.update() do
      {:ok, session, closed}
    end
  end

  defp stop_clock(session, access, round) do
    case Repo.get_by(Timer, round_id: round.id) do
      %{status: status} = timer when status in [:running, :paused] ->
        TimerMutation.save(session, access, timer, TimerMutation.cancel_attrs(timer), :timer_cancelled)

      _ ->
        {:ok, session}
    end
  end

  def record(session, access, round, action) do
    with {:ok, updated} <- session |> change(revision: session.revision + 1) |> Repo.update() do
      Mutation.record(updated, access.user_id, action, %{
        "round" => %{
          "number" => round.number,
          "prompt" => round.prompt,
          "status" => Atom.to_string(round.status),
          "started_at" => timestamp(round.started_at),
          "closed_at" => timestamp(round.closed_at),
          "private" => round.private,
          "reveal_on_expiry" => round.reveal_on_expiry,
          "revealed_at" => timestamp(round.revealed_at)
        }
      })
    end
  end

  defp timestamp(nil), do: nil
  defp timestamp(value), do: DateTime.to_iso8601(value)
end
