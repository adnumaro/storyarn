defmodule StoryarnWeb.MapLive.Handlers.LayerHandlers do
  @moduledoc """
  Layer management handlers for the map LiveView.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3, put_flash: 3]
  use StoryarnWeb, :verified_routes
  use Gettext, backend: StoryarnWeb.Gettext

  alias Storyarn.Maps
  import StoryarnWeb.MapLive.Helpers.MapHelpers
  import StoryarnWeb.MapLive.Helpers.Serializer
  import StoryarnWeb.MapLive.Handlers.UndoRedoHandlers, only: [push_undo: 2]

  def handle_create_layer(_params, socket) do
    case Maps.create_layer(socket.assigns.map.id, %{name: dgettext("maps", "New Layer")}) do
      {:ok, layer} ->
        {:noreply,
         socket
         |> push_undo({:create_layer, layer})
         |> push_event("layer_created", %{id: layer.id, name: layer.name})
         |> put_flash(:info, dgettext("maps", "Layer created."))
         |> reload_map()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("maps", "Could not create layer."))}
    end
  end

  def handle_set_active_layer(%{"id" => layer_id}, socket) do
    {:noreply, assign(socket, :active_layer_id, parse_id(layer_id))}
  end

  def handle_toggle_layer_visibility(%{"id" => layer_id}, socket) do
    case Maps.get_layer(socket.assigns.map.id, layer_id) do
      nil -> {:noreply, socket}
      layer -> do_toggle_layer_visibility(socket, layer)
    end
  end

  def handle_update_layer_fog(%{"id" => layer_id, "field" => field} = params, socket)
      when field in ~w(fog_enabled fog_color fog_opacity) do
    case Maps.get_layer(socket.assigns.map.id, layer_id) do
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
    case Maps.get_layer(socket.assigns.map.id, layer_id) do
      nil -> {:noreply, socket}
      layer -> do_delete_layer(socket, layer)
    end
  end

  def handle_toggle_background_upload(_params, socket) do
    {:noreply, assign(socket, :show_background_upload, !socket.assigns.show_background_upload)}
  end

  def handle_remove_background(_params, socket) do
    case Maps.update_map(socket.assigns.map, %{background_asset_id: nil}) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:map, updated)
         |> push_event("background_changed", %{url: nil})}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("maps", "Could not remove background."))}
    end
  end

  def handle_update_map_scale(%{"field" => field} = params, socket)
      when field in ~w(scale_unit scale_value) do
    value = parse_scale_field(field, extract_field_value(params, field))

    case Maps.update_map(socket.assigns.map, %{field => value}) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:map, updated)
         |> assign(:map_data, build_map_data(updated, socket.assigns.can_edit))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("maps", "Could not update map scale."))}
    end
  end

  def handle_toggle_pin_icon_upload(_params, socket) do
    {:noreply, assign(socket, :show_pin_icon_upload, !socket.assigns.show_pin_icon_upload)}
  end

  def handle_remove_pin_icon(_params, socket) do
    pin = socket.assigns.selected_element

    if is_struct(pin, Storyarn.Maps.MapPin) do
      case Maps.update_pin(pin, %{"icon_asset_id" => nil}) do
        {:ok, updated} ->
          updated =
            Storyarn.Repo.preload(updated, [:icon_asset, sheet: :avatar_asset], force: true)

          {:noreply,
           socket
           |> assign(:selected_element, updated)
           |> update_pin_in_list(updated)
           |> assign(:show_pin_icon_upload, false)
           |> push_event("pin_updated", serialize_pin(updated))}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, dgettext("maps", "Could not remove pin icon."))}
      end
    else
      {:noreply, put_flash(socket, :error, dgettext("maps", "No pin selected."))}
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
    case Maps.get_layer(socket.assigns.map.id, id) do
      nil -> socket
      layer -> do_update_layer_name(socket, layer, name)
    end
  end

  defp do_update_layer_name(socket, layer, name) when name == layer.name, do: socket

  defp do_update_layer_name(socket, layer, name) do
    prev_name = layer.name

    case Maps.update_layer(layer, %{"name" => name}) do
      {:ok, _updated} ->
        socket
        |> push_undo({:rename_layer, layer.id, prev_name, name})
        |> put_flash(:info, dgettext("maps", "Layer renamed."))
        |> reload_map()

      {:error, _} ->
        put_flash(socket, :error, dgettext("maps", "Could not rename layer."))
    end
  end

  defp do_toggle_layer_visibility(socket, layer) do
    case Maps.toggle_layer_visibility(layer) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> push_event("layer_visibility_changed", %{id: updated.id, visible: updated.visible})
         |> reload_map()}

      {:error, _} ->
        {:noreply,
         put_flash(socket, :error, dgettext("maps", "Could not toggle layer visibility."))}
    end
  end

  defp normalize_fog_value("fog_enabled", value), do: value in ["true", true]
  defp normalize_fog_value("fog_opacity", value), do: parse_float(value)
  defp normalize_fog_value(_field, value), do: value

  defp do_update_layer_fog(socket, layer, field, value) do
    prev_value = Map.get(layer, String.to_existing_atom(field))

    case Maps.update_layer(layer, %{field => value}) do
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
         |> reload_map()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("maps", "Could not update fog settings."))}
    end
  end

  defp do_delete_layer(socket, layer) do
    case Maps.delete_layer(layer) do
      {:ok, _} ->
        {:noreply,
         socket
         |> push_undo({:delete_layer, layer})
         |> push_event("layer_deleted", %{id: layer.id})
         |> put_flash(:info, dgettext("maps", "Layer deleted."))
         |> reload_map()}

      {:error, :cannot_delete_last_layer} ->
        {:noreply,
         put_flash(socket, :error, dgettext("maps", "Cannot delete the last layer of a map."))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("maps", "Could not delete layer."))}
    end
  end
end
