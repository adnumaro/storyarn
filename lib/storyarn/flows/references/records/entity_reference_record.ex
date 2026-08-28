defmodule Storyarn.Flows.References.Projections.EntityReferenceRecord do
  @moduledoc "Consumer-owned writable record for the cross-entity reference index maintained by Flows."

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "entity_references" do
    field :source_type, :string
    field :source_id, :id
    field :target_type, :string
    field :target_id, :id
    field :context, :string

    timestamps()
  end
end
