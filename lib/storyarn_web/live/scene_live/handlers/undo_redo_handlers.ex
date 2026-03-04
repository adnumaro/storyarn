defmodule StoryarnWeb.SceneLive.Handlers.UndoRedoHandlers do
  @moduledoc """
  Undo/redo handlers for the scene LiveView.

  Uses a dispatch map to generalize create/update/delete across element types
  (pin, zone, connection, annotation), keeping layer and special actions separate.
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
  # Element-type dispatch — maps type atoms to context functions, assign keys,
  # serializer functions, and push event names.
  # ---------------------------------------------------------------------------

  @type_config %{
    pin: %{
      get: &Scenes.get_pin/2,
      create: &Scenes.create_pin/2,
      update: &Scenes.update_pin/2,
      delete: &Scenes.delete_pin/1,
      assign_key: :pins,
      type_string: "pin"
    },
    zone: %{
      get: &Scenes.get_zone/2,
      create: &Scenes.create_zone/2,
      update: &Scenes.update_zone/2,
      delete: &Scenes.delete_zone/1,
      assign_key: :zones,
      type_string: "zone"
    },
    connection: %{
      get: &Scenes.get_connection/2,
      create: &Scenes.create_connection/2,
      update: &Scenes.update_connection/2,
      delete: &Scenes.delete_connection/1,
      assign_key: :connections,
      type_string: "connection"
    },
    annotation: %{
      get: &Scenes.get_annotation/2,
      create: &Scenes.create_annotation/2,
      update: &Scenes.update_annotation/2,
      delete: &Scenes.delete_annotation/1,
      assign_key: :annotations,
      type_string: "annotation"
    }
  }

  defp type_config(type), do: Map.fetch!(@type_config, type)

  defp serialize(type, element) do
    case type do
      :pin -> serialize_pin(element)
      :zone -> serialize_zone(element)
      :connection -> serialize_connection(element)
      :annotation -> serialize_annotation(element)
    end
  end

  # ---------------------------------------------------------------------------
  # Attr extraction helpers (used by both undo and redo of creates/deletes)
  # ---------------------------------------------------------------------------

  defp to_attrs(:pin, el),
    do: Map.put(ElementHandlers.pin_copyable_attrs(el), "locked", el.locked)

  defp to_attrs(:zone, el),
    do: Map.put(ElementHandlers.zone_copyable_attrs(el), "locked", el.locked)

  defp to_attrs(:connection, el) do
    %{
      "from_pin_id" => el.from_pin_id,
      "to_pin_id" => el.to_pin_id,
      "line_style" => el.line_style,
      "line_width" => el.line_width,
      "color" => el.color,
      "label" => el.label,
      "bidirectional" => el.bidirectional,
      "show_label" => el.show_label,
      "waypoints" => el.waypoints || []
    }
  end

  defp to_attrs(:annotation, el) do
    %{
      "text" => el.text,
      "position_x" => el.position_x,
      "position_y" => el.position_y,
      "font_size" => el.font_size,
      "color" => el.color,
      "layer_id" => el.layer_id,
      "locked" => el.locked
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

  # Per-type flash messages preserve existing gettext entries and Spanish translations
  # (each type has different grammatical gender in Spanish)
  defp flash_restored(:pin), do: dgettext("scenes", "Undo: pin restored.")
  defp flash_restored(:zone), do: dgettext("scenes", "Undo: zone restored.")
  defp flash_restored(:connection), do: dgettext("scenes", "Undo: connection restored.")
  defp flash_restored(:annotation), do: dgettext("scenes", "Undo: annotation restored.")

  defp flash_creation_reverted(:pin), do: dgettext("scenes", "Undo: pin creation reverted.")
  defp flash_creation_reverted(:zone), do: dgettext("scenes", "Undo: zone creation reverted.")

  defp flash_creation_reverted(:connection),
    do: dgettext("scenes", "Undo: connection creation reverted.")

  defp flash_creation_reverted(:annotation),
    do: dgettext("scenes", "Undo: annotation creation reverted.")

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
  # Generic undo: delete → re-create the deleted element
  # ---------------------------------------------------------------------------

  for type <- [:pin, :zone, :connection, :annotation] do
    delete_action = :"delete_#{type}"

    defp undo_action({unquote(delete_action), element}, socket) do
      undo_delete(unquote(type), element, socket)
    end
  end

  defp undo_delete(type, element, socket) do
    cfg = type_config(type)
    scene_id = socket.assigns.scene.id

    case cfg.create.(scene_id, to_attrs(type, element)) do
      {:ok, new_el} ->
        action_tag = :"delete_#{type}"

        {:ok,
         socket
         |> assign(cfg.assign_key, Map.get(socket.assigns, cfg.assign_key) ++ [new_el])
         |> push_event("#{cfg.type_string}_created", serialize(type, new_el))
         |> put_flash(:info, flash_restored(type)), {action_tag, new_el}}

      {:error, _} ->
        {:error, put_flash(socket, :error, dgettext("scenes", "Could not undo."))}
    end
  end

  # ---------------------------------------------------------------------------
  # Generic undo: create → delete the created element
  # ---------------------------------------------------------------------------

  for type <- [:pin, :zone, :connection, :annotation] do
    create_action = :"create_#{type}"

    defp undo_action({unquote(create_action), element}, socket) do
      undo_create(unquote(type), element, socket)
    end
  end

  defp undo_create(type, element, socket) do
    cfg = type_config(type)
    list = Map.get(socket.assigns, cfg.assign_key)

    case Enum.find(list, &(&1.id == element.id)) do
      nil ->
        {:error, socket}

      found ->
        case cfg.delete.(found) do
          {:ok, _} ->
            action_tag = :"create_#{type}"

            {:ok,
             socket
             |> assign(cfg.assign_key, Enum.reject(list, &(&1.id == found.id)))
             |> assign(:selected_element, nil)
             |> assign(:selected_type, nil)
             |> push_event("#{cfg.type_string}_deleted", %{id: found.id})
             |> put_flash(:info, flash_creation_reverted(type)), {action_tag, found}}

          {:error, _} ->
            {:error, socket}
        end
    end
  end

  # ---------------------------------------------------------------------------
  # Generic undo: update → restore previous attrs
  # ---------------------------------------------------------------------------

  for type <- [:pin, :zone, :connection, :annotation] do
    update_action = :"update_#{type}"

    defp undo_action({unquote(update_action), id, prev_attrs, new_attrs}, socket) do
      undo_update(unquote(type), id, prev_attrs, new_attrs, socket)
    end
  end

  defp undo_update(type, id, prev_attrs, new_attrs, socket) do
    cfg = type_config(type)
    scene_id = socket.assigns.scene.id

    case cfg.get.(scene_id, id) do
      nil ->
        {:error, socket}

      element ->
        case cfg.update.(element, prev_attrs) do
          {:ok, updated} ->
            action_tag = :"update_#{type}"

            {:ok,
             socket
             |> assign(
               cfg.assign_key,
               replace_in_list(Map.get(socket.assigns, cfg.assign_key), updated)
             )
             |> maybe_update_selected_element(cfg.type_string, updated)
             |> push_event("#{cfg.type_string}_updated", serialize(type, updated)),
             {action_tag, id, prev_attrs, new_attrs}}

          {:error, _} ->
            {:error, socket}
        end
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
  # Undo: zone vertices (special update)
  # ---------------------------------------------------------------------------

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

  # ---------------------------------------------------------------------------
  # Undo: connection waypoints (special update)
  # ---------------------------------------------------------------------------

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

  # ---------------------------------------------------------------------------
  # Undo: layer actions (unique structure — no generic dispatch)
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
  # Generic redo: delete → re-delete the restored element
  # ---------------------------------------------------------------------------

  for type <- [:pin, :zone, :connection, :annotation] do
    delete_action = :"delete_#{type}"

    defp redo_action({unquote(delete_action), element}, socket) do
      redo_delete(unquote(type), element, socket)
    end
  end

  defp redo_delete(type, element, socket) do
    cfg = type_config(type)
    list = Map.get(socket.assigns, cfg.assign_key)

    case Enum.find(list, &(&1.id == element.id)) do
      nil ->
        {:error, socket}

      found ->
        case cfg.delete.(found) do
          {:ok, _} ->
            action_tag = :"delete_#{type}"

            {:ok,
             socket
             |> assign(cfg.assign_key, Enum.reject(list, &(&1.id == found.id)))
             |> assign(:selected_element, nil)
             |> assign(:selected_type, nil)
             |> push_event("#{cfg.type_string}_deleted", %{id: found.id}), {action_tag, found}}

          {:error, _} ->
            {:error, socket}
        end
    end
  end

  # ---------------------------------------------------------------------------
  # Generic redo: create → re-create from stored attrs
  # ---------------------------------------------------------------------------

  for type <- [:pin, :zone, :connection, :annotation] do
    create_action = :"create_#{type}"

    defp redo_action({unquote(create_action), element}, socket) do
      redo_create(unquote(type), element, socket)
    end
  end

  defp redo_create(type, element, socket) do
    cfg = type_config(type)
    scene_id = socket.assigns.scene.id

    case cfg.create.(scene_id, to_attrs(type, element)) do
      {:ok, new_el} ->
        action_tag = :"create_#{type}"

        {:ok,
         socket
         |> assign(cfg.assign_key, Map.get(socket.assigns, cfg.assign_key) ++ [new_el])
         |> push_event("#{cfg.type_string}_created", serialize(type, new_el)),
         {action_tag, new_el}}

      {:error, _} ->
        {:error, socket}
    end
  end

  # ---------------------------------------------------------------------------
  # Generic redo: update → re-apply new attrs
  # ---------------------------------------------------------------------------

  for type <- [:pin, :zone, :connection, :annotation] do
    update_action = :"update_#{type}"

    defp redo_action({unquote(update_action), id, prev_attrs, new_attrs}, socket) do
      redo_update(unquote(type), id, prev_attrs, new_attrs, socket)
    end
  end

  defp redo_update(type, id, prev_attrs, new_attrs, socket) do
    cfg = type_config(type)
    scene_id = socket.assigns.scene.id

    case cfg.get.(scene_id, id) do
      nil ->
        {:error, socket}

      element ->
        case cfg.update.(element, new_attrs) do
          {:ok, updated} ->
            action_tag = :"update_#{type}"

            {:ok,
             socket
             |> assign(
               cfg.assign_key,
               replace_in_list(Map.get(socket.assigns, cfg.assign_key), updated)
             )
             |> maybe_update_selected_element(cfg.type_string, updated)
             |> push_event("#{cfg.type_string}_updated", serialize(type, updated)),
             {action_tag, id, prev_attrs, new_attrs}}

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
  # Redo: zone vertices (special update)
  # ---------------------------------------------------------------------------

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

  # ---------------------------------------------------------------------------
  # Redo: connection waypoints (special update)
  # ---------------------------------------------------------------------------

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

  # ---------------------------------------------------------------------------
  # Redo: layer actions (unique structure)
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
