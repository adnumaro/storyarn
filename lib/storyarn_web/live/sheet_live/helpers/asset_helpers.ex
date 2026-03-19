defmodule StoryarnWeb.SheetLive.Helpers.AssetHelpers do
  @moduledoc false

  import Phoenix.Component
  import Phoenix.LiveView
  import StoryarnWeb.Helpers.SaveStatusTimer
  use Gettext, backend: Storyarn.Gettext

  alias Storyarn.Assets
  alias Storyarn.Sheets

  @doc """
  Handles remove_avatar event.
  Removes the default avatar from the sheet's avatars list.
  """
  def remove_avatar(socket) do
    sheet = socket.assigns.sheet

    case Sheets.get_default_avatar(sheet.id) do
      nil ->
        {:noreply, socket}

      avatar ->
        case Sheets.remove_avatar(avatar.id) do
          {:ok, _} ->
            updated_sheet = Sheets.get_sheet_full!(socket.assigns.project.id, sheet.id)
            sheets_tree = Sheets.list_sheets_tree(socket.assigns.project.id)

            {:noreply,
             socket
             |> assign(:sheet, updated_sheet)
             |> assign(:sheets_tree, sheets_tree)
             |> mark_saved()}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not remove avatar."))}
        end
    end
  end

  @doc """
  Handles set_avatar event.
  Adds an asset as the default avatar for the sheet.
  """
  def set_avatar(socket, asset_id) do
    sheet = socket.assigns.sheet

    case Sheets.add_avatar(sheet, asset_id) do
      {:ok, avatar} ->
        # Set the newly added avatar as the default
        Sheets.set_avatar_default(avatar)

        updated_sheet = Sheets.get_sheet_full!(socket.assigns.project.id, sheet.id)
        sheets_tree = Sheets.list_sheets_tree(socket.assigns.project.id)

        {:noreply,
         socket
         |> assign(:sheet, updated_sheet)
         |> assign(:sheets_tree, sheets_tree)
         |> mark_saved()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not set avatar."))}
    end
  end

  @doc """
  Handles upload_avatar event.
  """
  def upload_avatar(socket, filename, content_type, data) do
    case decode_data_url(data) do
      {:ok, binary_data} ->
        upload_avatar_file(socket, filename, content_type, binary_data)

      :error ->
        {:noreply, put_flash(socket, :error, dgettext("sheets", "Invalid file data."))}
    end
  end

  @doc """
  Handles remove_banner event.
  """
  def remove_banner(socket) do
    sheet = socket.assigns.sheet

    case Sheets.update_sheet(sheet, %{banner_asset_id: nil}) do
      {:ok, _updated_sheet} ->
        updated_sheet = Sheets.get_sheet_full!(socket.assigns.project.id, sheet.id)

        {:noreply,
         socket
         |> assign(:sheet, updated_sheet)
         |> mark_saved()}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not remove banner."))}
    end
  end

  @doc """
  Handles upload_banner event.
  """
  def upload_banner(socket, filename, content_type, data) do
    case decode_data_url(data) do
      {:ok, binary_data} ->
        upload_banner_file(socket, filename, content_type, binary_data)

      :error ->
        {:noreply, put_flash(socket, :error, dgettext("sheets", "Invalid file data."))}
    end
  end

  # Private functions

  defp decode_data_url(data) do
    case String.split(data, ",", parts: 2) do
      [_header, base64_data] -> Base.decode64(base64_data)
      _ -> :error
    end
  end

  defp upload_avatar_file(socket, filename, content_type, binary_data) do
    if Assets.allowed_content_type?(content_type) do
      project = socket.assigns.project
      user = socket.assigns.current_scope.user
      sheet = socket.assigns.sheet
      attrs = %{filename: filename, content_type: content_type}

      with {:ok, asset} <-
             Assets.upload_binary_and_create_asset(binary_data, attrs, project, user),
           {:ok, avatar} <- Sheets.add_avatar(sheet, asset.id),
           {:ok, _} <- Sheets.set_avatar_default(avatar) do
        updated_sheet = Sheets.get_sheet_full!(project.id, sheet.id)
        sheets_tree = Sheets.list_sheets_tree(project.id)

        {:noreply,
         socket
         |> assign(:sheet, updated_sheet)
         |> assign(:sheets_tree, sheets_tree)
         |> mark_saved()}
      else
        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not upload avatar."))}
      end
    else
      {:noreply, put_flash(socket, :error, dgettext("sheets", "Unsupported file type."))}
    end
  end

  defp upload_banner_file(socket, filename, content_type, binary_data) do
    if Assets.allowed_content_type?(content_type) do
      project = socket.assigns.project
      user = socket.assigns.current_scope.user
      sheet = socket.assigns.sheet
      attrs = %{filename: filename, content_type: content_type}

      with {:ok, asset} <-
             Assets.upload_binary_and_create_asset(binary_data, attrs, project, user),
           {:ok, _updated_sheet} <- Sheets.update_sheet(sheet, %{banner_asset_id: asset.id}) do
        updated_sheet = Sheets.get_sheet_full!(project.id, sheet.id)

        {:noreply,
         socket
         |> assign(:sheet, updated_sheet)
         |> mark_saved()}
      else
        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not upload banner."))}
      end
    else
      {:noreply, put_flash(socket, :error, dgettext("sheets", "Unsupported file type."))}
    end
  end
end
