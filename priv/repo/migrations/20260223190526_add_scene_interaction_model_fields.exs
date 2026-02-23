defmodule Storyarn.Repo.Migrations.AddSceneInteractionModelFields do
  use Ecto.Migration

  def change do
    # 1.1 — Add scene_map_id to flows
    alter table(:flows) do
      add :scene_map_id, references(:maps, on_delete: :nilify_all), null: true
    end

    create index(:flows, [:scene_map_id])

    # 1.2 — Add condition fields to map_zones
    alter table(:map_zones) do
      add :condition, :map, null: true
      add :condition_effect, :string, default: "hide"
    end

    # 1.3 + 1.4 — Add condition fields + action fields to map_pins
    alter table(:map_pins) do
      add :condition, :map, null: true
      add :condition_effect, :string, default: "hide"
      add :action_type, :string, default: "none"
      add :action_data, :map, default: %{}
    end
  end
end
