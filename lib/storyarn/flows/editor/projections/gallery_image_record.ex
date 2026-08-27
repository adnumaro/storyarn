defmodule Storyarn.Flows.Editor.Projections.GalleryImageRecord do
  @moduledoc """
  Consumer-local gallery image projection used by the Flow editor catalog.

  Gallery lifecycle remains owned by Sheets; Editor reads only the display
  fields and active asset association it needs.
  """

  use Ecto.Schema

  alias Storyarn.Flows.Editor.Projections.AssetRecord

  @type t :: %__MODULE__{}

  schema "block_gallery_images" do
    field :label, :string
    field :position, :integer, default: 0
    field :block_id, :id

    belongs_to :asset, AssetRecord, where: [deleted_at: nil]
  end
end
