defmodule Storyarn.Scenes.References.Projections.BlockRecord do
  @moduledoc "References-owned consumer-local SQL projection used to validate and maintain Scene reference indexes."

  use Ecto.Schema

  alias Storyarn.Scenes.References.Projections.SheetRecord
  alias Storyarn.Scenes.References.Projections.TableColumnRecord
  alias Storyarn.Scenes.References.Projections.TableRowRecord

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
    has_many :table_columns, TableColumnRecord, foreign_key: :block_id
    has_many :table_rows, TableRowRecord, foreign_key: :block_id

    timestamps(type: :utc_datetime)
  end
end
