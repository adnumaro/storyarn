defmodule Storyarn.Sheets.Logic.Data.BlockRecord do
  @moduledoc """
  Logic-owned read model of variable-bearing Sheet blocks.

  Formula resolution and typed predicates read this projection without
  depending on the editor's writable Block entity or its changesets.
  """

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
    field :inherited_from_block_id, :id
    field :deleted_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end
end
