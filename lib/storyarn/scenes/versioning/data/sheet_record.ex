defmodule Storyarn.Scenes.Versioning.Data.SheetRecord do
  @moduledoc "Versioning-owned consumer-local SQL projection used to capture and restore Scene versions without importing another context's schema."

  use Ecto.Schema

  alias Storyarn.Scenes.Versioning.Data.AssetRecord
  alias Storyarn.Scenes.Versioning.Data.BlockRecord
  alias Storyarn.Scenes.Versioning.Data.SheetAvatarRecord

  @type t :: %__MODULE__{}

  schema "sheets" do
    field :name, :string
    field :shortcut, :string
    field :description, :string
    field :color, :string
    field :position, :integer, default: 0
    field :hidden_inherited_block_ids, {:array, :integer}, default: []
    field :project_id, :id
    field :banner_asset_id, :id
    field :current_version_id, :id
    field :deleted_at, :utc_datetime

    belongs_to :parent, __MODULE__
    belongs_to :banner_asset, AssetRecord, define_field: false, where: [deleted_at: nil]
    has_many :children, __MODULE__, foreign_key: :parent_id
    has_many :avatars, SheetAvatarRecord, foreign_key: :sheet_id
    has_many :blocks, BlockRecord, foreign_key: :sheet_id

    timestamps(type: :utc_datetime)
  end
end
