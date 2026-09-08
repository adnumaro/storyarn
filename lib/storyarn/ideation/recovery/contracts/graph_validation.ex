defmodule Storyarn.Ideation.Recovery.GraphValidation do
  @moduledoc false
  alias Storyarn.Ideation.Recovery.TimerState

  # Authentication proves who produced the capsule, not referential integrity.
  # Validate links before issuing writes; never turn a bad archive into a DB error.
  def valid?(rows) do
    sessions = Map.new(rows["sessions"], &{&1["id"], &1})
    rounds = Map.new(rows["rounds"], &{&1["id"], &1})
    ideas = Map.new(rows["ideas"], &{&1["id"], &1})
    reveals = Map.new(rows["reveals"], &{&1["id"], &1})
    revisions = MapSet.new(rows["revisions"], &{&1["idea_id"], &1["number"]})
    index = %{sessions: sessions, rounds: rounds, ideas: ideas, reveals: reveals, revisions: revisions}

    Enum.all?(rows, fn {collection, entries} ->
      Enum.all?(entries, &valid_row?(&1, collection, index)) and unique_identities?(entries, collection, index)
    end) and unique_numbers?(rows["revisions"], "idea_id") and
      unique_numbers?(rows["session_revisions"], "session_id") and
      unique_numbers?(rows["rounds"], "session_id") and one_active_round?(rows["rounds"]) and
      length(rows["timers"]) == length(Enum.uniq_by(rows["timers"], & &1["session_id"]))
  end

  defp valid_row?(row, collection, index) do
    is_integer(row["id"]) and row["id"] > 0 and uuid?(row["recovery_identity"]) and
      valid_links?(row, collection, index)
  end

  defp valid_links?(row, "sessions", _) do
    is_integer(row["project_id"]) and is_map(row["configuration"]) and
      row["status"] in ~w(open archived) and is_binary(row["title"]) and is_boolean(row["contributions_open"])
  end

  defp valid_links?(row, "session_revisions", index) do
    Map.has_key?(index.sessions, row["session_id"]) and positive?(row["number"]) and
      is_map(row["snapshot"]) and round_snapshot?(row, index) and timer_snapshot?(row)
  end

  defp valid_links?(row, "rounds", index), do: Map.has_key?(index.sessions, row["session_id"]) and round_metadata?(row)

  defp valid_links?(row, "timers", index), do: Map.has_key?(index.sessions, row["session_id"]) and TimerState.valid?(row)

  defp valid_links?(row, "ideas", index) do
    Map.has_key?(index.sessions, row["session_id"]) and revision?(index, row["id"], row["revision"]) and
      (is_nil(row["published_revision"]) or revision?(index, row["id"], row["published_revision"])) and
      source_valid?(row, index) and canvas_valid?(row, index) and round_valid?(row, index)
  end

  defp valid_links?(row, "revisions", index), do: Map.has_key?(index.ideas, row["idea_id"]) and positive?(row["number"])

  defp valid_links?(row, "edits", index),
    do: Map.has_key?(index.ideas, row["idea_id"]) and revision?(index, row["idea_id"], row["result_revision"])

  defp valid_links?(row, "reveals", index) do
    Map.has_key?(index.sessions, row["session_id"]) and is_map(row["selection"]) and
      valid_targets?(row["manifest"], row["session_id"], index) and valid_selection?(row, index)
  end

  defp valid_links?(row, "publications", index) do
    idea = index.ideas[row["idea_id"]]
    operation = index.reveals[row["operation_id"]]

    is_map(idea) and is_map(operation) and idea["session_id"] == operation["session_id"] and
      revision?(index, row["idea_id"], row["revision"])
  end

  defp canvas_valid?(row, index) do
    canvas = Map.get(row, "canvas", %{})

    is_map(canvas) and
      (map_size(canvas) == 0 or valid_placement?(canvas)) and
      is_list(Map.get(canvas, "links", [])) and length(Map.get(canvas, "links", [])) <= 100 and
      Enum.all?(Map.get(canvas, "links", []), fn id ->
        target = index.ideas[id]
        is_map(target) and id != row["id"] and target["session_id"] == row["session_id"]
      end)
  end

  defp valid_placement?(canvas) do
    # Connections may precede the first explicit positioning of legacy notes.
    Enum.all?(["x", "y"], &optional_range?(canvas[&1], -1_000_000, 1_000_000)) and
      optional_range?(canvas["width"], 180, 800) and
      (is_nil(canvas["color"]) or canvas["color"] in ~w(yellow coral mint blue violet paper)) and
      valid_canvas_version?(canvas["version"])
  end

  defp optional_range?(nil, _, _), do: true
  defp optional_range?(value, minimum, maximum), do: is_number(value) and value >= minimum and value <= maximum
  defp valid_canvas_version?(nil), do: true
  defp valid_canvas_version?(value), do: is_integer(value) and value >= 0

  defp source_valid?(%{"source_idea_id" => nil}, _), do: true

  defp source_valid?(row, index) do
    source = index.ideas[row["source_idea_id"]]

    is_map(source) and source["session_id"] == row["session_id"] and
      revision?(index, source["id"], row["source_revision"])
  end

  defp round_valid?(%{"round_id" => nil, "late_contribution" => false}, _), do: true

  defp round_valid?(row, index) do
    round = index.rounds[row["round_id"]]

    is_map(round) and round["session_id"] == row["session_id"] and
      round["status"] in ~w(active closed) and is_boolean(row["late_contribution"]) and
      (not row["late_contribution"] or round["status"] == "closed")
  end

  defp round_metadata?(row) do
    positive?(row["number"]) and
      (is_nil(row["prompt"]) or (is_binary(row["prompt"]) and length(String.to_charlist(row["prompt"])) <= 2000)) and
      round_timing?(row)
  end

  defp round_timing?(%{"status" => status, "started_at" => nil, "closed_at" => nil})
       when status in ["planned", "cancelled"], do: true

  defp round_timing?(%{"status" => "active", "started_at" => started, "closed_at" => nil}), do: valid_time?(started)

  defp round_timing?(%{"status" => "closed", "started_at" => started, "closed_at" => closed}) do
    with {:ok, start_time} <- parse_time(started),
         {:ok, close_time} <- parse_time(closed) do
      NaiveDateTime.compare(close_time, start_time) != :lt
    else
      _ -> false
    end
  end

  defp round_timing?(_), do: false
  defp valid_time?(value), do: match?({:ok, _}, parse_time(value))
  defp parse_time(value) when is_binary(value), do: NaiveDateTime.from_iso8601(value)
  defp parse_time(_), do: :error

  defp one_active_round?(rounds) do
    sessions = for %{"status" => "active", "session_id" => id} <- rounds, do: id
    length(sessions) == MapSet.size(MapSet.new(sessions))
  end

  defp round_snapshot?(%{"action" => action, "snapshot" => snapshot} = row, index)
       when action in ~w(round_created round_updated round_cancelled round_started round_closed) do
    round = snapshot["round"]

    is_map(round) and round_metadata?(round) and
      Enum.any?(index.rounds, fn {_, current} ->
        current["session_id"] == row["session_id"] and current["number"] == round["number"]
      end)
  end

  defp round_snapshot?(_, _), do: true

  defp timer_snapshot?(%{"action" => action, "snapshot" => snapshot})
       when action in ~w(timer_started timer_paused timer_resumed timer_extended timer_cancelled timer_elapsed),
       do: TimerState.snapshot_valid?(snapshot["timer"])

  defp timer_snapshot?(_), do: true

  defp valid_selection?(%{"selection" => %{"mode" => "eligible", "states" => states}}, _) do
    is_list(states) and length(states) in 1..3 and Enum.all?(states, &(&1 in ~w(active parked discarded)))
  end

  defp valid_selection?(%{"selection" => %{"mode" => "eligible"}}, _), do: true
  defp valid_selection?(%{"selection" => %{"mode" => mode}}, _) when mode in ["creation", "session"], do: true

  defp valid_selection?(%{"selection" => %{"mode" => "selected", "targets" => targets}} = row, index),
    do: valid_targets?(targets, row["session_id"], index)

  defp valid_selection?(_, _), do: false

  defp valid_targets?(targets, session_id, index) when is_list(targets) do
    Enum.all?(targets, fn
      %{"idea_id" => id, "revision" => revision} ->
        idea = index.ideas[id]
        is_map(idea) and idea["session_id"] == session_id and revision?(index, id, revision)

      _ ->
        false
    end)
  end

  defp valid_targets?(_, _, _), do: false
  defp revision?(index, idea_id, number), do: MapSet.member?(index.revisions, {idea_id, number})
  defp positive?(value), do: is_integer(value) and value > 0

  defp uuid?(value) when is_binary(value) do
    case Base.decode64(value) do
      {:ok, bytes} -> byte_size(bytes) == 16
      _ -> false
    end
  end

  defp uuid?(_), do: false

  defp unique_identities?(entries, collection, index) do
    keys = Enum.map(entries, fn row -> {session_id(row, collection, index), row["recovery_identity"]} end)
    length(keys) == MapSet.size(MapSet.new(keys))
  end

  defp session_id(row, "sessions", _), do: row["id"]

  defp session_id(row, collection, _) when collection in ["session_revisions", "rounds", "timers", "ideas", "reveals"],
    do: row["session_id"]

  defp session_id(row, _, index), do: get_in(index.ideas, [row["idea_id"], "session_id"])

  defp unique_numbers?(rows, parent) do
    keys = Enum.map(rows, &{&1[parent], &1["number"]})
    length(keys) == MapSet.size(MapSet.new(keys))
  end
end
