defmodule Storyarn.Repo.Migrations.CreatePages do
  use Ecto.Migration

  def change do
    create table(:pages) do
      add :name, :string, null: false
      add :position, :integer, default: 0
      add :description, :text
      add :shortcut, :string
      add :color, :string
      add :deleted_at, :utc_datetime
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :parent_id, references(:pages, on_delete: :nilify_all)
      add :avatar_asset_id, references(:assets, on_delete: :nilify_all)
      add :banner_asset_id, references(:assets, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:pages, [:project_id])
    create index(:pages, [:parent_id])
    create index(:pages, [:project_id, :parent_id, :position])
    create index(:pages, [:avatar_asset_id])
    create index(:pages, [:banner_asset_id])
    create index(:pages, [:deleted_at])

    create index(:pages, [:project_id, :deleted_at],
             where: "deleted_at IS NOT NULL",
             name: :pages_trash_index
           )

    create unique_index(:pages, [:project_id, :shortcut],
             where: "shortcut IS NOT NULL AND deleted_at IS NULL",
             name: :pages_project_shortcut_unique
           )

    create table(:blocks) do
      add :type, :string, null: false
      add :position, :integer, default: 0
      add :config, :map, default: %{}
      add :value, :map, default: %{}
      add :is_constant, :boolean, default: false, null: false
      add :variable_name, :string
      add :deleted_at, :utc_datetime
      add :page_id, references(:pages, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:blocks, [:page_id])
    create index(:blocks, [:page_id, :position])
    create index(:blocks, [:deleted_at])

    create unique_index(:blocks, [:page_id, :variable_name],
             where: "variable_name IS NOT NULL AND deleted_at IS NULL",
             name: :blocks_page_variable_unique
           )
  end
end
