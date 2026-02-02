defmodule StoryarnWeb.Components.BlockComponents.SelectBlocks do
  @moduledoc false

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.Components.CoreComponents, only: [icon: 1]

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
        <option :for={opt <- @options} value={opt["key"]} selected={@content == opt["key"]}>
          {opt["value"]}
        </option>
      </select>
      <div
        :if={!@can_edit}
        class={["py-2 min-h-10", @display_value == nil && "text-base-content/40"]}
      >
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

  defp find_option_label(options, key) do
    Enum.find_value(options, fn opt -> opt["key"] == key && opt["value"] end)
  end
end
