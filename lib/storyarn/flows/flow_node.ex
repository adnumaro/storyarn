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
  alias Storyarn.Flows.SequenceTrack
  alias Storyarn.Flows.SequenceVisualLayer
  alias Storyarn.Localization.RuntimeKey
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
          sequence_tracks: [SequenceTrack.t()] | NotLoaded.t(),
          sequence_visual_layers: [SequenceVisualLayer.t()] | NotLoaded.t(),
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
    has_many :sequence_tracks, SequenceTrack, foreign_key: :flow_node_id
    has_many :sequence_visual_layers, SequenceVisualLayer, foreign_key: :flow_node_id
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
    attrs = ensure_dialogue_runtime_ids(attrs, nil)

    node
    |> cast(attrs, [:type, :position_x, :position_y, :data, :source, :parent_id])
    |> validate_required([:type])
    |> validate_inclusion(:type, @node_types)
    |> validate_inclusion(:source, @valid_sources)
    |> validate_dialogue_runtime_ids()
    |> dialogue_localization_id_constraint()
    |> foreign_key_constraint(:flow_id)
    |> foreign_key_constraint(:parent_id)
  end

  @doc "Strict changeset for materializing a node from a current snapshot."
  def materialize_changeset(node, attrs) do
    node
    |> cast(attrs, [:type, :position_x, :position_y, :data, :word_count, :source, :parent_id])
    |> validate_required([:type])
    |> validate_inclusion(:type, @node_types)
    |> validate_inclusion(:source, @valid_sources)
    |> validate_dialogue_runtime_ids()
    |> dialogue_localization_id_constraint()
    |> foreign_key_constraint(:flow_id)
    |> foreign_key_constraint(:parent_id)
  end

  @doc """
  Changeset for updating a node.
  """
  def update_changeset(node, attrs) do
    attrs = ensure_dialogue_runtime_ids(attrs, node)

    node
    |> cast(attrs, [:type, :position_x, :position_y, :data, :parent_id])
    |> validate_required([:type])
    |> validate_inclusion(:type, @node_types)
    |> validate_dialogue_runtime_ids()
    |> dialogue_localization_id_constraint()
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
    attrs = ensure_dialogue_runtime_ids(attrs, node)

    node
    |> cast(attrs, [:data])
    |> validate_dialogue_runtime_ids()
    |> dialogue_localization_id_constraint()
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
    node
    |> change(deleted_at: nil)
    |> validate_dialogue_runtime_ids()
    |> dialogue_localization_id_constraint()
  end

  defp ensure_dialogue_runtime_ids(attrs, node) when is_map(attrs) do
    type = attr(attrs, :type) || (node && node.type)
    data = attr(attrs, :data) || existing_data(node)

    if type == "dialogue" and is_map(data) do
      put_attr(attrs, :data, normalize_dialogue_runtime_ids(data, existing_localization_id(node)))
    else
      attrs
    end
  end

  defp normalize_dialogue_runtime_ids(data, existing_id) do
    data
    |> ensure_localization_id(existing_id)
    |> ensure_response_ids()
  end

  defp ensure_localization_id(data, existing_id) do
    case map_value(data, "localization_id") do
      value when value not in [nil, ""] -> put_string_key(data, "localization_id", value)
      _missing -> put_string_key(data, "localization_id", reusable_id(existing_id, &RuntimeKey.new_dialogue_id/0))
    end
  end

  defp ensure_response_ids(data) do
    case map_value(data, "responses") do
      responses when is_list(responses) ->
        responses = Enum.map(responses, &ensure_response_id/1)
        put_string_key(data, "responses", responses)

      missing_or_invalid ->
        if map_has_key?(data, "responses"),
          do: put_string_key(data, "responses", missing_or_invalid),
          else: data
    end
  end

  defp ensure_response_id(response) when is_map(response) do
    case map_value(response, "id") do
      value when value not in [nil, ""] -> put_string_key(response, "id", value)
      _missing -> put_string_key(response, "id", RuntimeKey.new_response_id())
    end
  end

  defp ensure_response_id(response), do: response

  defp reusable_id(existing_id, generator) do
    if RuntimeKey.valid_dialogue_id?(existing_id), do: existing_id, else: generator.()
  end

  defp existing_localization_id(%__MODULE__{data: data}) when is_map(data), do: data["localization_id"]
  defp existing_localization_id(_node), do: nil

  defp existing_data(%__MODULE__{data: data}) when is_map(data), do: data
  defp existing_data(_node), do: %{}

  defp validate_dialogue_runtime_ids(changeset) do
    if get_field(changeset, :type) == "dialogue" do
      data = get_field(changeset, :data) || %{}
      changeset |> validate_localization_id(data) |> validate_response_ids(data)
    else
      changeset
    end
  end

  defp validate_localization_id(changeset, data) do
    if RuntimeKey.valid_dialogue_id?(data["localization_id"]) do
      changeset
    else
      add_error(changeset, :data, "must contain a valid localization_id")
    end
  end

  defp validate_response_ids(changeset, data) do
    responses = data["responses"] || []

    if is_list(responses) do
      ids =
        Enum.map(responses, fn
          response when is_map(response) -> response["id"]
          _response -> nil
        end)

      cond do
        not Enum.all?(ids, &RuntimeKey.valid_response_id?/1) ->
          add_error(changeset, :data, "every response must contain a valid id")

        length(ids) != length(Enum.uniq(ids)) ->
          add_error(changeset, :data, "response ids must be unique")

        true ->
          changeset
      end
    else
      add_error(changeset, :data, "responses must be a list")
    end
  end

  defp dialogue_localization_id_constraint(changeset) do
    unique_constraint(changeset, :data,
      name: :flow_nodes_dialogue_localization_id_unique,
      message: "localization_id must be unique within the project"
    )
  end

  defp attr(attrs, field), do: Map.get(attrs, field, Map.get(attrs, to_string(field)))

  defp map_value(map, key), do: Map.get(map, key, Map.get(map, atom_key(key)))

  defp map_has_key?(map, key), do: Map.has_key?(map, key) or Map.has_key?(map, atom_key(key))

  defp put_string_key(map, key, value) do
    map
    |> Map.delete(atom_key(key))
    |> Map.put(key, value)
  end

  defp atom_key("localization_id"), do: :localization_id
  defp atom_key("responses"), do: :responses
  defp atom_key("id"), do: :id

  defp put_attr(attrs, field, value) do
    cond do
      Map.has_key?(attrs, field) -> Map.put(attrs, field, value)
      Map.has_key?(attrs, to_string(field)) -> Map.put(attrs, to_string(field), value)
      Enum.any?(Map.keys(attrs), &is_atom/1) -> Map.put(attrs, field, value)
      true -> Map.put(attrs, to_string(field), value)
    end
  end
end
