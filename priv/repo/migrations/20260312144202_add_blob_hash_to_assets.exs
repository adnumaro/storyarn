defmodule Storyarn.Repo.Migrations.AddBlobHashToAssets do
  use Ecto.Migration

  def change do
    alter table(:assets) do
      add :blob_hash, :string
    end

    create index(:assets, [:project_id, :blob_hash])
  end
end
