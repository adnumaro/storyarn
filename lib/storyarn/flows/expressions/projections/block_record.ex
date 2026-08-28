defmodule Storyarn.Flows.Expressions.Projections.BlockRecord do
  @moduledoc "Logic-owned read projection of variable-bearing Sheet blocks."

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "blocks" do
    field :type, :string
    field :position, :integer, default: 0
    field :config, :map, default: %{}
    field :value, :map, default: %{}
    field :is_constant, :boolean, default: false
    field :variable_name, :string
    field :sheet_id, :id
    field :deleted_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end
end
