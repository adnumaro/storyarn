defmodule Storyarn.Ideation.Sessions.Commands.MoveDecisionLane do
  @moduledoc false
  import Ecto.Changeset
  import Ecto.Query

  alias Storyarn.Ideation.Sessions.Events.Invalidation
  alias Storyarn.Ideation.Sessions.Execution.ContributionAccess
  alias Storyarn.Ideation.Sessions.Execution.RoundPrivacy
  alias Storyarn.Ideation.Sessions.Round
  alias Storyarn.Platform.Kernel.MapAccess
  alias Storyarn.Repo

  @limit 1_000_000

  # Moving a round's decision lane is a placement on the board, like moving a
  # group: whoever can contribute to the open session may do it, the session
  # revision is untouched, and the lane's own version fences concurrent moves.
  # A place never rises above the round header (y >= 0); moving to no place at
  # all (x and y nil) returns the lane to its automatic place under the band's
  # content. A retried move that already landed answers with the lane as it is.
  def run(scope, project_id, session_id, round_id, attrs) when is_map(attrs) do
    with :ok <- outermost(),
         {:ok, move} <- input(attrs) do
      fn -> locked(scope, project_id, session_id, round_id, move) end
      |> Repo.transact()
      |> announce(project_id, session_id)
    end
  end

  def run(_scope, _project_id, _session_id, _round_id, _attrs), do: {:error, :invalid_decision_lane}

  # Readers hear about the move only once it is committed.
  defp outermost, do: if(Repo.in_transaction?(), do: {:error, :decision_lane_requires_outer_transaction}, else: :ok)

  defp locked(scope, project_id, session_id, round_id, move) do
    with {:ok, access} <- ContributionAccess.lock(scope, project_id, session_id),
         {:ok, round} <- round(access.session_id, round_id),
         :ok <- visible(round) do
      place(round, move)
    end
  end

  defp round(session_id, round_id)
       when is_integer(round_id) and round_id > 0 and round_id <= 9_223_372_036_854_775_807 do
    case Repo.one(from r in Round, where: r.session_id == ^session_id and r.id == ^round_id) do
      nil -> {:error, :round_not_found}
      round -> {:ok, round}
    end
  end

  defp round(_session_id, _round_id), do: {:error, :invalid_round}

  # A private round stays hidden, so nobody arranges it until the reveal.
  defp visible(round), do: if(RoundPrivacy.private?(round.id), do: {:error, :private_round}, else: :ok)

  defp place(round, %{x: x, y: y, version: expected}) do
    lane = round.decision_lane
    current = Map.get(lane, "version", 0)

    cond do
      current == expected ->
        moved = placed(x, y, expected + 1)
        round |> change(decision_lane: moved) |> Repo.update!()
        {:ok, {view(round.id, moved), true}}

      current == expected + 1 and lane["x"] == x and lane["y"] == y ->
        {:ok, {view(round.id, lane), false}}

      true ->
        {:error, :stale_decision_lane}
    end
  end

  defp placed(nil, nil, version), do: %{"version" => version}
  defp placed(x, y, version), do: %{"x" => x, "y" => y, "version" => version}

  defp view(round_id, lane), do: %{round_id: round_id, x: lane["x"], y: lane["y"], version: lane["version"]}

  defp announce({:ok, {lane, changed?}}, project_id, session_id) do
    if changed?, do: Invalidation.broadcast_board(project_id, session_id)
    {:ok, lane}
  end

  defp announce({:error, _} = error, _project_id, _session_id), do: error

  defp input(attrs) do
    x = MapAccess.get_flexible(attrs, :x)
    y = MapAccess.get_flexible(attrs, :y)
    version = MapAccess.get_flexible(attrs, :version)

    if place?(x, y) and is_integer(version) and version >= 0 and version < 2_147_483_647,
      do: {:ok, %{x: x, y: y, version: version}},
      else: {:error, :invalid_decision_lane}
  end

  defp place?(nil, nil), do: true
  defp place?(x, y), do: coordinate?(x) and coordinate?(y) and y >= 0

  defp coordinate?(value), do: is_number(value) and abs(value) <= @limit
end
