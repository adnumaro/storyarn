defmodule Storyarn.Flows.Persistence.TableColumnRecord do
  @moduledoc false

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "table_columns" do
    field :name, :string
    field :slug, :string
    field :type, :string
    field :is_constant, :boolean, default: false
    field :position, :integer, default: 0
    field :config, :map, default: %{}
    field :block_id, :id

    timestamps(type: :utc_datetime)
  end
end
