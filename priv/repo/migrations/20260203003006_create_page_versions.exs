defmodule Storyarn.Repo.Migrations.CreatePageVersions do
  use Ecto.Migration

  def change do
    create table(:page_versions) do
      add :page_id, references(:pages, on_delete: :delete_all), null: false
      add :version_number, :integer, null: false
      add :snapshot, :map, null: false
      add :changed_by_id, references(:users, on_delete: :nilify_all)
      add :change_summary, :string

      timestamps(updated_at: false)
    end

    create index(:page_versions, [:page_id, :version_number])
    create index(:page_versions, [:page_id, :inserted_at])

    create unique_index(:page_versions, [:page_id, :version_number],
             name: :page_versions_page_version_unique
           )
  end
end
