defmodule Storyarn.Projects.Persistence.BlockGalleryImageRecord do
  @moduledoc false

  use Ecto.Schema

  alias Storyarn.Projects.Assets.Asset
  alias Storyarn.Projects.Persistence.BlockRecord

  @type t :: %__MODULE__{}

  schema "block_gallery_images" do
    field :label, :string
    field :description, :string
    field :position, :integer, default: 0

    belongs_to :block, BlockRecord
    belongs_to :asset, Asset, where: [deleted_at: nil]

    timestamps(type: :utc_datetime)
  end
end
