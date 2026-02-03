defmodule Storyarn.Pages.EntityReference do
  @moduledoc """
  Schema for tracking references between entities (pages, flows).

  Used to build backlinks: "What references this page/flow?"

  ## Source Types
  - "block" - A block in a page (e.g., reference block, mention in rich_text)
  - "flow_node" - A node in a flow (e.g., speaker reference, mention in dialogue)

  ## Target Types
  - "page" - Reference to a page
  - "flow" - Reference to a flow

  ## Context
  The context field identifies where in the source the reference was found:
  - For blocks: the block_id
  - For flow nodes: the node_id and field (e.g., "speaker", "content")
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @source_types ~w(block flow_node)
  @target_types ~w(page flow)

  schema "entity_references" do
    field :source_type, :string
    field :source_id, Ecto.UUID
    field :target_type, :string
    field :target_id, Ecto.UUID
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
