defmodule StoryarnWeb.SheetLive.Handlers.HeaderHandlers do
  @moduledoc """
  Handle events for sheet header: name, shortcut, color, banner, avatars.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3]

  use Gettext, backend: Storyarn.Gettext

  alias StoryarnWeb.Helpers.Authorize
  alias Storyarn.Assets
  alias Storyarn.Billing
  alias Storyarn.Collaboration
  alias Storyarn.Sheets

  def handle_save_name(%{"name" => name}, socket, helpers) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      sheet = socket.assigns.sheet

      case Sheets.update_sheet(sheet, %{name: name}) do
        {:ok, updated_sheet} ->
          sheets_tree = helpers.prepare_tree.(socket.assigns.project.id)

          if name != sheet.name do
            Sheets.maybe_create_version(updated_sheet, socket.assigns.current_scope.user.id)
          end

          {:noreply,
           socket
           |> assign(:sheet, Sheets.get_sheet_full!(socket.assigns.project.id, sheet.id))
           |> assign(:sheets_tree, sheets_tree)
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

  def handle_upload_banner(
        %{"filename" => filename, "content_type" => content_type, "data" => data},
        socket,
        helpers
      ) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      with [_header, base64_data] <- String.split(data, ",", parts: 2),
           {:ok, binary_data} <- Base.decode64(base64_data) do
        upload_asset(socket, filename, content_type, binary_data, :banner, helpers)
      else
        _ ->
          {:noreply, put_flash(socket, :error, dgettext("sheets", "Invalid file data."))}
      end
    end)
  end

  def handle_upload_avatar(
        %{"filename" => filename, "content_type" => content_type, "data" => data},
        socket,
        helpers
      ) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      with [_header, base64_data] <- String.split(data, ",", parts: 2),
           {:ok, binary_data} <- Base.decode64(base64_data) do
        upload_asset(socket, filename, content_type, binary_data, :avatar, helpers)
      else
        _ ->
          {:noreply, put_flash(socket, :error, dgettext("sheets", "Invalid file data."))}
      end
    end)
  end

  def handle_remove_avatar(%{"id" => id}, socket, helpers) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      id = helpers.parse_id.(id)

      case Sheets.remove_avatar(socket.assigns.sheet.id, id) do
        {:ok, _} ->
          {:noreply,
           socket |> helpers.reload_sheet_and_tree.() |> helpers.broadcast.(:sheet_updated)}

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
         socket |> helpers.reload_sheet_and_tree.() |> helpers.broadcast.(:sheet_updated)}
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

  def upload_asset(socket, filename, content_type, binary_data, purpose, helpers) do
    project = socket.assigns.project

    case Billing.can_upload_asset_for_project?(project, byte_size(binary_data)) do
      :ok ->
        user = socket.assigns.current_scope.user
        sheet = socket.assigns.sheet

        case Assets.upload_binary_and_create_asset(
               binary_data,
               %{filename: filename, content_type: content_type, purpose: purpose},
               project,
               user
             ) do
          {:ok, asset} ->
            case purpose do
              :banner -> Sheets.update_sheet(sheet, %{banner_asset_id: asset.id})
              :avatar -> Sheets.add_avatar(sheet, asset.id)
            end

            Collaboration.broadcast_change({:assets, project.id}, :asset_created, %{})

            {:noreply,
             socket
             |> helpers.reload_sheet_and_tree.()
             |> helpers.broadcast.(:sheet_updated)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not upload file."))}
        end

      {:error, :limit_reached, _} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("sheets", "Storage limit reached. Upgrade your plan.")
         )}
    end
  end
end
