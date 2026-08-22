defmodule Storyarn.Projects.Persistence.SheetRecord do
  @moduledoc false

  use Ecto.Schema

  alias Storyarn.Assets.Asset
  alias Storyarn.Projects.Persistence.BlockRecord
  alias Storyarn.Projects.Persistence.SheetAvatarRecord

  @type t :: %__MODULE__{}

  schema "sheets" do
    field :name, :string
    field :shortcut, :string
    field :description, :string
    field :color, :string
    field :position, :integer, default: 0
    field :project_id, :id
    field :parent_id, :id
    field :deleted_at, :utc_datetime

    belongs_to :banner_asset, Asset, where: [deleted_at: nil]
    has_many :avatars, SheetAvatarRecord, foreign_key: :sheet_id
    has_many :blocks, BlockRecord, foreign_key: :sheet_id

    timestamps(type: :utc_datetime)
  end
end
