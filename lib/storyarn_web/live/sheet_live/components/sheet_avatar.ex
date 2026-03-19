defmodule StoryarnWeb.SheetLive.Components.SheetAvatar do
  @moduledoc """
  LiveComponent for the sheet avatar film strip.
  Handles avatar display, upload, removal, and default selection.
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
      <%!-- Main avatar display --%>
      <div class="flex items-center gap-3">
        <div class="relative group">
          <%= if @default_avatar && @default_avatar.asset do %>
            <img
              src={Assets.display_url(@default_avatar.asset)}
              alt={@sheet.name}
              class="size-10 rounded object-cover"
            />
          <% else %>
            <.icon name="file" class="size-10 opacity-60" />
          <% end %>

          <label
            :if={@can_edit}
            for="avatar-upload-input"
            class="absolute inset-0 bg-black/50 opacity-0 group-hover:opacity-100 rounded flex items-center justify-center transition-opacity cursor-pointer"
          >
            <.icon name="camera" class="size-4 text-white" />
          </label>
        </div>
      </div>

      <%!-- Film strip --%>
      <div :if={@can_edit && @avatars != []} class="flex items-center gap-1.5 mt-2">
        <div
          :for={avatar <- @avatars}
          class={[
            "relative group/thumb size-7 rounded overflow-hidden border-2 transition-colors shrink-0",
            if(avatar.is_default,
              do: "border-primary",
              else: "border-base-content/10 hover:border-base-content/30"
            )
          ]}
        >
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
            class="absolute top-0 right-0 size-3.5 bg-black/70 rounded-bl flex items-center justify-center opacity-0 group-hover/thumb:opacity-100 transition-opacity z-10"
          >
            <.icon name="x" class="size-2.5 text-white" />
          </button>
        </div>

        <label
          for="avatar-upload-input"
          class="size-7 rounded border-2 border-dashed border-base-content/20 hover:border-base-content/40 flex items-center justify-center cursor-pointer transition-colors shrink-0"
        >
          <.icon name="plus" class="size-3 text-base-content/40" />
        </label>
      </div>

      <%!-- Single shared file input --%>
      <input
        :if={@can_edit}
        type="file"
        accept="image/*"
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

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:avatars, Enum.sort_by(avatars, & &1.position))
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
    avatar = Sheets.get_avatar(String.to_integer(id))

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
