defmodule StoryarnWeb.SceneLive.Helpers.PropsSerializer do
  @moduledoc """
  Pure functions to serialize Elixir data structures into Vue component-ready props.
  Converts snake_case Ecto structs to camelCase plain maps.
  """

  use Gettext, backend: Storyarn.Gettext

  alias Storyarn.Assets
  alias Storyarn.Assets.Asset
  alias Storyarn.Flows
  alias Storyarn.Scenes.RoutePoints

  # ---- Scene ----

  def format_display_value(value) when is_float(value) do
    if value == trunc(value) do
      Integer.to_string(trunc(value))
    else
      Flows.evaluator_format_value(value)
    end
  end

  def format_display_value(value), do: Flows.evaluator_format_value(value)

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
      labelMode: Map.get(zone, :label_mode, "text") || "text",
      labelFontSize: Map.get(zone, :label_font_size, 12) || 12,
      labelFontFamily: Map.get(zone, :label_font_family, "system") || "system",
      labelFontWeight: Map.get(zone, :label_font_weight, "600") || "600",
      labelFontStyle: Map.get(zone, :label_font_style, "normal") || "normal",
      labelIconAssetId: Map.get(zone, :label_icon_asset_id),
      labelIconAssetUrl: zone_label_icon_asset_url(zone),
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
      toPinId: conn.to_pin_id,
      fromStop: conn.from_stop,
      toStop: conn.to_stop,
      fromPauseMs: conn.from_pause_ms,
      toPauseMs: conn.to_pause_ms
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

  defp pin_type_label("location"), do: dgettext("scenes", "Location")
  defp pin_type_label("character"), do: dgettext("scenes", "Character")
  defp pin_type_label("event"), do: dgettext("scenes", "Event")
  defp pin_type_label("custom"), do: dgettext("scenes", "Custom")
  defp pin_type_label(other), do: other

  @pin_type_icons %{
    "location" => "map-pin",
    "character" => "user",
    "event" => "zap",
    "custom" => "star"
  }

  defp line_style_label("solid"), do: dgettext("scenes", "Solid")
  defp line_style_label("dashed"), do: dgettext("scenes", "Dashed")
  defp line_style_label("dotted"), do: dgettext("scenes", "Dotted")
  defp line_style_label(other), do: other

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
        label: pin_type_label(pin_type),
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

      hex = (avg_opacity * 255) |> round() |> Integer.to_string(16) |> String.pad_leading(2, "0")

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
        label: line_style_label(line_style),
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
  def prepare_exploration_data_for_vue(scene, zones, pins, variables \\ %{}) do
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
          z
          |> serialize_zone()
          |> Map.put(:visibility, to_string(z.visibility))
          |> maybe_put_zone_display_value(z, variables)
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

  defp maybe_put_zone_display_value(serialized, %{action_type: "display", action_data: action_data}, variables)
       when is_map(action_data) and is_map(variables) do
    variable_ref = action_data["variable_ref"]

    case display_variable_value(variables, variable_ref) do
      {:ok, value} -> Map.put(serialized, :displayValue, format_display_value(value))
      :error -> serialized
    end
  end

  defp maybe_put_zone_display_value(serialized, _zone, _variables), do: serialized

  defp display_variable_value(_variables, ref) when not is_binary(ref) or ref == "", do: :error

  defp display_variable_value(variables, ref) do
    case Map.get(variables, ref) do
      %{value: value} -> {:ok, value}
      %{"value" => value} -> {:ok, value}
      _ -> :error
    end
  end

  # ---- Patrol Route Builder ----

  # Builds an ordered patrol route by traversing connections from the given pin.
  # Returns a flat list of %{x, y, isPinStop} points.
  defp build_patrol_route(pin, pins, connections) do
    pins_by_id = Map.new(pins, &{&1.id, &1})
    start_point = route_pin_point(pin, true, nil)
    traverse_route([pin.id], pin.id, pins_by_id, connections, [start_point])
  end

  defp traverse_route(visited, current_pin_id, pins_by_id, connections, acc) do
    next_connections = find_unvisited_connections(connections, current_pin_id, visited)

    case next_connections do
      [] ->
        Enum.reverse(acc)

      [conn | _] ->
        {waypoints, target_pin_id, stop?, pause_ms} = connection_traversal_data(conn, current_pin_id)
        follow_connection(visited, target_pin_id, waypoints, pins_by_id, connections, acc, stop?, pause_ms)
    end
  end

  defp find_unvisited_connections(connections, pin_id, visited) do
    connections
    |> Enum.filter(fn conn ->
      (conn.from_pin_id == pin_id && unvisited_target?(conn.to_pin_id, visited)) ||
        (conn.bidirectional && conn.to_pin_id == pin_id && unvisited_target?(conn.from_pin_id, visited))
    end)
    |> Enum.sort_by(& &1.id)
  end

  defp unvisited_target?(nil, _visited), do: true
  defp unvisited_target?(target_pin_id, visited), do: target_pin_id not in visited

  defp connection_traversal_data(conn, current_pin_id) do
    if conn.from_pin_id == current_pin_id do
      {conn.waypoints || [], conn.to_pin_id, conn.to_stop, conn.to_pause_ms}
    else
      {Enum.reverse(conn.waypoints || []), conn.from_pin_id, conn.from_stop, conn.from_pause_ms}
    end
  end

  defp follow_connection(visited, target_pin_id, waypoints, pins_by_id, connections, acc, stop?, pause_ms) do
    waypoint_points = Enum.map(waypoints, &route_waypoint/1)
    acc = Enum.reverse(waypoint_points, acc)

    case Map.get(pins_by_id, target_pin_id) do
      nil when is_nil(target_pin_id) ->
        Enum.reverse(acc)

      nil ->
        Enum.reverse(acc)

      target_pin ->
        pin_point = route_pin_point(target_pin, stop?, pause_ms)

        traverse_route(
          [target_pin_id | visited],
          target_pin_id,
          pins_by_id,
          connections,
          [pin_point | acc]
        )
    end
  end

  defp route_pin_point(pin, stop?, pause_ms) do
    %{x: pin.position_x, y: pin.position_y, isPinStop: true, isStop: stop?, pauseMs: pause_ms}
  end

  defp route_waypoint(wp) do
    stop? = Map.get(wp, "stop", false)
    pause_ms = RoutePoints.waypoint_pause_ms(wp)

    %{x: wp["x"], y: wp["y"], isPinStop: false, isStop: stop?, pauseMs: pause_ms}
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

  defp pin_icon_asset_url(%{icon_asset: %Asset{} = asset}), do: Assets.display_url(asset)

  defp pin_icon_asset_url(_), do: nil

  defp zone_label_icon_asset_url(%{label_icon_asset: %Asset{} = asset}), do: Assets.display_url(asset)

  defp zone_label_icon_asset_url(_), do: nil
end
