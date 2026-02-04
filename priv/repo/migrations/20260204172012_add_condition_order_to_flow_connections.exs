defmodule Storyarn.Repo.Migrations.AddConditionOrderToFlowConnections do
  use Ecto.Migration

  def change do
    alter table(:flow_connections) do
      add :condition_order, :integer, default: 0
    end

    # Index for efficient ordering when evaluating connections
    create index(:flow_connections, [:source_node_id, :condition_order])
  end
end
