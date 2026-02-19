defmodule Storyarn.Repo.Migrations.AddLineWidthToMapConnections do
  use Ecto.Migration

  def change do
    alter table(:map_connections) do
      add :line_width, :integer, default: 2
    end
  end
end
