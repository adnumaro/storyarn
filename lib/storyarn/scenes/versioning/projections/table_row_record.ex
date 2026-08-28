defmodule Storyarn.Scenes.Versioning.Projections.TableRowRecord do
  @moduledoc "Versioning-owned consumer-local SQL projection used to capture and restore Scene versions without importing another context's schema."

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
