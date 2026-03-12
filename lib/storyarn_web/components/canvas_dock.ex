defmodule StoryarnWeb.Components.CanvasDock do
  @moduledoc """
  Shared bottom dock component for canvas editors (flow, scene).

  Renders groups of tool items as a floating bottom bar with icons,
  tooltips, dropdowns, and separators between groups.
  """

  use Phoenix.Component

  import StoryarnWeb.Components.CoreComponents

  @doc """
  Renders a bottom-centered dock with grouped items.

  ## Item structure

  Each group is a list of item maps. Groups are separated by vertical dividers.

      %{
        id: "dialogue",
        icon: "message-square",
        tooltip_title: "Dialogue",
        tooltip: "Character speech and player responses",
        click: "add_node",           # phx-click event (or nil)
        navigate: nil,               # navigate URL (or nil)
        value: "dialogue",           # phx-value-type for click events
        active: false,               # highlight as active
        disabled: false,             # grayed out
        children: [],                # if present, renders as dropdown
        panel_trigger: "my-panel"    # links button to a RightSidebar panel for active state
      }

  Child items:

      %{
        id: "dialogue",
        icon: "message-square",
        title: "Dialogue",
        description: "Character speech and player responses",
        click: "add_node",
        value: "dialogue"
      }
  """
  attr :id, :string, default: "canvas-dock"
  attr :groups, :list, required: true

  slot :extra, doc: "Extra content rendered below the dock (e.g., pending indicators)"

  def canvas_dock(assigns) do
    ~H"""
    <div>
      <div
        id={@id}
        class="absolute bottom-3 left-1/2 -translate-x-1/2 z-[1000] flex items-center gap-1 surface-panel px-2 py-2"
      >
        <%= for {group, gi} <- Enum.with_index(@groups) do %>
          <.dock_separator :if={gi > 0} />
          <%= for item <- group do %>
            <%= if item[:children] && item[:children] != [] do %>
              <.dock_dropdown item={item} />
            <% else %>
              <.dock_item item={item} />
            <% end %>
          <% end %>
        <% end %>
      </div>
      {render_slot(@extra)}
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Internal components
  # ---------------------------------------------------------------------------

  attr :item, :map, required: true

  defp dock_item(assigns) do
    ~H"""
    <div class="dock-item group relative">
      <%= if @item[:navigate] do %>
        <.link navigate={@item.navigate} class={dock_btn_class(@item)}>
          <.icon name={@item.icon} class="size-5" />
        </.link>
      <% else %>
        <button
          type="button"
          phx-click={@item[:click]}
          phx-value-type={@item[:value]}
          data-panel-trigger={@item[:panel_trigger]}
          class={dock_btn_class(@item)}
          disabled={@item[:disabled]}
        >
          <.icon name={@item.icon} class="size-5" />
        </button>
      <% end %>
      <div :if={@item[:tooltip]} class="dock-tooltip">
        <div :if={@item[:tooltip_title]} class="text-sm font-semibold mb-0.5">
          {@item.tooltip_title}
        </div>
        <div class="text-xs text-base-content/60 leading-relaxed">{@item.tooltip}</div>
      </div>
    </div>
    """
  end

  attr :item, :map, required: true

  defp dock_dropdown(assigns) do
    ~H"""
    <div class="dock-item group relative">
      <div class="dropdown dropdown-top">
        <div
          tabindex="0"
          role="button"
          class={dock_btn_class(@item)}
        >
          <.icon name={@item.icon} class="size-5" />
        </div>
        <div
          tabindex="0"
          class="dropdown-content mb-3 p-3 bg-base-100 rounded-xl border border-base-300 shadow-xl w-52"
        >
          <div
            :if={@item[:dropdown_title]}
            class="text-xs font-semibold text-base-content/50 uppercase tracking-wider mb-2 px-1"
          >
            {@item.dropdown_title}
          </div>
          <div class="flex flex-col gap-0.5">
            <button
              :for={child <- @item.children}
              type="button"
              phx-click={child[:click]}
              phx-value-type={child[:value]}
              class="w-full flex items-start gap-2.5 px-2.5 py-2 rounded-lg text-sm text-start cursor-pointer hover:bg-base-200 transition-colors"
            >
              <.icon name={child.icon} class="size-4 mt-0.5 shrink-0" />
              <div>
                <div class="font-medium">{child.title}</div>
                <div :if={child[:description]} class="text-xs text-base-content/50">
                  {child.description}
                </div>
              </div>
            </button>
          </div>
        </div>
      </div>
      <div :if={@item[:tooltip]} class="dock-tooltip">
        <div :if={@item[:tooltip_title]} class="text-sm font-semibold mb-0.5">
          {@item.tooltip_title}
        </div>
        <div class="text-xs text-base-content/60 leading-relaxed">{@item.tooltip}</div>
      </div>
    </div>
    """
  end

  defp dock_separator(assigns) do
    ~H"""
    <div class="w-px h-6 bg-base-300 mx-0.5 shrink-0"></div>
    """
  end

  defp dock_btn_class(item) do
    base = "dock-btn"
    active = if item[:active], do: " dock-btn-active", else: ""
    disabled = if item[:disabled], do: " opacity-30 pointer-events-none", else: ""
    base <> active <> disabled
  end
end
