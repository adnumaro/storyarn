defmodule StoryarnWeb.SceneLive.Helpers.PropsSerializer do
  @moduledoc """
  Pure functions to serialize Elixir data structures into Vue component-ready props.
  Converts snake_case Ecto structs to camelCase plain maps.
  """

  alias Storyarn.Assets

  # ---- Scene ----

  def prepare_scene_for_vue(nil), do: nil

  def prepare_scene_for_vue(scene) do
    %{
      id: scene.id,
      name: scene.name,
      shortcut: scene.shortcut,
      description: scene.description,
      width: scene.width,
      height: scene.height,
      defaultZoom: scene.default_zoom,
      defaultCenterX: scene.default_center_x,
      defaultCenterY: scene.default_center_y,
      scaleUnit: scene.scale_unit,
      scaleValue: scene.scale_value,
      explorationDisplayMode: scene.exploration_display_mode,
      backgroundUrl: background_url(scene)
    }
  end

  # ---- Layers ----

  def prepare_layers_for_vue(layers) do
    Enum.map(layers, &serialize_layer/1)
  end

  defp serialize_layer(layer) do
    %{
      id: layer.id,
      name: layer.name,
      visible: layer.visible,
      isDefault: layer.is_default,
      position: layer.position,
      fogEnabled: layer.fog_enabled,
      fogColor: layer.fog_color,
      fogOpacity: layer.fog_opacity
    }
  end

  # ---- Pins ----

  def prepare_pins_for_vue(pins) do
    Enum.map(pins, &serialize_pin/1)
  end

  defp serialize_pin(pin) do
    %{
      id: pin.id,
      positionX: pin.position_x,
      positionY: pin.position_y,
      pinType: pin.pin_type,
      icon: pin.icon,
      color: pin.color,
      opacity: pin.opacity,
      label: pin.label,
      shortcut: pin.shortcut,
      hidden: pin.hidden,
      tooltip: pin.tooltip,
      size: pin.size,
      position: pin.position,
      locked: pin.locked,
      condition: pin.condition,
      conditionEffect: pin.condition_effect,
      isPlayable: pin.is_playable,
      isLeader: pin.is_leader,
      patrolMode: pin.patrol_mode,
      patrolSpeed: pin.patrol_speed,
      patrolPauseMs: pin.patrol_pause_ms,
      layerId: pin.layer_id,
      sheetId: pin.sheet_id,
      flowId: pin.flow_id,
      iconAssetId: pin.icon_asset_id,
      sheetAvatarUrl: pin_avatar_url(pin),
      iconAssetUrl: pin_icon_asset_url(pin)
    }
  end

  # ---- Zones ----

  def prepare_zones_for_vue(zones) do
    Enum.map(zones, &serialize_zone/1)
  end

  defp serialize_zone(zone) do
    %{
      id: zone.id,
      name: zone.name,
      shortcut: zone.shortcut,
      vertices: zone.vertices,
      fillColor: zone.fill_color,
      borderColor: zone.border_color,
      borderWidth: zone.border_width,
      borderStyle: zone.border_style,
      opacity: zone.opacity,
      targetType: zone.target_type,
      targetId: zone.target_id,
      tooltip: zone.tooltip,
      position: zone.position,
      locked: zone.locked,
      actionType: zone.action_type,
      actionData: zone.action_data,
      condition: zone.condition,
      conditionEffect: zone.condition_effect,
      isWalkable: zone.is_walkable,
      hidden: zone.hidden,
      layerId: zone.layer_id
    }
  end

  # ---- Connections ----

  def prepare_connections_for_vue(connections) do
    Enum.map(connections, &serialize_connection/1)
  end

  defp serialize_connection(conn) do
    %{
      id: conn.id,
      lineStyle: conn.line_style,
      lineWidth: conn.line_width,
      color: conn.color,
      label: conn.label,
      bidirectional: conn.bidirectional,
      showLabel: conn.show_label,
      waypoints: conn.waypoints,
      fromPinId: conn.from_pin_id,
      toPinId: conn.to_pin_id
    }
  end

  # ---- Annotations ----

  def prepare_annotations_for_vue(annotations) do
    Enum.map(annotations, &serialize_annotation/1)
  end

  defp serialize_annotation(ann) do
    %{
      id: ann.id,
      text: ann.text,
      positionX: ann.position_x,
      positionY: ann.position_y,
      fontSize: ann.font_size,
      color: ann.color,
      position: ann.position,
      locked: ann.locked,
      layerId: ann.layer_id
    }
  end

  # ---- Selected element (for toolbar/panel) ----

  def serialize_selected_element("pin", pin), do: serialize_pin(pin)
  def serialize_selected_element("zone", zone), do: serialize_zone(zone)
  def serialize_selected_element("connection", conn), do: serialize_connection(conn)
  def serialize_selected_element("annotation", ann), do: serialize_annotation(ann)
  def serialize_selected_element(_, _), do: nil

  # ---- Scene Tree ----

  def prepare_scenes_tree(nodes) do
    Enum.map(nodes, fn node ->
      %{
        id: node.id,
        name: node.name,
        children: prepare_scenes_tree(Map.get(node, :children, []))
      }
    end)
  end

  # ---- Legend groups (server-side aggregation) ----

  @pin_type_labels %{
    "location" => "Location",
    "character" => "Character",
    "event" => "Event",
    "custom" => "Custom"
  }

  @pin_type_icons %{
    "location" => "map-pin",
    "character" => "user",
    "event" => "zap",
    "custom" => "star"
  }

  @line_style_labels %{
    "solid" => "Solid",
    "dashed" => "Dashed",
    "dotted" => "Dotted"
  }

  def prepare_legend_groups(pins, zones, connections) do
    pin_groups = group_pins(pins)
    zone_groups = group_zones(zones)
    connection_groups = group_connections(connections)

    %{
      pinGroups: pin_groups,
      zoneGroups: zone_groups,
      connectionGroups: connection_groups,
      hasEntries: pin_groups != [] or zone_groups != [] or connection_groups != []
    }
  end

  defp group_pins(pins) do
    pins
    |> Enum.group_by(fn pin -> {pin.pin_type, pin.color} end)
    |> Enum.map(fn {{pin_type, color}, items} ->
      %{
        icon: Map.get(@pin_type_icons, pin_type, "map-pin"),
        label: Map.get(@pin_type_labels, pin_type, pin_type),
        color: color,
        count: length(items)
      }
    end)
    |> Enum.sort_by(& &1.label)
  end

  defp group_zones(zones) do
    zones
    |> Enum.group_by(fn zone -> zone.fill_color || "#3b82f6" end)
    |> Enum.map(fn {color, items} ->
      avg_opacity =
        Enum.reduce(items, 0, fn z, acc -> acc + (z.opacity || 0.3) end) / max(length(items), 1)

      hex = round(avg_opacity * 255) |> Integer.to_string(16) |> String.pad_leading(2, "0")

      %{
        color: color,
        opacityHex: hex,
        label: color,
        count: length(items)
      }
    end)
    |> Enum.sort_by(& &1.color)
  end

  defp group_connections(connections) do
    connections
    |> Enum.group_by(fn conn -> {conn.line_style, conn.color || "#6b7280"} end)
    |> Enum.map(fn {{line_style, color}, items} ->
      %{
        lineStyle: line_style,
        color: color,
        label: Map.get(@line_style_labels, line_style, line_style),
        dashArray: line_dash(line_style),
        count: length(items)
      }
    end)
    |> Enum.sort_by(& &1.label)
  end

  defp line_dash("dashed"), do: "4,3"
  defp line_dash("dotted"), do: "2,3"
  defp line_dash(_), do: "none"

  # ---- Entity Locks ----

  def serialize_entity_locks(locks) when is_map(locks) do
    Map.new(locks, fn {entity_id, lock} ->
      {to_string(entity_id),
       %{
         userId: lock.user_id,
         userEmail: lock.user_email,
         userColor: lock.user_color
       }}
    end)
  end

  def serialize_entity_locks(_), do: %{}

  # ---- Ambient Flows ----

  def prepare_ambient_flows_for_vue(flows) do
    Enum.map(flows, fn af ->
      %{
        id: af.id,
        flowId: af.flow_id,
        flowName: af.flow.name,
        triggerType: af.trigger_type,
        triggerConfig: af.trigger_config,
        priority: af.priority,
        enabled: af.enabled,
        position: af.position
      }
    end)
  end

  def prepare_project_flows_for_vue(flows) do
    Enum.map(flows, fn f -> %{id: f.id, name: f.name} end)
  end

  def prepare_project_scenes_for_vue(scenes) do
    Enum.map(scenes, fn s -> %{id: s.id, name: s.name} end)
  end

  def prepare_project_sheets_for_vue(sheets) do
    sheets
    |> flatten_sheet_tree()
    |> Enum.map(fn s -> %{id: s.id, name: s.name, shortcut: s.shortcut} end)
  end

  defp flatten_sheet_tree(sheets) do
    Enum.flat_map(sheets, fn sheet ->
      children = Map.get(sheet, :children, [])
      [sheet | flatten_sheet_tree(children)]
    end)
  end

  # ---- Exploration Data ----

  @doc """
  Serializes scene data for exploration mode (read-only player).
  Adds visibility states, patrol routes, and filters by evaluated conditions.
  Zones and pins must have a `:visibility` virtual field pre-evaluated by the caller.
  """
  def prepare_exploration_data_for_vue(scene, zones, pins) do
    connections = scene.connections || []

    %{
      backgroundUrl: background_url(scene),
      sceneWidth: scene.width,
      sceneHeight: scene.height,
      displayMode: scene.exploration_display_mode || "fit",
      defaultZoom: scene.default_zoom || 1.0,
      defaultCenterX: scene.default_center_x,
      defaultCenterY: scene.default_center_y,
      zones:
        Enum.map(zones, fn z ->
          z |> serialize_zone() |> Map.put(:visibility, to_string(z.visibility))
        end),
      pins:
        Enum.map(pins, fn p ->
          serialized = p |> serialize_pin() |> Map.put(:visibility, to_string(p.visibility))

          if p.patrol_mode in [nil, "none"] do
            serialized
          else
            route = build_patrol_route(p, pins, connections)
            Map.put(serialized, :patrolRoute, route)
          end
        end),
      connections: prepare_connections_for_vue(connections)
    }
  end

  # ---- Patrol Route Builder ----

  # Builds an ordered patrol route by traversing connections from the given pin.
  # Returns a flat list of %{x, y, isPinStop} points.
  defp build_patrol_route(pin, pins, connections) do
    pins_by_id = Map.new(pins, &{&1.id, &1})
    start_point = %{x: pin.position_x, y: pin.position_y, isPinStop: true}
    traverse_route([pin.id], pin.id, pins_by_id, connections, [start_point])
  end

  defp traverse_route(visited, current_pin_id, pins_by_id, connections, acc) do
    next_connections = find_unvisited_connections(connections, current_pin_id, visited)

    case next_connections do
      [] ->
        Enum.reverse(acc)

      [conn | _] ->
        {waypoints, target_pin_id} = connection_traversal_data(conn, current_pin_id)
        follow_connection(visited, target_pin_id, waypoints, pins_by_id, connections, acc)
    end
  end

  defp find_unvisited_connections(connections, pin_id, visited) do
    connections
    |> Enum.filter(fn conn ->
      (conn.from_pin_id == pin_id && conn.to_pin_id not in visited) ||
        (conn.bidirectional && conn.to_pin_id == pin_id && conn.from_pin_id not in visited)
    end)
    |> Enum.sort_by(& &1.id)
  end

  defp connection_traversal_data(conn, current_pin_id) do
    if conn.from_pin_id == current_pin_id do
      {conn.waypoints || [], conn.to_pin_id}
    else
      {Enum.reverse(conn.waypoints || []), conn.from_pin_id}
    end
  end

  defp follow_connection(visited, target_pin_id, waypoints, pins_by_id, connections, acc) do
    waypoint_points =
      Enum.map(waypoints, fn wp ->
        %{x: wp["x"], y: wp["y"], isPinStop: false}
      end)

    case Map.get(pins_by_id, target_pin_id) do
      nil ->
        Enum.reverse(acc)

      target_pin ->
        pin_point = %{x: target_pin.position_x, y: target_pin.position_y, isPinStop: true}
        new_acc = [pin_point | Enum.reverse(waypoint_points)] ++ acc

        traverse_route(
          [target_pin_id | visited],
          target_pin_id,
          pins_by_id,
          connections,
          new_acc
        )
    end
  end

  # ---- Private helpers ----

  defp background_url(%{background_asset: %Ecto.Association.NotLoaded{}}), do: nil
  defp background_url(%{background_asset: %{} = asset}), do: Assets.display_url(asset)
  defp background_url(_), do: nil

  defp pin_avatar_url(%{sheet: %{avatars: avatars}}) when is_list(avatars) do
    case Enum.find(avatars, & &1.is_default) || List.first(avatars) do
      %{asset: asset} -> Assets.display_url(asset)
      _ -> nil
    end
  end

  defp pin_avatar_url(_), do: nil

  defp pin_icon_asset_url(%{icon_asset: %Storyarn.Assets.Asset{} = asset}),
    do: Assets.display_url(asset)

  defp pin_icon_asset_url(_), do: nil
end
