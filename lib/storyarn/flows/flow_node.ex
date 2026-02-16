defmodule Storyarn.Flows.FlowNode do
  @moduledoc """
  Schema for flow nodes.

  A flow node represents a single element in the flow graph, such as a dialogue,
  hub, condition, instruction, or jump. Each node has a type, position on the
  canvas, and type-specific data.

  ## Node Types

  - `entry` - Entry point of the flow (exactly one per flow, output only)
  - `exit` - Exit point of the flow (multiple allowed, input only)
  - `dialogue` - A dialogue block with speaker, text, and optional choices
  - `hub` - A central point connecting multiple paths
  - `condition` - A branching point based on game state or variables
  - `instruction` - An action to execute (set variable, trigger event, etc.)
  - `jump` - A reference to another flow or node
  - `scene` - A scene break establishing location and time context
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Storyarn.Flows.{Flow, FlowConnection}

  @node_types ~w(dialogue hub condition instruction jump entry exit subflow scene)
  @valid_sources ~w(manual screenplay_sync)

  @type node_type ::
          :dialogue
          | :hub
          | :condition
          | :instruction
          | :jump
          | :entry
          | :exit
          | :subflow
          | :scene
  @type t :: %__MODULE__{
          id: integer() | nil,
          type: String.t() | nil,
          position_x: float(),
          position_y: float(),
          data: map(),
          source: String.t(),
          deleted_at: DateTime.t() | nil,
          flow_id: integer() | nil,
          flow: Flow.t() | Ecto.Association.NotLoaded.t() | nil,
          outgoing_connections: [FlowConnection.t()] | Ecto.Association.NotLoaded.t(),
          incoming_connections: [FlowConnection.t()] | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "flow_nodes" do
    field :type, :string
    field :position_x, :float, default: 0.0
    field :position_y, :float, default: 0.0
    field :data, :map, default: %{}
    field :source, :string, default: "manual"
    field :deleted_at, :utc_datetime

    belongs_to :flow, Flow
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
    |> cast(attrs, [:type, :position_x, :position_y, :data, :source])
    |> validate_required([:type])
    |> validate_inclusion(:type, @node_types)
    |> validate_inclusion(:source, @valid_sources)
  end

  @doc """
  Changeset for updating a node.
  """
  def update_changeset(node, attrs) do
    node
    |> cast(attrs, [:type, :position_x, :position_y, :data])
    |> validate_required([:type])
    |> validate_inclusion(:type, @node_types)
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
  Changeset for updating only the data of a node.
  Used for editing node properties.
  """
  def data_changeset(node, attrs) do
    node
    |> cast(attrs, [:data])
  end

  @doc """
  Changeset for soft-deleting a node by setting deleted_at.
  """
  def soft_delete_changeset(node) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    change(node, deleted_at: now)
  end

  @doc """
  Changeset for restoring a soft-deleted node by clearing deleted_at.
  """
  def restore_changeset(node) do
    change(node, deleted_at: nil)
  end
end
