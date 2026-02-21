defmodule Storyarn.Repo.Migrations.AddSoftDeleteToFlowNodes do
  use Ecto.Migration

  def change do
    alter table(:flow_nodes) do
      add :deleted_at, :utc_datetime
    end

    create index(:flow_nodes, [:flow_id],
             where: "deleted_at IS NULL",
             name: :flow_nodes_active_flow_id_index
           )
  end
end
