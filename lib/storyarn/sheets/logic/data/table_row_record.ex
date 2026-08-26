defmodule Storyarn.Sheets.Logic.Data.TableRowRecord do
  @moduledoc """
  Logic-owned read model of table-row variable values.

  The projection carries only row identity, ordering and cell data used by
  formula evaluation and qualified-reference resolution.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "table_rows" do
    field :name, :string
    field :slug, :string
    field :position, :integer, default: 0
    field :cells, :map, default: %{}
    field :block_id, :id

    timestamps(type: :utc_datetime)
  end
end
