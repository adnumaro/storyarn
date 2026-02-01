defmodule Storyarn.Repo.Migrations.CreateFlows do
  use Ecto.Migration

  def change do
    create table(:flows) do
      add :name, :string, null: false
      add :description, :text
      add :is_main, :boolean, default: false, null: false
      add :settings, :map, default: %{}
      add :project_id, references(:projects, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:flows, [:project_id])
    create unique_index(:flows, [:project_id, :is_main], where: "is_main = true")

    create table(:flow_nodes) do
      add :type, :string, null: false
      add :position_x, :float, default: 0.0, null: false
      add :position_y, :float, default: 0.0, null: false
      add :data, :map, default: %{}
      add :flow_id, references(:flows, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:flow_nodes, [:flow_id])
    create index(:flow_nodes, [:flow_id, :type])

    create table(:flow_connections) do
      add :source_pin, :string, null: false
      add :target_pin, :string, null: false
      add :label, :string
      add :condition, :string
      add :flow_id, references(:flows, on_delete: :delete_all), null: false
      add :source_node_id, references(:flow_nodes, on_delete: :delete_all), null: false
      add :target_node_id, references(:flow_nodes, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:flow_connections, [:flow_id])
    create index(:flow_connections, [:source_node_id])
    create index(:flow_connections, [:target_node_id])

    create unique_index(:flow_connections, [
             :source_node_id,
             :source_pin,
             :target_node_id,
             :target_pin
           ])
  end
end
