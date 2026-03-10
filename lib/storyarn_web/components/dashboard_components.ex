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
end
