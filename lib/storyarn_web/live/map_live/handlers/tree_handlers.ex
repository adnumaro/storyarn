defmodule StoryarnWeb.MapLive.Handlers.TreeHandlers do
  @moduledoc """
  Tree/navigation handlers for the map LiveView.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_navigate: 2, put_flash: 3]
  use StoryarnWeb, :verified_routes
  use Gettext, backend: StoryarnWeb.Gettext

  alias Storyarn.Maps
  import StoryarnWeb.MapLive.Helpers.MapHelpers
  import StoryarnWeb.MapLive.Helpers.Serializer

  def handle_create_map(_params, socket) do
    case Maps.create_map(socket.assigns.project, %{name: dgettext("maps", "Untitled")}) do
      {:ok, new_map} ->
        {:noreply,
         push_navigate(socket,
           to:
             ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/maps/#{new_map.id}"
         )}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, dgettext("maps", "Could not create map."))}
    end
  end

  def handle_create_child_map(%{"parent-id" => parent_id}, socket) do
    attrs = %{name: dgettext("maps", "Untitled"), parent_id: parent_id}

    case Maps.create_map(socket.assigns.project, attrs) do
      {:ok, new_map} ->
        {:noreply,
         push_navigate(socket,
           to:
             ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/maps/#{new_map.id}"
         )}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, dgettext("maps", "Could not create map."))}
    end
  end

  def handle_set_pending_delete_map(%{"id" => id}, socket) do
    {:noreply, assign(socket, :pending_delete_id, id)}
  end

  def handle_confirm_delete_map(_params, socket) do
    if id = socket.assigns[:pending_delete_id] do
      handle_delete_map(%{"id" => id}, socket)
    else
      {:noreply, socket}
    end
  end

  def handle_delete_map(%{"id" => map_id}, socket) do
    case Maps.get_map(socket.assigns.project.id, map_id) do
      nil -> {:noreply, socket}
      map -> do_delete_current_map(socket, map, map_id)
    end
  end

  def handle_move_to_parent(
        %{"item_id" => item_id, "new_parent_id" => new_parent_id, "position" => position},
        socket
      ) do
    case Maps.get_map(socket.assigns.project.id, item_id) do
      nil -> {:noreply, socket}
      map -> do_move_map_in_show(socket, map, new_parent_id, position)
    end
  end

  def handle_navigate_to_target(%{"type" => "map", "id" => id}, socket) do
    {:noreply,
     push_navigate(socket,
       to:
         ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/maps/#{id}"
     )}
  end

  def handle_navigate_to_target(_params, socket) do
    {:noreply, socket}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp do_delete_current_map(socket, map, map_id) do
    case Maps.delete_map(map) do
      {:ok, _} -> {:noreply, after_map_deleted(socket, map_id)}
      {:error, _} -> {:noreply, put_flash(socket, :error, dgettext("maps", "Could not delete map."))}
    end
  end

  defp do_move_map_in_show(socket, map, new_parent_id, position) do
    new_parent_id = parse_int(new_parent_id)
    position = parse_int(position) || 0

    case Maps.move_map_to_position(map, new_parent_id, position) do
      {:ok, _} -> {:noreply, reload_maps_tree(socket)}
      {:error, _} -> {:noreply, put_flash(socket, :error, dgettext("maps", "Could not move map."))}
    end
  end

  defp after_map_deleted(socket, deleted_map_id) do
    socket = put_flash(socket, :info, dgettext("maps", "Map moved to trash."))

    if to_string(deleted_map_id) == to_string(socket.assigns.map.id) do
      push_navigate(socket,
        to:
          ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/maps"
      )
    else
      reload_maps_tree(socket)
    end
  end
end
