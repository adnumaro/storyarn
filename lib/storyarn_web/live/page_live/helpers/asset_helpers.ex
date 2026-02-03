defmodule StoryarnWeb.PageLive.Helpers.AssetHelpers do
  @moduledoc false

  import Phoenix.Component
  import Phoenix.LiveView
  use Gettext, backend: StoryarnWeb.Gettext

  alias Storyarn.Assets
  alias Storyarn.Pages
  alias Storyarn.Repo

  @doc """
  Handles remove_avatar event.
  """
  def remove_avatar(socket) do
    page = socket.assigns.page

    case Pages.update_page(page, %{avatar_asset_id: nil}) do
      {:ok, updated_page} ->
        updated_page = Repo.preload(updated_page, :avatar_asset)
        pages_tree = Pages.list_pages_tree(socket.assigns.project.id)

        {:noreply,
         socket
         |> assign(:page, updated_page)
         |> assign(:pages_tree, pages_tree)
         |> assign(:save_status, :saved)
         |> schedule_save_status_reset()}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, gettext("Could not remove avatar."))}
    end
  end

  @doc """
  Handles set_avatar event.
  """
  def set_avatar(socket, asset_id) do
    page = socket.assigns.page

    case Pages.update_page(page, %{avatar_asset_id: asset_id}) do
      {:ok, updated_page} ->
        updated_page = Repo.preload(updated_page, :avatar_asset)
        pages_tree = Pages.list_pages_tree(socket.assigns.project.id)

        {:noreply,
         socket
         |> assign(:page, updated_page)
         |> assign(:pages_tree, pages_tree)
         |> assign(:save_status, :saved)
         |> schedule_save_status_reset()}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, gettext("Could not set avatar."))}
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
        {:noreply, put_flash(socket, :error, gettext("Invalid file data."))}
    end
  end

  @doc """
  Handles remove_banner event.
  """
  def remove_banner(socket) do
    page = socket.assigns.page

    case Pages.update_page(page, %{banner_asset_id: nil}) do
      {:ok, updated_page} ->
        updated_page = Repo.preload(updated_page, [:avatar_asset, :banner_asset])

        {:noreply,
         socket
         |> assign(:page, updated_page)
         |> assign(:save_status, :saved)
         |> schedule_save_status_reset()}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, gettext("Could not remove banner."))}
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
        {:noreply, put_flash(socket, :error, gettext("Invalid file data."))}
    end
  end

  # Private functions

  defp upload_avatar_file(socket, filename, content_type, binary_data) do
    project = socket.assigns.project
    user = socket.assigns.current_scope.user
    page = socket.assigns.page
    safe_filename = sanitize_filename(filename)
    key = Assets.generate_key(project, safe_filename)

    asset_attrs = %{
      filename: safe_filename,
      content_type: content_type,
      size: byte_size(binary_data),
      key: key
    }

    with {:ok, url} <- Assets.Storage.upload(key, binary_data, content_type),
         {:ok, asset} <- Assets.create_asset(project, user, Map.put(asset_attrs, :url, url)),
         {:ok, updated_page} <- Pages.update_page(page, %{avatar_asset_id: asset.id}) do
      updated_page = Repo.preload(updated_page, :avatar_asset)
      pages_tree = Pages.list_pages_tree(project.id)

      {:noreply,
       socket
       |> assign(:page, updated_page)
       |> assign(:pages_tree, pages_tree)
       |> assign(:save_status, :saved)
       |> schedule_save_status_reset()}
    else
      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Could not upload avatar."))}
    end
  end

  defp upload_banner_file(socket, filename, content_type, binary_data) do
    project = socket.assigns.project
    user = socket.assigns.current_scope.user
    page = socket.assigns.page
    safe_filename = sanitize_filename(filename)
    key = Assets.generate_key(project, safe_filename)

    asset_attrs = %{
      filename: safe_filename,
      content_type: content_type,
      size: byte_size(binary_data),
      key: key
    }

    with {:ok, url} <- Assets.Storage.upload(key, binary_data, content_type),
         {:ok, asset} <- Assets.create_asset(project, user, Map.put(asset_attrs, :url, url)),
         {:ok, updated_page} <- Pages.update_page(page, %{banner_asset_id: asset.id}) do
      updated_page = Repo.preload(updated_page, [:avatar_asset, :banner_asset])

      {:noreply,
       socket
       |> assign(:page, updated_page)
       |> assign(:save_status, :saved)
       |> schedule_save_status_reset()}
    else
      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Could not upload banner."))}
    end
  end

  defp sanitize_filename(filename) do
    filename
    |> String.split(~r/[\/\\]/)
    |> List.last()
    |> String.replace(~r/[^\w\-\.]/, "_")
    |> String.slice(0, 255)
  end

  defp schedule_save_status_reset(socket) do
    Process.send_after(self(), :reset_save_status, 4000)
    socket
  end
end
