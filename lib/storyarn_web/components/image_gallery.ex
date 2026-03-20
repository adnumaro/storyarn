defmodule StoryarnWeb.Components.ImageGallery do
  @moduledoc """
  Reusable LiveComponent for browsing and editing a collection of images.

  Two views:
  - **Grid**: thumbnails with names, click to open single view
  - **Single**: full-size original image, name/notes editing, circular prev/next

  ## Usage

      <.live_component
        module={ImageGallery}
        id="avatar-gallery"
        items={@gallery_items}
        can_edit={true}
        title="Avatar Gallery"
        name_placeholder="e.g. happy, angry..."
        notes_placeholder="Voice direction, art notes..."
        upload_label="Add avatar"
        upload_input_id="avatar-upload-input"
        empty_message="No avatars yet."
      >
        <:item_badge :let={item}>
          <span :if={item.is_default} class="badge badge-primary badge-xs">default</span>
        </:item_badge>
        <:item_actions :let={item}>
          <button phx-click="set_default" phx-value-id={item.id}>Set as default</button>
        </:item_actions>
      </.live_component>

  ## Events emitted to parent (via send/2)

  - `{:image_gallery, :update_name, %{id: id, value: value}}`
  - `{:image_gallery, :update_notes, %{id: id, value: value}}`
  - `{:image_gallery, :delete, %{id: id}}`

  ## Item shape

  Each item in `items` must be a map with:
  - `id` (integer)
  - `url` (string — thumbnail/optimized)
  - `original_url` (string — full size for single view)
  - `name` (string | nil)
  - `notes` (string | nil)
  - `filename` (string | nil)
  - Any extra keys are preserved and passed through to slots
  """

  use StoryarnWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.modal id={@id} on_cancel={hide_modal(@id)}>
        <div class="min-w-[28rem]">
          <%= if @selected_item do %>
            <%!-- Single view --%>
            <div class="flex items-center justify-between mb-3">
              <button
                type="button"
                phx-click="back_to_grid"
                phx-target={@myself}
                class="btn btn-ghost btn-sm gap-1"
              >
                <.icon name="arrow-left" class="size-4" />
                {@title}
              </button>
              <div :if={length(@items) > 1} class="flex items-center gap-1">
                <button
                  type="button"
                  phx-click="nav_prev"
                  phx-target={@myself}
                  class="btn btn-ghost btn-xs btn-square"
                >
                  <.icon name="chevron-left" class="size-4" />
                </button>
                <span class="text-xs text-base-content/40">
                  {@selected_index + 1}/{length(@items)}
                </span>
                <button
                  type="button"
                  phx-click="nav_next"
                  phx-target={@myself}
                  class="btn btn-ghost btn-xs btn-square"
                >
                  <.icon name="chevron-right" class="size-4" />
                </button>
              </div>
            </div>

            <%!-- Original size image --%>
            <div class="flex justify-center bg-base-300/20 rounded-lg overflow-hidden mb-4">
              <img
                src={@selected_item.original_url}
                alt={@selected_item.name || ""}
                class="max-w-full max-h-[55vh] object-contain"
              />
            </div>

            <p :if={@selected_item.filename} class="text-xs text-base-content/40 truncate mb-3">
              {@selected_item.filename}
            </p>

            <%!-- Name --%>
            <div class="mb-3">
              <label class="label text-xs font-medium">{dgettext("sheets", "Name")}</label>
              <input
                type="text"
                value={@selected_item.name || ""}
                placeholder={@name_placeholder}
                disabled={!@can_edit}
                phx-blur="update_name"
                phx-target={@myself}
                class="input input-sm input-bordered w-full"
              />
            </div>

            <%!-- Notes --%>
            <div class="mb-3">
              <label class="label text-xs font-medium">{dgettext("sheets", "Notes")}</label>
              <textarea
                rows="3"
                placeholder={@notes_placeholder}
                disabled={!@can_edit}
                phx-blur="update_notes"
                phx-target={@myself}
                class="textarea textarea-sm textarea-bordered w-full"
              >{@selected_item.notes || ""}</textarea>
            </div>

            <%!-- Custom actions from caller + delete --%>
            <div class="flex items-center justify-between pt-3 border-t border-base-content/10">
              <div class="flex items-center gap-2">
                {render_slot(@item_actions, @selected_item)}
              </div>
              <button
                :if={@can_edit}
                type="button"
                phx-click="delete_item"
                phx-target={@myself}
                class="btn btn-sm btn-error btn-outline gap-1"
              >
                <.icon name="trash-2" class="size-3.5" />
                {dgettext("sheets", "Delete")}
              </button>
            </div>
          <% else %>
            <%!-- Grid view --%>
            <h3 class="font-bold text-lg mb-4">{@title}</h3>

            <%= if @items == [] do %>
              <div class="text-center py-8 text-base-content/40">
                <.icon name="image" class="size-8 mx-auto mb-2 opacity-40" />
                <p class="text-sm">{@empty_message}</p>
              </div>
            <% else %>
              <div class="grid grid-cols-3 sm:grid-cols-4 gap-3">
                <div :for={item <- @items} class="group/card relative flex flex-col items-center">
                  <button
                    type="button"
                    phx-click="select_item"
                    phx-value-id={item.id}
                    phx-target={@myself}
                    class="aspect-square w-full rounded-lg overflow-hidden border-2 border-base-content/10 hover:border-base-content/30 transition-colors cursor-pointer"
                  >
                    <img
                      src={item.url}
                      alt={item.name || ""}
                      class="w-full h-full object-cover"
                    />
                  </button>
                  <%!-- Custom badge from caller --%>
                  <div class="absolute top-1 left-1">
                    {render_slot(@item_badge, item)}
                  </div>
                  <%!-- Delete on hover --%>
                  <button
                    :if={@can_edit}
                    type="button"
                    phx-click="delete_item_from_grid"
                    phx-value-id={item.id}
                    phx-target={@myself}
                    class="absolute top-1 right-1 size-5 rounded-full bg-black/70 flex items-center justify-center opacity-0 group-hover/card:opacity-100 transition-opacity"
                  >
                    <.icon name="x" class="size-3 text-white" />
                  </button>
                  <p class="text-xs text-base-content/60 mt-1 truncate max-w-full">
                    {item.name || item.filename || ""}
                  </p>
                </div>
              </div>
            <% end %>

            <%!-- Upload button --%>
            <div :if={@can_edit && @upload_input_id} class="mt-4">
              <label
                for={@upload_input_id}
                class="btn btn-ghost btn-sm w-full border border-dashed border-base-content/20 cursor-pointer"
              >
                <.icon name="plus" class="size-4" />
                {@upload_label}
              </label>
            </div>
          <% end %>
        </div>
      </.modal>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    items = assigns[:items] || []
    selected_id = socket.assigns[:selected_id]

    selected_index =
      if selected_id, do: Enum.find_index(items, &(&1.id == selected_id)), else: nil

    selected_item =
      if selected_index, do: Enum.at(items, selected_index), else: nil

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:items, items)
     |> assign(:selected_id, selected_id)
     |> assign(:selected_index, selected_index)
     |> assign(:selected_item, selected_item)
     |> assign_new(:name_placeholder, fn -> "" end)
     |> assign_new(:notes_placeholder, fn -> "" end)
     |> assign_new(:upload_label, fn -> dgettext("sheets", "Add image") end)
     |> assign_new(:upload_input_id, fn -> nil end)
     |> assign_new(:empty_message, fn -> dgettext("sheets", "No images yet.") end)
     |> assign_new(:title, fn -> dgettext("sheets", "Gallery") end)}
  end

  @impl true
  def handle_event("select_item", %{"id" => id}, socket) do
    {:noreply, assign(socket, :selected_id, to_int(id))}
  end

  def handle_event("back_to_grid", _params, socket) do
    {:noreply, assign(socket, :selected_id, nil)}
  end

  def handle_event("nav_prev", _params, socket) do
    {:noreply, navigate(socket, -1)}
  end

  def handle_event("nav_next", _params, socket) do
    {:noreply, navigate(socket, 1)}
  end

  def handle_event("update_name", %{"value" => value}, socket) do
    if item = socket.assigns.selected_item do
      send(self(), {:image_gallery, :update_name, %{id: item.id, value: value}})
    end

    {:noreply, socket}
  end

  def handle_event("update_notes", %{"value" => value}, socket) do
    if item = socket.assigns.selected_item do
      send(self(), {:image_gallery, :update_notes, %{id: item.id, value: value}})
    end

    {:noreply, socket}
  end

  def handle_event("delete_item", _params, socket) do
    if item = socket.assigns.selected_item do
      send(self(), {:image_gallery, :delete, %{id: item.id}})
    end

    {:noreply, assign(socket, :selected_id, nil)}
  end

  def handle_event("delete_item_from_grid", %{"id" => id}, socket) do
    send(self(), {:image_gallery, :delete, %{id: to_int(id)}})
    {:noreply, socket}
  end

  defp navigate(socket, direction) do
    items = socket.assigns.items
    count = length(items)

    if count <= 1 do
      socket
    else
      current_index = socket.assigns.selected_index || 0
      new_index = rem(current_index + direction + count, count)
      new_item = Enum.at(items, new_index)
      assign(socket, :selected_id, new_item.id)
    end
  end

  defp to_int(id) when is_integer(id), do: id
  defp to_int(id) when is_binary(id), do: String.to_integer(id)
end
