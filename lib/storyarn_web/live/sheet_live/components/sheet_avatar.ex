defmodule StoryarnWeb.SheetLive.Components.SheetAvatar do
  @moduledoc """
  LiveComponent for sheet avatar management.
  Film strip popover + JS ImageGallery hook overlay for detailed editing.
  """

  use StoryarnWeb, :live_component
  alias StoryarnWeb.Helpers.Authorize

  import StoryarnWeb.Components.UIComponents, only: [optimization_warning_dialog: 1]

  alias Storyarn.Assets
  alias Storyarn.Billing
  alias Storyarn.Collaboration
  alias Storyarn.Sheets

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <%!-- Main avatar with click → strip popover --%>
      <div class="dropdown dropdown-bottom">
        <div tabindex="0" role="button" class="cursor-pointer">
          <div class="relative group">
            <%= if @default_avatar && @default_avatar.asset do %>
              <img
                src={Assets.display_url(@default_avatar.asset)}
                alt={@sheet.name}
                class="size-20 rounded object-cover"
              />
            <% else %>
              <div class="size-20 rounded bg-base-300 flex items-center justify-center">
                <.icon name="file" class="size-8 opacity-40" />
              </div>
            <% end %>
          </div>
        </div>

        <%!-- Film strip popover --%>
        <div
          :if={@can_edit}
          tabindex="0"
          class="dropdown-content z-50 bg-base-200 border border-base-300 rounded-lg shadow-lg p-3 mt-1"
        >
          <div class="grid grid-cols-3 gap-2" style="width: 16.5rem;">
            <div :for={avatar <- @avatars} class="flex flex-col items-center">
              <div class={[
                "relative group/thumb size-20 rounded-lg overflow-hidden border-2 transition-colors",
                if(avatar.is_default,
                  do: "border-primary",
                  else: "border-base-content/10 hover:border-base-content/30"
                )
              ]}>
                <button
                  :if={avatar.asset}
                  type="button"
                  phx-click="set_default"
                  phx-value-id={avatar.id}
                  phx-target={@myself}
                  class="w-full h-full"
                >
                  <img
                    src={Assets.display_url(avatar.asset)}
                    alt={avatar.name || ""}
                    class="w-full h-full object-cover"
                  />
                </button>
                <button
                  type="button"
                  phx-click="remove_avatar"
                  phx-value-id={avatar.id}
                  phx-target={@myself}
                  class="absolute top-0 right-0 size-4 bg-black/70 rounded-bl flex items-center justify-center opacity-0 group-hover/thumb:opacity-100 transition-opacity z-10"
                >
                  <.icon name="x" class="size-2.5 text-white" />
                </button>
              </div>
              <span class="text-[10px] text-base-content/50 truncate max-w-full mt-0.5">
                {avatar.name || ""}
              </span>
            </div>

            <div class="flex flex-col items-center">
              <label
                for="avatar-upload-input"
                class="size-20 rounded-lg border-2 border-dashed border-base-content/20 hover:border-base-content/40 flex items-center justify-center cursor-pointer transition-colors"
              >
                <.icon name="plus" class="size-5 text-base-content/40" />
              </label>
            </div>
          </div>

          <button
            :if={@avatars != []}
            type="button"
            phx-click={JS.dispatch("open-gallery", to: "#avatar-gallery-#{@sheet.id}")}
            class="flex items-center justify-center gap-1.5 w-full mt-2 pt-2 border-t border-base-content/10 text-xs text-base-content/50 hover:text-base-content transition-colors cursor-pointer"
          >
            <.icon name="layout-grid" class="size-3.5" />
            {dgettext("sheets", "Gallery")}
          </button>
        </div>
      </div>

      <%!-- Gallery (pure JS hook overlay) --%>
      <div
        :if={@can_edit}
        phx-hook="ImageGallery"
        id={"avatar-gallery-#{@sheet.id}"}
        data-items={Jason.encode!(to_gallery_items(@avatars))}
        data-can-edit={to_string(@can_edit)}
        data-target={"##{@id}"}
        data-title={dgettext("sheets", "Avatar Gallery")}
        data-name-placeholder={dgettext("sheets", "e.g. happy, angry, combat...")}
        data-notes-placeholder={dgettext("sheets", "Voice direction, art notes...")}
        data-upload-input-id="avatar-upload-input"
        data-empty-message={dgettext("sheets", "No avatars yet. Upload one to get started.")}
        data-upload-label={dgettext("sheets", "Add avatar")}
        data-name-label={dgettext("sheets", "Name")}
        data-notes-label={dgettext("sheets", "Notes")}
        data-delete-text={dgettext("sheets", "Delete")}
        data-set-default-text={dgettext("sheets", "Set as default")}
        data-default-badge-text={dgettext("sheets", "default")}
        data-default-label-text={dgettext("sheets", "Default")}
      />

      <%!-- Shared file input --%>
      <input
        :if={@can_edit}
        type="file"
        accept="image/*"
        multiple
        class="hidden"
        phx-hook="AvatarUpload"
        id="avatar-upload-input"
        data-sheet-id={@sheet.id}
        data-target={@myself}
      />

      <.optimization_warning_dialog
        id="optimization-warning-avatar"
        message={
          dgettext(
            "sheets",
            "For best results, upload a 192\u00D7192 WebP or JPEG image. Larger or PNG images will be automatically converted, and the optimized copy will count toward your storage limit."
          )
        }
      />
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    avatars = if is_list(assigns.sheet.avatars), do: assigns.sheet.avatars, else: []
    sorted = Enum.sort_by(avatars, & &1.position)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:avatars, sorted)
     |> assign(:default_avatar, Enum.find(avatars, & &1.is_default))}
  end

  # ===========================================================================
  # Event Handlers
  # ===========================================================================

  @impl true
  def handle_event("set_default", %{"id" => id}, socket) do
    Authorize.with_edit_authorization(socket, fn socket ->
      case get_owned_avatar(socket, id) do
        {:ok, avatar} ->
          Sheets.set_avatar_default(avatar)
          reload_and_notify(socket)

        {:error, _} ->
          {:noreply, socket}
      end
    end)
  end

  def handle_event("remove_avatar", %{"id" => id}, socket) do
    Authorize.with_edit_authorization(socket, fn socket ->
      case get_owned_avatar(socket, id) do
        {:ok, avatar} -> do_remove_avatar(socket, avatar)
        {:error, _} -> {:noreply, socket}
      end
    end)
  end

  # Gallery hook events (pushEventTo from JS)
  def handle_event("gallery_update_name", %{"id" => id, "value" => value}, socket) do
    Authorize.with_edit_authorization(socket, fn socket ->
      case get_owned_avatar(socket, id) do
        {:ok, avatar} ->
          Sheets.update_avatar(avatar, %{name: value})
          {:noreply, socket}

        {:error, _} ->
          {:noreply, socket}
      end
    end)
  end

  def handle_event("gallery_update_notes", %{"id" => id, "value" => value}, socket) do
    Authorize.with_edit_authorization(socket, fn socket ->
      case get_owned_avatar(socket, id) do
        {:ok, avatar} ->
          Sheets.update_avatar(avatar, %{notes: value})
          {:noreply, socket}

        {:error, _} ->
          {:noreply, socket}
      end
    end)
  end

  def handle_event("gallery_delete", %{"id" => id}, socket) do
    Authorize.with_edit_authorization(socket, fn socket ->
      case get_owned_avatar(socket, id) do
        {:ok, avatar} -> do_remove_avatar(socket, avatar)
        {:error, _} -> {:noreply, socket}
      end
    end)
  end

  def handle_event("gallery_set_default", %{"id" => id}, socket) do
    Authorize.with_edit_authorization(socket, fn socket ->
      case get_owned_avatar(socket, id) do
        {:ok, avatar} ->
          Sheets.set_avatar_default(avatar)
          reload_and_notify(socket)

        {:error, _} ->
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
    Authorize.with_edit_authorization(socket, fn socket ->
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

  defp to_gallery_items(avatars) do
    Enum.map(avatars, fn a ->
      %{
        id: a.id,
        url: Assets.display_url(a.asset),
        original_url: a.asset && a.asset.url,
        name: a.name,
        notes: a.notes,
        filename: a.asset && a.asset.filename,
        is_default: a.is_default
      }
    end)
  end

  defp do_remove_avatar(socket, avatar) do
    case Sheets.remove_avatar(avatar.id) do
      {:ok, _} ->
        reload_and_notify(socket)

      {:error, _} ->
        send(self(), {:sheet_avatar, :error, dgettext("sheets", "Could not remove avatar.")})
        {:noreply, socket}
    end
  end

  defp get_owned_avatar(socket, id) do
    id = if is_binary(id), do: String.to_integer(id), else: id
    avatar = Sheets.get_avatar(id)

    if avatar && avatar.sheet_id == socket.assigns.sheet.id do
      {:ok, avatar}
    else
      {:error, :not_owned}
    end
  end

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

    with {:ok, asset} <-
           Assets.upload_binary_and_create_asset(
             binary_data,
             %{filename: filename, content_type: content_type, purpose: :avatar},
             project,
             user
           ),
         {:ok, _avatar} <- Sheets.add_avatar(sheet, asset.id) do
      Collaboration.broadcast_change({:assets, project.id}, :asset_created, %{})
      reload_and_notify(socket)
    else
      {:error, _reason} ->
        send(self(), {:sheet_avatar, :error, dgettext("sheets", "Could not upload avatar.")})
        {:noreply, socket}
    end
  end

  defp reload_and_notify(socket) do
    project = socket.assigns.project
    sheet = socket.assigns.sheet
    updated_sheet = Sheets.get_sheet_full!(project.id, sheet.id)
    sheets_tree = Sheets.list_sheets_tree(project.id)
    send(self(), {:sheet_avatar, :sheet_updated, updated_sheet, sheets_tree})
    {:noreply, assign(socket, :sheet, updated_sheet)}
  end
end
