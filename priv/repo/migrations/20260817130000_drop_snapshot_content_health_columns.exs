defmodule Storyarn.Repo.Migrations.DropSnapshotContentHealthColumns do
  @moduledoc """
  Removes the inert snapshot health columns left by the deployed health cleanup.

  Snapshot writers must be stopped while this migration and the matching code
  deploy are applied.
  """

  use Ecto.Migration

  def up do
    execute("ALTER TABLE project_snapshots DROP COLUMN IF EXISTS content_health")
    execute("ALTER TABLE project_snapshot_captures DROP COLUMN IF EXISTS content_health")
  end

  def down do
    raise Ecto.MigrationError,
          "DropSnapshotContentHealthColumns is irreversible because discarded health data cannot be reconstructed"
  end
end
