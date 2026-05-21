defmodule Storyarn.Flows.SequenceConfig do
  @moduledoc """
  Per-sequence configuration. 1:1 with `Storyarn.Flows.FlowNode` where
  `type='sequence'`.

  Sequences are flow_nodes rows with `type='sequence'`; this table holds
  the fields that are specific to sequences and don't apply to other node
  types:

    * `name` — display label.
    * `width` / `height` — container bounds on the canvas.

  The `flow_node_id` is both the primary key and the foreign key to
  `flow_nodes(id)`. A DB trigger enforces that the referenced flow_node
  has `type='sequence'`.

  Visual composition lives in the separate
  `flow_node_sequence_visual_layers` table (schema
  `Storyarn.Flows.SequenceVisualLayer`).

  Audio tracks live in the separate `flow_node_sequence_tracks` table
  (schema `Storyarn.Flows.SequenceTrack`). See its moduledoc for
  rationale.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Ecto.Association.NotLoaded
  alias Storyarn.Flows.FlowNode

  @type t :: %__MODULE__{
          flow_node_id: integer() | nil,
          flow_node: FlowNode.t() | NotLoaded.t() | nil,
          name: String.t() | nil,
          width: float(),
          height: float(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @primary_key false
  schema "flow_node_sequence_configs" do
    belongs_to :flow_node, FlowNode, primary_key: true

    field :name, :string
    field :width, :float, default: 300.0
    field :height, :float, default: 200.0

    timestamps(type: :utc_datetime)
  end

  @doc "Changeset for creating a new sequence config."
  def create_changeset(sequence_config, attrs) do
    sequence_config
    |> cast(attrs, [:flow_node_id, :name, :width, :height])
    |> validate_required([:flow_node_id, :name])
    |> validate_length(:name, min: 1, max: 200)
    |> foreign_key_constraint(:flow_node_id)
  end

  @doc """
  Changeset for updating an existing sequence config. `flow_node_id` is
  immutable.
  """
  def update_changeset(sequence_config, attrs) do
    sequence_config
    |> cast(attrs, [:name, :width, :height])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 200)
  end
end
