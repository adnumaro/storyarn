defmodule StoryarnWeb.MapLive.Helpers.MapHelpers do
  @moduledoc """
  Pure utility helpers for the map LiveView.
  """

  import Phoenix.Component, only: [assign: 3]
  use StoryarnWeb, :verified_routes
  use Gettext, backend: StoryarnWeb.Gettext

  alias Storyarn.Maps

  @element_icons %{
    "pin" => "map-pin",
    "zone" => "pentagon",
    "connection" => "cable",
    "annotation" => "sticky-note"
  }

  # ---------------------------------------------------------------------------
  # Search helpers
  # ---------------------------------------------------------------------------

  def search_map_elements(socket, query, filter) do
    q = String.downcase(query)

    []
    |> maybe_search(filter, "pin", fn -> search_pins(socket.assigns.pins, q) end)
    |> maybe_search(filter, "zone", fn -> search_zones(socket.assigns.zones, q) end)
    |> maybe_search(filter, "annotation", fn -> search_annotations(socket.assigns.annotations, q) end)
    |> maybe_search(filter, "connection", fn -> search_connections(socket.assigns.connections, q) end)
  end

  def maybe_search(acc, "all", _type, fun), do: acc ++ fun.()
  def maybe_search(acc, filter, filter, fun), do: acc ++ fun.()
  def maybe_search(acc, _filter, _type, _fun), do: acc

  def search_pins(pins, q) do
    pins
    |> Enum.filter(&matches_text?(&1.label, q))
    |> Enum.map(&%{type: "pin", id: &1.id, label: &1.label || dgettext("maps", "Pin")})
  end

  def search_zones(zones, q) do
    zones
    |> Enum.filter(&matches_text?(&1.name, q))
    |> Enum.map(&%{type: "zone", id: &1.id, label: &1.name || dgettext("maps", "Zone")})
  end

  def search_annotations(annotations, q) do
    annotations
    |> Enum.filter(&matches_text?(&1.text, q))
    |> Enum.map(&%{type: "annotation", id: &1.id, label: &1.text || dgettext("maps", "Note")})
  end

  def search_connections(connections, q) do
    connections
    |> Enum.filter(&matches_text?(&1.label, q))
    |> Enum.map(&%{type: "connection", id: &1.id, label: &1.label || dgettext("maps", "Connection")})
  end

  def matches_text?(nil, _q), do: false
  def matches_text?(text, q), do: String.contains?(String.downcase(text), q)

  def search_result_icon(type), do: Map.get(@element_icons, type, "search")

  # ---------------------------------------------------------------------------
  # Parse helpers
  # ---------------------------------------------------------------------------

  def parse_id(id) when is_integer(id), do: id

  def parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int, ""} -> int
      _ -> id
    end
  end

  def parse_float(val, default \\ 0.85)
  def parse_float("", default), do: default
  def parse_float(nil, default), do: default
  def parse_float(val, _default) when is_float(val), do: val
  def parse_float(val, _default) when is_integer(val), do: val / 1

  def parse_float(val, default) when is_binary(val) do
    case Float.parse(val) do
      {f, _} -> f
      :error -> default
    end
  end

  def parse_float(_, default), do: default

  def parse_float_or_nil(val), do: parse_float(val, nil)

  def parse_scale_field("scale_value", raw) do
    case parse_float_or_nil(raw) do
      v when is_number(v) and v > 0 -> v
      _ -> nil
    end
  end

  def parse_scale_field(_field, value), do: value

  def parse_int(""), do: nil
  def parse_int(nil), do: nil
  def parse_int(val) when is_integer(val), do: val

  def parse_int(str) when is_binary(str) do
    case Integer.parse(str) do
      {int, ""} -> int
      _ -> nil
    end
  end

  # ---------------------------------------------------------------------------
  # Field / list helpers
  # ---------------------------------------------------------------------------

  # Checkbox phx-click sends DOM value "on" as "value", so boolean toggles
  # use phx-value-toggle to avoid the collision.
  def extract_field_value(%{"toggle" => value}, _field), do: value
  def extract_field_value(%{"value" => value}, _field), do: value

  def extract_field_value(params, field) do
    # For phx-blur inputs, value comes from the input's value attribute
    Map.get(params, field, Map.get(params, "value", ""))
  end

  def replace_in_list(list, updated) do
    Enum.map(list, &replace_element(&1, updated))
  end

  def replace_element(element, updated) when element.id == updated.id, do: updated
  def replace_element(element, _updated), do: element

  def maybe_update_selected_element(socket, type, updated) do
    if socket.assigns.selected_type == type &&
         socket.assigns.selected_element &&
         socket.assigns.selected_element.id == updated.id do
      assign(socket, :selected_element, updated)
    else
      socket
    end
  end

  # ---------------------------------------------------------------------------
  # Panel icon/title helpers
  # ---------------------------------------------------------------------------

  def panel_icon(type), do: Map.get(@element_icons, type, "settings")

  def panel_title("pin"), do: dgettext("maps", "Pin Properties")
  def panel_title("zone"), do: dgettext("maps", "Zone Properties")
  def panel_title("connection"), do: dgettext("maps", "Connection Properties")
  def panel_title("annotation"), do: dgettext("maps", "Annotation Properties")
  def panel_title(_), do: dgettext("maps", "Properties")

  # ---------------------------------------------------------------------------
  # Sheet helpers
  # ---------------------------------------------------------------------------

  def flatten_sheets(sheets) do
    Enum.flat_map(sheets, fn sheet ->
      children = if Map.has_key?(sheet, :children) && is_list(sheet.children), do: sheet.children, else: []
      [sheet | flatten_sheets(children)]
    end)
  end

  def sheet_avatar_url(%{avatar_asset: %{url: url}}) when is_binary(url), do: url
  def sheet_avatar_url(_), do: nil

  # ---------------------------------------------------------------------------
  # Element loading
  # ---------------------------------------------------------------------------

  def load_element("pin", id, map_id), do: Maps.get_pin(map_id, id)
  def load_element("zone", id, map_id), do: Maps.get_zone(map_id, id)
  def load_element("connection", id, map_id), do: Maps.get_connection(map_id, id)
  def load_element("annotation", id, map_id), do: Maps.get_annotation(map_id, id)
  def load_element(_, _, _), do: nil
end
