defmodule StoryarnWeb.Components.BlockComponents.ConfigPopovers.SelectConfig do
  @moduledoc """
  Popover content for `select` and `multi_select` block configuration.

  Renders an editable options list (key + label per option, add/remove),
  placeholder, max selections (multi_select only), and the shared advanced section.
  Option inputs use `data-blur-event`, add/remove buttons use `data-event`.
  """

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.Components.CoreComponents, only: [icon: 1]
  import StoryarnWeb.Components.BlockComponents.BlockAdvancedConfig

  attr :block, :map, required: true
  attr :can_edit, :boolean, default: false

  def select_config(assigns) do
    config = assigns.block.config || %{}

    assigns =
      assigns
      |> assign(:options, config["options"] || [])
      |> assign(:placeholder, config["placeholder"] || "")
      |> assign(:max_options, config["max_options"])
      |> assign(:is_multi, assigns.block.type == "multi_select")

    ~H"""
    <div class="p-3 space-y-3 min-w-0">
      <%!-- Options list --%>
      <div>
        <label class="text-xs text-base-content/60">{dgettext("sheets", "Options")}</label>
        <div class="space-y-1 mt-1 max-h-48 overflow-y-auto">
          <div
            :for={{opt, idx} <- Enum.with_index(@options)}
            class="flex items-center gap-1"
          >
            <input
              type="text"
              class="input input-xs input-bordered w-16 font-mono"
              value={opt["key"]}
              placeholder={dgettext("sheets", "key")}
              data-blur-event="update_select_option"
              data-params={Jason.encode!(%{block_id: @block.id, index: idx, key_field: "key"})}
              disabled={!@can_edit}
            />
            <input
              type="text"
              class="input input-xs input-bordered flex-1"
              value={opt["value"]}
              placeholder={dgettext("sheets", "Label")}
              data-blur-event="update_select_option"
              data-params={Jason.encode!(%{block_id: @block.id, index: idx, key_field: "value"})}
              disabled={!@can_edit}
            />
            <button
              :if={@can_edit}
              type="button"
              class="btn btn-ghost btn-xs btn-square text-error"
              data-event="remove_select_option"
              data-params={Jason.encode!(%{block_id: @block.id, index: idx})}
              data-close-on-click="false"
            >
              <.icon name="x" class="size-3" />
            </button>
          </div>
        </div>
        <button
          :if={@can_edit}
          type="button"
          class="btn btn-ghost btn-xs mt-1"
          data-event="add_select_option"
          data-params={Jason.encode!(%{block_id: @block.id})}
          data-close-on-click="false"
        >
          <.icon name="plus" class="size-3" />
          {dgettext("sheets", "Add option")}
        </button>
      </div>

      <%!-- Placeholder --%>
      <div>
        <label class="text-xs text-base-content/60">{dgettext("sheets", "Placeholder")}</label>
        <input
          type="text"
          class="input input-xs input-bordered w-full mt-1"
          value={@placeholder}
          placeholder={dgettext("sheets", "Select...")}
          data-blur-event="save_config_field"
          data-params={Jason.encode!(%{block_id: @block.id, field: "placeholder"})}
          disabled={!@can_edit}
        />
      </div>

      <%!-- Max Selections (multi_select only) --%>
      <div :if={@is_multi}>
        <label class="text-xs text-base-content/60">
          {dgettext("sheets", "Max Selections")}
        </label>
        <input
          type="number"
          class="input input-xs input-bordered w-full mt-1"
          value={@max_options}
          placeholder={dgettext("sheets", "No limit")}
          min="1"
          data-blur-event="save_config_field"
          data-params={Jason.encode!(%{block_id: @block.id, field: "max_options"})}
          disabled={!@can_edit}
        />
      </div>

      <%!-- Advanced section --%>
      <.block_advanced_config block={@block} can_edit={@can_edit} />
    </div>
    """
  end
end
