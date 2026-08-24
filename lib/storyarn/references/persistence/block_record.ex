defmodule Storyarn.References.Persistence.BlockRecord do
  @moduledoc "References-owned read model for variable-bearing Sheet blocks."

  use Ecto.Schema

  alias Storyarn.References.Persistence.SheetRecord
  alias Storyarn.References.Persistence.TableColumnRecord
  alias Storyarn.References.Persistence.TableRowRecord

  @type t :: %__MODULE__{
          id: integer() | nil,
          sheet_id: integer() | nil,
          type: String.t() | nil,
          variable_name: String.t() | nil,
          is_constant: boolean(),
          deleted_at: DateTime.t() | nil
        }

  schema "blocks" do
    field :type, :string
    field :position, :integer, default: 0
    field :config, :map, default: %{}
    field :value, :map, default: %{}
    field :variable_name, :string
    field :is_constant, :boolean, default: false
    field :deleted_at, :utc_datetime

    belongs_to :sheet, SheetRecord
    has_many :table_columns, TableColumnRecord, foreign_key: :block_id
    has_many :table_rows, TableRowRecord, foreign_key: :block_id

    timestamps(type: :utc_datetime)
  end
end
