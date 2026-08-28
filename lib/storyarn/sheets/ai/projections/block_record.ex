defmodule Storyarn.Sheets.AI.Projections.BlockRecord do
  @moduledoc """
  AI-owned read model of Sheet blocks included in a context package.

  The projection is intentionally read-only and excludes editor changesets,
  associations and fields that cannot enter the Sheet AI contract.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "blocks" do
    field :type, :string
    field :position, :integer, default: 0
    field :config, :map, default: %{}
    field :value, :map, default: %{}
    field :variable_name, :string
    field :sheet_id, :id
    field :deleted_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end
end
