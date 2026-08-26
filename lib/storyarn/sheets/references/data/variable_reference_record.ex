defmodule Storyarn.Sheets.References.Data.VariableReferenceRecord do
  @moduledoc """
  References-owned SQL projection of recorded Sheet variable usages.

  Commands maintain missing rows after restore and queries report usage and
  staleness. The schema is passive and contains no cross-context behavior.
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
