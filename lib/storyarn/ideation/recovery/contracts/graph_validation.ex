defmodule Storyarn.Ideation.Recovery.GraphValidation do
  @moduledoc false

  # Authentication proves who produced the capsule, not referential integrity.
  # Validate links before issuing writes; never turn a bad archive into a DB error.
  def valid?(rows) do
    sessions = Map.new(rows["sessions"], &{&1["id"], &1})
    ideas = Map.new(rows["ideas"], &{&1["id"], &1})
    reveals = Map.new(rows["reveals"], &{&1["id"], &1})
    revisions = MapSet.new(rows["revisions"], &{&1["idea_id"], &1["number"]})
    index = %{sessions: sessions, ideas: ideas, reveals: reveals, revisions: revisions}

    Enum.all?(rows, fn {collection, entries} ->
      Enum.all?(entries, &valid_row?(&1, collection, index)) and unique_identities?(entries, collection, index)
    end) and unique_numbers?(rows["revisions"], "idea_id") and
      unique_numbers?(rows["session_revisions"], "session_id")
  end

  defp valid_row?(row, collection, index) do
    is_integer(row["id"]) and row["id"] > 0 and uuid?(row["recovery_identity"]) and
      valid_links?(row, collection, index)
  end

  defp valid_links?(row, "sessions", _) do
    is_integer(row["project_id"]) and is_map(row["configuration"]) and
      row["status"] in ~w(open archived) and is_binary(row["title"])
  end

  defp valid_links?(row, "session_revisions", index),
    do: Map.has_key?(index.sessions, row["session_id"]) and positive?(row["number"]) and is_map(row["snapshot"])

  defp valid_links?(row, "ideas", index) do
    Map.has_key?(index.sessions, row["session_id"]) and revision?(index, row["id"], row["revision"]) and
      (is_nil(row["published_revision"]) or revision?(index, row["id"], row["published_revision"])) and
      source_valid?(row, index)
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

  defp source_valid?(%{"source_idea_id" => nil}, _), do: true

  defp source_valid?(row, index) do
    source = index.ideas[row["source_idea_id"]]

    is_map(source) and source["session_id"] == row["session_id"] and
      revision?(index, source["id"], row["source_revision"])
  end

  defp valid_selection?(%{"selection" => %{"mode" => "eligible"}}, _), do: true
  defp valid_selection?(%{"selection" => %{"mode" => "creation"}}, _), do: true

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
  defp session_id(row, collection, _) when collection in ["session_revisions", "ideas", "reveals"], do: row["session_id"]
  defp session_id(row, _, index), do: get_in(index.ideas, [row["idea_id"], "session_id"])

  defp unique_numbers?(rows, parent) do
    keys = Enum.map(rows, &{&1[parent], &1["number"]})
    length(keys) == MapSet.size(MapSet.new(keys))
  end
end
