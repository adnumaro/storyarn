defmodule Storyarn.Flows.Persistence.GalleryImageRecord do
  @moduledoc false

  use Ecto.Schema

  alias Storyarn.Flows.Persistence.AssetRecord

  schema "block_gallery_images" do
    field :label, :string
    field :position, :integer, default: 0
    field :block_id, :id

    belongs_to :asset, AssetRecord, where: [deleted_at: nil]
  end
end
