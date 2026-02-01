defmodule StoryarnWeb.Components.BlockComponents do
  @moduledoc """
  Components for rendering page blocks (text, rich_text, number, select, etc.).
  """
  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.CoreComponents, only: [icon: 1]

  # =============================================================================
  # Block Component (Main Dispatcher)
  # =============================================================================

  @doc """
  Renders a block with its controls (drag handle, menu) and content.

  ## Examples

      <.block_component block={@block} can_edit={true} editing_block_id={@editing_block_id} />
  """
  attr :block, :map, required: true
  attr :can_edit, :boolean, default: false
  attr :editing_block_id, :any, default: nil

  def block_component(assigns) do
    is_editing = assigns.editing_block_id == assigns.block.id
    assigns = assign(assigns, :is_editing, is_editing)

    ~H"""
    <div class="flex items-start gap-2 lg:relative lg:block w-full">
      <%!-- Drag handle and delete - inline on mobile, absolute on lg --%>
      <div
        :if={@can_edit}
        class="flex items-center pt-2 lg:absolute lg:-left-14 lg:top-2 lg:opacity-0 lg:group-hover:opacity-100"
      >
        <button
          type="button"
          class="drag-handle p-1 cursor-grab active:cursor-grabbing text-base-content/50 hover:text-base-content"
          title={gettext("Drag to reorder")}
        >
          <.icon name="grip-vertical" class="size-4" />
        </button>
        <div class="dropdown dropdown-end">
          <button
            type="button"
            tabindex="0"
            class="p-1 text-base-content/50 hover:text-base-content"
          >
            <.icon name="ellipsis-vertical" class="size-4" />
          </button>
          <ul
            tabindex="0"
            class="dropdown-content menu bg-base-200 rounded-box z-50 w-40 p-2 shadow-lg"
          >
            <li>
              <button type="button" phx-click="configure_block" phx-value-id={@block.id}>
                <.icon name="settings" class="size-4" />
                {gettext("Configure")}
              </button>
            </li>
            <li>
              <button
                type="button"
                class="text-error"
                phx-click="delete_block"
                phx-value-id={@block.id}
              >
                <.icon name="trash-2" class="size-4" />
                {gettext("Delete")}
              </button>
            </li>
          </ul>
        </div>
      </div>

      <%!-- Block content --%>
      <div class="flex-1 lg:flex-none">
        <%= case @block.type do %>
          <% "text" -> %>
            <.text_block block={@block} can_edit={@can_edit} is_editing={@is_editing} />
          <% "rich_text" -> %>
            <.rich_text_block block={@block} can_edit={@can_edit} is_editing={@is_editing} />
          <% "number" -> %>
            <.number_block block={@block} can_edit={@can_edit} is_editing={@is_editing} />
          <% "select" -> %>
            <.select_block block={@block} can_edit={@can_edit} is_editing={@is_editing} />
          <% "multi_select" -> %>
            <.multi_select_block block={@block} can_edit={@can_edit} is_editing={@is_editing} />
          <% "divider" -> %>
            <.divider_block />
          <% "date" -> %>
            <.date_block block={@block} can_edit={@can_edit} />
          <% _ -> %>
            <div class="text-base-content/50">{gettext("Unknown block type")}</div>
        <% end %>
      </div>
    </div>
    """
  end

  # =============================================================================
  # Block Type Components
  # =============================================================================

  attr :block, :map, required: true
  attr :can_edit, :boolean, default: false
  attr :is_editing, :boolean, default: false

  def text_block(assigns) do
    label = get_in(assigns.block.config, ["label"]) || ""
    placeholder = get_in(assigns.block.config, ["placeholder"]) || ""
    content = get_in(assigns.block.value, ["content"]) || ""

    assigns =
      assigns
      |> assign(:label, label)
      |> assign(:placeholder, placeholder)
      |> assign(:content, content)

    ~H"""
    <div class="py-1">
      <label :if={@label != ""} class="text-sm text-base-content/70 mb-1 block">{@label}</label>
      <input
        :if={@can_edit}
        type="text"
        value={@content}
        placeholder={@placeholder}
        class="input input-bordered w-full"
        phx-blur="update_block_value"
        phx-value-id={@block.id}
      />
      <div :if={!@can_edit} class={["py-2 min-h-10", @content == "" && "text-base-content/40"]}>
        {if @content == "", do: "-", else: @content}
      </div>
    </div>
    """
  end

  attr :block, :map, required: true
  attr :can_edit, :boolean, default: false
  attr :is_editing, :boolean, default: false

  def rich_text_block(assigns) do
    label = get_in(assigns.block.config, ["label"]) || ""
    content = get_in(assigns.block.value, ["content"]) || ""

    assigns =
      assigns
      |> assign(:label, label)
      |> assign(:content, content)

    ~H"""
    <div class="py-1">
      <label :if={@label != ""} class="text-sm text-base-content/70 mb-1 block">{@label}</label>
      <div
        id={"tiptap-#{@block.id}"}
        phx-hook="TiptapEditor"
        phx-update="ignore"
        data-content={@content}
        data-editable={to_string(@can_edit)}
        data-block-id={@block.id}
      >
      </div>
    </div>
    """
  end

  attr :block, :map, required: true
  attr :can_edit, :boolean, default: false
  attr :is_editing, :boolean, default: false

  def number_block(assigns) do
    label = get_in(assigns.block.config, ["label"]) || ""
    placeholder = get_in(assigns.block.config, ["placeholder"]) || "0"
    content = get_in(assigns.block.value, ["content"])

    assigns =
      assigns
      |> assign(:label, label)
      |> assign(:placeholder, placeholder)
      |> assign(:content, content)

    ~H"""
    <div class="py-1">
      <label :if={@label != ""} class="text-sm text-base-content/70 mb-1 block">{@label}</label>
      <input
        :if={@can_edit}
        type="number"
        value={@content}
        placeholder={@placeholder}
        class="input input-bordered w-full"
        phx-blur="update_block_value"
        phx-value-id={@block.id}
      />
      <div :if={!@can_edit} class={["py-2 min-h-10", @content == nil && "text-base-content/40"]}>
        {@content || "-"}
      </div>
    </div>
    """
  end

  attr :block, :map, required: true
  attr :can_edit, :boolean, default: false
  attr :is_editing, :boolean, default: false

  def select_block(assigns) do
    label = get_in(assigns.block.config, ["label"]) || ""
    placeholder = get_in(assigns.block.config, ["placeholder"]) || gettext("Select...")
    options = get_in(assigns.block.config, ["options"]) || []
    content = get_in(assigns.block.value, ["content"])
    display_value = find_option_label(options, content)

    assigns =
      assigns
      |> assign(:label, label)
      |> assign(:placeholder, placeholder)
      |> assign(:options, options)
      |> assign(:content, content)
      |> assign(:display_value, display_value)

    ~H"""
    <div class="py-1">
      <label :if={@label != ""} class="text-sm text-base-content/70 mb-1 block">{@label}</label>
      <select
        :if={@can_edit}
        class="select select-bordered w-full"
        phx-change="update_block_value"
        phx-value-id={@block.id}
      >
        <option value="">{@placeholder}</option>
        <option
          :for={opt <- @options}
          value={opt["key"]}
          selected={@content == opt["key"]}
        >
          {opt["value"]}
        </option>
      </select>
      <div :if={!@can_edit} class={["py-2 min-h-10", @display_value == nil && "text-base-content/40"]}>
        {@display_value || "-"}
      </div>
    </div>
    """
  end

  attr :block, :map, required: true
  attr :can_edit, :boolean, default: false
  attr :is_editing, :boolean, default: false

  def multi_select_block(assigns) do
    label = get_in(assigns.block.config, ["label"]) || ""
    placeholder = get_in(assigns.block.config, ["placeholder"]) || ""
    options = get_in(assigns.block.config, ["options"]) || []
    content = get_in(assigns.block.value, ["content"]) || []

    # Get selected options with their labels
    selected_options =
      Enum.map(content, fn key ->
        option = Enum.find(options, fn opt -> opt["key"] == key end)
        %{key: key, label: (option && option["value"]) || key}
      end)

    # Use configured placeholder or default
    default_placeholder =
      if selected_options == [],
        do: gettext("Type and press Enter to add..."),
        else: gettext("Add more...")

    display_placeholder = if placeholder != "", do: placeholder, else: default_placeholder

    assigns =
      assigns
      |> assign(:label, label)
      |> assign(:placeholder, display_placeholder)
      |> assign(:options, options)
      |> assign(:content, content)
      |> assign(:selected_options, selected_options)

    ~H"""
    <div class="py-1">
      <label :if={@label != ""} class="text-sm text-base-content/70 mb-1 block">{@label}</label>
      <div
        :if={@can_edit}
        class="block-input w-full min-h-12 py-2 flex flex-wrap items-center gap-1.5 px-4"
      >
        <%!-- Selected tags --%>
        <span :for={opt <- @selected_options} class="badge badge-primary gap-1">
          {opt.label}
          <button
            type="button"
            class="hover:opacity-70"
            phx-click="toggle_multi_select"
            phx-value-id={@block.id}
            phx-value-key={opt.key}
          >
            <.icon name="x" class="size-3" />
          </button>
        </span>
        <%!-- Input for adding new tags --%>
        <input
          type="text"
          class="flex-1 min-w-24 bg-transparent border-none outline-none text-sm"
          placeholder={@placeholder}
          phx-keydown="multi_select_keydown"
          phx-value-id={@block.id}
        />
      </div>
      <div :if={!@can_edit} class="py-2 min-h-10">
        <div :if={@content != []} class="flex flex-wrap gap-1">
          <span :for={opt <- @selected_options} class="badge badge-sm badge-primary">
            {opt.label}
          </span>
        </div>
        <span :if={@content == []} class="text-base-content/40">-</span>
      </div>
    </div>
    """
  end

  def divider_block(assigns) do
    ~H"""
    <div class="py-3">
      <hr class="border-base-content/20" />
    </div>
    """
  end

  attr :block, :map, required: true
  attr :can_edit, :boolean, default: false

  def date_block(assigns) do
    label = get_in(assigns.block.config, ["label"]) || ""
    content = get_in(assigns.block.value, ["content"])
    formatted = format_date(content)

    assigns =
      assigns
      |> assign(:label, label)
      |> assign(:content, content)
      |> assign(:formatted, formatted)

    ~H"""
    <div class="py-1">
      <label :if={@label != ""} class="text-sm text-base-content/70 mb-1 block">{@label}</label>
      <input
        :if={@can_edit}
        type="date"
        value={@content}
        class="input input-bordered w-full"
        phx-blur="update_block_value"
        phx-value-id={@block.id}
      />
      <div :if={!@can_edit} class={["py-2 min-h-10", @content in [nil, ""] && "text-base-content/40"]}>
        {@formatted}
      </div>
    </div>
    """
  end

  # =============================================================================
  # Block Menu
  # =============================================================================

  @doc """
  Renders the block type selection menu.

  ## Examples

      <.block_menu />
  """
  def block_menu(assigns) do
    ~H"""
    <div class="absolute z-10 bg-base-100 border border-base-300 rounded-lg shadow-lg p-2 w-64">
      <div class="text-xs text-base-content/50 px-2 py-1 uppercase">{gettext("Basic Blocks")}</div>
      <button
        type="button"
        class="w-full text-left px-2 py-2 hover:bg-base-200 rounded flex items-center gap-2"
        phx-click="add_block"
        phx-value-type="text"
      >
        <span class="text-lg">T</span>
        <span>{gettext("Text")}</span>
      </button>
      <button
        type="button"
        class="w-full text-left px-2 py-2 hover:bg-base-200 rounded flex items-center gap-2"
        phx-click="add_block"
        phx-value-type="rich_text"
      >
        <span class="text-lg">T</span>
        <span>{gettext("Rich Text")}</span>
      </button>
      <button
        type="button"
        class="w-full text-left px-2 py-2 hover:bg-base-200 rounded flex items-center gap-2"
        phx-click="add_block"
        phx-value-type="number"
      >
        <span class="text-lg">#</span>
        <span>{gettext("Number")}</span>
      </button>
      <button
        type="button"
        class="w-full text-left px-2 py-2 hover:bg-base-200 rounded flex items-center gap-2"
        phx-click="add_block"
        phx-value-type="select"
      >
        <.icon name="chevron-down" class="size-4" />
        <span>{gettext("Select")}</span>
      </button>
      <button
        type="button"
        class="w-full text-left px-2 py-2 hover:bg-base-200 rounded flex items-center gap-2"
        phx-click="add_block"
        phx-value-type="multi_select"
      >
        <.icon name="check" class="size-4" />
        <span>{gettext("Multi Select")}</span>
      </button>
      <button
        type="button"
        class="w-full text-left px-2 py-2 hover:bg-base-200 rounded flex items-center gap-2"
        phx-click="add_block"
        phx-value-type="date"
      >
        <.icon name="calendar" class="size-4" />
        <span>{gettext("Date")}</span>
      </button>

      <div class="text-xs text-base-content/50 px-2 py-1 uppercase mt-2">{gettext("Layout")}</div>
      <button
        type="button"
        class="w-full text-left px-2 py-2 hover:bg-base-200 rounded flex items-center gap-2"
        phx-click="add_block"
        phx-value-type="divider"
      >
        <.icon name="minus" class="size-4" />
        <span>{gettext("Divider")}</span>
      </button>

      <div class="border-t border-base-300 mt-2 pt-2">
        <button
          type="button"
          class="w-full text-left px-2 py-1 text-sm text-base-content/50 hover:text-base-content"
          phx-click="hide_block_menu"
        >
          {gettext("Cancel")}
        </button>
      </div>
    </div>
    """
  end

  # =============================================================================
  # Helpers
  # =============================================================================

  defp format_date(nil), do: "-"
  defp format_date(""), do: "-"

  defp format_date(date_string) do
    case Date.from_iso8601(date_string) do
      {:ok, date} -> Calendar.strftime(date, "%B %d, %Y")
      _ -> date_string
    end
  end

  defp find_option_label(options, key) do
    Enum.find_value(options, fn opt -> opt["key"] == key && opt["value"] end)
  end

  # =============================================================================
  # Config Panel
  # =============================================================================

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
        <button
          type="button"
          class="btn btn-ghost btn-sm btn-square"
          phx-click="close_config_panel"
        >
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
            <div
              :for={{opt, idx} <- Enum.with_index(@options)}
              class="flex items-center gap-2"
            >
              <form phx-change="update_select_option" phx-value-index={idx} class="flex items-center gap-2 flex-1">
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
            <button
              type="button"
              class="btn btn-ghost btn-sm"
              phx-click="add_select_option"
            >
              <.icon name="plus" class="size-4" />
              {gettext("Add option")}
            </button>
          </div>
        </div>
      </div>
    </div>
    <%!-- Backdrop --%>
    <div
      class="fixed inset-0 bg-black/20 z-40"
      phx-click="close_config_panel"
    >
    </div>
    """
  end
end
