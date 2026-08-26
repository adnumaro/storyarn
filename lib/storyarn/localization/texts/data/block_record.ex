defmodule Storyarn.Localization.Texts.Data.BlockRecord do
  @moduledoc """
  Read-only projection of a Sheet block used to build the runtime text inventory.

  The projection is consumer-owned by Texts and must not be used for ordinary
  block writes.
  """
  use Ecto.Schema

  alias Storyarn.Localization.Texts.Data.SheetRecord

  @type t :: %__MODULE__{
          id: integer() | nil,
          sheet_id: integer() | nil,
          sheet: SheetRecord.t() | Ecto.Association.NotLoaded.t() | nil,
          type: String.t() | nil,
          value: map(),
          is_constant: boolean(),
          variable_name: String.t() | nil,
          word_count: non_neg_integer(),
          inherited_from_block_id: integer() | nil,
          deleted_at: DateTime.t() | nil
        }

  schema "blocks" do
    field :type, :string
    field :value, :map, default: %{}
    field :is_constant, :boolean, default: false
    field :variable_name, :string
    field :word_count, :integer, default: 0
    field :inherited_from_block_id, :id
    field :deleted_at, :utc_datetime
    belongs_to :sheet, SheetRecord
    timestamps(type: :utc_datetime)
  end
end
