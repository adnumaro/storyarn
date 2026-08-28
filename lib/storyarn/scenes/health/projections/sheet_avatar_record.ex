defmodule Storyarn.Scenes.Health.Projections.SheetAvatarRecord do
  @moduledoc "Health-owned consumer-local SQL projection used to evaluate Scene health without importing another context's schema."

  use Ecto.Schema

  alias Storyarn.Scenes.Health.Projections.AssetRecord

  @type t :: %__MODULE__{}

  schema "sheet_avatars" do
    field :name, :string
    field :position, :integer, default: 0
    field :is_default, :boolean, default: false
    field :sheet_id, :id

    belongs_to :asset, AssetRecord, where: [deleted_at: nil]
  end
end
