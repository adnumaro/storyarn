defmodule Storyarn.Repo.Migrations.AddTreeStructureToFlows do
  use Ecto.Migration

  def change do
    alter table(:flows) do
      add :parent_id, references(:flows, on_delete: :nilify_all)
      add :position, :integer, default: 0
      add :is_folder, :boolean, default: false, null: false
      add :deleted_at, :utc_datetime
    end

    create index(:flows, [:parent_id])
    create index(:flows, [:project_id, :parent_id, :position])
    create index(:flows, [:deleted_at])

    # Drop the old shortcut unique index and recreate with deleted_at filter
    drop_if_exists unique_index(:flows, [:project_id, :shortcut],
                     name: :flows_project_shortcut_unique
                   )

    create unique_index(:flows, [:project_id, :shortcut],
             where: "shortcut IS NOT NULL AND deleted_at IS NULL",
             name: :flows_project_shortcut_unique
           )
  end
end
