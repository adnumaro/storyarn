defmodule Storyarn.Repo.Migrations.CreateBlockGalleryImages do
  use Ecto.Migration

  def change do
    create table(:block_gallery_images) do
      add :label, :string
      add :description, :text
      add :position, :integer, null: false, default: 0
      add :block_id, references(:blocks, on_delete: :delete_all), null: false
      add :asset_id, references(:assets, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:block_gallery_images, [:block_id])
    create unique_index(:block_gallery_images, [:block_id, :asset_id])
  end
end
