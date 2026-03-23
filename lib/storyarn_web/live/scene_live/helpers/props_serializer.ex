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

  # ---- Private helpers ----

  defp background_url(%{background_asset: %{} = asset}), do: Assets.display_url(asset)
  defp background_url(_), do: nil

  defp pin_avatar_url(%{sheet: %{avatars: avatars}}) when is_list(avatars) do
    case Enum.find(avatars, & &1.is_default) || List.first(avatars) do
      %{asset: asset} -> Assets.display_url(asset)
      _ -> nil
    end
  end

  defp pin_avatar_url(_), do: nil

  defp pin_icon_asset_url(%{icon_asset: %{} = asset}), do: Assets.display_url(asset)
  defp pin_icon_asset_url(_), do: nil
end
