defmodule StoryarnWeb.Components.BlockComponents.TableBlocks do
  @moduledoc false

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.Components.CoreComponents, only: [block_label: 1, icon: 1]

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
              <th class="font-medium text-base-content/60 w-32"></th>
              <th :for={col <- @columns} class="font-medium text-base-content/70">
                {col.name}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr :for={row <- @rows} class="even:bg-base-200/30">
              <td class="sticky left-0 z-10 bg-base-100 font-medium text-base-content/60 text-sm border-r border-base-300">
                {row.name}
              </td>
              <td :for={col <- @columns} class="p-1">
                <.table_cell
                  column={col}
                  row={row}
                  value={row.cells[col.slug]}
                  can_edit={@can_edit}
                  target={@target}
                />
              </td>
            </tr>
          </tbody>
        </table>
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
end
