defmodule Storyarn.Flows.FlowNode do
  @moduledoc """
  Schema for flow nodes.

  A flow node represents a single element in the flow graph, such as a
  dialogue, hub, condition, instruction, jump, or sequence container.
  Each node has a type, position on the canvas, and type-specific data.

  ## Node Types

  - `entry` - Entry point of the flow (exactly one per flow, output only)
  - `exit` - Exit point of the flow (multiple allowed, input only)
  - `dialogue` - A dialogue block with speaker, text, and optional choices
  - `hub` - A central point connecting multiple paths
  - `condition` - A branching point based on game state or variables
  - `instruction` - An action to execute (set variable, trigger event, etc.)
  - `jump` - A reference to another flow or node
  - `subflow` - A reference to an embedded flow
  - `annotation` - A pure-visual note on the canvas
  - `sequence` - A container that groups child nodes; nests via `parent_id`

  ## Hierarchy

  `parent_id` is a self-FK: every flow_node can have a single parent, and
  only `type='sequence'` rows are valid parents. This is enforced by a
  DB trigger. Non-sequence nodes have `has_many :children`, which
  conceptually only makes sense for sequence-type rows but is exposed
  uniformly.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Ecto.Association.NotLoaded
  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowConnection
  alias Storyarn.Flows.SequenceConfig
  alias Storyarn.Shared.TimeHelpers

  @node_types ~w(annotation dialogue hub condition instruction jump entry exit subflow sequence)
  @valid_sources ~w(manual screenplay_sync)

  @type node_type ::
          :annotation
          | :dialogue
          | :hub
          | :condition
          | :instruction
          | :jump
          | :entry
          | :exit
          | :subflow
          | :sequence
  @type t :: %__MODULE__{
          id: integer() | nil,
          type: String.t() | nil,
          position_x: float(),
          position_y: float(),
          data: map(),
          source: String.t(),
          deleted_at: DateTime.t() | nil,
          flow_id: integer() | nil,
          flow: Flow.t() | NotLoaded.t() | nil,
          parent_id: integer() | nil,
          parent: t() | NotLoaded.t() | nil,
          children: [t()] | NotLoaded.t(),
          sequence_config: SequenceConfig.t() | NotLoaded.t() | nil,
          outgoing_connections: [FlowConnection.t()] | NotLoaded.t(),
          incoming_connections: [FlowConnection.t()] | NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "flow_nodes" do
    field :type, :string
    field :position_x, :float, default: 0.0
    field :position_y, :float, default: 0.0
    field :data, :map, default: %{}
    field :word_count, :integer, default: 0
    field :source, :string, default: "manual"
    field :deleted_at, :utc_datetime

    belongs_to :flow, Flow
    belongs_to :parent, __MODULE__, foreign_key: :parent_id
    has_many :children, __MODULE__, foreign_key: :parent_id
    has_one :sequence_config, SequenceConfig, foreign_key: :flow_node_id
    has_many :outgoing_connections, FlowConnection, foreign_key: :source_node_id
    has_many :incoming_connections, FlowConnection, foreign_key: :target_node_id

    timestamps(type: :utc_datetime)
  end

  @doc """
  Returns the list of valid node types.
  """
  def node_types, do: @node_types

  @doc """
  Changeset for creating a new node.
  """
  def create_changeset(node, attrs) do
    node
    |> cast(attrs, [:type, :position_x, :position_y, :data, :source, :parent_id])
    |> validate_required([:type])
    |> validate_inclusion(:type, @node_types)
    |> validate_inclusion(:source, @valid_sources)
    |> foreign_key_constraint(:flow_id)
    |> foreign_key_constraint(:parent_id)
  end

  @doc """
  Changeset for updating a node.
  """
  def update_changeset(node, attrs) do
    node
    |> cast(attrs, [:type, :position_x, :position_y, :data, :parent_id])
    |> validate_required([:type])
    |> validate_inclusion(:type, @node_types)
    |> foreign_key_constraint(:parent_id)
  end

  @doc """
  Changeset for updating only the position of a node.
  Used for drag operations on the canvas.
  """
  def position_changeset(node, attrs) do
    node
    |> cast(attrs, [:position_x, :position_y])
    |> validate_required([:position_x, :position_y])
  end

  @doc """
  Changeset scoped to only reparenting. Accepts `parent_id` (may be nil
  for root-level). Used by canvas drag-reparent + context-menu "Remove
  from sequence" operations — intentionally narrow so the handler can't
  accidentally mutate position/data/type through the same code path.
  The `trg_flow_nodes_validate_parent_is_sequence` DB trigger enforces
  that the target references a sequence-typed row.
  """
  def reparent_changeset(node, attrs) do
    node
    |> cast(attrs, [:parent_id])
    |> foreign_key_constraint(:parent_id)
  end

  @doc """
  Changeset for updating only the data of a node.
  Used for editing node properties.
  """
  def data_changeset(node, attrs) do
    cast(node, attrs, [:data])
  end

  @doc """
  Changeset for soft-deleting a node by setting deleted_at.
  """
  def soft_delete_changeset(node) do
    change(node, deleted_at: TimeHelpers.now())
  end

  @doc """
  Changeset for restoring a soft-deleted node by clearing deleted_at.
  """
  def restore_changeset(node) do
    change(node, deleted_at: nil)
  end
end
