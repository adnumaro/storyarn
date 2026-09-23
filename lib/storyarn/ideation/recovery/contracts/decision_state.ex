defmodule Storyarn.Ideation.Recovery.DecisionState do
  @moduledoc false

  alias Storyarn.Platform.Vault

  @max_decisions 100
  @max_revisions 100
  @max_sources 20
  @max_targets 5
  @max_applications 500
  @operations ~w(propose revise accept register withdraw supersede)
  @verbs ~w(create change test keep discard)
  @target_types ~w(sheet flow scene)
  @states ~w(not_applied partially_applied applied no_change_needed)
  @required_content ~w(title conclusion source_context target_context)
  @optional_content ~w(reason next_action)
  # Records that copy the content they close rather than author new content.
  @copies ~w(accept register withdraw)

  def valid?(row, "decisions", index) do
    Map.has_key?(index.sessions, row["session_id"]) and optional_id?(row["author_id"]) and
      integer_in?(row["version"], 1, @max_revisions) and
      row["status"] in ~w(proposed accepted withdrawn superseded) and
      (is_nil(row["accepted_version"]) or integer_in?(row["accepted_version"], 1, row["version"])) and
      MapSet.member?(index.decision_revisions, {row["id"], row["version"]})
  end

  def valid?(row, "decision_revisions", index) do
    decision = index.decisions[row["decision_id"]]

    is_map(decision) and decision["session_id"] == row["session_id"] and
      integer_in?(row["number"], 1, decision["version"]) and revision_fields?(row) and
      sources?(row, index) and targets?(row["targets"]) and round?(row, index) and links?(row, index)
  end

  def valid?(row, "decision_applications", index) do
    decision = index.decisions[row["decision_id"]]

    is_map(decision) and decision["session_id"] == row["session_id"] and
      MapSet.member?(index.decision_revisions, {row["decision_id"], row["agreement"]}) and
      row["state"] in @states and (is_nil(row["target_key"]) or bytes?(row["target_key"], 16)) and
      (is_nil(row["note"]) or is_binary(row["note"])) and receipt?(row)
  end

  defp revision_fields?(row) do
    row["operation"] in @operations and row["verb"] in @verbs and optional_id?(row["responsible_id"]) and
      optional_id?(row["next_action_owner_id"]) and receipt?(row) and
      Enum.all?(@required_content, &is_binary(row[&1])) and
      Enum.all?(@optional_content, &(is_nil(row[&1]) or is_binary(row[&1])))
  end

  defp receipt?(row) do
    optional_id?(row["actor_id"]) and bytes?(row["request_key"], 16) and bytes?(row["fingerprint"], 32)
  end

  def unique?(rows) do
    revisions = rows["decision_revisions"]
    applications = Map.get(rows, "decision_applications", [])

    unique_by?(revisions, &{&1["decision_id"], &1["number"]}) and
      unique_by?(
        Enum.reject(revisions, &is_nil(&1["actor_id"])),
        &{&1["session_id"], &1["actor_id"], &1["request_key"]}
      ) and
      unique_by?(
        Enum.reject(applications, &is_nil(&1["actor_id"])),
        &{&1["session_id"], &1["actor_id"], &1["request_key"]}
      ) and
      rows["decisions"] |> Enum.frequencies_by(& &1["session_id"]) |> Enum.all?(fn {_, n} -> n <= @max_decisions end) and
      applications |> Enum.frequencies_by(& &1["decision_id"]) |> Enum.all?(fn {_, n} -> n <= @max_applications end)
  end

  def consistent?(rows) do
    revisions = Enum.group_by(rows["decision_revisions"], & &1["decision_id"])
    decisions = Map.new(rows["decisions"], &{&1["id"], &1})

    Enum.all?(rows["decisions"], fn decision ->
      history = revisions |> Map.get(decision["id"], []) |> Enum.sort_by(& &1["number"])
      first = List.first(history)
      agreements = Enum.filter(history, &(&1["operation"] in ~w(accept register)))

      Enum.map(history, & &1["number"]) == Enum.to_list(1..decision["version"]) and
        first["operation"] == "propose" and first["actor_id"] == decision["author_id"] and
        decision["accepted_version"] == if(agreements != [], do: List.last(agreements)["number"]) and
        decision["status"] == status(history) and transitions?(history) and
        supersession?(List.last(history), decision, revisions, decisions)
    end) and applications?(rows, revisions)
  end

  # A capsule can only claim a replacement that the replacing decision accepted.
  defp supersession?(%{"operation" => "supersede", "superseded_by_id" => by}, decision, revisions, decisions) do
    replacing = decisions[by]

    is_map(replacing) and replacing["session_id"] == decision["session_id"] and
      revisions
      |> Map.get(by, [])
      |> Enum.any?(&(&1["operation"] in ~w(accept register) and &1["replaces_id"] == decision["id"]))
  end

  defp supersession?(_last, _decision, _revisions, _decisions), do: true

  defp applications?(rows, revisions) do
    by_number =
      for {_, history} <- revisions, revision <- history, into: %{} do
        {{revision["decision_id"], revision["number"]}, revision}
      end

    rows
    |> Map.get("decision_applications", [])
    |> Enum.all?(&declared_on_agreement?(&1, by_number[{&1["decision_id"], &1["agreement"]}]))
  end

  defp declared_on_agreement?(application, %{"operation" => operation, "targets" => %{"items" => items}})
       when operation in ~w(accept register) do
    keys = Enum.map(items, &encoded_key/1)
    if keys == [], do: is_nil(application["target_key"]), else: application["target_key"] in keys
  end

  defp declared_on_agreement?(_application, _agreement), do: false

  # A capsule stores target keys as they travel inside the targets JSON; the
  # application row carries the same UUID as bytes.
  defp encoded_key(target) do
    case Ecto.UUID.dump(target["key"]) do
      {:ok, bytes} -> Base.encode64(bytes)
      _ -> nil
    end
  end

  defp status(history) do
    agreed? = Enum.any?(history, &(&1["operation"] in ~w(accept register)))

    case List.last(history)["operation"] do
      operation when operation in ~w(propose revise) -> "proposed"
      operation when operation in ~w(accept register) -> "accepted"
      "withdraw" -> if agreed?, do: "accepted", else: "withdrawn"
      "supersede" -> "superseded"
    end
  end

  # Replays the lifecycle: every record must be allowed from the state the
  # previous records left, and closing records copy what they close.
  defp transitions?(history), do: Enum.reduce_while(history, {:none, nil, nil}, &step/2) != :error

  defp step(revision, {state, previous, agreement}) do
    case transition(state, revision, previous, agreement) do
      {:ok, next} ->
        agreement = if revision["operation"] in ~w(accept register), do: revision, else: agreement
        {:cont, {next, revision, agreement}}

      :error ->
        {:halt, :error}
    end
  end

  defp transition(:none, %{"operation" => "propose"}, nil, nil), do: {:ok, :proposed}

  defp transition(state, %{"operation" => "revise"}, _previous, _agreement) when state in [:proposed, :accepted],
    do: {:ok, :proposed}

  defp transition(:proposed, %{"operation" => "accept"} = current, previous, _agreement) do
    if same_record?(current, previous) and current["actor_id"] == current["responsible_id"],
      do: {:ok, :accepted},
      else: :error
  end

  defp transition(:proposed, %{"operation" => "register"} = current, previous, _agreement) do
    if same_record?(current, previous) and previous["operation"] in ~w(propose revise) and
         current["actor_id"] == current["responsible_id"] and current["actor_id"] == previous["actor_id"],
       do: {:ok, :accepted},
       else: :error
  end

  defp transition(:proposed, %{"operation" => "withdraw"} = current, previous, agreement) do
    cond do
      not same_record?(current, previous) -> :error
      agreement -> {:ok, :accepted}
      true -> {:ok, :withdrawn}
    end
  end

  defp transition(state, %{"operation" => "supersede"} = current, _previous, agreement)
       when state in [:proposed, :accepted] and not is_nil(agreement) do
    if same_record?(current, agreement), do: {:ok, :superseded}, else: :error
  end

  defp transition(_state, _current, _previous, _agreement), do: :error

  defp same_record?(current, previous) do
    Enum.all?(
      ~w(verb responsible_id sources targets next_action_owner_id round_id replaces_id),
      &(current[&1] == previous[&1])
    )
  end

  # Ciphertext differs even for equal text, so a closing record is compared
  # with what it closes after decryption.
  def content_valid?(rows) do
    ideas = Map.new(rows["revisions"], &{{&1["idea_id"], &1["number"]}, &1})
    groups = Map.new(Map.get(rows, "group_revisions", []), &{{&1["group_id"], &1["number"]}, &1})
    revisions = Map.get(rows, "decision_revisions", [])

    with {:ok, content} <- decrypt_revisions(revisions),
         true <- Enum.all?(revisions, &source_context?(&1, content[&1["id"]], ideas, groups)),
         true <- Enum.all?(revisions, &target_context?(&1, content[&1["id"]])),
         true <- notes_valid?(Map.get(rows, "decision_applications", [])) do
      revisions
      |> Enum.group_by(& &1["decision_id"])
      |> Enum.all?(fn {_, history} -> copies?(history, content) end)
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

  defp targets?(%{"items" => items} = targets) when is_list(items) and map_size(targets) == 1 do
    length(items) <= @max_targets and Enum.all?(items, &target?/1) and unique_by?(items, & &1["key"]) and
      unique_by?(Enum.reject(items, &is_nil(&1["id"])), &{&1["type"], &1["id"]})
  end

  defp targets?(_), do: false

  defp target?(%{"key" => key, "type" => type, "id" => id, "identity" => identity} = target)
       when map_size(target) == 4 do
    match?({:ok, _}, Ecto.UUID.cast(key)) and type in @target_types and optional_id?(id) and
      (is_nil(identity) or (is_binary(identity) and byte_size(identity) <= 120)) and
      (is_nil(id) or not is_nil(identity))
  end

  defp target?(_), do: false

  defp round?(%{"round_id" => nil}, _index), do: true

  defp round?(row, index) do
    round = index.rounds[row["round_id"]]
    is_map(round) and round["session_id"] == row["session_id"]
  end

  defp links?(row, index) do
    same_session?(row["replaces_id"], row, index) and same_session?(row["superseded_by_id"], row, index) and
      row["replaces_id"] != row["decision_id"] and
      row["operation"] == "supersede" == not is_nil(row["superseded_by_id"])
  end

  defp same_session?(nil, _row, _index), do: true

  defp same_session?(id, row, index) do
    decision = index.decisions[id]
    is_map(decision) and decision["session_id"] == row["session_id"]
  end

  defp decrypt_revisions(revisions) do
    Enum.reduce_while(revisions, {:ok, %{}}, fn row, {:ok, contents} ->
      with {:ok, title} <- plaintext(row["title"]),
           {:ok, conclusion} <- plaintext(row["conclusion"]),
           {:ok, reason} <- plaintext(row["reason"]),
           {:ok, next_action} <- plaintext(row["next_action"]),
           {:ok, source_json} <- plaintext(row["source_context"]),
           {:ok, target_json} <- plaintext(row["target_context"]),
           true <- text?(title, 160) and text?(conclusion, 4000),
           true <- optional_text?(reason, 4000) and optional_text?(next_action, 500),
           true <- byte_size(source_json) <= 256_000 and byte_size(target_json) <= 64_000,
           {:ok, sources} when is_map(sources) <- Jason.decode(source_json),
           {:ok, targets} when is_map(targets) <- Jason.decode(target_json) do
        content = %{
          title: title,
          conclusion: conclusion,
          reason: reason,
          next_action: next_action,
          sources: sources,
          targets: targets
        }

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

  defp target_context?(row, content) do
    keys = Enum.map(row["targets"]["items"], & &1["key"])

    Enum.sort(Map.keys(content.targets)) == Enum.sort(keys) and
      Enum.all?(content.targets, fn {_, label} ->
        match?(%{"label" => text} when is_binary(text), label) and map_size(label) == 1 and
          text?(label["label"], 240)
      end)
  end

  defp notes_valid?(applications) do
    Enum.all?(applications, fn application ->
      case plaintext(application["note"]) do
        {:ok, note} -> optional_text?(note, 1000)
        _ -> false
      end
    end)
  end

  defp copies?(history, contents) do
    history = Enum.sort_by(history, & &1["number"])
    agreements = Enum.filter(history, &(&1["operation"] in ~w(accept register)))

    history
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.all?(fn [previous, current] ->
      cond do
        current["operation"] in @copies ->
          contents[previous["id"]] == contents[current["id"]]

        current["operation"] == "supersede" ->
          agreement = agreements |> Enum.filter(&(&1["number"] < current["number"])) |> List.last()
          agreement != nil and contents[agreement["id"]] == contents[current["id"]]

        true ->
          true
      end
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
  defp optional_text?(nil, _max), do: true
  defp optional_text?(value, max), do: text?(value, max)
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
