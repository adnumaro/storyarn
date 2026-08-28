defmodule Storyarn.Scenes.Versioning.Projections.SheetAvatarRecord do
  @moduledoc "Versioning-owned consumer-local SQL projection used to capture and restore Scene versions without importing another context's schema."

  use Ecto.Schema

  alias Storyarn.Scenes.Versioning.Entities.AssetRecord

  @type t :: %__MODULE__{}

  schema "sheet_avatars" do
    field :name, :string
    field :position, :integer, default: 0
    field :is_default, :boolean, default: false
    field :sheet_id, :id

    belongs_to :asset, AssetRecord, where: [deleted_at: nil]
  end
end
