defmodule Storyarn.Scenes.Exploration.Projections.SheetRecord do
  @moduledoc "Exploration-owned projection of Sheet identity and speaker data."

  use Ecto.Schema

  alias Storyarn.Scenes.Exploration.Projections.SheetAvatarRecord

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
    has_many :children, __MODULE__, foreign_key: :parent_id
    has_many :avatars, SheetAvatarRecord, foreign_key: :sheet_id

    timestamps(type: :utc_datetime)
  end
end
