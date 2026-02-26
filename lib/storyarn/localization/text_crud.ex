defmodule Storyarn.Localization.TextCrud do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Localization.LocalizedText
  alias Storyarn.Repo
  alias Storyarn.Shared.MapUtils

  # =============================================================================
  # Queries
  # =============================================================================

  @doc """
  Lists all localized texts for a project, optionally filtered.

  Options:
  - `:locale_code` - Filter by locale
  - `:status` - Filter by status
  - `:source_type` - Filter by source type
  - `:speaker_sheet_id` - Filter by speaker
  - `:search` - Search in source_text and translated_text
  - `:limit` - Max results
  - `:offset` - Offset for pagination
  """
  def list_texts(project_id, opts \\ []) do
    from(t in LocalizedText,
      where: t.project_id == ^project_id,
      order_by: [asc: t.source_type, asc: t.source_id, asc: t.source_field]
    )
    |> maybe_filter_locale(opts[:locale_code])
    |> maybe_filter_status(opts[:status])
    |> maybe_filter_source_type(opts[:source_type])
    |> maybe_filter_speaker(opts[:speaker_sheet_id])
    |> maybe_search(opts[:search])
    |> maybe_paginate(opts[:limit], opts[:offset])
    |> Repo.all()
  end

  @doc """
  Counts localized texts for a project, optionally filtered.
  Accepts the same filter options as `list_texts/2`.
  """
  def count_texts(project_id, opts \\ []) do
    from(t in LocalizedText,
      where: t.project_id == ^project_id,
      select: count(t.id)
    )
    |> maybe_filter_locale(opts[:locale_code])
    |> maybe_filter_status(opts[:status])
    |> maybe_filter_source_type(opts[:source_type])
    |> maybe_filter_speaker(opts[:speaker_sheet_id])
    |> maybe_search(opts[:search])
    |> Repo.one!()
  end

  def get_text(project_id, id) do
    from(t in LocalizedText, where: t.id == ^id and t.project_id == ^project_id)
    |> Repo.one()
  end

  def get_text!(project_id, id) do
    from(t in LocalizedText, where: t.id == ^id and t.project_id == ^project_id)
    |> Repo.one!()
  end

  @doc """
  Gets a specific localized text by its composite key.
  """
  def get_text_by_source(source_type, source_id, source_field, locale_code) do
    from(t in LocalizedText,
      where:
        t.source_type == ^source_type and
          t.source_id == ^source_id and
          t.source_field == ^source_field and
          t.locale_code == ^locale_code
    )
    |> Repo.one()
  end

  @doc """
  Gets all localized texts for a source entity across all locales.
  """
  def get_texts_for_source(source_type, source_id) do
    from(t in LocalizedText,
      where: t.source_type == ^source_type and t.source_id == ^source_id,
      order_by: [asc: t.source_field, asc: t.locale_code]
    )
    |> Repo.all()
  end

  @doc """
  Gets translation progress stats for a project and locale.
  Returns `%{total: integer, pending: integer, draft: integer, in_progress: integer, review: integer, final: integer}`.
  """
  def get_progress(project_id, locale_code) do
    from(t in LocalizedText,
      where: t.project_id == ^project_id and t.locale_code == ^locale_code,
      group_by: t.status,
      select: {t.status, count(t.id)}
    )
    |> Repo.all()
    |> Enum.into(%{})
    |> then(fn counts ->
      total =
        Map.values(counts) |> Enum.sum()

      %{
        total: total,
        pending: Map.get(counts, "pending", 0),
        draft: Map.get(counts, "draft", 0),
        in_progress: Map.get(counts, "in_progress", 0),
        review: Map.get(counts, "review", 0),
        final: Map.get(counts, "final", 0)
      }
    end)
  end

  # =============================================================================
  # Mutations
  # =============================================================================

  def create_text(project_id, attrs) do
    attrs = MapUtils.stringify_keys(attrs)

    %LocalizedText{project_id: project_id}
    |> LocalizedText.create_changeset(attrs)
    |> Repo.insert()
  end

  def update_text(%LocalizedText{} = text, attrs) do
    attrs = MapUtils.stringify_keys(attrs)

    text
    |> LocalizedText.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Upserts a localized text by its composite key.
  Creates if not exists, updates source_text if hash changed.
  Returns `{:ok, localized_text}` or `{:error, changeset}`.
  """
  def upsert_text(project_id, attrs) do
    attrs = MapUtils.stringify_keys(attrs)

    source_type = attrs["source_type"]
    source_id = attrs["source_id"]
    source_field = attrs["source_field"]
    locale_code = attrs["locale_code"]

    case get_text_by_source(source_type, source_id, source_field, locale_code) do
      nil ->
        create_text(project_id, attrs)

      existing ->
        update_source_text(existing, attrs)
    end
  end

  @doc """
  Deletes all localized texts for a given source entity.
  Used when the source entity is deleted.
  """
  def delete_texts_for_source(source_type, source_id) do
    from(t in LocalizedText,
      where: t.source_type == ^source_type and t.source_id == ^source_id
    )
    |> Repo.delete_all()
  end

  @doc """
  Deletes all localized texts for a given source field.
  Used when a specific field is removed (e.g., a response deleted from a dialogue node).
  """
  def delete_texts_for_source_field(source_type, source_id, source_field) do
    from(t in LocalizedText,
      where:
        t.source_type == ^source_type and
          t.source_id == ^source_id and
          t.source_field == ^source_field
    )
    |> Repo.delete_all()
  end

  # =============================================================================
  # Private
  # =============================================================================

  defp update_source_text(%LocalizedText{} = existing, attrs) do
    new_hash = attrs["source_text_hash"]

    if new_hash && new_hash != existing.source_text_hash do
      # Source text changed — update source and possibly downgrade status
      new_status = if existing.status == "final", do: "review", else: existing.status

      existing
      |> LocalizedText.source_update_changeset(%{
        "source_text" => attrs["source_text"],
        "source_text_hash" => new_hash,
        "word_count" => attrs["word_count"],
        "speaker_sheet_id" => attrs["speaker_sheet_id"],
        "status" => new_status
      })
      |> Repo.update()
    else
      # Hash unchanged — no update needed (but update speaker if changed)
      if attrs["speaker_sheet_id"] != existing.speaker_sheet_id do
        existing
        |> LocalizedText.source_update_changeset(%{
          "speaker_sheet_id" => attrs["speaker_sheet_id"]
        })
        |> Repo.update()
      else
        {:ok, existing}
      end
    end
  end

  defp maybe_filter_locale(query, nil), do: query

  defp maybe_filter_locale(query, locale_code) do
    where(query, [t], t.locale_code == ^locale_code)
  end

  defp maybe_filter_status(query, nil), do: query

  defp maybe_filter_status(query, status) do
    where(query, [t], t.status == ^status)
  end

  defp maybe_filter_source_type(query, nil), do: query

  defp maybe_filter_source_type(query, source_type) do
    where(query, [t], t.source_type == ^source_type)
  end

  defp maybe_filter_speaker(query, nil), do: query

  defp maybe_filter_speaker(query, speaker_sheet_id) do
    where(query, [t], t.speaker_sheet_id == ^speaker_sheet_id)
  end

  defp maybe_search(query, nil), do: query
  defp maybe_search(query, ""), do: query

  defp maybe_search(query, search) do
    sanitized = Storyarn.Shared.SearchHelpers.sanitize_like_query(search)
    pattern = "%#{sanitized}%"

    where(
      query,
      [t],
      ilike(t.source_text, ^pattern) or ilike(t.translated_text, ^pattern)
    )
  end

  defp maybe_paginate(query, nil, _offset), do: query

  defp maybe_paginate(query, limit, offset) do
    query
    |> limit(^limit)
    |> offset(^(offset || 0))
  end

  # =============================================================================
  # Export / Import helpers
  # =============================================================================

  @doc """
  Lists localized texts for export, filtered by locale codes.
  """
  def list_texts_for_export(project_id, locale_codes) do
    from(lt in LocalizedText,
      where: lt.project_id == ^project_id and lt.locale_code in ^locale_codes,
      order_by: [
        asc: lt.source_type,
        asc: lt.source_id,
        asc: lt.source_field,
        asc: lt.locale_code
      ]
    )
    |> Repo.all()
  end

  @doc """
  Lists target (non-source) locale codes for a project.
  Used by the export Validator.
  """
  def list_target_locale_codes(project_id) do
    alias Storyarn.Localization.ProjectLanguage

    from(l in ProjectLanguage,
      where: l.project_id == ^project_id and l.is_source == false,
      select: l.locale_code
    )
    |> Repo.all()
  end

  @doc """
  Counts distinct source entries (unique source_type + source_id + source_field) for a project.
  Used by the export Validator.
  """
  def count_distinct_source_entries(project_id) do
    from(lt in LocalizedText,
      where: lt.project_id == ^project_id,
      select: fragment("count(DISTINCT (?, ?, ?))", lt.source_type, lt.source_id, lt.source_field)
    )
    |> Repo.one() || 0
  end

  @doc """
  Counts pending/draft texts grouped by locale for specified languages.
  Returns a map of `%{locale_code => count}`.
  """
  def count_pending_by_locale(project_id, languages) do
    from(lt in LocalizedText,
      where:
        lt.project_id == ^project_id and
          lt.locale_code in ^languages and
          lt.status in ["pending", "draft"],
      group_by: lt.locale_code,
      select: {lt.locale_code, count(lt.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Batch-upserts localized texts for a project using insert_all with on_conflict.

  Each entry in `entries` should be a map with string keys:
  `source_type`, `source_id`, `source_field`, `source_text`, `source_text_hash`,
  `locale_code`, `word_count`, and optionally `speaker_sheet_id`.

  On conflict (same source_type/source_id/source_field/locale_code):
  - Updates source_text, source_text_hash, word_count, speaker_sheet_id
  - Downgrades status from "final" to "review" if source_text_hash changed

  Returns the total number of entries processed.
  """
  @spec batch_upsert_texts(integer(), [map()]) :: non_neg_integer()
  def batch_upsert_texts(_project_id, []), do: 0

  def batch_upsert_texts(project_id, entries) when is_list(entries) do
    now = Storyarn.Shared.TimeHelpers.now()

    rows =
      Enum.map(entries, fn attrs ->
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
          status: "pending",
          vo_status: "none",
          machine_translated: false,
          inserted_at: now,
          updated_at: now
        }
      end)

    rows
    |> Enum.chunk_every(500)
    |> Enum.each(&do_batch_upsert_chunk/1)

    length(rows)
  end

  @upsert_sql """
  INSERT INTO localized_texts (
    project_id, source_type, source_id, source_field, source_text,
    source_text_hash, locale_code, word_count, speaker_sheet_id,
    status, vo_status, machine_translated, inserted_at, updated_at
  )
  SELECT * FROM unnest(
    $1::bigint[], $2::text[], $3::bigint[], $4::text[], $5::text[],
    $6::text[], $7::text[], $8::int[], $9::bigint[], $10::text[],
    $11::text[], $12::boolean[], $13::timestamp[], $14::timestamp[]
  )
  ON CONFLICT (source_type, source_id, source_field, locale_code)
  DO UPDATE SET
    source_text = EXCLUDED.source_text,
    source_text_hash = EXCLUDED.source_text_hash,
    word_count = EXCLUDED.word_count,
    speaker_sheet_id = EXCLUDED.speaker_sheet_id,
    status = CASE
      WHEN localized_texts.source_text_hash IS DISTINCT FROM EXCLUDED.source_text_hash
        AND localized_texts.status = 'final'
      THEN 'review'
      ELSE localized_texts.status
    END,
    updated_at = EXCLUDED.updated_at
  WHERE localized_texts.source_text_hash IS DISTINCT FROM EXCLUDED.source_text_hash
    OR localized_texts.speaker_sheet_id IS DISTINCT FROM EXCLUDED.speaker_sheet_id
  """

  defp do_batch_upsert_chunk(chunk) do
    {project_ids, source_types, source_ids, source_fields, source_texts, source_text_hashes,
     locale_codes, word_counts, speaker_sheet_ids, statuses, vo_statuses, machine_translateds,
     inserted_ats, updated_ats} =
      Enum.reduce(chunk, {[], [], [], [], [], [], [], [], [], [], [], [], [], []}, fn row, acc ->
        {p, st, si, sf, stxt, sth, lc, wc, ssi, s, vs, mt, ia, ua} = acc

        {
          [row.project_id | p],
          [row.source_type | st],
          [row.source_id | si],
          [row.source_field | sf],
          [row.source_text | stxt],
          [row.source_text_hash | sth],
          [row.locale_code | lc],
          [row.word_count | wc],
          [row.speaker_sheet_id | ssi],
          [row.status | s],
          [row.vo_status | vs],
          [row.machine_translated | mt],
          [row.inserted_at | ia],
          [row.updated_at | ua]
        }
      end)

    Repo.query!(@upsert_sql, [
      Enum.reverse(project_ids),
      Enum.reverse(source_types),
      Enum.reverse(source_ids),
      Enum.reverse(source_fields),
      Enum.reverse(source_texts),
      Enum.reverse(source_text_hashes),
      Enum.reverse(locale_codes),
      Enum.reverse(word_counts),
      Enum.reverse(speaker_sheet_ids),
      Enum.reverse(statuses),
      Enum.reverse(vo_statuses),
      Enum.reverse(machine_translateds),
      Enum.reverse(inserted_ats),
      Enum.reverse(updated_ats)
    ])
  end

  @doc """
  Bulk-inserts localized texts from a list of attr maps.
  Uses on_conflict: :nothing for deduplication.
  """
  def bulk_import_texts(attrs_list) do
    attrs_list
    |> Enum.chunk_every(500)
    |> Enum.each(fn chunk ->
      Repo.insert_all(LocalizedText, chunk, on_conflict: :nothing)
    end)
  end
end
