defmodule StoryarnWeb.Components.BlockComponents.BlockMenu do
  @moduledoc false

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.Components.CoreComponents, only: [icon: 1]

  @doc """
  Renders the block type selection menu.

  ## Examples

      <.block_menu target={@myself} />
  """
  attr :target, :any, default: nil
  attr :scope, :string, default: "self"

  def block_menu(assigns) do
    ~H"""
    <div class="absolute z-10 bg-base-100 border border-base-300 rounded-lg shadow-lg p-2 w-64">
      <%!-- Scope selector --%>
      <div class="px-2 py-2 mb-2 border-b border-base-300">
        <div class="text-xs text-base-content/50 uppercase mb-1">{dgettext("sheets", "Scope")}</div>
        <div class="flex flex-col gap-1">
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
            <span>{dgettext("sheets", "This page only")}</span>
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
            <span>{dgettext("sheets", "This page and all children")}</span>
          </label>
        </div>
      </div>

      <div class="text-xs text-base-content/50 px-2 py-1 uppercase">{dgettext("sheets", "Basic Blocks")}</div>
      <button
        type="button"
        class="w-full text-left px-2 py-2 hover:bg-base-200 rounded flex items-center gap-2"
        phx-click="add_block"
        phx-value-type="text"
        phx-target={@target}
      >
        <span class="text-lg">T</span>
        <span>{dgettext("sheets", "Text")}</span>
      </button>
      <button
        type="button"
        class="w-full text-left px-2 py-2 hover:bg-base-200 rounded flex items-center gap-2"
        phx-click="add_block"
        phx-value-type="rich_text"
        phx-target={@target}
      >
        <span class="text-lg">T</span>
        <span>{dgettext("sheets", "Rich Text")}</span>
      </button>
      <button
        type="button"
        class="w-full text-left px-2 py-2 hover:bg-base-200 rounded flex items-center gap-2"
        phx-click="add_block"
        phx-value-type="number"
        phx-target={@target}
      >
        <span class="text-lg">#</span>
        <span>{dgettext("sheets", "Number")}</span>
      </button>
      <button
        type="button"
        class="w-full text-left px-2 py-2 hover:bg-base-200 rounded flex items-center gap-2"
        phx-click="add_block"
        phx-value-type="select"
        phx-target={@target}
      >
        <.icon name="chevron-down" class="size-4" />
        <span>{dgettext("sheets", "Select")}</span>
      </button>
      <button
        type="button"
        class="w-full text-left px-2 py-2 hover:bg-base-200 rounded flex items-center gap-2"
        phx-click="add_block"
        phx-value-type="multi_select"
        phx-target={@target}
      >
        <.icon name="check" class="size-4" />
        <span>{dgettext("sheets", "Multi Select")}</span>
      </button>
      <button
        type="button"
        class="w-full text-left px-2 py-2 hover:bg-base-200 rounded flex items-center gap-2"
        phx-click="add_block"
        phx-value-type="date"
        phx-target={@target}
      >
        <.icon name="calendar" class="size-4" />
        <span>{dgettext("sheets", "Date")}</span>
      </button>
      <button
        type="button"
        class="w-full text-left px-2 py-2 hover:bg-base-200 rounded flex items-center gap-2"
        phx-click="add_block"
        phx-value-type="boolean"
        phx-target={@target}
      >
        <.icon name="toggle-left" class="size-4" />
        <span>{dgettext("sheets", "Boolean")}</span>
      </button>
      <button
        type="button"
        class="w-full text-left px-2 py-2 hover:bg-base-200 rounded flex items-center gap-2"
        phx-click="add_block"
        phx-value-type="reference"
        phx-target={@target}
      >
        <.icon name="link" class="size-4" />
        <span>{dgettext("sheets", "Reference")}</span>
      </button>

      <div class="text-xs text-base-content/50 px-2 py-1 uppercase mt-2">{dgettext("sheets", "Layout")}</div>
      <button
        type="button"
        class="w-full text-left px-2 py-2 hover:bg-base-200 rounded flex items-center gap-2"
        phx-click="add_block"
        phx-value-type="divider"
        phx-target={@target}
      >
        <.icon name="minus" class="size-4" />
        <span>{dgettext("sheets", "Divider")}</span>
      </button>

      <div class="border-t border-base-300 mt-2 pt-2">
        <button
          type="button"
          class="w-full text-left px-2 py-1 text-sm text-base-content/50 hover:text-base-content"
          phx-click="hide_block_menu"
          phx-target={@target}
        >
          {dgettext("sheets", "Cancel")}
        </button>
      </div>
    </div>
    """
  end
end
