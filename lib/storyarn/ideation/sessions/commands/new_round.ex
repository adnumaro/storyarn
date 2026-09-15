defmodule Storyarn.Ideation.Sessions.Commands.NewRound do
  @moduledoc false
  import Ecto.Changeset, only: [unique_constraint: 3]
  import Ecto.Query

  alias Storyarn.Ideation.Sessions.Execution.RoundMutation
  alias Storyarn.Ideation.Sessions.Round
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Repo

  # One step: the active round closes and the next one starts as the band below
  # it. Bands are as tall as their content, so nothing about layout is stored.
  def run(scope, project_id, session_id, revision, attrs) when is_map(attrs) do
    RoundMutation.run(scope, project_id, session_id, revision, fn session, access ->
      now = %{TimeHelpers.now() | microsecond: {0, 6}}
      rounds = Repo.all(from r in Round, where: r.session_id == ^session.id, order_by: [asc: r.number])

      with :ok <- close_active(rounds, now),
           {:ok, round} <- insert(session, List.last(rounds), attrs, now) do
        RoundMutation.record(session, access, round, :round_started)
      end
    end)
  end

  def run(_scope, _project_id, _session_id, _revision, _attrs), do: {:error, :invalid_round}

  defp close_active(rounds, now) do
    case Enum.find(rounds, &(&1.status == :active)) do
      nil ->
        :ok

      active ->
        with {:ok, _closed} <-
               active |> Round.lifecycle_changeset(status: :closed, closed_at: now) |> Repo.update(),
             do: :ok
    end
  end

  defp insert(session, last, attrs, now) do
    %Round{
      session_id: session.id,
      number: if(last, do: last.number + 1, else: 1),
      status: :active,
      started_at: now
    }
    |> Round.changeset(attrs)
    |> unique_constraint(:status, name: :ideation_rounds_one_active_per_session)
    |> Repo.insert()
  end
end
