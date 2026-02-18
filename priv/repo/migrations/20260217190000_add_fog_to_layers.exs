defmodule Storyarn.Repo.Migrations.AddFogToLayers do
  use Ecto.Migration

  def change do
    alter table(:map_layers) do
      add :fog_enabled, :boolean, default: false, null: false
      add :fog_color, :string, default: "#000000"
      add :fog_opacity, :float, default: 0.85
    end
  end
end
