defmodule Storyarn.Repo.Migrations.AddWalkableAndPlayableFields do
  use Ecto.Migration

  def change do
    alter table(:scene_zones) do
      add :is_walkable, :boolean, default: false, null: false
    end

    alter table(:scene_pins) do
      add :is_playable, :boolean, default: false, null: false
      add :is_leader, :boolean, default: false, null: false
    end
  end
end
