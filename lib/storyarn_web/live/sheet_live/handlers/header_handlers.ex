defmodule StoryarnWeb.SheetLive.Handlers.HeaderHandlers do
  @moduledoc """
  Handle events for sheet header: name, shortcut, color, banner, avatars.
  """

  use Gettext, backend: Storyarn.Gettext

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3]

  alias Storyarn.Assets
  alias Storyarn.Sheets
  alias StoryarnWeb.Helpers.Authorize

  def handle_save_name(%{"name" => name}, socket, helpers) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      save_name(socket, name, helpers)
    end)
  end

  def handle_save_shortcut(%{"shortcut" => shortcut}, socket, helpers) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      save_shortcut(socket, normalize_shortcut(shortcut), helpers)
    end)
  end

  def handle_set_color(%{"color" => color}, socket, helpers) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      update_sheet_field(socket, %{color: color}, helpers)
    end)
  end

  def handle_clear_color(_params, socket, helpers) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      update_sheet_field(socket, %{color: nil}, helpers)
    end)
  end

  def handle_remove_banner(_params, socket, helpers) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      sheet = socket.assigns.sheet

      case Sheets.update_sheet(sheet, %{banner_asset_id: nil}) do
        {:ok, _} ->
          {:noreply, socket |> helpers.reload_sheet.() |> helpers.broadcast.(:sheet_updated)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not remove banner."))}
      end
    end)
  end

  def handle_remove_avatar(%{"id" => id}, socket, helpers) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      id = helpers.parse_id.(id)

      case Sheets.remove_avatar(socket.assigns.sheet.id, id) do
        {:ok, _} ->
          {:noreply, reload_broadcast_and_refresh_tree(socket, helpers)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not remove avatar."))}
      end
    end)
  end

  def handle_set_default_avatar(%{"id" => id}, socket, helpers) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      id = helpers.parse_id.(id)
      avatar = Sheets.get_avatar(id)

      if avatar && avatar.sheet_id == socket.assigns.sheet.id do
        Sheets.set_avatar_default(avatar)

        {:noreply, reload_broadcast_and_refresh_tree(socket, helpers)}
      else
        {:noreply, socket}
      end
    end)
  end

  def handle_gallery_update_name(%{"id" => id, "value" => value}, socket, helpers) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      with avatar when not is_nil(avatar) <- Sheets.get_avatar(helpers.parse_id.(id)),
           true <- avatar.sheet_id == socket.assigns.sheet.id do
        Sheets.update_avatar(avatar, %{name: value})
        {:noreply, socket |> helpers.reload_sheet.() |> helpers.broadcast.(:sheet_updated)}
      else
        _ -> {:noreply, socket}
      end
    end)
  end

  def handle_gallery_update_notes(%{"id" => id, "value" => value}, socket, helpers) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      with avatar when not is_nil(avatar) <- Sheets.get_avatar(helpers.parse_id.(id)),
           true <- avatar.sheet_id == socket.assigns.sheet.id do
        Sheets.update_avatar(avatar, %{notes: value})
        {:noreply, socket |> helpers.reload_sheet.() |> helpers.broadcast.(:sheet_updated)}
      else
        _ -> {:noreply, socket}
      end
    end)
  end

  # --- Attach pre-uploaded assets (from multipart upload controller) ---

  def handle_attach_banner(%{"asset_id" => asset_id}, socket, helpers) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      attach_asset(socket, asset_id, :banner, helpers)
    end)
  end

  def handle_attach_avatar(%{"asset_id" => asset_id}, socket, helpers) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      attach_asset(socket, asset_id, :avatar, helpers)
    end)
  end

  defp attach_asset(socket, asset_id, purpose, helpers) do
    sheet = socket.assigns.sheet
    project = socket.assigns.project

    case Assets.get_asset(project.id, asset_id) do
      nil ->
        {:noreply, put_flash(socket, :error, dgettext("sheets", "Asset not found."))}

      _asset ->
        case purpose do
          :banner -> Sheets.update_sheet(sheet, %{banner_asset_id: asset_id})
          :avatar -> Sheets.add_avatar(sheet, asset_id)
        end

        socket =
          if purpose == :avatar do
            reload_broadcast_and_refresh_tree(socket, helpers)
          else
            socket
            |> helpers.reload_sheet.()
            |> helpers.broadcast.(:sheet_updated)
          end

        {:noreply, socket}
    end
  end

  # --- Shared helpers used by header event delegates ---

  def update_sheet_field(socket, attrs, helpers) do
    case Sheets.update_sheet(socket.assigns.sheet, attrs) do
      {:ok, _} ->
        {:noreply,
         socket
         |> helpers.reload_sheet.()
         |> helpers.broadcast.(:sheet_updated)}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  defp save_name(socket, name, helpers) do
    sheet = socket.assigns.sheet

    case Sheets.update_sheet(sheet, %{name: name}) do
      {:ok, updated_sheet} ->
        {:noreply, after_sheet_name_saved(socket, sheet, updated_sheet, name, helpers)}

      {:error, _changeset} ->
        {:noreply, socket}
    end
  end

  defp after_sheet_name_saved(socket, previous_sheet, updated_sheet, name, helpers) do
    changed? = name != previous_sheet.name

    maybe_create_sheet_version(changed?, updated_sheet, socket)

    socket =
      socket
      |> reload_sheet_assign(previous_sheet.id)
      |> helpers.broadcast.(:sheet_updated)

    maybe_broadcast_tree_changed(changed?, socket.assigns.project.id)

    socket
  end

  defp save_shortcut(socket, shortcut, helpers) do
    sheet = socket.assigns.sheet

    case Sheets.update_sheet(sheet, %{shortcut: shortcut}) do
      {:ok, _updated_sheet} ->
        {:noreply, after_sheet_shortcut_saved(socket, sheet, shortcut, helpers)}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, shortcut_error_message(changeset))}
    end
  end

  defp after_sheet_shortcut_saved(socket, previous_sheet, shortcut, helpers) do
    updated_sheet = Sheets.get_sheet_full!(socket.assigns.project.id, previous_sheet.id)
    changed? = shortcut != previous_sheet.shortcut

    maybe_create_sheet_version(changed?, updated_sheet, socket)

    socket
    |> assign(:sheet, updated_sheet)
    |> helpers.broadcast.(:sheet_updated)
  end

  defp normalize_shortcut(""), do: nil
  defp normalize_shortcut(shortcut), do: shortcut

  defp reload_sheet_assign(socket, sheet_id) do
    assign(socket, :sheet, Sheets.get_sheet_full!(socket.assigns.project.id, sheet_id))
  end

  defp reload_broadcast_and_refresh_tree(socket, helpers) do
    socket =
      socket
      |> helpers.reload_sheet.()
      |> helpers.broadcast.(:sheet_updated)

    helpers.broadcast_tree_changed.(socket.assigns.project.id)

    socket
  end

  defp maybe_create_sheet_version(true, sheet, socket) do
    Sheets.maybe_create_version(sheet, socket.assigns.current_scope.user.id)
  end

  defp maybe_create_sheet_version(false, _sheet, _socket), do: :ok

  defp maybe_broadcast_tree_changed(true, project_id) do
    Phoenix.PubSub.broadcast(
      Storyarn.PubSub,
      StoryarnWeb.SheetsSidebarLive.shell_topic(project_id),
      {:tree_changed, :sheets}
    )
  end

  defp maybe_broadcast_tree_changed(false, _project_id), do: :ok

  defp shortcut_error_message(changeset) do
    case changeset.errors[:shortcut] do
      {msg, _opts} -> dgettext("sheets", "Shortcut %{error}", error: msg)
      nil -> dgettext("sheets", "Could not save shortcut.")
    end
  end
end
