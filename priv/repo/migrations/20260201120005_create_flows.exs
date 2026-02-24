defmodule Storyarn.Repo.Migrations.CreateFlows do
  use Ecto.Migration

  def change do
    create table(:flows) do
      add :name, :string, null: false
      add :description, :text
      add :shortcut, :string
      add :is_main, :boolean, default: false, null: false
      add :settings, :map, default: %{}
      add :position, :integer, default: 0
      add :deleted_at, :utc_datetime
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :parent_id, references(:flows, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:flows, [:project_id])
    create index(:flows, [:parent_id])
    create index(:flows, [:project_id, :parent_id, :position])
    create index(:flows, [:deleted_at])
    create unique_index(:flows, [:project_id, :is_main], where: "is_main = true")

    create unique_index(:flows, [:project_id, :shortcut],
             where: "shortcut IS NOT NULL AND deleted_at IS NULL",
             name: :flows_project_shortcut_unique
           )

    create table(:flow_nodes) do
      add :type, :string, null: false
      add :position_x, :float, default: 0.0, null: false
      add :position_y, :float, default: 0.0, null: false
      add :data, :map, default: %{}
      add :source, :string, default: "manual", null: false
      add :deleted_at, :utc_datetime
      add :flow_id, references(:flows, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:flow_nodes, [:flow_id])
    create index(:flow_nodes, [:flow_id, :type])
    create index(:flow_nodes, [:source])

    create index(:flow_nodes, [:flow_id],
             where: "deleted_at IS NULL",
             name: :flow_nodes_active_flow_id_index
           )

    create index(:flow_nodes, [:deleted_at],
             where: "deleted_at IS NOT NULL",
             name: :flow_nodes_trash_index
           )

    create index(:flow_nodes, [:flow_id, :type],
             where: "deleted_at IS NULL",
             name: :flow_nodes_active_by_type_index
           )

    create index(:flow_nodes, ["(data)"],
             using: "GIN",
             name: :flow_nodes_data_gin_index
           )

    create table(:flow_connections) do
      add :source_pin, :string, null: false
      add :target_pin, :string, null: false
      add :label, :string
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
