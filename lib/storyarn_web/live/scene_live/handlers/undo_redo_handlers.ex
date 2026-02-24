defmodule StoryarnWeb.SceneLive.Handlers.UndoRedoHandlers do
  @moduledoc """
  Undo/redo handlers for the scene LiveView.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3, put_flash: 3]
  use StoryarnWeb, :verified_routes
  use Gettext, backend: StoryarnWeb.Gettext

  alias Storyarn.Scenes
  alias StoryarnWeb.Helpers.UndoRedoStack
  alias StoryarnWeb.SceneLive.Handlers.ElementHandlers
  import StoryarnWeb.SceneLive.Helpers.Serializer

  import StoryarnWeb.SceneLive.Helpers.SceneHelpers,
    only: [replace_in_list: 2, maybe_update_selected_element: 3]

  # ---------------------------------------------------------------------------
  # Public dispatch
  # ---------------------------------------------------------------------------

  def handle_undo(_params, socket) do
    case UndoRedoStack.pop_undo(socket) do
      :empty ->
        {:noreply, socket}

      {action, socket} ->
        case undo_action(action, socket) do
          {:ok, socket, redo_item} ->
            {:noreply,
             socket
             |> UndoRedoStack.push_redo(redo_item)
             |> reload_scene()}

          {:error, socket} ->
            {:noreply, socket}
        end
    end
  end

  def handle_redo(_params, socket) do
    case UndoRedoStack.pop_redo(socket) do
      :empty ->
        {:noreply, socket}

      {action, socket} ->
        case redo_action(action, socket) do
          {:ok, socket, undo_item} ->
            {:noreply,
             socket
             |> UndoRedoStack.push_undo_no_clear(undo_item)
             |> reload_scene()}

          {:error, socket} ->
            {:noreply, socket}
        end
    end
  end

  # ---------------------------------------------------------------------------
  # Stack operations (delegate to shared module, keep local API for callers)
  # ---------------------------------------------------------------------------

  def push_undo(socket, action), do: UndoRedoStack.push_undo(socket, action)

  def push_undo_no_clear(socket, action), do: UndoRedoStack.push_undo_no_clear(socket, action)

  def push_redo(socket, action), do: UndoRedoStack.push_redo(socket, action)

  def push_undo_coalesced(socket, {:move_pin, pin_id, prev, new}) do
    UndoRedoStack.push_coalesced(
      socket,
      {:move_pin, pin_id, prev, new},
      fn
        {:move_pin, ^pin_id, _, _} -> true
        _ -> false
      end,
      fn {:move_pin, ^pin_id, original_prev, _} ->
        {:move_pin, pin_id, original_prev, new}
      end
    )
  end

  def push_undo_coalesced(socket, {:move_annotation, ann_id, prev, new}) do
    UndoRedoStack.push_coalesced(
      socket,
      {:move_annotation, ann_id, prev, new},
      fn
        {:move_annotation, ^ann_id, _, _} -> true
        _ -> false
      end,
      fn {:move_annotation, ^ann_id, original_prev, _} ->
        {:move_annotation, ann_id, original_prev, new}
      end
    )
  end

  # ---------------------------------------------------------------------------
  # Attr extraction helpers (DRY — used by both undo and redo of creates/deletes)
  # ---------------------------------------------------------------------------

  defp pin_to_attrs(pin) do
    Map.put(ElementHandlers.pin_copyable_attrs(pin), "locked", pin.locked)
  end

  defp zone_to_attrs(zone) do
    Map.put(ElementHandlers.zone_copyable_attrs(zone), "locked", zone.locked)
  end

  defp connection_to_attrs(conn) do
    %{
      "from_pin_id" => conn.from_pin_id,
      "to_pin_id" => conn.to_pin_id,
      "line_style" => conn.line_style,
      "line_width" => conn.line_width,
      "color" => conn.color,
      "label" => conn.label,
      "bidirectional" => conn.bidirectional,
      "show_label" => conn.show_label,
      "waypoints" => conn.waypoints || []
    }
  end

  defp annotation_to_attrs(annotation) do
    %{
      "text" => annotation.text,
      "position_x" => annotation.position_x,
      "position_y" => annotation.position_y,
      "font_size" => annotation.font_size,
      "color" => annotation.color,
      "layer_id" => annotation.layer_id,
      "locked" => annotation.locked
    }
  end

  defp layer_to_attrs(layer) do
    %{
      "name" => layer.name,
      "visible" => layer.visible,
      "fog_enabled" => layer.fog_enabled,
      "fog_color" => layer.fog_color,
      "fog_opacity" => layer.fog_opacity
    }
  end

  # ---------------------------------------------------------------------------
  # Undo: delete actions (re-create the deleted element)
  # ---------------------------------------------------------------------------

  defp undo_action({:delete_pin, pin}, socket) do
    case Scenes.create_pin(socket.assigns.scene.id, pin_to_attrs(pin)) do
      {:ok, new_pin} ->
        {:ok,
         socket
         |> assign(:pins, socket.assigns.pins ++ [new_pin])
         |> push_event("pin_created", serialize_pin(new_pin))
         |> put_flash(:info, dgettext("scenes", "Undo: pin restored.")), {:delete_pin, new_pin}}

      {:error, _} ->
        {:error, put_flash(socket, :error, dgettext("scenes", "Could not undo."))}
    end
  end

  defp undo_action({:delete_zone, zone}, socket) do
    case Scenes.create_zone(socket.assigns.scene.id, zone_to_attrs(zone)) do
      {:ok, new_zone} ->
        {:ok,
         socket
         |> assign(:zones, socket.assigns.zones ++ [new_zone])
         |> push_event("zone_created", serialize_zone(new_zone))
         |> put_flash(:info, dgettext("scenes", "Undo: zone restored.")),
         {:delete_zone, new_zone}}

      {:error, _} ->
        {:error, put_flash(socket, :error, dgettext("scenes", "Could not undo."))}
    end
  end

  defp undo_action({:delete_connection, conn}, socket) do
    case Scenes.create_connection(socket.assigns.scene.id, connection_to_attrs(conn)) do
      {:ok, new_conn} ->
        {:ok,
         socket
         |> assign(:connections, socket.assigns.connections ++ [new_conn])
         |> push_event("connection_created", serialize_connection(new_conn))
         |> put_flash(:info, dgettext("scenes", "Undo: connection restored.")),
         {:delete_connection, new_conn}}

      {:error, _} ->
        {:error, put_flash(socket, :error, dgettext("scenes", "Could not undo."))}
    end
  end

  defp undo_action({:delete_annotation, annotation}, socket) do
    case Scenes.create_annotation(socket.assigns.scene.id, annotation_to_attrs(annotation)) do
      {:ok, new_ann} ->
        {:ok,
         socket
         |> assign(:annotations, socket.assigns.annotations ++ [new_ann])
         |> push_event("annotation_created", serialize_annotation(new_ann))
         |> put_flash(:info, dgettext("scenes", "Undo: annotation restored.")),
         {:delete_annotation, new_ann}}

      {:error, _} ->
        {:error, put_flash(socket, :error, dgettext("scenes", "Could not undo."))}
    end
  end

  # ---------------------------------------------------------------------------
  # Undo: move actions (restore previous position)
  # ---------------------------------------------------------------------------

  defp undo_action({:move_pin, pin_id, prev, new}, socket) do
    case Scenes.get_pin(socket.assigns.scene.id, pin_id) do
      nil ->
        {:error, socket}

      pin ->
        case Scenes.move_pin(pin, prev.x, prev.y) do
          {:ok, _} -> {:ok, socket, {:move_pin, pin_id, prev, new}}
          {:error, _} -> {:error, socket}
        end
    end
  end

  defp undo_action({:move_annotation, ann_id, prev, new}, socket) do
    case Scenes.get_annotation(socket.assigns.scene.id, ann_id) do
      nil ->
        {:error, socket}

      ann ->
        case Scenes.move_annotation(ann, prev.x, prev.y) do
          {:ok, _} -> {:ok, socket, {:move_annotation, ann_id, prev, new}}
          {:error, _} -> {:error, socket}
        end
    end
  end

  # ---------------------------------------------------------------------------
  # Undo: create actions (delete the created element)
  # ---------------------------------------------------------------------------

  defp undo_action({:create_pin, pin}, socket) do
    case Enum.find(socket.assigns.pins, &(&1.id == pin.id)) do
      nil ->
        {:error, socket}

      found ->
        case Scenes.delete_pin(found) do
          {:ok, _} ->
            {:ok,
             socket
             |> assign(:pins, Enum.reject(socket.assigns.pins, &(&1.id == found.id)))
             |> assign(:selected_element, nil)
             |> assign(:selected_type, nil)
             |> push_event("pin_deleted", %{id: found.id})
             |> put_flash(:info, dgettext("scenes", "Undo: pin creation reverted.")),
             {:create_pin, found}}

          {:error, _} ->
            {:error, socket}
        end
    end
  end

  defp undo_action({:create_zone, zone}, socket) do
    case Enum.find(socket.assigns.zones, &(&1.id == zone.id)) do
      nil ->
        {:error, socket}

      found ->
        case Scenes.delete_zone(found) do
          {:ok, _} ->
            {:ok,
             socket
             |> assign(:zones, Enum.reject(socket.assigns.zones, &(&1.id == found.id)))
             |> assign(:selected_element, nil)
             |> assign(:selected_type, nil)
             |> push_event("zone_deleted", %{id: found.id})
             |> put_flash(:info, dgettext("scenes", "Undo: zone creation reverted.")),
             {:create_zone, found}}

          {:error, _} ->
            {:error, socket}
        end
    end
  end

  defp undo_action({:create_connection, conn}, socket) do
    case Enum.find(socket.assigns.connections, &(&1.id == conn.id)) do
      nil ->
        {:error, socket}

      found ->
        case Scenes.delete_connection(found) do
          {:ok, _} ->
            {:ok,
             socket
             |> assign(
               :connections,
               Enum.reject(socket.assigns.connections, &(&1.id == found.id))
             )
             |> assign(:selected_element, nil)
             |> assign(:selected_type, nil)
             |> push_event("connection_deleted", %{id: found.id})
             |> put_flash(:info, dgettext("scenes", "Undo: connection creation reverted.")),
             {:create_connection, found}}

          {:error, _} ->
            {:error, socket}
        end
    end
  end

  defp undo_action({:create_annotation, annotation}, socket) do
    case Enum.find(socket.assigns.annotations, &(&1.id == annotation.id)) do
      nil ->
        {:error, socket}

      found ->
        case Scenes.delete_annotation(found) do
          {:ok, _} ->
            {:ok,
             socket
             |> assign(
               :annotations,
               Enum.reject(socket.assigns.annotations, &(&1.id == found.id))
             )
             |> assign(:selected_element, nil)
             |> assign(:selected_type, nil)
             |> push_event("annotation_deleted", %{id: found.id})
             |> put_flash(:info, dgettext("scenes", "Undo: annotation creation reverted.")),
             {:create_annotation, found}}

          {:error, _} ->
            {:error, socket}
        end
    end
  end

  # ---------------------------------------------------------------------------
  # Undo: update actions (restore previous values)
  # ---------------------------------------------------------------------------

  defp undo_action({:update_pin, pin_id, prev_attrs, new_attrs}, socket) do
    case Scenes.get_pin(socket.assigns.scene.id, pin_id) do
      nil ->
        {:error, socket}

      pin ->
        case Scenes.update_pin(pin, prev_attrs) do
          {:ok, updated} ->
            {:ok,
             socket
             |> assign(:pins, replace_in_list(socket.assigns.pins, updated))
             |> maybe_update_selected_element("pin", updated)
             |> push_event("pin_updated", serialize_pin(updated)),
             {:update_pin, pin_id, prev_attrs, new_attrs}}

          {:error, _} ->
            {:error, socket}
        end
    end
  end

  defp undo_action({:update_zone, zone_id, prev_attrs, new_attrs}, socket) do
    case Scenes.get_zone(socket.assigns.scene.id, zone_id) do
      nil ->
        {:error, socket}

      zone ->
        case Scenes.update_zone(zone, prev_attrs) do
          {:ok, updated} ->
            {:ok,
             socket
             |> assign(:zones, replace_in_list(socket.assigns.zones, updated))
             |> maybe_update_selected_element("zone", updated)
             |> push_event("zone_updated", serialize_zone(updated)),
             {:update_zone, zone_id, prev_attrs, new_attrs}}

          {:error, _} ->
            {:error, socket}
        end
    end
  end

  defp undo_action({:update_zone_vertices, zone_id, prev_vertices, new_vertices}, socket) do
    case Scenes.get_zone(socket.assigns.scene.id, zone_id) do
      nil ->
        {:error, socket}

      zone ->
        case Scenes.update_zone_vertices(zone, %{"vertices" => prev_vertices}) do
          {:ok, updated} ->
            {:ok,
             socket
             |> assign(:zones, replace_in_list(socket.assigns.zones, updated))
             |> maybe_update_selected_element("zone", updated)
             |> push_event("zone_vertices_updated", serialize_zone(updated)),
             {:update_zone_vertices, zone_id, prev_vertices, new_vertices}}

          {:error, _} ->
            {:error, socket}
        end
    end
  end

  defp undo_action({:update_connection, conn_id, prev_attrs, new_attrs}, socket) do
    case Scenes.get_connection(socket.assigns.scene.id, conn_id) do
      nil ->
        {:error, socket}

      conn ->
        case Scenes.update_connection(conn, prev_attrs) do
          {:ok, updated} ->
            {:ok,
             socket
             |> assign(:connections, replace_in_list(socket.assigns.connections, updated))
             |> maybe_update_selected_element("connection", updated)
             |> push_event("connection_updated", serialize_connection(updated)),
             {:update_connection, conn_id, prev_attrs, new_attrs}}

          {:error, _} ->
            {:error, socket}
        end
    end
  end

  defp undo_action({:update_connection_waypoints, conn_id, prev_waypoints, new_waypoints}, socket) do
    case Scenes.get_connection(socket.assigns.scene.id, conn_id) do
      nil ->
        {:error, socket}

      conn ->
        case Scenes.update_connection_waypoints(conn, %{"waypoints" => prev_waypoints}) do
          {:ok, updated} ->
            {:ok,
             socket
             |> assign(:connections, replace_in_list(socket.assigns.connections, updated))
             |> maybe_update_selected_element("connection", updated)
             |> push_event("connection_updated", serialize_connection(updated)),
             {:update_connection_waypoints, conn_id, prev_waypoints, new_waypoints}}

          {:error, _} ->
            {:error, socket}
        end
    end
  end

  defp undo_action({:update_annotation, ann_id, prev_attrs, new_attrs}, socket) do
    case Scenes.get_annotation(socket.assigns.scene.id, ann_id) do
      nil ->
        {:error, socket}

      ann ->
        case Scenes.update_annotation(ann, prev_attrs) do
          {:ok, updated} ->
            {:ok,
             socket
             |> assign(:annotations, replace_in_list(socket.assigns.annotations, updated))
             |> maybe_update_selected_element("annotation", updated)
             |> push_event("annotation_updated", serialize_annotation(updated)),
             {:update_annotation, ann_id, prev_attrs, new_attrs}}

          {:error, _} ->
            {:error, socket}
        end
    end
  end

  # ---------------------------------------------------------------------------
  # Undo: layer actions
  # ---------------------------------------------------------------------------

  defp undo_action({:create_layer, layer}, socket) do
    case Scenes.get_layer(socket.assigns.scene.id, layer.id) do
      nil ->
        {:error, socket}

      found ->
        case Scenes.delete_layer(found) do
          {:ok, _} ->
            {:ok,
             socket
             |> push_event("layer_deleted", %{id: found.id})
             |> put_flash(:info, dgettext("scenes", "Undo: layer creation reverted.")),
             {:create_layer, found}}

          {:error, _} ->
            {:error, socket}
        end
    end
  end

  defp undo_action({:delete_layer, layer}, socket) do
    case Scenes.create_layer(socket.assigns.scene.id, layer_to_attrs(layer)) do
      {:ok, new_layer} ->
        {:ok,
         socket
         |> push_event("layer_created", %{id: new_layer.id, name: new_layer.name})
         |> put_flash(:info, dgettext("scenes", "Undo: layer restored.")),
         {:delete_layer, new_layer}}

      {:error, _} ->
        {:error, put_flash(socket, :error, dgettext("scenes", "Could not undo."))}
    end
  end

  defp undo_action({:rename_layer, layer_id, prev_name, new_name}, socket) do
    case Scenes.get_layer(socket.assigns.scene.id, layer_id) do
      nil ->
        {:error, socket}

      layer ->
        case Scenes.update_layer(layer, %{"name" => prev_name}) do
          {:ok, _} -> {:ok, socket, {:rename_layer, layer_id, prev_name, new_name}}
          {:error, _} -> {:error, socket}
        end
    end
  end

  defp undo_action({:update_layer_fog, layer_id, prev_attrs, new_attrs}, socket) do
    case Scenes.get_layer(socket.assigns.scene.id, layer_id) do
      nil ->
        {:error, socket}

      layer ->
        case Scenes.update_layer(layer, prev_attrs) do
          {:ok, updated} ->
            {:ok,
             socket
             |> push_event("layer_fog_changed", %{
               id: updated.id,
               fog_enabled: updated.fog_enabled,
               fog_color: updated.fog_color,
               fog_opacity: updated.fog_opacity
             }), {:update_layer_fog, layer_id, prev_attrs, new_attrs}}

          {:error, _} ->
            {:error, socket}
        end
    end
  end

  # ---------------------------------------------------------------------------
  # Undo: compound actions
  # ---------------------------------------------------------------------------

  defp undo_action({:compound, actions}, socket) do
    result =
      actions
      |> Enum.reverse()
      |> Enum.reduce_while({:ok, socket, [], %{}}, fn action, {:ok, sock, redo_items, id_map} ->
        rebased = rebase_ids(action, id_map)

        case undo_action(rebased, sock) do
          {:ok, sock, redo_item} ->
            new_id_map = track_rebased_id(action, redo_item, id_map)
            {:cont, {:ok, sock, [redo_item | redo_items], new_id_map}}

          {:error, sock} ->
            {:halt, {:error, sock}}
        end
      end)

    case result do
      {:ok, socket, redo_items, _} -> {:ok, socket, {:compound, redo_items}}
      {:error, socket} -> {:error, socket}
    end
  end

  # ---------------------------------------------------------------------------
  # Redo: delete actions (re-delete the restored element)
  # ---------------------------------------------------------------------------

  defp redo_action({:delete_pin, pin}, socket) do
    case Enum.find(socket.assigns.pins, &(&1.id == pin.id)) do
      nil ->
        {:error, socket}

      found ->
        case Scenes.delete_pin(found) do
          {:ok, _} ->
            {:ok,
             socket
             |> assign(:pins, Enum.reject(socket.assigns.pins, &(&1.id == found.id)))
             |> assign(:selected_element, nil)
             |> assign(:selected_type, nil)
             |> push_event("pin_deleted", %{id: found.id}), {:delete_pin, found}}

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
        case Scenes.delete_zone(found) do
          {:ok, _} ->
            {:ok,
             socket
             |> assign(:zones, Enum.reject(socket.assigns.zones, &(&1.id == found.id)))
             |> assign(:selected_element, nil)
             |> assign(:selected_type, nil)
             |> push_event("zone_deleted", %{id: found.id}), {:delete_zone, found}}

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
        case Scenes.delete_connection(found) do
          {:ok, _} ->
            {:ok,
             socket
             |> assign(
               :connections,
               Enum.reject(socket.assigns.connections, &(&1.id == found.id))
             )
             |> assign(:selected_element, nil)
             |> assign(:selected_type, nil)
             |> push_event("connection_deleted", %{id: found.id}), {:delete_connection, found}}

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
        case Scenes.delete_annotation(found) do
          {:ok, _} ->
            {:ok,
             socket
             |> assign(
               :annotations,
               Enum.reject(socket.assigns.annotations, &(&1.id == found.id))
             )
             |> assign(:selected_element, nil)
             |> assign(:selected_type, nil)
             |> push_event("annotation_deleted", %{id: found.id}), {:delete_annotation, found}}

          {:error, _} ->
            {:error, socket}
        end
    end
  end

  # ---------------------------------------------------------------------------
  # Redo: move actions (re-apply the move)
  # ---------------------------------------------------------------------------

  defp redo_action({:move_pin, pin_id, prev, new}, socket) do
    case Scenes.get_pin(socket.assigns.scene.id, pin_id) do
      nil ->
        {:error, socket}

      pin ->
        case Scenes.move_pin(pin, new.x, new.y) do
          {:ok, _} -> {:ok, socket, {:move_pin, pin_id, prev, new}}
          {:error, _} -> {:error, socket}
        end
    end
  end

  defp redo_action({:move_annotation, ann_id, prev, new}, socket) do
    case Scenes.get_annotation(socket.assigns.scene.id, ann_id) do
      nil ->
        {:error, socket}

      ann ->
        case Scenes.move_annotation(ann, new.x, new.y) do
          {:ok, _} -> {:ok, socket, {:move_annotation, ann_id, prev, new}}
          {:error, _} -> {:error, socket}
        end
    end
  end

  # ---------------------------------------------------------------------------
  # Redo: create actions (re-create from stored attrs)
  # ---------------------------------------------------------------------------

  defp redo_action({:create_pin, pin}, socket) do
    case Scenes.create_pin(socket.assigns.scene.id, pin_to_attrs(pin)) do
      {:ok, new_pin} ->
        {:ok,
         socket
         |> assign(:pins, socket.assigns.pins ++ [new_pin])
         |> push_event("pin_created", serialize_pin(new_pin)), {:create_pin, new_pin}}

      {:error, _} ->
        {:error, socket}
    end
  end

  defp redo_action({:create_zone, zone}, socket) do
    case Scenes.create_zone(socket.assigns.scene.id, zone_to_attrs(zone)) do
      {:ok, new_zone} ->
        {:ok,
         socket
         |> assign(:zones, socket.assigns.zones ++ [new_zone])
         |> push_event("zone_created", serialize_zone(new_zone)), {:create_zone, new_zone}}

      {:error, _} ->
        {:error, socket}
    end
  end

  defp redo_action({:create_connection, conn}, socket) do
    case Scenes.create_connection(socket.assigns.scene.id, connection_to_attrs(conn)) do
      {:ok, new_conn} ->
        {:ok,
         socket
         |> assign(:connections, socket.assigns.connections ++ [new_conn])
         |> push_event("connection_created", serialize_connection(new_conn)),
         {:create_connection, new_conn}}

      {:error, _} ->
        {:error, socket}
    end
  end

  defp redo_action({:create_annotation, annotation}, socket) do
    case Scenes.create_annotation(socket.assigns.scene.id, annotation_to_attrs(annotation)) do
      {:ok, new_ann} ->
        {:ok,
         socket
         |> assign(:annotations, socket.assigns.annotations ++ [new_ann])
         |> push_event("annotation_created", serialize_annotation(new_ann)),
         {:create_annotation, new_ann}}

      {:error, _} ->
        {:error, socket}
    end
  end

  # ---------------------------------------------------------------------------
  # Redo: update actions (re-apply new values)
  # ---------------------------------------------------------------------------

  defp redo_action({:update_pin, pin_id, prev_attrs, new_attrs}, socket) do
    case Scenes.get_pin(socket.assigns.scene.id, pin_id) do
      nil ->
        {:error, socket}

      pin ->
        case Scenes.update_pin(pin, new_attrs) do
          {:ok, updated} ->
            {:ok,
             socket
             |> assign(:pins, replace_in_list(socket.assigns.pins, updated))
             |> maybe_update_selected_element("pin", updated)
             |> push_event("pin_updated", serialize_pin(updated)),
             {:update_pin, pin_id, prev_attrs, new_attrs}}

          {:error, _} ->
            {:error, socket}
        end
    end
  end

  defp redo_action({:update_zone, zone_id, prev_attrs, new_attrs}, socket) do
    case Scenes.get_zone(socket.assigns.scene.id, zone_id) do
      nil ->
        {:error, socket}

      zone ->
        case Scenes.update_zone(zone, new_attrs) do
          {:ok, updated} ->
            {:ok,
             socket
             |> assign(:zones, replace_in_list(socket.assigns.zones, updated))
             |> maybe_update_selected_element("zone", updated)
             |> push_event("zone_updated", serialize_zone(updated)),
             {:update_zone, zone_id, prev_attrs, new_attrs}}

          {:error, _} ->
            {:error, socket}
        end
    end
  end

  defp redo_action({:update_zone_vertices, zone_id, prev_vertices, new_vertices}, socket) do
    case Scenes.get_zone(socket.assigns.scene.id, zone_id) do
      nil ->
        {:error, socket}

      zone ->
        case Scenes.update_zone_vertices(zone, %{"vertices" => new_vertices}) do
          {:ok, updated} ->
            {:ok,
             socket
             |> assign(:zones, replace_in_list(socket.assigns.zones, updated))
             |> maybe_update_selected_element("zone", updated)
             |> push_event("zone_vertices_updated", serialize_zone(updated)),
             {:update_zone_vertices, zone_id, prev_vertices, new_vertices}}

          {:error, _} ->
            {:error, socket}
        end
    end
  end

  defp redo_action({:update_connection, conn_id, prev_attrs, new_attrs}, socket) do
    case Scenes.get_connection(socket.assigns.scene.id, conn_id) do
      nil ->
        {:error, socket}

      conn ->
        case Scenes.update_connection(conn, new_attrs) do
          {:ok, updated} ->
            {:ok,
             socket
             |> assign(:connections, replace_in_list(socket.assigns.connections, updated))
             |> maybe_update_selected_element("connection", updated)
             |> push_event("connection_updated", serialize_connection(updated)),
             {:update_connection, conn_id, prev_attrs, new_attrs}}

          {:error, _} ->
            {:error, socket}
        end
    end
  end

  defp redo_action({:update_connection_waypoints, conn_id, prev_waypoints, new_waypoints}, socket) do
    case Scenes.get_connection(socket.assigns.scene.id, conn_id) do
      nil ->
        {:error, socket}

      conn ->
        case Scenes.update_connection_waypoints(conn, %{"waypoints" => new_waypoints}) do
          {:ok, updated} ->
            {:ok,
             socket
             |> assign(:connections, replace_in_list(socket.assigns.connections, updated))
             |> maybe_update_selected_element("connection", updated)
             |> push_event("connection_updated", serialize_connection(updated)),
             {:update_connection_waypoints, conn_id, prev_waypoints, new_waypoints}}

          {:error, _} ->
            {:error, socket}
        end
    end
  end

  defp redo_action({:update_annotation, ann_id, prev_attrs, new_attrs}, socket) do
    case Scenes.get_annotation(socket.assigns.scene.id, ann_id) do
      nil ->
        {:error, socket}

      ann ->
        case Scenes.update_annotation(ann, new_attrs) do
          {:ok, updated} ->
            {:ok,
             socket
             |> assign(:annotations, replace_in_list(socket.assigns.annotations, updated))
             |> maybe_update_selected_element("annotation", updated)
             |> push_event("annotation_updated", serialize_annotation(updated)),
             {:update_annotation, ann_id, prev_attrs, new_attrs}}

          {:error, _} ->
            {:error, socket}
        end
    end
  end

  # ---------------------------------------------------------------------------
  # Redo: layer actions
  # ---------------------------------------------------------------------------

  defp redo_action({:create_layer, layer}, socket) do
    case Scenes.create_layer(socket.assigns.scene.id, layer_to_attrs(layer)) do
      {:ok, new_layer} ->
        {:ok,
         socket
         |> push_event("layer_created", %{id: new_layer.id, name: new_layer.name}),
         {:create_layer, new_layer}}

      {:error, _} ->
        {:error, socket}
    end
  end

  defp redo_action({:delete_layer, layer}, socket) do
    case Scenes.get_layer(socket.assigns.scene.id, layer.id) do
      nil ->
        {:error, socket}

      found ->
        case Scenes.delete_layer(found) do
          {:ok, _} ->
            {:ok,
             socket
             |> push_event("layer_deleted", %{id: found.id}), {:delete_layer, found}}

          {:error, _} ->
            {:error, socket}
        end
    end
  end

  defp redo_action({:rename_layer, layer_id, prev_name, new_name}, socket) do
    case Scenes.get_layer(socket.assigns.scene.id, layer_id) do
      nil ->
        {:error, socket}

      layer ->
        case Scenes.update_layer(layer, %{"name" => new_name}) do
          {:ok, _} -> {:ok, socket, {:rename_layer, layer_id, prev_name, new_name}}
          {:error, _} -> {:error, socket}
        end
    end
  end

  defp redo_action({:update_layer_fog, layer_id, prev_attrs, new_attrs}, socket) do
    case Scenes.get_layer(socket.assigns.scene.id, layer_id) do
      nil ->
        {:error, socket}

      layer ->
        case Scenes.update_layer(layer, new_attrs) do
          {:ok, updated} ->
            {:ok,
             socket
             |> push_event("layer_fog_changed", %{
               id: updated.id,
               fog_enabled: updated.fog_enabled,
               fog_color: updated.fog_color,
               fog_opacity: updated.fog_opacity
             }), {:update_layer_fog, layer_id, prev_attrs, new_attrs}}

          {:error, _} ->
            {:error, socket}
        end
    end
  end

  # ---------------------------------------------------------------------------
  # Redo: compound actions
  # ---------------------------------------------------------------------------

  defp redo_action({:compound, actions}, socket) do
    result =
      Enum.reduce_while(actions, {:ok, socket, []}, fn action, {:ok, sock, undo_items} ->
        case redo_action(action, sock) do
          {:ok, sock, undo_item} -> {:cont, {:ok, sock, [undo_item | undo_items]}}
          {:error, sock} -> {:halt, {:error, sock}}
        end
      end)

    case result do
      {:ok, socket, undo_items} -> {:ok, socket, {:compound, Enum.reverse(undo_items)}}
      {:error, socket} -> {:error, socket}
    end
  end

  # ---------------------------------------------------------------------------
  # Compound undo helpers: ID rebasing for FK integrity
  # ---------------------------------------------------------------------------

  # Rewrite connection FK IDs to point to newly-created pin IDs
  defp rebase_ids({:delete_connection, conn}, id_map) when map_size(id_map) > 0 do
    from = Map.get(id_map, conn.from_pin_id, conn.from_pin_id)
    to = Map.get(id_map, conn.to_pin_id, conn.to_pin_id)
    {:delete_connection, %{conn | from_pin_id: from, to_pin_id: to}}
  end

  defp rebase_ids(action, _id_map), do: action

  # Track old_id → new_id when a delete undo creates a new element
  defp track_rebased_id({:delete_pin, old}, {:delete_pin, new}, id_map) do
    Map.put(id_map, old.id, new.id)
  end

  defp track_rebased_id({:delete_zone, old}, {:delete_zone, new}, id_map) do
    Map.put(id_map, old.id, new.id)
  end

  defp track_rebased_id(_original, _redo_item, id_map), do: id_map
end
