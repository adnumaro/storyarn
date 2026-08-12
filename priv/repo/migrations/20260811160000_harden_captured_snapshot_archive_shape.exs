defmodule Storyarn.Repo.Migrations.HardenCapturedSnapshotArchiveShape do
  use Ecto.Migration

  def up do
    replace_archive_format_constraint(hardened_archive_format_check())
  end

  def down do
    replace_archive_format_constraint(previous_archive_format_check())
  end

  defp replace_archive_format_constraint(check) do
    drop constraint(:project_snapshots, :project_snapshots_archive_format)

    create constraint(:project_snapshots, :project_snapshots_archive_format, check: check)
  end

  defp hardened_archive_format_check do
    """
    (format_version = 1 AND project_size_bytes IS NOT NULL AND project_size_bytes > 0 AND
     capture_digest IS NOT NULL AND capture_digest ~ '^[0-9a-f]{64}$' AND captured_at IS NOT NULL AND
     archive_storage_key IS NULL AND archive_size_bytes IS NULL AND archive_checksum IS NULL) OR
    (format_version = 2 AND mode = 'full' AND project_storage_key IS NULL AND
     archive_storage_key IS NOT NULL AND
     ((lifecycle_state IN ('pending', 'failed', 'cancelled', 'deleting') AND capture_digest IS NULL AND
       project_size_bytes IS NULL AND project_checksum IS NULL AND captured_at IS NULL AND
       archive_size_bytes IS NULL AND archive_checksum IS NULL AND
       manifest_size_bytes IS NULL AND manifest_checksum IS NULL AND total_size_bytes IS NULL AND
       object_count IS NULL AND asset_count IS NULL AND blob_count IS NULL) OR
      (project_size_bytes IS NOT NULL AND project_size_bytes > 0 AND
       project_checksum IS NOT NULL AND project_checksum ~ '^[0-9a-f]{64}$' AND
       capture_digest IS NOT NULL AND capture_digest ~ '^[0-9a-f]{64}$' AND captured_at IS NOT NULL AND
       archive_size_bytes IS NOT NULL AND archive_size_bytes > 0 AND
       (archive_checksum IS NULL OR archive_checksum ~ '^[0-9a-f]{64}$') AND
       manifest_size_bytes IS NOT NULL AND manifest_size_bytes > 0 AND
       manifest_checksum IS NOT NULL AND manifest_checksum ~ '^[0-9a-f]{64}$' AND
       total_size_bytes = archive_size_bytes + manifest_size_bytes AND
       object_count = 2 AND asset_count IS NOT NULL AND blob_count IS NOT NULL AND
       progress_total_bytes = total_size_bytes)))
    """
  end

  defp previous_archive_format_check do
    """
    (format_version = 1 AND project_size_bytes IS NOT NULL AND project_size_bytes > 0 AND
     capture_digest IS NOT NULL AND capture_digest ~ '^[0-9a-f]{64}$' AND captured_at IS NOT NULL AND
     archive_storage_key IS NULL AND archive_size_bytes IS NULL AND archive_checksum IS NULL) OR
    (format_version = 2 AND mode = 'full' AND project_storage_key IS NULL AND
     archive_storage_key IS NOT NULL AND
     ((lifecycle_state IN ('pending', 'failed', 'cancelled', 'deleting') AND capture_digest IS NULL AND
       project_size_bytes IS NULL AND captured_at IS NULL AND archive_size_bytes IS NULL AND
       archive_checksum IS NULL) OR
      (project_size_bytes IS NOT NULL AND project_size_bytes > 0 AND
       capture_digest IS NOT NULL AND capture_digest ~ '^[0-9a-f]{64}$' AND captured_at IS NOT NULL AND
       archive_size_bytes IS NOT NULL AND archive_size_bytes > 0 AND
       (archive_checksum IS NULL OR archive_checksum ~ '^[0-9a-f]{64}$'))))
    """
  end
end
