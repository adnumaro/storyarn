defmodule Storyarn.Screenplays.ScreenplayElement do
  @moduledoc """
  Schema for screenplay elements (blocks).

  Each element represents a block in the screenplay editor: scene headings,
  action lines, character names, dialogue, etc. Elements are ordered by
  `position` within their screenplay.

  ## Element Types

  **Standard screenplay types:**
  - `scene_heading` - INT./EXT. location lines
  - `action` - Narrative description
  - `character` - Character name (ALL CAPS)
  - `dialogue` - Spoken text
  - `parenthetical` - Acting direction
  - `transition` - CUT TO:, FADE IN:, etc.
  - `dual_dialogue` - Two speakers simultaneously

  **Interactive types (map to flow nodes):**
  - `conditional` - Branch based on variable
  - `instruction` - Modify a variable
  - `response` - Player choices

  **Flow navigation markers (round-trip safe):**
  - `hub_marker` - Preserves hub data for sync
  - `jump_marker` - Preserves jump target data for sync

  **Utility types (no flow mapping):**
  - `note` - Writer's note (not exported)
  - `section` - Outline header
  - `page_break` - Force page break
  - `title_page` - Title page metadata

  ## Nesting

  The `depth` and `branch` fields support nesting inside conditional blocks.
  Dialogue groups are computed from adjacency — no stored group_id (Edge Case F).
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Storyarn.Flows.FlowNode
  alias Storyarn.Screenplays.Screenplay

  @element_types ~w(
    scene_heading action character dialogue parenthetical
    transition dual_dialogue conditional instruction response
    hub_marker jump_marker
    note section page_break title_page
  )

  @standard_types ~w(scene_heading action character dialogue parenthetical transition dual_dialogue note section page_break title_page)
  @interactive_types ~w(conditional instruction response)
  @flow_marker_types ~w(hub_marker jump_marker)
  @dialogue_group_types ~w(character dialogue parenthetical)
  @non_mappeable_types ~w(note section page_break title_page)
  @valid_branches [nil, "true", "false"]

  @type t :: %__MODULE__{
          id: integer() | nil,
          type: String.t() | nil,
          position: integer(),
          content: String.t(),
          data: map(),
          depth: integer(),
          branch: String.t() | nil,
          screenplay_id: integer() | nil,
          screenplay: Screenplay.t() | Ecto.Association.NotLoaded.t() | nil,
          linked_node_id: integer() | nil,
          linked_node: FlowNode.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "screenplay_elements" do
    field :type, :string
    field :position, :integer, default: 0
    field :content, :string, default: ""
    field :data, :map, default: %{}
    field :depth, :integer, default: 0
    field :branch, :string

    belongs_to :screenplay, Screenplay
    belongs_to :linked_node, FlowNode

    timestamps(type: :utc_datetime)
  end

  @doc "Returns all valid element types."
  def types, do: @element_types

  @doc "Standard screenplay element types (text-based, no special flow mapping)."
  def standard_types, do: @standard_types

  @doc "Interactive types that map to flow nodes (condition, instruction, response)."
  def interactive_types, do: @interactive_types

  @doc "Flow navigation markers preserved for round-trip sync (Edge Case D)."
  def flow_marker_types, do: @flow_marker_types

  @doc "Types that form dialogue groups when adjacent (character, dialogue, parenthetical)."
  def dialogue_group_types, do: @dialogue_group_types

  @doc "Types with no flow mapping, preserved during sync_from_flow (Edge Case C)."
  def non_mappeable_types, do: @non_mappeable_types

  @doc """
  Changeset for creating a new element.
  """
  def create_changeset(element, attrs) do
    element
    |> cast(attrs, [:type, :position, :content, :data, :depth, :branch])
    |> validate_required([:type])
    |> validate_inclusion(:type, @element_types)
    |> validate_number(:position, greater_than_or_equal_to: 0)
    |> validate_number(:depth, greater_than_or_equal_to: 0)
    |> validate_inclusion(:branch, @valid_branches)
  end

  @doc """
  Changeset for updating an element's content and metadata.
  """
  def update_changeset(element, attrs) do
    element
    |> cast(attrs, [:type, :content, :data, :depth, :branch])
    |> validate_inclusion(:type, @element_types)
    |> validate_number(:depth, greater_than_or_equal_to: 0)
    |> validate_inclusion(:branch, @valid_branches)
  end

  @doc """
  Changeset for updating only the position.
  """
  def position_changeset(element, attrs) do
    element
    |> cast(attrs, [:position])
    |> validate_required([:position])
    |> validate_number(:position, greater_than_or_equal_to: 0)
  end

  @doc """
  Changeset for linking/unlinking a flow node.
  """
  def link_node_changeset(element, attrs) do
    element
    |> cast(attrs, [:linked_node_id])
    |> foreign_key_constraint(:linked_node_id)
  end
end
