defmodule Storyarn.Repo.Migrations.AddChecksumToEntityVersions do
  use Ecto.Migration

  def change do
    alter table(:entity_versions) do
      # Existing closed-beta versions remain nullable at rest, but restore and
      # comparison reject them because their object bytes are not bound to the
      # database record.
      add :checksum, :string
    end

    create constraint(:entity_versions, :entity_versions_checksum_format,
             check: "checksum IS NULL OR checksum ~ '^[0-9a-f]{64}$'"
           )
  end
end
