defmodule StoryarnWeb.MapLive.Handlers.ElementHandlers do
  @moduledoc """
  Element (pin/zone/connection/annotation) handlers for the map LiveView.
  """

  import Phoenix.Component, only: [assign: 2, assign: 3]
  import Phoenix.LiveView, only: [push_event: 3, put_flash: 3]
  use StoryarnWeb, :verified_routes
  use Gettext, backend: StoryarnWeb.Gettext

  alias Storyarn.Maps
  import StoryarnWeb.MapLive.Helpers.MapHelpers
  import StoryarnWeb.MapLive.Helpers.Serializer
  import StoryarnWeb.MapLive.Handlers.UndoRedoHandlers, only: [push_undo: 2]

  # ---------------------------------------------------------------------------
  # Pin handlers
  # ---------------------------------------------------------------------------

  def handle_create_pin(%{"position_x" => x, "position_y" => y}, socket) do
    attrs = %{
      "position_x" => x,
      "position_y" => y,
      "label" => dgettext("maps", "New Pin"),
      "pin_type" => "location",
      "layer_id" => socket.assigns.active_layer_id
    }

    case Maps.create_pin(socket.assigns.map.id, attrs) do
      {:ok, pin} ->
        {:noreply,
         socket
         |> assign(:pins, socket.assigns.pins ++ [pin])
         |> assign(:selected_type, "pin")
         |> assign(:selected_element, pin)
         |> push_event("pin_created", serialize_pin(pin))
         |> push_event("element_selected", %{type: "pin", id: pin.id})
         |> reset_tool_to_select()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("maps", "Could not create pin."))}
    end
  end

  def handle_move_pin(%{"id" => pin_id, "position_x" => x, "position_y" => y}, socket) do
    case Maps.get_pin(socket.assigns.map.id, pin_id) do
      nil -> {:noreply, socket}
      pin -> do_move_pin(socket, pin, x, y)
    end
  end

  def handle_show_sheet_picker(_params, socket) do
    {:noreply, assign(socket, :show_sheet_picker, true)}
  end

  def handle_cancel_sheet_picker(_params, socket) do
    {:noreply,
     socket
     |> assign(show_sheet_picker: false, pending_sheet_for_pin: nil)
     |> push_event("pending_sheet_changed", %{active: false})}
  end

  def handle_start_pin_from_sheet(%{"sheet-id" => sheet_id}, socket) do
    raw_sheet = Storyarn.Sheets.get_sheet(socket.assigns.project.id, sheet_id)
    sheet = if raw_sheet, do: Storyarn.Repo.preload(raw_sheet, avatar_asset: []), else: nil

    if sheet do
      {:noreply,
       socket
       |> assign(:pending_sheet_for_pin, sheet)
       |> assign(:show_sheet_picker, false)
       |> assign(:active_tool, :pin)
       |> push_event("tool_changed", %{tool: "pin"})
       |> push_event("pending_sheet_changed", %{active: true})}
    else
      {:noreply, put_flash(socket, :error, dgettext("maps", "Sheet not found."))}
    end
  end

  def handle_create_pin_from_sheet(%{"position_x" => x, "position_y" => y}, socket) do
    do_create_pin_from_sheet(socket, x, y)
  end

  def handle_delete_pin(%{"id" => pin_id}, socket) do
    case Maps.get_pin(socket.assigns.map.id, pin_id) do
      nil -> {:noreply, socket}
      pin -> do_delete_pin(socket, pin)
    end
  end

  def handle_update_pin(%{"field" => field} = params, socket) do
    id = params["id"] || params["element_id"]

    case Maps.get_pin(socket.assigns.map.id, id) do
      nil -> {:noreply, socket}
      pin -> do_update_pin(socket, pin, field, extract_field_value(params, field))
    end
  end

  def handle_set_pending_delete_pin(%{"id" => id}, socket) do
    {:noreply, assign(socket, :pending_delete_element, {:pin, parse_id(id)})}
  end

  def handle_confirm_delete_element(_params, socket) do
    case socket.assigns[:pending_delete_element] do
      {:pin, id} ->
        handle_delete_pin(%{"id" => to_string(id)}, socket)

      {:zone, id} ->
        handle_delete_zone(%{"id" => to_string(id)}, socket)

      {:connection, id} ->
        handle_delete_connection(%{"id" => to_string(id)}, socket)

      {:annotation, id} ->
        handle_delete_annotation(%{"id" => to_string(id)}, socket)

      _ ->
        {:noreply, socket}
    end
  end

  # ---------------------------------------------------------------------------
  # Zone handlers
  # ---------------------------------------------------------------------------

  def handle_create_zone(%{"vertices" => vertices} = params, socket) do
    name = params["name"]
    name = if name == "" or is_nil(name), do: dgettext("maps", "New Zone"), else: name

    attrs = %{
      "name" => name,
      "vertices" => vertices,
      "layer_id" => socket.assigns.active_layer_id
    }

    case Maps.create_zone(socket.assigns.map.id, attrs) do
      {:ok, zone} ->
        {:noreply,
         socket
         |> assign(:zones, socket.assigns.zones ++ [zone])
         |> assign(:selected_type, "zone")
         |> assign(:selected_element, zone)
         |> push_event("zone_created", serialize_zone(zone))
         |> push_event("element_selected", %{type: "zone", id: zone.id})
         |> reset_tool_to_select()}

      {:error, changeset} ->
        msg = zone_error_message(changeset)
        {:noreply, put_flash(socket, :error, msg)}
    end
  end

  def handle_update_zone(%{"field" => field} = params, socket) do
    id = params["id"] || params["element_id"]

    case Maps.get_zone(socket.assigns.map.id, id) do
      nil -> {:noreply, socket}
      zone -> do_update_zone(socket, zone, field, extract_field_value(params, field))
    end
  end

  def handle_update_zone_vertices(%{"id" => id, "vertices" => vertices}, socket) do
    case Maps.get_zone(socket.assigns.map.id, id) do
      nil -> {:noreply, socket}
      zone -> do_update_zone_vertices(socket, zone, vertices)
    end
  end

  def handle_duplicate_zone(%{"id" => zone_id}, socket) do
    case Maps.get_zone(socket.assigns.map.id, zone_id) do
      nil -> {:noreply, socket}
      zone -> do_duplicate_zone(socket, zone)
    end
  end

  def handle_delete_zone(%{"id" => zone_id}, socket) do
    case Maps.get_zone(socket.assigns.map.id, zone_id) do
      nil -> {:noreply, socket}
      zone -> do_delete_zone(socket, zone)
    end
  end

  def handle_set_pending_delete_zone(%{"id" => id}, socket) do
    {:noreply, assign(socket, :pending_delete_element, {:zone, parse_id(id)})}
  end

  # ---------------------------------------------------------------------------
  # Connection handlers
  # ---------------------------------------------------------------------------

  def handle_create_connection(%{"from_pin_id" => from_pin_id, "to_pin_id" => to_pin_id}, socket) do
    attrs = %{
      "from_pin_id" => from_pin_id,
      "to_pin_id" => to_pin_id
    }

    case Maps.create_connection(socket.assigns.map.id, attrs) do
      {:ok, conn} ->
        {:noreply,
         socket
         |> assign(:connections, socket.assigns.connections ++ [conn])
         |> push_event("connection_created", serialize_connection(conn))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("maps", "Could not create connection."))}
    end
  end

  def handle_update_connection(%{"field" => field} = params, socket) do
    id = params["id"] || params["element_id"]

    case Maps.get_connection(socket.assigns.map.id, id) do
      nil -> {:noreply, socket}
      conn -> do_update_connection(socket, conn, field, extract_field_value(params, field))
    end
  end

  def handle_update_connection_waypoints(%{"id" => id, "waypoints" => waypoints}, socket) do
    case Maps.get_connection(socket.assigns.map.id, id) do
      nil -> {:noreply, socket}
      conn -> do_update_connection_waypoints(socket, conn, waypoints)
    end
  end

  def handle_clear_connection_waypoints(%{"id" => id}, socket) do
    case Maps.get_connection(socket.assigns.map.id, id) do
      nil -> {:noreply, socket}
      conn -> do_clear_connection_waypoints(socket, conn)
    end
  end

  def handle_delete_connection(%{"id" => connection_id}, socket) do
    case Maps.get_connection(socket.assigns.map.id, connection_id) do
      nil -> {:noreply, socket}
      connection -> do_delete_connection(socket, connection)
    end
  end

  def handle_set_pending_delete_connection(%{"id" => id}, socket) do
    {:noreply, assign(socket, :pending_delete_element, {:connection, parse_id(id)})}
  end

  # ---------------------------------------------------------------------------
  # Annotation handlers
  # ---------------------------------------------------------------------------

  def handle_create_annotation(%{"position_x" => x, "position_y" => y} = params, socket) do
    attrs = %{
      "text" => params["text"] || dgettext("maps", "Note"),
      "position_x" => x,
      "position_y" => y,
      "font_size" => params["font_size"] || "md",
      "color" => params["color"],
      "layer_id" => socket.assigns.active_layer_id
    }

    case Maps.create_annotation(socket.assigns.map.id, attrs) do
      {:ok, annotation} ->
        {:noreply,
         socket
         |> assign(:annotations, socket.assigns.annotations ++ [annotation])
         |> assign(:selected_type, "annotation")
         |> assign(:selected_element, annotation)
         |> push_event("annotation_created", serialize_annotation(annotation))
         |> push_event("element_selected", %{type: "annotation", id: annotation.id})
         |> push_event("focus_annotation_text", %{})
         |> reset_tool_to_select()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("maps", "Could not create annotation."))}
    end
  end

  def handle_update_annotation(%{"field" => field} = params, socket) do
    id = params["id"] || params["element_id"]
    value = params["value"] || params[field]

    case Maps.get_annotation(socket.assigns.map.id, id) do
      nil -> {:noreply, socket}
      annotation -> do_update_annotation(socket, annotation, field, value)
    end
  end

  def handle_move_annotation(%{"id" => id, "position_x" => x, "position_y" => y}, socket) do
    case Maps.get_annotation(socket.assigns.map.id, id) do
      nil -> {:noreply, socket}
      annotation -> do_move_annotation(socket, annotation, x, y)
    end
  end

  def handle_delete_annotation(%{"id" => annotation_id}, socket) do
    case Maps.get_annotation(socket.assigns.map.id, annotation_id) do
      nil -> {:noreply, socket}
      annotation -> do_delete_annotation(socket, annotation)
    end
  end

  def handle_set_pending_delete_annotation(%{"id" => id}, socket) do
    {:noreply, assign(socket, :pending_delete_element, {:annotation, parse_id(id)})}
  end

  # ---------------------------------------------------------------------------
  # Keyboard shortcut handlers (delete / duplicate / copy / paste)
  # ---------------------------------------------------------------------------

  def handle_delete_selected(socket) do
    case {socket.assigns.selected_type, socket.assigns.selected_element} do
      {nil, _} -> {:noreply, socket}
      {"pin", pin} -> do_delete_pin(socket, pin)
      {"zone", zone} -> do_delete_zone(socket, zone)
      {"connection", conn} -> do_delete_connection(socket, conn)
      {"annotation", ann} -> do_delete_annotation(socket, ann)
      _ -> {:noreply, socket}
    end
  end

  def handle_duplicate_selected(socket) do
    case {socket.assigns.selected_type, socket.assigns.selected_element} do
      {nil, _} -> {:noreply, socket}
      {"pin", pin} -> do_duplicate_pin(socket, pin)
      {"zone", zone} -> do_duplicate_zone(socket, zone)
      {"annotation", ann} -> do_duplicate_annotation(socket, ann)
      _ -> {:noreply, socket}
    end
  end

  def handle_copy_selected(socket) do
    case {socket.assigns.selected_type, socket.assigns.selected_element} do
      {nil, _} ->
        {:noreply, socket}

      {type, element} ->
        data = serialize_element_for_clipboard(type, element)
        {:noreply, push_event(socket, "element_copied", data)}
    end
  end

  def handle_paste_element(%{"type" => type, "attrs" => attrs}, socket) do
    attrs = shift_paste_position(attrs)

    case type do
      "pin" -> do_create_pin_from_clipboard(socket, attrs)
      "zone" -> do_create_zone_from_clipboard(socket, attrs)
      "annotation" -> do_create_annotation_from_clipboard(socket, attrs)
      _ -> {:noreply, socket}
    end
  end

  def handle_paste_element(_params, socket), do: {:noreply, socket}

  # ---------------------------------------------------------------------------
  # Private do_* helpers
  # ---------------------------------------------------------------------------

  defp do_create_pin_from_sheet(socket, _x, _y) when is_nil(socket.assigns.pending_sheet_for_pin) do
    {:noreply, put_flash(socket, :error, dgettext("maps", "No sheet selected."))}
  end

  defp do_create_pin_from_sheet(socket, x, y) do
    sheet = socket.assigns.pending_sheet_for_pin

    attrs = %{
      "position_x" => x,
      "position_y" => y,
      "label" => sheet.name,
      "pin_type" => "character",
      "sheet_id" => sheet.id,
      "target_type" => "sheet",
      "target_id" => sheet.id,
      "layer_id" => socket.assigns.active_layer_id
    }

    case Maps.create_pin(socket.assigns.map.id, attrs) do
      {:ok, pin} ->
        pin = %{pin | sheet: sheet}

        {:noreply,
         socket
         |> assign(:pins, socket.assigns.pins ++ [pin])
         |> assign(:pending_sheet_for_pin, nil)
         |> assign(:active_tool, :select)
         |> push_event("pin_created", serialize_pin(pin))
         |> push_event("tool_changed", %{tool: "select"})
         |> push_event("pending_sheet_changed", %{active: false})}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("maps", "Could not create pin."))}
    end
  end

  defp do_move_pin(socket, %{locked: true}, _x, _y), do: {:noreply, socket}

  defp do_move_pin(socket, pin, x, y) do
    case Maps.move_pin(pin, x, y) do
      {:ok, _updated} -> {:noreply, socket}
      {:error, _} -> {:noreply, put_flash(socket, :error, dgettext("maps", "Could not move pin."))}
    end
  end

  defp do_delete_pin(socket, %{locked: true}) do
    {:noreply, put_flash(socket, :error, dgettext("maps", "Cannot delete a locked element."))}
  end

  defp do_delete_pin(socket, pin) do
    case Maps.delete_pin(pin) do
      {:ok, _} ->
        {:noreply,
         socket
         |> push_undo({:delete_pin, pin})
         |> assign(:selected_element, nil)
         |> assign(:selected_type, nil)
         |> push_event("pin_deleted", %{id: pin.id})
         |> put_flash(:info, dgettext("maps", "Pin deleted. Press Ctrl+Z to undo."))
         |> reload_map()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("maps", "Could not delete pin."))}
    end
  end

  defp do_update_pin(socket, pin, field, value) do
    case Maps.update_pin(pin, %{field => value}) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:selected_element, updated)
         |> assign(:pins, replace_in_list(socket.assigns.pins, updated))
         |> push_event("pin_updated", serialize_pin(updated))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("maps", "Could not update pin."))}
    end
  end

  defp do_update_zone_vertices(socket, %{locked: true}, _vertices), do: {:noreply, socket}

  defp do_update_zone_vertices(socket, zone, vertices) do
    case Maps.update_zone_vertices(zone, %{"vertices" => vertices}) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:zones, replace_in_list(socket.assigns.zones, updated))
         |> maybe_update_selected_element("zone", updated)
         |> push_event("zone_vertices_updated", serialize_zone(updated))}

      {:error, changeset} ->
        msg = zone_error_message(changeset)
        {:noreply, put_flash(socket, :error, msg)}
    end
  end

  defp do_update_zone(socket, zone, field, value) do
    case Maps.update_zone(zone, %{field => value}) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:selected_element, updated)
         |> assign(:zones, replace_in_list(socket.assigns.zones, updated))
         |> push_event("zone_updated", serialize_zone(updated))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("maps", "Could not update zone."))}
    end
  end

  defp do_duplicate_zone(socket, zone) do
    shifted_vertices =
      Enum.map(zone.vertices, fn v ->
        %{"x" => min(v["x"] + 5, 100.0), "y" => min(v["y"] + 5, 100.0)}
      end)

    attrs = %{
      "name" => zone.name <> " (copy)",
      "vertices" => shifted_vertices,
      "fill_color" => zone.fill_color,
      "border_color" => zone.border_color,
      "border_width" => zone.border_width,
      "border_style" => zone.border_style,
      "opacity" => zone.opacity,
      "layer_id" => zone.layer_id
    }

    case Maps.create_zone(socket.assigns.map.id, attrs) do
      {:ok, new_zone} ->
        {:noreply,
         socket
         |> assign(:zones, socket.assigns.zones ++ [new_zone])
         |> push_event("zone_created", serialize_zone(new_zone))
         |> put_flash(:info, dgettext("maps", "Zone duplicated."))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("maps", "Could not duplicate zone."))}
    end
  end

  defp do_delete_zone(socket, %{locked: true}) do
    {:noreply, put_flash(socket, :error, dgettext("maps", "Cannot delete a locked element."))}
  end

  defp do_delete_zone(socket, zone) do
    case Maps.delete_zone(zone) do
      {:ok, _} ->
        {:noreply,
         socket
         |> push_undo({:delete_zone, zone})
         |> assign(:selected_element, nil)
         |> assign(:selected_type, nil)
         |> push_event("zone_deleted", %{id: zone.id})
         |> put_flash(:info, dgettext("maps", "Zone deleted. Press Ctrl+Z to undo."))
         |> reload_map()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("maps", "Could not delete zone."))}
    end
  end

  defp do_update_connection(socket, conn, field, value) do
    case Maps.update_connection(conn, %{field => value}) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:selected_element, updated)
         |> assign(:connections, replace_in_list(socket.assigns.connections, updated))
         |> push_event("connection_updated", serialize_connection(updated))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("maps", "Could not update connection."))}
    end
  end

  defp do_update_connection_waypoints(socket, conn, waypoints) do
    case Maps.update_connection_waypoints(conn, %{"waypoints" => waypoints}) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:selected_element, updated)
         |> push_event("connection_updated", serialize_connection(updated))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("maps", "Could not update waypoints."))}
    end
  end

  defp do_clear_connection_waypoints(socket, conn) do
    case Maps.update_connection_waypoints(conn, %{"waypoints" => []}) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:selected_element, updated)
         |> push_event("connection_updated", serialize_connection(updated))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("maps", "Could not clear waypoints."))}
    end
  end

  defp do_delete_connection(socket, connection) do
    case Maps.delete_connection(connection) do
      {:ok, _} ->
        {:noreply,
         socket
         |> push_undo({:delete_connection, connection})
         |> assign(:selected_element, nil)
         |> assign(:selected_type, nil)
         |> push_event("connection_deleted", %{id: connection.id})
         |> put_flash(:info, dgettext("maps", "Connection deleted. Press Ctrl+Z to undo."))
         |> reload_map()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("maps", "Could not delete connection."))}
    end
  end

  defp do_update_annotation(socket, annotation, field, value) do
    case Maps.update_annotation(annotation, %{field => value}) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:annotations, replace_in_list(socket.assigns.annotations, updated))
         |> maybe_update_selected_element("annotation", updated)
         |> push_event("annotation_updated", serialize_annotation(updated))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("maps", "Could not update annotation."))}
    end
  end

  defp do_move_annotation(socket, %{locked: true}, _x, _y), do: {:noreply, socket}

  defp do_move_annotation(socket, annotation, x, y) do
    case Maps.move_annotation(annotation, x, y) do
      {:ok, _updated} -> {:noreply, socket}
      {:error, _} -> {:noreply, put_flash(socket, :error, dgettext("maps", "Could not move annotation."))}
    end
  end

  defp do_delete_annotation(socket, %{locked: true}) do
    {:noreply, put_flash(socket, :error, dgettext("maps", "Cannot delete a locked element."))}
  end

  defp do_delete_annotation(socket, annotation) do
    case Maps.delete_annotation(annotation) do
      {:ok, _} ->
        {:noreply,
         socket
         |> push_undo({:delete_annotation, annotation})
         |> assign(:annotations, Enum.reject(socket.assigns.annotations, &(&1.id == annotation.id)))
         |> assign(:selected_element, nil)
         |> assign(:selected_type, nil)
         |> push_event("annotation_deleted", %{id: annotation.id})
         |> put_flash(:info, dgettext("maps", "Annotation deleted. Press Ctrl+Z to undo."))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("maps", "Could not delete annotation."))}
    end
  end

  defp do_duplicate_pin(socket, %{locked: true}) do
    {:noreply, put_flash(socket, :error, dgettext("maps", "Cannot duplicate a locked element."))}
  end

  defp do_duplicate_pin(socket, pin) do
    attrs = %{
      "position_x" => min(pin.position_x + 5, 100.0),
      "position_y" => min(pin.position_y + 5, 100.0),
      "label" => pin.label <> " (copy)",
      "pin_type" => pin.pin_type,
      "icon" => pin.icon,
      "color" => pin.color,
      "size" => pin.size,
      "tooltip" => pin.tooltip,
      "layer_id" => pin.layer_id
    }

    case Maps.create_pin(socket.assigns.map.id, attrs) do
      {:ok, new_pin} ->
        {:noreply,
         socket
         |> assign(:pins, socket.assigns.pins ++ [new_pin])
         |> assign(:selected_type, "pin")
         |> assign(:selected_element, new_pin)
         |> push_event("pin_created", serialize_pin(new_pin))
         |> push_event("element_selected", %{type: "pin", id: new_pin.id})
         |> put_flash(:info, dgettext("maps", "Pin duplicated."))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("maps", "Could not duplicate pin."))}
    end
  end

  defp do_duplicate_annotation(socket, %{locked: true}) do
    {:noreply, put_flash(socket, :error, dgettext("maps", "Cannot duplicate a locked element."))}
  end

  defp do_duplicate_annotation(socket, annotation) do
    attrs = %{
      "text" => annotation.text <> " (copy)",
      "position_x" => min(annotation.position_x + 5, 100.0),
      "position_y" => min(annotation.position_y + 5, 100.0),
      "font_size" => annotation.font_size,
      "color" => annotation.color,
      "layer_id" => annotation.layer_id
    }

    case Maps.create_annotation(socket.assigns.map.id, attrs) do
      {:ok, new_ann} ->
        {:noreply,
         socket
         |> assign(:annotations, socket.assigns.annotations ++ [new_ann])
         |> assign(:selected_type, "annotation")
         |> assign(:selected_element, new_ann)
         |> push_event("annotation_created", serialize_annotation(new_ann))
         |> push_event("element_selected", %{type: "annotation", id: new_ann.id})
         |> put_flash(:info, dgettext("maps", "Annotation duplicated."))}

      {:error, _} ->
        {:noreply,
         put_flash(socket, :error, dgettext("maps", "Could not duplicate annotation."))}
    end
  end

  # ---------------------------------------------------------------------------
  # Clipboard serialization & paste helpers
  # ---------------------------------------------------------------------------

  defp serialize_element_for_clipboard("pin", pin) do
    %{
      type: "pin",
      attrs: %{
        position_x: pin.position_x,
        position_y: pin.position_y,
        label: pin.label,
        pin_type: pin.pin_type,
        icon: pin.icon,
        color: pin.color,
        size: pin.size,
        tooltip: pin.tooltip
      }
    }
  end

  defp serialize_element_for_clipboard("zone", zone) do
    %{
      type: "zone",
      attrs: %{
        name: zone.name,
        vertices: zone.vertices,
        fill_color: zone.fill_color,
        border_color: zone.border_color,
        border_width: zone.border_width,
        border_style: zone.border_style,
        opacity: zone.opacity
      }
    }
  end

  defp serialize_element_for_clipboard("annotation", annotation) do
    %{
      type: "annotation",
      attrs: %{
        text: annotation.text,
        position_x: annotation.position_x,
        position_y: annotation.position_y,
        font_size: annotation.font_size,
        color: annotation.color
      }
    }
  end

  defp serialize_element_for_clipboard(_type, _element), do: %{type: "unknown", attrs: %{}}

  defp shift_paste_position(attrs) do
    attrs
    |> shift_field("position_x")
    |> shift_field("position_y")
    |> shift_vertices()
  end

  defp shift_field(attrs, key) do
    case Map.get(attrs, key) do
      val when is_number(val) -> Map.put(attrs, key, min(val + 5, 100.0))
      _ -> attrs
    end
  end

  defp shift_vertices(%{"vertices" => verts} = attrs) when is_list(verts) do
    shifted =
      Enum.map(verts, fn v ->
        %{
          "x" => min((v["x"] || 0) + 5, 100.0),
          "y" => min((v["y"] || 0) + 5, 100.0)
        }
      end)

    Map.put(attrs, "vertices", shifted)
  end

  defp shift_vertices(attrs), do: attrs

  defp do_create_pin_from_clipboard(socket, attrs) do
    pin_attrs = %{
      "position_x" => attrs["position_x"] || 50.0,
      "position_y" => attrs["position_y"] || 50.0,
      "label" => attrs["label"] || dgettext("maps", "New Pin"),
      "pin_type" => attrs["pin_type"] || "location",
      "icon" => attrs["icon"],
      "color" => attrs["color"],
      "size" => attrs["size"],
      "tooltip" => attrs["tooltip"],
      "layer_id" => socket.assigns.active_layer_id
    }

    case Maps.create_pin(socket.assigns.map.id, pin_attrs) do
      {:ok, pin} ->
        {:noreply,
         socket
         |> assign(:pins, socket.assigns.pins ++ [pin])
         |> assign(:selected_type, "pin")
         |> assign(:selected_element, pin)
         |> push_event("pin_created", serialize_pin(pin))
         |> push_event("element_selected", %{type: "pin", id: pin.id})
         |> put_flash(:info, dgettext("maps", "Pin pasted."))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("maps", "Could not paste pin."))}
    end
  end

  defp do_create_zone_from_clipboard(socket, attrs) do
    zone_attrs = %{
      "name" => (attrs["name"] || dgettext("maps", "New Zone")) <> " (paste)",
      "vertices" => attrs["vertices"] || [],
      "fill_color" => attrs["fill_color"],
      "border_color" => attrs["border_color"],
      "border_width" => attrs["border_width"],
      "border_style" => attrs["border_style"],
      "opacity" => attrs["opacity"],
      "layer_id" => socket.assigns.active_layer_id
    }

    case Maps.create_zone(socket.assigns.map.id, zone_attrs) do
      {:ok, zone} ->
        {:noreply,
         socket
         |> assign(:zones, socket.assigns.zones ++ [zone])
         |> assign(:selected_type, "zone")
         |> assign(:selected_element, zone)
         |> push_event("zone_created", serialize_zone(zone))
         |> push_event("element_selected", %{type: "zone", id: zone.id})
         |> put_flash(:info, dgettext("maps", "Zone pasted."))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("maps", "Could not paste zone."))}
    end
  end

  defp do_create_annotation_from_clipboard(socket, attrs) do
    ann_attrs = %{
      "text" => attrs["text"] || dgettext("maps", "Note"),
      "position_x" => attrs["position_x"] || 50.0,
      "position_y" => attrs["position_y"] || 50.0,
      "font_size" => attrs["font_size"] || "md",
      "color" => attrs["color"],
      "layer_id" => socket.assigns.active_layer_id
    }

    case Maps.create_annotation(socket.assigns.map.id, ann_attrs) do
      {:ok, annotation} ->
        {:noreply,
         socket
         |> assign(:annotations, socket.assigns.annotations ++ [annotation])
         |> assign(:selected_type, "annotation")
         |> assign(:selected_element, annotation)
         |> push_event("annotation_created", serialize_annotation(annotation))
         |> push_event("element_selected", %{type: "annotation", id: annotation.id})
         |> put_flash(:info, dgettext("maps", "Annotation pasted."))}

      {:error, _} ->
        {:noreply,
         put_flash(socket, :error, dgettext("maps", "Could not paste annotation."))}
    end
  end

  defp reset_tool_to_select(socket) do
    socket
    |> assign(:active_tool, :select)
    |> push_event("tool_changed", %{tool: "select"})
  end
end
