defmodule Storyarn.Flows.Runtime.Data.SheetRecord do
  @moduledoc "Runtime-owned speaker projection for the Flow player catalog."

  use Ecto.Schema

  alias Storyarn.Flows.Runtime.Data.SheetAvatarRecord

  @type t :: %__MODULE__{}

  schema "sheets" do
    field :name, :string
    field :color, :string
    field :position, :integer, default: 0
    field :project_id, :id
    field :deleted_at, :utc_datetime

    has_many :avatars, SheetAvatarRecord, foreign_key: :sheet_id

    timestamps(type: :utc_datetime)
  end
end
