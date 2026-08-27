defmodule Storyarn.Projects.Persistence.VariableReferenceRecord do
  @moduledoc """
  Writable Project record used by reference repair and exact reconstitution.
  Ordinary tool writers keep their own reference models and invariants.
  """

  use Ecto.Schema

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
