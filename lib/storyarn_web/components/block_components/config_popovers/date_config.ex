defmodule StoryarnWeb.Components.BlockComponents.ConfigPopovers.DateConfig do
  @moduledoc """
  Popover content for `date` block configuration.

  Renders min/max date inputs and the shared advanced section.
  All inputs use `data-blur-event` for save-on-blur via ToolbarPopover hook.
  """

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  attr :block, :map, required: true
  attr :can_edit, :boolean, default: false

  def date_config(assigns) do
    config = assigns.block.config || %{}

    assigns =
      assigns
      |> assign(:min_date, config["min_date"])
      |> assign(:max_date, config["max_date"])

    ~H"""
    <div class="p-3 space-y-3 min-w-0">
      <%!-- Date Range --%>
      <div class="grid grid-cols-2 gap-2">
        <div>
          <label class="text-sm text-base-content/60">{dgettext("sheets", "Min Date")}</label>
          <input
            type="date"
            class="input input-sm input-bordered w-full mt-1"
            value={@min_date}
            data-blur-event="save_config_field"
            data-params={Jason.encode!(%{block_id: @block.id, field: "min_date"})}
            disabled={!@can_edit}
          />
        </div>
        <div>
          <label class="text-sm text-base-content/60">{dgettext("sheets", "Max Date")}</label>
          <input
            type="date"
            class="input input-sm input-bordered w-full mt-1"
            value={@max_date}
            data-blur-event="save_config_field"
            data-params={Jason.encode!(%{block_id: @block.id, field: "max_date"})}
            disabled={!@can_edit}
          />
        </div>
      </div>
    </div>
    """
  end
end
