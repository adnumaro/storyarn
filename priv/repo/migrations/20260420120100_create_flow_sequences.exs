defmodule Storyarn.Repo.Migrations.CreateFlowSequences do
  use Ecto.Migration

  def change do
    create table(:flow_sequences) do
      add :name, :string, null: false
      add :tracks, :map, default: %{}, null: false
      add :deleted_at, :utc_datetime
      add :flow_id, references(:flows, on_delete: :delete_all), null: false
      add :start_node_id, references(:flow_nodes, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:flow_sequences, [:flow_id])
    create index(:flow_sequences, [:start_node_id])

    create index(:flow_sequences, [:flow_id],
             where: "deleted_at IS NULL",
             name: :flow_sequences_active_flow_id_index
           )
  end
end
