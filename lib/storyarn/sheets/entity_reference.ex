defmodule Storyarn.Sheets.EntityReference do
  @moduledoc """
  Schema for tracking references between entities (sheets, flows).

  Used to build backlinks: "What references this sheet/flow?"

  ## Source Types
  - "block" - A block in a sheet (e.g., reference block, mention in rich_text)
  - "flow_node" - A node in a flow (e.g., speaker reference, mention in dialogue)
  - "screenplay_element" - An element in a screenplay (e.g., character sheet ref, inline mention)

  ## Target Types
  - "sheet" - Reference to a sheet
  - "flow" - Reference to a flow

  ## Context
  The context field identifies where in the source the reference was found:
  - For blocks: the block_id
  - For flow nodes: the node_id and field (e.g., "speaker", "content")
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @source_types ~w(block flow_node screenplay_element map_pin map_zone)
  @target_types ~w(sheet flow)

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
