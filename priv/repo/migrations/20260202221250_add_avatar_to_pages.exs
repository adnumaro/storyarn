defmodule Storyarn.Repo.Migrations.AddAvatarToPages do
  use Ecto.Migration

  def change do
    alter table(:pages) do
      add :avatar_asset_id, references(:assets, on_delete: :nilify_all)
      remove :icon, :string, default: "page"
    end

    create index(:pages, [:avatar_asset_id])
  end
end
