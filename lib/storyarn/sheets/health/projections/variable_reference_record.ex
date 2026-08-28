defmodule Storyarn.Sheets.Health.Projections.VariableReferenceRecord do
  @moduledoc """
  Health-local read projection of the variable-reference index.

  Health currently queries only the target block identity, but declares the
  persisted reference fields so health fixtures can construct representative
  rows without importing References data or another bounded context's model.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "variable_references" do
    field :source_type, :string
    field :source_id, :integer
    field :flow_node_id, :id
    field :block_id, :id
    field :kind, :string
    field :source_sheet, :string
    field :source_variable, :string

    timestamps(type: :utc_datetime)
  end
end
