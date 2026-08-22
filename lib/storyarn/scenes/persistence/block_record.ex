defmodule Storyarn.Scenes.Persistence.BlockRecord do
  @moduledoc false

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "blocks" do
    field :type, :string
    field :position, :integer, default: 0
    field :config, :map, default: %{}
    field :value, :map, default: %{}
    field :is_constant, :boolean, default: false
    field :variable_name, :string
    field :deleted_at, :utc_datetime
    field :sheet_id, :id

    timestamps(type: :utc_datetime)
  end
end
