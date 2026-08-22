defmodule Storyarn.References.Persistence.TableRowRecord do
  @moduledoc "References-owned projection and rewrite model for table rows."

  use Ecto.Schema

  alias Storyarn.References.Persistence.BlockRecord

  @type t :: %__MODULE__{
          id: integer() | nil,
          block_id: integer() | nil,
          slug: String.t() | nil,
          cells: map()
        }

  schema "table_rows" do
    field :name, :string
    field :slug, :string
    field :position, :integer, default: 0
    field :cells, :map, default: %{}

    belongs_to :block, BlockRecord

    timestamps(type: :utc_datetime)
  end
end
