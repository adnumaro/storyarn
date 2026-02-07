defmodule Storyarn.Repo.Migrations.CreateVariableReferences do
  use Ecto.Migration

  def change do
    create table(:variable_references) do
      add :flow_node_id, references(:flow_nodes, on_delete: :delete_all), null: false
      add :block_id, references(:blocks, on_delete: :delete_all), null: false
      add :kind, :string, null: false
      add :source_page, :string, null: false
      add :source_variable, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:variable_references, [:block_id, :kind])
    create index(:variable_references, [:flow_node_id])
    create unique_index(:variable_references, [:flow_node_id, :block_id, :kind])
  end
end
