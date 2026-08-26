defmodule Storyarn.Flows.Editor.Data.BlockRecord do
  @moduledoc """
  Consumer-local Sheet block projection used by the Flow editor catalog.

  It describes only foreign authored data needed for editor lookup; it does
  not claim ownership of the shared `blocks` table.
  """

  use Ecto.Schema

  alias Storyarn.Flows.Editor.Data.SheetRecord

  @type t :: %__MODULE__{}

  schema "blocks" do
    field :type, :string
    field :position, :integer, default: 0
    field :config, :map, default: %{}
    field :value, :map, default: %{}
    field :is_constant, :boolean, default: false
    field :variable_name, :string
    field :scope, :string, default: "self"
    field :inherited_from_block_id, :id
    field :deleted_at, :utc_datetime

    belongs_to :sheet, SheetRecord

    timestamps(type: :utc_datetime)
  end
end
