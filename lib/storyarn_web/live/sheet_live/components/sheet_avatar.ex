defmodule StoryarnWeb.SheetLive.Components.SheetAvatar do
  @moduledoc """
  LiveComponent for the sheet avatar with edit options.
  Handles avatar display, upload, and removal.
  """

  use StoryarnWeb, :live_component

  import StoryarnWeb.Components.SheetComponents

  alias Storyarn.Assets
  alias Storyarn.Repo
  alias Storyarn.Sheets

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <%= if @can_edit do %>
        <div class="relative group">
          <div class="dropdown">
            <div tabindex="0" role="button" class="cursor-pointer">
              <.sheet_avatar avatar_asset={@sheet.avatar_asset} name={@sheet.name} size="xl" />
              <div class="absolute inset-0 bg-black/50 opacity-0 group-hover:opacity-100 rounded flex items-center justify-center transition-opacity">
                <.icon name="camera" class="size-4 text-white" />
              </div>
            </div>
            <ul
              tabindex="0"
              class="dropdown-content menu menu-sm bg-base-100 rounded-box shadow-lg border border-base-300 w-40 z-50"
            >
              <li>
                <label class="cursor-pointer">
                  <.icon name="upload" class="size-4" />
                  {gettext("Upload avatar")}
                  <input
                    type="file"
                    accept="image/*"
                    class="hidden"
                    phx-hook="AvatarUpload"
                    id="avatar-upload-input"
                    data-sheet-id={@sheet.id}
                    data-target={@myself}
                  />
                </label>
              </li>
              <li :if={@sheet.avatar_asset}>
                <button
                  type="button"
                  class="text-error"
                  phx-click="remove_avatar"
                  phx-target={@myself}
                >
                  <.icon name="trash-2" class="size-4" />
                  {gettext("Remove")}
                </button>
              </li>
            </ul>
          </div>
        </div>
      <% else %>
        <.sheet_avatar avatar_asset={@sheet.avatar_asset} name={@sheet.name} size="xl" />
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
  def handle_event("remove_avatar", _params, socket) do
    sheet = socket.assigns.sheet

    case Sheets.update_sheet(sheet, %{avatar_asset_id: nil}) do
      {:ok, updated_sheet} ->
        updated_sheet = Repo.preload(updated_sheet, :avatar_asset, force: true)
        sheets_tree = Sheets.list_sheets_tree(socket.assigns.project.id)
        send(self(), {:sheet_avatar, :sheet_updated, updated_sheet, sheets_tree})
        {:noreply, assign(socket, :sheet, updated_sheet)}

      {:error, _changeset} ->
        send(self(), {:sheet_avatar, :error, gettext("Could not remove avatar.")})
        {:noreply, socket}
    end
  end

  def handle_event("upload_validation_error", %{"message" => message}, socket) do
    send(self(), {:sheet_avatar, :error, message})
    {:noreply, socket}
  end

  def handle_event(
        "upload_avatar",
        %{"filename" => filename, "content_type" => content_type, "data" => data},
        socket
      ) do
    # Extract binary data from base64 data URL
    [_header, base64_data] = String.split(data, ",", parts: 2)

    case Base.decode64(base64_data) do
      {:ok, binary_data} ->
        upload_avatar_file(socket, filename, content_type, binary_data)

      :error ->
        send(self(), {:sheet_avatar, :error, gettext("Invalid file data.")})
        {:noreply, socket}
    end
  end

  # ===========================================================================
  # Private Functions
  # ===========================================================================

  defp upload_avatar_file(socket, filename, content_type, binary_data) do
    project = socket.assigns.project
    user = socket.assigns.current_user
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
      updated_sheet = Repo.preload(updated_sheet, :avatar_asset, force: true)
      sheets_tree = Sheets.list_sheets_tree(project.id)
      send(self(), {:sheet_avatar, :sheet_updated, updated_sheet, sheets_tree})
      {:noreply, assign(socket, :sheet, updated_sheet)}
    else
      {:error, _reason} ->
        send(self(), {:sheet_avatar, :error, gettext("Could not upload avatar.")})
        {:noreply, socket}
    end
  end

end
