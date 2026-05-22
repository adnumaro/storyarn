defmodule Storyarn.Repo.Migrations.AddSceneZoneLabelSettings do
  use Ecto.Migration

  def change do
    alter table(:scene_zones) do
      add :label_mode, :string, default: "text", null: false
      add :label_font_size, :integer, default: 12, null: false
      add :label_font_family, :string, default: "system", null: false
      add :label_font_weight, :string, default: "600", null: false
      add :label_font_style, :string, default: "normal", null: false
    end
  end
end
