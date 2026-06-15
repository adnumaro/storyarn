defmodule Storyarn.Repo.Migrations.AddSceneZoneLabelIconAsset do
  use Ecto.Migration

  def change do
    alter table(:scene_zones) do
      add :label_icon_asset_id, references(:assets, on_delete: :nilify_all)
    end

    create index(:scene_zones, [:label_icon_asset_id])
  end
end
