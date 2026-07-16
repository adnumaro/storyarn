defmodule Storyarn.Versioning.Builders.FlowBuilder do
  @moduledoc """
  Snapshot builder for flows.

  Captures flow metadata, nodes (sorted deterministically), and connections
  (referenced by node index rather than ID for portability).
  """

  @behaviour Storyarn.Versioning.SnapshotBuilder

  use Gettext, backend: Storyarn.Gettext

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowConnection
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.SequenceConfig
  alias Storyarn.Flows.SequenceTrack
  alias Storyarn.Flows.SequenceVisualLayer
  alias Storyarn.Localization
  alias Storyarn.Localization.TextCrud
  alias Storyarn.Repo
  alias Storyarn.Scenes.Scene
  alias Storyarn.Shared.WordCount
  alias Storyarn.Sheets
  alias Storyarn.Versioning.Builders.AssetHashResolver
  alias Storyarn.Versioning.Builders.FlowSnapshotNormalizer
  alias Storyarn.Versioning.DiffHelpers
  alias Storyarn.Versioning.LocalizationSnapshotCodec
  alias Storyarn.Versioning.MaterializationHelpers

  # ========== Build Snapshot ==========

  @impl true
  def build_snapshot(%Flow{} = flow) do
    flow =
      Repo.preload(flow, [
        :connections,
        nodes: [:sequence_config, :sequence_tracks, :sequence_visual_layers]
      ])

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

    # Collect asset IDs from node data and sequence composition.
    asset_ids =
      Enum.flat_map(sorted_nodes, fn node ->
        [(node.data || %{})["audio_asset_id"]] ++
          Enum.map(sequence_tracks(node), & &1.asset_id) ++
          Enum.map(sequence_visual_layers(node), & &1.asset_id)
      end)

    {hash_map, metadata_map} = AssetHashResolver.resolve_hashes(asset_ids)

    referenced_sheets = build_referenced_sheets(sorted_nodes, flow.project_id)

    localization =
      LocalizationSnapshotCodec.capture(flow.project_id, %{
        "flow_node" => Enum.map(sorted_nodes, & &1.id)
      })

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
      "referenced_sheets" => referenced_sheets,
      "localization" => localization
    }
  end

  defp node_to_snapshot(%FlowNode{} = node) do
    snapshot = %{
      "original_id" => node.id,
      "type" => node.type,
      "position_x" => node.position_x,
      "position_y" => node.position_y,
      "data" => node.data,
      "source" => node.source,
      "parent_id" => node.parent_id
    }

    if node.type == "sequence" do
      Map.merge(snapshot, %{
        "sequence_config" => sequence_config_to_snapshot(node.sequence_config),
        "sequence_tracks" =>
          node
          |> sequence_tracks()
          |> Enum.sort_by(&{&1.kind, &1.position, &1.id})
          |> Enum.map(&sequence_track_to_snapshot/1),
        "sequence_visual_layers" =>
          node
          |> sequence_visual_layers()
          |> Enum.sort_by(&{&1.z_index, &1.id})
          |> Enum.map(&sequence_visual_layer_to_snapshot/1)
      })
    else
      snapshot
    end
  end

  defp sequence_config_to_snapshot(%SequenceConfig{} = config) do
    %{
      "name" => config.name,
      "width" => config.width,
      "height" => config.height
    }
  end

  defp sequence_config_to_snapshot(_config), do: nil

  defp sequence_track_to_snapshot(%SequenceTrack{} = track) do
    %{
      "kind" => track.kind,
      "position" => track.position,
      "asset_id" => track.asset_id,
      "start_time" => decimal_to_snapshot(track.start_time),
      "end_time" => decimal_to_snapshot(track.end_time),
      "volume" => decimal_to_snapshot(track.volume)
    }
  end

  defp sequence_visual_layer_to_snapshot(%SequenceVisualLayer{} = layer) do
    %{
      "asset_id" => layer.asset_id,
      "kind" => layer.kind,
      "label" => layer.label,
      "z_index" => layer.z_index,
      "slot" => layer.slot,
      "x" => layer.x,
      "y" => layer.y,
      "width" => layer.width,
      "height" => layer.height,
      "anchor_x" => layer.anchor_x,
      "anchor_y" => layer.anchor_y,
      "fit" => layer.fit,
      "opacity" => layer.opacity,
      "visible" => layer.visible
    }
  end

  defp decimal_to_snapshot(nil), do: nil
  defp decimal_to_snapshot(%Decimal{} = value), do: Decimal.to_string(value, :normal)

  defp sequence_tracks(%FlowNode{sequence_tracks: tracks}) when is_list(tracks), do: tracks
  defp sequence_tracks(_node), do: []

  defp sequence_visual_layers(%FlowNode{sequence_visual_layers: layers}) when is_list(layers), do: layers
  defp sequence_visual_layers(_node), do: []

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
    snapshot = FlowSnapshotNormalizer.normalize(snapshot)

    fn -> instantiate_flow_snapshot(project_id, snapshot, opts) end
    |> Repo.transaction()
    |> finalize_flow_instantiation()
  end

  defp instantiate_flow_snapshot(project_id, snapshot, opts) do
    now = MaterializationHelpers.now()
    nodes = Map.get(snapshot, "nodes", [])
    connections = Map.get(snapshot, "connections", [])

    with {:ok, flow_id} <-
           MaterializationHelpers.insert_one_returning_id(
             Repo,
             Flow,
             flow_snapshot_attrs(project_id, snapshot, opts, now)
           ),
         {:ok, inserted_nodes} <- insert_flow_nodes(Repo, flow_id, nodes, snapshot, project_id, now, opts),
         node_id_map = MaterializationHelpers.build_id_map(nodes, inserted_nodes),
         {:ok, _linked_parents} <- link_snapshot_node_parents(Repo, nodes, node_id_map),
         {:ok, _sequence_resources} <-
           insert_sequence_resources(Repo, nodes, inserted_nodes, snapshot, project_id, opts, now),
         {:ok, connection_id_map} <-
           insert_flow_connections(
             Repo,
             flow_id,
             connections,
             nodes,
             Enum.map(inserted_nodes, & &1.id),
             node_id_map,
             now
           ) do
      complete_flow_instantiation(project_id, snapshot, flow_id, node_id_map, connection_id_map)
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp flow_snapshot_attrs(project_id, snapshot, opts, now) do
    Map.merge(
      %{
        project_id: project_id,
        name: snapshot["name"],
        shortcut: MaterializationHelpers.root_shortcut(snapshot, opts),
        description: snapshot["description"],
        is_main: snapshot["is_main"] || false,
        settings: snapshot["settings"] || %{},
        scene_id:
          MaterializationHelpers.resolve_project_external_ref(snapshot["scene_id"], Scene, :scene, project_id, opts),
        parent_id: MaterializationHelpers.root_parent_id(opts),
        position: MaterializationHelpers.root_position(opts)
      },
      MaterializationHelpers.timestamps(now)
    )
  end

  defp complete_flow_instantiation(project_id, snapshot, flow_id, node_id_map, connection_id_map) do
    flow =
      Flow
      |> Repo.get!(flow_id)
      |> Repo.preload(
        [:connections, nodes: [:sequence_config, :sequence_tracks, :sequence_visual_layers]],
        force: true
      )

    id_maps = %{
      flow: MaterializationHelpers.root_id_map(snapshot, flow_id),
      node: node_id_map,
      connection: connection_id_map
    }

    case LocalizationSnapshotCodec.restore(project_id, Map.get(snapshot, "localization", []), id_maps) do
      :ok -> {flow, id_maps}
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp finalize_flow_instantiation(result) do
    case result do
      {:ok, {flow, id_maps}} ->
        Localization.extract_flow_nodes(flow.id)
        {:ok, flow, id_maps}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def restore_snapshot(%Flow{} = flow, snapshot, opts \\ []) do
    snapshot = FlowSnapshotNormalizer.normalize(snapshot)
    localization_rows = Map.get(snapshot, "localization", [])

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
            Scene,
            :scene,
            flow.project_id,
            opts
          )
      })
    end)
    |> Multi.run(:archive_localization, fn _repo, _changes ->
      node_ids = Repo.all(from(n in FlowNode, where: n.flow_id == ^flow.id, select: n.id))
      TextCrud.archive_texts_for_sources("flow_node", node_ids, "version_replaced")
      {:ok, length(node_ids)}
    end)
    |> Multi.delete_all(:delete_connections, fn _changes ->
      from(c in FlowConnection, where: c.flow_id == ^flow.id)
    end)
    |> Multi.delete_all(:delete_nodes, fn _changes ->
      from(n in FlowNode, where: n.flow_id == ^flow.id)
    end)
    |> Multi.run(:restore_nodes, fn repo, _changes ->
      restore_nodes(repo, flow.id, snapshot["nodes"] || [], snapshot, flow.project_id, opts)
    end)
    |> Multi.run(:restore_connections, fn repo, %{restore_nodes: node_data} ->
      restore_connections(
        repo,
        flow.id,
        snapshot["connections"] || [],
        snapshot["nodes"] || [],
        node_data.node_ids,
        node_data.node_id_map
      )
    end)
    |> Multi.run(:restore_localization, fn _repo, %{restore_nodes: node_data} ->
      case LocalizationSnapshotCodec.restore(flow.project_id, localization_rows, %{node: node_data.node_id_map}) do
        :ok -> {:ok, length(localization_rows)}
        {:error, reason} -> {:error, reason}
      end
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{flow: updated_flow, restore_nodes: node_data}} ->
        Localization.extract_flow_nodes(updated_flow.id)

        restored_flow =
          Repo.preload(
            updated_flow,
            [:connections, nodes: [:sequence_config, :sequence_tracks, :sequence_visual_layers]],
            force: true
          )

        if Keyword.get(opts, :return_id_maps, false) do
          id_maps = %{
            flow: MaterializationHelpers.root_id_map(snapshot, updated_flow.id),
            node: node_data.node_id_map
          }

          {:ok, restored_flow, id_maps}
        else
          {:ok, restored_flow}
        end

      {:error, _op, reason, _changes} ->
        {:error, reason}
    end
  end

  defp restore_nodes(_repo, _flow_id, [], _snapshot, _project_id, _opts), do: {:ok, %{node_ids: [], node_id_map: %{}}}

  defp restore_nodes(repo, flow_id, nodes_data, snapshot, project_id, opts) do
    now = MaterializationHelpers.now()

    with {:ok, nodes} <-
           insert_snapshot_nodes(nodes_data, fn node_data ->
             data = resolve_node_asset_refs(node_data["data"] || %{}, snapshot, project_id, opts)
             insert_snapshot_node(repo, flow_id, node_data, data, now)
           end),
         node_ids = Enum.map(nodes, & &1.id),
         node_id_map = restored_node_id_map(nodes_data, node_ids),
         {:ok, _linked_parents} <- link_snapshot_node_parents(repo, nodes_data, node_id_map),
         {:ok, _sequence_resources} <-
           insert_sequence_resources(repo, nodes_data, nodes, snapshot, project_id, opts, now) do
      {:ok, %{node_ids: node_ids, node_id_map: node_id_map}}
    end
  end

  defp insert_snapshot_nodes(nodes_data, insert_fun) do
    nodes_data
    |> Enum.reduce_while({:ok, []}, fn node_data, {:ok, nodes} ->
      case insert_fun.(node_data) do
        {:ok, node} -> {:cont, {:ok, [node | nodes]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, nodes} -> {:ok, Enum.reverse(nodes)}
      error -> error
    end
  end

  defp insert_snapshot_node(repo, flow_id, node_data, data, now) do
    %FlowNode{flow_id: flow_id, inserted_at: now, updated_at: now}
    |> FlowNode.materialize_changeset(%{
      type: node_data["type"],
      position_x: node_data["position_x"] || 0.0,
      position_y: node_data["position_y"] || 0.0,
      data: data,
      word_count: WordCount.for_node_data(node_data["type"], data),
      source: node_data["source"] || "manual"
    })
    |> repo.insert()
  end

  defp restored_node_id_map(nodes_data, node_ids) do
    nodes_data
    |> Enum.zip(node_ids)
    |> Enum.reduce(%{}, fn {node_data, new_id}, acc ->
      case node_data["original_id"] do
        nil -> acc
        old_id -> Map.put(acc, old_id, new_id)
      end
    end)
  end

  defp link_snapshot_node_parents(repo, nodes_data, node_id_map) do
    nodes_by_original_id =
      nodes_data
      |> Enum.reject(&is_nil(&1["original_id"]))
      |> Map.new(&{&1["original_id"], &1})

    Enum.reduce_while(nodes_data, {:ok, 0}, fn node_data, acc ->
      link_snapshot_node_parent(repo, node_data, acc, nodes_by_original_id, node_id_map)
    end)
  end

  defp link_snapshot_node_parent(repo, node_data, acc, nodes_by_original_id, node_id_map) do
    link_snapshot_node_parent(
      repo,
      node_data,
      acc,
      nodes_by_original_id,
      node_id_map,
      node_data["parent_id"]
    )
  end

  defp link_snapshot_node_parent(_repo, _node_data, {:ok, count}, _nodes_by_original_id, _node_id_map, nil) do
    {:cont, {:ok, count}}
  end

  defp link_snapshot_node_parent(repo, node_data, {:ok, count}, nodes_by_original_id, node_id_map, parent_original_id) do
    with %{"type" => "sequence"} <- Map.get(nodes_by_original_id, parent_original_id),
         child_id when is_integer(child_id) <- Map.get(node_id_map, node_data["original_id"]),
         parent_id when is_integer(parent_id) <- Map.get(node_id_map, parent_original_id),
         false <- child_id == parent_id,
         %FlowNode{} = child <- repo.get(FlowNode, child_id),
         {:ok, _updated_child} <-
           child
           |> FlowNode.reparent_changeset(%{parent_id: parent_id})
           |> repo.update() do
      {:cont, {:ok, count + 1}}
    else
      reason ->
        {:halt, {:error, {:invalid_snapshot_node_parent, node_data["original_id"], parent_original_id, reason}}}
    end
  end

  defp insert_sequence_resources(repo, nodes_data, inserted_nodes, snapshot, project_id, opts, now) do
    nodes_data
    |> Enum.zip(inserted_nodes)
    |> Enum.reduce_while({:ok, %{configs: 0, tracks: 0, visual_layers: 0}}, fn
      {%{"type" => "sequence"} = node_data, %{id: node_id}}, {:ok, counts} ->
        with {:ok, config_count} <- insert_sequence_config(repo, node_id, node_data["sequence_config"], now),
             {:ok, track_count} <-
               insert_sequence_tracks(
                 repo,
                 node_id,
                 node_data["sequence_tracks"] || [],
                 snapshot,
                 project_id,
                 opts,
                 now
               ),
             {:ok, layer_count} <-
               insert_sequence_visual_layers(
                 repo,
                 node_id,
                 node_data["sequence_visual_layers"] || [],
                 snapshot,
                 project_id,
                 opts,
                 now
               ) do
          {:cont,
           {:ok,
            %{
              configs: counts.configs + config_count,
              tracks: counts.tracks + track_count,
              visual_layers: counts.visual_layers + layer_count
            }}}
        else
          {:error, reason} -> {:halt, {:error, reason}}
        end

      {_node_data, _inserted_node}, {:ok, counts} ->
        {:cont, {:ok, counts}}
    end)
  end

  defp insert_sequence_config(_repo, _node_id, nil, _now), do: {:ok, 0}

  defp insert_sequence_config(repo, node_id, config_data, now) when is_map(config_data) do
    attrs =
      config_data
      |> Map.take(["name", "width", "height"])
      |> Map.put("flow_node_id", node_id)

    %SequenceConfig{inserted_at: now, updated_at: now}
    |> SequenceConfig.create_changeset(attrs)
    |> repo.insert()
    |> inserted_resource_count()
  end

  defp insert_sequence_config(_repo, _node_id, config_data, _now) do
    {:error, {:invalid_sequence_config_snapshot, config_data}}
  end

  defp insert_sequence_tracks(repo, node_id, tracks, snapshot, project_id, opts, now) when is_list(tracks) do
    insert_sequence_items(tracks, fn track_data ->
      asset_id = resolve_flow_asset(track_data["asset_id"], snapshot, project_id, opts)

      attrs =
        track_data
        |> Map.take(["kind", "position", "start_time", "end_time", "volume"])
        |> Map.put("flow_node_id", node_id)
        |> Map.put("asset_id", asset_id)

      %SequenceTrack{inserted_at: now, updated_at: now}
      |> SequenceTrack.create_changeset(attrs)
      |> repo.insert()
    end)
  end

  defp insert_sequence_tracks(_repo, _node_id, tracks, _snapshot, _project_id, _opts, _now) do
    {:error, {:invalid_sequence_tracks_snapshot, tracks}}
  end

  defp insert_sequence_visual_layers(repo, node_id, layers, snapshot, project_id, opts, now) when is_list(layers) do
    if flow_asset_mode(opts) == :drop do
      {:ok, 0}
    else
      insert_sequence_visual_layer_items(repo, node_id, layers, snapshot, project_id, opts, now)
    end
  end

  defp insert_sequence_visual_layers(_repo, _node_id, layers, _snapshot, _project_id, _opts, _now) do
    {:error, {:invalid_sequence_visual_layers_snapshot, layers}}
  end

  defp insert_sequence_visual_layer_items(repo, node_id, layers, snapshot, project_id, opts, now) do
    insert_sequence_items(layers, fn layer_data ->
      asset_id = resolve_flow_asset(layer_data["asset_id"], snapshot, project_id, opts)
      insert_sequence_visual_layer(repo, node_id, layer_data, asset_id, now)
    end)
  end

  defp insert_sequence_visual_layer(_repo, _node_id, layer_data, nil, _now) do
    {:error, {:missing_sequence_visual_layer_asset, layer_data["asset_id"]}}
  end

  defp insert_sequence_visual_layer(repo, node_id, layer_data, asset_id, now) do
    attrs =
      layer_data
      |> Map.take([
        "kind",
        "label",
        "z_index",
        "slot",
        "x",
        "y",
        "width",
        "height",
        "anchor_x",
        "anchor_y",
        "fit",
        "opacity",
        "visible"
      ])
      |> Map.put("flow_node_id", node_id)
      |> Map.put("asset_id", asset_id)

    %SequenceVisualLayer{inserted_at: now, updated_at: now}
    |> SequenceVisualLayer.create_changeset(attrs)
    |> repo.insert()
  end

  defp insert_sequence_items(items, insert_fun) do
    Enum.reduce_while(items, {:ok, 0}, fn item, {:ok, count} ->
      result =
        if is_map(item) do
          insert_fun.(item)
        else
          {:error, {:invalid_sequence_resource_snapshot, item}}
        end

      case result do
        {:ok, _resource} -> {:cont, {:ok, count + 1}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp inserted_resource_count({:ok, _resource}), do: {:ok, 1}
  defp inserted_resource_count({:error, reason}), do: {:error, reason}

  defp resolve_node_asset_refs(data, snapshot, project_id, opts) do
    case data["audio_asset_id"] do
      nil ->
        data

      audio_id ->
        resolved = resolve_flow_asset(audio_id, snapshot, project_id, opts)
        Map.put(data, "audio_asset_id", resolved)
    end
  end

  defp restore_connections(_repo, _flow_id, [], _nodes_data, _node_ids, _node_id_map), do: {:ok, 0}

  defp restore_connections(repo, flow_id, connections_data, nodes_data, node_ids, node_id_map) do
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
        source_node = Enum.at(nodes_data, conn["source_node_index"])

        %{
          flow_id: flow_id,
          source_node_id: Map.fetch!(index_to_id, conn["source_node_index"]),
          target_node_id: Map.fetch!(index_to_id, conn["target_node_index"]),
          source_pin: remap_dynamic_pin(conn["source_pin"], source_node && source_node["type"], node_id_map),
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
    used_localization_ids = existing_dialogue_localization_ids(repo, project_id)

    {prepared_nodes, _used_localization_ids} =
      Enum.map_reduce(nodes_data, used_localization_ids, fn node_data, used_ids ->
        data = resolve_materialized_node_data(node_data["data"] || %{}, snapshot, project_id, opts)
        {data, used_ids} = ensure_unique_dialogue_id(node_data["type"], data, used_ids)
        {{node_data, data}, used_ids}
      end)

    changesets =
      Enum.map(prepared_nodes, fn {node_data, data} ->
        materialized_node_changeset(flow_id, node_data, data, now)
      end)

    case Enum.find(changesets, &(not &1.valid?)) do
      nil -> insert_materialized_nodes(repo, changesets)
      invalid_changeset -> {:error, invalid_changeset}
    end
  end

  defp existing_dialogue_localization_ids(repo, project_id) do
    from(node in FlowNode,
      join: flow in Flow,
      on: flow.id == node.flow_id,
      where: flow.project_id == ^project_id and node.type == "dialogue",
      select: fragment("?->>'localization_id'", node.data)
    )
    |> repo.all()
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
  end

  defp ensure_unique_dialogue_id("dialogue", %{"localization_id" => localization_id} = data, used_ids)
       when is_binary(localization_id) and localization_id != "" do
    if MapSet.member?(used_ids, localization_id) do
      new_id = unused_dialogue_id(used_ids)
      {Map.put(data, "localization_id", new_id), MapSet.put(used_ids, new_id)}
    else
      {data, MapSet.put(used_ids, localization_id)}
    end
  end

  defp ensure_unique_dialogue_id(_type, data, used_ids), do: {data, used_ids}

  defp unused_dialogue_id(used_ids) do
    candidate = "dialogue_#{Ecto.UUID.generate()}"
    if MapSet.member?(used_ids, candidate), do: unused_dialogue_id(used_ids), else: candidate
  end

  defp materialized_node_changeset(flow_id, node_data, data, now) do
    FlowNode.materialize_changeset(%FlowNode{flow_id: flow_id, inserted_at: now, updated_at: now}, %{
      type: node_data["type"],
      position_x: node_data["position_x"] || 0.0,
      position_y: node_data["position_y"] || 0.0,
      data: data,
      word_count: WordCount.for_node_data(node_data["type"], data),
      source: node_data["source"] || "manual"
    })
  end

  defp insert_materialized_nodes(repo, changesets) do
    entries =
      Enum.map(changesets, fn changeset ->
        changeset
        |> Ecto.Changeset.apply_changes()
        |> Map.from_struct()
        |> Map.take([
          :flow_id,
          :type,
          :position_x,
          :position_y,
          :data,
          :word_count,
          :source,
          :parent_id,
          :inserted_at,
          :updated_at
        ])
      end)

    case repo.insert_all(FlowNode, entries, returning: [:id]) do
      {count, nodes} when count == length(entries) -> {:ok, nodes}
      other -> {:error, {:node_materialization_failed, other}}
    end
  end

  defp insert_flow_connections(_repo, _flow_id, [], _nodes_data, _node_ids, _node_id_map, _now), do: {:ok, %{}}

  defp insert_flow_connections(repo, flow_id, connections_data, nodes_data, node_ids, node_id_map, now) do
    {entries, snapshots} =
      Enum.reduce(connections_data, {[], []}, fn conn, {acc_entries, acc_snapshots} ->
        source_node_id = Enum.at(node_ids, conn["source_node_index"])
        target_node_id = Enum.at(node_ids, conn["target_node_index"])

        if source_node_id && target_node_id do
          source_node = Enum.at(nodes_data, conn["source_node_index"])

          entry =
            Map.merge(
              %{
                flow_id: flow_id,
                source_node_id: source_node_id,
                target_node_id: target_node_id,
                source_pin: remap_dynamic_pin(conn["source_pin"], source_node && source_node["type"], node_id_map),
                target_pin: conn["target_pin"],
                label: conn["label"]
              },
              MaterializationHelpers.timestamps(now)
            )

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
    case flow_asset_mode(opts) do
      :drop -> Map.put(data, "audio_asset_id", nil)
      _asset_mode -> resolve_node_asset_refs(data, snapshot, project_id, opts)
    end
  end

  defp resolve_flow_asset(asset_id, snapshot, project_id, opts) do
    case flow_asset_mode(opts) do
      :drop ->
        nil

      asset_mode ->
        AssetHashResolver.resolve_asset_fk(
          asset_id,
          snapshot,
          project_id,
          Keyword.get(opts, :user_id),
          MaterializationHelpers.asset_resolution_opts(opts, asset_mode)
        )
    end
  end

  defp flow_asset_mode(opts) do
    cond do
      mode = Keyword.get(opts, :asset_mode) ->
        mode

      MaterializationHelpers.preserve_external_refs?(opts) ->
        :reuse

      true ->
        :drop
    end
  end

  defp remap_dynamic_pin("exit_" <> old_id_text = pin, "subflow", node_id_map) do
    case Integer.parse(old_id_text) do
      {old_id, ""} ->
        case Map.get(node_id_map, old_id) do
          nil -> pin
          new_id -> "exit_#{new_id}"
        end

      _ ->
        pin
    end
  end

  defp remap_dynamic_pin(pin, _source_node_type, _node_id_map), do: pin

  # ========== Diff Snapshots ==========

  # Fields excluded from node comparison (canvas position and denormalized counts are noise)
  @node_ignore_fields ["position_x", "position_y", "original_id", "word_count"]

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

    {old_parent_tokens, new_parent_tokens} = parent_identity_tokens(matched)

    {modified, _unchanged} =
      DiffHelpers.find_modified(matched, fn old, new ->
        node_differs?(old, new, old_parent_tokens, new_parent_tokens)
      end)

    # Build old_index → new_index mapping from matched node pairs
    # so connections can be compared by semantic identity, not positional index
    old_node_index = old_nodes |> Enum.with_index() |> Map.new()
    new_node_index = new_nodes |> Enum.with_index() |> Map.new()

    old_index_to_new =
      Enum.reduce(matched, %{}, fn {old_node, new_node}, acc ->
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

  defp parent_identity_tokens(matched) do
    matched
    |> Enum.with_index()
    |> Enum.reduce({%{}, %{}}, fn {{old_node, new_node}, token}, {old_tokens, new_tokens} ->
      {
        maybe_put_parent_token(old_tokens, old_node["original_id"], token),
        maybe_put_parent_token(new_tokens, new_node["original_id"], token)
      }
    end)
  end

  defp maybe_put_parent_token(tokens, nil, _token), do: tokens
  defp maybe_put_parent_token(tokens, node_id, token), do: Map.put(tokens, node_id, token)

  defp node_differs?(old, new, old_parent_tokens, new_parent_tokens) do
    old_cleaned = normalize_node_for_diff(old, old_parent_tokens)
    new_cleaned = normalize_node_for_diff(new, new_parent_tokens)
    old_cleaned != new_cleaned
  end

  defp normalize_node_for_diff(node, parent_tokens) do
    node
    |> Map.drop(@node_ignore_fields)
    |> Map.update("parent_id", nil, &Map.get(parent_tokens, &1, {:unmatched_parent, &1}))
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
      {conn["source_node_index"], conn["target_node_index"], conn["source_pin"], conn["target_pin"]}
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

        acc =
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

        add_sequence_asset_refs(acc, node, idx)
      end)

    refs
  end

  defp maybe_add_ref(refs, _type, nil, _context), do: refs

  defp maybe_add_ref(refs, type, id, context), do: [%{type: type, id: id, context: context} | refs]

  defp add_sequence_asset_refs(refs, node, node_index) do
    refs =
      node
      |> snapshot_collection("sequence_tracks")
      |> Enum.with_index(1)
      |> Enum.reduce(refs, fn {track, track_index}, acc ->
        if is_map(track) do
          maybe_add_ref(
            acc,
            :asset,
            track["asset_id"],
            dgettext("flows", "Node #%{n} sequence track #%{track} — audio",
              n: node_index,
              track: track_index
            )
          )
        else
          acc
        end
      end)

    node
    |> snapshot_collection("sequence_visual_layers")
    |> Enum.with_index(1)
    |> Enum.reduce(refs, fn {layer, layer_index}, acc ->
      if is_map(layer) do
        maybe_add_ref(
          acc,
          :asset,
          layer["asset_id"],
          dgettext("flows", "Node #%{n} sequence visual layer #%{layer}",
            n: node_index,
            layer: layer_index
          )
        )
      else
        acc
      end
    end)
  end

  defp snapshot_collection(snapshot, key) when is_map(snapshot) do
    case Map.get(snapshot, key, []) do
      collection when is_list(collection) -> collection
      _malformed -> []
    end
  end

  defp snapshot_collection(_snapshot, _key), do: []

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
