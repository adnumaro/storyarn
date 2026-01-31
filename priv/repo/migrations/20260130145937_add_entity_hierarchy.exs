defmodule Storyarn.Repo.Migrations.AddEntityHierarchy do
  use Ecto.Migration

  def change do
    alter table(:entities) do
      # Self-referencing foreign key for parent-child hierarchy
      add :parent_id, references(:entities, on_delete: :nilify_all)

      # Position for ordering siblings at the same level
      add :position, :integer, default: 0
    end

    # Index for efficient parent lookups
    create index(:entities, [:parent_id])

    # Composite index for efficient tree queries (list children of a parent, ordered)
    create index(:entities, [:template_id, :parent_id, :position])
  end
end
