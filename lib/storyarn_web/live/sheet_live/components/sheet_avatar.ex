defmodule StoryarnWeb.SheetLive.Components.SheetAvatar do
  @moduledoc """
  LiveComponent for the sheet avatar with edit options.
  Handles avatar display, upload, and removal.
  """

  use StoryarnWeb, :live_component
  use StoryarnWeb.Helpers.Authorize

  import StoryarnWeb.Components.SheetComponents

  alias Storyarn.Assets
  alias Storyarn.Assets.BlobStore
  alias Storyarn.Billing
  alias Storyarn.Collaboration
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
                  {dgettext("sheets", "Upload avatar")}
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
                  {dgettext("sheets", "Remove")}
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
    with_edit_authorization(socket, fn socket ->
      sheet = socket.assigns.sheet

      case Sheets.update_sheet(sheet, %{avatar_asset_id: nil}) do
        {:ok, _updated_sheet} ->
          updated_sheet = Sheets.get_sheet_full!(socket.assigns.project.id, sheet.id)
          sheets_tree = Sheets.list_sheets_tree(socket.assigns.project.id)
          send(self(), {:sheet_avatar, :sheet_updated, updated_sheet, sheets_tree})
          {:noreply, assign(socket, :sheet, updated_sheet)}

        {:error, _changeset} ->
          send(self(), {:sheet_avatar, :error, dgettext("sheets", "Could not remove avatar.")})
          {:noreply, socket}
      end
    end)
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
    with_edit_authorization(socket, fn socket ->
      with [_header, base64_data] <- String.split(data, ",", parts: 2),
           {:ok, binary_data} <- Base.decode64(base64_data) do
        upload_avatar_file(socket, filename, content_type, binary_data)
      else
        _ ->
          send(self(), {:sheet_avatar, :error, dgettext("sheets", "Invalid file data.")})
          {:noreply, socket}
      end
    end)
  end

  # ===========================================================================
  # Private Functions
  # ===========================================================================

  defp upload_avatar_file(socket, filename, content_type, binary_data) do
    project = socket.assigns.project

    case Billing.can_upload_asset_for_project?(project, byte_size(binary_data)) do
      :ok ->
        do_upload_avatar_file(socket, project, filename, content_type, binary_data)

      {:error, :limit_reached, _details} ->
        send(
          self(),
          {:sheet_avatar, :error, dgettext("sheets", "Storage limit reached. Upgrade your plan.")}
        )

        {:noreply, socket}
    end
  end

  defp do_upload_avatar_file(socket, project, filename, content_type, binary_data) do
    user = socket.assigns.current_user
    sheet = socket.assigns.sheet
    safe_filename = Assets.sanitize_filename(filename)
    key = Assets.generate_key(project, safe_filename)

    blob_hash = BlobStore.compute_hash(binary_data)
    ext = BlobStore.ext_from_content_type(content_type)
    BlobStore.ensure_blob(project.id, blob_hash, ext, binary_data)

    asset_attrs = %{
      filename: safe_filename,
      content_type: content_type,
      size: byte_size(binary_data),
      key: key,
      blob_hash: blob_hash
    }

    with {:ok, url} <- Assets.storage_upload(key, binary_data, content_type),
         {:ok, asset} <- Assets.create_asset(project, user, Map.put(asset_attrs, :url, url)),
         {:ok, _updated_sheet} <- Sheets.update_sheet(sheet, %{avatar_asset_id: asset.id}) do
      updated_sheet = Sheets.get_sheet_full!(project.id, sheet.id)
      sheets_tree = Sheets.list_sheets_tree(project.id)
      send(self(), {:sheet_avatar, :sheet_updated, updated_sheet, sheets_tree})
      Collaboration.broadcast_change({:assets, project.id}, :asset_created, %{})
      {:noreply, assign(socket, :sheet, updated_sheet)}
    else
      {:error, _reason} ->
        Assets.storage_delete(key)
        send(self(), {:sheet_avatar, :error, dgettext("sheets", "Could not upload avatar.")})
        {:noreply, socket}
    end
  end
end
