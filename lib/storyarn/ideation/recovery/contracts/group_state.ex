defmodule Storyarn.Ideation.Recovery.GroupState do
  @moduledoc false

  # A capsule may retain published notes that were later deleted, but a group
  # must never turn an unpublished draft into shared synthesis or provenance.
  def valid?(row, "groups", index) do
    Map.has_key?(index.sessions, row["session_id"]) and optional_id?(row["author_id"]) and
      positive_integer?(row["version"]) and
      MapSet.member?(index.group_revisions, {row["id"], row["version"]}) and
      content?(row) and canvas?(row["canvas"])
  end

  def valid?(row, "group_memberships", index) do
    group = index.groups[row["group_id"]]

    is_map(group) and group["session_id"] == row["session_id"] and optional_id?(row["actor_id"]) and
      published_source?(row["idea_id"], row["source_revision"], row["session_id"], index)
  end

  def valid?(row, "group_revisions", index) do
    group = index.groups[row["group_id"]]

    is_map(group) and group["session_id"] == row["session_id"] and optional_id?(row["actor_id"]) and
      positive_integer?(row["number"]) and row["number"] <= group["version"] and
      receipt?(row) and content?(row) and canvas?(row["canvas"]) and sources?(row, index)
  end

  def unique?(rows) do
    active = Enum.filter(rows["group_memberships"], &is_nil(&1["removed_at"]))
    receipts = Enum.reject(rows["group_revisions"], &is_nil(&1["actor_id"]))

    unique_by?(active, & &1["idea_id"]) and
      unique_by?(receipts, &{&1["session_id"], &1["actor_id"], &1["request_key"]})
  end

  # Ordinary writers stop at 500 live groups per session and the board reader
  # refuses more, so a capsule beyond that would restore an unreadable board.
  @max_live_groups 500

  def within_limits?(rows) do
    rows["groups"]
    |> Enum.filter(&is_nil(&1["deleted_at"]))
    |> Enum.frequencies_by(& &1["session_id"])
    |> Enum.all?(fn {_session_id, count} -> count <= @max_live_groups end)
  end

  def consistent?(rows) do
    revisions = Map.new(rows["group_revisions"], &{{&1["group_id"], &1["number"]}, &1})
    memberships = Enum.group_by(rows["group_memberships"], & &1["group_id"])

    Enum.all?(rows["groups"], fn group ->
      latest = revisions[{group["id"], group["version"]}]

      active_sources =
        memberships
        |> Map.get(group["id"], [])
        |> Enum.filter(&is_nil(&1["removed_at"]))
        |> Map.new(&{to_string(&1["idea_id"]), &1["source_revision"]})

      deleted? = not is_nil(group["deleted_at"])

      group["canvas"] == latest["canvas"] and group["deleted_at"] == latest["deleted_at"] and
        deleted? == (latest["operation"] == "delete") and
        active_sources == if(deleted?, do: %{}, else: latest["sources"])
    end)
  end

  defp sources?(row, index) do
    ids = row["idea_ids"]
    sources = row["sources"]

    is_list(ids) and length(ids) <= 200 and Enum.all?(ids, &valid_id?/1) and length(ids) == MapSet.size(MapSet.new(ids)) and
      is_map(sources) and Enum.sort(Map.keys(sources)) == Enum.sort(Enum.map(ids, &to_string/1)) and
      Enum.all?(ids, fn id ->
        revision = sources[to_string(id)]

        published_source?(id, revision, row["session_id"], index) and
          MapSet.member?(index.memberships, {row["group_id"], id, revision})
      end)
  end

  defp published_source?(idea_id, revision, session_id, index) do
    idea = index.ideas[idea_id]

    is_map(idea) and idea["session_id"] == session_id and positive_integer?(revision) and
      MapSet.member?(index.publications, {idea_id, revision})
  end

  defp receipt?(row) do
    row["operation"] in ~w(create update move delete restore) and
      bytes?(row["request_key"], 16) and bytes?(row["fingerprint"], 32)
  end

  defp content?(row), do: Enum.all?(~w(title synthesis), &(is_nil(row[&1]) or is_binary(row[&1])))

  defp canvas?(canvas) when is_map(canvas) do
    Enum.sort(Map.keys(canvas)) == ~w(height width x y) and
      Enum.all?(~w(x y), &range?(canvas[&1], -1_000_000, 1_000_000)) and
      range?(canvas["width"], 200, 100_000) and range?(canvas["height"], 120, 100_000)
  end

  defp canvas?(_), do: false
  defp range?(value, minimum, maximum), do: is_number(value) and value >= minimum and value <= maximum
  defp optional_id?(nil), do: true
  defp optional_id?(value), do: valid_id?(value)
  defp valid_id?(value), do: is_integer(value) and value > 0 and value <= 9_223_372_036_854_775_807
  defp positive_integer?(value), do: is_integer(value) and value > 0 and value <= 2_147_483_647

  defp bytes?(value, size) when is_binary(value) do
    case Base.decode64(value) do
      {:ok, decoded} -> byte_size(decoded) == size
      _ -> false
    end
  end

  defp bytes?(_, _), do: false
  defp unique_by?(rows, fun), do: length(rows) == length(Enum.uniq_by(rows, fun))
end
