defmodule Storyarn.Flows.Versioning.LocalizationCodec do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Flows.Persistence.AssetRecord
  alias Storyarn.Flows.Persistence.SheetRecord
  alias Storyarn.Flows.Versioning.LocaleCode
  alias Storyarn.Flows.Versioning.LocalizedTextRecord
  alias Storyarn.Flows.Versioning.ProjectLanguageRecord
  alias Storyarn.Flows.Versioning.SourceContract
  alias Storyarn.Flows.Versioning.UserRecord
  alias Storyarn.Repo
  alias Storyarn.Shared.HtmlUtils
  alias Storyarn.Shared.TimeHelpers

  @manifest_fields ~w(count sha256 target_locales)
  @sha256_regex ~r/\A[0-9a-f]{64}\z/
  @snapshot_fields ~w(
    source_type source_id source_field source_text source_text_hash translated_source_hash
    locale_code translated_text status vo_status vo_asset_id translator_notes reviewer_notes
    speaker_sheet_id word_count machine_translated last_translated_at last_reviewed_at
    translated_by_id reviewed_by_id archived_at archive_reason
  )

  @spec manifest([map()], [String.t()] | nil) :: map()
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
      %{"rows" => canonical_rows, "target_locales" => target_locales}
      |> Jason.encode!()
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)

    %{"count" => length(rows), "sha256" => digest, "target_locales" => target_locales}
  end

  @spec validate_manifest([map()], term()) :: :ok | {:error, term()}
  def validate_manifest(rows, manifest) when is_list(rows) and is_map(manifest) do
    with :ok <- validate_manifest_shape(manifest) do
      expected = manifest(rows, manifest["target_locales"])

      if manifest == expected,
        do: :ok,
        else: {:error, {:localization_manifest_mismatch, manifest, expected}}
    end
  end

  def validate_manifest(_rows, manifest), do: {:error, {:invalid_localization_manifest, manifest}}

  @spec active_target_locales(pos_integer()) :: [String.t()]
  def active_target_locales(project_id) do
    Repo.all(
      from(language in ProjectLanguageRecord,
        where:
          language.project_id == ^project_id and language.is_source == false and
            is_nil(language.archived_at),
        select: language.locale_code,
        order_by: [asc: language.locale_code]
      )
    )
  end

  @spec active_target_rows(pos_integer(), [map()]) :: [map()]
  def active_target_rows(project_id, rows) when is_list(rows) do
    active_locales = project_id |> active_target_locales() |> MapSet.new()
    Enum.filter(rows, &MapSet.member?(active_locales, &1["locale_code"]))
  end

  @spec complete_pending_rows([map()], [map()], Enumerable.t()) :: [map()]
  def complete_pending_rows(rows, sources, target_locales) when is_list(rows) and is_list(sources) do
    actual = MapSet.new(rows, &snapshot_key/1)

    missing =
      sources
      |> Enum.sort_by(&snapshot_source_key/1)
      |> Enum.flat_map(fn source ->
        target_locales
        |> Enum.sort()
        |> Enum.reject(&MapSet.member?(actual, {snapshot_source_key(source), &1}))
        |> Enum.map(&pending_snapshot_row(source, &1))
      end)

    rows ++ missing
  end

  @spec capture(pos_integer(), %{optional(String.t()) => [integer()]}, keyword()) :: [map()]
  def capture(project_id, sources, opts \\ []) do
    include_archived? = Keyword.get(opts, :include_archived, false)
    target_locales = Keyword.get_lazy(opts, :target_locales, fn -> active_target_locales(project_id) end)

    sources
    |> Enum.flat_map(fn {source_type, source_ids} ->
      query =
        from(text in LocalizedTextRecord,
          where:
            text.project_id == ^project_id and text.source_type == ^source_type and
              text.source_id in ^source_ids and text.locale_code in ^target_locales,
          order_by: [asc: text.source_id, asc: text.source_field, asc: text.locale_code]
        )

      query = if include_archived?, do: query, else: where(query, [text], is_nil(text.archived_at))
      Repo.all(query)
    end)
    |> Enum.map(&to_snapshot/1)
  end

  @spec restore(pos_integer(), [map()], map()) :: :ok | {:error, term()}
  def restore(_project_id, [], _id_maps), do: :ok

  def restore(project_id, rows, id_maps) do
    if Repo.in_transaction?() do
      do_restore(project_id, rows, id_maps)
    else
      restore_in_transaction(project_id, rows, id_maps)
    end
  end

  defp restore_in_transaction(project_id, rows, id_maps) do
    case Repo.transaction(fn -> rollback_failed_restore(do_restore(project_id, rows, id_maps)) end) do
      {:ok, :ok} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp rollback_failed_restore(:ok), do: :ok
  defp rollback_failed_restore({:error, reason}), do: Repo.rollback(reason)

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
      {:ok,
       entries
       |> Enum.reverse()
       |> Enum.uniq_by(&{&1.source_type, &1.source_id, &1.source_field, &1.locale_code})
       |> Enum.reverse()}
    else
      {:error, {:localization_restore_unmaterialized_rows, length(rows), length(entries)}}
    end
  end

  defp insert_restore_entries(entries) do
    result =
      Repo.insert_all(LocalizedTextRecord, entries,
        on_conflict: restore_conflict_query(),
        conflict_target: [:source_type, :source_id, :source_field, :locale_code]
      )

    case result do
      {count, _} when count == length(entries) -> :ok
      other -> {:error, {:localization_restore_failed, other}}
    end
  end

  defp restore_conflict_query do
    from(text in LocalizedTextRecord,
      where: text.project_id == fragment("EXCLUDED.project_id"),
      update: [
        set: [
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
      _invalid -> []
    end
  end

  defp restore_context(project_id, rows) do
    %{
      locales:
        from(language in ProjectLanguageRecord,
          where: language.project_id == ^project_id,
          select: language.locale_code
        )
        |> Repo.all()
        |> MapSet.new(),
      assets: project_ids(AssetRecord, project_id, rows, "vo_asset_id"),
      sheets: project_ids(SheetRecord, project_id, rows, "speaker_sheet_id"),
      users: existing_ids(UserRecord, rows, ["translated_by_id", "reviewed_by_id"])
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
    Enum.find_value(references, fn {field, valid_ids} ->
      invalid_reference(row[field], field, valid_ids)
    end)
  end

  defp invalid_reference(nil, _field, _valid_ids), do: nil

  defp invalid_reference(id, field, valid_ids) do
    if MapSet.member?(valid_ids, id), do: nil, else: {field, id}
  end

  defp project_ids(SheetRecord, project_id, rows, key) do
    ids = rows |> Enum.map(& &1[key]) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    from(sheet in SheetRecord,
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

    from(record in schema, where: record.id in ^ids, select: record.id)
    |> Repo.all()
    |> MapSet.new()
  end

  defp remap_source_id("flow_node", source_id, id_maps), do: get_in(id_maps, [:node, source_id])
  defp remap_source_id(_source_type, _source_id, _id_maps), do: nil

  defp normalize_status(row) do
    translated? = present?(row["translated_text"])
    source_hash = row["source_text_hash"]
    current? = translated? and present?(source_hash) and row["translated_source_hash"] == source_hash

    case row["status"] do
      "final" when not current? -> if(translated?, do: "review", else: "pending")
      status when status in ~w(pending draft in_progress review final) -> status
      _invalid -> if(translated?, do: "draft", else: "pending")
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
      _invalid -> nil
    end
  end

  defp parse_datetime(_value), do: nil

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_value), do: false

  defp validate_manifest_shape(manifest) do
    valid? =
      manifest |> Map.keys() |> Enum.sort() == @manifest_fields and
        is_integer(manifest["count"]) and manifest["count"] >= 0 and
        is_binary(manifest["sha256"]) and Regex.match?(@sha256_regex, manifest["sha256"]) and
        valid_target_locales?(manifest["target_locales"])

    if valid?, do: :ok, else: {:error, {:invalid_localization_manifest, manifest}}
  end

  defp valid_target_locales?(target_locales) when is_list(target_locales) do
    canonical = target_locales |> Enum.uniq() |> Enum.sort()

    target_locales == canonical and
      Enum.all?(target_locales, fn locale ->
        LocaleCode.valid?(locale) and locale == LocaleCode.normalize(locale)
      end)
  end

  defp valid_target_locales?(_target_locales), do: false

  defp infer_target_locales(rows) do
    rows |> Enum.map(& &1["locale_code"]) |> Enum.filter(&is_binary/1)
  end

  defp snapshot_key(row), do: {{row["source_type"], row["source_id"], row["source_field"]}, row["locale_code"]}

  defp snapshot_source_key(source), do: {source["source_type"], source["source_id"], source["source_field"]}

  defp pending_snapshot_row(source, locale_code) do
    source_text = source["source_text"]

    %{
      "source_type" => source["source_type"],
      "source_id" => source["source_id"],
      "source_field" => source["source_field"],
      "source_text" => source_text,
      "source_text_hash" => source_text_hash(source_text),
      "translated_source_hash" => nil,
      "locale_code" => locale_code,
      "translated_text" => nil,
      "status" => "pending",
      "vo_status" => "none",
      "vo_asset_id" => nil,
      "translator_notes" => nil,
      "reviewer_notes" => nil,
      "speaker_sheet_id" => source["speaker_sheet_id"],
      "word_count" => HtmlUtils.word_count(source_text),
      "machine_translated" => false,
      "last_translated_at" => nil,
      "last_reviewed_at" => nil,
      "translated_by_id" => nil,
      "reviewed_by_id" => nil,
      "archived_at" => nil,
      "archive_reason" => nil
    }
  end

  defp source_text_hash(text) do
    :sha256 |> :crypto.hash(text) |> Base.encode16(case: :lower)
  end

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
    Map.new(@snapshot_fields, fn field ->
      value = Map.fetch!(text, String.to_existing_atom(field))
      {field, canonical_snapshot_value(value)}
    end)
  end

  defp canonical_snapshot_value(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp canonical_snapshot_value(value), do: value
end
