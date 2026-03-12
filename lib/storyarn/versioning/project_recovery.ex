defmodule Storyarn.Versioning.ProjectRecovery do
  @moduledoc """
  Creates a new project from a project snapshot with full ID remapping.

  Unlike `ProjectSnapshotBuilder.restore_snapshot/3` which restores into an
  existing project by matching entity IDs, this module creates brand new entities
  from snapshot data and remaps all internal cross-references to point to the
  new autoincrement IDs.
  """

  require Logger

  import Ecto.Query, warn: false

  alias Storyarn.Flows.{FlowConnection, FlowNode}
  alias Storyarn.Localization.{GlossaryEntry, LocalizedText, ProjectLanguage}
  alias Storyarn.Projects.{Project, ProjectMembership}
  alias Storyarn.Repo
  alias Storyarn.Scenes.{SceneAnnotation, SceneConnection, SceneLayer, ScenePin, SceneZone}
  alias Storyarn.Shared.{NameNormalizer, TimeHelpers}
  alias Storyarn.Sheets.{Block, TableColumn, TableRow}
  alias Storyarn.Versioning.Builders.AssetHashResolver

  @doc """
  Recovers a project from snapshot data by creating a new project with all entities.

  Creates fresh entities with new IDs and remaps all internal cross-references.
  Runs in a single transaction with a 5-minute timeout.

  ## Options
  - `:name` - Override the recovered project name (default: "{original} (Recovered)")
  """
  @spec recover_project(integer(), map(), integer(), keyword()) ::
          {:ok, Project.t()} | {:error, term()}
  def recover_project(workspace_id, snapshot_data, user_id, opts \\ []) do
    name = Keyword.get(opts, :name, "Recovered Project")

    Repo.transaction(
      fn ->
        case do_recover(workspace_id, snapshot_data, user_id, name) do
          {:ok, project} -> project
          {:error, reason} -> Repo.rollback(reason)
        end
      end,
      timeout: :timer.minutes(5)
    )
  end

  defp do_recover(workspace_id, snapshot_data, user_id, name) do
    now = TimeHelpers.now()

    with {:ok, project} <- create_project(workspace_id, user_id, name),
         {:ok, _membership} <- create_owner_membership(project, user_id) do
      # Phase A: Create entities and collect ID maps
      {sheet_id_map, block_id_map} = recover_sheets(project.id, snapshot_data, now)
      {flow_id_map, node_id_map} = recover_flows(project.id, snapshot_data, now)
      scene_id_map = recover_scenes(project.id, snapshot_data, now)

      id_maps = %{
        sheet: sheet_id_map,
        block: block_id_map,
        flow: flow_id_map,
        node: node_id_map,
        scene: scene_id_map
      }

      # Phase B: Remap cross-entity references
      remap_flow_refs(id_maps, snapshot_data)
      remap_scene_refs(id_maps, snapshot_data)
      remap_block_inheritance(block_id_map)

      # Phase C: Restore tree hierarchy
      restore_tree_hierarchy(snapshot_data, id_maps)

      # Phase D: Restore localization
      recover_localization(project.id, snapshot_data, id_maps, now)

      {:ok, project}
    end
  end

  # ========== Project Creation ==========

  defp create_project(workspace_id, user_id, name) do
    slug = NameNormalizer.generate_unique_slug(Project, [workspace_id: workspace_id], name)

    %Project{owner_id: user_id}
    |> Project.create_changeset(%{
      name: name,
      slug: slug,
      workspace_id: workspace_id
    })
    |> Repo.insert()
  end

  defp create_owner_membership(project, user_id) do
    %ProjectMembership{}
    |> ProjectMembership.changeset(%{project_id: project.id, user_id: user_id, role: "owner"})
    |> Repo.insert()
  end

  # ========== Phase A: Create Entities ==========

  defp recover_sheets(project_id, snapshot_data, now) do
    sheet_entries = snapshot_data["sheets"] || []

    Enum.reduce(sheet_entries, {%{}, %{}}, fn entry, {s_map, b_map} ->
      old_id = entry["id"]
      snapshot = entry["snapshot"]

      {new_sheet_id, new_block_ids} = insert_sheet(project_id, snapshot, now)
      new_s_map = Map.put(s_map, old_id, new_sheet_id)
      new_b_map = build_block_id_map(snapshot["blocks"] || [], new_block_ids, b_map)

      {new_s_map, new_b_map}
    end)
  end

  defp build_block_id_map(blocks_data, new_block_ids, existing_map) do
    blocks_data
    |> Enum.zip(new_block_ids)
    |> Enum.reduce(existing_map, fn {block_data, new_id}, acc ->
      case block_data["original_id"] do
        nil -> acc
        old_block_id -> Map.put(acc, old_block_id, new_id)
      end
    end)
  end

  defp insert_sheet(project_id, snapshot, now) do
    sheet_attrs = %{
      project_id: project_id,
      name: snapshot["name"],
      shortcut: snapshot["shortcut"],
      description: nil,
      color: nil,
      avatar_asset_id: nil,
      banner_asset_id: nil,
      position: 0,
      inserted_at: now,
      updated_at: now
    }

    {1, [%{id: sheet_id}]} =
      Repo.insert_all(Storyarn.Sheets.Sheet, [sheet_attrs], returning: [:id])

    # Resolve asset FKs after sheet creation
    resolve_and_update_sheet_assets(sheet_id, snapshot, project_id)

    # Insert blocks
    block_ids = insert_sheet_blocks(sheet_id, snapshot["blocks"] || [], now)

    {sheet_id, block_ids}
  end

  defp resolve_and_update_sheet_assets(sheet_id, snapshot, project_id) do
    avatar_id =
      AssetHashResolver.resolve_asset_fk(snapshot["avatar_asset_id"], snapshot, project_id)

    banner_id =
      AssetHashResolver.resolve_asset_fk(snapshot["banner_asset_id"], snapshot, project_id)

    if avatar_id || banner_id do
      from(s in Storyarn.Sheets.Sheet, where: s.id == ^sheet_id)
      |> Repo.update_all(set: [avatar_asset_id: avatar_id, banner_asset_id: banner_id])
    end
  end

  defp insert_sheet_blocks(_sheet_id, [], _now), do: []

  defp insert_sheet_blocks(sheet_id, blocks_data, now) do
    sorted = Enum.sort_by(blocks_data, & &1["position"])

    block_entries =
      Enum.map(sorted, fn block_data ->
        %{
          sheet_id: sheet_id,
          type: block_data["type"],
          position: block_data["position"],
          config: block_data["config"] || %{},
          value: block_data["value"] || %{},
          is_constant: block_data["is_constant"] || false,
          variable_name: block_data["variable_name"],
          scope: block_data["scope"] || "self",
          inherited_from_block_id: block_data["inherited_from_block_id"],
          detached: block_data["detached"] || false,
          required: block_data["required"] || false,
          inserted_at: now,
          updated_at: now
        }
      end)

    {_count, inserted} =
      Repo.insert_all(Block, block_entries, returning: [:id, :type, :position])

    restore_block_table_data(inserted, sorted, now)
    Enum.map(inserted, & &1.id)
  end

  defp restore_block_table_data(inserted_blocks, sorted_data, now) do
    inserted_by_position = Map.new(inserted_blocks, &{&1.position, &1})

    sorted_data
    |> Enum.filter(&(&1["type"] == "table" && is_map(&1["table_data"])))
    |> Enum.each(fn block_data ->
      case Map.get(inserted_by_position, block_data["position"]) do
        nil -> :skip
        block -> insert_table_data(block.id, block_data["table_data"], now)
      end
    end)
  end

  defp insert_table_data(block_id, table_data, now) do
    columns = Map.get(table_data, "columns", [])

    if columns != [] do
      entries =
        Enum.map(columns, fn col ->
          %{
            block_id: block_id,
            name: col["name"],
            slug: col["slug"],
            type: col["type"],
            is_constant: col["is_constant"] || false,
            required: col["required"] || false,
            position: col["position"] || 0,
            config: col["config"] || %{},
            inserted_at: now,
            updated_at: now
          }
        end)

      Repo.insert_all(TableColumn, entries)
    end

    rows = Map.get(table_data, "rows", [])

    if rows != [] do
      entries =
        Enum.map(rows, fn row ->
          %{
            block_id: block_id,
            name: row["name"],
            slug: row["slug"],
            position: row["position"] || 0,
            cells: row["cells"] || %{},
            inserted_at: now,
            updated_at: now
          }
        end)

      Repo.insert_all(TableRow, entries)
    end
  end

  defp recover_flows(project_id, snapshot_data, now) do
    flow_entries = snapshot_data["flows"] || []

    Enum.reduce(flow_entries, {%{}, %{}}, fn entry, {f_map, n_map} ->
      old_id = entry["id"]
      snapshot = entry["snapshot"]

      {new_flow_id, node_ids, nodes_data} = insert_flow(project_id, snapshot, now)
      new_f_map = Map.put(f_map, old_id, new_flow_id)

      new_n_map = build_node_id_map(nodes_data, node_ids, n_map)

      {new_f_map, new_n_map}
    end)
  end

  defp build_node_id_map(nodes_data, node_ids, existing_map) do
    nodes_data
    |> Enum.zip(node_ids)
    |> Enum.reduce(existing_map, fn {node_data, new_id}, acc ->
      case node_data["original_id"] do
        nil -> acc
        old_node_id -> Map.put(acc, old_node_id, new_id)
      end
    end)
  end

  defp insert_flow(project_id, snapshot, now) do
    flow_attrs = %{
      project_id: project_id,
      name: snapshot["name"],
      shortcut: snapshot["shortcut"],
      description: snapshot["description"],
      is_main: snapshot["is_main"] || false,
      settings: snapshot["settings"] || %{},
      scene_id: nil,
      position: 0,
      inserted_at: now,
      updated_at: now
    }

    {1, [%{id: flow_id}]} =
      Repo.insert_all(Storyarn.Flows.Flow, [flow_attrs], returning: [:id])

    # Insert nodes
    nodes_data = snapshot["nodes"] || []
    node_ids = insert_flow_nodes(flow_id, nodes_data, snapshot, project_id, now)

    # Insert connections using index-based mapping
    insert_flow_connections(flow_id, snapshot["connections"] || [], node_ids, now)

    {flow_id, node_ids, nodes_data}
  end

  defp insert_flow_nodes(_flow_id, [], _snapshot, _project_id, _now), do: []

  defp insert_flow_nodes(flow_id, nodes_data, snapshot, project_id, now) do
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

      {1, [%{id: id}]} = Repo.insert_all(FlowNode, [attrs], returning: [:id])
      id
    end)
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

  defp insert_flow_connections(_flow_id, [], _node_ids, _now), do: :ok

  defp insert_flow_connections(flow_id, connections_data, node_ids, now) do
    node_count = length(node_ids)
    index_to_id = node_ids |> Enum.with_index() |> Map.new(fn {id, idx} -> {idx, id} end)

    entries =
      connections_data
      |> Enum.filter(fn conn ->
        s = conn["source_node_index"]
        t = conn["target_node_index"]
        s >= 0 and s < node_count and t >= 0 and t < node_count
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

    if entries != [], do: Repo.insert_all(FlowConnection, entries)
  end

  defp recover_scenes(project_id, snapshot_data, now) do
    scene_entries = snapshot_data["scenes"] || []

    Enum.reduce(scene_entries, %{}, fn entry, acc ->
      old_id = entry["id"]
      snapshot = entry["snapshot"]

      new_scene_id = insert_scene(project_id, snapshot, now)
      Map.put(acc, old_id, new_scene_id)
    end)
  end

  defp insert_scene(project_id, snapshot, now) do
    scene_attrs = %{
      project_id: project_id,
      name: snapshot["name"],
      shortcut: snapshot["shortcut"],
      description: snapshot["description"],
      width: snapshot["width"],
      height: snapshot["height"],
      default_zoom: snapshot["default_zoom"],
      default_center_x: snapshot["default_center_x"],
      default_center_y: snapshot["default_center_y"],
      scale_unit: snapshot["scale_unit"],
      scale_value: snapshot["scale_value"],
      background_asset_id: nil,
      position: 0,
      inserted_at: now,
      updated_at: now
    }

    {1, [%{id: scene_id}]} =
      Repo.insert_all(Storyarn.Scenes.Scene, [scene_attrs], returning: [:id])

    # Resolve background asset
    bg_id =
      AssetHashResolver.resolve_asset_fk(snapshot["background_asset_id"], snapshot, project_id)

    if bg_id do
      from(s in Storyarn.Scenes.Scene, where: s.id == ^scene_id)
      |> Repo.update_all(set: [background_asset_id: bg_id])
    end

    # Insert layers with their zones, pins, annotations
    layer_data =
      insert_scene_layers(scene_id, snapshot["layers"] || [], snapshot, project_id, now)

    # Insert connections
    insert_scene_connections(scene_id, snapshot["connections"] || [], layer_data, now)

    scene_id
  end

  defp insert_scene_layers(_scene_id, [], _snapshot, _project_id, _now), do: %{}

  defp insert_scene_layers(scene_id, layers_data, snapshot, project_id, now) do
    layers_data
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {layer_data, layer_idx}, acc ->
      layer_attrs = %{
        scene_id: scene_id,
        name: layer_data["name"],
        is_default: layer_data["is_default"] || false,
        position: layer_data["position"] || layer_idx,
        visible: Map.get(layer_data, "visible", true),
        fog_enabled: layer_data["fog_enabled"] || false,
        fog_color: layer_data["fog_color"] || "#000000",
        fog_opacity: layer_data["fog_opacity"] || 0.85,
        inserted_at: now,
        updated_at: now
      }

      {1, [%{id: layer_id}]} = Repo.insert_all(SceneLayer, [layer_attrs], returning: [:id])

      insert_scene_zones(scene_id, layer_id, layer_data["zones"] || [], now)

      pin_ids =
        insert_scene_pins(scene_id, layer_id, layer_data["pins"] || [], snapshot, project_id, now)

      insert_scene_annotations(scene_id, layer_id, layer_data["annotations"] || [], now)

      Map.put(acc, layer_idx, %{layer_id: layer_id, pin_ids: pin_ids})
    end)
  end

  defp insert_scene_zones(_scene_id, _layer_id, [], _now), do: :ok

  defp insert_scene_zones(scene_id, layer_id, zones_data, now) do
    Enum.each(zones_data, fn zone_data ->
      attrs = %{
        scene_id: scene_id,
        layer_id: layer_id,
        name: zone_data["name"],
        vertices: zone_data["vertices"],
        fill_color: zone_data["fill_color"],
        border_color: zone_data["border_color"],
        border_width: zone_data["border_width"] || 2,
        border_style: zone_data["border_style"] || "solid",
        opacity: zone_data["opacity"] || 0.3,
        target_type: zone_data["target_type"],
        target_id: nil,
        tooltip: zone_data["tooltip"],
        position: zone_data["position"] || 0,
        locked: zone_data["locked"] || false,
        action_type: zone_data["action_type"] || "none",
        action_data: zone_data["action_data"] || %{},
        condition: zone_data["condition"],
        condition_effect: zone_data["condition_effect"] || "hide",
        inserted_at: now,
        updated_at: now
      }

      Repo.insert_all(SceneZone, [attrs])
    end)
  end

  defp insert_scene_pins(_scene_id, _layer_id, [], _snapshot, _project_id, _now), do: []

  defp insert_scene_pins(scene_id, layer_id, pins_data, snapshot, project_id, now) do
    Enum.map(pins_data, fn pin_data ->
      attrs = %{
        scene_id: scene_id,
        layer_id: layer_id,
        position_x: pin_data["position_x"],
        position_y: pin_data["position_y"],
        pin_type: pin_data["pin_type"] || "location",
        icon: pin_data["icon"],
        color: pin_data["color"],
        opacity: pin_data["opacity"] || 1.0,
        label: pin_data["label"],
        target_type: pin_data["target_type"],
        target_id: nil,
        tooltip: pin_data["tooltip"],
        size: pin_data["size"] || "md",
        position: pin_data["position"] || 0,
        locked: pin_data["locked"] || false,
        sheet_id: nil,
        icon_asset_id:
          AssetHashResolver.resolve_asset_fk(pin_data["icon_asset_id"], snapshot, project_id),
        action_type: pin_data["action_type"] || "none",
        action_data: pin_data["action_data"] || %{},
        condition: pin_data["condition"],
        condition_effect: pin_data["condition_effect"] || "hide",
        inserted_at: now,
        updated_at: now
      }

      {1, [%{id: pin_id}]} = Repo.insert_all(ScenePin, [attrs], returning: [:id])
      pin_id
    end)
  end

  defp insert_scene_annotations(_scene_id, _layer_id, [], _now), do: :ok

  defp insert_scene_annotations(scene_id, layer_id, annotations_data, now) do
    Enum.each(annotations_data, fn ann_data ->
      attrs = %{
        scene_id: scene_id,
        layer_id: layer_id,
        text: ann_data["text"],
        position_x: ann_data["position_x"],
        position_y: ann_data["position_y"],
        font_size: ann_data["font_size"] || "md",
        color: ann_data["color"],
        position: ann_data["position"] || 0,
        locked: ann_data["locked"] || false,
        inserted_at: now,
        updated_at: now
      }

      Repo.insert_all(SceneAnnotation, [attrs])
    end)
  end

  defp insert_scene_connections(_scene_id, [], _layer_data, _now), do: :ok

  defp insert_scene_connections(scene_id, connections_data, layer_data, now) do
    pin_index_maps =
      Map.new(layer_data, fn {layer_idx, %{pin_ids: pin_ids}} ->
        indexed = pin_ids |> Enum.with_index() |> Map.new(fn {id, idx} -> {idx, id} end)
        {layer_idx, %{map: indexed, count: length(pin_ids)}}
      end)

    entries =
      connections_data
      |> Enum.filter(&valid_scene_connection?(&1, pin_index_maps))
      |> Enum.map(&build_scene_connection_entry(&1, scene_id, pin_index_maps, now))

    if entries != [], do: Repo.insert_all(SceneConnection, entries)
  end

  defp valid_scene_connection?(conn, pin_index_maps) do
    from = Map.get(pin_index_maps, conn["from_layer_index"])
    to = Map.get(pin_index_maps, conn["to_layer_index"])

    from != nil and to != nil and
      conn["from_pin_index"] >= 0 and conn["from_pin_index"] < from.count and
      conn["to_pin_index"] >= 0 and conn["to_pin_index"] < to.count
  end

  defp build_scene_connection_entry(conn, scene_id, pin_index_maps, now) do
    from = Map.fetch!(pin_index_maps, conn["from_layer_index"])
    to = Map.fetch!(pin_index_maps, conn["to_layer_index"])

    %{
      scene_id: scene_id,
      from_pin_id: Map.fetch!(from.map, conn["from_pin_index"]),
      to_pin_id: Map.fetch!(to.map, conn["to_pin_index"]),
      line_style: conn["line_style"] || "solid",
      line_width: conn["line_width"] || 2,
      color: conn["color"],
      label: conn["label"],
      bidirectional: Map.get(conn, "bidirectional", true),
      show_label: Map.get(conn, "show_label", true),
      waypoints: conn["waypoints"] || [],
      inserted_at: now,
      updated_at: now
    }
  end

  # ========== Phase B: Remap Cross-Entity References ==========

  defp remap_flow_refs(id_maps, snapshot_data) do
    Enum.each(snapshot_data["flows"] || [], fn entry ->
      new_flow_id = Map.get(id_maps.flow, entry["id"])
      if new_flow_id, do: remap_single_flow(new_flow_id, entry["snapshot"], id_maps)
    end)
  end

  defp remap_single_flow(new_flow_id, snapshot, id_maps) do
    remap_flow_scene_id(new_flow_id, snapshot["scene_id"], id_maps.scene)

    Enum.each(snapshot["nodes"] || [], fn node_data ->
      new_node_id = remap_id(node_data["original_id"], id_maps.node)
      if new_node_id, do: remap_single_node_data(new_node_id, node_data["data"] || %{}, id_maps)
    end)
  end

  defp remap_flow_scene_id(_new_flow_id, nil, _scene_map), do: :ok

  defp remap_flow_scene_id(new_flow_id, old_scene_id, scene_map) do
    case Map.get(scene_map, old_scene_id) do
      nil ->
        :ok

      new_id ->
        from(f in Storyarn.Flows.Flow, where: f.id == ^new_flow_id)
        |> Repo.update_all(set: [scene_id: new_id])
    end
  end

  defp remap_id(nil, _map), do: nil
  defp remap_id(old_id, map), do: Map.get(map, old_id)

  defp remap_single_node_data(node_id, data, id_maps) do
    updates = %{}

    updates =
      case data["speaker_sheet_id"] do
        nil -> updates
        old_id -> Map.put(updates, "speaker_sheet_id", Map.get(id_maps.sheet, old_id))
      end

    updates =
      case data["referenced_flow_id"] do
        nil -> updates
        old_id -> Map.put(updates, "referenced_flow_id", Map.get(id_maps.flow, old_id))
      end

    if map_size(updates) > 0 do
      new_data = Map.merge(data, updates)

      from(n in FlowNode, where: n.id == ^node_id)
      |> Repo.update_all(set: [data: new_data])
    end
  end

  defp remap_scene_refs(id_maps, snapshot_data) do
    scene_entries = snapshot_data["scenes"] || []

    Enum.each(scene_entries, fn entry ->
      new_scene_id = Map.get(id_maps.scene, entry["id"])
      snapshot = entry["snapshot"]

      if new_scene_id do
        remap_scene_layers_refs(new_scene_id, snapshot["layers"] || [], id_maps)
      end
    end)
  end

  defp remap_scene_layers_refs(new_scene_id, layers_data, id_maps) do
    pins_by_layer =
      from(p in ScenePin,
        where: p.scene_id == ^new_scene_id,
        order_by: [asc: p.layer_id, asc: p.position, asc: p.id]
      )
      |> Repo.all()
      |> Enum.group_by(& &1.layer_id)

    zones_by_layer =
      from(z in SceneZone,
        where: z.scene_id == ^new_scene_id,
        order_by: [asc: z.layer_id, asc: z.position, asc: z.id]
      )
      |> Repo.all()
      |> Enum.group_by(& &1.layer_id)

    layers =
      from(l in SceneLayer,
        where: l.scene_id == ^new_scene_id,
        order_by: [asc: l.position, asc: l.id]
      )
      |> Repo.all()

    Enum.zip(layers, layers_data)
    |> Enum.each(fn {layer, layer_data} ->
      remap_pins_refs(Map.get(pins_by_layer, layer.id, []), layer_data["pins"] || [], id_maps)
      remap_zones_refs(Map.get(zones_by_layer, layer.id, []), layer_data["zones"] || [], id_maps)
    end)
  end

  defp remap_pins_refs(pins, pins_data, id_maps) do
    Enum.zip(pins, pins_data)
    |> Enum.each(fn {pin, pin_data} ->
      updates = []

      updates =
        case pin_data["sheet_id"] do
          nil -> updates
          old_id -> [{:sheet_id, Map.get(id_maps.sheet, old_id)} | updates]
        end

      updates =
        case {pin_data["target_type"], pin_data["target_id"]} do
          {_, nil} -> updates
          {type, old_id} -> [{:target_id, remap_target_id(type, old_id, id_maps)} | updates]
        end

      if updates != [] do
        from(p in ScenePin, where: p.id == ^pin.id)
        |> Repo.update_all(set: updates)
      end
    end)
  end

  defp remap_zones_refs(zones, zones_data, id_maps) do
    Enum.zip(zones, zones_data)
    |> Enum.each(fn {zone, zone_data} ->
      remap_zone_target(zone, zone_data, id_maps)
    end)
  end

  defp remap_zone_target(_zone, %{"target_id" => nil}, _id_maps), do: :ok
  defp remap_zone_target(_zone, %{"target_id" => ""}, _id_maps), do: :ok

  defp remap_zone_target(zone, zone_data, id_maps) do
    case remap_target_id(zone_data["target_type"], zone_data["target_id"], id_maps) do
      nil ->
        :ok

      new_id ->
        from(z in SceneZone, where: z.id == ^zone.id) |> Repo.update_all(set: [target_id: new_id])
    end
  end

  defp remap_target_id("sheet", old_id, id_maps), do: Map.get(id_maps.sheet, old_id)
  defp remap_target_id("flow", old_id, id_maps), do: Map.get(id_maps.flow, old_id)
  defp remap_target_id("scene", old_id, id_maps), do: Map.get(id_maps.scene, old_id)
  defp remap_target_id(_type, _old_id, _id_maps), do: nil

  defp remap_block_inheritance(block_id_map) do
    # Update inherited_from_block_id using the block_id_map
    Enum.each(block_id_map, fn {old_block_id, new_block_id} ->
      # Find blocks that reference this old block and remap
      from(b in Block,
        where: b.inherited_from_block_id == ^old_block_id and b.id in ^Map.values(block_id_map)
      )
      |> Repo.update_all(set: [inherited_from_block_id: new_block_id])
    end)
  end

  # ========== Phase C: Tree Hierarchy ==========

  defp restore_tree_hierarchy(snapshot_data, id_maps) do
    case snapshot_data["tree"] do
      nil ->
        :ok

      tree ->
        remap_tree(tree["sheets"] || [], id_maps.sheet, Storyarn.Sheets.Sheet)
        remap_tree(tree["flows"] || [], id_maps.flow, Storyarn.Flows.Flow)
        remap_tree(tree["scenes"] || [], id_maps.scene, Storyarn.Scenes.Scene)
    end
  end

  defp remap_tree(tree_entries, id_map, schema) do
    Enum.each(tree_entries, fn entry ->
      new_id = Map.get(id_map, entry["id"])
      if new_id, do: apply_tree_position(schema, new_id, entry, id_map)
    end)
  end

  defp apply_tree_position(schema, new_id, entry, id_map) do
    new_parent_id = if entry["parent_id"], do: Map.get(id_map, entry["parent_id"])

    updates =
      if new_parent_id,
        do: [position: entry["position"] || 0, parent_id: new_parent_id],
        else: [position: entry["position"] || 0]

    from(e in schema, where: e.id == ^new_id)
    |> Repo.update_all(set: updates)
  end

  # ========== Phase D: Localization ==========

  defp recover_localization(project_id, snapshot_data, id_maps, now) do
    case snapshot_data["localization"] do
      nil ->
        :ok

      localization ->
        restore_languages(project_id, Map.get(localization, "languages", []), now)
        restore_texts(project_id, Map.get(localization, "texts", []), id_maps, now)
        restore_glossary(project_id, Map.get(localization, "glossary", []), now)
    end
  end

  defp restore_languages(_project_id, [], _now), do: :ok

  defp restore_languages(project_id, languages, now) do
    entries =
      Enum.map(languages, fn lang ->
        %{
          project_id: project_id,
          locale_code: lang["locale_code"],
          name: lang["name"],
          is_source: lang["is_source"] || false,
          position: lang["position"] || 0,
          inserted_at: now,
          updated_at: now
        }
      end)

    Repo.insert_all(ProjectLanguage, entries)
  end

  defp restore_texts(_project_id, [], _id_maps, _now), do: :ok

  defp restore_texts(project_id, texts, id_maps, now) do
    texts
    |> Enum.map(fn text ->
      source_id = remap_source_id(text["source_type"], text["source_id"], id_maps)

      speaker_id =
        if text["speaker_sheet_id"], do: Map.get(id_maps.sheet, text["speaker_sheet_id"])

      %{
        project_id: project_id,
        source_type: text["source_type"],
        source_id: source_id,
        source_field: text["source_field"],
        source_text: text["source_text"],
        source_text_hash: text["source_text_hash"],
        locale_code: text["locale_code"],
        translated_text: text["translated_text"],
        status: text["status"] || "pending",
        vo_status: text["vo_status"] || "none",
        vo_asset_id: text["vo_asset_id"],
        translator_notes: text["translator_notes"],
        reviewer_notes: text["reviewer_notes"],
        speaker_sheet_id: speaker_id,
        word_count: text["word_count"],
        machine_translated: text["machine_translated"] || false,
        last_translated_at: text["last_translated_at"],
        last_reviewed_at: text["last_reviewed_at"],
        translated_by_id: text["translated_by_id"],
        reviewed_by_id: text["reviewed_by_id"],
        inserted_at: now,
        updated_at: now
      }
    end)
    |> Enum.chunk_every(500)
    |> Enum.each(fn chunk -> Repo.insert_all(LocalizedText, chunk) end)
  end

  defp remap_source_id("flow_node", old_id, id_maps), do: Map.get(id_maps.node, old_id, old_id)
  defp remap_source_id("sheet", old_id, id_maps), do: Map.get(id_maps.sheet, old_id, old_id)
  defp remap_source_id("flow", old_id, id_maps), do: Map.get(id_maps.flow, old_id, old_id)
  defp remap_source_id("scene", old_id, id_maps), do: Map.get(id_maps.scene, old_id, old_id)
  defp remap_source_id(_type, old_id, _id_maps), do: old_id

  defp restore_glossary(_project_id, [], _now), do: :ok

  defp restore_glossary(project_id, glossary, now) do
    glossary
    |> Enum.map(fn entry ->
      %{
        project_id: project_id,
        source_term: entry["source_term"],
        source_locale: entry["source_locale"],
        target_term: entry["target_term"],
        target_locale: entry["target_locale"],
        context: entry["context"],
        do_not_translate: entry["do_not_translate"] || false,
        inserted_at: now,
        updated_at: now
      }
    end)
    |> Enum.chunk_every(500)
    |> Enum.each(fn chunk -> Repo.insert_all(GlossaryEntry, chunk) end)
  end
end
