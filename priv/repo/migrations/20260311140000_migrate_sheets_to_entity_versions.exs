defmodule Storyarn.Repo.Migrations.MigrateSheetsToEntityVersions do
  use Ecto.Migration

  def up do
    # 1. Drop the old FK constraint pointing to sheet_versions
    execute "ALTER TABLE sheets DROP CONSTRAINT sheets_current_version_id_fkey"

    # 2. Clear all current_version_id values (old IDs are meaningless for the new table)
    execute "UPDATE sheets SET current_version_id = NULL"

    # 3. Add new FK pointing to entity_versions
    execute """
    ALTER TABLE sheets
    ADD CONSTRAINT sheets_current_version_id_fkey
    FOREIGN KEY (current_version_id) REFERENCES entity_versions(id)
    ON DELETE SET NULL
    """

    # 4. Drop the old sheet_versions table
    drop table(:sheet_versions)
  end

  def down do
    # Recreate sheet_versions table
    create table(:sheet_versions) do
      add :version_number, :integer, null: false
      add :title, :string, size: 255
      add :description, :text
      add :snapshot, :map, null: false
      add :change_summary, :text
      add :sheet_id, references(:sheets, on_delete: :delete_all), null: false
      add :changed_by_id, references(:users, on_delete: :nilify_all)

      timestamps(updated_at: false)
    end

    create index(:sheet_versions, [:sheet_id])

    create unique_index(:sheet_versions, [:sheet_id, :version_number],
             name: :sheet_versions_sheet_version_unique
           )

    # Remove new FK and add old one back
    execute "ALTER TABLE sheets DROP CONSTRAINT sheets_current_version_id_fkey"
    execute "UPDATE sheets SET current_version_id = NULL"

    execute """
    ALTER TABLE sheets
    ADD CONSTRAINT sheets_current_version_id_fkey
    FOREIGN KEY (current_version_id) REFERENCES sheet_versions(id)
    ON DELETE SET NULL
    """
  end
end
