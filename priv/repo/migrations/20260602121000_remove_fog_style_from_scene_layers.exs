defmodule Storyarn.Repo.Migrations.RemoveFogStyleFromSceneLayers do
  use Ecto.Migration

  def change do
    alter table(:scene_layers) do
      remove :fog_color, :string
      remove :fog_opacity, :float
    end
  end
end
