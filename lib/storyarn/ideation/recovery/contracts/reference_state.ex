defmodule Storyarn.Ideation.Recovery.ReferenceState do
  @moduledoc false

  @types ~w(sheet flow scene asset localization)
  @relations ~w(origin reference affects result work)
  @overview_fields %{
    "sheet" => ~w(name shortcut description description_truncated color),
    "flow" => ~w(name shortcut description description_truncated is_main scene_id),
    "scene" => ~w(name shortcut description description_truncated width height),
    "asset" => ~w(filename content_type size),
    "localization" =>
      ~w(locale_code source_type source_id source_field source_text translated_text status source_text_truncated translated_text_truncated)
  }

  def valid?(row, "references", index) do
    Map.has_key?(index.sessions, row["session_id"]) and same_session_idea?(row, index) and
      optional_id?(row["created_by_id"]) and target?(row) and version?(row) and
      context?(row["context"], row["target_type"])
  end

  def valid?(row, "reference_revisions", index) do
    reference = index.references[row["reference_id"]]

    is_map(reference) and reference["session_id"] == row["session_id"] and optional_id?(row["actor_id"]) and
      revision_number?(row["number"], reference["version"]) and receipt?(row) and
      context?(row["context"], reference["target_type"])
  end

  def consistent?(rows) do
    revisions = Enum.group_by(rows["reference_revisions"], & &1["reference_id"])

    Enum.all?(rows["references"], fn reference ->
      history = revisions |> Map.get(reference["id"], []) |> Enum.sort_by(& &1["number"])
      latest = List.last(history)

      Enum.map(history, & &1["number"]) == Enum.to_list(1..reference["version"]) and
        hd(history)["operation"] == "create" and
        Enum.all?(Enum.drop(history, 1), &(&1["operation"] in ~w(refresh remove))) and
        Enum.all?(Enum.drop(history, -1), &(&1["operation"] != "remove")) and
        reference["context"] == latest["context"] and
        not is_nil(reference["deleted_at"]) == (latest["operation"] == "remove")
    end)
  end

  def unique?(rows) do
    active = Enum.filter(rows["references"], &is_nil(&1["deleted_at"]))
    available = Enum.reject(active, &is_nil(&1["target_id"]))
    receipts = Enum.reject(rows["reference_revisions"], &is_nil(&1["actor_id"]))
    counts = Enum.frequencies_by(active, &{&1["session_id"], &1["idea_id"]})

    unique_by?(available, &{&1["session_id"], &1["idea_id"], &1["target_type"], &1["target_id"], &1["relation"]}) and
      unique_by?(receipts, &{&1["session_id"], &1["actor_id"], &1["request_key"]}) and
      Enum.all?(counts, fn {_source, count} -> count <= 100 end)
  end

  defp same_session_idea?(%{"idea_id" => nil}, _index), do: true

  defp same_session_idea?(row, index) do
    idea = index.ideas[row["idea_id"]]
    is_map(idea) and idea["session_id"] == row["session_id"]
  end

  defp target?(row) do
    optional_id?(row["target_id"]) and row["target_type"] in @types and
      identity?(row["target_identity"]) and row["relation"] in @relations
  end

  defp version?(row) do
    is_integer(row["version"]) and row["version"] in 1..50 and
      (row["version"] < 50 or not is_nil(row["deleted_at"]))
  end

  defp revision_number?(number, version),
    do: is_integer(number) and number > 0 and is_integer(version) and number <= version

  defp receipt?(row) do
    row["operation"] in ~w(create refresh remove) and bytes?(row["request_key"], 16) and
      bytes?(row["fingerprint"], 32)
  end

  defp context?(context, type) when is_map(context) do
    Enum.sort(Map.keys(context)) == ~w(captured_at fingerprint name overview) and
      text?(context["name"], 240) and digest?(context["fingerprint"]) and timestamp?(context["captured_at"]) and
      overview?(context["overview"], type)
  end

  defp context?(_, _), do: false

  defp overview?(overview, type) when is_map(overview) do
    fields = Map.get(@overview_fields, type, [])

    Enum.sort(Map.keys(overview)) == Enum.sort(["comparison_scope" | fields]) and
      overview["comparison_scope"] == "overview_v1" and Enum.all?(fields, &overview_value?(&1, overview[&1]))
  end

  defp overview?(_, _), do: false

  defp overview_value?(field, value)
       when field in ~w(description_truncated source_text_truncated translated_text_truncated is_main),
       do: is_boolean(value)

  defp overview_value?(field, value) when field in ~w(scene_id source_id), do: optional_id?(value)

  defp overview_value?(field, value) when field in ~w(width height size),
    do: is_nil(value) or (is_integer(value) and value >= 0)

  defp overview_value?(_field, nil), do: true
  defp overview_value?(_field, value), do: text?(value, 2000)

  defp identity?("created:" <> timestamp), do: timestamp?(timestamp)
  defp identity?(_), do: false
  defp timestamp?(value) when is_binary(value), do: match?({:ok, _, _}, DateTime.from_iso8601(value))
  defp timestamp?(_), do: false
  defp digest?(value) when is_binary(value), do: Regex.match?(~r/\A[0-9a-f]{64}\z/, value)
  defp digest?(_), do: false
  defp text?(value, limit), do: is_binary(value) and byte_size(value) <= limit
  defp optional_id?(nil), do: true
  defp optional_id?(value), do: is_integer(value) and value > 0 and value <= 9_223_372_036_854_775_807

  defp bytes?(value, size) when is_binary(value) do
    case Base.decode64(value) do
      {:ok, decoded} -> byte_size(decoded) == size
      _ -> false
    end
  end

  defp bytes?(_, _), do: false
  defp unique_by?(rows, fun), do: length(rows) == length(Enum.uniq_by(rows, fun))
end
