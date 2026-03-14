defmodule Storyarn.Versioning.SnapshotViewer do
  @moduledoc """
  Converts raw snapshot maps into editor-compatible data shapes for the
  split-view comparison viewer. Operates entirely on snapshot data without
  any database queries.
  """

  @doc """
  Serializes a flow snapshot into the shape expected by the FlowCanvas JS hook.
  Uses negative IDs to avoid collisions with live data.
  """
  @spec serialize_flow(map()) :: map()
  def serialize_flow(snapshot) do
    nodes = snapshot["nodes"] || []

    id_map =
      nodes
      |> Enum.with_index()
      |> Map.new(fn {_node, idx} -> {idx, -(idx + 1)} end)

    serialized_nodes = Enum.map(Enum.with_index(nodes), &serialize_flow_node(&1, id_map))

    serialized_connections =
      snapshot
      |> Map.get("connections", [])
      |> Enum.with_index()
      |> Enum.map(&serialize_flow_connection(&1, id_map))
      |> Enum.filter(fn conn -> conn.source_node_id != nil and conn.target_node_id != nil end)

    %{
      id: -1,
      name: snapshot["name"],
      nodes: serialized_nodes,
      connections: serialized_connections
    }
  end

  @doc """
  Serializes a scene snapshot into the shape expected by the SceneCanvas JS hook.
  Sets `can_edit: false` for readonly mode.
  """
  @spec serialize_scene(map()) :: map()
  def serialize_scene(snapshot) do
    asset_metadata = snapshot["asset_metadata"] || %{}

    {serialized_layers, pin_id_map} =
      serialize_scene_layers(snapshot["layers"] || [], asset_metadata)

    serialized_connections =
      snapshot
      |> Map.get("connections", [])
      |> Enum.with_index()
      |> Enum.map(&serialize_scene_connection(&1, pin_id_map))
      |> Enum.filter(fn conn -> conn.from_pin_id != nil and conn.to_pin_id != nil end)

    build_scene_result(snapshot, asset_metadata, serialized_layers, serialized_connections)
  end

  @doc """
  Serializes a sheet snapshot into a list of block maps compatible with
  `BlockComponents.block_component/1` with `can_edit: false`.
  """
  @spec serialize_sheet(map()) :: list(map())
  def serialize_sheet(snapshot) do
    snapshot
    |> Map.get("blocks", [])
    |> Enum.with_index()
    |> Enum.map(&serialize_block/1)
  end

  # ========== Flow Helpers ==========

  defp serialize_flow_node({node, idx}, id_map) do
    data =
      (node["data"] || %{})
      |> maybe_add_hub_color()

    %{
      id: Map.fetch!(id_map, idx),
      type: node["type"],
      position: %{x: node["position_x"] || 0, y: node["position_y"] || 0},
      data: data
    }
  end

  defp serialize_flow_connection({conn, idx}, id_map) do
    %{
      id: -(idx + 1),
      source_node_id: Map.get(id_map, conn["source_node_index"]),
      target_node_id: Map.get(id_map, conn["target_node_index"]),
      source_pin: conn["source_pin"],
      target_pin: conn["target_pin"],
      label: conn["label"]
    }
  end

  defp maybe_add_hub_color(%{"color" => color} = data) when is_binary(color) do
    hex = Storyarn.Flows.HubColors.to_hex(color, Storyarn.Flows.HubColors.default_hex())
    Map.put(data, "color_hex", hex)
  end

  defp maybe_add_hub_color(data), do: data

  # ========== Scene Helpers ==========

  defp serialize_scene_layers(layers, asset_metadata) do
    # Use a global counter to generate unique negative IDs, avoiding
    # collisions regardless of entity counts per layer.
    {results, {pin_map, _counter}} =
      layers
      |> Enum.with_index()
      |> Enum.map_reduce({%{}, 1}, fn {layer, layer_idx}, {pin_map, counter} ->
        serialize_single_layer(layer, layer_idx, pin_map, counter, asset_metadata)
      end)

    {results, pin_map}
  end

  defp serialize_single_layer(layer, layer_idx, pin_map, counter, asset_metadata) do
    layer_id = -(layer_idx + 1)

    pins = Map.get(layer, "pins", [])
    zones = Map.get(layer, "zones", [])
    annotations = Map.get(layer, "annotations", [])

    {serialized_pins, {updated_pin_map, counter}} =
      pins
      |> Enum.with_index()
      |> Enum.map_reduce({pin_map, counter}, fn {pin, pin_idx}, {acc, c} ->
        pin_id = -c
        serialized = serialize_pin(pin, pin_id, layer_id, asset_metadata)
        {serialized, {Map.put(acc, {layer_idx, pin_idx}, pin_id), c + 1}}
      end)

    {serialized_zones, counter} =
      zones
      |> Enum.with_index()
      |> Enum.map_reduce(counter, fn {zone, _zone_idx}, c ->
        {serialize_zone(zone, -c, layer_id), c + 1}
      end)

    {serialized_annotations, counter} =
      annotations
      |> Enum.with_index()
      |> Enum.map_reduce(counter, fn {ann, _ann_idx}, c ->
        {serialize_annotation(ann, -c, layer_id), c + 1}
      end)

    serialized_layer = %{
      id: layer_id,
      name: layer["name"],
      visible: Map.get(layer, "visible", true),
      is_default: layer["is_default"] || false,
      position: layer["position"] || layer_idx,
      fog_enabled: layer["fog_enabled"] || false,
      fog_color: layer["fog_color"] || "#000000",
      fog_opacity: layer["fog_opacity"] || 0.85
    }

    {{serialized_layer, serialized_pins, serialized_zones, serialized_annotations},
     {updated_pin_map, counter}}
  end

  defp serialize_pin(pin, pin_id, layer_id, asset_metadata) do
    %{
      id: pin_id,
      position_x: pin["position_x"],
      position_y: pin["position_y"],
      pin_type: pin["pin_type"] || "location",
      icon: pin["icon"],
      color: pin["color"],
      opacity: pin["opacity"] || 1.0,
      label: pin["label"],
      tooltip: pin["tooltip"],
      size: pin["size"] || "md",
      layer_id: layer_id,
      target_type: pin["target_type"],
      target_id: pin["target_id"],
      sheet_id: pin["sheet_id"],
      avatar_url: nil,
      icon_asset_id: pin["icon_asset_id"],
      icon_asset_url: resolve_asset_url(pin["icon_asset_id"], asset_metadata),
      position: pin["position"] || 0,
      locked: pin["locked"] || false,
      action_type: pin["action_type"] || "none",
      action_data: pin["action_data"] || %{},
      condition: pin["condition"],
      condition_effect: pin["condition_effect"] || "hide"
    }
  end

  defp serialize_zone(zone, zone_id, layer_id) do
    %{
      id: zone_id,
      name: zone["name"],
      vertices: zone["vertices"],
      fill_color: zone["fill_color"],
      border_color: zone["border_color"],
      border_width: zone["border_width"] || 2,
      border_style: zone["border_style"] || "solid",
      opacity: zone["opacity"] || 0.3,
      tooltip: zone["tooltip"],
      layer_id: layer_id,
      target_type: zone["target_type"],
      target_id: zone["target_id"],
      position: zone["position"] || 0,
      locked: zone["locked"] || false,
      action_type: zone["action_type"] || "none",
      action_data: zone["action_data"] || %{},
      condition: zone["condition"],
      condition_effect: zone["condition_effect"] || "hide"
    }
  end

  defp serialize_annotation(ann, ann_id, layer_id) do
    %{
      id: ann_id,
      text: ann["text"],
      position_x: ann["position_x"],
      position_y: ann["position_y"],
      font_size: ann["font_size"] || "md",
      color: ann["color"],
      layer_id: layer_id,
      position: ann["position"] || 0,
      locked: ann["locked"] || false
    }
  end

  defp serialize_scene_connection({conn, idx}, pin_id_map) do
    %{
      id: -(idx + 1),
      from_pin_id: Map.get(pin_id_map, {conn["from_layer_index"], conn["from_pin_index"]}),
      to_pin_id: Map.get(pin_id_map, {conn["to_layer_index"], conn["to_pin_index"]}),
      line_style: conn["line_style"] || "solid",
      line_width: conn["line_width"] || 2,
      color: conn["color"],
      label: conn["label"],
      show_label: Map.get(conn, "show_label", true),
      bidirectional: Map.get(conn, "bidirectional", true),
      waypoints: conn["waypoints"] || []
    }
  end

  defp build_scene_result(snapshot, asset_metadata, serialized_layers, serialized_connections) do
    %{
      id: -1,
      name: snapshot["name"],
      width: snapshot["width"] || 1920,
      height: snapshot["height"] || 1080,
      default_zoom: snapshot["default_zoom"],
      default_center_x: snapshot["default_center_x"],
      default_center_y: snapshot["default_center_y"],
      background_url: resolve_asset_url(snapshot["background_asset_id"], asset_metadata),
      scale_unit: snapshot["scale_unit"],
      scale_value: snapshot["scale_value"],
      can_edit: false,
      boundary_vertices: nil,
      layers: Enum.map(serialized_layers, &elem(&1, 0)),
      pins: Enum.flat_map(serialized_layers, &elem(&1, 1)),
      zones: Enum.flat_map(serialized_layers, &elem(&1, 2)),
      connections: serialized_connections,
      annotations: Enum.flat_map(serialized_layers, &elem(&1, 3))
    }
  end

  # ========== Sheet Helpers ==========

  defp serialize_block({block, idx}) do
    block_id = -(idx + 1)
    table_data = serialize_table_data(block["table_data"])

    %{
      id: block_id,
      type: block["type"],
      position: block["position"] || idx,
      config: block["config"] || %{},
      value: block["value"] || %{},
      is_constant: block["is_constant"] || false,
      variable_name: block["variable_name"],
      scope: block["scope"] || "self",
      required: block["required"] || false,
      table_columns: table_data[:columns] || [],
      table_rows: table_data[:rows] || [],
      # Fields required by BlockComponents but not present in snapshots
      inherited_from_block_id: nil,
      detached: nil,
      reference_target: nil
    }
  end

  defp serialize_table_data(nil), do: %{columns: [], rows: []}

  defp serialize_table_data(table_data) do
    columns =
      table_data
      |> Map.get("columns", [])
      |> Enum.with_index()
      |> Enum.map(&serialize_table_column/1)

    rows =
      table_data
      |> Map.get("rows", [])
      |> Enum.with_index()
      |> Enum.map(&serialize_table_row/1)

    %{columns: columns, rows: rows}
  end

  defp serialize_table_column({col, idx}) do
    %{
      id: -(idx + 1),
      name: col["name"],
      slug: col["slug"],
      type: col["type"],
      is_constant: col["is_constant"] || false,
      required: col["required"] || false,
      position: col["position"] || idx,
      config: col["config"] || %{}
    }
  end

  defp serialize_table_row({row, idx}) do
    %{
      id: -(idx + 1),
      name: row["name"],
      slug: row["slug"],
      position: row["position"] || idx,
      cells: row["cells"] || %{}
    }
  end

  # ========== Shared Helpers ==========

  defp resolve_asset_url(nil, _metadata), do: nil

  defp resolve_asset_url(asset_id, metadata) do
    case Map.get(metadata, to_string(asset_id)) do
      %{"url" => url} when is_binary(url) -> url
      _ -> nil
    end
  end
end
