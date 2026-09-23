defmodule Storyarn.Ideation.Recovery.Inventory do
  @moduledoc false
  alias Storyarn.Ideation.Recovery.GraphValidation

  # Closed, versioned persistence contract. Ciphertext is copied as bytes, never
  # loaded through the ordinary encrypted-field schema or returned as plaintext.
  @tables [
    {"sessions", "ideation_sessions", :project_id,
     ~w(id recovery_identity project_id created_by_id facilitator_id decision_owner_id title objective context status archived_at deleted_at revision configuration_version configuration contributions_open inserted_at updated_at)a},
    {"session_revisions", "ideation_session_revisions", :session_id,
     ~w(id recovery_identity session_id actor_id number action snapshot inserted_at)a},
    {"rounds", "ideation_rounds", :session_id,
     ~w(id recovery_identity session_id number prompt status private reveal_on_expiry revealed_at started_at closed_at inserted_at updated_at)a},
    {"timers", "ideation_timers", :session_id,
     ~w(id recovery_identity session_id actor_id version status deadline_at remaining_seconds duration_seconds started_at completed_at close_contributions_on_expiry configuration_version expiry_outcome inserted_at updated_at)a},
    {"ideas", "ideation_ideas", :session_id,
     ~w(id recovery_identity session_id author_id author_kind creation_key revision published_revision state publication_consent configuration_version creation_source_id source_idea_id source_revision canvas round_id late_contribution deleted_at inserted_at updated_at)a},
    {"revisions", "ideation_idea_revisions", :idea_id,
     ~w(id recovery_identity idea_id number actor_id title body state inserted_at)a},
    {"edits", "ideation_idea_edits", :idea_id,
     ~w(id recovery_identity idea_id actor_id request_key fingerprint outcome base_revision result_revision title body state inserted_at)a},
    {"reveals", "ideation_reveal_operations", :session_id,
     ~w(id recovery_identity session_id actor_id request_key selection manifest status completed_at inserted_at updated_at)a},
    {"publications", "ideation_idea_publications", :idea_id,
     ~w(id recovery_identity idea_id revision operation_id actor_id inserted_at)a},
    {"groups", "ideation_groups", :session_id,
     ~w(id recovery_identity session_id author_id round_id title synthesis version canvas deleted_at inserted_at updated_at)a},
    {"group_memberships", "ideation_group_memberships", :group_id,
     ~w(id recovery_identity session_id group_id idea_id source_revision actor_id removed_at inserted_at)a},
    {"group_revisions", "ideation_group_revisions", :group_id,
     ~w(id recovery_identity session_id group_id actor_id number operation request_key fingerprint title synthesis canvas idea_ids sources deleted_at inserted_at)a},
    {"references", "ideation_references", :session_id,
     ~w(id recovery_identity session_id idea_id created_by_id target_type target_id target_identity relation version context deleted_at inserted_at updated_at)a},
    {"reference_revisions", "ideation_reference_revisions", :reference_id,
     ~w(id recovery_identity session_id reference_id actor_id number operation request_key fingerprint context inserted_at)a},
    {"decisions", "ideation_decisions", :session_id,
     ~w(id recovery_identity session_id author_id version status accepted_version inserted_at updated_at)a},
    {"decision_revisions", "ideation_decision_revisions", :decision_id,
     ~w(id recovery_identity session_id decision_id number operation actor_id responsible_id verb title conclusion reason sources source_context targets target_context next_action next_action_owner_id round_id replaces_id superseded_by_id request_key fingerprint inserted_at)a},
    {"decision_applications", "ideation_decision_applications", :decision_id,
     ~w(id recovery_identity session_id decision_id agreement target_key state note actor_id request_key fingerprint inserted_at)a}
  ]
  @group_collections ~w(groups group_memberships group_revisions)
  @reference_collections ~w(references reference_revisions)
  @decision_collections ~w(decisions decision_revisions decision_applications)
  @actor_fields ~w(created_by_id facilitator_id decision_owner_id author_id actor_id responsible_id next_action_owner_id)a
  @dates ~w(archived_at deleted_at removed_at inserted_at updated_at completed_at started_at closed_at deadline_at revealed_at)a
  @max_rows 100_000

  def tables, do: @tables
  def actor_fields, do: @actor_fields
  def max_rows, do: @max_rows
  def max_bytes, do: 48 * 1024 * 1024

  def encode(data), do: data |> canonical_value() |> Jason.encode!()

  defp canonical_value(value) when is_map(value) do
    value
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(fn {key, child} -> {key, canonical_value(child)} end)
    |> Jason.OrderedObject.new()
  end

  defp canonical_value(value) when is_list(value), do: Enum.map(value, &canonical_value/1)
  defp canonical_value(value), do: value

  def encode_row(collection, row) do
    Map.new(row, fn {key, value} ->
      encoded =
        cond do
          is_nil(value) ->
            nil

          key in @dates ->
            NaiveDateTime.to_iso8601(value)

          binary_field?(collection, key) ->
            Base.encode64(value)

          collection == "ideas" and key == :canvas ->
            value |> Map.drop(["links_receipt", "creation_links_receipt"]) |> Map.put_new("links", [])

          true ->
            value
        end

      {Atom.to_string(key), encoded}
    end)
  end

  def decode_row(collection, row) do
    {_, _, _, fields} = Enum.find(@tables, &(elem(&1, 0) == collection))

    Map.new(fields, fn key ->
      value =
        case key do
          :canvas -> Map.get(row, "canvas", %{})
          :deleted_at when collection == "ideas" -> Map.get(row, "deleted_at")
          _ -> Map.fetch!(row, Atom.to_string(key))
        end

      decoded =
        cond do
          is_nil(value) -> nil
          key in @dates -> NaiveDateTime.from_iso8601!(value)
          binary_field?(collection, key) -> Base.decode64!(value)
          true -> value
        end

      {key, decoded}
    end)
  end

  def validate(%{"format" => "storyarn.ideation", "version" => version, "rows" => rows, "actors" => actors} = data)
      when version in [1, 2, 3, 4, 5, 6, 7, 8, 9] and is_map(rows) and is_map(actors) do
    tables = tables_for(version)
    expected = Enum.map(tables, &elem(&1, 0))

    if Enum.sort(Map.keys(rows)) == Enum.sort(expected) and
         Enum.all?(tables, &valid_rows?(&1, rows)) and
         Enum.sum(Enum.map(rows, fn {_, entries} -> length(entries) end)) <= @max_rows and
         Enum.all?(actors, fn {id, identity} ->
           match?({_, ""}, Integer.parse(id)) and match?({:ok, _}, Ecto.UUID.cast(identity))
         end) and GraphValidation.valid?(normalize(data)["rows"]) do
      :ok
    else
      {:error, :invalid_ideation_recovery}
    end
  end

  def validate(_), do: {:error, :invalid_ideation_recovery}

  # Call only after validation. Normalize older inventories before remapping and
  # equality checks, keeping backups made before rounds and timers usable.
  def normalize(%{"version" => 1, "rows" => rows} = data) do
    ideas =
      Enum.map(rows["ideas"], fn row ->
        row |> Map.put("round_id", nil) |> Map.put("late_contribution", false)
      end)

    normalize(%{data | "version" => 2, "rows" => rows |> Map.put("rounds", []) |> Map.put("ideas", ideas)})
  end

  def normalize(%{"version" => 2, "rows" => rows} = data) do
    sessions = Enum.map(rows["sessions"], &Map.put(&1, "contributions_open", true))
    normalize(%{data | "version" => 3, "rows" => rows |> Map.put("sessions", sessions) |> Map.put("timers", [])})
  end

  def normalize(%{"version" => 3, "rows" => rows} = data),
    do: normalize(%{data | "version" => 4, "rows" => Enum.reduce(@group_collections, rows, &Map.put(&2, &1, []))})

  def normalize(%{"version" => 4, "rows" => rows} = data),
    do: normalize(%{data | "version" => 5, "rows" => Enum.reduce(@reference_collections, rows, &Map.put(&2, &1, []))})

  def normalize(%{"version" => 5, "rows" => rows} = data),
    do: normalize(%{data | "version" => 6, "rows" => Enum.reduce(@decision_collections, rows, &Map.put(&2, &1, []))})

  # Rounds became canvas bands: prepared and cancelled rounds never held a note
  # and disappear; every remaining round gets a header offset. Older captures
  # keep absolute note positions, so their headers all start at 0.
  def normalize(%{"version" => 6, "rows" => rows} = data) do
    rounds = Enum.filter(rows["rounds"], &(&1["status"] in ["active", "closed"]))
    {rounds, ideas} = with_first_rounds(rows["sessions"], rounds, rows["ideas"])

    normalize(%{data | "version" => 7, "rows" => rows |> Map.put("rounds", rounds) |> Map.put("ideas", ideas)})
  end

  # Private mode moved from the session to the round in progress, and groups
  # learned their round. A session that was private keeps hiding every round it has.
  def normalize(%{"version" => 7, "rows" => rows} = data) do
    private_sessions =
      for %{"id" => id, "configuration" => %{"private_mode" => true}} <- rows["sessions"], into: MapSet.new(), do: id

    # A clock that promised to reveal at 0:00 hands that promise to the round in progress.
    revealing_sessions =
      for %{"session_id" => id, "reveal_on_expiry" => true, "status" => status} <- Map.get(rows, "timers", []),
          status in ["running", "paused"],
          into: MapSet.new(),
          do: id

    rounds =
      Enum.map(rows["rounds"], fn round ->
        active? = round["status"] == "active"

        Map.merge(round, %{
          "private" => MapSet.member?(private_sessions, round["session_id"]),
          "reveal_on_expiry" => active? and MapSet.member?(revealing_sessions, round["session_id"]),
          "revealed_at" => nil
        })
      end)

    sessions =
      Enum.map(rows["sessions"], fn session ->
        Map.update(session, "configuration", %{}, &Map.delete(&1 || %{}, "private_mode"))
      end)

    groups = attach_legacy_groups(rows, rounds)

    # The clock no longer decides the reveal, so its flag leaves the rows and the audit snapshots.
    rows =
      rows
      |> Map.put("rounds", rounds)
      |> Map.put("sessions", sessions)
      |> Map.put("groups", groups)
      |> Map.update("timers", [], fn timers -> Enum.map(timers, &Map.delete(&1, "reveal_on_expiry")) end)
      |> Map.update("session_revisions", [], fn revisions -> Enum.map(revisions, &strip_timer_reveal/1) end)

    normalize(%{data | "version" => 8, "rows" => rows})
  end

  # Decisions became objects with a verb, affected content and application.
  # Earlier decisions have no expression in that model and are not carried over.
  def normalize(%{"version" => 8, "rows" => rows} = data),
    do: %{data | "version" => 9, "rows" => Enum.reduce(@decision_collections, rows, &Map.put(&2, &1, []))}

  def normalize(data), do: data

  # Separating a synthesis removes its memberships, not the privacy of the work
  # it came from. Prefer current sources, then the last retained source, with the
  # session's first round as a stable home when no source round is recoverable.
  defp attach_legacy_groups(rows, rounds) do
    idea_rounds = Map.new(rows["ideas"], &{&1["id"], &1["round_id"]})
    memberships = Enum.group_by(rows["group_memberships"], & &1["group_id"])

    first_rounds =
      rounds
      |> Enum.group_by(& &1["session_id"])
      |> Map.new(fn {session_id, entries} -> {session_id, Enum.min_by(entries, & &1["number"])["id"]} end)

    Enum.map(rows["groups"], fn group ->
      round_id =
        legacy_group_round(Map.get(memberships, group["id"], []), idea_rounds) || first_rounds[group["session_id"]]

      Map.put(group, "round_id", round_id)
    end)
  end

  defp legacy_group_round(memberships, idea_rounds) do
    current =
      memberships
      |> Enum.reject(& &1["removed_at"])
      |> Enum.map(&idea_rounds[&1["idea_id"]])
      |> Enum.reject(&is_nil/1)
      |> Enum.min(fn -> nil end)

    historical =
      memberships
      |> Enum.sort_by(& &1["id"], :desc)
      |> Enum.find_value(&idea_rounds[&1["idea_id"]])

    current || historical
  end

  # Every session has a round: one that had none is born its Round 1, in
  # progress unless the session is archived. Notes without a round join the
  # earliest round of their session, as the bands migration did.
  defp with_first_rounds(sessions, rounds, ideas) do
    with_rounds = MapSet.new(rounds, & &1["session_id"])
    next_id = Enum.reduce(rounds, 0, &max(&1["id"], &2)) + 1

    {born, _} =
      sessions
      |> Enum.reject(&MapSet.member?(with_rounds, &1["id"]))
      |> Enum.map_reduce(next_id, fn session, id -> {first_round(session, id), id + 1} end)

    rounds = rounds ++ born

    earliest =
      rounds
      |> Enum.group_by(& &1["session_id"])
      |> Map.new(fn {session_id, list} -> {session_id, Enum.min_by(list, & &1["number"])["id"]} end)

    ideas =
      Enum.map(ideas, fn idea ->
        case {idea["round_id"], earliest[idea["session_id"]]} do
          {nil, round_id} when is_integer(round_id) ->
            Map.merge(idea, %{"round_id" => round_id, "late_contribution" => false})

          _ ->
            idea
        end
      end)

    {rounds, ideas}
  end

  defp first_round(session, id) do
    open? = session["status"] == "open"

    %{
      "id" => id,
      "recovery_identity" => derived_identity(session["recovery_identity"], "round-1"),
      "session_id" => session["id"],
      "number" => 1,
      "prompt" => nil,
      "status" => if(open?, do: "active", else: "closed"),
      "started_at" => session["inserted_at"],
      "closed_at" => if(open?, do: nil, else: session["inserted_at"]),
      "inserted_at" => session["inserted_at"],
      "updated_at" => session["inserted_at"]
    }
  end

  # Opening the same capsule again must find the same born round; identities
  # travel base64-encoded like every other row's.
  defp derived_identity(identity, suffix), do: Base.encode64(:crypto.hash(:md5, "#{identity}:#{suffix}"))

  defp strip_timer_reveal(%{"snapshot" => %{"timer" => %{} = timer} = snapshot} = row),
    do: %{row | "snapshot" => %{snapshot | "timer" => Map.delete(timer, "reveal_on_expiry")}}

  defp strip_timer_reveal(row), do: row

  defp tables_for(9), do: @tables

  defp tables_for(8) do
    for {collection, table, parent, fields} <- tables_for(9), collection != "decision_applications" do
      fields =
        if collection == "decision_revisions",
          do:
            fields --
              ~w(verb targets target_context next_action next_action_owner_id round_id replaces_id superseded_by_id)a,
          else: fields

      {collection, table, parent, fields}
    end
  end

  defp tables_for(7) do
    for {collection, table, parent, fields} <- tables_for(8) do
      fields =
        case collection do
          "rounds" -> fields -- [:private, :reveal_on_expiry, :revealed_at]
          "groups" -> fields -- [:round_id]
          "timers" -> fields ++ [:reveal_on_expiry]
          _ -> fields
        end

      {collection, table, parent, fields}
    end
  end

  defp tables_for(6), do: tables_for(7)

  defp tables_for(5), do: Enum.reject(tables_for(6), &(elem(&1, 0) in ~w(decisions decision_revisions)))
  defp tables_for(4), do: Enum.reject(tables_for(5), &(elem(&1, 0) in @reference_collections))
  defp tables_for(3), do: Enum.reject(tables_for(4), &(elem(&1, 0) in @group_collections))

  defp tables_for(2) do
    for {collection, table, parent, fields} <- tables_for(3), collection != "timers" do
      fields = if collection == "sessions", do: fields -- [:contributions_open], else: fields
      {collection, table, parent, fields}
    end
  end

  defp tables_for(1) do
    for {collection, table, parent, fields} <- tables_for(2), collection != "rounds" do
      fields = if collection == "ideas", do: fields -- [:round_id, :late_contribution], else: fields
      {collection, table, parent, fields}
    end
  end

  defp valid_rows?({collection, _, _, fields}, rows) do
    entries = rows[collection]
    keys = Enum.sort(Enum.map(fields, &Atom.to_string/1))

    is_list(entries) and length(entries) <= @max_rows and
      Enum.all?(
        entries,
        &(is_map(&1) and
            (Enum.sort(Map.keys(&1)) == keys or
               (collection == "ideas" and
                  Enum.sort(Map.keys(Map.drop(&1, ["canvas", "deleted_at"]))) == keys -- ["canvas", "deleted_at"])) and
            is_integer(&1["id"]) and valid_dates?(&1, fields))
      ) and
      length(Enum.uniq_by(entries, & &1["id"])) == length(entries)
  end

  defp valid_dates?(row, fields) do
    fields
    |> Enum.filter(&(&1 in @dates))
    |> Enum.all?(fn field ->
      case Map.get(row, Atom.to_string(field)) do
        nil ->
          field in [
            :archived_at,
            :deleted_at,
            :removed_at,
            :completed_at,
            :started_at,
            :closed_at,
            :deadline_at,
            :revealed_at
          ]

        value when is_binary(value) ->
          valid_timestamp?(value)

        _ ->
          false
      end
    end)
  end

  defp valid_timestamp?(value) do
    case NaiveDateTime.from_iso8601(value) do
      # ISO accepts earlier years than PostgreSQL's timestamp storage supports.
      # Its upper bound exceeds the ISO parser's maximum year of 9999.
      {:ok, date} -> NaiveDateTime.compare(date, ~N[-4713-11-24 00:00:00]) != :lt
      _ -> false
    end
  end

  defp binary_field?(collection, key) do
    key in [:recovery_identity, :creation_key, :request_key, :fingerprint] or
      (collection in ["revisions", "edits"] and key in [:title, :body]) or
      (collection in ["groups", "group_revisions"] and key in [:title, :synthesis]) or
      (collection == "decision_revisions" and
         key in [:title, :conclusion, :reason, :source_context, :target_context, :next_action]) or
      (collection == "decision_applications" and key in [:target_key, :note])
  end
end
