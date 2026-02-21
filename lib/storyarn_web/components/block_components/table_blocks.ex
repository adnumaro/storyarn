defmodule StoryarnWeb.Components.BlockComponents.TableBlocks do
  @moduledoc false

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.Components.CoreComponents,
    only: [block_label: 1, icon: 1, confirm_modal: 1]

  alias Phoenix.LiveView.JS

  attr :block, :map, required: true
  attr :can_edit, :boolean, default: false
  attr :columns, :list, default: []
  attr :rows, :list, default: []
  attr :target, :any, default: nil

  def table_block(assigns) do
    label = get_in(assigns.block.config, ["label"]) || ""
    collapsed = get_in(assigns.block.config, ["collapsed"]) == true
    is_constant = assigns.block.is_constant || false
    row_count = length(assigns.rows)
    col_count = length(assigns.columns)

    assigns =
      assigns
      |> assign(:label, label)
      |> assign(:collapsed, collapsed)
      |> assign(:is_constant, is_constant)
      |> assign(:row_count, row_count)
      |> assign(:col_count, col_count)

    ~H"""
    <div class="py-1">
      <.block_label label={@label} is_constant={@is_constant} />

      <%= if @collapsed && @can_edit do %>
        <.collapsed_table
          block={@block}
          row_count={@row_count}
          col_count={@col_count}
          target={@target}
        />
      <% else %>
        <.expanded_table
          block={@block}
          columns={@columns}
          rows={@rows}
          can_edit={@can_edit}
          target={@target}
        />
      <% end %>
    </div>
    """
  end

  # =============================================================================
  # Collapsed View
  # =============================================================================

  defp collapsed_table(assigns) do
    summary =
      dngettext(
        "sheets",
        "%{rows} row, %{columns} column",
        "%{rows} rows, %{columns} columns",
        assigns.row_count,
        rows: assigns.row_count,
        columns: assigns.col_count
      )

    assigns = assign(assigns, :summary, summary)

    ~H"""
    <button
      type="button"
      class="flex items-center gap-2 py-2 px-3 rounded-lg border border-base-300 bg-base-200/30 hover:bg-base-200/60 w-full text-left text-sm transition-colors"
      phx-click="toggle_table_collapse"
      phx-value-block-id={@block.id}
      phx-target={@target}
    >
      <.icon name="table-2" class="size-4 text-base-content/60" />
      <span class="text-base-content/60">({@summary})</span>
      <.icon name="chevron-right" class="size-3 text-base-content/40 ml-auto" />
    </button>
    """
  end

  # =============================================================================
  # Expanded View
  # =============================================================================

  defp expanded_table(assigns) do
    ~H"""
    <div>
      <%!-- Collapse toggle --%>
      <button
        :if={@can_edit}
        type="button"
        class="flex items-center gap-1 text-xs text-base-content/40 hover:text-base-content/70 mb-1 transition-colors"
        phx-click="toggle_table_collapse"
        phx-value-block-id={@block.id}
        phx-target={@target}
      >
        <.icon name="chevron-down" class="size-3" />
        <span>{dgettext("sheets", "Collapse")}</span>
      </button>

      <%!-- Table grid --%>
      <div class="overflow-x-clip border border-base-content/20 rounded-lg">
        <table class="table table-sm w-full [&_:is(th,td)]:border-base-content/20 [&_:is(th,td)]:border-r [&_:is(th,td):last-child]:border-r-0">
          <thead>
            <tr class="bg-base-content/5 border-b border-base-content/20">
              <%!-- Row label header (wider when editable for drag handle) --%>
              <th class={["font-medium text-base-content/60", (@can_edit && "w-40") || "w-32"]}></th>

              <%!-- Column headers --%>
              <th :for={col <- @columns} class="font-medium text-base-content/70">
                <%!-- Editable: floating dropdown with management options --%>
                <div
                  :if={@can_edit}
                  phx-hook="TableColumnDropdown"
                  id={"col-dropdown-#{col.id}"}
                  data-phx-target={@target}
                >
                  <button
                    type="button"
                    data-role="trigger"
                    class="flex items-center gap-1.5 cursor-pointer hover:text-base-content"
                  >
                    <.icon name={type_icon(col.type)} class="size-3.5 opacity-50" />
                    {col.name}
                    <span :if={col.required} class="text-error text-xs">*</span>
                    <.icon name="chevron-down" class="size-3 opacity-40" />
                  </button>
                  <.column_dropdown_template
                    column={col}
                    columns={@columns}
                    block={@block}
                    target={@target}
                  />
                </div>
                <%!-- Read-only: plain text --%>
                <span :if={!@can_edit} class="flex items-center gap-1.5">
                  <.icon name={type_icon(col.type)} class="size-3.5 opacity-50" />
                  {col.name}
                  <span :if={col.required} class="text-error text-xs">*</span>
                </span>
              </th>

              <%!-- Add column button --%>
              <th :if={@can_edit} class="w-10">
                <button
                  type="button"
                  phx-click="add_table_column"
                  phx-value-block-id={@block.id}
                  phx-target={@target}
                  class="btn btn-ghost btn-xs btn-circle"
                >
                  <.icon name="plus" class="size-3" />
                </button>
              </th>
            </tr>
          </thead>
          <tbody
            id={"table-rows-#{@block.id}"}
            phx-hook={(@can_edit && "TableRowSortable") || nil}
            data-block-id={@block.id}
            data-phx-target={(@can_edit && @target) || nil}
          >
            <tr :for={row <- @rows} data-row-id={row.id} class="group/row">
              <%!-- Row label cell --%>
              <td class="sticky left-0 z-10 bg-base-100 font-medium text-base-content/60 text-sm focus-within:border-primary focus-within:border-2">
                <div :if={@can_edit} class="flex items-center gap-1">
                  <.icon
                    name="grip-vertical"
                    class="size-3 opacity-30 cursor-grab row-drag-handle shrink-0"
                  />
                  <input
                    type="text"
                    value={row.name}
                    class="input input-ghost input-sm w-full px-1 font-medium focus:outline-none focus:shadow-none focus:border-transparent"
                    phx-blur="rename_table_row"
                    phx-keydown="rename_table_row_keydown"
                    phx-key="Enter"
                    phx-value-row-id={row.id}
                    phx-target={@target}
                  />
                </div>
                <span :if={!@can_edit}>{row.name}</span>
              </td>

              <%!-- Data cells --%>
              <td
                :for={col <- @columns}
                class="!p-0 focus-within:border-primary focus-within:border-2"
              >
                <.table_cell
                  column={col}
                  row={row}
                  value={row.cells[col.slug]}
                  can_edit={@can_edit}
                  target={@target}
                />
              </td>

              <%!-- Row actions (delete) --%>
              <td :if={@can_edit} class="w-8">
                <div
                  phx-hook="TableRowMenu"
                  id={"row-menu-#{row.id}"}
                  data-phx-target={@target}
                >
                  <button
                    data-role="trigger"
                    type="button"
                    class="btn btn-ghost btn-xs opacity-0 group-hover/row:opacity-100"
                  >
                    <.icon name="more-vertical" class="size-3" />
                  </button>
                  <template data-role="popover-template">
                    <ul class="menu p-2">
                      <li>
                        <button
                          disabled={length(@rows) <= 1}
                          data-event="prepare_delete_row"
                          data-params={Jason.encode!(%{"row-id" => row.id})}
                          data-modal-id={"table-delete-row-#{@block.id}"}
                          class="text-error disabled:opacity-30"
                        >
                          <.icon name="trash-2" class="size-3" />
                          {dgettext("sheets", "Delete")}
                        </button>
                      </li>
                    </ul>
                  </template>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <%!-- Add row button --%>
      <button
        :if={@can_edit}
        type="button"
        phx-click="add_table_row"
        phx-value-block-id={@block.id}
        phx-target={@target}
        class="btn btn-ghost btn-xs gap-1 mt-1"
      >
        <.icon name="plus" class="size-3" />
        <span>{dgettext("sheets", "+ New")}</span>
      </button>

      <%!-- Confirmation modals --%>
      <.confirm_modal
        :if={@can_edit}
        id={"table-delete-col-#{@block.id}"}
        title={dgettext("sheets", "Delete column?")}
        message={
          dgettext(
            "sheets",
            "This will remove the column and all its data. This cannot be undone."
          )
        }
        confirm_text={dgettext("sheets", "Delete")}
        confirm_variant="error"
        icon="trash-2"
        icon_class="text-error"
        on_confirm={JS.push("execute_delete_column", target: @target)}
        on_cancel={JS.push("cancel_table_confirm", target: @target)}
      />

      <.confirm_modal
        :if={@can_edit}
        id={"table-delete-row-#{@block.id}"}
        title={dgettext("sheets", "Delete row?")}
        message={
          dgettext(
            "sheets",
            "This will remove the row and all its cell data. This cannot be undone."
          )
        }
        confirm_text={dgettext("sheets", "Delete")}
        confirm_variant="error"
        icon="trash-2"
        icon_class="text-error"
        on_confirm={JS.push("execute_delete_row", target: @target)}
        on_cancel={JS.push("cancel_table_confirm", target: @target)}
      />
    </div>
    """
  end

  # =============================================================================
  # Column Header Dropdown
  # =============================================================================

  defp column_dropdown_template(assigns) do
    ~H"""
    <template data-role="popover-template">
      <ul class="menu p-0">
        <%!-- Rename input --%>
        <li class="mb-2">
          <input
            type="text"
            data-role="rename-input"
            data-rename-event="rename_table_column"
            data-column-id={@column.id}
            value={@column.name}
            class="input input-ghost input-sm w-full h-full rounded-none focus:outline-none focus:shadow-none focus:border-transparent"
          />
        </li>

        <%!-- Constant toggle --%>
        <li class="mb-1">
          <button
            type="button"
            class={@column.is_constant && "active"}
            data-event="toggle_table_column_constant"
            data-params={Jason.encode!(%{"column-id" => @column.id})}
            data-close-on-click="false"
          >
            <.icon name="lock" class="size-3.5 opacity-60" />
            <div class="flex-1">
              <div class="flex items-center justify-between">
                <span class="text-sm">{dgettext("sheets", "Constant")}</span>
                <.icon
                  :if={@column.is_constant}
                  name="check"
                  class="size-3.5 opacity-60"
                />
              </div>
              <span class="text-xs text-base-content/50 block">
                {dgettext("sheets", "Won't generate a variable")}
              </span>
            </div>
          </button>
        </li>

        <%!-- Required toggle --%>
        <li class="mb-1">
          <button
            type="button"
            class={@column.required && "active"}
            data-event="toggle_table_column_required"
            data-params={Jason.encode!(%{"column-id" => @column.id})}
            data-close-on-click="false"
          >
            <.icon name="asterisk" class="size-3.5 opacity-60" />
            <div class="flex-1">
              <div class="flex items-center justify-between">
                <span class="text-sm">{dgettext("sheets", "Required")}</span>
                <.icon
                  :if={@column.required}
                  name="check"
                  class="size-3.5 opacity-60"
                />
              </div>
              <span class="text-xs text-base-content/50 block">
                {dgettext("sheets", "Value cannot be empty")}
              </span>
            </div>
          </button>
        </li>

        <%!-- Type selection --%>
        <li class="menu-title text-xs">{dgettext("sheets", "Type")}</li>
        <li :for={type <- ~w(number text boolean select multi_select date)}>
          <button
            type="button"
            class={@column.type == type && "active"}
            data-event={if @column.type != type, do: "change_table_column_type"}
            data-params={
              if @column.type != type,
                do: Jason.encode!(%{"column-id" => @column.id, "new-type" => type})
            }
            data-close-on-click="false"
          >
            <.icon name={type_icon(type)} class="size-3.5 opacity-60" />
            <span class="text-sm">{type_label(type)}</span>
            <.icon :if={@column.type == type} name="check" class="size-3.5 ml-auto opacity-60" />
          </button>
        </li>

        <%!-- Options management for select/multi_select --%>
        <.column_options_template
          :if={@column.type in ["select", "multi_select"]}
          column={@column}
          target={@target}
        />

        <%!-- Delete column --%>
        <li class="mt-2 border-t border-base-300 pt-2">
          <button
            disabled={length(@columns) <= 1}
            data-event="prepare_delete_column"
            data-params={Jason.encode!(%{"column-id" => @column.id})}
            data-modal-id={"table-delete-col-#{@block.id}"}
            class="text-error disabled:opacity-30"
          >
            <.icon name="trash-2" class="size-3" />
            {dgettext("sheets", "Delete column")}
          </button>
        </li>
      </ul>
    </template>
    """
  end

  # =============================================================================
  # Select Options Section (in column dropdown)
  # =============================================================================

  defp column_options_template(assigns) do
    options = (assigns.column.config || %{})["options"] || []
    assigns = assign(assigns, :options, options)

    ~H"""
    <div class="mt-2 border-t border-base-300 pt-2">
      <div class="text-xs font-medium text-base-content/50 mb-1 px-2">
        {dgettext("sheets", "Options")}
      </div>
      <div
        :for={{opt, idx} <- Enum.with_index(@options)}
        class="flex items-center gap-1 mb-1 px-1"
      >
        <input
          type="text"
          data-role="option-input"
          data-blur-event="update_table_column_option"
          data-param-column-id={@column.id}
          data-param-index={idx}
          value={opt["value"]}
          class="input input-bordered input-xs flex-1"
        />
        <button
          type="button"
          data-event="remove_table_column_option"
          data-params={Jason.encode!(%{"column-id" => @column.id, "key" => opt["key"]})}
          data-close-on-click="false"
          class="btn btn-ghost btn-xs btn-circle"
        >
          <.icon name="x" class="size-3" />
        </button>
      </div>
      <div class="px-1">
        <input
          type="text"
          data-role="add-option-input"
          data-keydown-event="add_table_column_option_keydown"
          data-column-id={@column.id}
          placeholder={dgettext("sheets", "+ Add option")}
          class="input input-bordered input-xs w-full"
        />
      </div>
    </div>
    """
  end

  # =============================================================================
  # Cell Rendering
  # =============================================================================

  defp table_cell(%{can_edit: true} = assigns) do
    ~H"""
    <%= case @column.type do %>
      <% "number" -> %>
        <input
          type="number"
          value={@value}
          class="input input-ghost input-sm w-full h-full rounded-none focus:outline-none focus:shadow-none focus:border-transparent"
          phx-blur="update_table_cell"
          phx-value-row-id={@row.id}
          phx-value-column-slug={@column.slug}
          phx-target={@target}
        />
      <% "text" -> %>
        <input
          type="text"
          value={@value}
          class="input input-ghost input-sm w-full h-full rounded-none focus:outline-none focus:shadow-none focus:border-transparent"
          phx-blur="update_table_cell"
          phx-value-row-id={@row.id}
          phx-value-column-slug={@column.slug}
          phx-target={@target}
        />
      <% "boolean" -> %>
        <label class="flex items-center justify-center cursor-pointer py-1">
          <input
            type="checkbox"
            checked={@value == true}
            class="checkbox checkbox-sm"
            phx-hook="TableCellCheckbox"
            id={"table-cell-#{@row.id}-#{@column.slug}"}
            data-row-id={@row.id}
            data-column-slug={@column.slug}
            data-state={if @value == true, do: "true", else: "false"}
            data-phx-target={if @target, do: "#content-tab"}
          />
        </label>
      <% "select" -> %>
        <% options = @column.config["options"] || [] %>
        <% selected_label = find_option_label(options, @value) %>
        <div
          phx-hook="TableCellSelect"
          id={"table-cell-select-#{@row.id}-#{@column.slug}"}
          data-mode="select"
          class="w-full"
        >
          <button
            type="button"
            data-role="trigger"
            class="flex items-center gap-1 w-full px-2 py-1 text-sm text-left cursor-pointer hover:bg-base-200/50 min-h-[2rem]"
          >
            <span :if={selected_label} class="truncate">{selected_label}</span>
            <span :if={!selected_label} class="text-base-content/40 truncate">
              {dgettext("sheets", "Select...")}
            </span>
          </button>
          <template data-role="popover-template">
            <div class="p-2">
              <input
                data-role="search"
                type="text"
                class="input input-bordered input-xs w-full"
                placeholder={dgettext("sheets", "Search...")}
              />
            </div>
            <div data-role="list" class="max-h-48 overflow-y-auto px-1 pb-1">
              <button
                :if={@value}
                type="button"
                data-search-text=""
                class="flex items-center gap-2 w-full px-2 py-1.5 text-xs text-base-content/50 hover:bg-base-content/10 rounded"
                phx-click="select_table_cell"
                phx-value-row-id={@row.id}
                phx-value-column-slug={@column.slug}
                phx-value-key=""
                phx-target={@target}
              >
                <.icon name="x" class="size-3" />
                {dgettext("sheets", "Clear")}
              </button>
              <button
                :for={opt <- options}
                type="button"
                data-search-text={String.downcase(opt["value"] || "")}
                class={[
                  "flex items-center gap-2 w-full px-2 py-1.5 text-sm hover:bg-base-content/10 rounded",
                  @value == opt["key"] && "bg-primary/10 text-primary"
                ]}
                phx-click="select_table_cell"
                phx-value-row-id={@row.id}
                phx-value-column-slug={@column.slug}
                phx-value-key={opt["key"]}
                phx-target={@target}
              >
                {opt["value"]}
                <.icon
                  :if={@value == opt["key"]}
                  name="check"
                  class="size-3 ml-auto opacity-60"
                />
              </button>
            </div>
            <div class="border-t border-base-content/10 p-2">
              <input
                data-role="add-input"
                type="text"
                class="input input-bordered input-xs w-full"
                placeholder={dgettext("sheets", "+ New option")}
                phx-keydown="add_table_cell_option"
                phx-value-column-id={@column.id}
                phx-value-row-id={@row.id}
                phx-value-column-slug={@column.slug}
                phx-target={@target}
              />
            </div>
            <div
              data-role="empty"
              style="display:none"
              class="px-3 py-2 text-xs text-base-content/40"
            >
              {dgettext("sheets", "No matches")}
            </div>
          </template>
        </div>
      <% "multi_select" -> %>
        <% options = @column.config["options"] || [] %>
        <% selected_labels = resolve_multi_select_labels(@value, options) %>
        <div
          phx-hook="TableCellSelect"
          id={"table-cell-select-#{@row.id}-#{@column.slug}"}
          data-mode="multi_select"
          class="w-full"
        >
          <button
            type="button"
            data-role="trigger"
            class="flex items-center gap-1 w-full px-2 py-1 text-sm text-left cursor-pointer hover:bg-base-200/50 min-h-[2rem]"
          >
            <div :if={selected_labels != []} class="flex flex-wrap gap-1">
              <span
                :for={label <- selected_labels}
                class="badge badge-xs badge-primary"
              >
                {label}
              </span>
            </div>
            <span :if={selected_labels == []} class="text-base-content/40 truncate">
              {dgettext("sheets", "Select...")}
            </span>
          </button>
          <template data-role="popover-template">
            <div class="p-2">
              <input
                data-role="search"
                type="text"
                class="input input-bordered input-xs w-full"
                placeholder={dgettext("sheets", "Search...")}
              />
            </div>
            <div data-role="list" class="max-h-48 overflow-y-auto px-1 pb-1">
              <button
                :for={opt <- options}
                type="button"
                data-search-text={String.downcase(opt["value"] || "")}
                class={[
                  "flex items-center gap-2 w-full px-2 py-1.5 text-sm hover:bg-base-content/10 rounded",
                  opt["key"] in (@value || []) && "bg-primary/10"
                ]}
                phx-click="toggle_table_cell_multi_select"
                phx-value-row-id={@row.id}
                phx-value-column-slug={@column.slug}
                phx-value-key={opt["key"]}
                phx-target={@target}
              >
                <input
                  type="checkbox"
                  checked={opt["key"] in (@value || [])}
                  class="checkbox checkbox-xs checkbox-primary"
                  onclick="event.preventDefault()"
                />
                {opt["value"]}
              </button>
            </div>
            <div class="border-t border-base-content/10 p-2">
              <input
                data-role="add-input"
                type="text"
                class="input input-bordered input-xs w-full"
                placeholder={dgettext("sheets", "+ New option")}
                phx-keydown="add_table_cell_option"
                phx-value-column-id={@column.id}
                phx-value-row-id={@row.id}
                phx-value-column-slug={@column.slug}
                phx-target={@target}
              />
            </div>
            <div
              data-role="empty"
              style="display:none"
              class="px-3 py-2 text-xs text-base-content/40"
            >
              {dgettext("sheets", "No matches")}
            </div>
          </template>
        </div>
      <% "date" -> %>
        <input
          type="date"
          value={@value}
          class="input input-ghost input-sm w-full h-full rounded-none focus:outline-none focus:shadow-none focus:border-transparent"
          phx-blur="update_table_cell"
          phx-value-row-id={@row.id}
          phx-value-column-slug={@column.slug}
          phx-target={@target}
        />
      <% _ -> %>
        <span class="text-base-content/40 text-sm">&mdash;</span>
    <% end %>
    """
  end

  defp table_cell(%{can_edit: false} = assigns) do
    ~H"""
    <%= case @column.type do %>
      <% "number" -> %>
        <span class="text-sm">{display_value(@value, "0")}</span>
      <% "text" -> %>
        <span class={["text-sm", is_nil(@value) && "text-base-content/40"]}>
          {display_value(@value, "\u2014")}
        </span>
      <% "boolean" -> %>
        <.boolean_badge value={@value} />
      <% "select" -> %>
        <% options = @column.config["options"] || [] %>
        <span class={["text-sm", is_nil(@value) && "text-base-content/40"]}>
          {find_option_label(options, @value) || "\u2014"}
        </span>
      <% "multi_select" -> %>
        <.multi_select_badges value={@value} column={@column} />
      <% "date" -> %>
        <span class={["text-sm", @value in [nil, ""] && "text-base-content/40"]}>
          {format_date(@value)}
        </span>
      <% _ -> %>
        <span class="text-base-content/40 text-sm">&mdash;</span>
    <% end %>
    """
  end

  # =============================================================================
  # Display Helpers
  # =============================================================================

  defp boolean_badge(%{value: true} = assigns) do
    ~H"""
    <span class="badge badge-sm badge-success">{dgettext("sheets", "Yes")}</span>
    """
  end

  defp boolean_badge(%{value: false} = assigns) do
    ~H"""
    <span class="badge badge-sm badge-error">{dgettext("sheets", "No")}</span>
    """
  end

  defp boolean_badge(assigns) do
    ~H"""
    <span class="text-base-content/40 text-sm">&mdash;</span>
    """
  end

  defp multi_select_badges(assigns) do
    values = assigns.value || []
    options = assigns.column.config["options"] || []

    labels =
      Enum.map(values, fn key ->
        option = Enum.find(options, fn opt -> opt["key"] == key end)
        (option && option["value"]) || key
      end)

    assigns = assign(assigns, :labels, labels)

    ~H"""
    <div :if={@labels != []} class="flex flex-wrap gap-1">
      <span :for={label <- @labels} class="badge badge-sm badge-primary">{label}</span>
    </div>
    <span :if={@labels == []} class="text-base-content/40 text-sm">&mdash;</span>
    """
  end

  defp display_value(nil, fallback), do: fallback
  defp display_value("", fallback), do: fallback
  defp display_value(value, _fallback), do: to_string(value)

  defp find_option_label(options, key) do
    Enum.find_value(options, fn opt -> opt["key"] == key && opt["value"] end)
  end

  defp format_date(nil), do: "\u2014"
  defp format_date(""), do: "\u2014"

  defp format_date(date_string) do
    case Date.from_iso8601(date_string) do
      {:ok, date} -> Calendar.strftime(date, "%B %d, %Y")
      _ -> date_string
    end
  end

  defp resolve_multi_select_labels(nil, _options), do: []
  defp resolve_multi_select_labels([], _options), do: []

  defp resolve_multi_select_labels(keys, options) when is_list(keys) do
    Enum.map(keys, fn key ->
      case Enum.find(options, fn opt -> opt["key"] == key end) do
        nil -> key
        opt -> opt["value"]
      end
    end)
  end

  defp resolve_multi_select_labels(_value, _options), do: []

  defp type_icon("number"), do: "hash"
  defp type_icon("text"), do: "type"
  defp type_icon("boolean"), do: "toggle-left"
  defp type_icon("select"), do: "circle-dot"
  defp type_icon("multi_select"), do: "list"
  defp type_icon("date"), do: "calendar"
  defp type_icon(_), do: "columns-2"

  defp type_label("number"), do: dgettext("sheets", "Number")
  defp type_label("text"), do: dgettext("sheets", "Text")
  defp type_label("boolean"), do: dgettext("sheets", "Boolean")
  defp type_label("select"), do: dgettext("sheets", "Select")
  defp type_label("multi_select"), do: dgettext("sheets", "Multi Select")
  defp type_label("date"), do: dgettext("sheets", "Date")
  defp type_label(type), do: type
end
