defmodule StoryarnWeb.SheetLive.Components.SheetAvatar do
  @moduledoc """
  LiveComponent for the sheet avatar with film strip popover and gallery modal.
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
      <div class="relative group">
        <%= if @default_avatar && @default_avatar.asset do %>
          <img
            src={Assets.display_url(@default_avatar.asset)}
            alt={@sheet.name}
            class="size-10 rounded object-cover cursor-pointer"
            phx-click={if @can_edit, do: show_modal("avatar-gallery-#{@sheet.id}")}
          />
        <% else %>
          <div
            class="size-10 rounded bg-base-300 flex items-center justify-center cursor-pointer"
            phx-click={if @can_edit, do: show_modal("avatar-gallery-#{@sheet.id}")}
          >
            <.icon name="file" class="size-5 opacity-40" />
          </div>
        <% end %>

        <label
          :if={@can_edit}
          for="avatar-upload-input"
          class="absolute inset-0 bg-black/50 opacity-0 group-hover:opacity-100 rounded flex items-center justify-center transition-opacity cursor-pointer"
        >
          <.icon name="camera" class="size-4 text-white" />
        </label>
      </div>

      <%!-- Gallery modal --%>
      <.modal :if={@can_edit} id={"avatar-gallery-#{@sheet.id}"} on_cancel={hide_modal("avatar-gallery-#{@sheet.id}")}>
        <h3 class="font-bold text-lg mb-4">
          {dgettext("sheets", "Avatar Gallery")}
        </h3>

        <%= if @avatars == [] do %>
          <div class="text-center py-8 text-base-content/40">
            <.icon name="image" class="size-8 mx-auto mb-2 opacity-40" />
            <p class="text-sm">{dgettext("sheets", "No avatars yet. Upload one to get started.")}</p>
          </div>
        <% else %>
          <%!-- Grid of avatars --%>
          <div class="grid grid-cols-3 sm:grid-cols-4 gap-3">
            <div :for={avatar <- @avatars} class="group/card relative">
              <%!-- Avatar image --%>
              <button
                :if={avatar.asset}
                type="button"
                phx-click="set_default"
                phx-value-id={avatar.id}
                phx-target={@myself}
                class={[
                  "aspect-square w-full rounded-lg overflow-hidden border-2 transition-colors",
                  if(avatar.is_default,
                    do: "border-primary",
                    else: "border-base-content/10 hover:border-base-content/30"
                  )
                ]}
              >
                <img
                  src={Assets.display_url(avatar.asset)}
                  alt={avatar.name || ""}
                  class="w-full h-full object-cover"
                />
              </button>

              <%!-- Default badge --%>
              <span
                :if={avatar.is_default}
                class="absolute top-1 left-1 badge badge-primary badge-xs"
              >
                {dgettext("sheets", "default")}
              </span>

              <%!-- Remove button --%>
              <button
                type="button"
                phx-click="remove_avatar"
                phx-value-id={avatar.id}
                phx-target={@myself}
                class="absolute top-1 right-1 size-5 rounded-full bg-black/70 flex items-center justify-center opacity-0 group-hover/card:opacity-100 transition-opacity"
              >
                <.icon name="x" class="size-3 text-white" />
              </button>

              <%!-- Name input --%>
              <input
                type="text"
                value={avatar.name || ""}
                placeholder={dgettext("sheets", "name...")}
                phx-blur="update_avatar_name"
                phx-value-id={avatar.id}
                phx-target={@myself}
                class="input input-xs w-full mt-1 text-center text-xs bg-transparent border-0 border-b border-base-content/10 focus:border-primary rounded-none px-0"
              />

              <%!-- Notes textarea (expandable) --%>
              <textarea
                rows="1"
                value={avatar.notes || ""}
                placeholder={dgettext("sheets", "notes...")}
                phx-blur="update_avatar_notes"
                phx-value-id={avatar.id}
                phx-target={@myself}
                class="textarea textarea-xs w-full mt-0.5 text-xs bg-transparent border-0 resize-none px-0 min-h-0 h-5 focus:h-12 transition-all text-base-content/50 focus:text-base-content"
              >{avatar.notes || ""}</textarea>
            </div>
          </div>
        <% end %>

        <%!-- Upload button --%>
        <div class="mt-4">
          <label
            for="avatar-upload-input"
            class="btn btn-ghost btn-sm w-full border border-dashed border-base-content/20"
          >
            <.icon name="plus" class="size-4" />
            {dgettext("sheets", "Add avatar")}
          </label>
        </div>
      </.modal>

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

  def handle_event("update_avatar_name", %{"id" => id, "value" => value}, socket) do
    Authorize.with_edit_authorization(socket, fn socket ->
      case get_owned_avatar(socket, id) do
        {:ok, avatar} ->
          Sheets.update_avatar(avatar, %{name: value})
          reload_and_notify(socket)

        {:error, _} ->
          {:noreply, socket}
      end
    end)
  end

  def handle_event("update_avatar_notes", %{"id" => id, "value" => value}, socket) do
    Authorize.with_edit_authorization(socket, fn socket ->
      case get_owned_avatar(socket, id) do
        {:ok, avatar} ->
          Sheets.update_avatar(avatar, %{notes: value})
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
