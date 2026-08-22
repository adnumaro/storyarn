defmodule Storyarn.Projects.Persistence.SheetAvatarRecord do
  @moduledoc false

  use Ecto.Schema

  alias Storyarn.Assets.Asset

  @type t :: %__MODULE__{}

  schema "sheet_avatars" do
    field :name, :string
    field :position, :integer, default: 0
    field :is_default, :boolean, default: false
    field :sheet_id, :id

    belongs_to :asset, Asset, where: [deleted_at: nil]
  end
end
