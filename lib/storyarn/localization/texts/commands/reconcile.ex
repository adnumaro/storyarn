defmodule Storyarn.Localization.Texts.Commands.Reconcile do
  @moduledoc "Bulk reconciliation and import of the Texts runtime inventory."

  import Ecto.Query, warn: false

  alias Storyarn.Localization.LocalizedText
  alias Storyarn.Localization.SourceContract
  alias Storyarn.Localization.Texts.Adapters.Upserts.Postgres
  alias Storyarn.Localization.Texts.Commands.TranslationAttributes
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Repo

  @doc """
  Batch-upserts localized texts for a project using insert_all with on_conflict.

  Each entry in `entries` should be a map with string keys:
  `source_type`, `source_id`, `source_field`, `source_text`, `source_text_hash`,
  `locale_code`, `word_count`, `content_role`, `vo_eligible`, and optionally
  `speaker_sheet_id`.

  On conflict (same source_type/source_id/source_field/locale_code):
  - Updates source_text, source_text_hash, word_count, speaker_sheet_id
  - Marks any existing translation as needing review when source_text_hash changes

  Returns the total number of entries processed.
  """
  @spec batch_upsert_texts(integer(), [map()]) :: non_neg_integer()
  def batch_upsert_texts(_project_id, []), do: 0

  def batch_upsert_texts(project_id, entries) when is_list(entries) do
    if Repo.in_transaction?() do
      do_batch_upsert_texts(project_id, entries)
    else
      {:ok, count} = Repo.transaction(fn -> do_batch_upsert_texts(project_id, entries) end)
      count
    end
  end

  defp do_batch_upsert_texts(project_id, entries) do
    now = TimeHelpers.now()

    rows =
      Enum.map(entries, fn attrs ->
        attrs = TranslationAttributes.apply_source_metadata(attrs)

        %{
          project_id: project_id,
          source_type: attrs["source_type"],
          source_id: attrs["source_id"],
          source_field: attrs["source_field"],
          source_text: attrs["source_text"],
          source_text_hash: attrs["source_text_hash"],
          locale_code: attrs["locale_code"],
          word_count: attrs["word_count"],
          speaker_sheet_id: attrs["speaker_sheet_id"],
          content_role: attrs["content_role"],
          vo_eligible: attrs["vo_eligible"],
          status: "pending",
          vo_status: "none",
          machine_translated: false,
          inserted_at: now,
          updated_at: now
        }
      end)

    rows
    |> Enum.chunk_every(500)
    |> Enum.each(&Postgres.upsert_chunk/1)

    length(rows)
  end

  @doc """
  Upserts the current runtime strings and removes rows whose source no longer
  belongs to the project localization contract.

  Locale rows for still-live sources are retained when a language is archived,
  so re-enabling a locale does not destroy previous translation work.
  """
  @spec reconcile_project_texts(integer(), [map()], MapSet.t()) :: {:ok, non_neg_integer()} | {:error, term()}
  def reconcile_project_texts(project_id, entries, source_keys) do
    Repo.transaction(fn ->
      batch_upsert_texts(project_id, entries)
      archive_obsolete_project_texts(project_id, source_keys)
      MapSet.size(source_keys)
    end)
  end

  defp archive_obsolete_project_texts(project_id, source_keys) do
    allowed_source_types = SourceContract.source_types()

    obsolete_ids =
      from(t in LocalizedText,
        where: t.project_id == ^project_id and is_nil(t.archived_at),
        select: {t.id, t.source_type, t.source_id, t.source_field}
      )
      |> Repo.all()
      |> Enum.reject(fn {_id, source_type, source_id, source_field} ->
        source_type in allowed_source_types and
          MapSet.member?(source_keys, {source_type, source_id, source_field})
      end)
      |> Enum.map(&elem(&1, 0))

    now = TimeHelpers.now()

    obsolete_ids
    |> Enum.chunk_every(500)
    |> Enum.each(fn ids ->
      Repo.update_all(
        from(t in LocalizedText, where: t.id in ^ids),
        set: [archived_at: now, archive_reason: "source_not_runtime", updated_at: now],
        inc: [lock_version: 1]
      )
    end)

    :ok
  end

  @doc """
  Bulk-inserts localized texts from a list of attr maps.
  Uses on_conflict: :nothing for deduplication.
  """
  def bulk_import_texts(attrs_list) do
    attrs_list
    |> Enum.flat_map(fn attrs ->
      case SourceContract.field_metadata(attrs[:source_type], attrs[:source_field]) do
        nil ->
          []

        metadata ->
          [
            attrs
            |> Map.put(:content_role, metadata.content_role)
            |> Map.put(:vo_eligible, metadata.vo_eligible)
            |> TranslationAttributes.maybe_clear_ineligible_voice(metadata)
          ]
      end
    end)
    |> Enum.chunk_every(500)
    |> Enum.each(fn chunk ->
      Repo.insert_all(LocalizedText, chunk, on_conflict: :nothing)
    end)
  end
end
