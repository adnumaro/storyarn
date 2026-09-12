defmodule Storyarn.Ideation.Recovery.DecisionState do
  @moduledoc false

  alias Storyarn.Platform.Vault

  @max_decisions 100
  @max_revisions 100
  @max_sources 20
  @content_fields ~w(title conclusion reason source_context)

  def valid?(row, "decisions", index) do
    Map.has_key?(index.sessions, row["session_id"]) and optional_id?(row["author_id"]) and
      integer_in?(row["version"], 1, @max_revisions) and row["status"] in ~w(proposed accepted) and
      (is_nil(row["accepted_version"]) or integer_in?(row["accepted_version"], 1, row["version"])) and
      MapSet.member?(index.decision_revisions, {row["id"], row["version"]})
  end

  def valid?(row, "decision_revisions", index) do
    decision = index.decisions[row["decision_id"]]

    is_map(decision) and decision["session_id"] == row["session_id"] and
      integer_in?(row["number"], 1, decision["version"]) and
      row["operation"] in ~w(propose revise accept) and optional_id?(row["responsible_id"]) and receipt?(row) and
      Enum.all?(@content_fields, &is_binary(row[&1])) and sources?(row, index)
  end

  defp receipt?(row) do
    optional_id?(row["actor_id"]) and bytes?(row["request_key"], 16) and bytes?(row["fingerprint"], 32)
  end

  def unique?(rows) do
    revisions = rows["decision_revisions"]
    receipts = Enum.reject(revisions, &is_nil(&1["actor_id"]))

    unique_by?(revisions, &{&1["decision_id"], &1["number"]}) and
      unique_by?(receipts, &{&1["session_id"], &1["actor_id"], &1["request_key"]}) and
      rows["decisions"]
      |> Enum.frequencies_by(& &1["session_id"])
      |> Enum.all?(fn {_, count} -> count <= @max_decisions end)
  end

  def consistent?(rows) do
    revisions = Enum.group_by(rows["decision_revisions"], & &1["decision_id"])

    Enum.all?(rows["decisions"], fn decision ->
      history = revisions |> Map.get(decision["id"], []) |> Enum.sort_by(& &1["number"])
      first = List.first(history)
      last = List.last(history)
      accepted = history |> Enum.filter(&(&1["operation"] == "accept")) |> List.last()

      Enum.map(history, & &1["number"]) == Enum.to_list(1..decision["version"]) and
        first["operation"] == "propose" and first["actor_id"] == decision["author_id"] and
        decision["accepted_version"] == if(accepted, do: accepted["number"]) and
        decision["status"] == if(last["operation"] == "accept", do: "accepted", else: "proposed") and
        transitions?(history)
    end)
  end

  # A frozen source is a published revision, never an author's current private
  # head. Check its plaintext against that retained revision after authentication.
  def content_valid?(rows) do
    ideas = Map.new(rows["revisions"], &{{&1["idea_id"], &1["number"]}, &1})
    groups = Map.new(Map.get(rows, "group_revisions", []), &{{&1["group_id"], &1["number"]}, &1})
    revisions = Map.get(rows, "decision_revisions", [])

    with {:ok, content} <- decrypt_revisions(revisions),
         true <- Enum.all?(revisions, &source_context?(&1, content[&1["id"]], ideas, groups)) do
      revisions
      |> Enum.group_by(& &1["decision_id"])
      |> Enum.all?(fn {_, history} -> acceptance_content?(history, content) end)
    else
      _ -> false
    end
  end

  defp sources?(%{"sources" => %{"items" => items} = sources} = row, index) when is_list(items) do
    map_size(sources) == 1 and length(items) in 1..@max_sources and
      Enum.all?(items, &source?(&1, row["session_id"], index)) and
      unique_by?(items, &{&1["type"], &1["id"]}) and unique_by?(items, & &1["identity"])
  end

  defp sources?(_, _), do: false

  defp source?(source, session_id, index) when is_map(source) do
    with true <- Enum.sort(Map.keys(source)) == ~w(author_id id identity type version),
         true <- source["type"] in ~w(idea group),
         true <- valid_id?(source["id"]) and valid_id?(source["version"]) and optional_id?(source["author_id"]),
         rows = if(source["type"] == "idea", do: index.ideas, else: index.groups),
         %{} = origin <- rows[source["id"]],
         true <- origin["session_id"] == session_id,
         {:ok, identity} <- Ecto.UUID.dump(source["identity"]),
         true <- Base.encode64(identity) == origin["recovery_identity"],
         true <- is_nil(origin["author_id"]) or origin["author_id"] == source["author_id"] do
      if source["type"] == "idea",
        do: MapSet.member?(index.publications, {source["id"], source["version"]}),
        else: MapSet.member?(index.group_revisions, {source["id"], source["version"]})
    else
      _ -> false
    end
  end

  defp source?(_, _, _), do: false

  defp transitions?(history) do
    history
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.all?(fn [previous, current] ->
      current["operation"] == "revise" or
        (current["operation"] == "accept" and previous["operation"] != "accept" and
           current["sources"] == previous["sources"] and current["responsible_id"] == previous["responsible_id"] and
           current["actor_id"] == current["responsible_id"])
    end)
  end

  defp decrypt_revisions(revisions) do
    Enum.reduce_while(revisions, {:ok, %{}}, fn row, {:ok, contents} ->
      with {:ok, title} <- plaintext(row["title"]),
           {:ok, conclusion} <- plaintext(row["conclusion"]),
           {:ok, reason} <- plaintext(row["reason"]),
           {:ok, source_json} <- plaintext(row["source_context"]),
           true <- text?(title, 160) and text?(conclusion, 4000) and text?(reason, 4000),
           true <- byte_size(source_json) <= 256_000,
           {:ok, sources} when is_map(sources) <- Jason.decode(source_json) do
        content = %{title: title, conclusion: conclusion, reason: reason, sources: sources}
        {:cont, {:ok, Map.put(contents, row["id"], content)}}
      else
        _ -> {:halt, :error}
      end
    end)
  end

  defp source_context?(row, content, ideas, groups) do
    items = row["sources"]["items"]

    Enum.sort(Map.keys(content.sources)) == Enum.sort(Enum.map(items, & &1["identity"])) and
      Enum.all?(items, fn item ->
        source =
          if item["type"] == "idea",
            do: ideas[{item["id"], item["version"]}],
            else: groups[{item["id"], item["version"]}]

        body_field = if item["type"] == "idea", do: "body", else: "synthesis"

        with %{} <- source,
             {:ok, title} <- plaintext(source["title"]),
             {:ok, body} <- plaintext(source[body_field]) do
          content.sources[item["identity"]] == %{"title" => title, "body" => body}
        else
          _ -> false
        end
      end)
  end

  defp acceptance_content?(history, contents) do
    history
    |> Enum.sort_by(& &1["number"])
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.all?(fn [previous, current] ->
      current["operation"] != "accept" or contents[previous["id"]] == contents[current["id"]]
    end)
  end

  defp plaintext(nil), do: {:ok, nil}

  defp plaintext(encoded) when is_binary(encoded) do
    with {:ok, bytes} <- Base.decode64(encoded),
         {:ok, text} when is_binary(text) <- Vault.decrypt(bytes),
         true <- String.valid?(text),
         do: {:ok, text}
  end

  defp plaintext(_), do: :error
  defp text?(value, max), do: is_binary(value) and String.trim(value) != "" and String.length(value) <= max
  defp optional_id?(nil), do: true
  defp optional_id?(id), do: valid_id?(id)
  defp valid_id?(id), do: integer_in?(id, 1, 9_223_372_036_854_775_807)
  defp integer_in?(number, min, max), do: is_integer(number) and number >= min and number <= max
  defp unique_by?(rows, fun), do: length(rows) == length(Enum.uniq_by(rows, fun))

  defp bytes?(value, size) when is_binary(value) do
    case Base.decode64(value) do
      {:ok, decoded} -> byte_size(decoded) == size
      _ -> false
    end
  end

  defp bytes?(_, _), do: false
end
