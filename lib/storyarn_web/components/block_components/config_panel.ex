defmodule StoryarnWeb.Components.BlockComponents.ConfigPanel do
  @moduledoc false

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.Components.CoreComponents, only: [icon: 1]

  @doc """
  Renders the block configuration panel (right sidebar).

  ## Examples

      <.config_panel :if={@configuring_block} block={@configuring_block} />
  """
  attr :block, :map, required: true
  attr :target, :any, default: nil

  def config_panel(assigns) do
    assigns =
      assigns
      |> assign_config_fields()
      |> assign_block_fields()

    ~H"""
    <div class="fixed inset-y-0 right-0 w-80 bg-base-200 shadow-xl z-50 flex flex-col">
      <%!-- Header --%>
      <div class="flex items-center justify-between p-4 border-b border-base-300">
        <h3 class="font-semibold">{gettext("Configure Block")}</h3>
        <button
          type="button"
          class="btn btn-ghost btn-sm btn-square"
          phx-click="close_config_panel"
          phx-target={@target}
        >
          <.icon name="x" class="size-5" />
        </button>
      </div>

      <%!-- Content --%>
      <div class="flex-1 overflow-y-auto p-4">
        <form phx-change="save_block_config" phx-target={@target} class="space-y-4">
          <%!-- Block Type (read-only) --%>
          <div>
            <label class="label">
              <span class="label-text">{gettext("Type")}</span>
            </label>
            <div class="flex items-center gap-2">
              <div class="badge badge-neutral">{@block.type}</div>
              <div :if={@is_inherited} class="badge badge-info badge-outline badge-sm">
                {gettext("Inherited")}
              </div>
              <div :if={@is_detached} class="badge badge-warning badge-outline badge-sm">
                {gettext("Detached")}
              </div>
            </div>
          </div>

          <%!-- Scope selector (only for non-inherited blocks) --%>
          <div :if={!@is_inherited && @block.type != "divider"}>
            <label class="label">
              <span class="label-text">{gettext("Scope")}</span>
            </label>
            <div class="flex flex-col gap-2">
              <label class="flex items-center gap-2 cursor-pointer text-sm">
                <input
                  type="radio"
                  name="scope"
                  value="self"
                  checked={@scope == "self"}
                  class="radio radio-sm"
                  phx-click="change_block_scope"
                  phx-value-scope="self"
                  phx-target={@target}
                />
                <span>{gettext("This page only")}</span>
              </label>
              <label class="flex items-center gap-2 cursor-pointer text-sm">
                <input
                  type="radio"
                  name="scope"
                  value="children"
                  checked={@scope == "children"}
                  class="radio radio-sm"
                  phx-click="change_block_scope"
                  phx-value-scope="children"
                  phx-target={@target}
                />
                <span>{gettext("This page and all children")}</span>
              </label>
            </div>
            <p :if={@scope == "children"} class="text-xs text-base-content/50 mt-1">
              {gettext("Changes to this property's definition will sync to all children.")}
            </p>
          </div>

          <%!-- Required toggle (only for inheritable blocks) --%>
          <div :if={@scope == "children" && !@is_inherited} class="form-control">
            <label class="label cursor-pointer justify-start gap-3">
              <input
                type="checkbox"
                name="required"
                value="true"
                checked={@required}
                class="toggle toggle-sm"
                phx-click="toggle_required"
                phx-target={@target}
              />
              <span class="label-text">{gettext("Required")}</span>
            </label>
            <p class="text-xs text-base-content/50 ml-12">
              {gettext("Mark this property as required for children.")}
            </p>
          </div>

          <%!-- Re-attach option for detached blocks --%>
          <div :if={@is_detached}>
            <button
              type="button"
              class="btn btn-sm btn-outline btn-info w-full"
              phx-click="reattach_block"
              phx-value-id={@block.id}
              phx-target={@target}
            >
              <.icon name="link" class="size-4" />
              {gettext("Re-sync with source")}
            </button>
            <p class="text-xs text-base-content/50 mt-1">
              {gettext(
                "Resets the property definition to match the source. Your value will be preserved."
              )}
            </p>
          </div>

          <%!-- Use as constant toggle (first after Type) --%>
          <div :if={@can_be_variable} class="form-control">
            <label class="label cursor-pointer justify-start gap-3">
              <input
                type="checkbox"
                name="is_constant"
                value="true"
                checked={@is_constant}
                class="toggle toggle-sm"
                phx-click="toggle_constant"
                phx-target={@target}
              />
              <span class="label-text">{gettext("Use as constant")}</span>
            </label>
            <p class="text-xs text-base-content/50 ml-12">
              {gettext("Constants are not accessible as variables in flow scripts.")}
            </p>
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
              required
            />
          </div>

          <%!-- Variable name (below label, derived from it) --%>
          <div :if={@can_be_variable and not @is_constant}>
            <label class="label">
              <span class="label-text text-xs">{gettext("Variable Name")}</span>
            </label>
            <div class="flex items-center gap-2">
              <code class="flex-1 px-3 py-2 bg-base-300 rounded text-sm font-mono">
                {if @variable_name, do: @variable_name, else: gettext("(derived from label)")}
              </code>
            </div>
            <p class="text-xs text-base-content/50 mt-1">
              {gettext("Use this name to reference the value in flows.")}
            </p>
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

          <%!-- Mode selector (for boolean) --%>
          <div :if={@block.type == "boolean"}>
            <label class="label">
              <span class="label-text">{gettext("Mode")}</span>
            </label>
            <select name="config[mode]" class="select select-bordered w-full">
              <option value="two_state" selected={@mode == "two_state"}>
                {gettext("Two states (Yes/No)")}
              </option>
              <option value="tri_state" selected={@mode == "tri_state"}>
                {gettext("Three states (Yes/Neutral/No)")}
              </option>
            </select>
            <p class="text-xs text-base-content/50 mt-1">
              {gettext("Tri-state allows a neutral/unknown value.")}
            </p>
          </div>

          <%!-- Allowed reference types (for reference) --%>
          <div :if={@block.type == "reference"} class="space-y-2">
            <label class="label">
              <span class="label-text">{gettext("Allowed Types")}</span>
            </label>
            <%!-- Hidden field to ensure key is always present --%>
            <input type="hidden" name="config[allowed_types][]" value="" />
            <div class="flex flex-col gap-2">
              <label class="label cursor-pointer justify-start gap-3">
                <input
                  type="checkbox"
                  name="config[allowed_types][]"
                  value="sheet"
                  checked={"sheet" in @allowed_types}
                  class="checkbox checkbox-sm"
                />
                <span class="label-text">{gettext("Sheets")}</span>
              </label>
              <label class="label cursor-pointer justify-start gap-3">
                <input
                  type="checkbox"
                  name="config[allowed_types][]"
                  value="flow"
                  checked={"flow" in @allowed_types}
                  class="checkbox checkbox-sm"
                />
                <span class="label-text">{gettext("Flows")}</span>
              </label>
            </div>
            <p class="text-xs text-base-content/50">
              {gettext("Select which types can be referenced.")}
            </p>
          </div>

          <%!-- Custom labels (for boolean) --%>
          <div :if={@block.type == "boolean"} class="space-y-2">
            <label class="label">
              <span class="label-text">{gettext("Custom Labels")}</span>
            </label>
            <div class="grid grid-cols-2 gap-2">
              <div>
                <input
                  type="text"
                  name="config[true_label]"
                  value={@true_label}
                  class="input input-bordered input-sm w-full"
                  placeholder={gettext("Yes")}
                />
                <span class="text-xs text-base-content/50">{gettext("True")}</span>
              </div>
              <div>
                <input
                  type="text"
                  name="config[false_label]"
                  value={@false_label}
                  class="input input-bordered input-sm w-full"
                  placeholder={gettext("No")}
                />
                <span class="text-xs text-base-content/50">{gettext("False")}</span>
              </div>
            </div>
            <div :if={@mode == "tri_state"}>
              <input
                type="text"
                name="config[neutral_label]"
                value={@neutral_label}
                class="input input-bordered input-sm w-full"
                placeholder={gettext("Neutral")}
              />
              <span class="text-xs text-base-content/50">{gettext("Neutral/Unknown")}</span>
            </div>
            <p class="text-xs text-base-content/50">
              {gettext("Leave empty to use defaults.")}
            </p>
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
                phx-target={@target}
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
                phx-target={@target}
              >
                <.icon name="x" class="size-4" />
              </button>
            </div>
            <button
              type="button"
              class="btn btn-ghost btn-sm"
              phx-click="add_select_option"
              phx-target={@target}
            >
              <.icon name="plus" class="size-4" />
              {gettext("Add option")}
            </button>
          </div>
        </div>
      </div>
    </div>
    <%!-- Backdrop --%>
    <div class="fixed inset-0 bg-black/20 z-40" phx-click="close_config_panel" phx-target={@target}>
    </div>
    """
  end

  defp assign_config_fields(assigns) do
    config = assigns.block.config || %{}

    assigns
    |> assign_core_config(config)
    |> assign_type_specific_config(config)
  end

  defp assign_core_config(assigns, config) do
    assigns
    |> assign(:label, config["label"] || "")
    |> assign(:placeholder, config["placeholder"] || "")
    |> assign(:options, config["options"] || [])
    |> assign(:max_length, config["max_length"])
    |> assign(:min, config["min"])
    |> assign(:max, config["max"])
    |> assign(:max_options, config["max_options"])
  end

  defp assign_type_specific_config(assigns, config) do
    assigns
    |> assign(:min_date, config["min_date"])
    |> assign(:max_date, config["max_date"])
    |> assign(:mode, config["mode"] || "two_state")
    |> assign(:true_label, config["true_label"] || "")
    |> assign(:false_label, config["false_label"] || "")
    |> assign(:neutral_label, config["neutral_label"] || "")
    |> assign(:allowed_types, config["allowed_types"] || ["sheet", "flow"])
  end

  defp assign_block_fields(assigns) do
    block = assigns.block

    assigns
    |> assign(:is_constant, block.is_constant || false)
    |> assign(:variable_name, block.variable_name)
    |> assign(:can_be_variable, Storyarn.Sheets.Block.can_be_variable?(block.type))
    |> assign(:scope, block.scope || "self")
    |> assign(:is_inherited, Storyarn.Sheets.Block.inherited?(block))
    |> assign(:is_detached, block.detached || false)
    |> assign(:required, block.required || false)
  end
end
