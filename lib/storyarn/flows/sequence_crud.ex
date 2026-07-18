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
  """

  import Ecto.Query

  alias Storyarn.Assets.Asset
  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.ReferenceIntegrity
  alias Storyarn.Flows.SequenceConfig
  alias Storyarn.Flows.SequenceTrack
  alias Storyarn.Flows.SequenceVisualLayer
  alias Storyarn.References.ProjectReferenceIntegrity
  alias Storyarn.Repo

  @type sequence :: FlowNode.t()

  @doc """
  Lists active (non-deleted) sequences for a flow, ordered by insertion
  time, with `sequence_config` preloaded.
  """
  @spec list_sequences(integer()) :: [sequence()]
  def list_sequences(flow_id) do
    Repo.all(
      from(n in FlowNode,
        where: n.flow_id == ^flow_id and n.type == "sequence" and is_nil(n.deleted_at),
        order_by: [asc: n.inserted_at],
        preload: [:sequence_config]
      )
    )
  end

  @doc """
  Lists soft-deleted sequences for a flow (for trash/restore UIs).
  """
  @spec list_deleted(integer()) :: [sequence()]
  def list_deleted(flow_id) do
    Repo.all(
      from(n in FlowNode,
        where: n.flow_id == ^flow_id and n.type == "sequence" and not is_nil(n.deleted_at),
        order_by: [desc: n.deleted_at],
        preload: [:sequence_config]
      )
    )
  end

  @doc """
  Fetches an active sequence by id scoped to a flow. Returns nil if
  absent, soft-deleted, or not a sequence.
  """
  @spec get_sequence(integer(), integer()) :: sequence() | nil
  def get_sequence(flow_id, id) do
    Repo.one(
      from(n in FlowNode,
        where: n.id == ^id and n.flow_id == ^flow_id and n.type == "sequence" and is_nil(n.deleted_at),
        preload: [:sequence_config]
      )
    )
  end

  @doc """
  Fetches a sequence by id scoped to a flow. Raises if absent.
  """
  @spec get_sequence!(integer(), integer()) :: sequence()
  def get_sequence!(flow_id, id) do
    Repo.one!(
      from(n in FlowNode,
        where: n.id == ^id and n.flow_id == ^flow_id and n.type == "sequence",
        preload: [:sequence_config]
      )
    )
  end

  @doc """
  Creates a sequence (flow_node + sequence_config) atomically.

  `attrs` may include: `:name` (required), `:position_x`, `:position_y`,
  `:width`, `:height`, `:parent_id`.
  """
  @spec create_sequence(integer(), map()) ::
          {:ok, sequence()} | {:error, Ecto.Changeset.t()}
  def create_sequence(flow_id, attrs) do
    attrs = normalize_keys(attrs)

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

    Repo.transaction(fn ->
      with {:ok, %{flow: flow}} <-
             ReferenceIntegrity.lock_active_flow_for_write(flow_id),
           {:ok, parent_id} <-
             ReferenceIntegrity.lock_node_parent(flow.id, node_attrs["parent_id"]),
           node_attrs = Map.put(node_attrs, "parent_id", parent_id),
           {:ok, node} <-
             %FlowNode{flow_id: flow_id}
             |> FlowNode.create_changeset(node_attrs)
             |> Repo.insert(),
           {:ok, config} <-
             %SequenceConfig{}
             |> SequenceConfig.create_changeset(Map.put(config_attrs, "flow_node_id", node.id))
             |> Repo.insert() do
        %{node | sequence_config: config}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
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
             ReferenceIntegrity.lock_active_node_for_write(node),
           :ok <- ensure_sequence(locked_node),
           parent_id = Map.get(node_attrs, "parent_id", locked_node.parent_id),
           {:ok, parent_id} <-
             ReferenceIntegrity.lock_node_parent(
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
    Repo.transaction(fn ->
      with {:ok, %{node: locked_node}} <-
             ReferenceIntegrity.lock_active_node_for_write(node),
           :ok <- ensure_sequence(locked_node),
           {:ok, deleted_node} <-
             locked_node
             |> FlowNode.soft_delete_changeset()
             |> Repo.update() do
        deleted_node
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Restores a soft-deleted sequence by clearing `deleted_at`. Children
  previously nilified are NOT re-attached — the user must re-parent
  them manually.
  """
  @spec restore_sequence(sequence()) :: {:ok, sequence()} | {:error, term()}
  def restore_sequence(%FlowNode{id: node_id, type: "sequence"}) when is_integer(node_id) do
    Repo.transaction(fn ->
      flow_id =
        Repo.one(
          from(node in FlowNode,
            where: node.id == ^node_id and node.type == "sequence",
            select: node.flow_id
          )
        ) || Repo.rollback(:sequence_not_found)

      with {:ok, %{flow: flow}} <-
             ReferenceIntegrity.lock_active_flow_for_write(flow_id),
           %FlowNode{} = locked_node <-
             Repo.one(
               from(node in FlowNode,
                 where:
                   node.id == ^node_id and node.flow_id == ^flow.id and
                     node.type == "sequence" and not is_nil(node.deleted_at),
                 lock: "FOR UPDATE"
               )
             ),
           {:ok, restored_node} <-
             locked_node
             |> FlowNode.restore_changeset()
             |> Repo.update() do
        restored_node
      else
        nil -> Repo.rollback(:sequence_not_deleted)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
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
    Repo.transaction(fn ->
      with {:ok, %{flow: locked_flow}} <-
             ReferenceIntegrity.lock_active_flow_for_write(flow_id),
           {:ok, nodes} <- load_active_nodes(locked_flow.id, node_ids),
           {:ok, parent_id} <- common_parent_id(nodes),
           attrs = build_wrap_attrs(attrs, parent_id),
           {:ok, sequence} <- create_sequence(locked_flow.id, attrs),
           :ok <- assign_nodes_to_sequence(nodes, sequence.id) do
        sequence
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

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
    case node |> ensure_config_loaded() |> SequenceConfig.update_changeset(attrs) |> Repo.update() do
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

  defp ensure_sequence(%FlowNode{type: "sequence", deleted_at: nil}), do: :ok
  defp ensure_sequence(_node), do: {:error, :sequence_not_found}

  # =========================================================================
  # Sequence visual layers
  # =========================================================================

  @doc """
  Lists all visual layers for a sequence, ordered for player rendering.
  """
  @spec list_sequence_visual_layers(integer()) :: [SequenceVisualLayer.t()]
  def list_sequence_visual_layers(sequence_id) when is_integer(sequence_id) do
    Repo.all(
      from(l in SequenceVisualLayer,
        where: l.flow_node_id == ^sequence_id,
        order_by: [asc: l.z_index, asc: l.id],
        preload: [:asset]
      )
    )
  end

  @doc "Fetches a visual layer scoped to its sequence."
  @spec get_sequence_visual_layer(integer(), integer()) :: SequenceVisualLayer.t() | nil
  def get_sequence_visual_layer(sequence_id, id) when is_integer(sequence_id) and is_integer(id) do
    Repo.one(
      from(l in SequenceVisualLayer,
        where: l.flow_node_id == ^sequence_id and l.id == ^id,
        preload: [:asset]
      )
    )
  end

  @doc """
  Creates a visual layer for a sequence. `kind` drives sensible stage
  defaults, and explicit attrs override those defaults.
  """
  @spec create_sequence_visual_layer(integer(), map()) ::
          {:ok, SequenceVisualLayer.t()} | {:error, Ecto.Changeset.t()}
  def create_sequence_visual_layer(sequence_id, attrs) when is_integer(sequence_id) and is_map(attrs) do
    attrs = normalize_keys(attrs)
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
      with {:ok, %{project_id: project_id}} <- lock_active_sequence(sequence_id),
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

  @doc "Updates a sequence visual layer."
  @spec update_sequence_visual_layer(SequenceVisualLayer.t(), map()) ::
          {:ok, SequenceVisualLayer.t()} | {:error, Ecto.Changeset.t()}
  def update_sequence_visual_layer(%SequenceVisualLayer{} = layer, attrs) when is_map(attrs) do
    Repo.transaction(fn ->
      with {:ok, %{layer: locked_layer, project_id: project_id}} <-
             lock_visual_layer_for_write(layer),
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

  @doc "Deletes a sequence visual layer."
  @spec delete_sequence_visual_layer(SequenceVisualLayer.t()) ::
          {:ok, SequenceVisualLayer.t()} | {:error, Ecto.Changeset.t()}
  def delete_sequence_visual_layer(%SequenceVisualLayer{} = layer) do
    Repo.transaction(fn ->
      with {:ok, %{layer: locked_layer}} <- lock_visual_layer_for_write(layer),
           {:ok, deleted_layer} <- Repo.delete(locked_layer) do
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
  Lists all tracks for a sequence, ordered by `kind` then `position`.
  Returns `[]` for sequences with no tracks.
  """
  @spec list_sequence_tracks(integer()) :: [SequenceTrack.t()]
  def list_sequence_tracks(sequence_id) when is_integer(sequence_id) do
    Repo.all(
      from(t in SequenceTrack,
        where: t.flow_node_id == ^sequence_id,
        order_by: [asc: t.kind, asc: t.position]
      )
    )
  end

  @doc """
  Fetches a sequence's track for a given kind, or `nil`.
  """
  @spec get_sequence_track(integer(), String.t()) :: SequenceTrack.t() | nil
  def get_sequence_track(sequence_id, kind) when is_binary(kind) do
    Repo.one(
      from(t in SequenceTrack,
        where: t.flow_node_id == ^sequence_id and t.kind == ^kind
      )
    )
  end

  @doc """
  Upserts the track row for `(sequence_id, kind)`. If no row exists it's
  created; if one exists it's updated with `attrs`. `kind` must be one of
  `SequenceTrack.kinds/0`. Silently rejects kinds outside the whitelist.

  Rejects calls targeting a non-sequence flow_node via the DB trigger
  (`fn_validate_sequence_track_owner`).
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
  Deletes the track row for `(sequence_id, kind)`. Returns `{:ok, :cleared}`
  whether or not a row existed — clearing an empty slot is a no-op.
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
      with {:ok, %{project_id: project_id}} <- lock_active_sequence(sequence_id),
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
    Repo.transaction(fn ->
      case lock_active_sequence(sequence_id) do
        {:ok, _context} ->
          Repo.delete_all(
            from(t in SequenceTrack,
              where: t.flow_node_id == ^sequence_id and t.kind == ^kind
            )
          )

          :cleared

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end

  defp lock_active_sequence(sequence_id) do
    with {:ok, %{node: node} = context} <-
           ReferenceIntegrity.lock_active_node_for_write(sequence_id),
         :ok <- ensure_sequence(node) do
      {:ok, context}
    end
  end

  defp lock_visual_layer_for_write(%SequenceVisualLayer{id: layer_id, flow_node_id: sequence_id})
       when is_integer(layer_id) and is_integer(sequence_id) do
    with {:ok, context} <- lock_active_sequence(sequence_id),
         %SequenceVisualLayer{} = layer <-
           Repo.one(
             from(layer in SequenceVisualLayer,
               where:
                 layer.id == ^layer_id and
                   layer.flow_node_id == ^sequence_id,
               lock: "FOR UPDATE"
             )
           ) do
      {:ok, Map.put(context, :layer, layer)}
    else
      nil -> {:error, :sequence_visual_layer_not_found}
      {:error, _reason} = error -> error
    end
  end

  defp lock_visual_layer_for_write(_layer), do: {:error, :sequence_visual_layer_not_found}

  defp lock_project_asset(project_id, context, asset_id, content_type_pattern) do
    with {:ok, [normalized_asset_id]} <-
           ProjectReferenceIntegrity.lock_active_references(project_id, [
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
         from(asset in Asset,
           where:
             asset.id == ^asset_id and asset.project_id == ^project_id and
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
        where: track.flow_node_id == ^sequence_id and track.kind == ^kind,
        lock: "FOR UPDATE"
      )
    )
  end

  defp sequence_track_changeset(nil, sequence_id, kind, attrs) do
    attrs =
      attrs
      |> normalize_keys()
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
end
