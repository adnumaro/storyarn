defmodule StoryarnWeb.Components.BlockComponents.BlockToolbar do
  @moduledoc """
  Hover toolbar for sheet blocks.

  Renders a minimal set of actions above the block:
  - Duplicate
  - Constant toggle (for variable-capable types)
  - Config gear — popover with type-specific config + shared Advanced section
  - [...] overflow menu with Delete + inherited actions
  """

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.Components.CoreComponents, only: [icon: 1]
  import StoryarnWeb.Components.BlockComponents.ConfigPopovers.TextConfig
  import StoryarnWeb.Components.BlockComponents.ConfigPopovers.NumberConfig
  import StoryarnWeb.Components.BlockComponents.ConfigPopovers.BooleanConfig
  import StoryarnWeb.Components.BlockComponents.ConfigPopovers.SelectConfig
  import StoryarnWeb.Components.BlockComponents.ConfigPopovers.DateConfig
  import StoryarnWeb.Components.BlockComponents.ConfigPopovers.ReferenceConfig
  import StoryarnWeb.Components.BlockComponents.BlockAdvancedConfig

  @non_constant_types ~w(reference table)

  attr :block, :map, required: true
  attr :can_edit, :boolean, default: false
  attr :is_inherited, :boolean, default: false
  attr :target, :any, default: nil
  attr :component_id, :string, default: nil

  def block_toolbar(assigns) do
    show_constant = assigns.block.type not in @non_constant_types

    assigns =
      assigns
      |> assign(:show_constant, show_constant)

    ~H"""
    <div
      :if={@can_edit}
      data-toolbar
      class="absolute -top-9 left-0 flex items-center gap-0.5 p-1 bg-base-200 border border-base-300 rounded-xl shadow-lg opacity-0 group-hover:opacity-100 transition-opacity pointer-events-none group-hover:pointer-events-auto"
    >
      <%!-- Duplicate --%>
      <button
        type="button"
        class="btn btn-ghost btn-xs btn-square"
        title={dgettext("sheets", "Duplicate")}
        phx-click="duplicate_block"
        phx-value-id={@block.id}
        phx-target={@target}
      >
        <.icon name="copy" class="size-3.5" />
      </button>

      <%!-- Constant toggle --%>
      <button
        :if={@show_constant}
        type="button"
        class={["btn btn-ghost btn-xs btn-square", @block.is_constant && "btn-active"]}
        title={
          if @block.is_constant,
            do: dgettext("sheets", "Make variable"),
            else: dgettext("sheets", "Make constant")
        }
        phx-click="toolbar_toggle_constant"
        phx-value-id={@block.id}
        phx-target={@target}
      >
        <.icon name={if @block.is_constant, do: "lock", else: "unlock"} class="size-3.5" />
      </button>

      <%!-- Config gear — popover with type-specific config --%>
      <.config_trigger
        block={@block}
        can_edit={@can_edit}
        target={@target}
        component_id={@component_id}
      />

      <%!-- Overflow menu --%>
      <div class="dropdown dropdown-end">
        <div
          tabindex="0"
          role="button"
          class="btn btn-ghost btn-xs btn-square"
        >
          <.icon name="ellipsis-vertical" class="size-3.5" />
        </div>
        <ul
          tabindex="0"
          class="dropdown-content z-[1030] menu p-2 shadow-lg bg-base-200 rounded-box w-52"
        >
          <%!-- Inherited block actions --%>
          <li :if={@is_inherited}>
            <button
              phx-click="navigate_to_source"
              phx-value-id={@block.id}
              phx-target={@target}
            >
              <.icon name="arrow-up-right" class="size-4" />
              {dgettext("sheets", "Go to source")}
            </button>
          </li>
          <li :if={@is_inherited}>
            <button
              phx-click="detach_inherited_block"
              phx-value-id={@block.id}
              phx-target={@target}
            >
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

          <div :if={@is_inherited} class="divider my-0.5"></div>

          <%!-- Delete --%>
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

  defp popover_content(%{block: %{type: "reference"}} = assigns) do
    ~H"<.reference_config block={@block} can_edit={@can_edit} />"
  end

  defp popover_content(%{block: %{type: "table"}} = assigns) do
    ~H"""
    <div class="p-3 min-w-0">
      <.block_advanced_config block={@block} can_edit={@can_edit} standalone={true} />
    </div>
    """
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
        class="btn btn-ghost btn-xs btn-square"
        title={dgettext("sheets", "Configure")}
      >
        <.icon name="settings" class="size-3.5" />
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
