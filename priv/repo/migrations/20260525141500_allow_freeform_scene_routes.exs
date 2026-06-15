defmodule Storyarn.Repo.Migrations.AllowFreeformSceneRoutes do
  use Ecto.Migration

  def change do
    execute(
      "ALTER TABLE scene_connections ALTER COLUMN from_pin_id DROP NOT NULL",
      "ALTER TABLE scene_connections ALTER COLUMN from_pin_id SET NOT NULL"
    )

    execute(
      "ALTER TABLE scene_connections ALTER COLUMN to_pin_id DROP NOT NULL",
      "ALTER TABLE scene_connections ALTER COLUMN to_pin_id SET NOT NULL"
    )

    alter table(:scene_connections) do
      add :from_stop, :boolean, default: true, null: false
      add :to_stop, :boolean, default: true, null: false
      add :from_pause_ms, :integer
      add :to_pause_ms, :integer
    end
  end
end
