defmodule Storyarn.Versioning.Builders.FlowBuilder do
  @moduledoc """
  Snapshot builder for flows.

  Captures flow metadata, nodes (sorted deterministically), and connections
  (referenced by node index rather than ID for portability).
  """

  @behaviour Storyarn.Versioning.SnapshotBuilder

  import Ecto.Query, warn: false
  use Gettext, backend: Storyarn.Gettext

  alias Ecto.Multi
  alias Storyarn.Flows.{Flow, FlowConnection, FlowNode}
  alias Storyarn.Repo
  alias Storyarn.Sheets
  alias Storyarn.Versioning.Builders.AssetHashResolver
  alias Storyarn.Versioning.DiffHelpers
  alias Storyarn.Versioning.MaterializationHelpers

  # ========== Build Snapshot ==========

  @impl true
  def build_snapshot(%Flow{} = flow) do
    flow = Repo.preload(flow, [:nodes, :connections])

    # Sort nodes deterministically for stable indexes
    sorted_nodes =
      flow.nodes
      |> Enum.filter(&is_nil(&1.deleted_at))
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
      |> Enum.map(fn node ->
        (node.data || %{})["audio_asset_id"]
      end)

    {hash_map, metadata_map} = AssetHashResolver.resolve_hashes(asset_ids)

    referenced_sheets = build_referenced_sheets(sorted_nodes, flow.project_id)

    %{
      "original_id" => flow.id,
      "name" => flow.name,
      "shortcut" => flow.shortcut,
      "description" => flow.description,
      "is_main" => flow.is_main,
      "settings" => flow.settings,
      "scene_id" => flow.scene_id,
      "nodes" => node_snapshots,
      "connections" => connection_snapshots,
      "asset_blob_hashes" => hash_map,
      "asset_metadata" => metadata_map,
      "referenced_sheets" => referenced_sheets
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
      "original_id" => conn.id,
      "source_node_index" => Map.fetch!(id_to_index, conn.source_node_id),
      "target_node_index" => Map.fetch!(id_to_index, conn.target_node_id),
      "source_pin" => conn.source_pin,
      "target_pin" => conn.target_pin,
      "label" => conn.label
    }
  end

  # Embeds sheet metadata (name, color, avatar, banner) at snapshot time
  # so the version viewer doesn't need to read live DB state.
  defp build_referenced_sheets(nodes, project_id) do
    sheet_ids =
      nodes
      |> Enum.flat_map(fn node ->
        data = node.data || %{}
        [data["speaker_sheet_id"], data["location_sheet_id"]]
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    if sheet_ids == [] do
      %{}
    else
      sheets = Sheets.list_sheets_by_ids(project_id, sheet_ids)

      Map.new(sheets, fn sheet ->
        {to_string(sheet.id),
         %{
           "id" => sheet.id,
           "name" => sheet.name,
           "shortcut" => sheet.shortcut,
           "color" => sheet.color,
           "avatar_url" => extract_default_avatar_url(sheet),
           "banner_url" => extract_asset_url(sheet.banner_asset)
         }}
      end)
    end
  end

  defp extract_asset_url(%{url: url}) when is_binary(url), do: url
  defp extract_asset_url(_), do: nil

  defp extract_default_avatar_url(%{avatars: avatars}) when is_list(avatars) do
    case Enum.find(avatars, & &1.is_default) || List.first(avatars) do
      %{asset: %{url: url}} when is_binary(url) -> url
      _ -> nil
    end
  end

  defp extract_default_avatar_url(sheet), do: extract_asset_url(Map.get(sheet, :avatar_asset))

  # ========== Restore Snapshot ==========

  @impl true
  def instantiate_snapshot(project_id, snapshot, opts \\ []) do
    Repo.transaction(fn ->
      now = MaterializationHelpers.now()

      flow_attrs =
        %{
          project_id: project_id,
          draft_id: MaterializationHelpers.root_draft_id(opts),
          name: snapshot["name"],
          shortcut: MaterializationHelpers.root_shortcut(snapshot, opts),
          description: snapshot["description"],
          is_main: snapshot["is_main"] || false,
          settings: snapshot["settings"] || %{},
          scene_id:
            MaterializationHelpers.resolve_project_external_ref(
              snapshot["scene_id"],
              Storyarn.Scenes.Scene,
              :scene,
              project_id,
              opts
            ),
          parent_id: MaterializationHelpers.root_parent_id(opts),
          position: MaterializationHelpers.root_position(opts)
        }
        |> Map.merge(MaterializationHelpers.timestamps(now))

      with {:ok, flow_id} <-
             MaterializationHelpers.insert_one_returning_id(Repo, Flow, flow_attrs),
           {:ok, inserted_nodes} <-
             insert_flow_nodes(
               Repo,
               flow_id,
               snapshot["nodes"] || [],
               snapshot,
               project_id,
               now,
               opts
             ),
           node_id_map <-
             MaterializationHelpers.build_id_map(snapshot["nodes"] || [], inserted_nodes),
           {:ok, connection_id_map} <-
             insert_flow_connections(
               Repo,
               flow_id,
               snapshot["connections"] || [],
               Enum.map(inserted_nodes, & &1.id),
               now
             ),
           flow <-
             Flow
             |> Repo.get!(flow_id)
             |> Repo.preload([:nodes, :connections], force: true) do
        id_maps = %{
          flow: MaterializationHelpers.root_id_map(snapshot, flow_id),
          node: node_id_map,
          connection: connection_id_map
        }

        {flow, id_maps}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, {flow, id_maps}} -> {:ok, flow, id_maps}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def restore_snapshot(%Flow{} = flow, snapshot, opts \\ []) do
    Multi.new()
    |> Multi.update(:flow, fn _changes ->
      Flow.update_changeset(flow, %{
        name: snapshot["name"],
        shortcut: snapshot["shortcut"],
        description: snapshot["description"],
        is_main: snapshot["is_main"],
        settings: snapshot["settings"],
        scene_id:
          MaterializationHelpers.resolve_project_external_ref(
            snapshot["scene_id"],
            Storyarn.Scenes.Scene,
            :scene,
            flow.project_id,
            opts
          )
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
    now = MaterializationHelpers.now()

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

        case repo.insert_all(FlowNode, [attrs], returning: [:id]) do
          {1, [%{id: id}]} -> id
          {0, _} -> raise "Failed to insert flow node during restore"
        end
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
    now = MaterializationHelpers.now()
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

  defp insert_flow_nodes(_repo, _flow_id, [], _snapshot, _project_id, _now, _opts), do: {:ok, []}

  defp insert_flow_nodes(repo, flow_id, nodes_data, snapshot, project_id, now, opts) do
    entries =
      Enum.map(nodes_data, fn node_data ->
        %{
          flow_id: flow_id,
          type: node_data["type"],
          position_x: node_data["position_x"] || 0.0,
          position_y: node_data["position_y"] || 0.0,
          data:
            resolve_materialized_node_data(node_data["data"] || %{}, snapshot, project_id, opts),
          word_count: node_data["word_count"] || 0,
          source: node_data["source"] || "manual"
        }
        |> Map.merge(MaterializationHelpers.timestamps(now))
      end)

    MaterializationHelpers.insert_all_returning(repo, FlowNode, entries, [:id])
  end

  defp insert_flow_connections(_repo, _flow_id, [], _node_id_map, _now), do: {:ok, %{}}

  defp insert_flow_connections(repo, flow_id, connections_data, node_ids, now) do
    {entries, snapshots} =
      connections_data
      |> Enum.reduce({[], []}, fn conn, {acc_entries, acc_snapshots} ->
        source_node_id = Enum.at(node_ids, conn["source_node_index"])
        target_node_id = Enum.at(node_ids, conn["target_node_index"])

        if source_node_id && target_node_id do
          entry =
            %{
              flow_id: flow_id,
              source_node_id: source_node_id,
              target_node_id: target_node_id,
              source_pin: conn["source_pin"],
              target_pin: conn["target_pin"],
              label: conn["label"]
            }
            |> Map.merge(MaterializationHelpers.timestamps(now))

          {[entry | acc_entries], [conn | acc_snapshots]}
        else
          {acc_entries, acc_snapshots}
        end
      end)

    entries = Enum.reverse(entries)
    snapshots = Enum.reverse(snapshots)

    case MaterializationHelpers.insert_all_returning(repo, FlowConnection, entries, [:id]) do
      {:ok, inserted_connections} ->
        {:ok, MaterializationHelpers.build_id_map(snapshots, inserted_connections)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp resolve_materialized_node_data(data, snapshot, project_id, opts) do
    if MaterializationHelpers.preserve_external_refs?(opts) do
      resolve_node_asset_refs(data, snapshot, project_id)
    else
      Map.put(data, "audio_asset_id", nil)
    end
  end

  # ========== Diff Snapshots ==========

  # Fields excluded from node comparison (canvas position is noise)
  @node_ignore_fields ["position_x", "position_y", "word_count", "original_id"]

  @impl true
  def diff_snapshots(old_snapshot, new_snapshot) do
    []
    |> DiffHelpers.check_field_change(
      old_snapshot,
      new_snapshot,
      "name",
      :property,
      dgettext("flows", "Renamed flow")
    )
    |> DiffHelpers.check_field_change(
      old_snapshot,
      new_snapshot,
      "shortcut",
      :property,
      dgettext("flows", "Changed shortcut")
    )
    |> DiffHelpers.check_field_change(
      old_snapshot,
      new_snapshot,
      "description",
      :property,
      dgettext("flows", "Changed description")
    )
    |> DiffHelpers.check_field_change(
      old_snapshot,
      new_snapshot,
      "scene_id",
      :property,
      dgettext("flows", "Changed scene")
    )
    |> DiffHelpers.check_field_change(
      old_snapshot,
      new_snapshot,
      "settings",
      :property,
      dgettext("flows", "Changed settings")
    )
    |> diff_nodes_and_connections(
      old_snapshot["nodes"] || [],
      new_snapshot["nodes"] || [],
      old_snapshot["connections"] || [],
      new_snapshot["connections"] || []
    )
    |> Enum.reverse()
  end

  # Diff nodes first, then use node matching to normalize connection indexes
  # so that position-only moves don't produce phantom connection changes.
  defp diff_nodes_and_connections(changes, old_nodes, new_nodes, old_conns, new_conns) do
    # Build identity-based index maps so the positional fallback can find
    # a node's index within its own list (old or new) without scanning the
    # concatenated list, which broke when IDs were regenerated.
    old_pos = node_position_map(old_nodes)
    new_pos = node_position_map(new_nodes)

    key_fns = [
      # Primary: match by original_id (same DB session)
      & &1["original_id"],
      # Secondary: match by type + technical_id (stable across restores)
      fn node ->
        tid = get_in(node, ["data", "technical_id"])
        if tid && tid != "", do: {node["type"], tid}
      end,
      # Tertiary: match by type + position within list
      fn node ->
        idx = Map.get(old_pos, node_identity(node)) || Map.get(new_pos, node_identity(node))
        if idx, do: {:type_pos, node["type"], idx}
      end
    ]

    {matched, added, removed} = DiffHelpers.match_by_keys(old_nodes, new_nodes, key_fns)

    {modified, _unchanged} =
      DiffHelpers.find_modified(matched, fn old, new ->
        node_differs?(old, new)
      end)

    # Build old_index → new_index mapping from matched node pairs
    # so connections can be compared by semantic identity, not positional index
    old_node_index = old_nodes |> Enum.with_index() |> Map.new()
    new_node_index = new_nodes |> Enum.with_index() |> Map.new()

    old_index_to_new =
      matched
      |> Enum.reduce(%{}, fn {old_node, new_node}, acc ->
        old_idx = Map.get(old_node_index, old_node)
        new_idx = Map.get(new_node_index, new_node)
        if old_idx && new_idx, do: Map.put(acc, old_idx, new_idx), else: acc
      end)

    changes
    |> append_node_change_list(added, :added)
    |> append_node_change_list(removed, :removed)
    |> append_node_change_list_modified(modified)
    |> diff_connections(old_conns, new_conns, old_index_to_new)
  end

  defp node_differs?(old, new) do
    old_cleaned = Map.drop(old, @node_ignore_fields)
    new_cleaned = Map.drop(new, @node_ignore_fields)
    old_cleaned != new_cleaned
  end

  defp append_node_change_list(changes, [], _action), do: changes

  defp append_node_change_list(changes, nodes, action) do
    Enum.reduce(nodes, changes, fn node, acc ->
      type = node["type"] || "unknown"

      detail =
        case action do
          :added -> dgettext("flows", "Added %{type} node", type: type)
          :removed -> dgettext("flows", "Removed %{type} node", type: type)
        end

      [%{category: :node, action: action, detail: detail} | acc]
    end)
  end

  defp append_node_change_list_modified(changes, []), do: changes

  defp append_node_change_list_modified(changes, modified_pairs) do
    Enum.reduce(modified_pairs, changes, fn {_old, new}, acc ->
      type = new["type"] || "unknown"
      detail = dgettext("flows", "Modified %{type} node", type: type)
      [%{category: :node, action: :modified, detail: detail} | acc]
    end)
  end

  defp diff_connections(changes, old_conns, new_conns, old_index_to_new) do
    # Remap old connection indexes to new coordinate space so that
    # node position-only moves don't appear as connection changes.
    # Connections referencing removed nodes get unique sentinel indexes
    # so they won't falsely match new connections at the same raw index.
    remapped_old_conns =
      old_conns
      |> Enum.with_index()
      |> Enum.map(fn {conn, idx} ->
        new_src = Map.get(old_index_to_new, conn["source_node_index"])
        new_tgt = Map.get(old_index_to_new, conn["target_node_index"])

        if new_src && new_tgt do
          conn
          |> Map.put("source_node_index", new_src)
          |> Map.put("target_node_index", new_tgt)
        else
          # Node was removed — use unique sentinel to ensure this appears as removed
          conn
          |> Map.put("source_node_index", {:removed, idx})
          |> Map.put("target_node_index", {:removed, idx})
        end
      end)

    key_fn = fn conn ->
      {conn["source_node_index"], conn["target_node_index"], conn["source_pin"],
       conn["target_pin"]}
    end

    {matched, added, removed} = DiffHelpers.match_by_keys(remapped_old_conns, new_conns, [key_fn])

    {modified, _unchanged} =
      DiffHelpers.find_modified(matched, fn old, new ->
        DiffHelpers.fields_differ?(old, new, ["label"])
      end)

    changes
    |> append_conn_changes(added, :added)
    |> append_conn_changes(removed, :removed)
    |> append_conn_changes_modified(modified)
  end

  defp append_conn_changes(changes, [], _action), do: changes

  defp append_conn_changes(changes, conns, action) do
    Enum.reduce(conns, changes, fn _conn, acc ->
      detail =
        case action do
          :added -> dgettext("flows", "Added connection")
          :removed -> dgettext("flows", "Removed connection")
        end

      [%{category: :connection, action: action, detail: detail} | acc]
    end)
  end

  defp append_conn_changes_modified(changes, []), do: changes

  defp append_conn_changes_modified(changes, modified_pairs) do
    Enum.reduce(modified_pairs, changes, fn _pair, acc ->
      [
        %{
          category: :connection,
          action: :modified,
          detail: dgettext("flows", "Modified connection")
        }
        | acc
      ]
    end)
  end

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

  # Identity key for a snapshot node used by the positional fallback matcher.
  # Uses type + spatial position as a lightweight fingerprint.
  defp node_identity(node) do
    {node["type"], node["position_x"], node["position_y"]}
  end

  # Builds an identity → list-index map for a list of snapshot nodes.
  defp node_position_map(nodes) do
    nodes
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {node, idx}, acc ->
      Map.put_new(acc, node_identity(node), idx)
    end)
  end
end
