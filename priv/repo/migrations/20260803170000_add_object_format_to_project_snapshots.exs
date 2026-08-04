defmodule Storyarn.Repo.Migrations.AddObjectFormatToProjectSnapshots do
  use Ecto.Migration

  def change do
    alter table(:project_snapshots) do
      add :format_version, :integer
      add :object_prefix, :string, size: 500
      add :manifest_storage_key, :string, size: 520
      add :manifest_size_bytes, :bigint
      add :manifest_checksum, :string
      add :total_size_bytes, :bigint
      add :object_count, :integer
      add :asset_count, :integer
      add :blob_count, :integer
    end

    create unique_index(:project_snapshots, [:object_prefix], where: "object_prefix IS NOT NULL")

    create unique_index(:project_snapshots, [:manifest_storage_key],
             where: "manifest_storage_key IS NOT NULL"
           )

    create constraint(:project_snapshots, :project_snapshots_object_format_version,
             check: "format_version IS NULL OR format_version = 1"
           )

    create constraint(:project_snapshots, :project_snapshots_manifest_checksum_format,
             check: "manifest_checksum IS NULL OR manifest_checksum ~ '^[0-9a-f]{64}$'"
           )

    create constraint(:project_snapshots, :project_snapshots_object_counts,
             check: """
             (object_count IS NULL AND asset_count IS NULL AND blob_count IS NULL) OR
             (object_count IS NOT NULL AND asset_count IS NOT NULL AND blob_count IS NOT NULL AND
              object_count = blob_count + 2 AND blob_count >= 0 AND asset_count >= blob_count)
             """
           )

    create constraint(:project_snapshots, :project_snapshots_object_sizes,
             check: """
             (manifest_size_bytes IS NULL AND total_size_bytes IS NULL) OR
             (manifest_size_bytes IS NOT NULL AND total_size_bytes IS NOT NULL AND
              manifest_size_bytes > 0 AND total_size_bytes >= manifest_size_bytes)
             """
           )
  end
end
