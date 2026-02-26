defmodule StoryarnWeb.Components.BlockComponents.SelectBlocks do
  @moduledoc false

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.Components.CoreComponents, only: [block_label: 1, icon: 1]

  attr :block, :map, required: true
  attr :can_edit, :boolean, default: false
  attr :is_editing, :boolean, default: false
  attr :target, :any, default: nil

  def select_block(assigns) do
    label = get_in(assigns.block.config, ["label"]) || ""
    placeholder = get_in(assigns.block.config, ["placeholder"]) || dgettext("sheets", "Select...")
    options = get_in(assigns.block.config, ["options"]) || []
    content = get_in(assigns.block.value, ["content"])
    display_value = find_option_label(options, content)
    is_constant = assigns.block.is_constant || false

    assigns =
      assigns
      |> assign(:label, label)
      |> assign(:placeholder, placeholder)
      |> assign(:options, options)
      |> assign(:content, content)
      |> assign(:display_value, display_value)
      |> assign(:is_constant, is_constant)

    ~H"""
    <div class="py-1">
      <.block_label
        label={@label}
        is_constant={@is_constant}
        block_id={@block.id}
        can_edit={@can_edit}
        target={@target}
      />
      <select
        :if={@can_edit}
        class="select select-bordered w-full"
        phx-change="update_block_value"
        phx-value-id={@block.id}
        phx-target={@target}
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
  attr :target, :any, default: nil

  def multi_select_block(assigns) do
    assigns = prepare_multi_select_assigns(assigns)

    ~H"""
    <div class="py-1">
      <.block_label
        label={@label}
        is_constant={@is_constant}
        block_id={@block.id}
        can_edit={@can_edit}
        target={@target}
      />
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
            phx-target={@target}
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
          phx-target={@target}
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

  defp prepare_multi_select_assigns(assigns) do
    label = get_in(assigns.block.config, ["label"]) || ""
    placeholder = get_in(assigns.block.config, ["placeholder"]) || ""
    options = get_in(assigns.block.config, ["options"]) || []
    content = get_in(assigns.block.value, ["content"]) || []
    is_constant = assigns.block.is_constant || false

    selected_options = resolve_selected_options(content, options)
    display_placeholder = resolve_placeholder(placeholder, selected_options)

    assigns
    |> assign(:label, label)
    |> assign(:placeholder, display_placeholder)
    |> assign(:options, options)
    |> assign(:content, content)
    |> assign(:selected_options, selected_options)
    |> assign(:is_constant, is_constant)
  end

  defp resolve_selected_options(content, options) do
    Enum.map(content, fn key ->
      option = Enum.find(options, fn opt -> opt["key"] == key end)
      %{key: key, label: (option && option["value"]) || key}
    end)
  end

  defp resolve_placeholder("", []), do: dgettext("sheets", "Type and press Enter to add...")
  defp resolve_placeholder("", _selected), do: dgettext("sheets", "Add more...")
  defp resolve_placeholder(placeholder, _selected), do: placeholder

  defp find_option_label(options, key) do
    Enum.find_value(options, fn opt -> opt["key"] == key && opt["value"] end)
  end
end
