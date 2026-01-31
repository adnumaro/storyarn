defmodule Storyarn.Repo.Migrations.RefactorToPagesAndBlocks do
  use Ecto.Migration

  def up do
    # Step 1: Drop foreign key constraint to entity_templates
    drop constraint(:entities, "entities_template_id_fkey")

    # Step 2: Drop indexes that reference template_id
    drop_if_exists index(:entities, [:template_id])
    drop_if_exists index(:entities, [:template_id, :parent_id, :position])

    # Step 3: Remove columns we don't need
    alter table(:entities) do
      remove :template_id
      remove :technical_name
      remove :color
      remove :data
      remove :description
    end

    # Step 4: Add icon column and rename display_name to name
    alter table(:entities) do
      add :icon, :string, default: "page"
    end

    rename table(:entities), :display_name, to: :name

    # Step 5: Drop unique index on technical_name
    drop_if_exists unique_index(:entities, [:project_id, :technical_name])

    # Step 6: Rename table from entities to pages
    rename table(:entities), to: table(:pages)

    # Step 7: Update self-referencing foreign key to point to pages
    # First drop the old constraint
    drop constraint(:pages, "entities_parent_id_fkey")

    # Then recreate with correct table name
    alter table(:pages) do
      modify :parent_id, references(:pages, on_delete: :nilify_all)
    end

    # Step 8: Recreate index for parent lookups (rename from entities to pages)
    drop_if_exists index(:pages, [:parent_id], name: "entities_parent_id_index")
    create index(:pages, [:parent_id])
    create index(:pages, [:project_id, :parent_id, :position])

    # Step 9: Create blocks table
    create table(:blocks) do
      add :type, :string, null: false
      add :position, :integer, default: 0

      # Configuration: label, placeholder, options (for selects)
      add :config, :map, default: %{}

      # Value: content stored here
      add :value, :map, default: %{}

      add :page_id, references(:pages, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:blocks, [:page_id])
    create index(:blocks, [:page_id, :position])

    # Step 10: Drop entity_templates table
    drop table(:entity_templates)
  end

  def down do
    # Recreate entity_templates table
    create table(:entity_templates) do
      add :name, :string, null: false
      add :type, :string, null: false
      add :description, :text
      add :icon, :string
      add :color, :string
      add :schema, :map, default: []
      add :is_default, :boolean, default: false
      add :project_id, references(:projects, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:entity_templates, [:project_id, :name])
    create index(:entity_templates, [:project_id])
    create index(:entity_templates, [:project_id, :type])

    # Drop blocks table
    drop table(:blocks)

    # Rename pages back to entities
    rename table(:pages), to: table(:entities)

    # Rename name back to display_name
    rename table(:entities), :name, to: :display_name

    # Re-add removed columns
    alter table(:entities) do
      remove :icon
      add :technical_name, :string
      add :color, :string
      add :data, :map, default: %{}
      add :description, :text
      add :template_id, references(:entity_templates, on_delete: :restrict)
    end

    create index(:entities, [:template_id])
    create unique_index(:entities, [:project_id, :technical_name])
  end
end
