defmodule Storyarn.Repo.Migrations.AddIconAssetToPins do
  use Ecto.Migration

  def change do
    alter table(:map_pins) do
      add :icon_asset_id, references(:assets, on_delete: :nilify_all)
    end

    create index(:map_pins, [:icon_asset_id])
  end
end
