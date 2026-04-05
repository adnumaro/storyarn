defmodule StoryarnWeb.Components.SaveIndicator do
  @moduledoc """
  A shared save indicator component for showing save status (saving/saved/idle).

  Supports two variants:
  - `:inline` - Simple inline indicator (used in flow editor header)
  - `:floating` - Absolute positioned with background (used in sheet editor)
  """

  use Phoenix.Component
  use Gettext, backend: Storyarn.Gettext

  import StoryarnWeb.Components.CoreComponents, only: [icon: 1]

  @doc """
  Renders a save status indicator.

  ## Attributes

  * `:status` - Required. The save status atom (`:idle`, `:saving`, `:saved`)
  * `:variant` - Optional. Display variant (`:inline` or `:floating`). Defaults to `:inline`

  ## Examples

      <.save_indicator status={@save_status} />
      <.save_indicator status={@save_status} variant={:floating} />
  """
  attr :status, :atom, required: true
  attr :variant, :atom, default: :inline, values: [:inline, :floating]

  def save_indicator(assigns) do
    ~H"""
    <%= case @variant do %>
      <% :inline -> %>
        <div :if={@status != :idle} class="flex items-center gap-2 text-sm">
          <span
            :if={@status == :saving}
            class="border-2 border-muted-foreground/20 border-t-muted-foreground/60 rounded-full animate-spin loading-xs"
          >
          </span>
          <.icon
            :if={@status == :saved}
            name="check"
            class="size-4 text-green-600 dark:text-green-400"
          />
          <span :if={@status == :saving} class="text-muted-foreground">{gettext("Saving...")}</span>
          <span :if={@status == :saved} class="text-green-600 dark:text-green-400">
            {gettext("Saved")}
          </span>
        </div>
      <% :floating -> %>
        <div
          :if={@status != :idle}
          class="absolute top-2 right-0 z-10 animate-in fade-in duration-300"
        >
          <div class={[
            "flex items-center gap-2 px-3 py-1.5 rounded-lg text-sm font-medium",
            @status == :saving && "bg-muted text-foreground",
            @status == :saved && "bg-success/10 text-green-600 dark:text-green-400"
          ]}>
            <span
              :if={@status == :saving}
              class="border-2 border-muted-foreground/20 border-t-muted-foreground/60 rounded-full animate-spin loading-xs"
            >
            </span>
            <.icon :if={@status == :saved} name="check" class="size-4" />
            <span :if={@status == :saving}>{gettext("Saving...")}</span>
            <span :if={@status == :saved}>{gettext("Saved")}</span>
          </div>
        </div>
    <% end %>
    """
  end
end
