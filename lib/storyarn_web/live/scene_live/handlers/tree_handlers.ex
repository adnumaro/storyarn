defmodule StoryarnWeb.SceneLive.Handlers.TreeHandlers do
  @moduledoc """
  Tree/navigation handlers for the scene LiveView.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3, push_navigate: 2, put_flash: 3]
  use StoryarnWeb, :verified_routes
  use Gettext, backend: StoryarnWeb.Gettext

  require Logger

  alias Storyarn.Scenes
  alias Storyarn.Scenes.ZoneImageExtractor
  alias Storyarn.Shared.MapUtils

  import StoryarnWeb.SceneLive.Helpers.SceneHelpers
  import StoryarnWeb.SceneLive.Helpers.Serializer

  def handle_create_scene(_params, socket) do
    case Scenes.create_scene(socket.assigns.project, %{name: dgettext("scenes", "Untitled")}) do
      {:ok, new_scene} ->
        {:noreply,
         push_navigate(socket,
           to:
             ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/scenes/#{new_scene.id}"
         )}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, dgettext("scenes", "Could not create scene."))}
    end
  end

  def handle_create_child_scene(%{"parent-id" => parent_id}, socket) do
    attrs = %{name: dgettext("scenes", "Untitled"), parent_id: parent_id}

    case Scenes.create_scene(socket.assigns.project, attrs) do
      {:ok, new_scene} ->
        {:noreply,
         push_navigate(socket,
           to:
             ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/scenes/#{new_scene.id}"
         )}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, dgettext("scenes", "Could not create scene."))}
    end
  end

  def handle_set_pending_delete_scene(%{"id" => id}, socket) do
    {:noreply, assign(socket, :pending_delete_id, id)}
  end

  def handle_confirm_delete_scene(_params, socket) do
    if id = socket.assigns[:pending_delete_id] do
      handle_delete_scene(%{"id" => id}, socket)
    else
      {:noreply, socket}
    end
  end

  def handle_delete_scene(%{"id" => scene_id}, socket) do
    case Scenes.get_scene(socket.assigns.project.id, scene_id) do
      nil -> {:noreply, socket}
      scene -> do_delete_current_scene(socket, scene, scene_id)
    end
  end

  def handle_move_to_parent(
        %{"item_id" => item_id, "new_parent_id" => new_parent_id, "position" => position},
        socket
      ) do
    case Scenes.get_scene(socket.assigns.project.id, item_id) do
      nil -> {:noreply, socket}
      scene -> do_move_scene_in_show(socket, scene, new_parent_id, position)
    end
  end

  def handle_create_child_scene_from_zone(%{"zone_id" => zone_id}, socket) do
    scene = socket.assigns.scene

    with zone when not is_nil(zone) <- Scenes.get_zone(scene.id, zone_id),
         :ok <- validate_zone_has_name(zone),
         {:ok, bg_asset, img_dims} <-
           ZoneImageExtractor.extract(scene, zone, socket.assigns.project),
         child_attrs <- build_child_scene_attrs(zone, scene, bg_asset, img_dims),
         {:ok, child_scene} <- Scenes.create_scene(socket.assigns.project, child_attrs),
         {:ok, _updated_zone} <-
           Scenes.update_zone(zone, %{target_type: "scene", target_id: child_scene.id}) do
      {:noreply,
       push_navigate(socket,
         to:
           ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/scenes/#{child_scene.id}"
       )}
    else
      nil ->
        {:noreply, put_flash(socket, :error, dgettext("scenes", "Zone not found."))}

      {:error, :zone_has_no_name} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("scenes", "Name the zone before creating a child scene.")
         )}

      {:error, :no_background_image} ->
        create_child_scene_without_image(zone_id, scene, socket)

      {:error, :image_extraction_failed} ->
        create_child_scene_without_image(zone_id, scene, socket)

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("scenes", "Could not create child scene."))}
    end
  end

  def handle_navigate_to_target(%{"type" => "scene", "id" => id}, socket) do
    project = socket.assigns.project

    case Scenes.get_scene_brief(project.id, id) do
      nil ->
        # Target scene was deleted — clear the stale zone reference
        socket = clear_stale_zone_target(socket, id)

        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext(
             "scenes",
             "The target scene no longer exists. The reference has been cleared."
           )
         )}

      _scene ->
        {:noreply,
         push_navigate(socket,
           to:
             ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{project.slug}/scenes/#{id}"
         )}
    end
  end

  def handle_navigate_to_target(_params, socket) do
    {:noreply, socket}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp do_delete_current_scene(socket, scene, scene_id) do
    case Scenes.delete_scene(scene) do
      {:ok, _} ->
        {:noreply, after_scene_deleted(socket, scene_id)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("scenes", "Could not delete scene."))}
    end
  end

  defp do_move_scene_in_show(socket, scene, new_parent_id, position) do
    new_parent_id = MapUtils.parse_int(new_parent_id)
    position = MapUtils.parse_int(position) || 0

    case Scenes.move_scene_to_position(scene, new_parent_id, position) do
      {:ok, _} ->
        {:noreply, reload_scenes_tree(socket)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("scenes", "Could not move scene."))}
    end
  end

  defp validate_zone_has_name(%{name: nil}), do: {:error, :zone_has_no_name}
  defp validate_zone_has_name(%{name: ""}), do: {:error, :zone_has_no_name}
  defp validate_zone_has_name(_zone), do: :ok

  defp build_child_scene_attrs(zone, parent_scene, bg_asset, {img_w, img_h}) do
    {min_x, _min_y, max_x, _max_y} = ZoneImageExtractor.bounding_box(zone.vertices)
    bw_percent = max_x - min_x

    child_scale =
      if parent_scene.scale_value && bw_percent > 0,
        do: parent_scene.scale_value * bw_percent / 100.0,
        else: nil

    %{
      name: zone.name,
      parent_id: parent_scene.id,
      background_asset_id: bg_asset && bg_asset.id,
      width: img_w,
      height: img_h,
      scale_value: child_scale,
      scale_unit: parent_scene.scale_unit
    }
  end

  defp build_child_scene_attrs(zone, parent_scene, nil, nil) do
    build_child_scene_attrs(zone, parent_scene, nil, {1000, 1000})
  end

  defp create_child_scene_without_image(zone_id, scene, socket) do
    zone = Scenes.get_zone(scene.id, zone_id)

    if zone do
      child_attrs = build_child_scene_attrs(zone, scene, nil, nil)

      case Scenes.create_scene(socket.assigns.project, child_attrs) do
        {:ok, child_scene} ->
          link_zone_to_child_scene(zone, child_scene)

          {:noreply,
           socket
           |> put_flash(
             :info,
             dgettext("scenes", "Child scene created. Add a background image to continue.")
           )
           |> push_navigate(
             to:
               ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/scenes/#{child_scene.id}"
           )}

        {:error, _} ->
          {:noreply,
           put_flash(socket, :error, dgettext("scenes", "Could not create child scene."))}
      end
    else
      {:noreply, put_flash(socket, :error, dgettext("scenes", "Zone not found."))}
    end
  end

  defp link_zone_to_child_scene(zone, child_scene) do
    case Scenes.update_zone(zone, %{target_type: "scene", target_id: child_scene.id}) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "[TreeHandlers] Failed to link zone #{zone.id} to child scene #{child_scene.id}: #{inspect(reason)}"
        )
    end
  end

  defp after_scene_deleted(socket, deleted_scene_id) do
    socket = put_flash(socket, :info, dgettext("scenes", "Scene moved to trash."))

    if to_string(deleted_scene_id) == to_string(socket.assigns.scene.id) do
      push_navigate(socket,
        to:
          ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/scenes"
      )
    else
      reload_scenes_tree(socket)
    end
  end

  # Clears target_type/target_id on any zone that references a deleted scene,
  # then refreshes socket state so the JS gets the updated zone data.
  defp clear_stale_zone_target(socket, deleted_scene_id) do
    case Scenes.get_zone_linking_to_scene(socket.assigns.scene.id, deleted_scene_id) do
      nil ->
        socket

      zone ->
        case Scenes.update_zone(zone, %{target_type: nil, target_id: nil}) do
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
