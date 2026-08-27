defmodule Storyarn.Scenes.References.Projections.VariableReferenceRecord do
  @moduledoc "References-owned consumer-local SQL projection used to validate and maintain Scene reference indexes."

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
