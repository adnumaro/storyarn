defmodule StoryarnWeb.Components.BlockComponents do
  @moduledoc """
  Components for rendering page blocks (text, rich_text, number, select, etc.).

  This module serves as a facade, delegating to specialized submodules:
  - `TextBlocks` - text, rich_text, number blocks
  - `SelectBlocks` - select, multi_select blocks
  - `LayoutBlocks` - divider, date blocks
  - `BlockMenu` - block type selection menu
  - `ConfigPanel` - block configuration sidebar
  """
  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.Components.CoreComponents, only: [icon: 1]

  # Import block type components for internal use in dispatcher
  import StoryarnWeb.Components.BlockComponents.TextBlocks
  import StoryarnWeb.Components.BlockComponents.SelectBlocks
  import StoryarnWeb.Components.BlockComponents.LayoutBlocks
  import StoryarnWeb.Components.BlockComponents.BooleanBlocks
  import StoryarnWeb.Components.BlockComponents.ReferenceBlocks

  # Re-export public components
  defdelegate block_menu(assigns), to: StoryarnWeb.Components.BlockComponents.BlockMenu
  defdelegate config_panel(assigns), to: StoryarnWeb.Components.BlockComponents.ConfigPanel

  # =============================================================================
  # Block Component (Main Dispatcher)
  # =============================================================================

  @doc """
  Renders a block with its controls (drag handle, menu) and content.

  ## Examples

      <.block_component block={@block} can_edit={true} editing_block_id={@editing_block_id} />
  """
  attr :block, :map, required: true
  attr :can_edit, :boolean, default: false
  attr :editing_block_id, :any, default: nil
  attr :target, :any, default: nil

  def block_component(assigns) do
    is_editing = assigns.editing_block_id == assigns.block.id
    assigns = assign(assigns, :is_editing, is_editing)

    ~H"""
    <div class="flex items-start gap-2 lg:relative lg:block w-full">
      <%!-- Drag handle and delete - inline on mobile, absolute on lg --%>
      <div
        :if={@can_edit}
        class="flex items-center pt-2 lg:absolute lg:-left-14 lg:top-2 lg:opacity-0 lg:group-hover:opacity-100"
      >
        <button
          type="button"
          class="drag-handle p-1 cursor-grab active:cursor-grabbing text-base-content/50 hover:text-base-content"
          title={gettext("Drag to reorder")}
        >
          <.icon name="grip-vertical" class="size-4" />
        </button>
        <div class="dropdown">
          <button
            type="button"
            tabindex="0"
            class="p-1 text-base-content/50 hover:text-base-content"
          >
            <.icon name="ellipsis-vertical" class="size-4" />
          </button>
          <ul
            tabindex="0"
            class="dropdown-content menu bg-base-200 rounded-box z-50 w-40 p-2 shadow-lg"
          >
            <li>
              <button
                type="button"
                phx-click="configure_block"
                phx-value-id={@block.id}
                phx-target={@target}
              >
                <.icon name="settings" class="size-4" />
                {gettext("Configure")}
              </button>
            </li>
            <li>
              <button
                type="button"
                class="text-error"
                phx-click="delete_block"
                phx-value-id={@block.id}
                phx-target={@target}
              >
                <.icon name="trash-2" class="size-4" />
                {gettext("Delete")}
              </button>
            </li>
          </ul>
        </div>
      </div>

      <%!-- Block content --%>
      <div class="flex-1 lg:flex-none">
        <%= case @block.type do %>
          <% "text" -> %>
            <.text_block block={@block} can_edit={@can_edit} is_editing={@is_editing} target={@target} />
          <% "rich_text" -> %>
            <.rich_text_block block={@block} can_edit={@can_edit} is_editing={@is_editing} target={@target} />
          <% "number" -> %>
            <.number_block block={@block} can_edit={@can_edit} is_editing={@is_editing} target={@target} />
          <% "select" -> %>
            <.select_block block={@block} can_edit={@can_edit} is_editing={@is_editing} target={@target} />
          <% "multi_select" -> %>
            <.multi_select_block block={@block} can_edit={@can_edit} is_editing={@is_editing} target={@target} />
          <% "divider" -> %>
            <.divider_block />
          <% "date" -> %>
            <.date_block block={@block} can_edit={@can_edit} target={@target} />
          <% "boolean" -> %>
            <.boolean_block block={@block} can_edit={@can_edit} target={@target} />
          <% "reference" -> %>
            <.reference_block
              block={@block}
              can_edit={@can_edit}
              reference_target={@block.reference_target}
              target={@target}
            />
          <% _ -> %>
            <div class="text-base-content/50">{gettext("Unknown block type")}</div>
        <% end %>
      </div>
    </div>
    """
  end
end
