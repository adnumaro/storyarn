defmodule Storyarn.Repo.Migrations.AddOpacityToMapPins do
  use Ecto.Migration

  def change do
    alter table(:map_pins) do
      add :opacity, :float, default: 1.0
    end
  end
end
