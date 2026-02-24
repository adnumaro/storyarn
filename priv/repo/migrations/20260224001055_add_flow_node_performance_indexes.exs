defmodule Storyarn.Repo.Migrations.AddFlowNodePerformanceIndexes do
  use Ecto.Migration

  def change do
    # GIN index on flow_nodes.data for JSONB containment/existence queries
    create index(:flow_nodes, ["(data)"],
             using: "GIN",
             name: :flow_nodes_data_gin_index
           )

    # Partial index on active flow_nodes by type (excludes soft-deleted)
    create index(:flow_nodes, [:flow_id, :type],
             where: "deleted_at IS NULL",
             name: :flow_nodes_active_by_type_index
           )
  end
end
