defmodule Storyarn.Scenes.Exploration.Projections.SheetAvatarRecord do
  @moduledoc "Exploration-owned projection of a Sheet speaker avatar."

  use Ecto.Schema

  alias Storyarn.Scenes.Exploration.Projections.AssetRecord

  @type t :: %__MODULE__{}

  schema "sheet_avatars" do
    field :name, :string
    field :position, :integer, default: 0
    field :is_default, :boolean, default: false
    field :sheet_id, :id

    belongs_to :asset, AssetRecord, where: [deleted_at: nil]
  end
end
