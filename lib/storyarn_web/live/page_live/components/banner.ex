defmodule StoryarnWeb.PageLive.Components.Banner do
  @moduledoc """
  LiveComponent for the page banner.
  Handles banner display, upload, and removal.
  """

  use StoryarnWeb, :live_component

  alias Storyarn.Assets
  alias Storyarn.Pages
  alias Storyarn.Repo

  @impl true
  def render(assigns) do
    ~H"""
    <div class={[!@page.banner_asset && !@can_edit && "hidden"]}>
      <%= if @page.banner_asset do %>
        <div class="relative group h-48 sm:h-56 lg:h-64 overflow-hidden rounded-2xl mb-6">
          <img
            src={@page.banner_asset.url}
            alt=""
            class="w-full h-full object-cover"
          />
          <div
            :if={@can_edit}
            class="absolute inset-0 bg-black/0 group-hover:bg-black/30 transition-colors flex items-center justify-center opacity-0 group-hover:opacity-100"
          >
            <div class="flex gap-2">
              <label class="btn btn-sm btn-ghost bg-base-100/80 hover:bg-base-100">
                <.icon name="image" class="size-4" />
                {gettext("Change")}
                <input
                  type="file"
                  accept="image/*"
                  class="hidden"
                  phx-hook="BannerUpload"
                  id="banner-upload-input"
                  data-page-id={@page.id}
                  data-target={@myself}
                />
              </label>
              <button
                type="button"
                class="btn btn-sm btn-ghost bg-base-100/80 hover:bg-base-100"
                phx-click="remove_banner"
                phx-target={@myself}
              >
                <.icon name="trash-2" class="size-4" />
                {gettext("Remove")}
              </button>
            </div>
          </div>
        </div>
      <% else %>
        <div :if={@can_edit} class="flex items-center mb-4">
          <label class="btn btn-ghost btn-sm text-base-content/50 hover:text-base-content">
            <.icon name="image" class="size-4" />
            {gettext("Add cover")}
            <input
              type="file"
              accept="image/*"
              class="hidden"
              phx-hook="BannerUpload"
              id="banner-upload-input-empty"
              data-page-id={@page.id}
              data-target={@myself}
            />
          </label>
        </div>
      <% end %>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  # ===========================================================================
  # Event Handlers
  # ===========================================================================

  @impl true
  def handle_event("remove_banner", _params, socket) do
    page = socket.assigns.page

    case Pages.update_page(page, %{banner_asset_id: nil}) do
      {:ok, updated_page} ->
        updated_page = Repo.preload(updated_page, [:avatar_asset, :banner_asset])
        send(self(), {:banner, :page_updated, updated_page})
        {:noreply, assign(socket, :page, updated_page)}

      {:error, _changeset} ->
        send(self(), {:banner, :error, gettext("Could not remove banner.")})
        {:noreply, socket}
    end
  end

  def handle_event(
        "upload_banner",
        %{"filename" => filename, "content_type" => content_type, "data" => data},
        socket
      ) do
    # Extract binary data from base64 data URL
    [_header, base64_data] = String.split(data, ",", parts: 2)

    case Base.decode64(base64_data) do
      {:ok, binary_data} ->
        upload_banner_file(socket, filename, content_type, binary_data)

      :error ->
        send(self(), {:banner, :error, gettext("Invalid file data.")})
        {:noreply, socket}
    end
  end

  # ===========================================================================
  # Private Functions
  # ===========================================================================

  defp upload_banner_file(socket, filename, content_type, binary_data) do
    project = socket.assigns.project
    user = socket.assigns.current_user
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
      send(self(), {:banner, :page_updated, updated_page})
      {:noreply, assign(socket, :page, updated_page)}
    else
      {:error, _reason} ->
        send(self(), {:banner, :error, gettext("Could not upload banner.")})
        {:noreply, socket}
    end
  end

  defp sanitize_filename(filename) do
    filename
    |> String.split(~r/[\/\\]/)
    |> List.last()
    |> String.replace(~r/[^\w\-\.]/, "_")
    |> String.slice(0, 255)
  end
end
