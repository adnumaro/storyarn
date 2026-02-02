defmodule Storyarn.Repo.Migrations.AddBannerToPages do
  use Ecto.Migration

  def change do
    alter table(:pages) do
      add :banner_asset_id, references(:assets, on_delete: :nilify_all)
    end

    create index(:pages, [:banner_asset_id])
  end
end
