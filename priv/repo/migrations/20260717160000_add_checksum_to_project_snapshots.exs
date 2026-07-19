defmodule Storyarn.Repo.Migrations.AddChecksumToProjectSnapshots do
  use Ecto.Migration

  def change do
    alter table(:project_snapshots) do
      # Existing beta snapshots may remain null at rest, but recovery rejects
      # them because their storage bytes are not cryptographically bound.
      add :checksum, :string
    end

    create constraint(:project_snapshots, :project_snapshots_checksum_format,
             check: "checksum IS NULL OR checksum ~ '^[0-9a-f]{64}$'"
           )
  end
end
