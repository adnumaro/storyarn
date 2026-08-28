defmodule Storyarn.Flows.Runtime.Projections.SheetAvatarRecord do
  @moduledoc "Runtime-owned projection of an authored speaker avatar."

  use Ecto.Schema

  alias Storyarn.Flows.Runtime.Projections.AssetRecord

  @type t :: %__MODULE__{}

  schema "sheet_avatars" do
    field :name, :string
    field :position, :integer, default: 0
    field :is_default, :boolean, default: false
    field :sheet_id, :id

    belongs_to :asset, AssetRecord, where: [deleted_at: nil]
  end
end
