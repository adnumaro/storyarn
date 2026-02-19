defmodule StoryarnWeb.MapLive.Helpers.Serializer do
  @moduledoc """
  Map data serialization helpers.
  """

  import Phoenix.Component, only: [assign: 3]
  use StoryarnWeb, :verified_routes
  use Gettext, backend: StoryarnWeb.Gettext

  alias Storyarn.Maps
  alias Storyarn.Maps.ZoneImageExtractor

  def build_map_data(map, can_edit) do
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

  def reload_map(socket) do
    map = Maps.get_map(socket.assigns.project.id, socket.assigns.map.id)

    socket
    |> assign(:map, map)
    |> assign(:layers, map.layers || [])
    |> assign(:zones, map.zones || [])
    |> assign(:pins, map.pins || [])
    |> assign(:connections, map.connections || [])
    |> assign(:annotations, map.annotations || [])
    |> reload_maps_tree()
  end

  def reload_maps_tree(socket) do
    assign(socket, :maps_tree, Maps.list_maps_tree_with_elements(socket.assigns.project.id))
  end

  def serialize_layer(layer) do
    %{
      id: layer.id,
      name: layer.name,
      visible: layer.visible,
      is_default: layer.is_default,
      position: layer.position,
      fog_enabled: layer.fog_enabled,
      fog_color: layer.fog_color,
      fog_opacity: layer.fog_opacity
    }
  end

  def serialize_pin(pin) do
    %{
      id: pin.id,
      position_x: pin.position_x,
      position_y: pin.position_y,
      pin_type: pin.pin_type,
      icon: pin.icon,
      color: pin.color,
      opacity: pin.opacity,
      label: pin.label,
      tooltip: pin.tooltip,
      size: pin.size,
      layer_id: pin.layer_id,
      target_type: pin.target_type,
      target_id: pin.target_id,
      sheet_id: pin.sheet_id,
      avatar_url: pin_avatar_url(pin),
      icon_asset_url: pin_icon_asset_url(pin),
      position: pin.position,
      locked: pin.locked || false
    }
  end

  def pin_avatar_url(%{sheet: %{avatar_asset: %{url: url}}}) when is_binary(url), do: url
  def pin_avatar_url(_), do: nil

  def pin_icon_asset_url(%{icon_asset: %{url: url}}) when is_binary(url), do: url
  def pin_icon_asset_url(_), do: nil

  def serialize_zone(zone) do
    %{
      id: zone.id,
      name: zone.name,
      vertices: zone.vertices,
      fill_color: zone.fill_color,
      border_color: zone.border_color,
      border_width: zone.border_width,
      border_style: zone.border_style,
      opacity: zone.opacity,
      tooltip: zone.tooltip,
      layer_id: zone.layer_id,
      target_type: zone.target_type,
      target_id: zone.target_id,
      position: zone.position,
      locked: zone.locked || false
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
      waypoints: conn.waypoints || []
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

  def zone_error_message(%Ecto.Changeset{} = changeset) do
    if Keyword.has_key?(changeset.errors, :vertices) do
      {msg, _} = Keyword.fetch!(changeset.errors, :vertices)
      dgettext("maps", "Invalid zone: %{reason}", reason: msg)
    else
      dgettext("maps", "Could not create zone.")
    end
  end

  def zone_error_message(_), do: dgettext("maps", "Could not create zone.")

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

  defp boundary_vertices(%{parent_id: parent_id, id: map_id}) do
    case Maps.get_zone_linking_to_map(parent_id, map_id) do
      nil -> nil
      zone -> ZoneImageExtractor.normalize_vertices_to_bbox(zone.vertices)
    end
  end
end
