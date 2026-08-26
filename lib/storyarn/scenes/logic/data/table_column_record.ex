defmodule Storyarn.Scenes.Logic.Data.TableColumnRecord do
  @moduledoc "Logic-owned projection of table-column variable definitions."

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "table_columns" do
    field :slug, :string
    field :type, :string
    field :position, :integer, default: 0
    field :config, :map, default: %{}
    field :is_constant, :boolean, default: false
    field :block_id, :id

    timestamps(type: :utc_datetime)
  end
end
