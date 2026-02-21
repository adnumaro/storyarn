defmodule StoryarnWeb.SheetLive.Components.InheritedBlockComponents do
  @moduledoc """
  Sub-components for rendering inherited (parent-sourced) blocks in the sheet content tab.

  Provides:
  - `inherited_section_header/1` - header row showing source sheet name and block count
  - `inherited_block_wrapper/1` - wraps a block with the inherited styling and required indicator
  """

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext
  use StoryarnWeb, :verified_routes

  import StoryarnWeb.Components.CoreComponents, only: [icon: 1]
  import StoryarnWeb.Components.BlockComponents, only: [block_component: 1]

  # ---------------------------------------------------------------------------
  # inherited_section_header/1
  # ---------------------------------------------------------------------------

  attr :source_sheet, :map, required: true
  attr :block_count, :integer, required: true
  attr :workspace, :map, required: true
  attr :project, :map, required: true

  def inherited_section_header(assigns) do
    ~H"""
    <div class="flex items-center gap-1.5 mb-1 ml-1">
      <.icon name="arrow-up-right" class="size-3 text-info/60" />
      <span class="text-[10px] text-base-content/40 uppercase tracking-wider">
        {dgettext("sheets", "Inherited from")}
      </span>
      <.link
        navigate={
          ~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/sheets/#{@source_sheet.id}"
        }
        class="text-xs font-medium text-info hover:underline"
      >
        {@source_sheet.name}
      </.link>
      <span class="text-[10px] text-base-content/30">({@block_count})</span>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # inherited_block_wrapper/1
  # ---------------------------------------------------------------------------

  attr :block, :map, required: true
  attr :can_edit, :boolean, required: true
  attr :editing_block_id, :any, default: nil
  attr :target, :any, default: nil
  attr :table_data, :map, default: %{}

  def inherited_block_wrapper(assigns) do
    ~H"""
    <div class="relative">
      <.block_component
        block={@block}
        can_edit={@can_edit}
        editing_block_id={@editing_block_id}
        target={@target}
        table_data={@table_data}
      />
      <%!-- Required indicator --%>
      <div
        :if={@block.required}
        class="absolute top-1 left-2 text-error text-xs font-bold"
        title={dgettext("sheets", "Required")}
      >
        *
      </div>
    </div>
    """
  end
end
