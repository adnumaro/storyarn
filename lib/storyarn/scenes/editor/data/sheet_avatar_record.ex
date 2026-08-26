defmodule Storyarn.Scenes.Editor.Data.SheetAvatarRecord do
  @moduledoc "Editor-owned consumer-local SQL projection used by Scene editing without importing another context's schema."

  use Ecto.Schema

  alias Storyarn.Scenes.Editor.Data.AssetRecord

  @type t :: %__MODULE__{}

  schema "sheet_avatars" do
    field :name, :string
    field :position, :integer, default: 0
    field :is_default, :boolean, default: false
    field :sheet_id, :id

    belongs_to :asset, AssetRecord, where: [deleted_at: nil]
  end
end
