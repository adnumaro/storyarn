defmodule Storyarn.Repo.Migrations.AddActionFieldsToMapZones do
  use Ecto.Migration

  def change do
    alter table(:map_zones) do
      add :action_type, :string, default: "navigate", null: false
      add :action_data, :map, default: %{}, null: false
    end

    create index(:map_zones, [:map_id, :action_type])
  end
end
