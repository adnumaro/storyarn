defmodule Storyarn.Repo.Migrations.AddLockedToMapElements do
  use Ecto.Migration

  def change do
    alter table(:map_pins) do
      add :locked, :boolean, default: false, null: false
    end

    alter table(:map_zones) do
      add :locked, :boolean, default: false, null: false
    end

    alter table(:map_annotations) do
      add :locked, :boolean, default: false, null: false
    end
  end
end
