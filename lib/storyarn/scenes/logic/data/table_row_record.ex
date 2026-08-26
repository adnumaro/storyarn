defmodule Storyarn.Scenes.Logic.Data.TableRowRecord do
  @moduledoc "Logic-owned projection of table-row variable values."

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "table_rows" do
    field :slug, :string
    field :position, :integer, default: 0
    field :cells, :map, default: %{}
    field :block_id, :id

    timestamps(type: :utc_datetime)
  end
end
