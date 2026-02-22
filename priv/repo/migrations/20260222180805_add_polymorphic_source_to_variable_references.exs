defmodule Storyarn.Repo.Migrations.AddPolymorphicSourceToVariableReferences do
  use Ecto.Migration

  def up do
    # Add polymorphic source columns
    alter table(:variable_references) do
      add :source_type, :string, null: false, default: "flow_node"
      add :source_id, :bigint
    end

    # Backfill source_id from flow_node_id
    execute "UPDATE variable_references SET source_id = flow_node_id"

    # Make source_id NOT NULL after backfill
    alter table(:variable_references) do
      modify :source_id, :bigint, null: false
    end

    # Make flow_node_id nullable (keep FK for cascade deletes on existing flow node refs)
    alter table(:variable_references) do
      modify :flow_node_id, :bigint, null: true
    end

    # Drop old unique index and create new polymorphic one
    drop_if_exists unique_index(:variable_references, [:flow_node_id, :block_id, :kind])

    create unique_index(
             :variable_references,
             [:source_type, :source_id, :block_id, :kind, :source_variable],
             name: :variable_references_source_block_kind_var
           )

    create index(:variable_references, [:source_type, :source_id])
  end

  def down do
    drop_if_exists index(:variable_references, [:source_type, :source_id])

    drop_if_exists unique_index(
                     :variable_references,
                     [:source_type, :source_id, :block_id, :kind, :source_variable],
                     name: :variable_references_source_block_kind_var
                   )

    # Restore flow_node_id NOT NULL
    # First delete any map_zone rows that can't have flow_node_id
    execute "DELETE FROM variable_references WHERE source_type != 'flow_node'"

    alter table(:variable_references) do
      modify :flow_node_id, :bigint, null: false
    end

    create unique_index(:variable_references, [:flow_node_id, :block_id, :kind])

    alter table(:variable_references) do
      remove :source_type
      remove :source_id
    end
  end
end
