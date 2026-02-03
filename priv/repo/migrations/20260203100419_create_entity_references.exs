defmodule Storyarn.Repo.Migrations.CreateEntityReferences do
  use Ecto.Migration

  def change do
    create table(:entity_references) do
      add :source_type, :string, null: false
      add :source_id, :bigint, null: false
      add :target_type, :string, null: false
      add :target_id, :bigint, null: false
      add :context, :string

      timestamps()
    end

    create index(:entity_references, [:target_type, :target_id])
    create index(:entity_references, [:source_type, :source_id])

    create unique_index(
             :entity_references,
             [:source_type, :source_id, :target_type, :target_id, :context],
             name: :entity_references_unique
           )
  end
end
