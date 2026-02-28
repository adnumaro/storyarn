defmodule StoryarnWeb.Components.BlockComponents.BlockMenu do
  @moduledoc false

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.Components.CoreComponents, only: [icon: 1]

  @doc """
  Renders the block type selection menu as a floating context menu.

  ## Examples

      <.block_menu target={@myself} />
  """
  attr :target, :any, default: nil
  attr :scope, :string, default: "self"

  def block_menu(assigns) do
    ~H"""
    <div
      id="block-menu"
      phx-hook="BlockMenu"
      class="fixed z-50 bg-base-200 border border-base-300 rounded-lg shadow-sm w-56"
      phx-click-away="hide_block_menu"
      phx-target={@target}
    >
      <%!-- Scope selector (pinned above scroll) --%>
      <div class="px-3 py-2 border-b border-base-300">
        <div class="text-xs text-base-content/50 uppercase mb-1">
          {dgettext("sheets", "Scope")}
        </div>
        <div class="flex flex-col gap-0.5">
          <label class="flex items-center gap-2 cursor-pointer text-sm">
            <input
              type="radio"
              name="block_scope"
              value="self"
              checked={@scope == "self"}
              class="radio radio-xs"
              phx-click="set_block_scope"
              phx-value-scope="self"
              phx-target={@target}
            />
            <span>{dgettext("sheets", "This sheet only")}</span>
          </label>
          <label class="flex items-center gap-2 cursor-pointer text-sm">
            <input
              type="radio"
              name="block_scope"
              value="children"
              checked={@scope == "children"}
              class="radio radio-xs"
              phx-click="set_block_scope"
              phx-value-scope="children"
              phx-target={@target}
            />
            <span>{dgettext("sheets", "This sheet and all children")}</span>
          </label>
        </div>
      </div>
      <%!-- Scrollable items --%>
      <ul class="menu menu-sm w-full p-1 max-h-[min(24rem,50vh)] overflow-y-auto">
        <li class="menu-title">{dgettext("sheets", "Basic Blocks")}</li>
        <li>
          <button type="button" phx-click="add_block" phx-value-type="text" phx-target={@target}>
            <.icon name="type" class="size-4 opacity-60" />
            {dgettext("sheets", "Text")}
          </button>
        </li>
        <li>
          <button
            type="button"
            phx-click="add_block"
            phx-value-type="rich_text"
            phx-target={@target}
          >
            <.icon name="align-left" class="size-4 opacity-60" />
            {dgettext("sheets", "Rich Text")}
          </button>
        </li>
        <li>
          <button
            type="button"
            phx-click="add_block"
            phx-value-type="number"
            phx-target={@target}
          >
            <.icon name="hash" class="size-4 opacity-60" />
            {dgettext("sheets", "Number")}
          </button>
        </li>
        <li>
          <button
            type="button"
            phx-click="add_block"
            phx-value-type="select"
            phx-target={@target}
          >
            <.icon name="circle-dot" class="size-4 opacity-60" />
            {dgettext("sheets", "Select")}
          </button>
        </li>
        <li>
          <button
            type="button"
            phx-click="add_block"
            phx-value-type="multi_select"
            phx-target={@target}
          >
            <.icon name="list-checks" class="size-4 opacity-60" />
            {dgettext("sheets", "Multi Select")}
          </button>
        </li>
        <li>
          <button type="button" phx-click="add_block" phx-value-type="date" phx-target={@target}>
            <.icon name="calendar" class="size-4 opacity-60" />
            {dgettext("sheets", "Date")}
          </button>
        </li>
        <li>
          <button
            type="button"
            phx-click="add_block"
            phx-value-type="boolean"
            phx-target={@target}
          >
            <.icon name="toggle-left" class="size-4 opacity-60" />
            {dgettext("sheets", "Boolean")}
          </button>
        </li>
        <li>
          <button
            type="button"
            phx-click="add_block"
            phx-value-type="reference"
            phx-target={@target}
          >
            <.icon name="link" class="size-4 opacity-60" />
            {dgettext("sheets", "Reference")}
          </button>
        </li>

        <li class="menu-title mt-1">{dgettext("sheets", "Structured Data")}</li>
        <li>
          <button type="button" phx-click="add_block" phx-value-type="table" phx-target={@target}>
            <.icon name="table-2" class="size-4 opacity-60" />
            {dgettext("sheets", "Table")}
          </button>
        </li>
      </ul>
      <%!-- Footer --%>
      <div class="border-t border-base-300 p-1">
        <ul class="menu menu-sm w-full p-0">
          <li>
            <button
              type="button"
              class="text-base-content/50"
              phx-click="hide_block_menu"
              phx-target={@target}
            >
              {dgettext("sheets", "Cancel")}
              <kbd class="kbd kbd-xs ml-auto">esc</kbd>
            </button>
          </li>
        </ul>
      </div>
    </div>
    """
  end
end
