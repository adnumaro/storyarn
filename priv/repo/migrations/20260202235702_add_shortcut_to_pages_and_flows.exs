defmodule Storyarn.Repo.Migrations.AddShortcutToPagesAndFlows do
  use Ecto.Migration

  def change do
    alter table(:pages) do
      add :shortcut, :string
    end

    alter table(:flows) do
      add :shortcut, :string
    end

    # Unique index for pages shortcuts within a project (only non-null values)
    create unique_index(:pages, [:project_id, :shortcut],
             where: "shortcut IS NOT NULL AND deleted_at IS NULL",
             name: :pages_project_shortcut_unique
           )

    # Unique index for flows shortcuts within a project (only non-null values)
    create unique_index(:flows, [:project_id, :shortcut],
             where: "shortcut IS NOT NULL",
             name: :flows_project_shortcut_unique
           )
  end
end
