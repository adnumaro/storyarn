defmodule Storyarn.Sheets.References.Entities.EntityReferenceRecord do
  @moduledoc """
  Consumer-local projection of the shared entity-reference index used by Sheets.

  Used to build backlinks: "What references this sheet/flow?"

  ## Source Types
  - "block" - A block in a sheet (e.g., reference block, mention in rich_text)
  - "flow_node" - A node in a flow (e.g., speaker reference, mention in dialogue)
  - "scene_pin" / "scene_zone" - Interactive elements in a scene

  ## Target Types
  - "sheet" - Reference to a sheet
  - "flow" - Reference to a flow
  - "scene" - Reference to a scene

  The record is intentionally local to the References capability: its fields
  and lifecycle can evolve with Sheet backlink and integrity workflows without
  importing another bounded context's schema.

  ## Context
  The context field identifies where in the source the reference was found:
  - For blocks: the block_id
  - For flow nodes: the node_id and field (e.g., "speaker", "content")
  """

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @source_types ~w(block flow_node scene_pin scene_zone)
  @target_types ~w(sheet flow scene)

  schema "entity_references" do
    field :source_type, :string
    field :source_id, :id
    field :target_type, :string
    field :target_id, :id
    field :context, :string

    timestamps()
  end

  @doc false
  def changeset(entity_reference, attrs) do
    entity_reference
    |> cast(attrs, [:source_type, :source_id, :target_type, :target_id, :context])
    |> validate_required([:source_type, :source_id, :target_type, :target_id])
    |> validate_inclusion(:source_type, @source_types)
    |> validate_inclusion(:target_type, @target_types)
    |> unique_constraint([:source_type, :source_id, :target_type, :target_id, :context],
      name: :entity_references_unique
    )
  end
end
