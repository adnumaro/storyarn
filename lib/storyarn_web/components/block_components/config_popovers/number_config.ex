defmodule StoryarnWeb.Components.BlockComponents.ConfigPopovers.NumberConfig do
  @moduledoc """
  Popover content for `number` block configuration.

  Renders min, max, step, placeholder inputs, and the shared advanced section.
  All inputs use `data-blur-event` for save-on-blur via ToolbarPopover hook.
  """

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  attr :block, :map, required: true
  attr :can_edit, :boolean, default: false

  def number_config(assigns) do
    config = assigns.block.config || %{}

    assigns =
      assigns
      |> assign(:min, config["min"])
      |> assign(:max, config["max"])
      |> assign(:step, config["step"])
      |> assign(:placeholder, config["placeholder"] || "")

    ~H"""
    <div class="p-3 space-y-3 min-w-0">
      <%!-- Min / Max --%>
      <div class="grid grid-cols-2 gap-2">
        <div>
          <label class="text-sm text-base-content/60">{dgettext("sheets", "Min")}</label>
          <input
            type="number"
            class="input input-sm input-bordered w-full mt-1"
            value={@min}
            placeholder={dgettext("sheets", "No min")}
            data-blur-event="save_config_field"
            data-params={Jason.encode!(%{block_id: @block.id, field: "min"})}
            disabled={!@can_edit}
          />
        </div>
        <div>
          <label class="text-sm text-base-content/60">{dgettext("sheets", "Max")}</label>
          <input
            type="number"
            class="input input-sm input-bordered w-full mt-1"
            value={@max}
            placeholder={dgettext("sheets", "No max")}
            data-blur-event="save_config_field"
            data-params={Jason.encode!(%{block_id: @block.id, field: "max"})}
            disabled={!@can_edit}
          />
        </div>
      </div>

      <%!-- Step --%>
      <div>
        <label class="text-sm text-base-content/60">{dgettext("sheets", "Step")}</label>
        <input
          type="number"
          class="input input-sm input-bordered w-full mt-1"
          value={@step}
          placeholder="1"
          min="0.001"
          data-blur-event="save_config_field"
          data-params={Jason.encode!(%{block_id: @block.id, field: "step"})}
          disabled={!@can_edit}
        />
      </div>

      <%!-- Placeholder --%>
      <div>
        <label class="text-sm text-base-content/60">{dgettext("sheets", "Placeholder")}</label>
        <input
          type="text"
          class="input input-sm input-bordered w-full mt-1"
          value={@placeholder}
          placeholder={dgettext("sheets", "Enter placeholder...")}
          data-blur-event="save_config_field"
          data-params={Jason.encode!(%{block_id: @block.id, field: "placeholder"})}
          disabled={!@can_edit}
        />
      </div>
    </div>
    """
  end
end
