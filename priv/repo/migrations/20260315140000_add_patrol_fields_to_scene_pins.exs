defmodule Storyarn.Repo.Migrations.AddPatrolFieldsToScenePins do
  use Ecto.Migration

  def change do
    alter table(:scene_pins) do
      add :patrol_mode, :string, default: "none", null: false
      add :patrol_speed, :float, default: 1.0, null: false
      add :patrol_pause_ms, :integer, default: 0, null: false
    end
  end
end
