defmodule Storyarn.Localization.Texts.Adapters.Upserts.Postgres do
  @moduledoc false

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

  @spec upsert_chunk([map()]) :: Postgrex.Result.t()
  def upsert_chunk(chunk) do
    {project_ids, source_types, source_ids, source_fields, source_texts, source_text_hashes, locale_codes, word_counts,
     speaker_sheet_ids, content_roles, vo_eligibles, statuses, vo_statuses, machine_translateds, inserted_ats,
     updated_ats} =
      Enum.reduce(chunk, {[], [], [], [], [], [], [], [], [], [], [], [], [], [], [], []}, fn row, acc ->
        {p, st, si, sf, stxt, sth, lc, wc, ssi, cr, ve, s, vs, mt, ia, ua} = acc

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
          [row.content_role | cr],
          [row.vo_eligible | ve],
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
      Enum.reverse(content_roles),
      Enum.reverse(vo_eligibles),
      Enum.reverse(statuses),
      Enum.reverse(vo_statuses),
      Enum.reverse(machine_translateds),
      Enum.reverse(inserted_ats),
      Enum.reverse(updated_ats)
    ])
  end
end
