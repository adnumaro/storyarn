defmodule Storyarn.Flows.Sequence do
  @moduledoc """
  Schema for flow sequences.

  A Sequence is a grouping of flow nodes with a shared atmosphere expressed as
  a multi-track timeline of 3 tracks: `background` (image asset), `music`
  (audio asset), and `ambient` (audio asset). Nodes become members of a
  Sequence via a `sequence_directive` pointer in their data — the directive
  marks the Sequence entry point; downstream nodes inherit it at runtime by
  walking back along the actual execution path.

  v1 deliberately omits video, effects, overlays, and SFX tracks. Those can
  be layered in later iterations once the minimum ships and gets use.

  Not to be confused with `Storyarn.Scenes.Scene`, which is the walkable 2D
  canvas entity used by the ExplorationPlayer. Different shapes, different
  consumers. See docs/features/flow-player-redesign/OVERVIEW.md.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Ecto.Association.NotLoaded
  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Shared.TimeHelpers

  @track_keys ~w(background music ambient)

  @type t :: %__MODULE__{
          id: integer() | nil,
          name: String.t() | nil,
          tracks: map(),
          deleted_at: DateTime.t() | nil,
          flow_id: integer() | nil,
          flow: Flow.t() | NotLoaded.t() | nil,
          start_node_id: integer() | nil,
          start_node: FlowNode.t() | NotLoaded.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "flow_sequences" do
    field :name, :string
    field :tracks, :map, default: %{}
    field :deleted_at, :utc_datetime

    belongs_to :flow, Flow
    belongs_to :start_node, FlowNode

    timestamps(type: :utc_datetime)
  end

  @doc """
  Returns the 3 fixed track keys: `background`, `music`, `ambient`.
  """
  @spec track_keys() :: [String.t()]
  def track_keys, do: @track_keys

  @doc """
  Returns an empty tracks map with all 3 fixed keys initialized to empty lists.
  Use this when creating a new Sequence.
  """
  @spec empty_tracks() :: map()
  def empty_tracks, do: Map.new(@track_keys, &{&1, []})

  @doc """
  Changeset for creating a new sequence.
  """
  def create_changeset(sequence, attrs) do
    sequence
    |> cast(attrs, [:name, :tracks, :flow_id, :start_node_id])
    |> validate_required([:name, :flow_id, :start_node_id])
    |> validate_length(:name, min: 1, max: 200)
    |> foreign_key_constraint(:flow_id)
    |> foreign_key_constraint(:start_node_id)
  end

  @doc """
  Changeset for updating an existing sequence. `flow_id` and `start_node_id`
  are immutable — to move a sequence, delete and recreate.
  """
  def update_changeset(sequence, attrs) do
    sequence
    |> cast(attrs, [:name, :tracks])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 200)
  end

  @doc """
  Soft-delete by setting `deleted_at`.
  """
  def soft_delete_changeset(sequence) do
    change(sequence, deleted_at: TimeHelpers.now())
  end

  @doc """
  Restore a soft-deleted sequence.
  """
  def restore_changeset(sequence) do
    change(sequence, deleted_at: nil)
  end
end
