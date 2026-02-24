defmodule StoryarnWeb.SceneLive.Handlers.LayerHandlers do
  @moduledoc """
  Layer management handlers for the scene LiveView.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3, put_flash: 3]
  use StoryarnWeb, :verified_routes
  use Gettext, backend: StoryarnWeb.Gettext

  alias Storyarn.Scenes
  import StoryarnWeb.SceneLive.Helpers.SceneHelpers
  import StoryarnWeb.SceneLive.Helpers.Serializer
  import StoryarnWeb.SceneLive.Handlers.UndoRedoHandlers, only: [push_undo: 2]

  def handle_create_layer(_params, socket) do
    case Scenes.create_layer(socket.assigns.scene.id, %{name: dgettext("scenes", "New Layer")}) do
      {:ok, layer} ->
        {:noreply,
         socket
         |> push_undo({:create_layer, layer})
         |> push_event("layer_created", %{id: layer.id, name: layer.name})
         |> put_flash(:info, dgettext("scenes", "Layer created."))
         |> reload_scene()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("scenes", "Could not create layer."))}
    end
  end

  def handle_set_active_layer(%{"id" => layer_id}, socket) do
    {:noreply, assign(socket, :active_layer_id, parse_id(layer_id))}
  end

  def handle_toggle_layer_visibility(%{"id" => layer_id}, socket) do
    case Scenes.get_layer(socket.assigns.scene.id, layer_id) do
      nil -> {:noreply, socket}
      layer -> do_toggle_layer_visibility(socket, layer)
    end
  end

  def handle_update_layer_fog(%{"id" => layer_id, "field" => field} = params, socket)
      when field in ~w(fog_enabled fog_color fog_opacity) do
    case Scenes.get_layer(socket.assigns.scene.id, layer_id) do
      nil ->
        {:noreply, socket}

      layer ->
        value = normalize_fog_value(field, extract_field_value(params, field))
        do_update_layer_fog(socket, layer, field, value)
    end
  end

  def handle_start_rename_layer(%{"id" => id}, socket) do
    {:noreply, assign(socket, :renaming_layer_id, id)}
  end

  def handle_rename_layer(%{"id" => id, "value" => name}, socket) do
    {:noreply,
     socket
     |> do_rename_layer(id, String.trim(name))
     |> assign(:renaming_layer_id, nil)}
  end

  def handle_set_pending_delete_layer(%{"id" => id}, socket) do
    {:noreply, assign(socket, :pending_delete_layer_id, id)}
  end

  def handle_confirm_delete_layer(_params, socket) do
    if id = socket.assigns[:pending_delete_layer_id] do
      handle_delete_layer(%{"id" => id}, socket)
    else
      {:noreply, socket}
    end
  end

  def handle_delete_layer(%{"id" => layer_id}, socket) do
    case Scenes.get_layer(socket.assigns.scene.id, layer_id) do
      nil -> {:noreply, socket}
      layer -> do_delete_layer(socket, layer)
    end
  end

  def handle_remove_background(_params, socket) do
    case Scenes.update_scene(socket.assigns.scene, %{background_asset_id: nil}) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:scene, updated)
         |> push_event("background_changed", %{url: nil})}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("scenes", "Could not remove background."))}
    end
  end

  def handle_update_scene_scale(%{"field" => field} = params, socket)
      when field in ~w(scale_unit scale_value) do
    value = parse_scale_field(field, extract_field_value(params, field))

    case Scenes.update_scene(socket.assigns.scene, %{field => value}) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:scene, updated)
         |> assign(:scene_data, build_scene_data(updated, socket.assigns.can_edit))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("scenes", "Could not update scene scale."))}
    end
  end

  def handle_toggle_pin_icon_upload(_params, socket) do
    {:noreply, assign(socket, :show_pin_icon_upload, !socket.assigns.show_pin_icon_upload)}
  end

  def handle_remove_pin_icon(_params, socket) do
    pin = socket.assigns.selected_element

    if is_struct(pin, Storyarn.Scenes.ScenePin) do
      case Scenes.update_pin(pin, %{"icon_asset_id" => nil}) do
        {:ok, updated} ->
          updated = Scenes.preload_pin_associations(updated)

          {:noreply,
           socket
           |> assign(:selected_element, updated)
           |> update_pin_in_list(updated)
           |> assign(:show_pin_icon_upload, false)
           |> push_event("pin_updated", serialize_pin(updated))}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, dgettext("scenes", "Could not remove pin icon."))}
      end
    else
      {:noreply, put_flash(socket, :error, dgettext("scenes", "No pin selected."))}
    end
  end

  def handle_toggle_legend(_params, socket) do
    {:noreply, assign(socket, :legend_open, !socket.assigns.legend_open)}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp do_rename_layer(socket, _id, name) when name == "", do: socket

  defp do_rename_layer(socket, id, name) do
    case Scenes.get_layer(socket.assigns.scene.id, id) do
      nil -> socket
      layer -> do_update_layer_name(socket, layer, name)
    end
  end

  defp do_update_layer_name(socket, layer, name) when name == layer.name, do: socket

  defp do_update_layer_name(socket, layer, name) do
    prev_name = layer.name

    case Scenes.update_layer(layer, %{"name" => name}) do
      {:ok, _updated} ->
        socket
        |> push_undo({:rename_layer, layer.id, prev_name, name})
        |> put_flash(:info, dgettext("scenes", "Layer renamed."))
        |> reload_scene()

      {:error, _} ->
        put_flash(socket, :error, dgettext("scenes", "Could not rename layer."))
    end
  end

  defp do_toggle_layer_visibility(socket, layer) do
    case Scenes.toggle_layer_visibility(layer) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> push_event("layer_visibility_changed", %{id: updated.id, visible: updated.visible})
         |> reload_scene()}

      {:error, _} ->
        {:noreply,
         put_flash(socket, :error, dgettext("scenes", "Could not toggle layer visibility."))}
    end
  end

  defp normalize_fog_value("fog_enabled", value), do: value in ["true", true]
  defp normalize_fog_value("fog_opacity", value), do: parse_float(value)
  defp normalize_fog_value(_field, value), do: value

  defp do_update_layer_fog(socket, layer, field, value) do
    prev_value = Map.get(layer, String.to_existing_atom(field))

    case Scenes.update_layer(layer, %{field => value}) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> push_undo({:update_layer_fog, layer.id, %{field => prev_value}, %{field => value}})
         |> push_event("layer_fog_changed", %{
           id: updated.id,
           fog_enabled: updated.fog_enabled,
           fog_color: updated.fog_color,
           fog_opacity: updated.fog_opacity
         })
         |> reload_scene()}

      {:error, _} ->
        {:noreply,
         put_flash(socket, :error, dgettext("scenes", "Could not update fog settings."))}
    end
  end

  defp do_delete_layer(socket, layer) do
    case Scenes.delete_layer(layer) do
      {:ok, _} ->
        {:noreply,
         socket
         |> push_undo({:delete_layer, layer})
         |> push_event("layer_deleted", %{id: layer.id})
         |> put_flash(:info, dgettext("scenes", "Layer deleted."))
         |> reload_scene()}

      {:error, :cannot_delete_last_layer} ->
        {:noreply,
         put_flash(socket, :error, dgettext("scenes", "Cannot delete the last layer of a scene."))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("scenes", "Could not delete layer."))}
    end
  end
end
