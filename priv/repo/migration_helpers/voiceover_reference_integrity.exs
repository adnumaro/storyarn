defmodule Storyarn.Repo.Migrations.VoiceoverReferenceIntegrity do
  @moduledoc false

  def lock_sql do
    [
      """
      SELECT id
      FROM projects
      ORDER BY id
      FOR UPDATE
      """,
      """
      LOCK TABLE assets, sheets
      IN SHARE MODE
      """,
      """
      LOCK TABLE localized_texts
      IN ACCESS EXCLUSIVE MODE
      """
    ]
  end

  def repair_sql do
    [repair_voiceover_assets_sql(), repair_speaker_sheets_sql()]
  end

  def trigger_function_sql do
    """
    CREATE OR REPLACE FUNCTION normalize_localized_voiceover_asset_removal()
    RETURNS trigger AS $$
    BEGIN
      IF OLD.vo_asset_id IS NOT NULL
         AND NEW.vo_asset_id IS NULL
         AND NEW.vo_status IN ('recorded', 'approved') THEN
        NEW.vo_status := CASE WHEN NEW.vo_eligible THEN 'needed' ELSE 'none' END;
        NEW.lock_version := COALESCE(NEW.lock_version, 0) + 1;
        NEW.updated_at := CURRENT_TIMESTAMP;
      END IF;

      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """
  end

  def trigger_sql do
    [
      """
      DROP TRIGGER IF EXISTS normalize_localized_voiceover_asset_removal
        ON localized_texts
      """,
      """
      CREATE TRIGGER normalize_localized_voiceover_asset_removal
      BEFORE UPDATE OF vo_asset_id ON localized_texts
      FOR EACH ROW
      EXECUTE FUNCTION normalize_localized_voiceover_asset_removal()
      """
    ]
  end

  def drop_trigger_sql do
    """
    DROP TRIGGER IF EXISTS normalize_localized_voiceover_asset_removal
      ON localized_texts;
    """
  end

  def drop_trigger_function_sql do
    """
    DROP FUNCTION IF EXISTS normalize_localized_voiceover_asset_removal();
    """
  end

  defp repair_voiceover_assets_sql do
    """
    UPDATE localized_texts AS localized_text
    SET vo_asset_id = NULL,
        vo_status = CASE
          WHEN localized_text.vo_status IN ('recorded', 'approved')
            THEN CASE WHEN localized_text.vo_eligible THEN 'needed' ELSE 'none' END
          ELSE localized_text.vo_status
        END,
        lock_version = localized_text.lock_version + 1,
        updated_at = CURRENT_TIMESTAMP
    WHERE (
      localized_text.vo_asset_id IS NULL
      AND localized_text.vo_status IN ('recorded', 'approved')
    ) OR (
      localized_text.vo_asset_id IS NOT NULL
      AND NOT EXISTS (
        SELECT 1
        FROM assets AS asset
        WHERE asset.id = localized_text.vo_asset_id
          AND asset.project_id = localized_text.project_id
          AND asset.content_type LIKE 'audio/%'
      )
    )
    """
  end

  defp repair_speaker_sheets_sql do
    """
    UPDATE localized_texts AS localized_text
    SET speaker_sheet_id = NULL,
        lock_version = localized_text.lock_version + 1,
        updated_at = CURRENT_TIMESTAMP
    WHERE localized_text.speaker_sheet_id IS NOT NULL
      AND NOT EXISTS (
        SELECT 1
        FROM sheets AS speaker_sheet
        WHERE speaker_sheet.id = localized_text.speaker_sheet_id
          AND speaker_sheet.project_id = localized_text.project_id
          AND speaker_sheet.deleted_at IS NULL
      )
    """
  end
end
