defmodule StoryarnWeb.Components.BlockComponents.ConfigPanel do
  @moduledoc false

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.CoreComponents, only: [icon: 1]

  @doc """
  Renders the block configuration panel (right sidebar).

  ## Examples

      <.config_panel :if={@configuring_block} block={@configuring_block} />
  """
  attr :block, :map, required: true

  def config_panel(assigns) do
    config = assigns.block.config || %{}

    assigns =
      assigns
      |> assign(:label, config["label"] || "")
      |> assign(:placeholder, config["placeholder"] || "")
      |> assign(:options, config["options"] || [])
      |> assign(:max_length, config["max_length"])
      |> assign(:min, config["min"])
      |> assign(:max, config["max"])
      |> assign(:max_options, config["max_options"])
      |> assign(:min_date, config["min_date"])
      |> assign(:max_date, config["max_date"])

    ~H"""
    <div class="fixed inset-y-0 right-0 w-80 bg-base-200 shadow-xl z-50 flex flex-col">
      <%!-- Header --%>
      <div class="flex items-center justify-between p-4 border-b border-base-300">
        <h3 class="font-semibold">{gettext("Configure Block")}</h3>
        <button type="button" class="btn btn-ghost btn-sm btn-square" phx-click="close_config_panel">
          <.icon name="x" class="size-5" />
        </button>
      </div>

      <%!-- Content --%>
      <div class="flex-1 overflow-y-auto p-4">
        <form phx-change="save_block_config" class="space-y-4">
          <%!-- Block Type (read-only) --%>
          <div>
            <label class="label">
              <span class="label-text">{gettext("Type")}</span>
            </label>
            <div class="badge badge-neutral">{@block.type}</div>
          </div>

          <%!-- Label field (for all types except divider) --%>
          <div :if={@block.type != "divider"}>
            <label class="label">
              <span class="label-text">{gettext("Label")}</span>
            </label>
            <input
              type="text"
              name="config[label]"
              value={@label}
              class="input input-bordered w-full"
              placeholder={gettext("Enter label...")}
            />
          </div>

          <%!-- Placeholder field --%>
          <div :if={@block.type in ["text", "number", "select", "rich_text", "multi_select"]}>
            <label class="label">
              <span class="label-text">{gettext("Placeholder")}</span>
            </label>
            <input
              type="text"
              name="config[placeholder]"
              value={@placeholder}
              class="input input-bordered w-full"
              placeholder={gettext("Enter placeholder...")}
            />
          </div>

          <%!-- Max Length (for text and rich_text) --%>
          <div :if={@block.type in ["text", "rich_text"]}>
            <label class="label">
              <span class="label-text">{gettext("Max Length")}</span>
            </label>
            <input
              type="number"
              name="config[max_length]"
              value={@max_length}
              class="input input-bordered w-full"
              placeholder={gettext("No limit")}
              min="1"
            />
          </div>

          <%!-- Min/Max (for number) --%>
          <div :if={@block.type == "number"} class="grid grid-cols-2 gap-2">
            <div>
              <label class="label">
                <span class="label-text">{gettext("Min")}</span>
              </label>
              <input
                type="number"
                name="config[min]"
                value={@min}
                class="input input-bordered w-full"
                placeholder={gettext("No min")}
              />
            </div>
            <div>
              <label class="label">
                <span class="label-text">{gettext("Max")}</span>
              </label>
              <input
                type="number"
                name="config[max]"
                value={@max}
                class="input input-bordered w-full"
                placeholder={gettext("No max")}
              />
            </div>
          </div>

          <%!-- Date Range (for date) --%>
          <div :if={@block.type == "date"} class="grid grid-cols-2 gap-2">
            <div>
              <label class="label">
                <span class="label-text">{gettext("Min Date")}</span>
              </label>
              <input
                type="date"
                name="config[min_date]"
                value={@min_date}
                class="input input-bordered w-full"
              />
            </div>
            <div>
              <label class="label">
                <span class="label-text">{gettext("Max Date")}</span>
              </label>
              <input
                type="date"
                name="config[max_date]"
                value={@max_date}
                class="input input-bordered w-full"
              />
            </div>
          </div>

          <%!-- Max Options (for multi_select) --%>
          <div :if={@block.type == "multi_select"}>
            <label class="label">
              <span class="label-text">{gettext("Max Selections")}</span>
            </label>
            <input
              type="number"
              name="config[max_options]"
              value={@max_options}
              class="input input-bordered w-full"
              placeholder={gettext("No limit")}
              min="1"
            />
          </div>
        </form>

        <%!-- Options (for select and multi_select) - Outside form to avoid nested form issues --%>
        <div :if={@block.type in ["select", "multi_select"]} class="mt-4">
          <label class="label">
            <span class="label-text">{gettext("Options")}</span>
          </label>
          <div class="space-y-2">
            <div :for={{opt, idx} <- Enum.with_index(@options)} class="flex items-center gap-2">
              <form
                phx-change="update_select_option"
                phx-value-index={idx}
                class="flex items-center gap-2 flex-1"
              >
                <input
                  type="text"
                  name="key"
                  value={opt["key"]}
                  class="input input-bordered input-sm w-20"
                  placeholder={gettext("Key")}
                />
                <input
                  type="text"
                  name="value"
                  value={opt["value"]}
                  class="input input-bordered input-sm flex-1"
                  placeholder={gettext("Label")}
                />
              </form>
              <button
                type="button"
                class="btn btn-ghost btn-sm btn-square text-error"
                phx-click="remove_select_option"
                phx-value-index={idx}
              >
                <.icon name="x" class="size-4" />
              </button>
            </div>
            <button type="button" class="btn btn-ghost btn-sm" phx-click="add_select_option">
              <.icon name="plus" class="size-4" />
              {gettext("Add option")}
            </button>
          </div>
        </div>
      </div>
    </div>
    <%!-- Backdrop --%>
    <div class="fixed inset-0 bg-black/20 z-40" phx-click="close_config_panel"></div>
    """
  end
end
