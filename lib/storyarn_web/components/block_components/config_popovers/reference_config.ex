defmodule StoryarnWeb.Components.BlockComponents.ConfigPopovers.ReferenceConfig do
  @moduledoc """
  Popover content for `reference` block configuration.

  Renders allowed type checkboxes (sheets, flows) and the shared advanced section.
  Checkboxes use `data-event` on the `<label>` for click delegation via ToolbarPopover.
  """

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.Components.BlockComponents.BlockAdvancedConfig

  attr :block, :map, required: true
  attr :can_edit, :boolean, default: false

  def reference_config(assigns) do
    config = assigns.block.config || %{}
    assigns = assign(assigns, :allowed_types, config["allowed_types"] || ["sheet", "flow"])

    ~H"""
    <div class="p-3 space-y-3 min-w-0">
      <%!-- Allowed Types --%>
      <div>
        <label class="text-xs text-base-content/60">
          {dgettext("sheets", "Allowed Types")}
        </label>
        <div class="flex flex-col gap-2 mt-1">
          <label
            class="flex items-center gap-2 cursor-pointer"
            data-event="toggle_allowed_type"
            data-params={Jason.encode!(%{block_id: @block.id, type: "sheet"})}
            data-close-on-click="false"
          >
            <input
              type="checkbox"
              class="checkbox checkbox-xs"
              checked={"sheet" in @allowed_types}
              disabled={!@can_edit}
            />
            <span class="text-xs text-base-content/70">{dgettext("sheets", "Sheets")}</span>
          </label>
          <label
            class="flex items-center gap-2 cursor-pointer"
            data-event="toggle_allowed_type"
            data-params={Jason.encode!(%{block_id: @block.id, type: "flow"})}
            data-close-on-click="false"
          >
            <input
              type="checkbox"
              class="checkbox checkbox-xs"
              checked={"flow" in @allowed_types}
              disabled={!@can_edit}
            />
            <span class="text-xs text-base-content/70">{dgettext("sheets", "Flows")}</span>
          </label>
        </div>
      </div>

      <%!-- Advanced section --%>
      <.block_advanced_config block={@block} can_edit={@can_edit} />
    </div>
    """
  end
end
