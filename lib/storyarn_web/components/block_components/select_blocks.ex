defmodule StoryarnWeb.Components.BlockComponents.SelectBlocks do
  @moduledoc false

  use Phoenix.Component
  use Gettext, backend: Storyarn.Gettext

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
    <div>
      <.block_label
        label={@label}
        is_constant={@is_constant}
        block_type={@block.type}
        block_id={@block.id}
        can_edit={@can_edit}
        target={@target}
      />
      <div
        :if={@can_edit}
        id={"block-select-#{@block.id}"}
        phx-hook="BlockSelect"
        data-mode="select"
        data-phx-target={@target}
        class="w-full"
      >
        <button
          type="button"
          data-role="trigger"
          class="select select-bordered w-full flex items-center justify-between cursor-pointer"
        >
          <span class={["truncate", !@display_value && "text-base-content/50"]}>
            {@display_value || @placeholder}
          </span>
        </button>

        <template data-role="popover-template">
          <div class="p-2">
            <input
              :if={length(@options) > 5}
              type="text"
              data-role="search"
              class="input input-bordered input-sm w-full mb-2"
              placeholder={dgettext("sheets", "Search...")}
            />
            <div data-role="list" class="max-h-48 overflow-y-auto">
              <button
                type="button"
                data-event="update_block_value"
                data-params={Jason.encode!(%{id: @block.id, value: ""})}
                data-search-text=""
                class={[
                  "w-full text-left px-2 py-1.5 rounded text-sm hover:bg-base-300 transition-colors",
                  !@content && "bg-base-300"
                ]}
              >
                <span class="text-base-content/50">{@placeholder}</span>
              </button>
              <button
                :for={opt <- @options}
                type="button"
                data-event="update_block_value"
                data-params={Jason.encode!(%{id: @block.id, value: opt["key"]})}
                data-search-text={String.downcase(opt["value"] || "")}
                class={[
                  "w-full text-left px-2 py-1.5 rounded text-sm hover:bg-base-300 transition-colors",
                  @content == opt["key"] && "bg-primary/10 text-primary font-medium"
                ]}
              >
                {opt["value"]}
              </button>
            </div>
            <div
              data-role="empty"
              class="text-center text-base-content/50 py-3 text-sm"
              style="display:none"
            >
              {dgettext("sheets", "No matches")}
            </div>
          </div>
        </template>
      </div>
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
    <div>
      <.block_label
        label={@label}
        is_constant={@is_constant}
        block_type={@block.type}
        block_id={@block.id}
        can_edit={@can_edit}
        target={@target}
      />
      <div
        :if={@can_edit}
        id={"block-select-#{@block.id}"}
        phx-hook="BlockSelect"
        data-mode="multi_select"
        data-phx-target={@target}
        class="w-full"
      >
        <button
          type="button"
          data-role="trigger"
          class="block-input w-full min-h-12 py-2 flex flex-wrap items-center gap-1.5 px-4 cursor-pointer"
        >
          <span :for={opt <- @selected_options} class="badge badge-primary gap-1">
            {opt.label}
          </span>
          <span :if={@selected_options == []} class="text-base-content/50 text-sm">
            {@placeholder}
          </span>
          <.icon name="chevron-down" class="size-4 shrink-0 text-base-content/50 ml-auto" />
        </button>

        <template data-role="popover-template">
          <div class="p-2">
            <input
              :if={length(@options) > 5}
              type="text"
              data-role="search"
              class="input input-bordered input-sm w-full mb-2"
              placeholder={dgettext("sheets", "Search...")}
            />
            <div data-role="list" class="max-h-48 overflow-y-auto">
              <button
                :for={opt <- @options}
                type="button"
                data-event="toggle_multi_select"
                data-params={Jason.encode!(%{id: @block.id, key: opt["key"]})}
                data-search-text={String.downcase(opt["value"] || "")}
                class={[
                  "w-full text-left px-2 py-1.5 rounded text-sm hover:bg-base-300 transition-colors flex items-center gap-2",
                  opt["key"] in @content && "bg-primary/10"
                ]}
              >
                <span class={[
                  "size-4 rounded border flex items-center justify-center shrink-0",
                  if(opt["key"] in @content,
                    do: "bg-primary border-primary text-primary-content",
                    else: "border-base-content/30"
                  )
                ]}>
                  <.icon :if={opt["key"] in @content} name="check" class="size-3" />
                </span>
                {opt["value"]}
              </button>
            </div>
            <div
              data-role="empty"
              class="text-center text-base-content/50 py-3 text-sm"
              style="display:none"
            >
              {dgettext("sheets", "No matches")}
            </div>
            <div class="border-t border-base-300 mt-2 pt-2">
              <input
                type="text"
                data-role="add-input"
                data-block-id={@block.id}
                class="input input-bordered input-sm w-full"
                placeholder={dgettext("sheets", "Type and press Enter to add...")}
              />
            </div>
          </div>
        </template>
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

    content =
      case get_in(assigns.block.value, ["content"]) do
        list when is_list(list) -> list
        _ -> []
      end

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
