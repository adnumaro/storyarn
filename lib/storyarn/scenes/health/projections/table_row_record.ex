defmodule Storyarn.Scenes.Health.Projections.TableRowRecord do
  @moduledoc "Health-owned consumer-local SQL projection used to evaluate Scene health without importing another context's schema."

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
