defmodule Storyarn.Sheets.Expressions.Projections.TableColumnRecord do
  @moduledoc """
  Logic-owned read model of table-column variable definitions.

  Only fields needed for type constraints, formula bindings and navigation are
  projected; editor mutations remain owned by the editor capability.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "table_columns" do
    field :name, :string
    field :slug, :string
    field :type, :string
    field :position, :integer, default: 0
    field :config, :map, default: %{}
    field :is_constant, :boolean, default: false
    field :block_id, :id

    timestamps(type: :utc_datetime)
  end
end
