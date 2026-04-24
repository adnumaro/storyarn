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

  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.SequenceConfig
  alias Storyarn.Flows.SequenceTrack
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
      with {:ok, node} <-
             %FlowNode{flow_id: flow_id}
             |> FlowNode.create_changeset(node_attrs)
             |> Repo.insert(),
           {:ok, config} <-
             %SequenceConfig{}
             |> SequenceConfig.create_changeset(Map.put(config_attrs, "flow_node_id", node.id))
             |> Repo.insert() do
        %{node | sequence_config: config}
      else
        {:error, changeset} -> Repo.rollback(changeset)
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
      Map.take(attrs, [
        "name",
        "width",
        "height",
        "background_asset_id",
        "background_position",
        "background_fit"
      ])

    Repo.transaction(fn ->
      updated_node =
        if map_size(node_attrs) > 0 do
          case node |> FlowNode.update_changeset(node_attrs) |> Repo.update() do
            {:ok, n} -> n
            {:error, cs} -> Repo.rollback(cs)
          end
        else
          node
        end

      updated_config =
        if map_size(config_attrs) > 0 do
          config = ensure_config_loaded(node)

          case config |> SequenceConfig.update_changeset(config_attrs) |> Repo.update() do
            {:ok, c} -> c
            {:error, cs} -> Repo.rollback(cs)
          end
        else
          ensure_config_loaded(node)
        end

      %{updated_node | sequence_config: updated_config}
    end)
  end

  @doc """
  Soft-deletes a sequence (its flow_node row). A DB trigger nilifies
  `parent_id` on all children when `deleted_at` transitions to non-null.
  """
  @spec delete_sequence(sequence()) :: {:ok, sequence()} | {:error, Ecto.Changeset.t()}
  def delete_sequence(%FlowNode{type: "sequence"} = node) do
    node
    |> FlowNode.soft_delete_changeset()
    |> Repo.update()
  end

  @doc """
  Restores a soft-deleted sequence by clearing `deleted_at`. Children
  previously nilified are NOT re-attached — the user must re-parent
  them manually.
  """
  @spec restore_sequence(sequence()) :: {:ok, sequence()} | {:error, Ecto.Changeset.t()}
  def restore_sequence(%FlowNode{type: "sequence"} = node) do
    node
    |> FlowNode.restore_changeset()
    |> Repo.update()
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
      with {:ok, nodes} <- load_active_nodes(flow_id, node_ids),
           {:ok, parent_id} <- common_parent_id(nodes),
           attrs = build_wrap_attrs(attrs, parent_id),
           {:ok, sequence} <- create_sequence(flow_id, attrs),
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

  defp load_active_nodes(flow_id, node_ids) do
    nodes =
      Repo.all(
        from(n in FlowNode,
          where: n.id in ^node_ids and n.flow_id == ^flow_id and is_nil(n.deleted_at)
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
  def upsert_sequence_track(sequence_id, kind, attrs)
      when is_integer(sequence_id) and is_binary(kind) do
    if kind in SequenceTrack.kinds() do
      case get_sequence_track(sequence_id, kind) do
        nil ->
          attrs =
            attrs
            |> normalize_keys()
            |> Map.put("flow_node_id", sequence_id)
            |> Map.put("kind", kind)

          %SequenceTrack{}
          |> SequenceTrack.create_changeset(attrs)
          |> Repo.insert()

        %SequenceTrack{} = track ->
          track
          |> SequenceTrack.update_changeset(normalize_keys(attrs))
          |> Repo.update()
      end
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
  def clear_sequence_track(sequence_id, kind)
      when is_integer(sequence_id) and is_binary(kind) do
    if kind in SequenceTrack.kinds() do
      Repo.delete_all(
        from(t in SequenceTrack,
          where: t.flow_node_id == ^sequence_id and t.kind == ^kind
        )
      )

      {:ok, :cleared}
    else
      {:error, :invalid_kind}
    end
  end
end
