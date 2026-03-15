defmodule Storyarn.Repo.Migrations.CreateSceneAmbientFlows do
  use Ecto.Migration

  def change do
    create table(:scene_ambient_flows) do
      add :scene_id, references(:scenes, on_delete: :delete_all), null: false
      add :flow_id, references(:flows, on_delete: :delete_all), null: false
      add :trigger_type, :string, null: false, default: "on_enter"
      add :enabled, :boolean, null: false, default: true
      add :position, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:scene_ambient_flows, [:scene_id])
    create index(:scene_ambient_flows, [:flow_id])
    create unique_index(:scene_ambient_flows, [:scene_id, :flow_id])
  end
end
