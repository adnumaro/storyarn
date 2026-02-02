defmodule StoryarnWeb.Components.SaveIndicator do
  @moduledoc """
  A shared save indicator component for showing save status (saving/saved/idle).

  Supports two variants:
  - `:inline` - Simple inline indicator (used in flow editor header)
  - `:floating` - Absolute positioned with background (used in page editor)
  """

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.CoreComponents, only: [icon: 1]

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
          <span :if={@status == :saving} class="loading loading-spinner loading-xs"></span>
          <.icon :if={@status == :saved} name="check" class="size-4 text-success" />
          <span :if={@status == :saving} class="text-base-content/70">{gettext("Saving...")}</span>
          <span :if={@status == :saved} class="text-success">{gettext("Saved")}</span>
        </div>
      <% :floating -> %>
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
    <% end %>
    """
  end
end
