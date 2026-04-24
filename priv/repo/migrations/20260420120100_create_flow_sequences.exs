defmodule Storyarn.Repo.Migrations.CreateFlowSequences do
  use Ecto.Migration

  def change do
    create table(:flow_sequences) do
      add :name, :string, null: false
      add :tracks, :map, default: %{}, null: false
      add :deleted_at, :utc_datetime

      add :position_x, :float, default: 0.0, null: false
      add :position_y, :float, default: 0.0, null: false
      add :width, :float, default: 300.0, null: false
      add :height, :float, default: 200.0, null: false

      add :flow_id, references(:flows, on_delete: :delete_all), null: false
      add :parent_id, references(:flow_sequences, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:flow_sequences, [:flow_id])
    create index(:flow_sequences, [:parent_id])

    create index(:flow_sequences, [:flow_id],
             where: "deleted_at IS NULL",
             name: :flow_sequences_active_flow_id_index
           )
  end
end
