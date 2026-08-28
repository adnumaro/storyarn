defmodule StoryarnWeb.SceneLive.VersionSnapshotSerializer do
  @moduledoc """
  Converts an immutable Scene snapshot into the read-only shape consumed by
  the Scene comparison surface.

  This mapping belongs to the presentation adapter: the Scene context owns the
  snapshot contract, while StoryarnWeb owns the Vue-facing representation.
  """

  alias StoryarnWeb.PrivateMedia

  @zone_view_defaults %{
    "hidden" => false,
    "border_width" => 2,
    "border_style" => "solid",
    "opacity" => 0.3,
    "position" => 0,
    "locked" => false,
    "action_type" => "action",
    "action_data" => %{"assignments" => []},
    "label_mode" => "text",
    "label_font_size" => 12,
    "label_font_family" => "system",
    "label_font_weight" => "600",
    "label_font_style" => "normal",
    "condition_effect" => "hide",
    "is_walkable" => false
  }

  @spec serialize(map(), pos_integer()) :: map()
  def serialize(snapshot, project_id) when is_map(snapshot) and is_integer(project_id) and project_id > 0 do
    asset_metadata = snapshot["asset_metadata"] || %{}

    {serialized_layers, pin_id_map, counter} =
      serialize_layers(snapshot["layers"] || [], asset_metadata, project_id)

    {orphan_pins, pin_id_map, counter} =
      serialize_orphan_pins(
        snapshot["orphan_pins"] || [],
        pin_id_map,
        counter,
        asset_metadata,
        project_id
      )

    {orphan_zones, counter} =
      serialize_orphan_zones(snapshot["orphan_zones"] || [], counter, asset_metadata, project_id)

    {orphan_annotations, _counter} =
      serialize_orphan_annotations(snapshot["orphan_annotations"] || [], counter)

    serialized_connections =
      snapshot
      |> Map.get("connections", [])
      |> Enum.with_index()
      |> Enum.map(&serialize_connection(&1, pin_id_map))
      |> Enum.filter(&route_has_two_points?/1)

    build_result(
      snapshot,
      asset_metadata,
      project_id,
      serialized_layers,
      orphan_pins,
      orphan_zones,
      orphan_annotations,
      serialized_connections
    )
  end

  defp serialize_layers(layers, asset_metadata, project_id) do
    {results, {pin_map, counter}} =
      layers
      |> Enum.with_index()
      |> Enum.map_reduce({%{}, 1}, fn {layer, layer_index}, {pin_map, counter} ->
        serialize_layer(layer, layer_index, pin_map, counter, asset_metadata, project_id)
      end)

    {results, pin_map, counter}
  end

  defp serialize_orphan_pins(pins, pin_map, counter, asset_metadata, project_id) do
    {serialized, {pin_map, counter}} =
      pins
      |> Enum.with_index()
      |> Enum.map_reduce({pin_map, counter}, fn {pin, pin_index}, {acc, current} ->
        pin_id = -current

        {serialize_pin(pin, pin_id, nil, asset_metadata, project_id),
         {Map.put(acc, {-1, pin_index}, pin_id), current + 1}}
      end)

    {serialized, pin_map, counter}
  end

  defp serialize_orphan_zones(zones, counter, asset_metadata, project_id) do
    Enum.map_reduce(zones, counter, fn zone, current ->
      {serialize_zone(zone, -current, nil, asset_metadata, project_id), current + 1}
    end)
  end

  defp serialize_orphan_annotations(annotations, counter) do
    Enum.map_reduce(annotations, counter, fn annotation, current ->
      {serialize_annotation(annotation, -current, nil), current + 1}
    end)
  end

  defp serialize_layer(layer, layer_index, pin_map, counter, asset_metadata, project_id) do
    layer_id = -(layer_index + 1)

    {serialized_pins, {pin_map, counter}} =
      layer
      |> Map.get("pins", [])
      |> Enum.with_index()
      |> Enum.map_reduce({pin_map, counter}, fn {pin, pin_index}, {acc, current} ->
        pin_id = -current

        {serialize_pin(pin, pin_id, layer_id, asset_metadata, project_id),
         {Map.put(acc, {layer_index, pin_index}, pin_id), current + 1}}
      end)

    {serialized_zones, counter} =
      layer
      |> Map.get("zones", [])
      |> Enum.map_reduce(counter, fn zone, current ->
        {serialize_zone(zone, -current, layer_id, asset_metadata, project_id), current + 1}
      end)

    {serialized_annotations, counter} =
      layer
      |> Map.get("annotations", [])
      |> Enum.map_reduce(counter, fn annotation, current ->
        {serialize_annotation(annotation, -current, layer_id), current + 1}
      end)

    serialized_layer = %{
      id: layer_id,
      name: layer["name"],
      visible: Map.get(layer, "visible", true),
      is_default: layer["is_default"] || false,
      position: layer["position"] || layer_index,
      fog_enabled: layer["fog_enabled"] || false
    }

    {{serialized_layer, serialized_pins, serialized_zones, serialized_annotations}, {pin_map, counter}}
  end

  defp serialize_pin(pin, pin_id, layer_id, asset_metadata, project_id) do
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
      shortcut: pin["shortcut"],
      hidden: pin["hidden"] || false,
      flow_id: pin["flow_id"],
      sheet_id: pin["sheet_id"],
      avatar_url: nil,
      icon_asset_id: pin["icon_asset_id"],
      icon_asset_url: resolve_asset_url(pin["icon_asset_id"], asset_metadata, project_id),
      position: pin["position"] || 0,
      locked: pin["locked"] || false,
      condition: pin["condition"],
      condition_effect: pin["condition_effect"] || "hide"
    }
  end

  defp serialize_zone(zone, zone_id, layer_id, asset_metadata, project_id) do
    zone = Map.merge(@zone_view_defaults, zone)

    %{
      id: zone_id,
      name: zone["name"],
      shortcut: zone["shortcut"],
      hidden: zone["hidden"],
      vertices: zone["vertices"],
      fill_color: zone["fill_color"],
      border_color: zone["border_color"],
      border_width: zone["border_width"],
      border_style: zone["border_style"],
      opacity: zone["opacity"],
      tooltip: zone["tooltip"],
      layer_id: layer_id,
      target_type: zone["target_type"],
      target_id: zone["target_id"],
      position: zone["position"],
      locked: zone["locked"],
      action_type: zone["action_type"],
      action_data: zone["action_data"],
      label_mode: zone["label_mode"],
      label_font_size: zone["label_font_size"],
      label_font_family: zone["label_font_family"],
      label_font_weight: zone["label_font_weight"],
      label_font_style: zone["label_font_style"],
      label_icon_asset_id: zone["label_icon_asset_id"],
      label_icon_asset_url: resolve_asset_url(zone["label_icon_asset_id"], asset_metadata, project_id),
      condition: zone["condition"],
      condition_effect: zone["condition_effect"],
      is_walkable: zone["is_walkable"]
    }
  end

  defp serialize_annotation(annotation, annotation_id, layer_id) do
    %{
      id: annotation_id,
      text: annotation["text"],
      position_x: annotation["position_x"],
      position_y: annotation["position_y"],
      font_size: annotation["font_size"] || "md",
      color: annotation["color"],
      layer_id: layer_id,
      position: annotation["position"] || 0,
      locked: annotation["locked"] || false
    }
  end

  defp serialize_connection({connection, index}, pin_id_map) do
    %{
      id: -(index + 1),
      from_pin_id: Map.get(pin_id_map, {connection["from_layer_index"], connection["from_pin_index"]}),
      to_pin_id: Map.get(pin_id_map, {connection["to_layer_index"], connection["to_pin_index"]}),
      line_style: connection["line_style"] || "solid",
      line_width: connection["line_width"] || 2,
      color: connection["color"],
      label: connection["label"],
      show_label: Map.get(connection, "show_label", true),
      bidirectional: Map.get(connection, "bidirectional", true),
      waypoints: connection["waypoints"] || [],
      from_stop: Map.get(connection, "from_stop", true),
      to_stop: Map.get(connection, "to_stop", true),
      from_pause_ms: connection["from_pause_ms"],
      to_pause_ms: connection["to_pause_ms"]
    }
  end

  defp route_has_two_points?(connection) do
    endpoint_count = Enum.count([connection.from_pin_id, connection.to_pin_id], &present?/1)
    endpoint_count + length(connection.waypoints) >= 2
  end

  defp present?(nil), do: false
  defp present?(""), do: false
  defp present?(_value), do: true

  defp build_result(
         snapshot,
         asset_metadata,
         project_id,
         serialized_layers,
         orphan_pins,
         orphan_zones,
         orphan_annotations,
         serialized_connections
       ) do
    %{
      id: -1,
      name: snapshot["name"],
      width: snapshot["width"] || 1920,
      height: snapshot["height"] || 1080,
      default_zoom: snapshot["default_zoom"],
      default_center_x: snapshot["default_center_x"],
      default_center_y: snapshot["default_center_y"],
      background_url: resolve_asset_url(snapshot["background_asset_id"], asset_metadata, project_id),
      scale_unit: snapshot["scale_unit"],
      scale_value: snapshot["scale_value"],
      fog_color: snapshot["fog_color"] || "#000000",
      fog_opacity: snapshot["fog_opacity"] || 0.85,
      exploration_display_mode: snapshot["exploration_display_mode"],
      can_edit: false,
      boundary_vertices: nil,
      layers: Enum.map(serialized_layers, &elem(&1, 0)),
      pins: Enum.flat_map(serialized_layers, &elem(&1, 1)) ++ orphan_pins,
      zones: Enum.flat_map(serialized_layers, &elem(&1, 2)) ++ orphan_zones,
      connections: serialized_connections,
      annotations: Enum.flat_map(serialized_layers, &elem(&1, 3)) ++ orphan_annotations
    }
  end

  defp resolve_asset_url(nil, _metadata, _project_id), do: nil

  defp resolve_asset_url(asset_id, metadata, project_id) do
    case Map.get(metadata, to_string(asset_id)) do
      %{} = asset_metadata ->
        PrivateMedia.project_snapshot_asset_url(project_id, asset_metadata) ||
          PrivateMedia.project_url_from_stored(project_id, asset_metadata["url"])

      _missing ->
        nil
    end
  end
end
