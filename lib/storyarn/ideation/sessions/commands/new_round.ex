defmodule Storyarn.Ideation.Sessions.Commands.NewRound do
  @moduledoc false
  import Ecto.Changeset, only: [unique_constraint: 3]
  import Ecto.Query

  alias Storyarn.Ideation.Sessions.Execution.RoundMutation
  alias Storyarn.Ideation.Sessions.Round
  alias Storyarn.Platform.Kernel.MapAccess
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Repo

  @max_offset 1_000_000
  # Canvas units. The caller measures the previous band and proposes where the
  # new header goes; the server only guarantees bands stay ordered and apart.
  @min_band 120
  @empty_band 320

  # One step: the active round closes, the next one starts, and its header is
  # placed below the previous band. The first round of a session starts at 0.
  def run(scope, project_id, session_id, revision, attrs) when is_map(attrs) do
    RoundMutation.run(scope, project_id, session_id, revision, fn session, access ->
      now = %{TimeHelpers.now() | microsecond: {0, 6}}
      rounds = Repo.all(from r in Round, where: r.session_id == ^session.id, order_by: [asc: r.number])
      last = List.last(rounds)

      with {:ok, offset} <- header_offset(MapAccess.get_flexible(attrs, :canvas_offset_y), last),
           :ok <- close_active(rounds, now),
           {:ok, round} <- insert(session, last, attrs, offset, now) do
        RoundMutation.record(session, access, round, :round_started)
      end
    end)
  end

  def run(_scope, _project_id, _session_id, _revision, _attrs), do: {:error, :invalid_round}

  defp header_offset(nil, nil), do: {:ok, 0}
  defp header_offset(nil, last), do: {:ok, last.canvas_offset_y + @empty_band}

  defp header_offset(value, last) when is_integer(value) and value <= @max_offset do
    minimum = if last, do: last.canvas_offset_y + @min_band, else: 0
    if value >= minimum, do: {:ok, value}, else: {:error, :invalid_round_offset}
  end

  defp header_offset(_value, _last), do: {:error, :invalid_round_offset}

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

  defp insert(session, last, attrs, offset, now) do
    %Round{
      session_id: session.id,
      number: if(last, do: last.number + 1, else: 1),
      status: :active,
      started_at: now,
      canvas_offset_y: offset
    }
    |> Round.changeset(attrs)
    |> unique_constraint(:status, name: :ideation_rounds_one_active_per_session)
    |> Repo.insert()
  end
end
