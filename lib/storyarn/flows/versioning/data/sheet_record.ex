defmodule Storyarn.Flows.Versioning.Data.SheetRecord do
  @moduledoc """
  Versioning-owned Sheet projection used to capture display metadata and validate Flow references.
  """

  use Ecto.Schema

  alias Storyarn.Flows.Versioning.Data.AssetRecord
  alias Storyarn.Flows.Versioning.Data.SheetAvatarRecord

  @type t :: %__MODULE__{}

  schema "sheets" do
    field :name, :string
    field :shortcut, :string
    field :color, :string
    field :project_id, :id
    field :deleted_at, :utc_datetime

    belongs_to :banner_asset, AssetRecord, where: [deleted_at: nil]
    has_many :avatars, SheetAvatarRecord, foreign_key: :sheet_id
  end
end
