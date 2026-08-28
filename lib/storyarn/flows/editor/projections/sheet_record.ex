defmodule Storyarn.Flows.Editor.Projections.SheetRecord do
  @moduledoc """
  Consumer-local Sheet projection used by Flow speaker and mention catalogs.

  The projection is intentionally independent from the Sheets bounded-context
  entity even while both map the same PostgreSQL table.
  """

  use Ecto.Schema

  alias Storyarn.Flows.Editor.Projections.AssetRecord
  alias Storyarn.Flows.Editor.Projections.BlockRecord
  alias Storyarn.Flows.Editor.Projections.SheetAvatarRecord

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

    belongs_to :banner_asset, AssetRecord, where: [deleted_at: nil]
    has_many :avatars, SheetAvatarRecord, foreign_key: :sheet_id
    has_many :blocks, BlockRecord, foreign_key: :sheet_id

    timestamps(type: :utc_datetime)
  end
end
