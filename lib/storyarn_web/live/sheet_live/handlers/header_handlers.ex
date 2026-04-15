defmodule StoryarnWeb.SheetLive.Handlers.HeaderHandlers do
  @moduledoc """
  Handle events for sheet header: name, shortcut, color, banner, avatars.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3]

  use Gettext, backend: Storyarn.Gettext

  alias StoryarnWeb.Helpers.Authorize
  alias Storyarn.Assets
  alias Storyarn.Sheets

  def handle_save_name(%{"name" => name}, socket, helpers) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      sheet = socket.assigns.sheet

      case Sheets.update_sheet(sheet, %{name: name}) do
        {:ok, updated_sheet} ->
          if name != sheet.name do
            Sheets.maybe_create_version(updated_sheet, socket.assigns.current_scope.user.id)
          end

          {:noreply,
           socket
           |> assign(:sheet, Sheets.get_sheet_full!(socket.assigns.project.id, sheet.id))
           |> helpers.broadcast.(:sheet_updated)}

        {:error, _changeset} ->
          {:noreply, socket}
      end
    end)
  end

  def handle_save_shortcut(%{"shortcut" => shortcut}, socket, helpers) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      sheet = socket.assigns.sheet
      shortcut = if shortcut == "", do: nil, else: shortcut

      case Sheets.update_sheet(sheet, %{shortcut: shortcut}) do
        {:ok, _updated_sheet} ->
          updated_sheet = Sheets.get_sheet_full!(socket.assigns.project.id, sheet.id)

          if shortcut != sheet.shortcut do
            Sheets.maybe_create_version(updated_sheet, socket.assigns.current_scope.user.id)
          end

          {:noreply,
           socket
           |> assign(:sheet, updated_sheet)
           |> helpers.broadcast.(:sheet_updated)}

        {:error, changeset} ->
          error_msg =
            case changeset.errors[:shortcut] do
              {msg, _opts} -> dgettext("sheets", "Shortcut %{error}", error: msg)
              nil -> dgettext("sheets", "Could not save shortcut.")
            end

          {:noreply, put_flash(socket, :error, error_msg)}
      end
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
          {:noreply,
           socket |> helpers.reload_sheet.() |> helpers.broadcast.(:sheet_updated)}

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

        {:noreply,
         socket |> helpers.reload_sheet.() |> helpers.broadcast.(:sheet_updated)}
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

        {:noreply,
         socket
         |> helpers.reload_sheet.()
         |> helpers.broadcast.(:sheet_updated)}
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

end
