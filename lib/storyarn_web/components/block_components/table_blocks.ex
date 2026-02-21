defmodule StoryarnWeb.Components.BlockComponents.TableBlocks do
  @moduledoc false

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.Components.CoreComponents, only: [icon: 1]

  attr :block, :map, required: true
  attr :can_edit, :boolean, default: false
  attr :schema_locked, :boolean, default: false
  attr :columns, :list, default: []
  attr :rows, :list, default: []
  attr :reference_options, :list, default: []
  attr :target, :any, default: nil

  def table_block(assigns) do
    label = get_in(assigns.block.config, ["label"]) || ""
    collapsed = get_in(assigns.block.config, ["collapsed"]) == true
    is_constant = assigns.block.is_constant || false
    row_count = length(assigns.rows)
    col_count = length(assigns.columns)
    # can_manage: allowed to modify table structure (add/delete/rename columns/rows)
    # When schema_locked, structure is locked but cell values are still editable
    can_manage = assigns.can_edit && !assigns.schema_locked

    summary =
      dngettext(
        "sheets",
        "%{rows} row, %{columns} column",
        "%{rows} rows, %{columns} columns",
        row_count,
        rows: row_count,
        columns: col_count
      )

    assigns =
      assigns
      |> assign(:label, label)
      |> assign(:collapsed, collapsed)
      |> assign(:is_constant, is_constant)
      |> assign(:row_count, row_count)
      |> assign(:col_count, col_count)
      |> assign(:can_manage, can_manage)
      |> assign(:summary, summary)

    ~H"""
    <div class="py-1">
      <%!-- Unified header: chevron + table icon + label (+ summary when collapsed) --%>
      <.table_header
        block={@block}
        label={@label}
        is_constant={@is_constant}
        collapsed={@collapsed}
        can_edit={@can_edit}
        can_manage={@can_manage}
        summary={@summary}
        target={@target}
      />

      <%!-- Table grid (only when expanded) --%>
      <.expanded_table
        :if={!@collapsed || !@can_manage}
        block={@block}
        columns={@columns}
        rows={@rows}
        can_edit={@can_edit}
        can_manage={@can_manage}
        reference_options={@reference_options}
        target={@target}
      />
    </div>
    """
  end

  # =============================================================================
  # Unified Table Header
  # =============================================================================

  defp table_header(assigns) do
    ~H"""
    <button
      :if={@can_manage}
      type="button"
      class="flex items-center gap-1.5 text-sm mb-1 transition-colors group/header"
      phx-click="toggle_table_collapse"
      phx-value-block-id={@block.id}
      phx-target={@target}
    >
      <.icon
        name={if @collapsed, do: "chevron-right", else: "chevron-down"}
        class="size-3 text-base-content/40 group-hover/header:text-base-content/70"
      />
      <.icon name="table-2" class="size-3.5 text-base-content/50" />
      <span :if={@is_constant} class="text-error tooltip tooltip-right" data-tip={gettext("Constant")}>
        <.icon name="lock" class="size-3" />
      </span>
      <span class="text-base-content/70">{@label}</span>
      <span :if={@collapsed} class="text-base-content/40">({@summary})</span>
    </button>
    <%!-- Read-only or schema-locked: no collapse, just label --%>
    <label
      :if={!@can_manage && @label != ""}
      class="text-sm text-base-content/70 mb-1 flex items-center gap-1.5"
    >
      <.icon name="table-2" class="size-3.5 text-base-content/50" />
      <span>{@label}</span>
    </label>
    """
  end

  # =============================================================================
  # Expanded View
  # =============================================================================

  defp expanded_table(assigns) do
    ~H"""
    <div class="group/table">
      <%!-- Table grid --%>
      <div class="relative">
        <div class="border border-base-content/20 rounded-lg overflow-x-auto">
          <table
            class="table table-sm table-fixed w-full [&_:is(th,td)]:border-base-content/20 [&_:is(th,td)]:border-r [&_:is(th,td):last-child]:border-r-0"
            id={@can_manage && "table-resize-#{@block.id}"}
            phx-hook={@can_manage && "TableColumnResize"}
            data-phx-target={@can_manage && @target}
          >
            <colgroup>
              <col style="width: 8rem;" />
              <col
                :for={col <- @columns}
                data-col-id={col.id}
                style={"width: #{column_width(col)}px;"}
              />
            </colgroup>
            <thead>
              <tr class="bg-base-content/5 border-b border-base-content/20 [&>th:first-child]:rounded-tl-lg [&>th:last-child]:rounded-tr-lg">
                <%!-- Row label header --%>
                <th class="font-medium text-base-content/60 sticky left-0 z-10 bg-base-200"></th>

                <%!-- Column headers --%>
                <th
                  :for={col <- @columns}
                  class="font-medium text-base-content/70 relative overflow-hidden"
                >
                  <%!-- Editable: floating dropdown with management options --%>
                  <div
                    :if={@can_manage}
                    phx-hook="TableColumnDropdown"
                    id={"col-dropdown-#{col.id}"}
                    data-phx-target={@target}
                    data-col-state={column_state_hash(col)}
                    class="min-w-0"
                  >
                    <button
                      type="button"
                      data-role="trigger"
                      class="flex flex-col items-start cursor-pointer hover:text-base-content w-full min-w-0"
                    >
                      <span class="flex items-center gap-1.5 max-w-full">
                        <.icon name={type_icon(col.type)} class="size-3.5 opacity-50 shrink-0" />
                        <span class="truncate">{col.name}</span>
                        <span :if={col.required} class="text-error text-xs shrink-0">*</span>
                        <.icon name="chevron-down" class="size-3 opacity-40 shrink-0" />
                      </span>
                      <span class="text-[10px] font-normal text-base-content/30 truncate max-w-full">
                        {col.slug}
                      </span>
                    </button>
                    <.column_dropdown_template
                      column={col}
                      columns={@columns}
                      block={@block}
                      target={@target}
                    />
                  </div>
                  <%!-- Read-only or schema-locked: plain text --%>
                  <div :if={!@can_manage} class="min-w-0">
                    <span class="flex items-center gap-1.5 max-w-full">
                      <.icon name={type_icon(col.type)} class="size-3.5 opacity-50 shrink-0" />
                      <span class="truncate">{col.name}</span>
                      <span :if={col.required} class="text-error text-xs shrink-0">*</span>
                    </span>
                    <span class="text-[10px] font-normal text-base-content/30 truncate max-w-full">
                      {col.slug}
                    </span>
                  </div>
                  <%!-- Resize handle (manage mode only) --%>
                  <div
                    :if={@can_manage}
                    data-resize-handle
                    data-col-id={col.id}
                    class="absolute top-0 -right-px w-1 h-full cursor-col-resize z-10 hover:bg-primary/40 transition-colors"
                  />
                </th>
              </tr>
            </thead>
            <tbody
              id={"table-rows-#{@block.id}"}
              phx-hook={(@can_manage && "TableRowSortable") || nil}
              data-block-id={@block.id}
              data-phx-target={(@can_manage && @target) || nil}
            >
              <tr :for={row <- @rows} data-row-id={row.id} class="group/row">
                <%!-- Row label cell (with handle positioned outside) --%>
                <td class="relative sticky left-0 z-10 bg-base-100 font-medium text-base-content/60 text-sm focus-within:border-primary focus-within:border-2">
                  <%!-- Row handle: grip (drag) + menu (delete) — on hover, over the left border --%>
                  <div
                    :if={@can_manage}
                    phx-hook="TableRowMenu"
                    id={"row-menu-#{row.id}"}
                    data-phx-target={@target}
                    class="absolute right-full top-0 h-full flex items-center pr-0.5 opacity-0 group-hover/row:opacity-100 transition-opacity z-20"
                  >
                    <button
                      data-role="trigger"
                      type="button"
                      class="cursor-grab row-drag-handle p-0.5 rounded hover:bg-base-content/10"
                    >
                      <.icon name="grip-vertical" class="size-3.5 text-base-content/40" />
                    </button>
                    <template data-role="popover-template">
                      <ul class="menu p-2">
                        <li>
                          <button
                            disabled={length(@rows) <= 1}
                            data-event="delete_table_row"
                            data-params={Jason.encode!(%{"row-id" => row.id})}
                            class="text-error disabled:opacity-30"
                          >
                            <.icon name="trash-2" class="size-3" />
                            {dgettext("sheets", "Delete")}
                          </button>
                        </li>
                      </ul>
                    </template>
                  </div>

                  <label :if={@can_manage} class="block cursor-text">
                    <input
                      type="text"
                      value={row.name}
                      class="w-full px-1 py-0.5 text-sm font-medium bg-transparent border-0 outline-none focus:outline-none"
                      phx-blur="rename_table_row"
                      phx-keydown="rename_table_row_keydown"
                      phx-key="Enter"
                      phx-value-row-id={row.id}
                      phx-target={@target}
                    />
                    <span class="text-[10px] text-base-content/30 px-1">{row.slug}</span>
                  </label>
                  <div :if={!@can_manage}>
                    <span>{row.name}</span>
                    <div class="text-[10px] text-base-content/30">{row.slug}</div>
                  </div>
                </td>

                <%!-- Data cells — relative + h-1 so absolute-inset children fill the cell --%>
                <td
                  :for={col <- @columns}
                  class="!p-0 relative h-1 focus-within:border-primary focus-within:border-2"
                >
                  <.table_cell
                    column={col}
                    row={row}
                    value={row.cells[col.slug]}
                    can_edit={@can_edit}
                    reference_options={@reference_options}
                    target={@target}
                  />
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <%!-- Add column bar — absolute, outside right edge --%>
        <button
          :if={@can_manage}
          type="button"
          phx-click="add_table_column"
          phx-value-block-id={@block.id}
          phx-target={@target}
          class="absolute left-full top-0 h-full flex items-center justify-center w-6 ml-2 rounded-lg border border-base-content/10 bg-base-content/[0.02] hover:bg-base-content/5 text-base-content/30 hover:text-base-content/50 transition-all cursor-pointer opacity-0 group-hover/table:opacity-100 tooltip tooltip-right"
          data-tip={dgettext("sheets", "Add column")}
        >
          <.icon name="plus" class="size-3.5" />
        </button>
      </div>

      <%!-- Add row bar — visible on hover near the bottom of the table --%>
      <button
        :if={@can_manage}
        type="button"
        phx-click="add_table_row"
        phx-value-block-id={@block.id}
        phx-target={@target}
        class="flex items-center justify-center w-full h-6 mt-2 rounded-lg border border-base-content/10 bg-base-content/[0.02] hover:bg-base-content/5 text-base-content/30 hover:text-base-content/50 transition-all cursor-pointer opacity-0 group-hover/table:opacity-100 tooltip"
        data-tip={dgettext("sheets", "Add row")}
      >
        <.icon name="plus" class="size-3.5" />
      </button>
    </div>
    """
  end

  # =============================================================================
  # Column Header Dropdown
  # =============================================================================

  defp column_dropdown_template(assigns) do
    options = (assigns.column.config || %{})["options"] || []
    assigns = assign(assigns, :options, options)

    ~H"""
    <div data-role="popover-template" hidden>
      <%!-- ========== Main Panel ========== --%>
      <div class="col-dropdown-panel" data-panel="main" data-active>
        <ul class="menu p-0">
          <%!-- Rename input with type icon --%>
          <li class="mb-2">
            <div class="flex items-center gap-1.5 px-2">
              <.icon name={type_icon(@column.type)} class="size-3.5 opacity-50 shrink-0" />
              <input
                type="text"
                data-role="rename-input"
                data-rename-event="rename_table_column"
                data-column-id={@column.id}
                value={@column.name}
                class="input input-ghost input-sm w-full h-full rounded-none focus:outline-none focus:shadow-none focus:border-transparent px-0"
              />
            </div>
          </li>

          <%!-- Constant toggle (compact single-line) --%>
          <li>
            <button
              type="button"
              data-event="toggle_table_column_constant"
              data-params={Jason.encode!(%{"column-id" => @column.id})}
              data-close-on-click="false"
            >
              <.icon name="lock" class="size-3.5 opacity-60" />
              <span class="flex-1 text-sm">{dgettext("sheets", "Constant")}</span>
              <.icon
                :if={@column.is_constant}
                name="check"
                class="size-3.5 opacity-60"
              />
            </button>
          </li>

          <%!-- Required toggle (compact single-line) --%>
          <li>
            <button
              type="button"
              data-event="toggle_table_column_required"
              data-params={Jason.encode!(%{"column-id" => @column.id})}
              data-close-on-click="false"
            >
              <.icon name="asterisk" class="size-3.5 opacity-60" />
              <span class="flex-1 text-sm">{dgettext("sheets", "Required")}</span>
              <.icon
                :if={@column.required}
                name="check"
                class="size-3.5 opacity-60"
              />
            </button>
          </li>

          <%!-- Separator --%>
          <div class="my-1 border-t border-base-300"></div>

          <%!-- Change type → slides to type panel --%>
          <li>
            <button type="button" data-navigate="type">
              <.icon name="arrow-left-right" class="size-3.5 opacity-60" />
              <span class="flex-1 text-sm">{dgettext("sheets", "Change type")}</span>
              <.icon name="chevron-right" class="size-3.5 opacity-40" />
            </button>
          </li>

          <%!-- Options → slides to options panel (only for select types) --%>
          <li :if={@column.type in ["select", "multi_select"]}>
            <button type="button" data-navigate="options">
              <.icon name="settings" class="size-3.5 opacity-60" />
              <span class="flex-1 text-sm">{dgettext("sheets", "Options")}</span>
              <.icon name="chevron-right" class="size-3.5 opacity-40" />
            </button>
          </li>

          <%!-- Settings → slides to reference-settings panel (only for reference type) --%>
          <li :if={@column.type == "reference"}>
            <button type="button" data-navigate="reference-settings">
              <.icon name="settings" class="size-3.5 opacity-60" />
              <span class="flex-1 text-sm">{dgettext("sheets", "Settings")}</span>
              <.icon name="chevron-right" class="size-3.5 opacity-40" />
            </button>
          </li>

          <%!-- Separator + Delete --%>
          <div class="my-1 border-t border-base-300"></div>

          <li>
            <button
              disabled={length(@columns) <= 1}
              data-event="delete_table_column"
              data-params={Jason.encode!(%{"column-id" => @column.id})}
              class="text-error disabled:opacity-30"
            >
              <.icon name="trash-2" class="size-3.5" />
              <span class="text-sm">{dgettext("sheets", "Delete column")}</span>
            </button>
          </li>
        </ul>
      </div>

      <%!-- ========== Type Panel ========== --%>
      <div class="col-dropdown-panel" data-panel="type">
        <ul class="menu p-0">
          <%!-- Back button header --%>
          <li class="mb-1">
            <button type="button" data-back class="text-xs font-medium opacity-70">
              <.icon name="arrow-left" class="size-3.5" />
              <span>{dgettext("sheets", "Change type")}</span>
            </button>
          </li>

          <div class="border-t border-base-300 mb-1"></div>

          <%!-- Type list --%>
          <li :for={type <- ~w(number text boolean select multi_select date reference)}>
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
              <span class="flex-1 text-sm">{type_label(type)}</span>
              <.icon
                :if={@column.type == type}
                name="check"
                class="size-3.5 opacity-60"
              />
            </button>
          </li>
        </ul>
      </div>

      <%!-- ========== Options Panel ========== --%>
      <div class="col-dropdown-panel" data-panel="options">
        <ul class="menu p-0">
          <%!-- Back button header --%>
          <li class="mb-1">
            <button type="button" data-back class="text-xs font-medium opacity-70">
              <.icon name="arrow-left" class="size-3.5" />
              <span>{dgettext("sheets", "Options")}</span>
            </button>
          </li>

          <div class="border-t border-base-300 mb-1"></div>
        </ul>

        <%!-- Option inputs --%>
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

      <%!-- ========== Reference Settings Panel ========== --%>
      <div class="col-dropdown-panel" data-panel="reference-settings">
        <ul class="menu p-0">
          <li class="mb-1">
            <button type="button" data-back class="text-xs font-medium opacity-70">
              <.icon name="arrow-left" class="size-3.5" />
              <span>{dgettext("sheets", "Settings")}</span>
            </button>
          </li>
          <div class="border-t border-base-300 mb-1"></div>
          <li>
            <button
              type="button"
              data-event="toggle_reference_multiple"
              data-params={Jason.encode!(%{"column-id" => @column.id})}
              data-close-on-click="false"
            >
              <.icon name="layers" class="size-3.5 opacity-60" />
              <span class="flex-1 text-sm">{dgettext("sheets", "Allow multiple")}</span>
              <.icon
                :if={@column.config["multiple"]}
                name="check"
                class="size-3.5 opacity-60"
              />
            </button>
          </li>
        </ul>
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
          class="absolute inset-0 px-2 text-sm bg-transparent border-0 rounded-none outline-none focus:outline-none"
          phx-blur="update_table_cell"
          phx-value-row-id={@row.id}
          phx-value-column-slug={@column.slug}
          phx-target={@target}
        />
      <% "text" -> %>
        <input
          type="text"
          value={@value}
          class="absolute inset-0 px-2 text-sm bg-transparent border-0 rounded-none outline-none focus:outline-none"
          phx-blur="update_table_cell"
          phx-value-row-id={@row.id}
          phx-value-column-slug={@column.slug}
          phx-target={@target}
        />
      <% "boolean" -> %>
        <label class="absolute inset-0 flex items-center justify-center cursor-pointer">
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
          class="absolute inset-0"
        >
          <button
            type="button"
            data-role="trigger"
            class="flex items-center gap-1 w-full h-full px-2 text-sm text-left cursor-pointer hover:bg-base-200/50"
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
          class="absolute inset-0"
        >
          <button
            type="button"
            data-role="trigger"
            class="flex items-center gap-1 w-full h-full px-2 text-sm text-left cursor-pointer hover:bg-base-200/50"
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
      <% "reference" -> %>
        <% is_multi = @column.config["multiple"] == true %>
        <% options = @reference_options %>
        <%= if is_multi do %>
          <% selected_labels = resolve_multi_select_labels(@value, options) %>
          <div
            phx-hook="TableCellSelect"
            id={"table-cell-select-#{@row.id}-#{@column.slug}"}
            data-mode="multi_select"
            class="absolute inset-0"
          >
            <button
              type="button"
              data-role="trigger"
              class="flex items-center gap-1 w-full h-full px-2 text-sm text-left cursor-pointer hover:bg-base-200/50"
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
              <div
                data-role="empty"
                style="display:none"
                class="px-3 py-2 text-xs text-base-content/40"
              >
                {dgettext("sheets", "No matches")}
              </div>
            </template>
          </div>
        <% else %>
          <% selected_label = find_option_label(options, @value) %>
          <div
            phx-hook="TableCellSelect"
            id={"table-cell-select-#{@row.id}-#{@column.slug}"}
            data-mode="select"
            class="absolute inset-0"
          >
            <button
              type="button"
              data-role="trigger"
              class="flex items-center gap-1 w-full h-full px-2 text-sm text-left cursor-pointer hover:bg-base-200/50"
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
              <div
                data-role="empty"
                style="display:none"
                class="px-3 py-2 text-xs text-base-content/40"
              >
                {dgettext("sheets", "No matches")}
              </div>
            </template>
          </div>
        <% end %>
      <% "date" -> %>
        <input
          type="date"
          value={@value}
          class="absolute inset-0 px-2 text-sm bg-transparent border-0 rounded-none outline-none focus:outline-none"
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
      <% "reference" -> %>
        <% is_multi = @column.config["multiple"] == true %>
        <% options = @reference_options %>
        <%= if is_multi do %>
          <.reference_badges value={@value} options={options} />
        <% else %>
          <span class={["text-sm", is_nil(@value) && "text-base-content/40"]}>
            {find_option_label(options, @value) || "\u2014"}
          </span>
        <% end %>
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

  defp reference_badges(assigns) do
    values = assigns.value || []
    options = assigns.options || []

    labels =
      Enum.map(List.wrap(values), fn key ->
        find_option_label(options, key) || key
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
    option_map = Map.new(options, fn opt -> {opt["key"], opt["value"]} end)
    Enum.map(keys, fn key -> Map.get(option_map, key, key) end)
  end

  defp resolve_multi_select_labels(_value, _options), do: []

  defp column_width(col) do
    (col.config || %{})["width"] || 150
  end

  defp column_state_hash(col) do
    :erlang.phash2({col.type, col.is_constant, col.required, col.config})
  end

  defp type_icon("number"), do: "hash"
  defp type_icon("text"), do: "type"
  defp type_icon("boolean"), do: "toggle-left"
  defp type_icon("select"), do: "circle-dot"
  defp type_icon("multi_select"), do: "list"
  defp type_icon("date"), do: "calendar"
  defp type_icon("reference"), do: "link"
  defp type_icon(_), do: "columns-2"

  defp type_label("number"), do: dgettext("sheets", "Number")
  defp type_label("text"), do: dgettext("sheets", "Text")
  defp type_label("boolean"), do: dgettext("sheets", "Boolean")
  defp type_label("select"), do: dgettext("sheets", "Select")
  defp type_label("multi_select"), do: dgettext("sheets", "Multi Select")
  defp type_label("date"), do: dgettext("sheets", "Date")
  defp type_label("reference"), do: dgettext("sheets", "Reference")
  defp type_label(type), do: type
end
