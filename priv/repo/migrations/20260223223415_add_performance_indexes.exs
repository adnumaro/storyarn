defmodule Storyarn.Repo.Migrations.AddPerformanceIndexes do
  use Ecto.Migration

  def change do
    # MI1: map_layers — missing individual map_id index
    # The existing composite [map_id, position] index doesn't serve queries filtering by map_id alone
    create index(:map_layers, [:map_id])

    # MI2: flow_nodes — partial index for soft-deleted nodes (trash queries)
    create index(:flow_nodes, [:deleted_at],
             where: "deleted_at IS NOT NULL",
             name: :flow_nodes_trash_index
           )

    # MI4: map_connections — missing individual pin reference indexes
    create index(:map_connections, [:from_pin_id])
    create index(:map_connections, [:to_pin_id])
  end
end
