defmodule Storyarn.Versioning.Builders.FlowBuilder do
  @moduledoc """
  Snapshot builder for flows.

  Captures flow metadata, nodes (sorted deterministically), and connections
  (referenced by node index rather than ID for portability).
  """

  @behaviour Storyarn.Versioning.SnapshotBuilder

  import Ecto.Query, warn: false
  use Gettext, backend: StoryarnWeb.Gettext

  alias Ecto.Multi
  alias Storyarn.Flows.{Flow, FlowConnection, FlowNode}
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Versioning.Builders.AssetHashResolver

  # ========== Build Snapshot ==========

  @impl true
  def build_snapshot(%Flow{} = flow) do
    flow = Repo.preload(flow, [:nodes, :connections])

    # Sort nodes deterministically for stable indexes
    sorted_nodes =
      flow.nodes
      |> Enum.reject(&(&1.deleted_at != nil))
      |> Enum.sort_by(&{&1.position_x, &1.position_y, &1.type, &1.id})

    # Build ID → index map for connection references
    id_to_index =
      sorted_nodes |> Enum.with_index() |> Map.new(fn {node, idx} -> {node.id, idx} end)

    node_snapshots = Enum.map(sorted_nodes, &node_to_snapshot/1)

    connection_snapshots =
      flow.connections
      |> Enum.filter(fn conn ->
        Map.has_key?(id_to_index, conn.source_node_id) and
          Map.has_key?(id_to_index, conn.target_node_id)
      end)
      |> Enum.sort_by(&{Map.get(id_to_index, &1.source_node_id), &1.source_pin})
      |> Enum.map(&connection_to_snapshot(&1, id_to_index))

    # Collect asset IDs from node data
    asset_ids =
      sorted_nodes
      |> Enum.flat_map(fn node ->
        data = node.data || %{}
        [data["audio_asset_id"]]
      end)

    {hash_map, metadata_map} = AssetHashResolver.resolve_hashes(asset_ids)

    %{
      "name" => flow.name,
      "shortcut" => flow.shortcut,
      "description" => flow.description,
      "is_main" => flow.is_main,
      "settings" => flow.settings,
      "scene_id" => flow.scene_id,
      "nodes" => node_snapshots,
      "connections" => connection_snapshots,
      "asset_blob_hashes" => hash_map,
      "asset_metadata" => metadata_map
    }
  end

  defp node_to_snapshot(%FlowNode{} = node) do
    %{
      "original_id" => node.id,
      "type" => node.type,
      "position_x" => node.position_x,
      "position_y" => node.position_y,
      "data" => node.data,
      "word_count" => node.word_count,
      "source" => node.source
    }
  end

  defp connection_to_snapshot(%FlowConnection{} = conn, id_to_index) do
    %{
      "source_node_index" => Map.fetch!(id_to_index, conn.source_node_id),
      "target_node_index" => Map.fetch!(id_to_index, conn.target_node_id),
      "source_pin" => conn.source_pin,
      "target_pin" => conn.target_pin,
      "label" => conn.label
    }
  end

  # ========== Restore Snapshot ==========

  @impl true
  def restore_snapshot(%Flow{} = flow, snapshot, _opts \\ []) do
    Multi.new()
    |> Multi.update(:flow, fn _changes ->
      Flow.update_changeset(flow, %{
        name: snapshot["name"],
        shortcut: snapshot["shortcut"],
        description: snapshot["description"],
        is_main: snapshot["is_main"],
        settings: snapshot["settings"],
        scene_id: resolve_fk(snapshot["scene_id"], Storyarn.Scenes.Scene)
      })
    end)
    |> Multi.delete_all(:delete_connections, fn _changes ->
      from(c in FlowConnection, where: c.flow_id == ^flow.id)
    end)
    |> Multi.delete_all(:delete_nodes, fn _changes ->
      from(n in FlowNode, where: n.flow_id == ^flow.id)
    end)
    |> Multi.run(:restore_nodes, fn repo, _changes ->
      restore_nodes(repo, flow.id, snapshot["nodes"] || [], snapshot, flow.project_id)
    end)
    |> Multi.run(:restore_connections, fn repo, %{restore_nodes: node_ids} ->
      restore_connections(repo, flow.id, snapshot["connections"] || [], node_ids)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{flow: updated_flow}} ->
        {:ok, Repo.preload(updated_flow, [:nodes, :connections], force: true)}

      {:error, _op, reason, _changes} ->
        {:error, reason}
    end
  end

  defp restore_nodes(_repo, _flow_id, [], _snapshot, _project_id), do: {:ok, []}

  defp restore_nodes(repo, flow_id, nodes_data, snapshot, project_id) do
    now = TimeHelpers.now()

    # Insert nodes one-by-one to get their IDs in order
    node_ids =
      Enum.map(nodes_data, fn node_data ->
        data = resolve_node_asset_refs(node_data["data"] || %{}, snapshot, project_id)

        attrs = %{
          flow_id: flow_id,
          type: node_data["type"],
          position_x: node_data["position_x"] || 0.0,
          position_y: node_data["position_y"] || 0.0,
          data: data,
          word_count: node_data["word_count"] || 0,
          source: node_data["source"] || "manual",
          inserted_at: now,
          updated_at: now
        }

        {1, [%{id: id}]} = repo.insert_all(FlowNode, [attrs], returning: [:id])
        id
      end)

    {:ok, node_ids}
  end

  defp resolve_node_asset_refs(data, snapshot, project_id) do
    case data["audio_asset_id"] do
      nil ->
        data

      audio_id ->
        resolved = AssetHashResolver.resolve_asset_fk(audio_id, snapshot, project_id)
        Map.put(data, "audio_asset_id", resolved)
    end
  end

  defp restore_connections(_repo, _flow_id, [], _node_ids), do: {:ok, 0}

  defp restore_connections(repo, flow_id, connections_data, node_ids) do
    now = TimeHelpers.now()
    node_count = length(node_ids)
    index_to_id = node_ids |> Enum.with_index() |> Map.new(fn {id, idx} -> {idx, id} end)

    entries =
      connections_data
      |> Enum.filter(fn conn ->
        source_idx = conn["source_node_index"]
        target_idx = conn["target_node_index"]

        source_idx >= 0 and source_idx < node_count and
          target_idx >= 0 and target_idx < node_count
      end)
      |> Enum.map(fn conn ->
        %{
          flow_id: flow_id,
          source_node_id: Map.fetch!(index_to_id, conn["source_node_index"]),
          target_node_id: Map.fetch!(index_to_id, conn["target_node_index"]),
          source_pin: conn["source_pin"],
          target_pin: conn["target_pin"],
          label: conn["label"],
          inserted_at: now,
          updated_at: now
        }
      end)

    {count, _} = repo.insert_all(FlowConnection, entries)
    {:ok, count}
  end

  # ========== Diff Snapshots ==========

  @impl true
  def diff_snapshots(old_snapshot, new_snapshot) do
    changes =
      []
      |> check_field_change(old_snapshot, new_snapshot, "name", dgettext("flows", "Renamed flow"))
      |> check_field_change(
        old_snapshot,
        new_snapshot,
        "shortcut",
        dgettext("flows", "Changed shortcut")
      )
      |> check_field_change(
        old_snapshot,
        new_snapshot,
        "description",
        dgettext("flows", "Changed description")
      )
      |> check_field_change(
        old_snapshot,
        new_snapshot,
        "scene_id",
        dgettext("flows", "Changed scene")
      )
      |> append_node_changes(old_snapshot["nodes"] || [], new_snapshot["nodes"] || [])
      |> append_connection_changes(
        old_snapshot["connections"] || [],
        new_snapshot["connections"] || []
      )

    format_change_summary(changes)
  end

  defp check_field_change(changes, old_snapshot, new_snapshot, field, message) do
    if old_snapshot[field] != new_snapshot[field] do
      [message | changes]
    else
      changes
    end
  end

  defp append_node_changes(changes, old_nodes, new_nodes) do
    old_count = length(old_nodes)
    new_count = length(new_nodes)
    diff = new_count - old_count

    cond do
      diff > 0 ->
        [
          dngettext("flows", "Added %{count} node", "Added %{count} nodes", diff, count: diff)
          | changes
        ]

      diff < 0 ->
        abs_diff = abs(diff)

        [
          dngettext("flows", "Removed %{count} node", "Removed %{count} nodes", abs_diff,
            count: abs_diff
          )
          | changes
        ]

      old_nodes != new_nodes ->
        [dgettext("flows", "Modified nodes") | changes]

      true ->
        changes
    end
  end

  defp append_connection_changes(changes, old_conns, new_conns) do
    old_count = length(old_conns)
    new_count = length(new_conns)
    diff = new_count - old_count

    cond do
      diff > 0 ->
        [
          dngettext("flows", "Added %{count} connection", "Added %{count} connections", diff,
            count: diff
          )
          | changes
        ]

      diff < 0 ->
        abs_diff = abs(diff)

        [
          dngettext(
            "flows",
            "Removed %{count} connection",
            "Removed %{count} connections",
            abs_diff,
            count: abs_diff
          )
          | changes
        ]

      old_conns != new_conns ->
        [dgettext("flows", "Modified connections") | changes]

      true ->
        changes
    end
  end

  defp format_change_summary([]), do: dgettext("flows", "No changes detected")
  defp format_change_summary(changes), do: changes |> Enum.reverse() |> Enum.join(", ")

  # ========== Scan References ==========

  @impl true
  def scan_references(snapshot) do
    refs = []

    refs =
      maybe_add_ref(refs, :scene, snapshot["scene_id"], dgettext("flows", "Flow backdrop scene"))

    refs =
      (snapshot["nodes"] || [])
      |> Enum.with_index(1)
      |> Enum.reduce(refs, fn {node, idx}, acc ->
        data = node["data"] || %{}
        type = node["type"] || "unknown"

        acc
        |> maybe_add_ref(
          :sheet,
          data["speaker_sheet_id"],
          dgettext("flows", "Node #%{n} (%{type}) — speaker", n: idx, type: type)
        )
        |> maybe_add_ref(
          :flow,
          data["referenced_flow_id"],
          dgettext("flows", "Node #%{n} (%{type}) — referenced flow", n: idx, type: type)
        )
        |> maybe_add_ref(
          :asset,
          data["audio_asset_id"],
          dgettext("flows", "Node #%{n} (%{type}) — audio", n: idx, type: type)
        )
      end)

    refs
  end

  defp maybe_add_ref(refs, _type, nil, _context), do: refs

  defp maybe_add_ref(refs, type, id, context),
    do: [%{type: type, id: id, context: context} | refs]

  # Returns the FK value only if the referenced record still exists, nil otherwise.
  defp resolve_fk(nil, _schema), do: nil

  defp resolve_fk(id, schema) do
    if Repo.exists?(from(e in schema, where: e.id == ^id)), do: id, else: nil
  end
end
