defmodule Storyarn.Repo.Migrations.AddWaypointsToConnections do
  use Ecto.Migration

  def change do
    alter table(:map_connections) do
      add :waypoints, :jsonb, default: "[]"
    end
  end
end
