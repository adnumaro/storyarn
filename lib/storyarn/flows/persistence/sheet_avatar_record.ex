defmodule Storyarn.Flows.Persistence.SheetAvatarRecord do
  @moduledoc false

  use Ecto.Schema

  alias Storyarn.Flows.Persistence.AssetRecord

  schema "sheet_avatars" do
    field :name, :string
    field :position, :integer, default: 0
    field :is_default, :boolean, default: false
    field :sheet_id, :id

    belongs_to :asset, AssetRecord, where: [deleted_at: nil]
  end
end
