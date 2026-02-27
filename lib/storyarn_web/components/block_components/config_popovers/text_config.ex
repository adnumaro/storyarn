defmodule StoryarnWeb.Components.BlockComponents.ConfigPopovers.TextConfig do
  @moduledoc """
  Popover content for `text` and `rich_text` block configuration.

  Renders placeholder, max_length inputs, and the shared advanced section.
  All inputs use `data-blur-event` for save-on-blur via ToolbarPopover hook.
  """

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  attr :block, :map, required: true
  attr :can_edit, :boolean, default: false

  def text_config(assigns) do
    config = assigns.block.config || %{}

    assigns =
      assigns
      |> assign(:placeholder, config["placeholder"] || "")
      |> assign(:max_length, config["max_length"])

    ~H"""
    <div class="p-3 space-y-3 min-w-0">
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

      <%!-- Max Length --%>
      <div>
        <label class="text-sm text-base-content/60">{dgettext("sheets", "Max Length")}</label>
        <input
          type="number"
          class="input input-sm input-bordered w-full mt-1"
          value={@max_length}
          placeholder={dgettext("sheets", "No limit")}
          min="1"
          data-blur-event="save_config_field"
          data-params={Jason.encode!(%{block_id: @block.id, field: "max_length"})}
          disabled={!@can_edit}
        />
      </div>
    </div>
    """
  end
end
