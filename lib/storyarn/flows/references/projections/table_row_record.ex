defmodule Storyarn.Flows.References.Projections.TableRowRecord do
  @moduledoc "Consumer-owned projection of table rows used by Flow variable references."

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
