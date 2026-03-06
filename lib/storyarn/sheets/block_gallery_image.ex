defmodule Storyarn.Sheets.BlockGalleryImage do
  @moduledoc """
  Schema for gallery images attached to a gallery block.

  Each gallery image links a block to an asset with optional label and description.
  Images are ordered by position within the block.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Storyarn.Assets.Asset
  alias Storyarn.Sheets.Block

  schema "block_gallery_images" do
    field :label, :string
    field :description, :string
    field :position, :integer, default: 0

    belongs_to :block, Block
    belongs_to :asset, Asset

    timestamps(type: :utc_datetime)
  end

  @doc "Changeset for creating a gallery image."
  def create_changeset(gallery_image, attrs) do
    gallery_image
    |> cast(attrs, [:label, :description, :position, :block_id, :asset_id])
    |> validate_required([:block_id, :asset_id])
    |> foreign_key_constraint(:block_id)
    |> foreign_key_constraint(:asset_id)
    |> unique_constraint([:block_id, :asset_id])
  end

  @doc "Changeset for updating a gallery image's label and description."
  def update_changeset(gallery_image, attrs) do
    gallery_image
    |> cast(attrs, [:label, :description])
  end
end
