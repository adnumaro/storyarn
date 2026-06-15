defmodule StoryarnWeb.SceneLive.Helpers.SceneSerializer do
  @moduledoc """
  Scene data serialization helpers.
  """

  use StoryarnWeb, :verified_routes
  use Gettext, backend: Storyarn.Gettext

  import Phoenix.Component, only: [assign: 3]

  alias Storyarn.Scenes

  def build_scene_data(map, can_edit) do
    %{
      id: map.id,
      name: map.name,
      width: map.width,
      height: map.height,
      default_zoom: map.default_zoom,
      default_center_x: map.default_center_x,
      default_center_y: map.default_center_y,
      background_url: background_url(map),
      scale_unit: map.scale_unit,
      scale_value: map.scale_value,
      fog_color: Map.get(map, :fog_color, "#000000") || "#000000",
      fog_opacity: Map.get(map, :fog_opacity, 0.85) || 0.85,
      can_edit: can_edit,
      boundary_vertices: boundary_vertices(map),
      layers: Enum.map(map.layers || [], &serialize_layer/1),
      pins: Enum.map(map.pins || [], &serialize_pin/1),
      zones: Enum.map(map.zones || [], &serialize_zone/1),
      connections: Enum.map(map.connections || [], &serialize_connection/1),
      annotations: Enum.map(map.annotations || [], &serialize_annotation/1)
    }
  end

  def background_url(%{background_asset: %{url: url}}) when is_binary(url), do: url
  def background_url(_), do: nil

  def reload_scene(socket) do
    scene = Scenes.get_scene(socket.assigns.project.id, socket.assigns.scene.id)

    socket
    |> assign(:scene, scene)
    |> assign(:layers, scene.layers || [])
    |> assign(:zones, scene.zones || [])
    |> assign(:pins, scene.pins || [])
    |> assign(:connections, scene.connections || [])
    |> assign(:annotations, scene.annotations || [])
    |> reload_scenes_tree()
  end

  @doc """
  Notifies the sticky `SceneSidebarLive` that the scenes tree changed so it
  reloads. Show no longer holds `:scenes_tree` — the sidebar is the sole
  source of truth for tree state after the project layout migration.
  """
  def reload_scenes_tree(socket) do
    Phoenix.PubSub.broadcast(
      Storyarn.PubSub,
      StoryarnWeb.Live.Shared.ProjectChromeHelpers.shell_topic(socket.assigns.project.id),
      {:tree_changed, :scenes}
    )

    socket
  end

  def serialize_layer(layer) do
    %{
      id: layer.id,
      name: layer.name,
      visible: layer.visible,
      is_default: layer.is_default,
      position: layer.position,
      fog_enabled: layer.fog_enabled
    }
  end

  def serialize_pin(pin) do
    apply_pin_defaults(%{
      id: pin.id,
      position_x: pin.position_x,
      position_y: pin.position_y,
      pin_type: pin.pin_type,
      icon: pin.icon,
      color: pin.color,
      opacity: pin.opacity,
      label: pin.label,
      shortcut: pin.shortcut,
      hidden: pin.hidden,
      tooltip: pin.tooltip,
      size: pin.size,
      layer_id: pin.layer_id,
      flow_id: pin.flow_id,
      sheet_id: pin.sheet_id,
      avatar_url: pin_avatar_url(pin),
      icon_asset_url: pin_icon_asset_url(pin),
      position: pin.position,
      locked: pin.locked,
      condition: pin.condition,
      condition_effect: pin.condition_effect,
      is_playable: pin.is_playable,
      is_leader: pin.is_leader,
      patrol_mode: pin.patrol_mode,
      patrol_speed: pin.patrol_speed,
      patrol_pause_ms: pin.patrol_pause_ms
    })
  end

  @pin_defaults %{
    locked: false,
    hidden: false,
    condition_effect: "hide",
    is_playable: false,
    is_leader: false,
    patrol_mode: "none",
    patrol_speed: 1.0,
    patrol_pause_ms: 0
  }

  defp apply_pin_defaults(data) do
    Enum.reduce(@pin_defaults, data, fn {key, default}, acc ->
      Map.update!(acc, key, &(&1 || default))
    end)
  end

  def pin_avatar_url(%{sheet: %{avatars: avatars}}) when is_list(avatars) do
    case Enum.find(avatars, & &1.is_default) || List.first(avatars) do
      %{asset: %{url: url}} when is_binary(url) -> url
      _ -> nil
    end
  end

  def pin_avatar_url(_), do: nil

  def pin_icon_asset_url(%{icon_asset: %{url: url}}) when is_binary(url), do: url
  def pin_icon_asset_url(_), do: nil

  def zone_label_icon_asset_url(%{label_icon_asset: %{url: url}}) when is_binary(url), do: url
  def zone_label_icon_asset_url(_), do: nil

  def serialize_zone(zone) do
    zone
    |> zone_base_payload()
    |> Map.merge(zone_visual_payload(zone))
    |> Map.merge(zone_behavior_payload(zone))
  end

  defp zone_base_payload(zone) do
    %{
      id: zone.id,
      name: zone.name,
      shortcut: zone.shortcut,
      hidden: zone.hidden || false,
      vertices: zone.vertices,
      fill_color: zone.fill_color,
      border_color: zone.border_color,
      border_width: zone.border_width,
      border_style: zone.border_style,
      opacity: zone.opacity,
      tooltip: zone.tooltip,
      layer_id: zone.layer_id,
      position: zone.position,
      locked: zone.locked || false
    }
  end

  defp zone_visual_payload(zone) do
    %{
      label_mode: Map.get(zone, :label_mode, "text") || "text",
      label_font_size: Map.get(zone, :label_font_size, 12) || 12,
      label_font_family: Map.get(zone, :label_font_family, "system") || "system",
      label_font_weight: Map.get(zone, :label_font_weight, "600") || "600",
      label_font_style: Map.get(zone, :label_font_style, "normal") || "normal",
      label_icon_asset_id: Map.get(zone, :label_icon_asset_id),
      label_icon_asset_url: zone_label_icon_asset_url(zone)
    }
  end

  defp zone_behavior_payload(zone) do
    %{
      target_type: zone.target_type,
      target_id: zone.target_id,
      action_type: zone.action_type,
      action_data: zone.action_data,
      condition: zone.condition,
      condition_effect: zone.condition_effect || "hide",
      is_walkable: zone.is_walkable || false
    }
  end

  def serialize_connection(conn) do
    %{
      id: conn.id,
      from_pin_id: conn.from_pin_id,
      to_pin_id: conn.to_pin_id,
      line_style: conn.line_style,
      line_width: conn.line_width,
      color: conn.color,
      label: conn.label,
      show_label: conn.show_label,
      bidirectional: conn.bidirectional,
      waypoints: conn.waypoints || [],
      from_stop: Map.get(conn, :from_stop, true),
      to_stop: Map.get(conn, :to_stop, true),
      from_pause_ms: Map.get(conn, :from_pause_ms),
      to_pause_ms: Map.get(conn, :to_pause_ms)
    }
  end

  def serialize_annotation(annotation) do
    %{
      id: annotation.id,
      text: annotation.text,
      position_x: annotation.position_x,
      position_y: annotation.position_y,
      font_size: annotation.font_size,
      color: annotation.color,
      layer_id: annotation.layer_id,
      position: annotation.position,
      locked: annotation.locked || false
    }
  end

  def update_pin_in_list(socket, updated_pin) do
    pins =
      Enum.map(socket.assigns.pins, fn pin ->
        if pin.id == updated_pin.id, do: updated_pin, else: pin
      end)

    assign(socket, :pins, pins)
  end

  def update_zone_in_list(socket, updated_zone) do
    zones =
      Enum.map(socket.assigns.zones, fn zone ->
        if zone.id == updated_zone.id, do: updated_zone, else: zone
      end)

    assign(socket, :zones, zones)
  end

  def zone_error_message(%Ecto.Changeset{} = changeset) do
    if Keyword.has_key?(changeset.errors, :vertices) do
      {msg, _} = Keyword.fetch!(changeset.errors, :vertices)
      dgettext("scenes", "Invalid zone: %{reason}", reason: msg)
    else
      dgettext("scenes", "Could not create zone.")
    end
  end

  def zone_error_message(_), do: dgettext("scenes", "Could not create zone.")

  def default_layer_id(nil), do: nil
  def default_layer_id([]), do: nil

  def default_layer_id(layers) do
    default = Enum.find(layers, fn l -> l.is_default end)
    if default, do: default.id, else: List.first(layers).id
  end

  # ---------------------------------------------------------------------------
  # Boundary polygon for child maps
  # ---------------------------------------------------------------------------

  # When this map was created from a parent zone, compute the zone polygon
  # in child coordinate space so the JS can render a fog overlay outside it.
  defp boundary_vertices(%{parent_id: nil}), do: nil

  defp boundary_vertices(%{parent_id: parent_id, id: scene_id}) do
    case Scenes.get_zone_linking_to_scene(parent_id, scene_id) do
      nil -> nil
      zone -> Scenes.normalize_zone_vertices(zone.vertices)
    end
  end
end
