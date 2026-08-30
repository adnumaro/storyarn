defmodule Storyarn.Localization.Texts.Commands.VersionRestore do
  @moduledoc """
  Restores version-owned localization state inside a caller-owned transaction.

  Flows and Sheets own their snapshot orchestration and source identities.
  Localization owns validation and persistence of the localized-text rows. The
  caller must lock its Project and aggregate before entering this command; the
  command then joins that transaction and serializes the shared inventory.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Localization.LocalizedText
  alias Storyarn.Localization.SourceContract
  alias Storyarn.Localization.Texts.Commands.Extract
  alias Storyarn.Localization.Texts.Projections.AssetRecord
  alias Storyarn.Localization.Texts.Projections.LanguageRecord
  alias Storyarn.Localization.Texts.Projections.SheetRecord
  alias Storyarn.Localization.Texts.Projections.UserRecord
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Repo

  @flow_source_types MapSet.new(["flow_node"])
  @sheet_source_types MapSet.new(["block", "sheet"])

  @doc """
  Archives the current Flow-localization inventory before exact replacement.

  This deliberately uses one timestamp for both archive phases, matching the
  pre-ownership Flow restore contract.
  """
  @spec prepare_flow(pos_integer(), [pos_integer()], [pos_integer()]) :: :ok
  def prepare_flow(project_id, deleted_node_ids, target_node_ids)
      when is_integer(project_id) and is_list(deleted_node_ids) and is_list(target_node_ids) do
    ensure_transaction!()
    Extract.lock_inventory!(project_id)

    now = TimeHelpers.now()
    archive_flow_nodes(project_id, deleted_node_ids, "source_deleted", now)
    archive_active_target_flow_nodes(project_id, target_node_ids, "version_replaced", now)
    :ok
  end

  @doc "Restores exact Flow localization rows using the supplied node ID map."
  @spec restore_flow(pos_integer(), [map()], map()) :: :ok | {:error, term()}
  def restore_flow(_project_id, [], _id_maps), do: :ok

  def restore_flow(project_id, rows, id_maps) when is_integer(project_id) and is_list(rows) and is_map(id_maps) do
    restore(project_id, rows, id_maps, @flow_source_types)
  end

  @doc "Restores exact Sheet localization rows using Sheet and Block ID maps."
  @spec restore_sheet(pos_integer(), [map()], map()) :: :ok | {:error, term()}
  def restore_sheet(_project_id, [], _id_maps), do: :ok

  def restore_sheet(project_id, rows, id_maps) when is_integer(project_id) and is_list(rows) and is_map(id_maps) do
    restore(project_id, rows, id_maps, @sheet_source_types)
  end

  defp restore(project_id, rows, id_maps, allowed_source_types) do
    ensure_transaction!()
    Extract.lock_inventory!(project_id)

    do_restore(project_id, rows, id_maps, allowed_source_types)
  end

  defp do_restore(project_id, rows, id_maps, allowed_source_types) do
    context = restore_context(project_id, rows)
    now = TimeHelpers.now()

    with :ok <- validate_referenced_ids(rows, context),
         {:ok, entries} <-
           materialize_restore_entries(
             rows,
             project_id,
             id_maps,
             allowed_source_types,
             context,
             now
           ) do
      insert_restore_entries(entries)
    end
  end

  defp materialize_restore_entries(rows, project_id, id_maps, allowed_source_types, context, now) do
    entries =
      Enum.flat_map(
        rows,
        &restore_entry(
          &1,
          project_id,
          id_maps,
          allowed_source_types,
          context,
          now
        )
      )

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

  defp restore_entry(row, project_id, id_maps, allowed_source_types, context, now) do
    source_type = row["source_type"]
    source_field = row["source_field"]

    with true <- MapSet.member?(allowed_source_types, source_type),
         metadata when not is_nil(metadata) <-
           SourceContract.field_metadata(source_type, source_field),
         source_id when not is_nil(source_id) <-
           remap_source_id(source_type, row["source_id"], id_maps),
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
        from(language in LanguageRecord,
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
    Enum.find_value(references, &invalid_field_reference(row, &1))
  end

  defp invalid_field_reference(row, {field, valid_ids}) do
    case row[field] do
      nil -> nil
      id -> if MapSet.member?(valid_ids, id), do: nil, else: {field, id}
    end
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

  defp deduplicate_entries(entries) do
    entries
    |> Enum.reverse()
    |> Enum.uniq_by(&{&1.source_type, &1.source_id, &1.source_field, &1.locale_code})
    |> Enum.reverse()
  end

  defp archive_flow_nodes(_project_id, [], _reason, _now), do: {0, nil}

  defp archive_flow_nodes(project_id, node_ids, reason, now) do
    Repo.update_all(
      from(text in LocalizedText,
        where:
          text.project_id == ^project_id and text.source_type == "flow_node" and
            text.source_id in ^node_ids and is_nil(text.archived_at)
      ),
      set: [archived_at: now, archive_reason: reason, updated_at: now],
      inc: [lock_version: 1]
    )
  end

  defp archive_active_target_flow_nodes(_project_id, [], _reason, _now), do: {0, nil}

  defp archive_active_target_flow_nodes(project_id, node_ids, reason, now) do
    active_target_locales =
      from(language in LanguageRecord,
        where:
          language.project_id == ^project_id and language.is_source == false and
            is_nil(language.archived_at),
        select: language.locale_code
      )

    Repo.update_all(
      from(text in LocalizedText,
        where:
          text.project_id == ^project_id and text.source_type == "flow_node" and
            text.source_id in ^node_ids and is_nil(text.archived_at) and
            text.locale_code in subquery(active_target_locales)
      ),
      set: [archived_at: now, archive_reason: reason, updated_at: now],
      inc: [lock_version: 1]
    )
  end

  defp ensure_transaction! do
    if not Repo.in_transaction?() do
      raise ArgumentError,
            "localization version restore requires an explicit database transaction"
    end
  end
end
