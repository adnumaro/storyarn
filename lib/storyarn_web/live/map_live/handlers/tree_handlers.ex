defmodule StoryarnWeb.MapLive.Handlers.TreeHandlers do
  @moduledoc """
  Tree/navigation handlers for the map LiveView.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3, push_navigate: 2, put_flash: 3]
  use StoryarnWeb, :verified_routes
  use Gettext, backend: StoryarnWeb.Gettext

  require Logger

  alias Storyarn.Maps
  alias Storyarn.Maps.ZoneImageExtractor

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

  def handle_create_child_map_from_zone(%{"zone_id" => zone_id}, socket) do
    map = socket.assigns.map

    with zone when not is_nil(zone) <- Maps.get_zone(map.id, zone_id),
         :ok <- validate_zone_has_name(zone),
         {:ok, bg_asset, img_dims} <- ZoneImageExtractor.extract(map, zone, socket.assigns.project),
         child_attrs <- build_child_map_attrs(zone, map, bg_asset, img_dims),
         {:ok, child_map} <- Maps.create_map(socket.assigns.project, child_attrs),
         {:ok, _updated_zone} <-
           Maps.update_zone(zone, %{target_type: "map", target_id: child_map.id}) do
      {:noreply,
       push_navigate(socket,
         to:
           ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/maps/#{child_map.id}"
       )}
    else
      nil ->
        {:noreply, put_flash(socket, :error, dgettext("maps", "Zone not found."))}

      {:error, :zone_has_no_name} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("maps", "Name the zone before creating a child map.")
         )}

      {:error, :no_background_image} ->
        create_child_map_without_image(zone_id, map, socket)

      {:error, :image_extraction_failed} ->
        create_child_map_without_image(zone_id, map, socket)

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("maps", "Could not create child map."))}
    end
  end

  def handle_navigate_to_target(%{"type" => "map", "id" => id}, socket) do
    project = socket.assigns.project

    case Maps.get_map_brief(project.id, id) do
      nil ->
        # Target map was deleted — clear the stale zone reference
        socket = clear_stale_zone_target(socket, id)

        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("maps", "The target map no longer exists. The reference has been cleared.")
         )}

      _map ->
        {:noreply,
         push_navigate(socket,
           to:
             ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{project.slug}/maps/#{id}"
         )}
    end
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

  defp validate_zone_has_name(%{name: nil}), do: {:error, :zone_has_no_name}
  defp validate_zone_has_name(%{name: ""}), do: {:error, :zone_has_no_name}
  defp validate_zone_has_name(_zone), do: :ok

  defp build_child_map_attrs(zone, parent_map, bg_asset, {img_w, img_h}) do
    {min_x, _min_y, max_x, _max_y} = ZoneImageExtractor.bounding_box(zone.vertices)
    bw_percent = max_x - min_x

    child_scale =
      if parent_map.scale_value && bw_percent > 0,
        do: parent_map.scale_value * bw_percent / 100.0,
        else: nil

    %{
      name: zone.name,
      parent_id: parent_map.id,
      background_asset_id: bg_asset && bg_asset.id,
      width: img_w,
      height: img_h,
      scale_value: child_scale,
      scale_unit: parent_map.scale_unit
    }
  end

  defp build_child_map_attrs(zone, parent_map, nil, nil) do
    build_child_map_attrs(zone, parent_map, nil, {1000, 1000})
  end

  defp create_child_map_without_image(zone_id, map, socket) do
    zone = Maps.get_zone(map.id, zone_id)

    if zone do
      child_attrs = build_child_map_attrs(zone, map, nil, nil)

      case Maps.create_map(socket.assigns.project, child_attrs) do
        {:ok, child_map} ->
          link_zone_to_child_map(zone, child_map)

          {:noreply,
           socket
           |> put_flash(
             :info,
             dgettext("maps", "Child map created. Add a background image to continue.")
           )
           |> push_navigate(
             to:
               ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/maps/#{child_map.id}"
           )}

        {:error, _} ->
          {:noreply,
           put_flash(socket, :error, dgettext("maps", "Could not create child map."))}
      end
    else
      {:noreply, put_flash(socket, :error, dgettext("maps", "Zone not found."))}
    end
  end

  defp link_zone_to_child_map(zone, child_map) do
    case Maps.update_zone(zone, %{target_type: "map", target_id: child_map.id}) do
      {:ok, _} -> :ok

      {:error, reason} ->
        Logger.warning(
          "[TreeHandlers] Failed to link zone #{zone.id} to child map #{child_map.id}: #{inspect(reason)}"
        )
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

  # Clears target_type/target_id on any zone that references a deleted map,
  # then refreshes socket state so the JS gets the updated zone data.
  defp clear_stale_zone_target(socket, deleted_map_id) do
    case Maps.get_zone_linking_to_map(socket.assigns.map.id, deleted_map_id) do
      nil ->
        socket

      zone ->
        case Maps.update_zone(zone, %{target_type: nil, target_id: nil}) do
          {:ok, updated} ->
            socket
            |> assign(:zones, replace_in_list(socket.assigns.zones, updated))
            |> maybe_update_selected_element("zone", updated)
            |> push_event("zone_updated", serialize_zone(updated))

          {:error, _} ->
            socket
        end
    end
  end
end
