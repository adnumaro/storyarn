defmodule StoryarnWeb.Components.BlockComponents.BlockAdvancedConfig do
  @moduledoc """
  Shared "Advanced" section for block config popovers (Plans 1-7).

  Renders scope selector, required toggle, variable name display,
  and re-attach button. Uses `data-event`/`data-params` pattern
  since it will render inside ToolbarPopover (cloned outside LiveView DOM).
  """

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.Components.CoreComponents, only: [icon: 1]

  alias Storyarn.Sheets.Block

  attr :block, :map, required: true
  attr :can_edit, :boolean, default: false
  attr :standalone, :boolean, default: false

  def block_advanced_config(assigns) do
    is_inherited = assigns.block.inherited_from_block_id != nil
    is_variable = Block.can_be_variable?(assigns.block.type) && !assigns.block.is_constant

    assigns =
      assigns
      |> assign(:is_inherited, is_inherited)
      |> assign(:is_variable, is_variable)

    ~H"""
    <div class={["space-y-3", !@standalone && "pt-3 border-t border-base-300"]}>

      <div class="text-sm font-medium text-base-content/60 uppercase tracking-wider">
        {dgettext("sheets", "Advanced")}
      </div>

      <%!-- Scope selector (own blocks only) --%>
      <div :if={!@is_inherited && @can_edit} class="flex items-center gap-2">
        <span class="text-sm text-base-content/70">{dgettext("sheets", "Scope")}</span>
        <div class="flex gap-1">
          <button
            type="button"
            class={["btn btn-sm", @block.scope == "self" && "btn-active"]}
            data-event="change_block_scope"
            data-params={Jason.encode!(%{scope: "self", id: @block.id})}
            data-close-on-click="false"
          >
            {dgettext("sheets", "Self")}
          </button>
          <button
            type="button"
            class={["btn btn-sm", @block.scope == "children" && "btn-active"]}
            data-event="change_block_scope"
            data-params={Jason.encode!(%{scope: "children", id: @block.id})}
            data-close-on-click="false"
          >
            {dgettext("sheets", "Children")}
          </button>
        </div>
      </div>

      <%!-- Required toggle (only when scope=children) --%>
      <label
        :if={!@is_inherited && @block.scope == "children" && @can_edit}
        class="flex items-center gap-2 cursor-pointer"
        data-event="toggle_required"
        data-params={Jason.encode!(%{id: @block.id})}
        data-close-on-click="false"
      >
        <input type="checkbox" class="checkbox checkbox-sm" checked={@block.required} />
        <span class="text-sm text-base-content/70">{dgettext("sheets", "Required")}</span>
      </label>

      <%!-- Variable name (read-only) --%>
      <div :if={@is_variable && @block.variable_name} class="flex items-center gap-2">
        <.icon name="variable" class="size-4 text-base-content/50" />
        <code class="text-sm text-base-content/60 bg-base-300 px-1.5 py-0.5 rounded">
          {@block.variable_name}
        </code>
      </div>

      <%!-- Re-attach button (detached blocks) --%>
      <button
        :if={@is_inherited && @block.detached && @can_edit}
        type="button"
        class="btn btn-ghost btn-sm gap-1"
        data-event="reattach_block"
        data-params={Jason.encode!(%{id: @block.id})}
      >
        <.icon name="link" class="size-4" />
        {dgettext("sheets", "Re-attach to source")}
      </button>
    </div>
    """
  end
end
