defmodule Storyarn.Repo.Migrations.RemoveAvatarAssetIdFromSheets do
  use Ecto.Migration

  def change do
    drop_if_exists index(:sheets, [:avatar_asset_id])

    alter table(:sheets) do
      remove :avatar_asset_id, references(:assets, on_delete: :nilify_all)
    end
  end
end
