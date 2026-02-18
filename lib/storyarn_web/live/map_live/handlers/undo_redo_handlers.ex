defmodule StoryarnWeb.MapLive.Handlers.UndoRedoHandlers do
  @moduledoc """
  Undo/redo handlers for the map LiveView.
  """

  import Phoenix.Component, only: [assign: 2, assign: 3]
  import Phoenix.LiveView, only: [push_event: 3, put_flash: 3]
  use StoryarnWeb, :verified_routes
  use Gettext, backend: StoryarnWeb.Gettext

  alias Storyarn.Maps
  import StoryarnWeb.MapLive.Helpers.Serializer

  @max_undo 50

  def handle_undo(_params, socket) do
    case socket.assigns.undo_stack do
      [] ->
        {:noreply, socket}

      [action | rest] ->
        case undo_action(action, socket) do
          {:ok, socket, recreated} ->
            {type, _} = action
            redo_action_item = {type, recreated}

            {:noreply,
             socket
             |> assign(:undo_stack, rest)
             |> push_redo(redo_action_item)
             |> reload_map()}

          {:error, socket} ->
            {:noreply, assign(socket, :undo_stack, rest)}
        end
    end
  end

  def handle_redo(_params, socket) do
    case socket.assigns.redo_stack do
      [] ->
        {:noreply, socket}

      [action | rest] ->
        case redo_action(action, socket) do
          {:ok, socket} ->
            {:noreply,
             socket
             |> assign(:redo_stack, rest)
             |> push_undo_no_clear(action)
             |> reload_map()}

          {:error, socket} ->
            {:noreply, assign(socket, :redo_stack, rest)}
        end
    end
  end

  def push_undo(socket, action) do
    stack = Enum.take([action | socket.assigns.undo_stack], @max_undo)
    assign(socket, undo_stack: stack, redo_stack: [])
  end

  def push_undo_no_clear(socket, action) do
    stack = Enum.take([action | socket.assigns.undo_stack], @max_undo)
    assign(socket, :undo_stack, stack)
  end

  def push_redo(socket, action) do
    stack = Enum.take([action | socket.assigns.redo_stack], @max_undo)
    assign(socket, :redo_stack, stack)
  end

  # Undo: re-create the deleted element
  # Returns {:ok, socket, recreated_element} so the redo stack stores the actual new element
  defp undo_action({:delete_pin, pin}, socket) do
    attrs = %{
      "position_x" => pin.position_x,
      "position_y" => pin.position_y,
      "label" => pin.label,
      "pin_type" => pin.pin_type,
      "color" => pin.color,
      "icon" => pin.icon,
      "size" => pin.size,
      "tooltip" => pin.tooltip,
      "layer_id" => pin.layer_id,
      "sheet_id" => pin.sheet_id,
      "target_type" => pin.target_type,
      "target_id" => pin.target_id
    }

    case Maps.create_pin(socket.assigns.map.id, attrs) do
      {:ok, new_pin} ->
        {:ok,
         socket
         |> assign(:pins, socket.assigns.pins ++ [new_pin])
         |> push_event("pin_created", serialize_pin(new_pin))
         |> put_flash(:info, dgettext("maps", "Undo: pin restored.")),
         new_pin}

      {:error, _} ->
        {:error, put_flash(socket, :error, dgettext("maps", "Could not undo."))}
    end
  end

  defp undo_action({:delete_zone, zone}, socket) do
    attrs = %{
      "name" => zone.name,
      "vertices" => zone.vertices,
      "fill_color" => zone.fill_color,
      "border_color" => zone.border_color,
      "border_width" => zone.border_width,
      "border_style" => zone.border_style,
      "opacity" => zone.opacity,
      "tooltip" => zone.tooltip,
      "layer_id" => zone.layer_id,
      "target_type" => zone.target_type,
      "target_id" => zone.target_id
    }

    case Maps.create_zone(socket.assigns.map.id, attrs) do
      {:ok, new_zone} ->
        {:ok,
         socket
         |> assign(:zones, socket.assigns.zones ++ [new_zone])
         |> push_event("zone_created", serialize_zone(new_zone))
         |> put_flash(:info, dgettext("maps", "Undo: zone restored.")),
         new_zone}

      {:error, _} ->
        {:error, put_flash(socket, :error, dgettext("maps", "Could not undo."))}
    end
  end

  defp undo_action({:delete_connection, conn}, socket) do
    attrs = %{
      "from_pin_id" => conn.from_pin_id,
      "to_pin_id" => conn.to_pin_id,
      "line_style" => conn.line_style,
      "color" => conn.color,
      "label" => conn.label,
      "bidirectional" => conn.bidirectional,
      "waypoints" => conn.waypoints || []
    }

    case Maps.create_connection(socket.assigns.map.id, attrs) do
      {:ok, new_conn} ->
        {:ok,
         socket
         |> assign(:connections, socket.assigns.connections ++ [new_conn])
         |> push_event("connection_created", serialize_connection(new_conn))
         |> put_flash(:info, dgettext("maps", "Undo: connection restored.")),
         new_conn}

      {:error, _} ->
        {:error, put_flash(socket, :error, dgettext("maps", "Could not undo."))}
    end
  end

  defp undo_action({:delete_annotation, annotation}, socket) do
    attrs = %{
      "text" => annotation.text,
      "position_x" => annotation.position_x,
      "position_y" => annotation.position_y,
      "font_size" => annotation.font_size,
      "color" => annotation.color,
      "layer_id" => annotation.layer_id
    }

    case Maps.create_annotation(socket.assigns.map.id, attrs) do
      {:ok, new_ann} ->
        {:ok,
         socket
         |> assign(:annotations, socket.assigns.annotations ++ [new_ann])
         |> push_event("annotation_created", serialize_annotation(new_ann))
         |> put_flash(:info, dgettext("maps", "Undo: annotation restored.")),
         new_ann}

      {:error, _} ->
        {:error, put_flash(socket, :error, dgettext("maps", "Could not undo."))}
    end
  end

  # Redo: re-delete the element using the recreated element stored by undo
  defp redo_action({:delete_pin, pin}, socket) do
    case Enum.find(socket.assigns.pins, &(&1.id == pin.id)) do
      nil ->
        {:error, socket}

      found ->
        case Maps.delete_pin(found) do
          {:ok, _} ->
            {:ok,
             socket
             |> assign(:pins, Enum.reject(socket.assigns.pins, &(&1.id == found.id)))
             |> assign(:selected_element, nil)
             |> assign(:selected_type, nil)
             |> push_event("pin_deleted", %{id: found.id})}

          {:error, _} ->
            {:error, socket}
        end
    end
  end

  defp redo_action({:delete_zone, zone}, socket) do
    case Enum.find(socket.assigns.zones, &(&1.id == zone.id)) do
      nil ->
        {:error, socket}

      found ->
        case Maps.delete_zone(found) do
          {:ok, _} ->
            {:ok,
             socket
             |> assign(:zones, Enum.reject(socket.assigns.zones, &(&1.id == found.id)))
             |> assign(:selected_element, nil)
             |> assign(:selected_type, nil)
             |> push_event("zone_deleted", %{id: found.id})}

          {:error, _} ->
            {:error, socket}
        end
    end
  end

  defp redo_action({:delete_connection, conn}, socket) do
    case Enum.find(socket.assigns.connections, &(&1.id == conn.id)) do
      nil ->
        {:error, socket}

      found ->
        case Maps.delete_connection(found) do
          {:ok, _} ->
            {:ok,
             socket
             |> assign(:connections, Enum.reject(socket.assigns.connections, &(&1.id == found.id)))
             |> assign(:selected_element, nil)
             |> assign(:selected_type, nil)
             |> push_event("connection_deleted", %{id: found.id})}

          {:error, _} ->
            {:error, socket}
        end
    end
  end

  defp redo_action({:delete_annotation, ann}, socket) do
    case Enum.find(socket.assigns.annotations, &(&1.id == ann.id)) do
      nil ->
        {:error, socket}

      found ->
        case Maps.delete_annotation(found) do
          {:ok, _} ->
            {:ok,
             socket
             |> assign(:annotations, Enum.reject(socket.assigns.annotations, &(&1.id == found.id)))
             |> assign(:selected_element, nil)
             |> assign(:selected_type, nil)
             |> push_event("annotation_deleted", %{id: found.id})}

          {:error, _} ->
            {:error, socket}
        end
    end
  end
end
