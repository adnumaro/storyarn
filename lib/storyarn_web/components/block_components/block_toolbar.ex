defmodule StoryarnWeb.Components.BlockComponents.BlockToolbar do
  @moduledoc """
  Hover toolbar for sheet blocks.

  Renders a minimal set of actions above the block:
  - Constant toggle (for variable-capable types)
  - Variable name (inline display / edit)
  - Scope Self/Children + Required checkbox (own blocks only)
  - Reference allowed_types checkboxes (reference blocks only)
  - Config gear — popover with type-specific config (types that have config beyond toolbar)
  """

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.Components.CoreComponents, only: [icon: 1]
  import StoryarnWeb.Components.BlockComponents.ConfigPopovers.TextConfig
  import StoryarnWeb.Components.BlockComponents.ConfigPopovers.NumberConfig
  import StoryarnWeb.Components.BlockComponents.ConfigPopovers.BooleanConfig
  import StoryarnWeb.Components.BlockComponents.ConfigPopovers.SelectConfig
  import StoryarnWeb.Components.BlockComponents.ConfigPopovers.DateConfig

  alias Storyarn.Sheets.Block

  @non_constant_types ~w(reference table)
  @no_popover_types ~w(reference table)

  attr :block, :map, required: true
  attr :can_edit, :boolean, default: false
  attr :target, :any, default: nil
  attr :component_id, :string, default: nil

  def block_toolbar(assigns) do
    show_constant = assigns.block.type not in @non_constant_types

    is_variable =
      Block.can_be_variable?(assigns.block.type) &&
        !assigns.block.is_constant &&
        assigns.block.variable_name != nil

    is_referenced = Map.get(assigns.block, :is_referenced, false)
    is_inherited = assigns.block.inherited_from_block_id != nil
    has_popover = assigns.block.type not in @no_popover_types

    config = assigns.block.config || %{}
    allowed_types = config["allowed_types"] || ["sheet", "flow"]

    # Whether there are toolbar items before the scope section (for border-l divider)
    has_left_items = show_constant || is_variable

    assigns =
      assigns
      |> assign(:show_constant, show_constant)
      |> assign(:show_variable_name, is_variable)
      |> assign(:is_referenced, is_referenced)
      |> assign(:is_inherited, is_inherited)
      |> assign(:has_popover, has_popover)
      |> assign(:allowed_types, allowed_types)
      |> assign(:has_left_items, has_left_items)

    ~H"""
    <div
      :if={@can_edit}
      data-toolbar
      class="absolute -top-11 left-1/2 -translate-x-1/2 flex items-center gap-0.5 p-1 bg-base-200 border border-base-300 rounded-xl shadow-lg opacity-0 group-hover:opacity-100 transition-opacity pointer-events-none group-hover:pointer-events-auto z-10"
    >
      <%!-- Constant toggle --%>
      <button
        :if={@show_constant}
        type="button"
        class={["btn btn-ghost btn-sm btn-square", @block.is_constant && "btn-active"]}
        title={
          if @block.is_constant,
            do: dgettext("sheets", "Make variable"),
            else: dgettext("sheets", "Make constant")
        }
        phx-click="toolbar_toggle_constant"
        phx-value-id={@block.id}
        phx-target={@target}
      >
        <.icon name={if @block.is_constant, do: "lock", else: "unlock"} class="size-4" />
      </button>

      <%!-- Variable name (inline display / edit) --%>
      <div
        :if={@show_variable_name}
        class="flex items-center gap-1 px-1.5 border-l border-base-300"
        title={@block.variable_name}
      >
        <.icon name="variable" class="size-3.5 text-base-content/50 shrink-0" />
        <%= if @is_referenced do %>
          <code
            class="text-xs text-base-content/60 bg-base-300/50 px-1 py-0.5 rounded max-w-32 truncate"
            title={@block.variable_name}
          >
            {@block.variable_name}
          </code>
        <% else %>
          <form phx-change="update_variable_name" phx-target={@target} class="flex">
            <input type="hidden" name="block_id" value={@block.id} />
            <input
              type="text"
              name="variable_name"
              id={"variable-name-#{@block.id}"}
              class="input input-xs font-mono text-xs bg-base-300/30 min-w-0"
              style="field-sizing: content; min-width: 4ch; max-width: 20ch;"
              value={@block.variable_name}
              title={@block.variable_name}
              phx-debounce="blur"
            />
          </form>
        <% end %>
      </div>

      <%!-- Scope buttons (own blocks only) --%>
      <div
        :if={!@is_inherited}
        class={["flex items-center gap-0.5 px-1", @has_left_items && "border-l border-base-300"]}
      >
        <button
          type="button"
          class={["btn btn-ghost btn-sm", @block.scope == "self" && "btn-active"]}
          title={dgettext("sheets", "Scope: Self only")}
          phx-click="change_block_scope"
          phx-value-scope="self"
          phx-value-id={@block.id}
          phx-target={@target}
        >
          {dgettext("sheets", "Self")}
        </button>
        <button
          type="button"
          class={["btn btn-ghost btn-sm", @block.scope == "children" && "btn-active"]}
          title={dgettext("sheets", "Scope: Inherited by children")}
          phx-click="change_block_scope"
          phx-value-scope="children"
          phx-value-id={@block.id}
          phx-target={@target}
        >
          {dgettext("sheets", "Children")}
        </button>

        <%!-- Required checkbox (only when scope=children) --%>
        <button
          :if={@block.scope == "children"}
          type="button"
          class="btn btn-ghost btn-sm gap-1 ml-1"
          title={dgettext("sheets", "Required for children")}
          phx-click="toggle_required"
          phx-value-id={@block.id}
          phx-target={@target}
          role="checkbox"
          aria-checked={to_string(@block.required)}
        >
          <.icon name={if @block.required, do: "square-check", else: "square"} class="size-4" />
          <span class="text-xs text-base-content/70">{dgettext("sheets", "Req")}</span>
        </button>
      </div>

      <%!-- Reference allowed_types (reference blocks only) --%>
      <div
        :if={@block.type == "reference" && !@is_inherited}
        class="flex items-center gap-1.5 px-1.5 border-l border-base-300"
      >
        <button
          type="button"
          class="btn btn-ghost btn-sm gap-1"
          phx-click="toggle_allowed_type"
          phx-value-block_id={@block.id}
          phx-value-type="sheet"
          phx-target={@target}
        >
          <.icon name={if "sheet" in @allowed_types, do: "square-check", else: "square"} class="size-4" />
          <span class="text-sm text-base-content/70">{dgettext("sheets", "Sheets")}</span>
        </button>
        <button
          type="button"
          class="btn btn-ghost btn-sm gap-1"
          phx-click="toggle_allowed_type"
          phx-value-block_id={@block.id}
          phx-value-type="flow"
          phx-target={@target}
        >
          <.icon name={if "flow" in @allowed_types, do: "square-check", else: "square"} class="size-4" />
          <span class="text-sm text-base-content/70">{dgettext("sheets", "Flows")}</span>
        </button>
      </div>

      <%!-- Config gear — popover with type-specific config --%>
      <.config_trigger
        :if={@has_popover}
        block={@block}
        can_edit={@can_edit}
        target={@target}
        component_id={@component_id}
      />
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Popover content — dispatches to the right config component by block type
  # ---------------------------------------------------------------------------

  attr :block, :map, required: true
  attr :can_edit, :boolean, required: true

  defp popover_content(%{block: %{type: "number"}} = assigns) do
    ~H"<.number_config block={@block} can_edit={@can_edit} />"
  end

  defp popover_content(%{block: %{type: "boolean"}} = assigns) do
    ~H"<.boolean_config block={@block} can_edit={@can_edit} />"
  end

  defp popover_content(%{block: %{type: type}} = assigns) when type in ~w(select multi_select) do
    ~H"<.select_config block={@block} can_edit={@can_edit} />"
  end

  defp popover_content(%{block: %{type: "date"}} = assigns) do
    ~H"<.date_config block={@block} can_edit={@can_edit} />"
  end

  defp popover_content(assigns) do
    ~H"<.text_config block={@block} can_edit={@can_edit} />"
  end

  # ---------------------------------------------------------------------------
  # Config trigger — popover or plain button
  # ---------------------------------------------------------------------------

  attr :block, :map, required: true
  attr :can_edit, :boolean, required: true
  attr :target, :any, default: nil
  attr :component_id, :string, default: nil

  defp config_trigger(assigns) do
    assigns = assign(assigns, :popover_width, popover_width(assigns.block.type))

    ~H"""
    <div
      phx-hook="ToolbarPopover"
      id={"config-popover-#{@block.id}"}
      data-width={@popover_width}
      data-target={"##{@component_id}"}
    >
      <button
        type="button"
        data-role="trigger"
        class="btn btn-ghost btn-sm btn-square"
        title={dgettext("sheets", "Configure")}
      >
        <.icon name="settings" class="size-4" />
      </button>
      <div data-role="popover-template" hidden>
        <.popover_content block={@block} can_edit={@can_edit} />
      </div>
    </div>
    """
  end

  defp popover_width(type) when type in ~w(select multi_select), do: "20rem"
  defp popover_width(_type), do: "16rem"
end
