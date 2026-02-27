defmodule StoryarnWeb.Components.BlockComponents.ConfigPopovers.BooleanConfig do
  @moduledoc """
  Popover content for `boolean` block configuration.

  Renders mode selector (two-state vs tri-state), custom label inputs,
  and the shared advanced section.
  Mode toggle uses `data-event` (click) with `data-close-on-click="false"`.
  Label inputs use `data-blur-event` for save-on-blur via ToolbarPopover hook.
  """

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.Components.BlockComponents.BlockAdvancedConfig

  attr :block, :map, required: true
  attr :can_edit, :boolean, default: false

  def boolean_config(assigns) do
    config = assigns.block.config || %{}

    assigns =
      assigns
      |> assign(:mode, config["mode"] || "two_state")
      |> assign(:true_label, config["true_label"] || "")
      |> assign(:false_label, config["false_label"] || "")
      |> assign(:neutral_label, config["neutral_label"] || "")

    ~H"""
    <div class="p-3 space-y-3 min-w-0">
      <%!-- Mode toggle --%>
      <div>
        <label class="text-xs text-base-content/60">
          {dgettext("sheets", "Three states (Yes/Neutral/No)")}
        </label>
        <label
          class="flex items-center gap-2 cursor-pointer mt-1"
          data-event="save_config_field"
          data-params={
            Jason.encode!(%{
              block_id: @block.id,
              field: "mode",
              value: if(@mode == "tri_state", do: "two_state", else: "tri_state")
            })
          }
          data-close-on-click="false"
        >
          <input
            type="checkbox"
            class="toggle toggle-xs"
            checked={@mode == "tri_state"}
            disabled={!@can_edit}
          />
          <span class="text-xs text-base-content/70">
            {if @mode == "tri_state",
              do: dgettext("sheets", "Enabled"),
              else: dgettext("sheets", "Disabled")}
          </span>
        </label>
      </div>

      <%!-- Custom Labels --%>
      <div>
        <label class="text-xs text-base-content/60">{dgettext("sheets", "Custom Labels")}</label>
        <div class="grid grid-cols-2 gap-2 mt-1">
          <div>
            <input
              type="text"
              class="input input-xs input-bordered w-full"
              value={@true_label}
              placeholder={dgettext("sheets", "Yes")}
              data-blur-event="save_config_field"
              data-params={Jason.encode!(%{block_id: @block.id, field: "true_label"})}
              disabled={!@can_edit}
            />
            <span class="text-xs text-base-content/50">{dgettext("sheets", "True")}</span>
          </div>
          <div>
            <input
              type="text"
              class="input input-xs input-bordered w-full"
              value={@false_label}
              placeholder={dgettext("sheets", "No")}
              data-blur-event="save_config_field"
              data-params={Jason.encode!(%{block_id: @block.id, field: "false_label"})}
              disabled={!@can_edit}
            />
            <span class="text-xs text-base-content/50">{dgettext("sheets", "False")}</span>
          </div>
        </div>
        <%!-- Neutral label (tri-state only) --%>
        <div :if={@mode == "tri_state"} class="mt-2">
          <input
            type="text"
            class="input input-xs input-bordered w-full"
            value={@neutral_label}
            placeholder={dgettext("sheets", "Neutral")}
            data-blur-event="save_config_field"
            data-params={Jason.encode!(%{block_id: @block.id, field: "neutral_label"})}
            disabled={!@can_edit}
          />
          <span class="text-xs text-base-content/50">
            {dgettext("sheets", "Neutral")}
          </span>
        </div>
      </div>

      <%!-- Advanced section --%>
      <.block_advanced_config block={@block} can_edit={@can_edit} />
    </div>
    """
  end
end
