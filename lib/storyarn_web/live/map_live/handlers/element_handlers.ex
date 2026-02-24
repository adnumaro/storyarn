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

  import StoryarnWeb.MapLive.Handlers.UndoRedoHandlers,
    only: [push_undo: 2, push_undo_coalesced: 2]

  # ---------------------------------------------------------------------------
  # Shared attr extraction (single source of truth for field lists)
  # ---------------------------------------------------------------------------

  @doc """
  Returns a string-keyed map of all copyable zone attributes.
  Used by duplicate, clipboard, paste, and undo/redo.
  """
  def zone_copyable_attrs(zone) do
    %{
      "name" => zone.name,
      "vertices" => zone.vertices,
      "fill_color" => zone.fill_color,
      "border_color" => zone.border_color,
      "border_width" => zone.border_width,
      "border_style" => zone.border_style,
      "opacity" => zone.opacity,
      "layer_id" => zone.layer_id,
      "tooltip" => zone.tooltip,
      "target_type" => zone.target_type,
      "target_id" => zone.target_id,
      "action_type" => zone.action_type,
      "action_data" => zone.action_data,
      "condition" => zone.condition,
      "condition_effect" => zone.condition_effect
    }
  end

  @doc """
  Returns a string-keyed map of all copyable pin attributes.
  Used by duplicate, clipboard, paste, and undo/redo.
  """
  def pin_copyable_attrs(pin) do
    %{
      "position_x" => pin.position_x,
      "position_y" => pin.position_y,
      "label" => pin.label,
      "pin_type" => pin.pin_type,
      "icon" => pin.icon,
      "color" => pin.color,
      "size" => pin.size,
      "tooltip" => pin.tooltip,
      "layer_id" => pin.layer_id,
      "opacity" => pin.opacity,
      "target_type" => pin.target_type,
      "target_id" => pin.target_id,
      "sheet_id" => pin.sheet_id,
      "icon_asset_id" => pin.icon_asset_id,
      "action_type" => pin.action_type,
      "action_data" => pin.action_data,
      "condition" => pin.condition,
      "condition_effect" => pin.condition_effect
    }
  end

  # ---------------------------------------------------------------------------
  # Pin handlers
  # ---------------------------------------------------------------------------

  @doc """
  Creates a new pin at the given canvas position on the active layer.
  """
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
         |> push_undo({:create_pin, pin})
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

  @doc "Moves a pin to new coordinates. Respects lock state."
  def handle_move_pin(%{"id" => pin_id, "position_x" => x, "position_y" => y}, socket) do
    case Maps.get_pin(socket.assigns.map.id, pin_id) do
      nil -> {:noreply, socket}
      pin -> do_move_pin(socket, pin, x, y)
    end
  end

  @doc "Opens the sheet picker modal for creating a pin from a sheet."
  def handle_show_sheet_picker(_params, socket) do
    {:noreply, assign(socket, :show_sheet_picker, true)}
  end

  @doc "Cancels the sheet picker without creating a pin."
  def handle_cancel_sheet_picker(_params, socket) do
    {:noreply,
     socket
     |> assign(show_sheet_picker: false, pending_sheet_for_pin: nil)
     |> push_event("pending_sheet_changed", %{active: false})}
  end

  @doc "Selects a sheet and switches to pin placement mode."
  def handle_start_pin_from_sheet(%{"sheet-id" => sheet_id}, socket) do
    raw_sheet = Storyarn.Sheets.get_sheet(socket.assigns.project.id, sheet_id)
    sheet = if raw_sheet, do: Maps.preload_sheet_avatar(raw_sheet), else: nil

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

  @doc "Places a character pin linked to the pending sheet at the given position."
  def handle_create_pin_from_sheet(%{"position_x" => x, "position_y" => y}, socket) do
    do_create_pin_from_sheet(socket, x, y)
  end

  @doc "Deletes a pin and its associated connections. Respects lock state."
  def handle_delete_pin(%{"id" => pin_id}, socket) do
    case Maps.get_pin(socket.assigns.map.id, pin_id) do
      nil -> {:noreply, socket}
      pin -> do_delete_pin(socket, pin)
    end
  end

  @doc "Updates a single field on a pin (e.g., label, color, size)."
  def handle_update_pin(%{"field" => field} = params, socket) do
    id = params["id"] || params["element_id"]

    case Maps.get_pin(socket.assigns.map.id, id) do
      nil -> {:noreply, socket}
      pin -> do_update_pin(socket, pin, field, extract_field_value(params, field))
    end
  end

  @doc "Marks a pin for pending confirmation-based deletion."
  def handle_set_pending_delete_pin(%{"id" => id}, socket) do
    {:noreply, assign(socket, :pending_delete_element, {:pin, parse_id(id)})}
  end

  @doc "Confirms and executes the pending element deletion (pin, zone, connection, or annotation)."
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

  @doc "Creates a polygon zone from the drawn vertices on the active layer."
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
         |> push_undo({:create_zone, zone})
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

  @doc "Updates a single field on a zone (e.g., name, color, opacity)."
  def handle_update_zone(%{"field" => field} = params, socket) do
    id = params["id"] || params["element_id"]

    case Maps.get_zone(socket.assigns.map.id, id) do
      nil -> {:noreply, socket}
      zone -> do_update_zone(socket, zone, field, extract_field_value(params, field))
    end
  end

  @doc "Updates the polygon vertices of a zone after user reshapes it."
  def handle_update_zone_vertices(%{"id" => id, "vertices" => vertices}, socket) do
    case Maps.get_zone(socket.assigns.map.id, id) do
      nil -> {:noreply, socket}
      zone -> do_update_zone_vertices(socket, zone, vertices)
    end
  end

  @doc "Duplicates a zone with shifted position and '(copy)' suffix."
  def handle_duplicate_zone(%{"id" => zone_id}, socket) do
    case Maps.get_zone(socket.assigns.map.id, zone_id) do
      nil -> {:noreply, socket}
      zone -> do_duplicate_zone(socket, zone)
    end
  end

  @doc "Deletes a zone. Respects lock state."
  def handle_delete_zone(%{"id" => zone_id}, socket) do
    case Maps.get_zone(socket.assigns.map.id, zone_id) do
      nil -> {:noreply, socket}
      zone -> do_delete_zone(socket, zone)
    end
  end

  @doc "Marks a zone for pending confirmation-based deletion."
  def handle_set_pending_delete_zone(%{"id" => id}, socket) do
    {:noreply, assign(socket, :pending_delete_element, {:zone, parse_id(id)})}
  end

  # ---------------------------------------------------------------------------
  # Zone action handlers (action_type + action_data)
  # ---------------------------------------------------------------------------

  @default_action_data %{
    "none" => %{},
    "instruction" => %{"assignments" => []},
    "display" => %{"variable_ref" => ""}
  }

  @doc "Changes a zone's action type (none, instruction, display) with default data."
  def handle_update_zone_action_type(%{"zone-id" => id, "action-type" => type}, socket) do
    case Maps.get_zone(socket.assigns.map.id, id) do
      nil ->
        {:noreply, socket}

      zone ->
        action_data = Map.get(@default_action_data, type, %{})

        do_update_zone_attrs(socket, zone, %{
          "action_type" => type,
          "action_data" => action_data
        })
    end
  end

  @doc "Updates instruction assignments for an instruction-type zone."
  def handle_update_zone_assignments(%{"zone-id" => id, "assignments" => assignments}, socket) do
    case Maps.get_zone(socket.assigns.map.id, id) do
      nil ->
        {:noreply, socket}

      zone ->
        new_data = Map.merge(zone.action_data || %{}, %{"assignments" => assignments})
        do_update_zone_attrs(socket, zone, %{"action_data" => new_data})
    end
  end

  @doc "Updates a single field in a zone's action_data (e.g., event_name, variable_ref)."
  def handle_update_zone_action_data(
        %{"zone-id" => id, "field" => field, "value" => value},
        socket
      ) do
    case Maps.get_zone(socket.assigns.map.id, id) do
      nil ->
        {:noreply, socket}

      zone ->
        new_data = Map.merge(zone.action_data || %{}, %{field => value})
        do_update_zone_attrs(socket, zone, %{"action_data" => new_data})
    end
  end

  # ---------------------------------------------------------------------------
  # Zone condition handlers
  # ---------------------------------------------------------------------------

  @doc "Updates a zone's visibility condition from the condition builder hook."
  def handle_update_zone_condition(%{"zone-id" => id, "condition" => condition_data}, socket) do
    case Maps.get_zone(socket.assigns.map.id, id) do
      nil -> {:noreply, socket}
      zone -> do_update_zone_attrs(socket, zone, %{"condition" => condition_data})
    end
  end

  def handle_update_zone_condition(_params, socket), do: {:noreply, socket}

  @doc "Updates a zone's condition_effect (hide or disable)."
  def handle_update_zone_condition_effect(%{"id" => id, "value" => value}, socket) do
    case Maps.get_zone(socket.assigns.map.id, id) do
      nil -> {:noreply, socket}
      zone -> do_update_zone_attrs(socket, zone, %{"condition_effect" => value})
    end
  end

  # ---------------------------------------------------------------------------
  # Pin action handlers (action_type + action_data)
  # ---------------------------------------------------------------------------

  @doc "Changes a pin's action type (none, instruction, display) with default data."
  def handle_update_pin_action_type(%{"pin-id" => id, "action-type" => type}, socket) do
    case Maps.get_pin(socket.assigns.map.id, id) do
      nil ->
        {:noreply, socket}

      pin ->
        action_data = Map.get(@default_action_data, type, %{})
        do_update_pin_attrs(socket, pin, %{"action_type" => type, "action_data" => action_data})
    end
  end

  @doc "Updates instruction assignments for an instruction-type pin."
  def handle_update_pin_assignments(%{"pin-id" => id, "assignments" => assignments}, socket) do
    case Maps.get_pin(socket.assigns.map.id, id) do
      nil ->
        {:noreply, socket}

      pin ->
        new_data = Map.merge(pin.action_data || %{}, %{"assignments" => assignments})
        do_update_pin_attrs(socket, pin, %{"action_data" => new_data})
    end
  end

  @doc "Updates a single field in a pin's action_data (e.g., variable_ref)."
  def handle_update_pin_action_data(
        %{"pin-id" => id, "field" => field, "value" => value},
        socket
      ) do
    case Maps.get_pin(socket.assigns.map.id, id) do
      nil ->
        {:noreply, socket}

      pin ->
        new_data = Map.merge(pin.action_data || %{}, %{field => value})
        do_update_pin_attrs(socket, pin, %{"action_data" => new_data})
    end
  end

  # ---------------------------------------------------------------------------
  # Pin condition handlers
  # ---------------------------------------------------------------------------

  @doc "Updates a pin's visibility condition from the condition builder hook."
  def handle_update_pin_condition(%{"pin-id" => id, "condition" => condition_data}, socket) do
    case Maps.get_pin(socket.assigns.map.id, id) do
      nil -> {:noreply, socket}
      pin -> do_update_pin_attrs(socket, pin, %{"condition" => condition_data})
    end
  end

  def handle_update_pin_condition(_params, socket), do: {:noreply, socket}

  @doc "Updates a pin's condition_effect (hide or disable)."
  def handle_update_pin_condition_effect(%{"id" => id, "value" => value}, socket) do
    case Maps.get_pin(socket.assigns.map.id, id) do
      nil -> {:noreply, socket}
      pin -> do_update_pin_attrs(socket, pin, %{"condition_effect" => value})
    end
  end

  # ---------------------------------------------------------------------------
  # Connection handlers
  # ---------------------------------------------------------------------------

  @doc "Creates a connection between two pins."
  def handle_create_connection(%{"from_pin_id" => from_pin_id, "to_pin_id" => to_pin_id}, socket) do
    attrs = %{
      "from_pin_id" => from_pin_id,
      "to_pin_id" => to_pin_id
    }

    case Maps.create_connection(socket.assigns.map.id, attrs) do
      {:ok, conn} ->
        {:noreply,
         socket
         |> push_undo({:create_connection, conn})
         |> assign(:connections, socket.assigns.connections ++ [conn])
         |> push_event("connection_created", serialize_connection(conn))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("maps", "Could not create connection."))}
    end
  end

  @doc "Updates a single field on a connection (e.g., label, color, style)."
  def handle_update_connection(%{"field" => field} = params, socket) do
    id = params["id"] || params["element_id"]

    case Maps.get_connection(socket.assigns.map.id, id) do
      nil -> {:noreply, socket}
      conn -> do_update_connection(socket, conn, field, extract_field_value(params, field))
    end
  end

  @doc "Updates the waypoint list for a connection path."
  def handle_update_connection_waypoints(%{"id" => id, "waypoints" => waypoints}, socket) do
    case Maps.get_connection(socket.assigns.map.id, id) do
      nil -> {:noreply, socket}
      conn -> do_update_connection_waypoints(socket, conn, waypoints)
    end
  end

  @doc "Clears all waypoints from a connection, resetting to direct path."
  def handle_clear_connection_waypoints(%{"id" => id}, socket) do
    case Maps.get_connection(socket.assigns.map.id, id) do
      nil -> {:noreply, socket}
      conn -> do_clear_connection_waypoints(socket, conn)
    end
  end

  @doc "Deletes a connection between two pins."
  def handle_delete_connection(%{"id" => connection_id}, socket) do
    case Maps.get_connection(socket.assigns.map.id, connection_id) do
      nil -> {:noreply, socket}
      connection -> do_delete_connection(socket, connection)
    end
  end

  @doc "Marks a connection for pending confirmation-based deletion."
  def handle_set_pending_delete_connection(%{"id" => id}, socket) do
    {:noreply, assign(socket, :pending_delete_element, {:connection, parse_id(id)})}
  end

  # ---------------------------------------------------------------------------
  # Annotation handlers
  # ---------------------------------------------------------------------------

  @doc "Creates a text annotation at the given canvas position."
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
         |> push_undo({:create_annotation, annotation})
         |> assign(:annotations, socket.assigns.annotations ++ [annotation])
         |> assign(:selected_type, "annotation")
         |> assign(:selected_element, annotation)
         |> push_event("annotation_created", serialize_annotation(annotation))
         |> push_event("element_selected", %{type: "annotation", id: annotation.id})
         |> push_event("focus_annotation_text", %{id: annotation.id})
         |> reset_tool_to_select()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("maps", "Could not create annotation."))}
    end
  end

  @doc "Updates a single field on an annotation (e.g., text, font_size, color)."
  def handle_update_annotation(%{"field" => field} = params, socket) do
    id = params["id"] || params["element_id"]
    value = params["value"] || params[field]

    case Maps.get_annotation(socket.assigns.map.id, id) do
      nil -> {:noreply, socket}
      annotation -> do_update_annotation(socket, annotation, field, value)
    end
  end

  @doc "Moves an annotation to new coordinates. Respects lock state."
  def handle_move_annotation(%{"id" => id, "position_x" => x, "position_y" => y}, socket) do
    case Maps.get_annotation(socket.assigns.map.id, id) do
      nil -> {:noreply, socket}
      annotation -> do_move_annotation(socket, annotation, x, y)
    end
  end

  @doc "Deletes an annotation. Respects lock state."
  def handle_delete_annotation(%{"id" => annotation_id}, socket) do
    case Maps.get_annotation(socket.assigns.map.id, annotation_id) do
      nil -> {:noreply, socket}
      annotation -> do_delete_annotation(socket, annotation)
    end
  end

  @doc "Marks an annotation for pending confirmation-based deletion."
  def handle_set_pending_delete_annotation(%{"id" => id}, socket) do
    {:noreply, assign(socket, :pending_delete_element, {:annotation, parse_id(id)})}
  end

  # ---------------------------------------------------------------------------
  # Keyboard shortcut handlers (delete / duplicate / copy / paste)
  # ---------------------------------------------------------------------------

  @doc "Deletes the currently selected element (keyboard shortcut handler)."
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

  @doc "Duplicates the currently selected element (keyboard shortcut handler)."
  def handle_duplicate_selected(socket) do
    case {socket.assigns.selected_type, socket.assigns.selected_element} do
      {nil, _} -> {:noreply, socket}
      {"pin", pin} -> do_duplicate_pin(socket, pin)
      {"zone", zone} -> do_duplicate_zone(socket, zone)
      {"annotation", ann} -> do_duplicate_annotation(socket, ann)
      _ -> {:noreply, socket}
    end
  end

  @doc "Copies the currently selected element to clipboard (keyboard shortcut handler)."
  def handle_copy_selected(socket) do
    case {socket.assigns.selected_type, socket.assigns.selected_element} do
      {nil, _} ->
        {:noreply, socket}

      {type, element} ->
        data = serialize_element_for_clipboard(type, element)
        {:noreply, push_event(socket, "element_copied", data)}
    end
  end

  @doc "Pastes an element from clipboard data with shifted position."
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

  defp do_create_pin_from_sheet(socket, _x, _y)
       when is_nil(socket.assigns.pending_sheet_for_pin) do
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
         |> push_undo({:create_pin, pin})
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
    prev = %{x: pin.position_x, y: pin.position_y}

    case Maps.move_pin(pin, x, y) do
      {:ok, _updated} ->
        {:noreply, push_undo_coalesced(socket, {:move_pin, pin.id, prev, %{x: x, y: y}})}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("maps", "Could not move pin."))}
    end
  end

  defp do_delete_pin(socket, %{locked: true}) do
    {:noreply, put_flash(socket, :error, dgettext("maps", "Cannot delete a locked element."))}
  end

  defp do_delete_pin(socket, pin) do
    affected_conns =
      Enum.filter(socket.assigns.connections, fn c ->
        c.from_pin_id == pin.id or c.to_pin_id == pin.id
      end)

    case Maps.delete_pin(pin) do
      {:ok, _} ->
        sub_actions = Enum.map(affected_conns, &{:delete_connection, &1}) ++ [{:delete_pin, pin}]

        action =
          if length(sub_actions) > 1, do: {:compound, sub_actions}, else: {:delete_pin, pin}

        {:noreply,
         socket
         |> push_undo(action)
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
    prev_value = Map.get(pin, String.to_existing_atom(field))

    case Maps.update_pin(pin, %{field => value}) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> push_undo({:update_pin, pin.id, %{field => prev_value}, %{field => value}})
         |> assign(:selected_element, updated)
         |> assign(:pins, replace_in_list(socket.assigns.pins, updated))
         |> push_event("pin_updated", serialize_pin(updated))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("maps", "Could not update pin."))}
    end
  end

  defp do_update_pin_attrs(socket, pin, new_attrs) do
    prev_attrs =
      Map.new(new_attrs, fn {key, _val} ->
        {key, Map.get(pin, String.to_existing_atom(key))}
      end)

    case Maps.update_pin(pin, new_attrs) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> push_undo({:update_pin, pin.id, prev_attrs, new_attrs})
         |> assign(:selected_element, updated)
         |> assign(:pins, replace_in_list(socket.assigns.pins, updated))
         |> push_event("pin_updated", serialize_pin(updated))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("maps", "Could not update pin."))}
    end
  end

  defp do_update_zone_vertices(socket, %{locked: true}, _vertices), do: {:noreply, socket}

  defp do_update_zone_vertices(socket, zone, vertices) do
    prev_vertices = zone.vertices

    case Maps.update_zone_vertices(zone, %{"vertices" => vertices}) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> push_undo({:update_zone_vertices, zone.id, prev_vertices, vertices})
         |> assign(:zones, replace_in_list(socket.assigns.zones, updated))
         |> maybe_update_selected_element("zone", updated)
         |> push_event("zone_vertices_updated", serialize_zone(updated))}

      {:error, changeset} ->
        msg = zone_error_message(changeset)
        {:noreply, put_flash(socket, :error, msg)}
    end
  end

  defp do_update_zone(socket, zone, field, value) do
    attrs = build_zone_update_attrs(zone, field, value)
    prev_attrs = Map.new(attrs, fn {k, _} -> {k, Map.get(zone, String.to_existing_atom(k))} end)

    case Maps.update_zone(zone, attrs) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> push_undo({:update_zone, zone.id, prev_attrs, attrs})
         |> assign(:selected_element, updated)
         |> assign(:zones, replace_in_list(socket.assigns.zones, updated))
         |> push_event("zone_updated", serialize_zone(updated))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("maps", "Could not update zone."))}
    end
  end

  defp build_zone_update_attrs(_zone, field, value), do: %{field => value}

  defp do_update_zone_attrs(socket, zone, new_attrs) do
    prev_attrs =
      Map.new(new_attrs, fn {key, _val} ->
        {key, Map.get(zone, String.to_existing_atom(key))}
      end)

    case Maps.update_zone(zone, new_attrs) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> push_undo({:update_zone, zone.id, prev_attrs, new_attrs})
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

    attrs =
      zone
      |> zone_copyable_attrs()
      |> Map.merge(%{"name" => zone.name <> " (copy)", "vertices" => shifted_vertices})

    case Maps.create_zone(socket.assigns.map.id, attrs) do
      {:ok, new_zone} ->
        {:noreply,
         socket
         |> push_undo({:create_zone, new_zone})
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
    prev_value = Map.get(conn, String.to_existing_atom(field))

    case Maps.update_connection(conn, %{field => value}) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> push_undo({:update_connection, conn.id, %{field => prev_value}, %{field => value}})
         |> assign(:selected_element, updated)
         |> assign(:connections, replace_in_list(socket.assigns.connections, updated))
         |> push_event("connection_updated", serialize_connection(updated))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("maps", "Could not update connection."))}
    end
  end

  defp do_update_connection_waypoints(socket, conn, waypoints) do
    prev_waypoints = conn.waypoints || []

    case Maps.update_connection_waypoints(conn, %{"waypoints" => waypoints}) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> push_undo({:update_connection_waypoints, conn.id, prev_waypoints, waypoints})
         |> assign(:selected_element, updated)
         |> push_event("connection_updated", serialize_connection(updated))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("maps", "Could not update waypoints."))}
    end
  end

  defp do_clear_connection_waypoints(socket, conn) do
    prev_waypoints = conn.waypoints || []

    case Maps.update_connection_waypoints(conn, %{"waypoints" => []}) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> push_undo({:update_connection_waypoints, conn.id, prev_waypoints, []})
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
    prev_value = Map.get(annotation, String.to_existing_atom(field))

    case Maps.update_annotation(annotation, %{field => value}) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> push_undo(
           {:update_annotation, annotation.id, %{field => prev_value}, %{field => value}}
         )
         |> assign(:annotations, replace_in_list(socket.assigns.annotations, updated))
         |> maybe_update_selected_element("annotation", updated)
         |> push_event("annotation_updated", serialize_annotation(updated))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("maps", "Could not update annotation."))}
    end
  end

  defp do_move_annotation(socket, %{locked: true}, _x, _y), do: {:noreply, socket}

  defp do_move_annotation(socket, annotation, x, y) do
    prev = %{x: annotation.position_x, y: annotation.position_y}

    case Maps.move_annotation(annotation, x, y) do
      {:ok, _updated} ->
        {:noreply,
         push_undo_coalesced(socket, {:move_annotation, annotation.id, prev, %{x: x, y: y}})}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("maps", "Could not move annotation."))}
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
         |> assign(
           :annotations,
           Enum.reject(socket.assigns.annotations, &(&1.id == annotation.id))
         )
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
    attrs =
      pin
      |> pin_copyable_attrs()
      |> Map.merge(%{
        "position_x" => min(pin.position_x + 5, 100.0),
        "position_y" => min(pin.position_y + 5, 100.0),
        "label" => pin.label <> " (copy)"
      })

    case Maps.create_pin(socket.assigns.map.id, attrs) do
      {:ok, new_pin} ->
        {:noreply,
         socket
         |> push_undo({:create_pin, new_pin})
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
         |> push_undo({:create_annotation, new_ann})
         |> assign(:annotations, socket.assigns.annotations ++ [new_ann])
         |> assign(:selected_type, "annotation")
         |> assign(:selected_element, new_ann)
         |> push_event("annotation_created", serialize_annotation(new_ann))
         |> push_event("element_selected", %{type: "annotation", id: new_ann.id})
         |> put_flash(:info, dgettext("maps", "Annotation duplicated."))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("maps", "Could not duplicate annotation."))}
    end
  end

  # ---------------------------------------------------------------------------
  # Clipboard serialization & paste helpers
  # ---------------------------------------------------------------------------

  defp serialize_element_for_clipboard("pin", pin) do
    %{
      type: "pin",
      attrs: Map.new(pin_copyable_attrs(pin), fn {k, v} -> {String.to_existing_atom(k), v} end)
    }
  end

  defp serialize_element_for_clipboard("zone", zone) do
    %{
      type: "zone",
      attrs: Map.new(zone_copyable_attrs(zone), fn {k, v} -> {String.to_existing_atom(k), v} end)
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
    pin_attrs =
      Map.merge(attrs, %{
        "position_x" => attrs["position_x"] || 50.0,
        "position_y" => attrs["position_y"] || 50.0,
        "label" => attrs["label"] || dgettext("maps", "New Pin"),
        "pin_type" => attrs["pin_type"] || "location",
        "layer_id" => socket.assigns.active_layer_id
      })

    case Maps.create_pin(socket.assigns.map.id, pin_attrs) do
      {:ok, pin} ->
        {:noreply,
         socket
         |> push_undo({:create_pin, pin})
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
    zone_attrs =
      Map.merge(attrs, %{
        "name" => (attrs["name"] || dgettext("maps", "New Zone")) <> " (paste)",
        "vertices" => attrs["vertices"] || [],
        "layer_id" => socket.assigns.active_layer_id
      })

    case Maps.create_zone(socket.assigns.map.id, zone_attrs) do
      {:ok, zone} ->
        {:noreply,
         socket
         |> push_undo({:create_zone, zone})
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
         |> push_undo({:create_annotation, annotation})
         |> assign(:annotations, socket.assigns.annotations ++ [annotation])
         |> assign(:selected_type, "annotation")
         |> assign(:selected_element, annotation)
         |> push_event("annotation_created", serialize_annotation(annotation))
         |> push_event("element_selected", %{type: "annotation", id: annotation.id})
         |> put_flash(:info, dgettext("maps", "Annotation pasted."))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("maps", "Could not paste annotation."))}
    end
  end

  defp reset_tool_to_select(socket) do
    socket
    |> assign(:active_tool, :select)
    |> push_event("tool_changed", %{tool: "select"})
  end
end
