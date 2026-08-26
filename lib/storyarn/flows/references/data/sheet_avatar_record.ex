defmodule Storyarn.Flows.References.Data.SheetAvatarRecord do
  @moduledoc "Consumer-owned projection of Sheet avatars referenced by dialogue nodes."

  use Ecto.Schema

  alias Storyarn.Flows.References.Data.AssetRecord

  @type t :: %__MODULE__{}

  schema "sheet_avatars" do
    field :name, :string
    field :position, :integer, default: 0
    field :is_default, :boolean, default: false
    field :sheet_id, :id

    belongs_to :asset, AssetRecord, where: [deleted_at: nil]
  end
end
