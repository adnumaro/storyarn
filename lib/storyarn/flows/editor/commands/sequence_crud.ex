defmodule Storyarn.Flows.SequenceCrud do
  @moduledoc """
  CRUD for sequence-type flow_nodes.

  Sequences are `flow_nodes` rows with `type='sequence'`. They group
  other flow_nodes on the canvas via `FlowNode.parent_id` (self-FK,
  `nilify_all`). Sequence-specific fields (name, canvas dimensions) live
  in `flow_node_sequence_configs` 1:1 with the flow_node.

  Soft-delete is supported via `deleted_at` on the flow_node row. A DB
  trigger nilifies `parent_id` on children when a sequence is
  soft-deleted — children orphan rather than cascade.

  Static visual layers and audio tracks may be owned by either a sequence or
  dialogue node. They compose through `composition_source_id`, independently
  from canvas hierarchy, using logical keys and property-level override masks.
  """

  import Ecto.Query

  alias Storyarn.Flows.Editor.Commands.ItemCapacity
  alias Storyarn.Flows.Editor.Projections.AssetRecord
  alias Storyarn.Flows.Editor.Queries.Sequences
  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.NodeCrud
  alias Storyarn.Flows.NodeDelete
  alias Storyarn.Flows.NodeTypes
  alias Storyarn.Flows.References
  alias Storyarn.Flows.SequenceCompositionIntegrity
  alias Storyarn.Flows.SequenceConfig
  alias Storyarn.Flows.SequenceTrack
  alias Storyarn.Flows.SequenceVisualLayer
  alias Storyarn.Platform.Collaboration
  alias Storyarn.Repo

  @type sequence :: FlowNode.t()

  @visual_layer_copy_fields [
    :asset_id,
    :layer_key,
    :overridden_fields,
    :removed,
    :kind,
    :label,
    :z_index,
    :slot,
    :x,
    :y,
    :width,
    :height,
    :anchor_x,
    :anchor_y,
    :fit,
    :opacity,
    :visible
  ]
  @track_copy_fields [
    :track_key,
    :is_override,
    :overridden_fields,
    :removed,
    :kind,
    :position,
    :asset_id,
    :start_time,
    :end_time,
    :volume
  ]

  @doc """
  Lists active (non-deleted) sequences for a flow, ordered by insertion
  time, with `sequence_config` preloaded.
  """
  @spec list_sequences(integer()) :: [sequence()]
  defdelegate list_sequences(flow_id), to: Sequences, as: :list

  @doc """
  Lists soft-deleted sequences for a flow (for trash/restore UIs).
  """
  @spec list_deleted(integer()) :: [sequence()]
  def list_deleted(flow_id), do: Sequences.list(flow_id, true)

  @doc """
  Fetches an active sequence by id scoped to a flow. Returns nil if
  absent, soft-deleted, or not a sequence.
  """
  @spec get_sequence(integer(), integer()) :: sequence() | nil
  defdelegate get_sequence(flow_id, id), to: Sequences, as: :get

  @doc """
  Fetches a sequence by id scoped to a flow. Raises if absent.
  """
  @spec get_sequence!(integer(), integer()) :: sequence()
  defdelegate get_sequence!(flow_id, id), to: Sequences, as: :get!

  @doc "Gets the sequence-specific configuration for an active sequence node."
  @spec get_sequence_config(integer()) :: SequenceConfig.t() | nil
  defdelegate get_sequence_config(sequence_id), to: Sequences, as: :get_config

  @doc """
  Creates a sequence (flow_node + sequence_config) atomically.

  `attrs` may include: `:name` (required), `:position_x`, `:position_y`,
  `:width`, `:height`, `:parent_id`.
  """
  @spec create_sequence(integer(), map()) ::
          {:ok, sequence()} | {:error, Ecto.Changeset.t()}
  def create_sequence(flow_id, attrs) do
    attrs = normalize_keys(attrs)

    fn -> create_sequence_in_transaction(flow_id, attrs) end
    |> Repo.transaction()
    |> broadcast_sequence_result()
  end

  defp create_sequence_in_transaction(flow_id, attrs) do
    node_attrs = %{
      "type" => "sequence",
      "position_x" => Map.get(attrs, "position_x", 0.0),
      "position_y" => Map.get(attrs, "position_y", 0.0),
      "parent_id" => Map.get(attrs, "parent_id")
    }

    config_attrs = %{
      "name" => Map.get(attrs, "name"),
      "width" => Map.get(attrs, "width", 300.0),
      "height" => Map.get(attrs, "height", 200.0)
    }

    with {:ok, %{flow: flow, project_id: project_id}} <-
           References.lock_active_flow_for_write(flow_id),
         {:ok, parent_id} <-
           References.lock_node_parent(flow.id, node_attrs["parent_id"]),
         node_attrs = Map.put(node_attrs, "parent_id", parent_id),
         {:ok, node} <-
           %FlowNode{flow_id: flow_id}
           |> FlowNode.create_changeset(node_attrs)
           |> Repo.insert(),
         {:ok, config} <-
           %SequenceConfig{}
           |> SequenceConfig.create_changeset(Map.put(config_attrs, "flow_node_id", node.id))
           |> Repo.insert() do
      {%{node | sequence_config: config}, project_id}
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  @doc """
  Updates a sequence's name/width/height (on sequence_config) and/or
  position/parent_id (on flow_node). Accepts a sequence struct
  (preloaded or not — config is loaded on demand if needed). `flow_id`
  and `type` are immutable.
  """
  @spec update_sequence(sequence(), map()) ::
          {:ok, sequence()} | {:error, Ecto.Changeset.t()}
  def update_sequence(%FlowNode{type: "sequence"} = node, attrs) do
    attrs = normalize_keys(attrs)
    node_attrs = Map.take(attrs, ["position_x", "position_y", "parent_id"])

    config_attrs =
      Map.take(attrs, ["name", "width", "height"])

    Repo.transaction(fn ->
      with {:ok, %{flow: flow, node: locked_node}} <-
             References.lock_active_node_for_write(node),
           :ok <- ensure_sequence(locked_node),
           parent_id = Map.get(node_attrs, "parent_id", locked_node.parent_id),
           {:ok, parent_id} <-
             References.lock_node_parent(
               flow.id,
               parent_id,
               locked_node.id
             ) do
        node_attrs = put_normalized_parent_id(node_attrs, parent_id)

        updated_node = update_sequence_node(locked_node, node_attrs)
        updated_config = update_sequence_config(locked_node, config_attrs)

        %{updated_node | sequence_config: updated_config}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Soft-deletes a sequence (its flow_node row). A DB trigger nilifies
  `parent_id` on all children when `deleted_at` transitions to non-null.
  """
  @spec delete_sequence(sequence()) :: {:ok, sequence()} | {:error, Ecto.Changeset.t()}
  def delete_sequence(%FlowNode{type: "sequence"} = node) do
    fn ->
      with {:ok, %{node: locked_node, project_id: project_id}} <-
             References.lock_active_node_for_write(node),
           :ok <- ensure_sequence(locked_node),
           :ok <- NodeDelete.validate_and_lock_no_active_composition_dependents(locked_node),
           {:ok, deleted_node} <-
             locked_node
             |> FlowNode.soft_delete_changeset()
             |> Repo.update() do
        {deleted_node, project_id}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end
    |> Repo.transaction()
    |> broadcast_sequence_result()
  end

  @doc """
  Restores a soft-deleted sequence by clearing `deleted_at`. Children
  previously nilified are NOT re-attached — the user must re-parent
  them manually.
  """
  @spec restore_sequence(sequence()) :: {:ok, sequence()} | {:error, term()}
  def restore_sequence(%FlowNode{id: node_id, type: "sequence"}) when is_integer(node_id) do
    fn ->
      flow_id =
        Repo.one(
          from(node in FlowNode,
            where: node.id == ^node_id and node.type == "sequence",
            select: node.flow_id
          )
        ) || Repo.rollback(:sequence_not_found)

      with {:ok, %{flow: flow, project_id: project_id}} <-
             References.lock_active_flow_for_write(flow_id),
           %FlowNode{} = locked_node <-
             Repo.one(
               from(node in FlowNode,
                 where:
                   node.id == ^node_id and node.flow_id == ^flow.id and
                     node.type == "sequence" and not is_nil(node.deleted_at),
                 lock: "FOR UPDATE"
               )
             ),
           :ok <- NodeDelete.validate_and_lock_active_composition_source(locked_node),
           :ok <-
             References.lock_active_asset_references_for_restore(project_id,
               flow_node_ids: [locked_node.id]
             ),
           {:ok, restored_node} <-
             locked_node
             |> FlowNode.restore_changeset()
             |> Repo.update() do
        {restored_node, project_id}
      else
        nil -> Repo.rollback(:sequence_not_deleted)
        {:error, reason} -> Repo.rollback(reason)
      end
    end
    |> Repo.transaction()
    |> broadcast_sequence_result()
  end

  @doc """
  Atomically wraps a selection of flow_nodes into a new sequence.

  Validations (fail-fast, no side effects on error):
    * `node_ids` non-empty (1 or more).
    * Every node exists, is active, and belongs to `flow`.
    * All nodes share the same `parent_id` — otherwise `{:error,
      :mixed_parents}`. The new sequence inherits that common parent.

  `attrs` may include `:name`, `:position_x`, `:position_y`, `:width`,
  `:height`. Missing name defaults to `"Sequence"`.

  Returns `{:ok, sequence}` (a FlowNode with sequence_config set), or
  `{:error, reason}` where reason is one of: `:empty_selection`,
  `:nodes_not_found`, `:mixed_parents`, or an `Ecto.Changeset`.
  """
  @spec wrap_selection_in_sequence(Flow.t(), [integer()], map()) ::
          {:ok, sequence()} | {:error, atom() | Ecto.Changeset.t()}
  def wrap_selection_in_sequence(flow, node_ids, attrs \\ %{})

  def wrap_selection_in_sequence(%Flow{}, [], _attrs), do: {:error, :empty_selection}

  def wrap_selection_in_sequence(%Flow{id: flow_id}, node_ids, attrs) when is_list(node_ids) do
    fn ->
      with {:ok, %{flow: locked_flow, project_id: project_id}} <-
             References.lock_active_flow_for_write(flow_id),
           {:ok, nodes} <- load_active_nodes(locked_flow.id, node_ids),
           {:ok, parent_id} <- common_parent_id(nodes),
           attrs = build_wrap_attrs(attrs, parent_id),
           {sequence, ^project_id} <- create_sequence_in_transaction(locked_flow.id, attrs),
           :ok <- assign_nodes_to_sequence(nodes, sequence.id) do
        {sequence, project_id}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end
    |> Repo.transaction()
    |> broadcast_sequence_result()
  end

  @doc """
  Atomically duplicates a dialogue or sequence together with its local static
  composition.

  The duplicate keeps the original canvas parent and explicit composition
  source. Sequence configuration, visual-layer definitions and patches,
  tombstones, and audio tracks are copied exactly. The new node is offset by
  50 pixels and dialogue runtime identity is regenerated through the standard
  duplicate-data rule.
  """
  @spec duplicate_composition_owner(Flow.t(), FlowNode.t()) ::
          {:ok, FlowNode.t()} | {:error, term()} | {:error, :limit_reached, map()}
  def duplicate_composition_owner(%Flow{} = flow, %FlowNode{id: source_id}) when is_integer(source_id) do
    fn -> duplicate_composition_owner_in_transaction(flow, source_id) end
    |> Repo.transaction()
    |> normalize_duplicate_result()
    |> broadcast_sequence_result()
  end

  def duplicate_composition_owner(_flow, _node), do: {:error, :composition_owner_not_found}

  # =========================================================================
  # Internals
  # =========================================================================

  defp normalize_keys(attrs) when is_map(attrs) do
    Map.new(attrs, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
  end

  defp ensure_config_loaded(%FlowNode{sequence_config: %SequenceConfig{} = c}), do: c

  defp ensure_config_loaded(%FlowNode{id: id}), do: Repo.get_by!(SequenceConfig, flow_node_id: id)

  defp update_sequence_node(node, attrs) when map_size(attrs) == 0, do: node

  defp update_sequence_node(node, attrs) do
    case node |> FlowNode.update_changeset(attrs) |> Repo.update() do
      {:ok, node} -> node
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  defp update_sequence_config(node, attrs) when map_size(attrs) == 0 do
    ensure_config_loaded(node)
  end

  defp update_sequence_config(node, attrs) do
    case node
         |> ensure_config_loaded()
         |> SequenceConfig.update_changeset(attrs)
         |> Repo.update() do
      {:ok, config} -> config
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  defp load_active_nodes(flow_id, node_ids) do
    nodes =
      Repo.all(
        from(n in FlowNode,
          where: n.id in ^node_ids and n.flow_id == ^flow_id and is_nil(n.deleted_at),
          order_by: [asc: n.id],
          lock: "FOR UPDATE"
        )
      )

    if length(nodes) == length(Enum.uniq(node_ids)) do
      {:ok, nodes}
    else
      {:error, :nodes_not_found}
    end
  end

  defp common_parent_id(nodes) do
    case nodes |> Enum.map(& &1.parent_id) |> Enum.uniq() do
      [parent_id] -> {:ok, parent_id}
      _ -> {:error, :mixed_parents}
    end
  end

  defp build_wrap_attrs(attrs, parent_id) do
    attrs
    |> normalize_keys()
    |> Map.put_new("name", "Sequence")
    |> Map.put("parent_id", parent_id)
  end

  defp assign_nodes_to_sequence(nodes, sequence_id) do
    ids = Enum.map(nodes, & &1.id)

    Repo.update_all(from(n in FlowNode, where: n.id in ^ids), set: [parent_id: sequence_id])
    :ok
  end

  defp duplicate_composition_owner_in_transaction(flow, source_id) do
    with {:ok, %{flow: locked_flow, project: project, project_id: project_id}} <-
           References.lock_active_flow_for_write(flow),
         :ok <- ItemCapacity.can_create_item?(project),
         %FlowNode{} = source <- lock_composition_owner_for_duplicate(locked_flow.id, source_id),
         source =
           Repo.preload(source, [
             :sequence_config,
             :sequence_tracks,
             :sequence_visual_layers
           ]),
         {:ok, duplicate} <- insert_composition_duplicate(locked_flow, source, project_id),
         {:ok, duplicate} <- set_composition_source(duplicate.id, source.composition_source_id),
         :ok <- duplicate_visual_layers(source, duplicate.id, project_id),
         :ok <- duplicate_tracks(source, duplicate.id, project_id) do
      duplicate = Repo.preload(duplicate, :sequence_config, force: true)
      {duplicate, project_id}
    else
      nil -> Repo.rollback(:composition_owner_not_found)
      {:error, :limit_reached, details} -> Repo.rollback({:limit_reached, details})
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp lock_composition_owner_for_duplicate(flow_id, source_id) do
    Repo.one(
      from(node in FlowNode,
        where:
          node.id == ^source_id and node.flow_id == ^flow_id and
            node.type in ["sequence", "dialogue"] and is_nil(node.deleted_at),
        lock: "FOR UPDATE"
      )
    )
  end

  defp insert_composition_duplicate(flow, %FlowNode{type: "dialogue"} = source, _project_id) do
    NodeCrud.create_node_without_dashboard_broadcast(flow, %{
      "type" => "dialogue",
      "position_x" => source.position_x + 50.0,
      "position_y" => source.position_y + 50.0,
      "parent_id" => source.parent_id,
      "composition_source_id" => nil,
      "data" => NodeTypes.duplicate_data("dialogue", source.data)
    })
  end

  defp insert_composition_duplicate(
         flow,
         %FlowNode{type: "sequence", sequence_config: %SequenceConfig{} = config} = source,
         project_id
       ) do
    attrs = %{
      "name" => config.name,
      "position_x" => source.position_x + 50.0,
      "position_y" => source.position_y + 50.0,
      "parent_id" => source.parent_id,
      "width" => config.width,
      "height" => config.height
    }

    case create_sequence_in_transaction(flow.id, attrs) do
      {duplicate, ^project_id} -> {:ok, duplicate}
      {_duplicate, _other_project_id} -> {:error, :flow_scope_mismatch}
    end
  end

  defp insert_composition_duplicate(_flow, _source, _project_id), do: {:error, :invalid_sequence_config}

  defp duplicate_visual_layers(source, duplicate_id, project_id) do
    source.sequence_visual_layers
    |> Enum.sort_by(& &1.id)
    |> Enum.reduce_while(:ok, fn layer, :ok ->
      with {:ok, asset_id} <-
             lock_project_asset(
               project_id,
               :sequence_visual_asset_id,
               layer.asset_id,
               "image/%"
             ),
           attrs =
             layer
             |> Map.from_struct()
             |> Map.take(@visual_layer_copy_fields)
             |> Map.put(:flow_node_id, duplicate_id)
             |> Map.put(:asset_id, asset_id),
           {:ok, _copy} <-
             %SequenceVisualLayer{}
             |> SequenceVisualLayer.override_changeset(attrs)
             |> Repo.insert() do
        {:cont, :ok}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp duplicate_tracks(source, duplicate_id, project_id) do
    source.sequence_tracks
    |> Enum.sort_by(& &1.id)
    |> Enum.reduce_while(:ok, fn track, :ok ->
      with {:ok, asset_id} <-
             lock_project_asset(
               project_id,
               :sequence_track_asset_id,
               track.asset_id,
               "audio/%"
             ),
           attrs =
             track
             |> Map.from_struct()
             |> Map.take(@track_copy_fields)
             |> Map.put(:flow_node_id, duplicate_id)
             |> Map.put(:asset_id, asset_id),
           {:ok, _copy} <-
             %SequenceTrack{}
             |> SequenceTrack.override_changeset(attrs)
             |> Repo.insert() do
        {:cont, :ok}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp normalize_duplicate_result({:error, {:limit_reached, details}}), do: {:error, :limit_reached, details}

  defp normalize_duplicate_result(result), do: result

  defp ensure_sequence(%FlowNode{type: "sequence", deleted_at: nil}), do: :ok
  defp ensure_sequence(_node), do: {:error, :sequence_not_found}

  defp broadcast_sequence_result({:ok, {sequence, project_id}}) do
    Collaboration.broadcast_dashboard_change(project_id, :flows)
    {:ok, sequence}
  end

  defp broadcast_sequence_result(result), do: result

  @doc "Selects the explicit composition source for a sequence or dialogue node."
  @spec set_composition_source(integer(), integer() | String.t() | nil) ::
          {:ok, FlowNode.t()} | {:error, atom() | tuple() | Ecto.Changeset.t()}
  def set_composition_source(owner_id, source_id) when is_integer(owner_id) do
    with {:ok, source_id} <- normalize_optional_id(source_id) do
      Repo.transaction(fn -> persist_composition_source(owner_id, source_id) end)
    end
  end

  def set_composition_source(_owner_id, source_id), do: {:error, {:invalid_composition_source, source_id}}

  defp persist_composition_source(owner_id, source_id) do
    with {:ok, %{flow: flow, node: owner}} <- lock_composition_owner(owner_id),
         {:ok, nodes} <- lock_composition_nodes(flow.id),
         :ok <- validate_composition_source(owner, source_id, nodes),
         {:ok, updated} <-
           owner
           |> FlowNode.composition_source_changeset(%{composition_source_id: source_id})
           |> Repo.update(),
         :ok <- validate_composition_dependents(flow.id, owner_id) do
      updated
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  # =========================================================================
  # Sequence visual layers
  # =========================================================================

  @doc """
  Lists all local visual-layer rows for a sequence or dialogue owner.
  """
  @spec list_sequence_visual_layers(integer()) :: [SequenceVisualLayer.t()]
  def list_sequence_visual_layers(sequence_id) when is_integer(sequence_id), do: Sequences.list_visual_layers(sequence_id)

  @doc "Fetches a visual layer scoped to its sequence or dialogue owner."
  @spec get_sequence_visual_layer(integer(), integer()) :: SequenceVisualLayer.t() | nil
  def get_sequence_visual_layer(sequence_id, id) when is_integer(sequence_id) and is_integer(id),
    do: Sequences.get_visual_layer(sequence_id, id)

  @doc "Fetches a local visual-layer row by logical key."
  def get_sequence_visual_layer_by_key(owner_id, layer_key) when is_integer(owner_id) and is_binary(layer_key),
    do: Sequences.get_visual_layer_by_key(owner_id, layer_key)

  @doc """
  Creates a local visual-layer definition. `kind` drives sensible stage
  defaults, and explicit attrs override those defaults.
  """
  @spec create_sequence_visual_layer(integer(), map()) ::
          {:ok, SequenceVisualLayer.t()} | {:error, Ecto.Changeset.t()}
  def create_sequence_visual_layer(sequence_id, attrs) when is_integer(sequence_id) and is_map(attrs) do
    attrs =
      attrs
      |> normalize_keys()
      |> Map.drop(~w(flow_node_id layer_key overridden_fields removed))

    kind = Map.get(attrs, "kind", "prop")
    slot = normalize_visual_slot(kind, Map.get(attrs, "slot", default_slot_for_visual_kind(kind)))

    attrs =
      kind
      |> visual_layer_defaults(slot)
      |> Map.merge(attrs)
      |> Map.put("flow_node_id", sequence_id)
      |> Map.put("kind", kind)
      |> Map.put("slot", slot)

    Repo.transaction(fn ->
      with {:ok, %{project_id: project_id}} <- lock_composition_owner(sequence_id),
           changeset = SequenceVisualLayer.create_changeset(%SequenceVisualLayer{}, attrs),
           asset_id = Ecto.Changeset.get_field(changeset, :asset_id),
           {:ok, asset_id} <-
             lock_project_asset(
               project_id,
               :sequence_visual_asset_id,
               asset_id,
               "image/%"
             ),
           {:ok, layer} <-
             changeset
             |> Ecto.Changeset.put_change(:asset_id, asset_id)
             |> Repo.insert() do
        layer
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc "Updates a local visual-layer row."
  @spec update_sequence_visual_layer(SequenceVisualLayer.t(), map()) ::
          {:ok, SequenceVisualLayer.t()} | {:error, Ecto.Changeset.t()}
  def update_sequence_visual_layer(%SequenceVisualLayer{} = layer, attrs) when is_map(attrs) do
    Repo.transaction(fn ->
      with {:ok, locked_layer, %{project_id: project_id}} <- lock_visual_layer_for_write(layer),
           attrs =
             normalize_visual_layer_update_attrs(
               locked_layer,
               normalize_keys(attrs)
             ),
           changeset = SequenceVisualLayer.update_changeset(locked_layer, attrs),
           asset_id = Ecto.Changeset.get_field(changeset, :asset_id),
           {:ok, asset_id} <-
             lock_project_asset(
               project_id,
               :sequence_visual_asset_id,
               asset_id,
               "image/%"
             ),
           {:ok, updated_layer} <-
             changeset
             |> Ecto.Changeset.put_change(:asset_id, asset_id)
             |> Repo.update() do
        updated_layer
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc "Deletes a local visual-layer row."
  @spec delete_sequence_visual_layer(SequenceVisualLayer.t()) ::
          {:ok, SequenceVisualLayer.t()} | {:error, atom() | Ecto.Changeset.t()}
  def delete_sequence_visual_layer(%SequenceVisualLayer{} = layer) do
    Repo.transaction(fn ->
      with {:ok, locked_layer, context} <- lock_visual_layer_for_write(layer),
           {:ok, deleted_layer} <- Repo.delete(locked_layer),
           :ok <- validate_composition_dependents(context.flow.id, locked_layer.flow_node_id) do
        deleted_layer
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp default_slot_for_visual_kind("backdrop"), do: "full"
  defp default_slot_for_visual_kind("overlay"), do: "full"
  defp default_slot_for_visual_kind("character"), do: "bottom-center"
  defp default_slot_for_visual_kind(_), do: "middle-center"

  defp normalize_visual_slot(kind, "left"), do: normalize_visual_slot(kind, "bottom-left")
  defp normalize_visual_slot(kind, "right"), do: normalize_visual_slot(kind, "bottom-right")
  defp normalize_visual_slot("character", "center"), do: "bottom-center"
  defp normalize_visual_slot(_kind, "center"), do: "middle-center"

  defp normalize_visual_slot(_kind, slot)
       when slot in [
              "full",
              "custom",
              "top-left",
              "top-center",
              "top-right",
              "middle-left",
              "middle-center",
              "middle-right",
              "bottom-left",
              "bottom-center",
              "bottom-right"
            ], do: slot

  defp normalize_visual_slot(kind, _slot), do: default_slot_for_visual_kind(kind)

  defp normalize_visual_layer_update_attrs(%SequenceVisualLayer{} = layer, attrs) do
    case Map.fetch(attrs, "slot") do
      {:ok, slot} ->
        kind = Map.get(attrs, "kind", layer.kind)
        Map.put(attrs, "slot", normalize_visual_slot(kind, slot))

      :error ->
        attrs
    end
  end

  defp visual_layer_defaults("backdrop", _slot) do
    %{
      "slot" => "full",
      "x" => 0.0,
      "y" => 0.0,
      "width" => 1.0,
      "height" => 1.0,
      "anchor_x" => 0.0,
      "anchor_y" => 0.0,
      "fit" => "cover",
      "z_index" => 0,
      "opacity" => 1.0,
      "visible" => true
    }
  end

  defp visual_layer_defaults(kind, "full") do
    %{
      "slot" => "full",
      "x" => 0.0,
      "y" => 0.0,
      "width" => 1.0,
      "height" => 1.0,
      "anchor_x" => 0.0,
      "anchor_y" => 0.0,
      "fit" => if(kind in ["backdrop", "overlay"], do: "cover", else: "contain"),
      "z_index" => visual_layer_z_index(kind),
      "opacity" => 1.0,
      "visible" => true
    }
  end

  defp visual_layer_defaults("character", slot) do
    {row, col} = position_parts(slot, "bottom-center")
    x = column_x(col, :character)
    y = row_y(row, :character)
    width = if col == "center", do: 0.42, else: 0.38

    %{
      "x" => x,
      "y" => y,
      "width" => width,
      "height" => 0.9,
      "anchor_x" => 0.5,
      "anchor_y" => row_anchor_y(row),
      "fit" => "contain",
      "z_index" => 100,
      "opacity" => 1.0,
      "visible" => true
    }
  end

  defp visual_layer_defaults(kind, slot) do
    {row, col} = position_parts(slot, "middle-center")

    %{
      "x" => column_x(col, :safe_center),
      "y" => row_y(row, :safe_center),
      "width" => 0.25,
      "height" => 0.25,
      "anchor_x" => 0.5,
      "anchor_y" => 0.5,
      "fit" => "contain",
      "z_index" => visual_layer_z_index(kind),
      "opacity" => 1.0,
      "visible" => true
    }
  end

  defp position_parts(slot, fallback) do
    slot =
      if slot in [
           "top-left",
           "top-center",
           "top-right",
           "middle-left",
           "middle-center",
           "middle-right",
           "bottom-left",
           "bottom-center",
           "bottom-right"
         ] do
        slot
      else
        fallback
      end

    [row, col] = String.split(slot, "-", parts: 2)
    {row, col}
  end

  defp column_x("left", :character), do: 0.25
  defp column_x("right", :character), do: 0.75
  defp column_x("center", :character), do: 0.5
  defp column_x("left", :safe_center), do: 0.2
  defp column_x("right", :safe_center), do: 0.8
  defp column_x("center", :safe_center), do: 0.5

  defp row_y("top", :character), do: 0.0
  defp row_y("bottom", :character), do: 1.0
  defp row_y("middle", :character), do: 0.5
  defp row_y("top", :safe_center), do: 0.2
  defp row_y("bottom", :safe_center), do: 0.8
  defp row_y("middle", :safe_center), do: 0.5

  defp row_anchor_y("top"), do: 0.0
  defp row_anchor_y("bottom"), do: 1.0
  defp row_anchor_y("middle"), do: 0.5

  defp visual_layer_z_index("backdrop"), do: 0
  defp visual_layer_z_index("character"), do: 100
  defp visual_layer_z_index("overlay"), do: 300
  defp visual_layer_z_index(_kind), do: 200

  # =========================================================================
  # Sequence tracks (audio)
  # =========================================================================

  @doc """
  Lists all local track and inherited-patch rows for an owner, ordered by
  `kind` then `position`. Returns `[]` when there are no rows.
  """
  @spec list_sequence_tracks(integer()) :: [SequenceTrack.t()]
  def list_sequence_tracks(sequence_id) when is_integer(sequence_id), do: Sequences.list_tracks(sequence_id)

  @doc """
  Fetches an owner's local track definition for a given kind, or `nil`.
  """
  @spec get_sequence_track(integer(), String.t()) :: SequenceTrack.t() | nil
  def get_sequence_track(sequence_id, kind) when is_binary(kind), do: Sequences.get_track(sequence_id, kind)

  @doc "Fetches a local audio-track row by logical key."
  def get_sequence_track_by_key(owner_id, track_key) when is_integer(owner_id) and is_binary(track_key),
    do: Sequences.get_track_by_key(owner_id, track_key)

  @doc """
  Upserts the local definition for `(owner_id, kind)`. Inherited patches with
  the same kind are left untouched. `kind` must be one of
  `SequenceTrack.kinds/0`.
  """
  @spec upsert_sequence_track(integer(), String.t(), map()) ::
          {:ok, SequenceTrack.t()} | {:error, atom() | Ecto.Changeset.t()}
  def upsert_sequence_track(sequence_id, kind, attrs) when is_integer(sequence_id) and is_binary(kind) do
    if kind in SequenceTrack.kinds() do
      do_upsert_sequence_track(sequence_id, kind, attrs)
    else
      {:error, :invalid_kind}
    end
  end

  @doc """
  Deletes the local definition for `(owner_id, kind)` and preserves inherited
  patches. Returns `{:ok, :cleared}` whether or not a definition existed.
  """
  @spec clear_sequence_track(integer(), String.t()) ::
          {:ok, :cleared} | {:error, atom()}
  def clear_sequence_track(sequence_id, kind) when is_integer(sequence_id) and is_binary(kind) do
    if kind in SequenceTrack.kinds() do
      do_clear_sequence_track(sequence_id, kind)
    else
      {:error, :invalid_kind}
    end
  end

  defp put_normalized_parent_id(node_attrs, parent_id) do
    if Map.has_key?(node_attrs, "parent_id"),
      do: Map.put(node_attrs, "parent_id", parent_id),
      else: node_attrs
  end

  defp do_upsert_sequence_track(sequence_id, kind, attrs) do
    Repo.transaction(fn ->
      with {:ok, %{project_id: project_id}} <- lock_composition_owner(sequence_id),
           track = lock_sequence_track(sequence_id, kind),
           changeset = sequence_track_changeset(track, sequence_id, kind, attrs),
           asset_id = Ecto.Changeset.get_field(changeset, :asset_id),
           {:ok, asset_id} <-
             lock_project_asset(
               project_id,
               :sequence_track_asset_id,
               asset_id,
               "audio/%"
             ),
           {:ok, persisted_track} <-
             persist_sequence_track(changeset, asset_id, track) do
        persisted_track
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp do_clear_sequence_track(sequence_id, kind) do
    Repo.transaction(fn -> clear_sequence_track_in_transaction(sequence_id, kind) end)
  end

  defp clear_sequence_track_in_transaction(sequence_id, kind) do
    case lock_composition_owner(sequence_id) do
      {:ok, context} ->
        Repo.delete_all(
          from(t in SequenceTrack,
            where:
              t.flow_node_id == ^sequence_id and t.kind == ^kind and
                t.is_override == false
          )
        )

        finish_clearing_track(validate_composition_dependents(context.flow.id, sequence_id))

      {:error, reason} ->
        Repo.rollback(reason)
    end
  end

  defp finish_clearing_track(:ok), do: :cleared
  defp finish_clearing_track({:error, reason}), do: Repo.rollback(reason)

  defp lock_composition_owner(owner_id) do
    with {:ok, %{node: node} = context} <-
           References.lock_active_node_for_write(owner_id),
         :ok <- ensure_composition_owner(node) do
      {:ok, context}
    end
  end

  defp ensure_composition_owner(%FlowNode{type: type, deleted_at: nil}) when type in ["sequence", "dialogue"], do: :ok

  defp ensure_composition_owner(_node), do: {:error, :composition_owner_not_found}

  defp lock_visual_layer_for_write(%SequenceVisualLayer{id: layer_id, flow_node_id: sequence_id})
       when is_integer(layer_id) and is_integer(sequence_id) do
    with {:ok, context} <- lock_composition_owner(sequence_id),
         %SequenceVisualLayer{} = layer <-
           Repo.one(
             from(layer in SequenceVisualLayer,
               where:
                 layer.id == ^layer_id and
                   layer.flow_node_id == ^sequence_id,
               lock: "FOR UPDATE"
             )
           ) do
      {:ok, layer, context}
    else
      nil -> {:error, :sequence_visual_layer_not_found}
      {:error, _reason} = error -> error
    end
  end

  defp lock_visual_layer_for_write(_layer), do: {:error, :sequence_visual_layer_not_found}

  defp lock_project_asset(project_id, context, asset_id, content_type_pattern) do
    with {:ok, [normalized_asset_id]} <-
           References.lock_active_references(project_id, [
             {:asset, context, asset_id}
           ]),
         :ok <-
           validate_asset_content_type(
             project_id,
             context,
             normalized_asset_id,
             content_type_pattern
           ) do
      {:ok, normalized_asset_id}
    end
  end

  defp validate_asset_content_type(_project_id, _context, nil, _content_type_pattern), do: :ok

  defp validate_asset_content_type(project_id, context, asset_id, content_type_pattern) do
    if Repo.exists?(
         from(asset in AssetRecord,
           where:
             asset.id == ^asset_id and asset.project_id == ^project_id and
               is_nil(asset.deleted_at) and
               like(asset.content_type, ^content_type_pattern)
         )
       ) do
      :ok
    else
      {:error, {:invalid_asset_content_type, context, asset_id}}
    end
  end

  defp lock_sequence_track(sequence_id, kind) do
    Repo.one(
      from(track in SequenceTrack,
        where:
          track.flow_node_id == ^sequence_id and track.kind == ^kind and
            track.is_override == false,
        lock: "FOR UPDATE"
      )
    )
  end

  defp sequence_track_changeset(nil, sequence_id, kind, attrs) do
    attrs =
      attrs
      |> normalize_keys()
      |> Map.drop(~w(flow_node_id kind track_key is_override overridden_fields removed))
      |> Map.put("flow_node_id", sequence_id)
      |> Map.put("kind", kind)

    SequenceTrack.create_changeset(%SequenceTrack{}, attrs)
  end

  defp sequence_track_changeset(%SequenceTrack{} = track, _sequence_id, _kind, attrs) do
    SequenceTrack.update_changeset(track, normalize_keys(attrs))
  end

  defp persist_sequence_track(changeset, asset_id, nil) do
    changeset
    |> Ecto.Changeset.put_change(:asset_id, asset_id)
    |> Repo.insert()
  end

  defp persist_sequence_track(changeset, asset_id, %SequenceTrack{}) do
    changeset
    |> Ecto.Changeset.put_change(:asset_id, asset_id)
    |> Repo.update()
  end

  defp lock_composition_nodes(flow_id) do
    nodes =
      Repo.all(
        from(node in FlowNode,
          where:
            node.flow_id == ^flow_id and node.type in ["sequence", "dialogue"] and
              is_nil(node.deleted_at),
          order_by: [asc: node.id],
          lock: "FOR UPDATE"
        )
      )

    {:ok, Map.new(nodes, &{&1.id, &1})}
  end

  defp validate_composition_source(_owner, nil, _nodes), do: :ok

  defp validate_composition_source(owner, source_id, nodes) do
    case Map.get(nodes, source_id) do
      %FlowNode{} ->
        if composition_cycle?(owner.id, source_id, nodes),
          do: {:error, :composition_cycle},
          else: :ok

      nil ->
        {:error, {:invalid_composition_source, source_id}}
    end
  end

  defp composition_cycle?(owner_id, source_id, nodes), do: composition_cycle?(owner_id, source_id, nodes, MapSet.new())

  defp composition_cycle?(owner_id, owner_id, _nodes, _visited), do: true
  defp composition_cycle?(_owner_id, nil, _nodes, _visited), do: false

  defp composition_cycle?(owner_id, source_id, nodes, visited) do
    if MapSet.member?(visited, source_id) do
      true
    else
      case Map.get(nodes, source_id) do
        %FlowNode{composition_source_id: next_id} ->
          composition_cycle?(owner_id, next_id, nodes, MapSet.put(visited, source_id))

        nil ->
          false
      end
    end
  end

  defp normalize_optional_id(value) when value in [nil, ""], do: {:ok, nil}
  defp normalize_optional_id(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp normalize_optional_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} when id > 0 -> {:ok, id}
      _ -> {:error, {:invalid_composition_source, value}}
    end
  end

  defp normalize_optional_id(value), do: {:error, {:invalid_composition_source, value}}

  defp validate_composition_dependents(flow_id, owner_id) do
    flow_id
    |> composition_nodes_including_deleted()
    |> Map.values()
    |> Enum.map(&composition_integrity_node/1)
    |> SequenceCompositionIntegrity.validate_affected(owner_id)
  end

  defp composition_nodes_including_deleted(flow_id) do
    from(node in FlowNode,
      where: node.flow_id == ^flow_id and node.type in ["sequence", "dialogue"],
      preload: [sequence_tracks: [:asset], sequence_visual_layers: [:asset]]
    )
    |> Repo.all()
    |> Map.new(&{&1.id, &1})
  end

  defp composition_integrity_node(node) do
    %{
      "original_id" => node.id,
      "type" => node.type,
      "deleted_at" => node.deleted_at,
      "composition_source_original_id" => node.composition_source_id,
      "sequence_config" => composition_integrity_config(node),
      "sequence_tracks" => Enum.map(node.sequence_tracks, &composition_integrity_track/1),
      "sequence_visual_layers" => Enum.map(node.sequence_visual_layers, &composition_integrity_visual_layer/1)
    }
  end

  defp composition_integrity_config(%FlowNode{type: "sequence"}), do: %{}
  defp composition_integrity_config(_node), do: nil

  defp composition_integrity_track(track) do
    %{
      "track_key" => track.track_key,
      "kind" => track.kind,
      "is_override" => track.is_override,
      "overridden_fields" => track.overridden_fields,
      "removed" => track.removed
    }
  end

  defp composition_integrity_visual_layer(layer) do
    %{
      "layer_key" => layer.layer_key,
      "overridden_fields" => layer.overridden_fields,
      "removed" => layer.removed
    }
  end
end
