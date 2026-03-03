defmodule StoryarnWeb.Components.ToolbarColorPicker do
  @moduledoc """
  Shared color swatch picker widget for canvas floating toolbars (flow, scene).

  Renders a trigger button that toggles a popover grid of color swatches via
  JS.toggle — no server round-trips for open/close. Suitable for any toolbar
  that is not inside an overflow:hidden container.

  Event format (both phx-click and phx-change):
    %{"field" => field, "value" => color_hex}
  """

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  alias Phoenix.LiveView.JS

  @color_swatches [
    ~w(#ef4444 #f97316 #f59e0b #eab308 #22c55e #14b8a6 #3b82f6 #6366f1 #8b5cf6 #a855f7 #ec4899 #000000),
    ~w(#fca5a5 #fdba74 #fde68a #a7f3d0 #a5f3fc #93c5fd #c4b5fd #e9d5ff #fbcfe8 #e5e7eb #ffffff)
  ]

  @doc "Returns the standard color swatch palette (list of rows)."
  def color_swatches, do: @color_swatches

  attr :id, :string, required: true
  attr :event, :string, required: true
  attr :element_id, :any, required: true
  attr :field, :string, required: true
  attr :value, :string, required: true
  attr :label, :string, required: true
  attr :disabled, :boolean, default: false

  slot :extra_content

  @doc "Color swatch picker trigger button + popover grid."
  def toolbar_color_picker(assigns) do
    assigns = assign(assigns, :swatches, @color_swatches)

    ~H"""
    <div class="relative">
      <button
        type="button"
        class="toolbar-btn"
        title={@label}
        disabled={@disabled}
        phx-click={JS.toggle(to: "#popover-color-#{@id}", display: "block")}
      >
        <span
          class="inline-block size-4 rounded-full border border-white/20"
          style={"background:#{@value}"}
        />
      </button>

      <div
        id={"popover-color-#{@id}"}
        class="toolbar-popover"
        style="display:none"
        phx-click-away={JS.hide(to: "#popover-color-#{@id}")}
      >
        <div class="p-2">
          <div class="text-xs font-medium text-base-content/60 mb-1.5">{@label}</div>
          <.color_swatch_grid
            swatches={@swatches}
            event={@event}
            element_id={@element_id}
            field={@field}
            current_color={@value}
            picker_id={@id}
            popover_id={"popover-color-#{@id}"}
            disabled={@disabled}
          />
        </div>
        {render_slot(@extra_content)}
      </div>
    </div>
    """
  end

  attr :swatches, :list, required: true
  attr :event, :string, required: true
  attr :element_id, :any, required: true
  attr :field, :string, required: true
  attr :current_color, :string, required: true
  attr :picker_id, :string, required: true
  attr :popover_id, :string, default: nil
  attr :disabled, :boolean, default: false

  def color_swatch_grid(assigns) do
    ~H"""
    <div :for={{row, idx} <- Enum.with_index(@swatches)} class="flex gap-1 mb-1">
      <button
        :for={color <- row}
        type="button"
        phx-click={
          js = JS.push(@event, value: %{id: @element_id, field: @field, value: color})
          if @popover_id, do: JS.hide(js, to: "##{@popover_id}"), else: js
        }
        class={"color-swatch #{if color == @current_color, do: "color-swatch-active"}"}
        style={"background:#{color}"}
        title={color}
        disabled={@disabled}
      />
      <%!-- Native color input at end of last row for custom colors --%>
      <form :if={idx == length(@swatches) - 1} phx-change={@event} phx-submit="noop" class="contents">
        <input type="hidden" name="element_id" value={@element_id} />
        <input type="hidden" name="field" value={@field} />
        <label
          for={"color-native-#{@picker_id}"}
          class="color-swatch color-swatch-rainbow"
          title={gettext("Custom")}
        >
          <input
            type="color"
            id={"color-native-#{@picker_id}"}
            name="value"
            value={@current_color}
            class="sr-only"
            disabled={@disabled}
          />
        </label>
      </form>
    </div>
    """
  end
end
