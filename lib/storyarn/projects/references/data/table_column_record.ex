defmodule Storyarn.Projects.References.Persistence.TableColumnRecord do
  @moduledoc "References-owned read model for variable-bearing table columns."

  use Ecto.Schema

  alias Storyarn.Projects.References.Persistence.BlockRecord

  @type t :: %__MODULE__{
          id: integer() | nil,
          block_id: integer() | nil,
          slug: String.t() | nil,
          type: String.t() | nil,
          is_constant: boolean()
        }

  schema "table_columns" do
    field :name, :string
    field :slug, :string
    field :type, :string
    field :position, :integer, default: 0
    field :config, :map, default: %{}
    field :is_constant, :boolean, default: false

    belongs_to :block, BlockRecord

    timestamps(type: :utc_datetime)
  end
end
