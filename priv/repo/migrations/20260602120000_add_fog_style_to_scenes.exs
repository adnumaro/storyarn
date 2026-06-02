defmodule Storyarn.Repo.Migrations.AddFogStyleToScenes do
  use Ecto.Migration

  def change do
    alter table(:scenes) do
      add :fog_color, :string, default: "#000000"
      add :fog_opacity, :float, default: 0.85, null: false
    end
  end
end
