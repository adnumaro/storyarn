defmodule Storyarn.Repo.Migrations.CreateSheetVersions do
  use Ecto.Migration

  def change do
    create table(:sheet_versions) do
      add :sheet_id, references(:sheets, on_delete: :delete_all), null: false
      add :version_number, :integer, null: false
      add :snapshot, :map, null: false
      add :changed_by_id, references(:users, on_delete: :nilify_all)
      add :change_summary, :string
      add :title, :string
      add :description, :text

      timestamps(updated_at: false)
    end

    create index(:sheet_versions, [:sheet_id, :version_number])
    create index(:sheet_versions, [:sheet_id, :inserted_at])

    create unique_index(:sheet_versions, [:sheet_id, :version_number],
             name: :sheet_versions_sheet_version_unique
           )

    # Add current_version_id to sheets (back-reference)
    alter table(:sheets) do
      add :current_version_id, references(:sheet_versions, on_delete: :nilify_all)
    end

    create index(:sheets, [:current_version_id])
  end
end
