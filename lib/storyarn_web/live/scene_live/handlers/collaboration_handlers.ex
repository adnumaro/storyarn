defmodule StoryarnWeb.SceneLive.Handlers.CollaborationHandlers do
  @moduledoc """
  Collaboration event handlers for the scene editor.

  Handles cursor broadcasting, remote change application, and lock state
  updates. Each function returns `{:noreply, socket}`.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3]

  alias Storyarn.Collaboration
  alias Storyarn.Scenes
  import StoryarnWeb.SceneLive.Helpers.Serializer

  # ===========================================================================
  # Client events (handle_event dispatches)
  # ===========================================================================

  @spec handle_cursor_moved(map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_cursor_moved(%{"x" => x, "y" => y}, socket)
      when is_number(x) and is_number(y) and x >= 0 and x <= 100 and y >= 0 and y <= 100 do
    if scope = socket.assigns[:collab_scope] do
      user = socket.assigns.current_scope.user
      Collaboration.broadcast_cursor(scope, user, x, y)
    end

    {:noreply, socket}
  end

  def handle_cursor_moved(_params, socket), do: {:noreply, socket}

  @spec handle_cursor_left(Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_cursor_left(socket) do
    if scope = socket.assigns[:collab_scope] do
      user_id = socket.assigns.current_scope.user.id
      Collaboration.broadcast_cursor_leave(scope, user_id)
    end

    {:noreply, socket}
  end

  # ===========================================================================
  # Remote change handlers (handle_info dispatches)
  # ===========================================================================

  @spec handle_remote_change(atom(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}

  # --- Position-only changes: push directly to JS, no DB reload ---

  def handle_remote_change(:pin_moved, payload, socket) do
    {:noreply, push_event(socket, "pin_updated", payload)}
  end

  def handle_remote_change(:annotation_moved, payload, socket) do
    {:noreply, push_event(socket, "annotation_updated", payload)}
  end

  def handle_remote_change(:zone_vertices_updated, payload, socket) do
    {:noreply, push_event(socket, "zone_vertices_updated", payload)}
  end

  # --- Element created: reload from DB, push to JS ---

  def handle_remote_change(:pin_created, payload, socket) do
    with id when not is_nil(id) <- get_in_payload(payload, :id),
         %{} = pin <- Scenes.get_pin(socket.assigns.scene.id, id) do
      {:noreply,
       socket
       |> assign(:pins, socket.assigns.pins ++ [pin])
       |> push_event("pin_created", serialize_pin(pin))}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_remote_change(:zone_created, payload, socket) do
    with id when not is_nil(id) <- get_in_payload(payload, :id),
         %{} = zone <- Scenes.get_zone(socket.assigns.scene.id, id) do
      {:noreply,
       socket
       |> assign(:zones, socket.assigns.zones ++ [zone])
       |> push_event("zone_created", serialize_zone(zone))}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_remote_change(:connection_created, payload, socket) do
    with id when not is_nil(id) <- get_in_payload(payload, :id),
         %{} = conn <- Scenes.get_connection(socket.assigns.scene.id, id) do
      {:noreply,
       socket
       |> assign(:connections, socket.assigns.connections ++ [conn])
       |> push_event("connection_created", serialize_connection(conn))}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_remote_change(:annotation_created, payload, socket) do
    with id when not is_nil(id) <- get_in_payload(payload, :id),
         %{} = ann <- Scenes.get_annotation(socket.assigns.scene.id, id) do
      {:noreply,
       socket
       |> assign(:annotations, socket.assigns.annotations ++ [ann])
       |> push_event("annotation_created", serialize_annotation(ann))}
    else
      _ -> {:noreply, socket}
    end
  end

  # --- Element deleted: remove from assigns + push to JS ---

  def handle_remote_change(:pin_deleted, payload, socket) do
    case get_in_payload(payload, :id) do
      nil -> {:noreply, socket}
      id ->
        {:noreply,
         socket
         |> assign(:pins, Enum.reject(socket.assigns.pins, &(&1.id == id)))
         |> deselect_if_selected(id)
         |> push_event("pin_deleted", %{id: id})}
    end
  end

  def handle_remote_change(:zone_deleted, payload, socket) do
    case get_in_payload(payload, :id) do
      nil -> {:noreply, socket}
      id ->
        {:noreply,
         socket
         |> assign(:zones, Enum.reject(socket.assigns.zones, &(&1.id == id)))
         |> deselect_if_selected(id)
         |> push_event("zone_deleted", %{id: id})}
    end
  end

  def handle_remote_change(:connection_deleted, payload, socket) do
    case get_in_payload(payload, :id) do
      nil -> {:noreply, socket}
      id ->
        {:noreply,
         socket
         |> assign(:connections, Enum.reject(socket.assigns.connections, &(&1.id == id)))
         |> deselect_if_selected(id)
         |> push_event("connection_deleted", %{id: id})}
    end
  end

  def handle_remote_change(:annotation_deleted, payload, socket) do
    case get_in_payload(payload, :id) do
      nil -> {:noreply, socket}
      id ->
        {:noreply,
         socket
         |> assign(:annotations, Enum.reject(socket.assigns.annotations, &(&1.id == id)))
         |> deselect_if_selected(id)
         |> push_event("annotation_deleted", %{id: id})}
    end
  end

  # --- Element property updates: reload from DB to get latest ---

  def handle_remote_change(:pin_updated, %{id: pin_id}, socket) do
    case Scenes.get_pin(socket.assigns.scene.id, pin_id) do
      nil ->
        {:noreply, socket}

      pin ->
        {:noreply,
         socket
         |> update_in_list(:pins, pin)
         |> push_event("pin_updated", serialize_pin(pin))}
    end
  end

  def handle_remote_change(:zone_updated, %{id: zone_id}, socket) do
    case Scenes.get_zone(socket.assigns.scene.id, zone_id) do
      nil ->
        {:noreply, socket}

      zone ->
        {:noreply,
         socket
         |> update_in_list(:zones, zone)
         |> push_event("zone_updated", serialize_zone(zone))}
    end
  end

  def handle_remote_change(:connection_updated, %{id: conn_id}, socket) do
    case Scenes.get_connection(socket.assigns.scene.id, conn_id) do
      nil ->
        {:noreply, socket}

      conn ->
        {:noreply,
         socket
         |> update_in_list(:connections, conn)
         |> push_event("connection_updated", serialize_connection(conn))}
    end
  end

  def handle_remote_change(:annotation_updated, %{id: ann_id}, socket) do
    case Scenes.get_annotation(socket.assigns.scene.id, ann_id) do
      nil ->
        {:noreply, socket}

      ann ->
        {:noreply,
         socket
         |> update_in_list(:annotations, ann)
         |> push_event("annotation_updated", serialize_annotation(ann))}
    end
  end

  # --- Layer / scene-level changes: full scene reload ---

  def handle_remote_change(action, _payload, socket)
      when action in [
             :layer_created,
             :layer_deleted,
             :layer_updated,
             :scene_settings_updated,
             :scene_refreshed
           ] do
    full_scene_reload(socket)
  end

  # --- Fallback: full reload (safety net for unknown actions) ---

  def handle_remote_change(_action, _payload, socket) do
    full_scene_reload(socket)
  end

  # ===========================================================================
  # Lock handlers
  # ===========================================================================

  @spec handle_lock_change(Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_lock_change(socket) do
    entity_locks = Collaboration.list_locks(socket.assigns.collab_scope)

    {:noreply,
     socket
     |> assign(:entity_locks, entity_locks)
     |> push_event("locks_updated", %{locks: entity_locks})}
  end

  # ===========================================================================
  # Private helpers
  # ===========================================================================

  defp full_scene_reload(socket) do
    scene = Scenes.get_scene(socket.assigns.project.id, socket.assigns.scene.id)

    if scene do
      scene_data = build_scene_data(scene, socket.assigns.can_edit)

      {:noreply,
       socket
       |> assign(:scene, scene)
       |> assign(:layers, scene.layers || [])
       |> assign(:zones, scene.zones || [])
       |> assign(:pins, scene.pins || [])
       |> assign(:connections, scene.connections || [])
       |> assign(:annotations, scene.annotations || [])
       |> assign(:scene_data, scene_data)
       |> push_event("scene_data", scene_data)}
    else
      {:noreply, socket}
    end
  end

  defp deselect_if_selected(socket, element_id) do
    if socket.assigns[:selected_element] && socket.assigns.selected_element.id == element_id do
      socket
      |> assign(:selected_type, nil)
      |> assign(:selected_element, nil)
      |> push_event("element_deselected", %{})
    else
      socket
    end
  end

  defp update_in_list(socket, key, updated_entity) do
    list = Map.get(socket.assigns, key, [])

    updated_list =
      Enum.map(list, fn e ->
        if e.id == updated_entity.id, do: updated_entity, else: e
      end)

    assign(socket, key, updated_list)
  end

  # Payload keys can be atoms or strings depending on the broadcast source
  defp get_in_payload(payload, key) when is_atom(key) do
    Map.get(payload, key) || Map.get(payload, Atom.to_string(key))
  end
end
