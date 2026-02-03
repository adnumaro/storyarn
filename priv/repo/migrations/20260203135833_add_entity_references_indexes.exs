defmodule Storyarn.Repo.Migrations.AddEntityReferencesIndexes do
  use Ecto.Migration

  def up do
    # Add composite index for efficient source-based queries (deletion, updates)
    create_if_not_exists index(:entity_references, [:source_type, :source_id])

    # Add index for faster backlink queries (grouped by target and filtered by source type)
    create_if_not_exists index(:entity_references, [:target_type, :target_id, :source_type])
  end

  def down do
    drop_if_exists index(:entity_references, [:source_type, :source_id])
    drop_if_exists index(:entity_references, [:target_type, :target_id, :source_type])
  end
end
