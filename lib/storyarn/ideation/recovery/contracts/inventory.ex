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
     ~w(id recovery_identity session_id number prompt status started_at closed_at inserted_at updated_at)a},
    {"timers", "ideation_timers", :session_id,
     ~w(id recovery_identity session_id actor_id version status deadline_at remaining_seconds duration_seconds started_at completed_at reveal_on_expiry close_contributions_on_expiry configuration_version expiry_outcome inserted_at updated_at)a},
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
     ~w(id recovery_identity session_id author_id title synthesis version canvas deleted_at inserted_at updated_at)a},
    {"group_memberships", "ideation_group_memberships", :group_id,
     ~w(id recovery_identity session_id group_id idea_id source_revision actor_id removed_at inserted_at)a},
    {"group_revisions", "ideation_group_revisions", :group_id,
     ~w(id recovery_identity session_id group_id actor_id number operation request_key fingerprint title synthesis canvas idea_ids sources deleted_at inserted_at)a}
  ]
  @group_collections ~w(groups group_memberships group_revisions)
  @actor_fields ~w(created_by_id facilitator_id decision_owner_id author_id actor_id)a
  @dates ~w(archived_at deleted_at removed_at inserted_at updated_at completed_at started_at closed_at deadline_at)a
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
      when version in [1, 2, 3, 4] and is_map(rows) and is_map(actors) do
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
    do: %{data | "version" => 4, "rows" => Enum.reduce(@group_collections, rows, &Map.put(&2, &1, []))}

  def normalize(data), do: data

  defp tables_for(4), do: @tables
  defp tables_for(3), do: Enum.reject(@tables, &(elem(&1, 0) in @group_collections))

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
        nil -> field in [:archived_at, :deleted_at, :removed_at, :completed_at, :started_at, :closed_at, :deadline_at]
        value when is_binary(value) -> valid_timestamp?(value)
        _ -> false
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
      (collection in ["groups", "group_revisions"] and key in [:title, :synthesis])
  end
end
