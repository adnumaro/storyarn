defmodule StoryarnWeb.SheetLive.Components.SheetColor do
  @moduledoc """
  LiveComponent for selecting a sheet color.
  Uses vanilla-colorful full-spectrum color picker.
  """

  use StoryarnWeb, :live_component

  import StoryarnWeb.Components.ColorPicker

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col gap-1">
      <div class="flex items-center gap-2">
        <span class="text-sm text-base-content/60">{dgettext("sheets", "Color")}</span>
        <%= if @sheet.color do %>
          <button
            type="button"
            title={dgettext("sheets", "Remove color")}
            class={[
              "w-5 h-5 rounded-full border border-base-300 flex items-center justify-center text-base-content/50 hover:text-base-content transition-colors",
              !@can_edit && "cursor-not-allowed opacity-50"
            ]}
            phx-click={@can_edit && "clear_sheet_color"}
            disabled={!@can_edit}
          >
            <.icon name="x" class="size-3" />
          </button>
        <% end %>
      </div>
      <.color_picker
        id={"sheet-color-#{@sheet.id}"}
        color={@sheet.color || "#3b82f6"}
        event="set_sheet_color"
        field="color"
        disabled={!@can_edit}
      />
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end
end
