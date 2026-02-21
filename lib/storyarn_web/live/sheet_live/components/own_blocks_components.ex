defmodule StoryarnWeb.SheetLive.Components.OwnBlocksComponents do
  @moduledoc """
  Sub-components for rendering the "own properties" section of the sheet content tab.

  Provides:
  - `own_properties_label/1`  - "Own Properties" divider shown when inherited blocks exist
  - `blocks_container/1`      - sortable container for full-width and column-group blocks
  - `add_block_prompt/1`      - "Type / to add a block" button + block-type menu
  """

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.Components.CoreComponents, only: [icon: 1]
  import StoryarnWeb.Components.BlockComponents, only: [block_component: 1, block_menu: 1]

  alias StoryarnWeb.SheetLive.Helpers.ContentTabHelpers

  # ---------------------------------------------------------------------------
  # own_properties_label/1
  # ---------------------------------------------------------------------------

  attr :show, :boolean, required: true

  def own_properties_label(assigns) do
    ~H"""
    <div
      :if={@show}
      class="text-xs text-base-content/50 uppercase tracking-wider mt-6 mb-2 px-2 sm:px-8 md:px-16"
    >
      {dgettext("sheets", "Own Properties")}
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # blocks_container/1
  # ---------------------------------------------------------------------------

  attr :layout_items, :list, required: true
  attr :can_edit, :boolean, required: true
  attr :editing_block_id, :any, default: nil
  attr :target, :any, required: true
  attr :component_id, :string, required: true
  attr :table_data, :map, default: %{}

  def blocks_container(assigns) do
    ~H"""
    <div
      id="blocks-container"
      class="flex flex-col gap-2 -mx-2 sm:-mx-8 md:-mx-16"
      phx-hook={if @can_edit, do: "ColumnSortable", else: nil}
      phx-target={@target}
      data-phx-target={"##{@component_id}"}
      data-group="blocks"
      data-handle=".drag-handle"
    >
      <%= for item <- @layout_items do %>
        <%= case item.type do %>
          <% :full_width -> %>
            <div
              class="group relative w-full px-2 sm:px-8 md:px-16"
              id={"block-#{item.block.id}"}
              data-id={item.block.id}
            >
              <.block_component
                block={item.block}
                can_edit={@can_edit}
                editing_block_id={@editing_block_id}
                target={@target}
                table_data={@table_data}
              />
            </div>
          <% :column_group -> %>
            <div
              class={[
                "column-group grid gap-8 px-2 sm:px-8 md:px-16",
                ContentTabHelpers.column_grid_class(item.column_count)
              ]}
              data-column-group={item.group_id}
            >
              <div
                :for={block <- item.blocks}
                class="column-item group relative w-full"
                id={"block-#{block.id}"}
                data-id={block.id}
                data-column-group={item.group_id}
                data-column-index={block.column_index}
              >
                <.block_component
                  block={block}
                  can_edit={@can_edit}
                  editing_block_id={@editing_block_id}
                  target={@target}
                  table_data={@table_data}
                />
              </div>
            </div>
        <% end %>
      <% end %>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # add_block_prompt/1
  # ---------------------------------------------------------------------------

  attr :can_edit, :boolean, required: true
  attr :show_block_menu, :boolean, required: true
  attr :block_scope, :string, required: true
  attr :target, :any, required: true

  def add_block_prompt(assigns) do
    ~H"""
    <div :if={@can_edit} class="relative mt-2">
      <div
        :if={!@show_block_menu}
        class="flex items-center gap-2 py-2 text-base-content/50 hover:text-base-content cursor-pointer group"
        phx-click="show_block_menu"
        phx-target={@target}
      >
        <.icon name="plus" class="size-4 opacity-0 group-hover:opacity-100" />
        <span class="text-sm">{dgettext("sheets", "Type / to add a block")}</span>
      </div>

      <.block_menu :if={@show_block_menu} target={@target} scope={@block_scope} />
    </div>
    """
  end
end
