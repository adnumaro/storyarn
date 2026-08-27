defmodule Storyarn.Scenes.References.Projections.EntityReferenceRecord do
  @moduledoc "References-owned writable SQL record used to validate and maintain Scene reference indexes."

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
