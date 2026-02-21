defmodule StoryarnWeb.Components.BlockComponents.TableBlocks do
  @moduledoc false

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.Components.CoreComponents,
    only: [block_label: 1, icon: 1, confirm_modal: 1, show_modal: 2]

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
      <div class="overflow-x-auto border border-base-300 rounded-lg">
        <table class="table table-sm w-full">
          <thead>
            <tr class="bg-base-200">
              <%!-- Row label header (wider when editable for drag handle) --%>
              <th class={["font-medium text-base-content/60", (@can_edit && "w-40") || "w-32"]}></th>

              <%!-- Column headers --%>
              <th :for={col <- @columns} class="font-medium text-base-content/70">
                <%!-- Editable: dropdown with management options --%>
                <div :if={@can_edit} class="dropdown dropdown-end">
                  <div
                    tabindex="0"
                    role="button"
                    class="flex items-center gap-1 cursor-pointer hover:text-base-content"
                  >
                    {col.name}
                    <.icon name="chevron-down" class="size-3 opacity-40" />
                  </div>
                  <.column_dropdown column={col} columns={@columns} block={@block} target={@target} />
                </div>
                <%!-- Read-only: plain text --%>
                <span :if={!@can_edit}>{col.name}</span>
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
            <tr :for={row <- @rows} data-row-id={row.id} class="group/row even:bg-base-200/30">
              <%!-- Row label cell --%>
              <td class="sticky left-0 z-10 bg-base-100 font-medium text-base-content/60 text-sm border-r border-base-300">
                <div :if={@can_edit} class="flex items-center gap-1">
                  <.icon
                    name="grip-vertical"
                    class="size-3 opacity-30 cursor-grab row-drag-handle shrink-0"
                  />
                  <input
                    type="text"
                    value={row.name}
                    class="input input-ghost input-sm w-full px-1 font-medium"
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
              <td :for={col <- @columns} class="p-1">
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
                <div class="dropdown dropdown-end">
                  <button
                    tabindex="0"
                    class="btn btn-ghost btn-xs opacity-0 group-hover/row:opacity-100"
                  >
                    <.icon name="more-vertical" class="size-3" />
                  </button>
                  <ul
                    tabindex="0"
                    class="dropdown-content z-50 menu p-2 shadow-lg bg-base-200 rounded-box w-44"
                  >
                    <li>
                      <button
                        disabled={length(@rows) <= 1}
                        phx-click={
                          JS.push("prepare_delete_row",
                            value: %{"row-id" => row.id},
                            target: @target
                          )
                          |> show_modal("table-delete-row-#{@block.id}")
                        }
                        class="text-error disabled:opacity-30"
                      >
                        <.icon name="trash-2" class="size-3" />
                        {dgettext("sheets", "Delete")}
                      </button>
                    </li>
                  </ul>
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
        id={"table-type-confirm-#{@block.id}"}
        title={dgettext("sheets", "Change column type?")}
        message={
          dgettext(
            "sheets",
            "All cell values in this column will be reset. This cannot be undone."
          )
        }
        confirm_text={dgettext("sheets", "Change type")}
        confirm_variant="warning"
        icon="alert-triangle"
        icon_class="text-warning"
        on_confirm={JS.push("execute_column_type_change", target: @target)}
        on_cancel={JS.push("cancel_table_confirm", target: @target)}
      />

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

  defp column_dropdown(assigns) do
    ~H"""
    <ul tabindex="0" class="dropdown-content z-50 menu p-3 shadow-lg bg-base-200 rounded-box w-56">
      <%!-- Rename input --%>
      <li class="mb-2">
        <input
          type="text"
          value={@column.name}
          class="input input-bordered input-sm w-full"
          phx-blur="rename_table_column"
          phx-keydown="rename_table_column"
          phx-key="Enter"
          phx-value-column-id={@column.id}
          phx-target={@target}
        />
      </li>

      <%!-- Type radios --%>
      <li class="menu-title text-xs">{dgettext("sheets", "Type")}</li>
      <li :for={type <- ~w(number text boolean select multi_select date)}>
        <label class="flex items-center gap-2">
          <input
            type="radio"
            name={"col-type-#{@column.id}"}
            value={type}
            checked={@column.type == type}
            phx-click={
              if @column.type != type,
                do:
                  JS.push("prepare_column_type_change",
                    value: %{"column-id" => @column.id, "new-type" => type},
                    target: @target
                  )
                  |> show_modal("table-type-confirm-#{@block.id}"),
                else: %JS{}
            }
            class="radio radio-xs"
          />
          <span class="text-sm">{type_label(type)}</span>
        </label>
      </li>

      <%!-- Options management for select/multi_select --%>
      <.column_options_section
        :if={@column.type in ["select", "multi_select"]}
        column={@column}
        target={@target}
      />

      <%!-- Constant checkbox --%>
      <li class="mt-2 border-t border-base-300 pt-2">
        <label class="flex items-center gap-2">
          <input
            type="checkbox"
            checked={@column.is_constant}
            class="checkbox checkbox-xs"
            phx-click="toggle_table_column_constant"
            phx-value-column-id={@column.id}
            phx-target={@target}
          />
          <div>
            <span class="text-sm">{dgettext("sheets", "Constant")}</span>
            <span class="text-xs text-base-content/50 block">
              {dgettext("sheets", "Won't generate a variable")}
            </span>
          </div>
        </label>
      </li>

      <%!-- Delete column --%>
      <li class="mt-2 border-t border-base-300 pt-2">
        <button
          disabled={length(@columns) <= 1}
          phx-click={
            JS.push("prepare_delete_column",
              value: %{"column-id" => @column.id},
              target: @target
            )
            |> show_modal("table-delete-col-#{@block.id}")
          }
          class="text-error disabled:opacity-30"
        >
          <.icon name="trash-2" class="size-3" />
          {dgettext("sheets", "Delete column")}
        </button>
      </li>
    </ul>
    """
  end

  # =============================================================================
  # Select Options Section (in column dropdown)
  # =============================================================================

  defp column_options_section(assigns) do
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
          value={opt["value"]}
          class="input input-bordered input-xs flex-1"
          phx-blur="update_table_column_option"
          phx-value-column-id={@column.id}
          phx-value-index={idx}
          phx-target={@target}
        />
        <button
          type="button"
          phx-click="remove_table_column_option"
          phx-value-column-id={@column.id}
          phx-value-key={opt["key"]}
          phx-target={@target}
          class="btn btn-ghost btn-xs btn-circle"
        >
          <.icon name="x" class="size-3" />
        </button>
      </div>
      <div class="px-1">
        <input
          type="text"
          placeholder={dgettext("sheets", "+ Add option")}
          class="input input-bordered input-xs w-full"
          phx-keydown="add_table_column_option_keydown"
          phx-key="Enter"
          phx-value-column-id={@column.id}
          phx-target={@target}
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
          class="input input-bordered input-sm w-full"
          phx-blur="update_table_cell"
          phx-value-row-id={@row.id}
          phx-value-column-slug={@column.slug}
          phx-target={@target}
        />
      <% "text" -> %>
        <input
          type="text"
          value={@value}
          class="input input-bordered input-sm w-full"
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
            class="checkbox checkbox-sm checkbox-primary"
            phx-click="toggle_table_cell_boolean"
            phx-value-row-id={@row.id}
            phx-value-column-slug={@column.slug}
            phx-target={@target}
          />
        </label>
      <% "select" -> %>
        <% options = @column.config["options"] || [] %>
        <select
          class="select select-bordered select-sm w-full"
          phx-change="update_table_cell"
          phx-value-row-id={@row.id}
          phx-value-column-slug={@column.slug}
          phx-target={@target}
        >
          <option value="">{dgettext("sheets", "Select...")}</option>
          <option :for={opt <- options} value={opt["key"]} selected={@value == opt["key"]}>
            {opt["value"]}
          </option>
        </select>
      <% "multi_select" -> %>
        <input
          type="text"
          value={format_multi_select(@value)}
          class="input input-bordered input-sm w-full"
          placeholder={dgettext("sheets", "comma-separated")}
          phx-blur="update_table_cell"
          phx-value-row-id={@row.id}
          phx-value-column-slug={@column.slug}
          phx-value-type="multi_select"
          phx-target={@target}
        />
      <% "date" -> %>
        <input
          type="date"
          value={@value}
          class="input input-bordered input-sm w-full"
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

  defp format_multi_select(nil), do: ""
  defp format_multi_select(values) when is_list(values), do: Enum.join(values, ", ")
  defp format_multi_select(_), do: ""

  defp type_label("number"), do: dgettext("sheets", "Number")
  defp type_label("text"), do: dgettext("sheets", "Text")
  defp type_label("boolean"), do: dgettext("sheets", "Boolean")
  defp type_label("select"), do: dgettext("sheets", "Select")
  defp type_label("multi_select"), do: dgettext("sheets", "Multi Select")
  defp type_label("date"), do: dgettext("sheets", "Date")
  defp type_label(type), do: type
end
