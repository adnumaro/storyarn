defmodule Storyarn.Versioning.LocalizationSnapshotCodec do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Accounts.User
  alias Storyarn.Assets.Asset
  alias Storyarn.Localization.LocaleCode
  alias Storyarn.Localization.LocalizedText
  alias Storyarn.Localization.ProjectLanguage
  alias Storyarn.Localization.SourceContract
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Sheets.Sheet

  @manifest_fields ~w(count sha256 target_locales)
  @sha256_regex ~r/\A[0-9a-f]{64}\z/

  @type manifest :: %{
          required(String.t()) => non_neg_integer() | String.t() | [String.t()]
        }

  @doc """
  Builds a deterministic, JSON-safe integrity manifest for localization rows.

  Every field participates in the digest. Map fields are ordered by key and
  rows are ordered by their canonical JSON representation, so the manifest is
  stable across map and row enumeration order.
  """
  @spec manifest([map()], [String.t()] | nil) :: manifest()
  def manifest(rows, target_locales \\ nil) when is_list(rows) do
    target_locales =
      target_locales
      |> Kernel.||(infer_target_locales(rows))
      |> Enum.map(&LocaleCode.normalize/1)
      |> Enum.uniq()
      |> Enum.sort()

    canonical_rows =
      rows
      |> Enum.map(&canonical_json_value/1)
      |> Enum.sort_by(&Jason.encode!/1)

    digest =
      %{
        "rows" => canonical_rows,
        "target_locales" => target_locales
      }
      |> Jason.encode!()
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)

    %{
      "count" => length(rows),
      "sha256" => digest,
      "target_locales" => target_locales
    }
  end

  @doc """
  Verifies the shape, count, and canonical digest of a localization manifest.
  """
  @spec validate_manifest([map()], term()) :: :ok | {:error, term()}
  def validate_manifest(rows, manifest) when is_list(rows) and is_map(manifest) do
    with :ok <- validate_manifest_shape(manifest) do
      validate_manifest_contents(rows, manifest)
    end
  end

  def validate_manifest(_rows, manifest), do: {:error, {:invalid_localization_manifest, manifest}}

  defp validate_manifest_shape(manifest) do
    with :ok <- validate_manifest_fields(manifest),
         :ok <- validate_manifest_count(manifest),
         :ok <- validate_manifest_sha256(manifest) do
      validate_manifest_target_locales(manifest)
    end
  end

  defp validate_manifest_fields(manifest) do
    if manifest |> Map.keys() |> Enum.sort() == @manifest_fields,
      do: :ok,
      else: invalid_manifest(manifest)
  end

  defp validate_manifest_count(%{"count" => count}) when is_integer(count) and count >= 0, do: :ok
  defp validate_manifest_count(manifest), do: invalid_manifest(manifest)

  defp validate_manifest_sha256(%{"sha256" => sha256} = manifest) when is_binary(sha256) do
    if Regex.match?(@sha256_regex, sha256), do: :ok, else: invalid_manifest(manifest)
  end

  defp validate_manifest_sha256(manifest), do: invalid_manifest(manifest)

  defp validate_manifest_target_locales(manifest) do
    if valid_target_locales?(manifest["target_locales"]),
      do: :ok,
      else: invalid_manifest(manifest)
  end

  defp validate_manifest_contents(rows, manifest) do
    expected = manifest(rows, manifest["target_locales"])

    if manifest == expected,
      do: :ok,
      else: {:error, {:localization_manifest_mismatch, manifest, expected}}
  end

  defp invalid_manifest(manifest), do: {:error, {:invalid_localization_manifest, manifest}}

  @spec active_target_locales(integer()) :: [String.t()]
  def active_target_locales(project_id) do
    Repo.all(
      from(language in ProjectLanguage,
        where: language.project_id == ^project_id and language.is_source == false and is_nil(language.archived_at),
        select: language.locale_code,
        order_by: [asc: language.locale_code]
      )
    )
  end

  @spec active_target_rows(integer(), [map()]) :: [map()]
  def active_target_rows(project_id, rows) when is_list(rows) do
    active_locales = project_id |> active_target_locales() |> MapSet.new()
    Enum.filter(rows, &MapSet.member?(active_locales, &1["locale_code"]))
  end

  @spec capture(integer(), %{optional(String.t()) => [integer()]}, keyword()) :: [map()]
  def capture(project_id, sources, opts \\ []) do
    include_archived? = Keyword.get(opts, :include_archived, false)
    target_locales = Keyword.get_lazy(opts, :target_locales, fn -> active_target_locales(project_id) end)

    sources
    |> Enum.flat_map(fn {source_type, source_ids} ->
      query =
        from(t in LocalizedText,
          where:
            t.project_id == ^project_id and t.source_type == ^source_type and
              t.source_id in ^source_ids and t.locale_code in ^target_locales,
          order_by: [asc: t.source_id, asc: t.source_field, asc: t.locale_code]
        )

      query = if include_archived?, do: query, else: where(query, [t], is_nil(t.archived_at))
      Repo.all(query)
    end)
    |> Enum.map(&to_snapshot/1)
  end

  @spec restore(integer(), [map()], map()) :: :ok | {:error, term()}
  def restore(_project_id, [], _id_maps), do: :ok

  def restore(project_id, rows, id_maps) do
    if Repo.in_transaction?() do
      do_restore(project_id, rows, id_maps)
    else
      restore_in_transaction(project_id, rows, id_maps)
    end
  end

  defp restore_in_transaction(project_id, rows, id_maps) do
    fn ->
      project_id
      |> do_restore(rows, id_maps)
      |> rollback_failed_restore()
    end
    |> Repo.transaction()
    |> normalize_restore_transaction()
  end

  defp rollback_failed_restore(:ok), do: :ok
  defp rollback_failed_restore({:error, reason}), do: Repo.rollback(reason)

  defp normalize_restore_transaction({:ok, :ok}), do: :ok
  defp normalize_restore_transaction({:error, reason}), do: {:error, reason}

  defp do_restore(project_id, rows, id_maps) do
    context = restore_context(project_id, rows)
    now = TimeHelpers.now()

    with :ok <- validate_referenced_ids(rows, context),
         {:ok, entries} <- materialize_restore_entries(rows, project_id, id_maps, context, now) do
      insert_restore_entries(entries)
    end
  end

  defp materialize_restore_entries(rows, project_id, id_maps, context, now) do
    entries = Enum.flat_map(rows, &restore_entry(&1, project_id, id_maps, context, now))

    if length(entries) == length(rows) do
      {:ok, deduplicate_entries(entries)}
    else
      {:error, {:localization_restore_unmaterialized_rows, length(rows), length(entries)}}
    end
  end

  defp insert_restore_entries(entries) do
    result =
      Repo.insert_all(LocalizedText, entries,
        on_conflict: restore_conflict_query(),
        conflict_target: [:source_type, :source_id, :source_field, :locale_code]
      )

    case result do
      {count, _} when count == length(entries) -> :ok
      other -> {:error, {:localization_restore_failed, other}}
    end
  end

  defp restore_conflict_query do
    from(text in LocalizedText,
      update: [
        set: [
          project_id: fragment("EXCLUDED.project_id"),
          source_text: fragment("EXCLUDED.source_text"),
          source_text_hash: fragment("EXCLUDED.source_text_hash"),
          translated_source_hash: fragment("EXCLUDED.translated_source_hash"),
          translated_text: fragment("EXCLUDED.translated_text"),
          status: fragment("EXCLUDED.status"),
          vo_status: fragment("EXCLUDED.vo_status"),
          vo_asset_id: fragment("EXCLUDED.vo_asset_id"),
          translator_notes: fragment("EXCLUDED.translator_notes"),
          reviewer_notes: fragment("EXCLUDED.reviewer_notes"),
          speaker_sheet_id: fragment("EXCLUDED.speaker_sheet_id"),
          word_count: fragment("EXCLUDED.word_count"),
          content_role: fragment("EXCLUDED.content_role"),
          vo_eligible: fragment("EXCLUDED.vo_eligible"),
          machine_translated: fragment("EXCLUDED.machine_translated"),
          last_translated_at: fragment("EXCLUDED.last_translated_at"),
          last_reviewed_at: fragment("EXCLUDED.last_reviewed_at"),
          translated_by_id: fragment("EXCLUDED.translated_by_id"),
          reviewed_by_id: fragment("EXCLUDED.reviewed_by_id"),
          archived_at: fragment("EXCLUDED.archived_at"),
          archive_reason: fragment("EXCLUDED.archive_reason"),
          updated_at: fragment("EXCLUDED.updated_at")
        ],
        inc: [lock_version: 1]
      ]
    )
  end

  defp deduplicate_entries(entries) do
    entries
    |> Enum.reverse()
    |> Enum.uniq_by(&{&1.source_type, &1.source_id, &1.source_field, &1.locale_code})
    |> Enum.reverse()
  end

  defp infer_target_locales(rows) do
    rows
    |> Enum.map(& &1["locale_code"])
    |> Enum.filter(&is_binary/1)
  end

  defp valid_target_locales?(target_locales) when is_list(target_locales) do
    canonical =
      target_locales
      |> Enum.uniq()
      |> Enum.sort()

    target_locales == canonical and
      Enum.all?(target_locales, fn locale ->
        LocaleCode.valid?(locale) and locale == LocaleCode.normalize(locale)
      end)
  end

  defp valid_target_locales?(_target_locales), do: false

  defp restore_entry(row, project_id, id_maps, context, now) do
    source_type = row["source_type"]
    source_field = row["source_field"]

    with metadata when not is_nil(metadata) <- SourceContract.field_metadata(source_type, source_field),
         source_id when not is_nil(source_id) <- remap_source_id(source_type, row["source_id"], id_maps),
         true <- MapSet.member?(context.locales, row["locale_code"]) do
      vo_asset_id = valid_id(row["vo_asset_id"], context.assets)
      translated_by_id = valid_id(row["translated_by_id"], context.users)
      reviewed_by_id = valid_id(row["reviewed_by_id"], context.users)
      speaker_sheet_id = valid_id(row["speaker_sheet_id"], context.sheets)
      status = normalize_status(row)
      archived_at = parse_datetime(row["archived_at"])

      [
        %{
          project_id: project_id,
          source_type: source_type,
          source_id: source_id,
          source_field: source_field,
          source_text: row["source_text"],
          source_text_hash: row["source_text_hash"],
          translated_source_hash: row["translated_source_hash"],
          locale_code: row["locale_code"],
          translated_text: row["translated_text"],
          status: status,
          vo_status: normalize_vo_status(row["vo_status"], metadata.vo_eligible, vo_asset_id),
          vo_asset_id: if(metadata.vo_eligible, do: vo_asset_id),
          translator_notes: row["translator_notes"],
          reviewer_notes: row["reviewer_notes"],
          speaker_sheet_id: if(metadata.content_role in ~w(dialogue response), do: speaker_sheet_id),
          word_count: row["word_count"],
          content_role: metadata.content_role,
          vo_eligible: metadata.vo_eligible,
          machine_translated: row["machine_translated"] || false,
          last_translated_at: parse_datetime(row["last_translated_at"]),
          last_reviewed_at: parse_datetime(row["last_reviewed_at"]),
          translated_by_id: translated_by_id,
          reviewed_by_id: reviewed_by_id,
          archived_at: archived_at,
          archive_reason: normalize_archive_reason(row["archive_reason"], archived_at),
          lock_version: 1,
          inserted_at: now,
          updated_at: now
        }
      ]
    else
      _ -> []
    end
  end

  defp restore_context(project_id, rows) do
    %{
      locales:
        from(l in ProjectLanguage, where: l.project_id == ^project_id, select: l.locale_code)
        |> Repo.all()
        |> MapSet.new(),
      assets: project_ids(Asset, project_id, rows, "vo_asset_id"),
      sheets: project_ids(Sheet, project_id, rows, "speaker_sheet_id"),
      users: existing_ids(User, rows, ["translated_by_id", "reviewed_by_id"])
    }
  end

  defp validate_referenced_ids(rows, context) do
    references = [
      {"vo_asset_id", context.assets},
      {"speaker_sheet_id", context.sheets},
      {"translated_by_id", context.users},
      {"reviewed_by_id", context.users}
    ]

    case Enum.find_value(rows, &invalid_row_reference(&1, references)) do
      nil -> :ok
      {field, id} -> {:error, {:localization_reference_not_materializable, field, id}}
    end
  end

  defp invalid_row_reference(row, references) do
    Enum.find_value(references, &invalid_field_reference(row, &1))
  end

  defp invalid_field_reference(row, {field, valid_ids}) do
    case row[field] do
      nil -> nil
      id -> if MapSet.member?(valid_ids, id), do: nil, else: {field, id}
    end
  end

  defp project_ids(Sheet, project_id, rows, key) do
    ids = rows |> Enum.map(& &1[key]) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    from(sheet in Sheet,
      where:
        sheet.project_id == ^project_id and sheet.id in ^ids and
          is_nil(sheet.deleted_at),
      order_by: [asc: sheet.id],
      lock: "FOR UPDATE",
      select: sheet.id
    )
    |> Repo.all()
    |> MapSet.new()
  end

  defp project_ids(schema, project_id, rows, key) do
    ids = rows |> Enum.map(& &1[key]) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    from(record in schema,
      where: record.project_id == ^project_id and record.id in ^ids,
      order_by: [asc: record.id],
      lock: "FOR UPDATE",
      select: record.id
    )
    |> Repo.all()
    |> MapSet.new()
  end

  defp existing_ids(schema, rows, keys) do
    ids =
      rows
      |> Enum.flat_map(fn row -> Enum.map(keys, &row[&1]) end)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    from(record in schema, where: record.id in ^ids, select: record.id) |> Repo.all() |> MapSet.new()
  end

  defp remap_source_id("flow_node", source_id, id_maps), do: get_in(id_maps, [:node, source_id])
  defp remap_source_id("block", source_id, id_maps), do: get_in(id_maps, [:block, source_id])
  defp remap_source_id("sheet", source_id, id_maps), do: get_in(id_maps, [:sheet, source_id])
  defp remap_source_id(_source_type, _source_id, _id_maps), do: nil

  defp normalize_status(row) do
    translated? = present?(row["translated_text"])
    source_hash = row["source_text_hash"]

    current? =
      translated? and present?(source_hash) and
        row["translated_source_hash"] == source_hash

    case row["status"] do
      "final" when not current? -> if(translated?, do: "review", else: "pending")
      status when status in ~w(pending draft in_progress review final) -> status
      _ -> if(translated?, do: "draft", else: "pending")
    end
  end

  defp normalize_vo_status(_status, false, _asset_id), do: "none"
  defp normalize_vo_status(status, true, nil) when status in ~w(recorded approved), do: "needed"
  defp normalize_vo_status(status, true, _asset_id) when status in ~w(none needed recorded approved), do: status
  defp normalize_vo_status(_status, true, _asset_id), do: "none"

  defp normalize_archive_reason(reason, %DateTime{})
       when reason in ~w(source_deleted source_field_removed source_not_runtime version_replaced), do: reason

  defp normalize_archive_reason(_reason, _archived_at), do: nil

  defp valid_id(nil, _valid_ids), do: nil
  defp valid_id(id, valid_ids), do: if(MapSet.member?(valid_ids, id), do: id)

  defp parse_datetime(nil), do: nil
  defp parse_datetime(%DateTime{} = datetime), do: datetime

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _ -> nil
    end
  end

  defp parse_datetime(_value), do: nil

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_value), do: false

  defp canonical_json_value(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp canonical_json_value(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp canonical_json_value(%Date{} = value), do: Date.to_iso8601(value)
  defp canonical_json_value(%Time{} = value), do: Time.to_iso8601(value)
  defp canonical_json_value(%Decimal{} = value), do: Decimal.to_string(value, :normal)

  defp canonical_json_value(value) when is_map(value) do
    value
    |> Enum.map(fn {key, nested_value} ->
      [canonical_json_key(key), canonical_json_value(nested_value)]
    end)
    |> Enum.sort_by(&hd/1)
  end

  defp canonical_json_value(value) when is_list(value), do: Enum.map(value, &canonical_json_value/1)

  defp canonical_json_value(value) when is_binary(value) or is_number(value) or is_boolean(value) or is_nil(value),
    do: value

  defp canonical_json_value(value), do: inspect(value)

  defp canonical_json_key(key) when is_binary(key), do: key
  defp canonical_json_key(key) when is_atom(key), do: Atom.to_string(key)
  defp canonical_json_key(key), do: to_string(key)

  defp to_snapshot(text) do
    %{
      "source_type" => text.source_type,
      "source_id" => text.source_id,
      "source_field" => text.source_field,
      "source_text" => text.source_text,
      "source_text_hash" => text.source_text_hash,
      "translated_source_hash" => text.translated_source_hash,
      "locale_code" => text.locale_code,
      "translated_text" => text.translated_text,
      "status" => text.status,
      "vo_status" => text.vo_status,
      "vo_asset_id" => text.vo_asset_id,
      "translator_notes" => text.translator_notes,
      "reviewer_notes" => text.reviewer_notes,
      "speaker_sheet_id" => text.speaker_sheet_id,
      "word_count" => text.word_count,
      "machine_translated" => text.machine_translated,
      "last_translated_at" => text.last_translated_at,
      "last_reviewed_at" => text.last_reviewed_at,
      "translated_by_id" => text.translated_by_id,
      "reviewed_by_id" => text.reviewed_by_id,
      "archived_at" => text.archived_at,
      "archive_reason" => text.archive_reason
    }
  end
end
