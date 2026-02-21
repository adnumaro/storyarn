defmodule StoryarnWeb.Components.BlockComponents do
  @moduledoc """
  Components for rendering sheet blocks (text, rich_text, number, select, etc.).

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
  import StoryarnWeb.Components.BlockComponents.TableBlocks

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
  attr :table_data, :map, default: %{}

  def block_component(assigns) do
    is_editing = assigns.editing_block_id == assigns.block.id
    is_inherited = assigns.block.inherited_from_block_id != nil
    assigns = assign(assigns, is_editing: is_editing, is_inherited: is_inherited)

    ~H"""
    <div class="relative flex items-start gap-2 lg:block w-full">
      <%!-- Drag handle (left side) --%>
      <div
        :if={@can_edit && !@is_inherited}
        class="flex items-center pt-2 lg:absolute lg:-left-6 lg:top-7 lg:opacity-0 lg:group-hover:opacity-100"
      >
        <button
          type="button"
          class="drag-handle p-1 cursor-grab active:cursor-grabbing text-base-content/50 hover:text-base-content"
          title={dgettext("sheets", "Drag to reorder")}
        >
          <.icon name="grip-vertical" class="size-4" />
        </button>
      </div>

      <%!-- Scope indicator for inheritable blocks --%>
      <div
        :if={Map.get(@block, :scope) == "children"}
        class="absolute -right-1 top-1 lg:opacity-0 lg:group-hover:opacity-100"
        title={dgettext("sheets", "Inherited by children")}
      >
        <.icon name="arrow-down" class="size-3 text-info/60" />
      </div>

      <%!-- Context menu (top-right, at label height) --%>
      <div
        :if={@can_edit}
        class="absolute right-0 top-0 flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity z-10"
      >
        <.block_context_menu block={@block} target={@target} is_inherited={@is_inherited} />
      </div>

      <%!-- Block content --%>
      <div class="flex-1 lg:flex-none">
        <%= case @block.type do %>
          <% "text" -> %>
            <.text_block
              block={@block}
              can_edit={@can_edit}
              is_editing={@is_editing}
              target={@target}
            />
          <% "rich_text" -> %>
            <.rich_text_block
              block={@block}
              can_edit={@can_edit}
              is_editing={@is_editing}
              target={@target}
            />
          <% "number" -> %>
            <.number_block
              block={@block}
              can_edit={@can_edit}
              is_editing={@is_editing}
              target={@target}
            />
          <% "select" -> %>
            <.select_block
              block={@block}
              can_edit={@can_edit}
              is_editing={@is_editing}
              target={@target}
            />
          <% "multi_select" -> %>
            <.multi_select_block
              block={@block}
              can_edit={@can_edit}
              is_editing={@is_editing}
              target={@target}
            />
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
          <% "table" -> %>
            <.table_block
              block={@block}
              can_edit={@can_edit}
              columns={@table_data[@block.id][:columns] || []}
              rows={@table_data[@block.id][:rows] || []}
              target={@target}
            />
          <% _ -> %>
            <div class="text-base-content/50">{dgettext("sheets", "Unknown block type")}</div>
        <% end %>
      </div>
    </div>
    """
  end

  # =============================================================================
  # Block Context Menu
  # =============================================================================

  attr :block, :map, required: true
  attr :target, :any, default: nil
  attr :is_inherited, :boolean, default: false

  defp block_context_menu(assigns) do
    ~H"""
    <%!-- Go to source shortcut (inherited only) --%>
    <button
      :if={@is_inherited}
      type="button"
      class="btn btn-ghost btn-xs btn-square tooltip tooltip-left"
      data-tip={dgettext("sheets", "Go to source")}
      phx-click="navigate_to_source"
      phx-value-id={@block.id}
      phx-target={@target}
    >
      <.icon name="arrow-up-right" class="size-3 text-info" />
    </button>

    <%!-- Dropdown menu --%>
    <div class="dropdown dropdown-end">
      <div tabindex="0" role="button" class="btn btn-ghost btn-xs btn-square">
        <.icon name="ellipsis-vertical" class="size-3" />
      </div>
      <ul tabindex="0" class="dropdown-content z-50 menu p-2 shadow-lg bg-base-200 rounded-box w-52">
        <%!-- Inherited block actions --%>
        <li :if={@is_inherited}>
          <button phx-click="navigate_to_source" phx-value-id={@block.id} phx-target={@target}>
            <.icon name="arrow-up-right" class="size-4" />
            {dgettext("sheets", "Go to source")}
          </button>
        </li>
        <li :if={@is_inherited}>
          <button phx-click="detach_inherited_block" phx-value-id={@block.id} phx-target={@target}>
            <.icon name="scissors" class="size-4" />
            {dgettext("sheets", "Detach property")}
          </button>
        </li>
        <li :if={@is_inherited}>
          <button
            phx-click="hide_inherited_for_children"
            phx-value-id={@block.inherited_from_block_id}
            phx-target={@target}
          >
            <.icon name="eye-off" class="size-4" />
            {dgettext("sheets", "Hide for children")}
          </button>
        </li>

        <%!-- Divider between sections --%>
        <div :if={@is_inherited} class="divider my-0.5"></div>

        <%!-- Common actions --%>
        <li>
          <button
            type="button"
            phx-click="configure_block"
            phx-value-id={@block.id}
            phx-target={@target}
          >
            <.icon name="settings" class="size-4" />
            {dgettext("sheets", "Configure")}
          </button>
        </li>

        <%!-- Danger zone --%>
        <div class="divider my-0.5"></div>
        <li>
          <button
            type="button"
            class="text-error"
            phx-click="delete_block"
            phx-value-id={@block.id}
            phx-target={@target}
          >
            <.icon name="trash-2" class="size-4" />
            {dgettext("sheets", "Delete")}
          </button>
        </li>
      </ul>
    </div>
    """
  end
end
