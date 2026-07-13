defmodule Storyarn.Versioning.LocalizationSnapshotCodec do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Accounts.User
  alias Storyarn.Assets.Asset
  alias Storyarn.Localization.LocalizedText
  alias Storyarn.Localization.ProjectLanguage
  alias Storyarn.Localization.SourceContract
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Sheets.Sheet

  @replace_fields [
    :project_id,
    :source_text,
    :source_text_hash,
    :translated_source_hash,
    :translated_text,
    :status,
    :vo_status,
    :vo_asset_id,
    :translator_notes,
    :reviewer_notes,
    :speaker_sheet_id,
    :word_count,
    :content_role,
    :vo_eligible,
    :machine_translated,
    :last_translated_at,
    :last_reviewed_at,
    :translated_by_id,
    :reviewed_by_id,
    :archived_at,
    :archive_reason,
    :lock_version,
    :updated_at
  ]

  @spec capture(integer(), %{optional(String.t()) => [integer()]}, keyword()) :: [map()]
  def capture(project_id, sources, opts \\ []) do
    include_archived? = Keyword.get(opts, :include_archived, false)

    sources
    |> Enum.flat_map(fn {source_type, source_ids} ->
      query =
        from(t in LocalizedText,
          where:
            t.project_id == ^project_id and t.source_type == ^source_type and
              t.source_id in ^source_ids,
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
    context = restore_context(project_id, rows)
    now = TimeHelpers.now()

    entries =
      rows
      |> Enum.flat_map(&restore_entry(&1, project_id, id_maps, context, now))
      |> deduplicate_entries()

    case Repo.insert_all(LocalizedText, entries,
           on_conflict: {:replace, @replace_fields},
           conflict_target: [:source_type, :source_id, :source_field, :locale_code]
         ) do
      {count, _} when count == length(entries) -> :ok
      other -> {:error, {:localization_restore_failed, other}}
    end
  end

  defp deduplicate_entries(entries) do
    entries
    |> Enum.reverse()
    |> Enum.uniq_by(&{&1.source_type, &1.source_id, &1.source_field, &1.locale_code})
    |> Enum.reverse()
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
          speaker_sheet_id: if(metadata.content_role == "dialogue", do: speaker_sheet_id),
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

  defp project_ids(schema, project_id, rows, key) do
    ids = rows |> Enum.map(& &1[key]) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    from(record in schema, where: record.project_id == ^project_id and record.id in ^ids, select: record.id)
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
