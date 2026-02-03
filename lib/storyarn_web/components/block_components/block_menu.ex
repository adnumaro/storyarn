defmodule StoryarnWeb.Components.BlockComponents.BlockMenu do
  @moduledoc false

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.Components.CoreComponents, only: [icon: 1]

  @doc """
  Renders the block type selection menu.

  ## Examples

      <.block_menu />
  """
  def block_menu(assigns) do
    ~H"""
    <div class="absolute z-10 bg-base-100 border border-base-300 rounded-lg shadow-lg p-2 w-64">
      <div class="text-xs text-base-content/50 px-2 py-1 uppercase">{gettext("Basic Blocks")}</div>
      <button
        type="button"
        class="w-full text-left px-2 py-2 hover:bg-base-200 rounded flex items-center gap-2"
        phx-click="add_block"
        phx-value-type="text"
      >
        <span class="text-lg">T</span>
        <span>{gettext("Text")}</span>
      </button>
      <button
        type="button"
        class="w-full text-left px-2 py-2 hover:bg-base-200 rounded flex items-center gap-2"
        phx-click="add_block"
        phx-value-type="rich_text"
      >
        <span class="text-lg">T</span>
        <span>{gettext("Rich Text")}</span>
      </button>
      <button
        type="button"
        class="w-full text-left px-2 py-2 hover:bg-base-200 rounded flex items-center gap-2"
        phx-click="add_block"
        phx-value-type="number"
      >
        <span class="text-lg">#</span>
        <span>{gettext("Number")}</span>
      </button>
      <button
        type="button"
        class="w-full text-left px-2 py-2 hover:bg-base-200 rounded flex items-center gap-2"
        phx-click="add_block"
        phx-value-type="select"
      >
        <.icon name="chevron-down" class="size-4" />
        <span>{gettext("Select")}</span>
      </button>
      <button
        type="button"
        class="w-full text-left px-2 py-2 hover:bg-base-200 rounded flex items-center gap-2"
        phx-click="add_block"
        phx-value-type="multi_select"
      >
        <.icon name="check" class="size-4" />
        <span>{gettext("Multi Select")}</span>
      </button>
      <button
        type="button"
        class="w-full text-left px-2 py-2 hover:bg-base-200 rounded flex items-center gap-2"
        phx-click="add_block"
        phx-value-type="date"
      >
        <.icon name="calendar" class="size-4" />
        <span>{gettext("Date")}</span>
      </button>
      <button
        type="button"
        class="w-full text-left px-2 py-2 hover:bg-base-200 rounded flex items-center gap-2"
        phx-click="add_block"
        phx-value-type="boolean"
      >
        <.icon name="toggle-left" class="size-4" />
        <span>{gettext("Boolean")}</span>
      </button>
      <button
        type="button"
        class="w-full text-left px-2 py-2 hover:bg-base-200 rounded flex items-center gap-2"
        phx-click="add_block"
        phx-value-type="reference"
      >
        <.icon name="link" class="size-4" />
        <span>{gettext("Reference")}</span>
      </button>

      <div class="text-xs text-base-content/50 px-2 py-1 uppercase mt-2">{gettext("Layout")}</div>
      <button
        type="button"
        class="w-full text-left px-2 py-2 hover:bg-base-200 rounded flex items-center gap-2"
        phx-click="add_block"
        phx-value-type="divider"
      >
        <.icon name="minus" class="size-4" />
        <span>{gettext("Divider")}</span>
      </button>

      <div class="border-t border-base-300 mt-2 pt-2">
        <button
          type="button"
          class="w-full text-left px-2 py-1 text-sm text-base-content/50 hover:text-base-content"
          phx-click="hide_block_menu"
        >
          {gettext("Cancel")}
        </button>
      </div>
    </div>
    """
  end
end
