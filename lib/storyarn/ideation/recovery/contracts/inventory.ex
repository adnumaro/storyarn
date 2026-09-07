defmodule Storyarn.Ideation.Recovery.Inventory do
  @moduledoc false
  alias Storyarn.Ideation.Recovery.GraphValidation

  # Closed, versioned persistence contract. Ciphertext is copied as bytes, never
  # loaded through the ordinary encrypted-field schema or returned as plaintext.
  @tables [
    {"sessions", "ideation_sessions", :project_id,
     ~w(id recovery_identity project_id created_by_id facilitator_id decision_owner_id title objective context status archived_at deleted_at revision configuration_version configuration inserted_at updated_at)a},
    {"session_revisions", "ideation_session_revisions", :session_id,
     ~w(id recovery_identity session_id actor_id number action snapshot inserted_at)a},
    {"ideas", "ideation_ideas", :session_id,
     ~w(id recovery_identity session_id author_id author_kind creation_key revision published_revision state publication_consent configuration_version creation_source_id source_idea_id source_revision canvas deleted_at inserted_at updated_at)a},
    {"revisions", "ideation_idea_revisions", :idea_id,
     ~w(id recovery_identity idea_id number actor_id title body state inserted_at)a},
    {"edits", "ideation_idea_edits", :idea_id,
     ~w(id recovery_identity idea_id actor_id request_key fingerprint outcome base_revision result_revision title body state inserted_at)a},
    {"reveals", "ideation_reveal_operations", :session_id,
     ~w(id recovery_identity session_id actor_id request_key selection manifest status completed_at inserted_at updated_at)a},
    {"publications", "ideation_idea_publications", :idea_id,
     ~w(id recovery_identity idea_id revision operation_id actor_id inserted_at)a}
  ]
  @actor_fields ~w(created_by_id facilitator_id decision_owner_id author_id actor_id)a
  @dates ~w(archived_at deleted_at inserted_at updated_at completed_at)a
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
          is_nil(value) -> nil
          key in @dates -> NaiveDateTime.to_iso8601(value)
          binary_field?(collection, key) -> Base.encode64(value)
          key == :canvas -> Map.put_new(value, "links", [])
          true -> value
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

  def validate(%{"format" => "storyarn.ideation", "version" => 1, "rows" => rows, "actors" => actors})
      when is_map(rows) and is_map(actors) do
    expected = Enum.map(@tables, &elem(&1, 0))

    if Enum.sort(Map.keys(rows)) == Enum.sort(expected) and
         Enum.all?(@tables, &valid_rows?(&1, rows)) and
         Enum.sum(Enum.map(rows, fn {_, entries} -> length(entries) end)) <= @max_rows and
         Enum.all?(actors, fn {id, identity} ->
           match?({_, ""}, Integer.parse(id)) and match?({:ok, _}, Ecto.UUID.cast(identity))
         end) and GraphValidation.valid?(rows) do
      :ok
    else
      {:error, :invalid_ideation_recovery}
    end
  end

  def validate(_), do: {:error, :invalid_ideation_recovery}

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
            is_integer(&1["id"]))
      ) and
      length(Enum.uniq_by(entries, & &1["id"])) == length(entries)
  end

  defp binary_field?(collection, key) do
    key in [:recovery_identity, :creation_key, :request_key, :fingerprint] or
      (collection in ["revisions", "edits"] and key in [:title, :body])
  end
end
