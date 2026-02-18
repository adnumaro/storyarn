defmodule Storyarn.Repo.Migrations.AddScaleToMaps do
  use Ecto.Migration

  def change do
    alter table(:maps) do
      add :scale_unit, :string
      add :scale_value, :float
    end
  end
end
