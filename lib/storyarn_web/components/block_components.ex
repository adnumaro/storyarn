defmodule StoryarnWeb.Components.BlockComponents do
  @moduledoc """
  Components for rendering sheet blocks (text, rich_text, number, select, etc.).

  This module serves as a facade, delegating to specialized submodules:
  - `TextBlocks` - text, rich_text, number blocks
  - `SelectBlocks` - select, multi_select blocks
  - `LayoutBlocks` - date blocks
  - `BlockMenu` - block type selection menu
  - `BlockToolbar` - hover toolbar for block actions
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
  defdelegate block_toolbar(assigns), to: StoryarnWeb.Components.BlockComponents.BlockToolbar

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
  attr :selected_block_id, :any, default: nil
  attr :target, :any, default: nil
  attr :component_id, :string, default: nil
  attr :table_data, :map, default: %{}
  attr :reference_options, :list, default: []

  def block_component(assigns) do
    is_editing = assigns.editing_block_id == assigns.block.id
    is_inherited = assigns.block.inherited_from_block_id != nil
    is_selected = assigns.selected_block_id == assigns.block.id

    assigns =
      assign(assigns,
        is_editing: is_editing,
        is_inherited: is_inherited,
        is_selected: is_selected
      )

    ~H"""
    <div
      class={[
        "relative flex items-start gap-2 lg:block w-full p-2",
        @is_selected && "ring-2 ring-primary/30 rounded-lg"
      ]}
      phx-click="select_block"
      phx-value-id={@block.id}
      phx-target={@target}
    >
      <%!-- Drag handle (left side) --%>
      <div
        :if={@can_edit && !@is_inherited}
        class="flex items-center pt-2 lg:absolute lg:-left-4 lg:top-7 lg:opacity-0 lg:group-hover:opacity-100"
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

      <%!-- Block toolbar (replaces old context menu) --%>
      <.block_toolbar
        block={@block}
        can_edit={@can_edit}
        target={@target}
        component_id={@component_id}
      />

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
              schema_locked={@is_inherited && !@block.detached}
              columns={@table_data[@block.id][:columns] || []}
              rows={@table_data[@block.id][:rows] || []}
              reference_options={@reference_options}
              target={@target}
            />
          <% _ -> %>
            <div class="text-base-content/50">{dgettext("sheets", "Unknown block type")}</div>
        <% end %>
      </div>
    </div>
    """
  end
end
