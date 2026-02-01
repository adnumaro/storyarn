defmodule StoryarnWeb.PageLive.Show do
  @moduledoc false

  use StoryarnWeb, :live_view
  use StoryarnWeb.LiveHelpers.Authorize

  alias Storyarn.Pages
  alias Storyarn.Projects
  alias Storyarn.Repo

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.project
      flash={@flash}
      current_scope={@current_scope}
      project={@project}
      workspace={@workspace}
      pages_tree={@pages_tree}
      current_path={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/pages/#{@page.id}"}
      selected_page_id={to_string(@page.id)}
      can_edit={@can_edit}
    >
      <%!-- Breadcrumb --%>
      <nav class="text-sm mb-4">
        <ol class="flex flex-wrap items-center gap-1 text-base-content/70">
          <li :for={{ancestor, idx} <- Enum.with_index(@ancestors)} class="flex items-center">
            <.link
              navigate={
                ~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/pages/#{ancestor.id}"
              }
              class="hover:text-primary flex items-center gap-1"
            >
              <.page_icon icon={ancestor.icon} size="sm" />
              {ancestor.name}
            </.link>
            <span :if={idx < length(@ancestors) - 1} class="mx-1 text-base-content/50">/</span>
          </li>
        </ol>
      </nav>

      <%!-- Page Header --%>
      <div class="relative">
        <div class="max-w-3xl mx-auto">
          <div class="flex items-start gap-4 mb-8">
            <.page_icon icon={@page.icon} size="xl" />
            <div class="flex-1">
              <h1
                :if={!@editing_name}
                class="text-3xl font-bold cursor-pointer hover:bg-base-200 rounded px-2 -mx-2 py-1"
                phx-click="edit_name"
              >
                {@page.name}
              </h1>
              <form :if={@editing_name} phx-submit="save_name" phx-click-away="cancel_edit_name">
                <input
                  type="text"
                  name="name"
                  value={@page.name}
                  class="input input-bordered text-3xl font-bold w-full"
                  autofocus
                  phx-key="escape"
                  phx-keydown="cancel_edit_name"
                />
              </form>
            </div>
          </div>
        </div>
        <%!-- Save indicator (positioned at header level) --%>
        <.save_indicator status={@save_status} />
      </div>

      <div class="max-w-3xl mx-auto">
        <%!-- Blocks --%>
        <div
          id="blocks-container"
          class="flex flex-col gap-2 -mx-2 sm:-mx-8 md:-mx-16"
          phx-hook={if @can_edit, do: "SortableList", else: nil}
          data-group="blocks"
          data-handle=".drag-handle"
        >
          <div
            :for={block <- @blocks}
            class="group relative w-full px-2 sm:px-8 md:px-16"
            id={"block-#{block.id}"}
            data-id={block.id}
          >
            <.block_component
              block={block}
              can_edit={@can_edit}
              editing_block_id={@editing_block_id}
            />
          </div>
        </div>

        <%!-- Add block button / slash command (outside sortable container) --%>
        <div :if={@can_edit} class="relative mt-2">
          <div
            :if={!@show_block_menu}
            class="flex items-center gap-2 py-2 text-base-content/50 hover:text-base-content cursor-pointer group"
            phx-click="show_block_menu"
          >
            <.icon name="plus" class="size-4 opacity-0 group-hover:opacity-100" />
            <span class="text-sm">{gettext("Type / to add a block")}</span>
          </div>

          <.block_menu :if={@show_block_menu} />
        </div>

        <%!-- Children pages --%>
        <div :if={@children != []} class="mt-12 pt-8 border-t border-base-300">
          <h2 class="text-lg font-semibold mb-4">{gettext("Subpages")}</h2>
          <div class="space-y-2">
            <.link
              :for={child <- @children}
              navigate={
                ~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/pages/#{child.id}"
              }
              class="flex items-center gap-2 p-2 rounded hover:bg-base-200"
            >
              <.page_icon icon={child.icon} size="md" />
              <span>{child.name}</span>
            </.link>
          </div>
        </div>
      </div>

      <%!-- Configuration Panel (Right Sidebar) --%>
      <.config_panel :if={@configuring_block} block={@configuring_block} />
    </Layouts.project>
    """
  end

  attr :block, :map, required: true

  defp config_panel(assigns) do
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

  attr :block, :map, required: true
  attr :can_edit, :boolean, default: false
  attr :editing_block_id, :any, default: nil

  defp block_component(assigns) do
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

  defp text_block(assigns) do
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

  defp rich_text_block(assigns) do
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

  defp number_block(assigns) do
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

  defp select_block(assigns) do
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

  defp multi_select_block(assigns) do
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

  defp divider_block(assigns) do
    ~H"""
    <div class="py-3">
      <hr class="border-base-content/20" />
    </div>
    """
  end

  attr :block, :map, required: true
  attr :can_edit, :boolean, default: false

  defp date_block(assigns) do
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

  defp block_menu(assigns) do
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

  @page_icon_sizes %{
    "sm" => {"size-4", "text-sm"},
    "md" => {"size-5", "text-base"},
    "lg" => {"size-6", "text-lg"},
    "xl" => {"size-10", "text-5xl"}
  }

  attr :icon, :string, default: nil
  attr :size, :string, values: ["sm", "md", "lg", "xl"], default: "md"

  defp page_icon(assigns) do
    {size_class, text_size} = Map.get(@page_icon_sizes, assigns.size, {"size-5", "text-base"})
    is_emoji = assigns.icon && assigns.icon not in [nil, "", "page"]

    assigns =
      assigns
      |> assign(:size_class, size_class)
      |> assign(:text_size, text_size)
      |> assign(:is_emoji, is_emoji)

    ~H"""
    <span :if={@is_emoji} class={@text_size}>{@icon}</span>
    <.icon :if={!@is_emoji} name="file" class={"#{@size_class} opacity-60"} />
    """
  end

  attr :status, :atom, required: true

  defp save_indicator(assigns) do
    ~H"""
    <div
      :if={@status != :idle}
      class="absolute top-2 right-0 z-10 animate-in fade-in duration-300"
    >
      <div class={[
        "flex items-center gap-2 px-3 py-1.5 rounded-lg text-sm font-medium",
        @status == :saving && "bg-base-200 text-base-content",
        @status == :saved && "bg-success/10 text-success"
      ]}>
        <span :if={@status == :saving} class="loading loading-spinner loading-xs"></span>
        <.icon :if={@status == :saved} name="check" class="size-4" />
        <span :if={@status == :saving}>{gettext("Saving...")}</span>
        <span :if={@status == :saved}>{gettext("Saved")}</span>
      </div>
    </div>
    """
  end

  @impl true
  def mount(
        %{"workspace_slug" => workspace_slug, "project_slug" => project_slug, "id" => page_id},
        _session,
        socket
      ) do
    case Projects.get_project_by_slugs(
           socket.assigns.current_scope,
           workspace_slug,
           project_slug
         ) do
      {:ok, project, membership} ->
        case Pages.get_page(project.id, page_id) do
          nil ->
            {:ok,
             socket
             |> put_flash(:error, gettext("Page not found."))
             |> redirect(to: ~p"/workspaces/#{workspace_slug}/projects/#{project_slug}/pages")}

          page ->
            project = Repo.preload(project, :workspace)
            pages_tree = Pages.list_pages_tree(project.id)
            ancestors = Pages.get_page_with_ancestors(project.id, page_id) || [page]
            children = Pages.get_children(page.id)
            blocks = Pages.list_blocks(page.id)
            can_edit = Projects.ProjectMembership.can?(membership.role, :edit_content)

            socket =
              socket
              |> assign(:project, project)
              |> assign(:workspace, project.workspace)
              |> assign(:membership, membership)
              |> assign(:page, page)
              |> assign(:pages_tree, pages_tree)
              |> assign(:ancestors, ancestors)
              |> assign(:children, children)
              |> assign(:blocks, blocks)
              |> assign(:can_edit, can_edit)
              |> assign(:editing_name, false)
              |> assign(:editing_block_id, nil)
              |> assign(:show_block_menu, false)
              |> assign(:save_status, :idle)
              |> assign(:configuring_block, nil)

            {:ok, socket}
        end

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, gettext("You don't have access to this project."))
         |> redirect(to: ~p"/workspaces")}
    end
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("edit_name", _params, socket) do
    if socket.assigns.can_edit do
      {:noreply, assign(socket, :editing_name, true)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("cancel_edit_name", _params, socket) do
    {:noreply, assign(socket, :editing_name, false)}
  end

  def handle_event("save_name", %{"name" => name}, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        case Pages.update_page(socket.assigns.page, %{name: name}) do
          {:ok, page} ->
            pages_tree = Pages.list_pages_tree(socket.assigns.project.id)

            {:noreply,
             socket
             |> assign(:page, page)
             |> assign(:pages_tree, pages_tree)
             |> assign(:editing_name, false)}

          {:error, _changeset} ->
            {:noreply, assign(socket, :editing_name, false)}
        end

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, gettext("You don't have permission to perform this action."))}
    end
  end

  def handle_event("delete_page", %{"id" => page_id}, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        page = Pages.get_page!(socket.assigns.project.id, page_id)
        do_delete_page(socket, page)

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, gettext("You don't have permission to perform this action."))}
    end
  end

  def handle_event("show_block_menu", _params, socket) do
    {:noreply, assign(socket, :show_block_menu, true)}
  end

  def handle_event("hide_block_menu", _params, socket) do
    {:noreply, assign(socket, :show_block_menu, false)}
  end

  def handle_event("add_block", %{"type" => type}, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        case Pages.create_block(socket.assigns.page, %{type: type}) do
          {:ok, _block} ->
            blocks = Pages.list_blocks(socket.assigns.page.id)

            {:noreply,
             socket
             |> assign(:blocks, blocks)
             |> assign(:show_block_menu, false)}

          {:error, _} ->
            {:noreply,
             socket
             |> put_flash(:error, gettext("Could not add block."))
             |> assign(:show_block_menu, false)}
        end

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, gettext("You don't have permission to perform this action."))}
    end
  end

  def handle_event("update_block_value", %{"id" => block_id, "value" => value}, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        block = Pages.get_block!(block_id)

        case Pages.update_block_value(block, %{"content" => value}) do
          {:ok, _block} ->
            blocks = Pages.list_blocks(socket.assigns.page.id)
            schedule_save_status_reset()

            {:noreply,
             socket
             |> assign(:blocks, blocks)
             |> assign(:save_status, :saved)}

          {:error, _} ->
            {:noreply, socket}
        end

      {:error, :unauthorized} ->
        {:noreply, socket}
    end
  end

  def handle_event("toggle_multi_select", %{"id" => block_id, "key" => key}, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        block = Pages.get_block!(block_id)
        current = get_in(block.value, ["content"]) || []

        new_content =
          if key in current do
            List.delete(current, key)
          else
            [key | current]
          end

        case Pages.update_block_value(block, %{"content" => new_content}) do
          {:ok, _block} ->
            blocks = Pages.list_blocks(socket.assigns.page.id)
            schedule_save_status_reset()

            {:noreply,
             socket
             |> assign(:blocks, blocks)
             |> assign(:save_status, :saved)}

          {:error, _} ->
            {:noreply, socket}
        end

      {:error, :unauthorized} ->
        {:noreply, socket}
    end
  end

  def handle_event("multi_select_keydown", %{"key" => "Enter", "value" => value, "id" => block_id}, socket) do
    value = String.trim(value)

    if value == "" do
      {:noreply, socket}
    else
      case authorize(socket, :edit_content) do
        :ok ->
          add_multi_select_option(socket, block_id, value)

        {:error, :unauthorized} ->
          {:noreply, socket}
      end
    end
  end

  def handle_event("multi_select_keydown", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("delete_block", %{"id" => block_id}, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        block = Pages.get_block!(block_id)

        case Pages.delete_block(block) do
          {:ok, _} ->
            blocks = Pages.list_blocks(socket.assigns.page.id)

            socket =
              socket
              |> assign(:blocks, blocks)
              |> assign(:configuring_block, nil)

            {:noreply, socket}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, gettext("Could not delete block."))}
        end

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, gettext("You don't have permission to perform this action."))}
    end
  end

  def handle_event("configure_block", %{"id" => block_id}, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        block = Pages.get_block!(block_id)
        {:noreply, assign(socket, :configuring_block, block)}

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, gettext("You don't have permission to perform this action."))}
    end
  end

  def handle_event("close_config_panel", _params, socket) do
    {:noreply, assign(socket, :configuring_block, nil)}
  end

  def handle_event("save_block_config", %{"config" => config_params}, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        block = socket.assigns.configuring_block

        # Convert options from indexed map to list
        config_params = normalize_config_params(config_params)

        case Pages.update_block_config(block, config_params) do
          {:ok, updated_block} ->
            blocks = Pages.list_blocks(socket.assigns.page.id)
            schedule_save_status_reset()

            {:noreply,
             socket
             |> assign(:blocks, blocks)
             |> assign(:configuring_block, updated_block)
             |> assign(:save_status, :saved)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, gettext("Could not save configuration."))}
        end

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, gettext("You don't have permission to perform this action."))}
    end
  end

  defp normalize_config_params(params) do
    case Map.get(params, "options") do
      nil ->
        params

      options when is_map(options) ->
        # Convert indexed map to list, sorted by index
        options_list =
          options
          |> Enum.sort_by(fn {idx, _} -> String.to_integer(idx) end)
          |> Enum.map(fn {_, opt} -> opt end)

        Map.put(params, "options", options_list)

      _ ->
        params
    end
  end

  def handle_event("add_select_option", _params, socket) do
    block = socket.assigns.configuring_block
    options = get_in(block.config, ["options"]) || []
    new_option = %{"key" => "option-#{length(options) + 1}", "value" => ""}
    new_options = options ++ [new_option]

    case Pages.update_block_config(block, %{"options" => new_options}) do
      {:ok, updated_block} ->
        blocks = Pages.list_blocks(socket.assigns.page.id)

        {:noreply,
         socket
         |> assign(:blocks, blocks)
         |> assign(:configuring_block, updated_block)}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  def handle_event("remove_select_option", %{"index" => index}, socket) do
    block = socket.assigns.configuring_block
    options = get_in(block.config, ["options"]) || []
    index = String.to_integer(index)
    new_options = List.delete_at(options, index)

    case Pages.update_block_config(block, %{"options" => new_options}) do
      {:ok, updated_block} ->
        blocks = Pages.list_blocks(socket.assigns.page.id)

        {:noreply,
         socket
         |> assign(:blocks, blocks)
         |> assign(:configuring_block, updated_block)}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  def handle_event("update_select_option", %{"index" => index, "key" => key, "value" => value}, socket) do
    block = socket.assigns.configuring_block
    options = get_in(block.config, ["options"]) || []
    index = String.to_integer(index)

    new_options =
      List.update_at(options, index, fn _opt ->
        %{"key" => key, "value" => value}
      end)

    case Pages.update_block_config(block, %{"options" => new_options}) do
      {:ok, updated_block} ->
        blocks = Pages.list_blocks(socket.assigns.page.id)

        {:noreply,
         socket
         |> assign(:blocks, blocks)
         |> assign(:configuring_block, updated_block)}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  def handle_event("update_rich_text", %{"id" => block_id, "content" => content}, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        block = Pages.get_block!(block_id)

        case Pages.update_block_value(block, %{"content" => content}) do
          {:ok, _block} ->
            # Don't reload blocks to avoid disrupting the editor
            schedule_save_status_reset()
            {:noreply, assign(socket, :save_status, :saved)}

          {:error, _} ->
            {:noreply, socket}
        end

      {:error, :unauthorized} ->
        {:noreply, socket}
    end
  end

  def handle_event("reorder", %{"ids" => ids, "group" => "blocks"}, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        case Pages.reorder_blocks(socket.assigns.page.id, ids) do
          {:ok, blocks} ->
            {:noreply, assign(socket, :blocks, blocks)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, gettext("Could not reorder blocks."))}
        end

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, gettext("You don't have permission to perform this action."))}
    end
  end

  def handle_event(
        "move_page",
        %{"page_id" => page_id, "parent_id" => parent_id, "position" => position},
        socket
      ) do
    case authorize(socket, :edit_content) do
      :ok ->
        page = Pages.get_page!(socket.assigns.project.id, page_id)
        parent_id = normalize_parent_id(parent_id)

        case Pages.move_page_to_position(page, parent_id, position) do
          {:ok, _page} ->
            pages_tree = Pages.list_pages_tree(socket.assigns.project.id)
            {:noreply, assign(socket, :pages_tree, pages_tree)}

          {:error, :would_create_cycle} ->
            {:noreply,
             put_flash(socket, :error, gettext("Cannot move a page into its own children."))}

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, gettext("Could not move page."))}
        end

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, gettext("You don't have permission to perform this action."))}
    end
  end

  def handle_event("create_child_page", %{"parent-id" => parent_id}, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        attrs = %{name: gettext("New Page"), parent_id: parent_id}

        case Pages.create_page(socket.assigns.project, attrs) do
          {:ok, new_page} ->
            pages_tree = Pages.list_pages_tree(socket.assigns.project.id)

            {:noreply,
             socket
             |> assign(:pages_tree, pages_tree)
             |> push_navigate(
               to:
                 ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/pages/#{new_page.id}"
             )}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, gettext("Could not create page."))}
        end

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, gettext("You don't have permission to perform this action."))}
    end
  end

  @impl true
  def handle_info(:reset_save_status, socket) do
    {:noreply, assign(socket, :save_status, :idle)}
  end

  defp schedule_save_status_reset do
    Process.send_after(self(), :reset_save_status, 4000)
  end

  defp add_multi_select_option(socket, block_id, value) do
    block = Pages.get_block!(block_id)

    # Generate a unique key from the value
    key = generate_option_key(value)

    # Get current options and content
    current_options = get_in(block.config, ["options"]) || []
    current_content = get_in(block.value, ["content"]) || []

    # Check if option already exists (by key or value)
    existing = Enum.find(current_options, fn opt ->
      opt["key"] == key || String.downcase(opt["value"] || "") == String.downcase(value)
    end)

    if existing do
      # Option exists - just select it if not already selected
      if existing["key"] in current_content do
        {:noreply, socket}
      else
        new_content = [existing["key"] | current_content]
        update_multi_select_content(socket, block, new_content)
      end
    else
      # Create new option and select it
      new_option = %{"key" => key, "value" => value}
      new_options = current_options ++ [new_option]
      new_content = [key | current_content]

      # Update both config and value
      with {:ok, _} <- Pages.update_block_config(block, %{"options" => new_options, "label" => block.config["label"] || ""}),
           block <- Pages.get_block!(block_id),
           {:ok, _} <- Pages.update_block_value(block, %{"content" => new_content}) do
        blocks = Pages.list_blocks(socket.assigns.page.id)
        schedule_save_status_reset()

        {:noreply,
         socket
         |> assign(:blocks, blocks)
         |> assign(:save_status, :saved)}
      else
        _ -> {:noreply, socket}
      end
    end
  end

  defp update_multi_select_content(socket, block, new_content) do
    case Pages.update_block_value(block, %{"content" => new_content}) do
      {:ok, _} ->
        blocks = Pages.list_blocks(socket.assigns.page.id)
        schedule_save_status_reset()

        {:noreply,
         socket
         |> assign(:blocks, blocks)
         |> assign(:save_status, :saved)}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  defp generate_option_key(value) do
    value
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
    |> then(fn key ->
      if key == "", do: "option-#{:rand.uniform(9999)}", else: key
    end)
  end

  defp do_delete_page(socket, page) do
    case Pages.delete_page(page) do
      {:ok, _} ->
        handle_page_deleted(socket, page)

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Could not delete page."))}
    end
  end

  defp handle_page_deleted(socket, deleted_page) do
    socket = put_flash(socket, :info, gettext("Page deleted successfully."))

    if deleted_page.id == socket.assigns.page.id do
      {:noreply,
       push_navigate(socket,
         to:
           ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/pages"
       )}
    else
      pages_tree = Pages.list_pages_tree(socket.assigns.project.id)
      {:noreply, assign(socket, :pages_tree, pages_tree)}
    end
  end

  defp normalize_parent_id(""), do: nil
  defp normalize_parent_id(nil), do: nil
  defp normalize_parent_id(parent_id), do: parent_id
end
