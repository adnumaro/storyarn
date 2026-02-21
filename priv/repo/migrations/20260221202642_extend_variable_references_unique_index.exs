defmodule Storyarn.Repo.Migrations.ExtendVariableReferencesUniqueIndex do
  use Ecto.Migration

  def change do
    drop unique_index(:variable_references, [:flow_node_id, :block_id, :kind])
    create unique_index(:variable_references, [:flow_node_id, :block_id, :kind, :source_variable])
  end
end
