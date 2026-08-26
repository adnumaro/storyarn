defmodule Storyarn.Sheets.Localization.Data.BlockRecord do
  @moduledoc """
  Localization-owned read model of Sheet blocks that may emit runtime text.

  It deliberately excludes editor changesets and unrelated presentation fields;
  reconciliation needs only content identity, export flags and inheritance.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "blocks" do
    field :type, :string
    field :value, :map, default: %{}
    field :is_constant, :boolean, default: false
    field :variable_name, :string
    field :sheet_id, :id
    field :inherited_from_block_id, :id
    field :deleted_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end
end
