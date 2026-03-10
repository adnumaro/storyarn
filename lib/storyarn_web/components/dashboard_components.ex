defmodule StoryarnWeb.Components.DashboardComponents do
  @moduledoc """
  Reusable dashboard components for project and tool dashboards.

  Provides stat cards, ranked lists, issue lists, and progress rows.
  Import only in LiveViews that use dashboards — not auto-imported.
  """

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.Components.CoreComponents, only: [icon: 1]

  # ===========================================================================
  # Stat Card
  # ===========================================================================

  @doc """
  Renders a clickable stat card with icon, label, and value.

  ## Examples

      <.stat_card icon="file-text" label="Sheets" value={42} href="/sheets" />
  """
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :value, :integer, required: true
  attr :href, :string, default: nil

  def stat_card(assigns) do
    ~H"""
    <.link :if={@href} navigate={@href} class="group h-full">
      <div class="card bg-base-200/50 p-4 h-full hover:bg-base-200 transition-colors cursor-pointer">
        <div class="flex items-start gap-3">
          <div class="rounded-lg bg-primary/10 p-2">
            <.icon name={@icon} class="size-5 text-primary" />
          </div>
          <div>
            <p class="text-2xl font-bold">{@value}</p>
            <p class="text-sm text-base-content/60">{@label}</p>
          </div>
        </div>
      </div>
    </.link>
    <div :if={!@href} class="card bg-base-200/50 p-4 h-full">
      <div class="flex items-center gap-3">
        <div class="rounded-lg bg-primary/10 p-2">
          <.icon name={@icon} class="size-5 text-primary" />
        </div>
        <div>
          <p class="text-2xl font-bold">{@value}</p>
          <p class="text-sm text-base-content/60">{@label}</p>
        </div>
      </div>
    </div>
    """
  end

  # ===========================================================================
  # Ranked List
  # ===========================================================================

  @doc """
  Renders a ranked list with bar visualization.

  Each item needs `:label`, `:value`, and optionally `:href`.
  The bar width is proportional to the max value in the list.

  ## Examples

      <.ranked_list items={[%{label: "Character A", value: 42, href: "/sheets/1"}]} />
  """
  attr :items, :list, required: true
  attr :title, :string, default: nil
  attr :empty_message, :string, default: nil

  def ranked_list(assigns) do
    max_value = assigns.items |> Enum.map(& &1.value) |> Enum.max(fn -> 1 end)
    assigns = assign(assigns, :max_value, max_value)

    ~H"""
    <div class="space-y-1">
      <h3 :if={@title} class="text-sm font-medium text-base-content/70 mb-3">{@title}</h3>
      <p :if={@items == [] && @empty_message} class="text-sm text-base-content/50 py-4 text-center">
        {@empty_message}
      </p>
      <div :for={item <- @items} class="flex items-center gap-3 py-1.5">
        <div class="flex-1 min-w-0">
          <.link
            :if={Map.get(item, :href)}
            navigate={item.href}
            class="text-sm hover:underline truncate block"
          >
            {item.label}
          </.link>
          <span :if={!Map.get(item, :href)} class="text-sm truncate block">{item.label}</span>
        </div>
        <div class="w-32 flex items-center gap-2">
          <div class="flex-1 bg-base-300 rounded-full h-2">
            <div
              class="bg-primary rounded-full h-2 transition-all"
              style={"width: #{round(item.value / @max_value * 100)}%"}
            >
            </div>
          </div>
          <span class="text-xs text-base-content/60 w-8 text-right tabular-nums">{item.value}</span>
        </div>
      </div>
    </div>
    """
  end

  # ===========================================================================
  # Issue List
  # ===========================================================================

  @doc """
  Renders a list of issues with severity badges and links.

  Each issue needs `:severity` (:error | :warning | :info), `:message`, and `:href`.

  ## Examples

      <.issue_list issues={[%{severity: :error, message: "Flow has no entry", href: "/flows/1"}]} />
  """
  attr :issues, :list, required: true
  attr :title, :string, default: nil
  attr :empty_message, :string, default: nil

  def issue_list(assigns) do
    ~H"""
    <div class="space-y-1">
      <h3 :if={@title} class="text-sm font-medium text-base-content/70 mb-3">{@title}</h3>
      <p :if={@issues == [] && @empty_message} class="text-sm text-base-content/50 py-4 text-center">
        {@empty_message}
      </p>
      <.link
        :for={issue <- @issues}
        navigate={issue.href}
        class="flex items-center gap-3 py-2 px-3 rounded-lg hover:bg-base-200 transition-colors group"
      >
        <span class={[
          "badge badge-sm",
          issue.severity == :error && "badge-error",
          issue.severity == :warning && "badge-warning",
          issue.severity == :info && "badge-info"
        ]}>
          {severity_label(issue.severity)}
        </span>
        <span class="text-sm flex-1">{issue.message}</span>
        <.icon
          name="arrow-right"
          class="size-4 text-base-content/30 group-hover:text-base-content/60 transition-colors"
        />
      </.link>
    </div>
    """
  end

  defp severity_label(:error), do: gettext("Error")
  defp severity_label(:warning), do: gettext("Warning")
  defp severity_label(:info), do: gettext("Info")

  # ===========================================================================
  # Progress Row
  # ===========================================================================

  @doc """
  Renders a progress bar with label and percentage.

  ## Examples

      <.progress_row label="Spanish" percentage={65.0} detail="130 / 200 texts" />
  """
  attr :label, :string, required: true
  attr :percentage, :float, required: true
  attr :detail, :string, default: nil
  attr :href, :string, default: nil

  def progress_row(assigns) do
    ~H"""
    <div class="flex items-center gap-3 py-1.5">
      <div class="w-24">
        <.link :if={@href} navigate={@href} class="text-sm hover:underline">{@label}</.link>
        <span :if={!@href} class="text-sm">{@label}</span>
      </div>
      <div class="flex-1 bg-base-300 rounded-full h-2.5">
        <div
          class={[
            "rounded-full h-2.5 transition-all",
            @percentage == 100.0 && "bg-success",
            @percentage >= 50.0 && @percentage < 100.0 && "bg-primary",
            @percentage < 50.0 && "bg-warning"
          ]}
          style={"width: #{round(@percentage)}%"}
        >
        </div>
      </div>
      <span class="text-xs text-base-content/60 w-12 text-right tabular-nums">
        {round(@percentage)}%
      </span>
      <span :if={@detail} class="text-xs text-base-content/40 w-24 text-right">
        {@detail}
      </span>
    </div>
    """
  end

  # ===========================================================================
  # Dashboard Section
  # ===========================================================================

  @doc """
  Renders a dashboard section with a title and content.
  """
  attr :title, :string, required: true
  attr :class, :string, default: nil
  slot :inner_block, required: true

  def dashboard_section(assigns) do
    ~H"""
    <section class={["card bg-base-100 border border-base-300 p-5", @class]}>
      <h2 class="text-base font-semibold mb-4">{@title}</h2>
      {render_slot(@inner_block)}
    </section>
    """
  end

  # ===========================================================================
  # Table Wrapper
  # ===========================================================================

  @doc """
  Wraps a dashboard table with max height, vertical scroll, and horizontal scroll.
  The thead stays sticky at the top.
  """
  slot :inner_block, required: true

  def dashboard_table_wrapper(assigns) do
    ~H"""
    <div class="overflow-auto max-h-[32rem] -mx-5">
      {render_slot(@inner_block)}
    </div>
    """
  end

  # ===========================================================================
  # Sort Indicator
  # ===========================================================================

  @doc "Renders an up/down chevron when the column matches the current sort."
  attr :column, :string, required: true
  attr :sort_by, :string, required: true
  attr :sort_dir, :atom, required: true

  def sort_indicator(assigns) do
    ~H"""
    <.icon
      :if={@sort_by == @column}
      name={if @sort_dir == :asc, do: "chevron-up", else: "chevron-down"}
      class="size-3"
    />
    """
  end

  # ===========================================================================
  # Pagination
  # ===========================================================================

  @default_per_page 25

  @doc "Default rows per page for dashboard tables."
  def default_per_page, do: @default_per_page

  @doc """
  Paginates a list of rows in-memory. Returns `{page_rows, total_pages}`.

  ## Examples

      {rows, total_pages} = paginate(all_rows, page, per_page)
  """
  def paginate(rows, page, per_page \\ @default_per_page) do
    total = length(rows)
    total_pages = max(ceil(total / per_page), 1)
    page = clamp(page, 1, total_pages)

    page_rows =
      rows
      |> Enum.drop((page - 1) * per_page)
      |> Enum.take(per_page)

    {page_rows, total_pages}
  end

  defp clamp(val, min, _max) when val < min, do: min
  defp clamp(val, _min, max) when val > max, do: max
  defp clamp(val, _min, _max), do: val

  @doc """
  Renders pagination controls (prev/next + page info).

  Emits the `event` with `%{"page" => page}` on click.
  """
  attr :page, :integer, required: true
  attr :total_pages, :integer, required: true
  attr :total, :integer, required: true
  attr :event, :string, required: true

  def pagination(assigns) do
    ~H"""
    <div :if={@total_pages > 1} class="flex items-center justify-between pt-3 px-1">
      <span class="text-xs text-base-content/50">
        {gettext("%{total} items", total: @total)}
      </span>
      <div class="flex items-center gap-1">
        <button
          type="button"
          phx-click={@event}
          phx-value-page={@page - 1}
          disabled={@page <= 1}
          class="btn btn-ghost btn-xs btn-square"
        >
          <.icon name="chevron-left" class="size-4" />
        </button>
        <span class="text-xs text-base-content/60 px-2 tabular-nums">
          {@page} / {@total_pages}
        </span>
        <button
          type="button"
          phx-click={@event}
          phx-value-page={@page + 1}
          disabled={@page >= @total_pages}
          class="btn btn-ghost btn-xs btn-square"
        >
          <.icon name="chevron-right" class="size-4" />
        </button>
      </div>
    </div>
    """
  end

  # ===========================================================================
  # Shared Helpers
  # ===========================================================================

  @doc "Toggles sort direction when the same column is clicked; resets to :asc for a new column."
  def toggle_sort(column, current_by, current_dir) do
    if column == current_by do
      {column, if(current_dir == :asc, do: :desc, else: :asc)}
    else
      {column, :asc}
    end
  end

  @doc "Safely parses a page number from user input. Returns 1 for invalid input."
  def parse_page(page) when is_binary(page) do
    case Integer.parse(page) do
      {n, ""} -> n
      _ -> 1
    end
  end

  def parse_page(page) when is_integer(page), do: page
  def parse_page(_), do: 1

  # ===========================================================================
  # Time Formatting
  # ===========================================================================

  @doc "Formats a DateTime as a human-readable relative time string."
  def format_relative_time(datetime) do
    diff = DateTime.diff(DateTime.utc_now(), datetime, :second)

    cond do
      diff < 60 -> gettext("just now")
      diff < 3600 -> gettext("%{count}m ago", count: div(diff, 60))
      diff < 86_400 -> gettext("%{count}h ago", count: div(diff, 3600))
      diff < 604_800 -> gettext("%{count}d ago", count: div(diff, 86_400))
      true -> Calendar.strftime(datetime, "%b %d")
    end
  end
end
