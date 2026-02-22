defmodule StoryarnWeb.SheetLive.Helpers.AssetHelpers do
  @moduledoc false

  import Phoenix.Component
  import Phoenix.LiveView
  import StoryarnWeb.Helpers.SaveStatusTimer
  use Gettext, backend: StoryarnWeb.Gettext

  alias Storyarn.Assets
  alias Storyarn.Repo
  alias Storyarn.Sheets

  @doc """
  Handles remove_avatar event.
  """
  def remove_avatar(socket) do
    sheet = socket.assigns.sheet

    case Sheets.update_sheet(sheet, %{avatar_asset_id: nil}) do
      {:ok, updated_sheet} ->
        updated_sheet = Repo.preload(updated_sheet, :avatar_asset)
        sheets_tree = Sheets.list_sheets_tree(socket.assigns.project.id)

        {:noreply,
         socket
         |> assign(:sheet, updated_sheet)
         |> assign(:sheets_tree, sheets_tree)
         |> assign(:save_status, :saved)
         |> schedule_reset()}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not remove avatar."))}
    end
  end

  @doc """
  Handles set_avatar event.
  """
  def set_avatar(socket, asset_id) do
    sheet = socket.assigns.sheet

    case Sheets.update_sheet(sheet, %{avatar_asset_id: asset_id}) do
      {:ok, updated_sheet} ->
        updated_sheet = Repo.preload(updated_sheet, :avatar_asset)
        sheets_tree = Sheets.list_sheets_tree(socket.assigns.project.id)

        {:noreply,
         socket
         |> assign(:sheet, updated_sheet)
         |> assign(:sheets_tree, sheets_tree)
         |> assign(:save_status, :saved)
         |> schedule_reset()}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not set avatar."))}
    end
  end

  @doc """
  Handles upload_avatar event.
  """
  def upload_avatar(socket, filename, content_type, data) do
    # Extract binary data from base64 data URL
    [_header, base64_data] = String.split(data, ",", parts: 2)

    case Base.decode64(base64_data) do
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
      {:ok, updated_sheet} ->
        updated_sheet = Repo.preload(updated_sheet, [:avatar_asset, :banner_asset])

        {:noreply,
         socket
         |> assign(:sheet, updated_sheet)
         |> assign(:save_status, :saved)
         |> schedule_reset()}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not remove banner."))}
    end
  end

  @doc """
  Handles upload_banner event.
  """
  def upload_banner(socket, filename, content_type, data) do
    # Extract binary data from base64 data URL
    [_header, base64_data] = String.split(data, ",", parts: 2)

    case Base.decode64(base64_data) do
      {:ok, binary_data} ->
        upload_banner_file(socket, filename, content_type, binary_data)

      :error ->
        {:noreply, put_flash(socket, :error, dgettext("sheets", "Invalid file data."))}
    end
  end

  # Private functions

  defp upload_avatar_file(socket, filename, content_type, binary_data) do
    alias Storyarn.Assets.Asset

    if Asset.allowed_content_type?(content_type) do
      project = socket.assigns.project
      user = socket.assigns.current_scope.user
      sheet = socket.assigns.sheet
      safe_filename = Assets.sanitize_filename(filename)
      key = Assets.generate_key(project, safe_filename)

      asset_attrs = %{
        filename: safe_filename,
        content_type: content_type,
        size: byte_size(binary_data),
        key: key
      }

      with {:ok, url} <- Assets.Storage.upload(key, binary_data, content_type),
           {:ok, asset} <- Assets.create_asset(project, user, Map.put(asset_attrs, :url, url)),
           {:ok, updated_sheet} <- Sheets.update_sheet(sheet, %{avatar_asset_id: asset.id}) do
        updated_sheet = Repo.preload(updated_sheet, :avatar_asset)
        sheets_tree = Sheets.list_sheets_tree(project.id)

        {:noreply,
         socket
         |> assign(:sheet, updated_sheet)
         |> assign(:sheets_tree, sheets_tree)
         |> assign(:save_status, :saved)
         |> schedule_reset()}
      else
        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not upload avatar."))}
      end
    else
      {:noreply, put_flash(socket, :error, dgettext("sheets", "Unsupported file type."))}
    end
  end

  defp upload_banner_file(socket, filename, content_type, binary_data) do
    alias Storyarn.Assets.Asset

    if Asset.allowed_content_type?(content_type) do
      project = socket.assigns.project
      user = socket.assigns.current_scope.user
      sheet = socket.assigns.sheet
      safe_filename = Assets.sanitize_filename(filename)
      key = Assets.generate_key(project, safe_filename)

      asset_attrs = %{
        filename: safe_filename,
        content_type: content_type,
        size: byte_size(binary_data),
        key: key
      }

      with {:ok, url} <- Assets.Storage.upload(key, binary_data, content_type),
           {:ok, asset} <- Assets.create_asset(project, user, Map.put(asset_attrs, :url, url)),
           {:ok, updated_sheet} <- Sheets.update_sheet(sheet, %{banner_asset_id: asset.id}) do
        updated_sheet = Repo.preload(updated_sheet, [:avatar_asset, :banner_asset])

        {:noreply,
         socket
         |> assign(:sheet, updated_sheet)
         |> assign(:save_status, :saved)
         |> schedule_reset()}
      else
        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not upload banner."))}
      end
    else
      {:noreply, put_flash(socket, :error, dgettext("sheets", "Unsupported file type."))}
    end
  end
end
