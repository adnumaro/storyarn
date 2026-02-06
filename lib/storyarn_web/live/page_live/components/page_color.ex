defmodule StoryarnWeb.PageLive.Components.PageColor do
  @moduledoc """
  LiveComponent for selecting a page color.
  Displays preset color options as clickable circles.
  """

  use StoryarnWeb, :live_component

  alias Storyarn.Pages
  alias Storyarn.Repo

  @preset_colors [
    {"#3b82f6", "Blue"},
    {"#22c55e", "Green"},
    {"#ef4444", "Red"},
    {"#f59e0b", "Amber"},
    {"#8b5cf6", "Purple"},
    {"#ec4899", "Pink"},
    {"#06b6d4", "Cyan"},
    {"#f97316", "Orange"},
    {"#6366f1", "Indigo"},
    {"#84cc16", "Lime"}
  ]

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex items-center gap-2">
      <span class="text-sm text-base-content/60">{gettext("Color")}</span>
      <div class="flex items-center gap-1">
        <%= for {color, name} <- @preset_colors do %>
          <button
            type="button"
            title={name}
            class={[
              "w-5 h-5 rounded-full transition-all",
              @page.color == color && "ring-2 ring-offset-2 ring-offset-base-100 ring-base-content/50",
              !@can_edit && "cursor-not-allowed opacity-50"
            ]}
            style={"background-color: #{color}"}
            phx-click={@can_edit && "set_color"}
            phx-value-color={color}
            phx-target={@myself}
            disabled={!@can_edit}
          >
          </button>
        <% end %>
        <%= if @page.color do %>
          <button
            type="button"
            title={gettext("Remove color")}
            class={[
              "w-5 h-5 rounded-full border border-base-300 flex items-center justify-center text-base-content/50 hover:text-base-content transition-colors",
              !@can_edit && "cursor-not-allowed opacity-50"
            ]}
            phx-click={@can_edit && "clear_color"}
            phx-target={@myself}
            disabled={!@can_edit}
          >
            <.icon name="x" class="size-3" />
          </button>
        <% end %>
      </div>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(:preset_colors, @preset_colors)}
  end

  @impl true
  def handle_event("set_color", %{"color" => color}, socket) do
    update_page_color(socket, color)
  end

  def handle_event("clear_color", _params, socket) do
    update_page_color(socket, nil)
  end

  defp update_page_color(socket, color) do
    page = socket.assigns.page

    case Pages.update_page(page, %{color: color}) do
      {:ok, updated_page} ->
        updated_page =
          Repo.preload(updated_page, [:avatar_asset, :banner_asset, :current_version],
            force: true
          )

        send(self(), {:page_color, :page_updated, updated_page})
        {:noreply, assign(socket, :page, updated_page)}

      {:error, _changeset} ->
        send(self(), {:page_color, :error, gettext("Could not update color.")})
        {:noreply, socket}
    end
  end
end
