defmodule Storyarn.Flows.Editor.Projections.SheetAvatarRecord do
  @moduledoc """
  Consumer-local Sheet avatar projection used by Flow speaker authoring.

  Sheets owns avatar lifecycle. Editor reads the stable presentation fields and
  active asset association needed by its catalog.
  """

  use Ecto.Schema

  alias Storyarn.Flows.Editor.Projections.AssetRecord

  @type t :: %__MODULE__{}

  schema "sheet_avatars" do
    field :name, :string
    field :position, :integer, default: 0
    field :is_default, :boolean, default: false
    field :sheet_id, :id

    belongs_to :asset, AssetRecord, where: [deleted_at: nil]
  end
end
