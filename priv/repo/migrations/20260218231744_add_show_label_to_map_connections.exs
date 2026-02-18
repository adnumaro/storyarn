defmodule Storyarn.Repo.Migrations.AddShowLabelToMapConnections do
  use Ecto.Migration

  def change do
    alter table(:map_connections) do
      add :show_label, :boolean, default: true, null: false
    end
  end
end
