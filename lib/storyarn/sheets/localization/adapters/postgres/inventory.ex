defmodule Storyarn.Sheets.Localization.Adapters.Postgres.Inventory do
  @moduledoc """
  PostgreSQL adapter for localization inventory upserts and advisory locks.

  SQL-specific batching, array parameter layout and lock primitives stay here;
  the projection command owns when and why reconciliation happens.
  """

  alias Storyarn.Repo

  @upsert_sql """
  INSERT INTO localized_texts (
    project_id, source_type, source_id, source_field, source_text,
    source_text_hash, locale_code, word_count, speaker_sheet_id,
    content_role, vo_eligible, status, vo_status, machine_translated, inserted_at, updated_at
  )
  SELECT * FROM unnest(
    $1::bigint[], $2::text[], $3::bigint[], $4::text[], $5::text[],
    $6::text[], $7::text[], $8::int[], $9::bigint[], $10::text[],
    $11::boolean[], $12::text[], $13::text[], $14::boolean[], $15::timestamp[], $16::timestamp[]
  )
  ON CONFLICT (source_type, source_id, source_field, locale_code)
  DO UPDATE SET
    source_text = EXCLUDED.source_text,
    source_text_hash = EXCLUDED.source_text_hash,
    word_count = EXCLUDED.word_count,
    speaker_sheet_id = EXCLUDED.speaker_sheet_id,
    content_role = EXCLUDED.content_role,
    vo_eligible = EXCLUDED.vo_eligible,
    vo_status = CASE
      WHEN localized_texts.source_text_hash IS DISTINCT FROM EXCLUDED.source_text_hash
        AND EXCLUDED.vo_eligible = true
        AND (localized_texts.vo_status IN ('recorded', 'approved') OR localized_texts.vo_asset_id IS NOT NULL)
      THEN 'needed'
      ELSE localized_texts.vo_status
    END,
    archived_at = NULL,
    archive_reason = NULL,
    status = CASE
      WHEN localized_texts.source_text_hash IS DISTINCT FROM EXCLUDED.source_text_hash
        AND NULLIF(BTRIM(localized_texts.translated_text), '') IS NULL
      THEN 'pending'
      WHEN localized_texts.source_text_hash IS DISTINCT FROM EXCLUDED.source_text_hash
      THEN 'review'
      ELSE localized_texts.status
    END,
    lock_version = localized_texts.lock_version + 1,
    updated_at = EXCLUDED.updated_at
  WHERE localized_texts.source_text_hash IS DISTINCT FROM EXCLUDED.source_text_hash
    OR localized_texts.speaker_sheet_id IS DISTINCT FROM EXCLUDED.speaker_sheet_id
    OR localized_texts.content_role IS DISTINCT FROM EXCLUDED.content_role
    OR localized_texts.vo_eligible IS DISTINCT FROM EXCLUDED.vo_eligible
    OR localized_texts.archived_at IS NOT NULL
  """

  @spec upsert_localized_texts!([map()], DateTime.t()) :: Postgrex.Result.t()
  def upsert_localized_texts!(entries, now) do
    values =
      entries
      |> Enum.reduce(empty_columns(), &append_entry(&1, now, &2))
      |> Tuple.to_list()
      |> Enum.map(&Enum.reverse/1)

    Repo.query!(@upsert_sql, values)
  end

  @spec lock_exclusive!(String.t(), integer()) :: Postgrex.Result.t()
  def lock_exclusive!(namespace, id) do
    Repo.query!(
      "SELECT pg_advisory_xact_lock(hashtextextended(concat($1::text, ':', $2::text), 0))",
      [namespace, to_string(id)]
    )
  end

  @spec lock_shared!(String.t(), integer()) :: Postgrex.Result.t()
  def lock_shared!(namespace, id) do
    Repo.query!(
      "SELECT pg_advisory_xact_lock_shared(hashtextextended(concat($1::text, ':', $2::text), 0))",
      [namespace, to_string(id)]
    )
  end

  defp empty_columns, do: {[], [], [], [], [], [], [], [], [], [], [], [], [], [], [], []}

  defp append_entry(entry, now, columns) do
    {project_ids, source_types, source_ids, source_fields, source_texts, source_hashes, locales, word_counts, speakers,
     roles, vo_eligibles, statuses, vo_statuses, machine_translated, inserted_ats, updated_ats} = columns

    {
      [entry.project_id | project_ids],
      [entry.source_type | source_types],
      [entry.source_id | source_ids],
      [entry.source_field | source_fields],
      [entry.source_text | source_texts],
      [entry.source_text_hash | source_hashes],
      [entry.locale_code | locales],
      [entry.word_count | word_counts],
      [entry.speaker_sheet_id | speakers],
      [entry.content_role | roles],
      [entry.vo_eligible | vo_eligibles],
      ["pending" | statuses],
      ["none" | vo_statuses],
      [false | machine_translated],
      [now | inserted_ats],
      [now | updated_ats]
    }
  end
end
