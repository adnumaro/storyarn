defmodule Storyarn.GlobalSearch.Persistence.BlockGalleryImageRecord do
  @moduledoc false

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "block_gallery_images" do
    field :label, :string
    field :description, :string
    field :block_id, :id

    timestamps(type: :utc_datetime)
  end
end
