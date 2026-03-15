defmodule StoryarnWeb.SceneLive.Components.ToolbarWidgets do
  @moduledoc """
  Shared widget components for the floating map toolbar.

  Each widget is a compact button that optionally opens a popover.
  Popovers toggle via JS.toggle — zero server round-trips for open/close.
  """

  use Phoenix.Component
  use Gettext, backend: Storyarn.Gettext

  alias Phoenix.LiveView.JS

  import StoryarnWeb.Components.CoreComponents
  import StoryarnWeb.Components.ToolbarColorPicker
  import StoryarnWeb.SceneLive.Helpers.SceneHelpers, only: [flatten_sheets: 1]

  # ---------------------------------------------------------------------------
  # Stroke Picker (style + width + color in one popover — for zones & connections)
  # ---------------------------------------------------------------------------

  attr :id, :string, required: true
  attr :event, :string, required: true
  attr :element_id, :any, required: true
  attr :current_style, :string, default: "solid"
  attr :current_color, :string, default: "#1e40af"
  attr :current_width, :integer, default: 2
  attr :style_field, :string, default: "border_style"
  attr :color_field, :string, default: "border_color"
  attr :width_field, :string, default: "border_width"
  attr :label, :string, default: "Border"
  attr :disabled, :boolean, default: false

  @doc "Border style/color/width picker with popover."
  def toolbar_stroke_picker(assigns) do
    assigns = assign(assigns, :swatches, color_swatches())

    ~H"""
    <div class="relative">
      <button
        type="button"
        class="toolbar-btn"
        title={@label}
        disabled={@disabled}
        phx-click={JS.toggle(to: "#popover-stroke-#{@id}", display: "block")}
      >
        <span class="flex items-center gap-1">
          <svg width="16" height="16" viewBox="0 0 16 16" class="text-current">
            <line
              x1="2"
              y1="8"
              x2="14"
              y2="8"
              stroke="currentColor"
              stroke-width="2"
              stroke-dasharray={border_dash(@current_style)}
            />
          </svg>
          <span
            class="inline-block w-2.5 h-2.5 rounded-full shrink-0"
            style={"background:#{@current_color}"}
          />
        </span>
      </button>

      <div
        id={"popover-stroke-#{@id}"}
        class="toolbar-popover"
        style="display:none"
        phx-click-away={JS.hide(to: "#popover-stroke-#{@id}")}
      >
        <div class="p-2 space-y-3">
          <%!-- Style + Width on same row --%>
          <div class="flex items-end gap-4">
            <div>
              <div class="text-xs font-medium text-base-content/60 mb-1.5">
                {dgettext("scenes", "Style")}
              </div>
              <div class="flex gap-1">
                <button
                  :for={style <- ~w(solid dashed dotted)}
                  type="button"
                  phx-click={
                    JS.push(@event, value: %{id: @element_id, field: @style_field, value: style})
                  }
                  class={"toolbar-btn h-7 w-10 #{if style == @current_style, do: "toolbar-btn-active"}"}
                  disabled={@disabled}
                >
                  <svg width="24" height="8" viewBox="0 0 24 8" class="text-current">
                    <line
                      x1="0"
                      y1="4"
                      x2="24"
                      y2="4"
                      stroke="currentColor"
                      stroke-width="2"
                      stroke-dasharray={border_dash(style)}
                    />
                  </svg>
                </button>
              </div>
            </div>
            <div>
              <div class="text-xs font-medium text-base-content/60 mb-1.5">
                {dgettext("scenes", "Width")}
              </div>
              <div class="flex items-center gap-2">
                <button
                  type="button"
                  phx-click={
                    JS.push(@event,
                      value: %{
                        id: @element_id,
                        field: @width_field,
                        value: max(@current_width - 1, 0)
                      }
                    )
                  }
                  class="toolbar-btn h-6 w-6 text-xs"
                  disabled={@disabled || @current_width <= 0}
                >
                  &minus;
                </button>
                <span class="text-sm font-mono w-6 text-center">{@current_width}</span>
                <button
                  type="button"
                  phx-click={
                    JS.push(@event,
                      value: %{
                        id: @element_id,
                        field: @width_field,
                        value: min(@current_width + 1, 10)
                      }
                    )
                  }
                  class="toolbar-btn h-6 w-6 text-xs"
                  disabled={@disabled || @current_width >= 10}
                >
                  +
                </button>
              </div>
            </div>
          </div>

          <%!-- Color --%>
          <div>
            <div class="text-xs font-medium text-base-content/60 mb-1.5">
              {dgettext("scenes", "Color")}
            </div>
            <.color_swatch_grid
              swatches={@swatches}
              event={@event}
              element_id={@element_id}
              field={@color_field}
              current_color={@current_color}
              picker_id={"stroke-#{@id}"}
              disabled={@disabled}
            />
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Opacity Slider (rendered inside fill color popover via :extra_content slot)
  # ---------------------------------------------------------------------------

  attr :event, :string, required: true
  attr :element_id, :any, required: true
  attr :value, :float, default: 0.3
  attr :disabled, :boolean, default: false

  @doc "Opacity slider (0.0-1.0) for zone/annotation transparency."
  def toolbar_opacity_slider(assigns) do
    ~H"""
    <div class="px-2 pb-2 pt-1 border-t border-base-300">
      <div class="text-xs font-medium text-base-content/60 mb-1">
        {dgettext("scenes", "Opacity")}
        <span class="text-base-content/40 ml-1">{format_opacity(@value)}</span>
      </div>
      <form phx-change={@event} phx-submit="noop">
        <input type="hidden" name="element_id" value={@element_id} />
        <input type="hidden" name="field" value="opacity" />
        <input
          type="range"
          min="0"
          max="1"
          step="0.05"
          value={@value}
          name="value"
          class="range range-xs w-full"
          disabled={@disabled}
        />
      </form>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Layer Picker
  # ---------------------------------------------------------------------------

  attr :id, :string, required: true
  attr :event, :string, required: true
  attr :element_id, :any, required: true
  attr :current_layer_id, :any, default: nil
  attr :layers, :list, default: []
  attr :disabled, :boolean, default: false

  @doc "Layer selector dropdown for moving elements between layers."
  def toolbar_layer_picker(assigns) do
    ~H"""
    <div class="relative">
      <button
        type="button"
        class="toolbar-btn"
        title={dgettext("scenes", "Layer")}
        disabled={@disabled}
        phx-click={JS.toggle(to: "#popover-layer-#{@id}", display: "block")}
      >
        <.icon name="layers" class="size-3.5" />
      </button>

      <div
        id={"popover-layer-#{@id}"}
        class="toolbar-popover"
        style="display:none"
        phx-click-away={JS.hide(to: "#popover-layer-#{@id}")}
      >
        <div class="p-1 min-w-[140px]">
          <div class="text-xs font-medium text-base-content/60 px-2 py-1">
            {dgettext("scenes", "Layer")}
          </div>
          <button
            type="button"
            phx-click={
              JS.push(@event, value: %{id: @element_id, field: "layer_id", value: ""})
              |> JS.hide(to: "#popover-layer-#{@id}")
            }
            class={"flex items-center gap-2 w-full px-2 py-1 rounded text-sm cursor-pointer hover:bg-base-content/10 #{if is_nil(@current_layer_id), do: "font-semibold text-primary"}"}
            disabled={@disabled}
          >
            {dgettext("scenes", "None")}
          </button>
          <button
            :for={layer <- @layers}
            type="button"
            phx-click={
              JS.push(@event, value: %{id: @element_id, field: "layer_id", value: layer.id})
              |> JS.hide(to: "#popover-layer-#{@id}")
            }
            class={"flex items-center gap-2 w-full px-2 py-1 rounded text-sm cursor-pointer hover:bg-base-content/10 #{if layer.id == @current_layer_id, do: "font-semibold text-primary"}"}
            disabled={@disabled}
          >
            {layer.name}
          </button>
        </div>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Target Picker (link to sheet/flow/map/url)
  # ---------------------------------------------------------------------------

  attr :id, :string, required: true
  attr :event, :string, required: true
  attr :element_id, :any, required: true
  attr :current_type, :string, default: nil
  attr :current_target_id, :any, default: nil
  attr :target_types, :list, default: ~w(sheet flow map)
  attr :project_scenes, :list, default: []
  attr :project_sheets, :list, default: []
  attr :project_flows, :list, default: []
  attr :disabled, :boolean, default: false

  @doc "Target picker for linking pins to sheets, flows, or maps."
  def toolbar_target_picker(assigns) do
    ~H"""
    <div class="relative">
      <button
        type="button"
        class="toolbar-btn gap-1 px-2"
        title={dgettext("scenes", "Link to")}
        disabled={@disabled}
        phx-click={JS.toggle(to: "#popover-target-#{@id}", display: "block")}
      >
        <.icon name="link" class="size-3.5" />
        <span :if={@current_type} class="text-xs max-w-[60px] truncate">
          {target_display_name(
            @current_type,
            @current_target_id,
            @project_scenes,
            @project_sheets,
            @project_flows
          )}
        </span>
        <span :if={!@current_type} class="text-xs text-base-content/40">
          {dgettext("scenes", "No link")}
        </span>
      </button>

      <div
        id={"popover-target-#{@id}"}
        class="toolbar-popover w-56"
        style="display:none"
        phx-click-away={JS.hide(to: "#popover-target-#{@id}")}
      >
        <%!-- Step 1: Type buttons --%>
        <div id={"target-step1-#{@id}"} class="p-1">
          <div class="text-xs font-medium text-base-content/60 px-2 py-1">
            {dgettext("scenes", "Link to")}
          </div>

          <%!-- Clear link --%>
          <button
            :if={@current_type}
            type="button"
            phx-click={
              JS.push(@event, value: %{id: @element_id, field: "target_type", value: ""})
              |> JS.hide(to: "#popover-target-#{@id}")
            }
            class="flex items-center gap-2 w-full px-2 py-1 rounded text-sm cursor-pointer hover:bg-base-content/10 text-error"
            disabled={@disabled}
          >
            <.icon name="x" class="size-3" />
            {dgettext("scenes", "Remove link")}
          </button>

          <button
            :for={t <- @target_types}
            type="button"
            phx-click={
              if t == "url" do
                JS.push(@event, value: %{id: @element_id, field: "target_type", value: "url"})
                |> JS.hide(to: "#target-step1-#{@id}")
                |> JS.show(to: "#target-url-#{@id}")
              else
                JS.hide(to: "#target-step1-#{@id}")
                |> JS.show(to: "#target-list-#{@id}-#{t}")
              end
            }
            class={"flex items-center gap-2 w-full px-2 py-1.5 rounded text-sm cursor-pointer hover:bg-base-content/10 #{if t == @current_type, do: "font-semibold text-primary"}"}
            disabled={@disabled}
          >
            <.icon name={target_type_icon(t)} class="size-3.5" />
            {target_type_label(t)}
          </button>
        </div>

        <%!-- Step 2: Resource lists (one per type) --%>
        <div
          :for={t <- Enum.filter(@target_types, &(&1 != "url"))}
          id={"target-list-#{@id}-#{t}"}
          style="display:none"
          class="p-1"
        >
          <button
            type="button"
            phx-click={
              JS.hide(to: "#target-list-#{@id}-#{t}")
              |> JS.show(to: "#target-step1-#{@id}")
            }
            class="flex items-center gap-1 px-2 py-1 text-xs text-base-content/50 hover:text-base-content"
          >
            <.icon name="chevron-left" class="size-3" />
            {dgettext("scenes", "Back")}
          </button>

          <div class="max-h-48 overflow-y-auto">
            <button
              :for={item <- target_items(t, @project_scenes, @project_sheets, @project_flows)}
              type="button"
              phx-click={
                JS.push(@event,
                  value: %{
                    id: @element_id,
                    field: "target",
                    target_type: t,
                    target_id: item.id
                  }
                )
                |> JS.hide(to: "#popover-target-#{@id}")
                |> JS.show(to: "#target-step1-#{@id}")
                |> JS.hide(to: "#target-list-#{@id}-#{t}")
              }
              class={"flex items-center gap-2 w-full px-2 py-1 rounded text-sm cursor-pointer hover:bg-base-content/10 #{if item.id == @current_target_id, do: "font-semibold text-primary"}"}
              disabled={@disabled}
            >
              {item.name}
            </button>
          </div>
        </div>

        <%!-- Step 2: URL input --%>
        <div
          id={"target-url-#{@id}"}
          style="display:none"
          class="p-2"
        >
          <button
            type="button"
            phx-click={
              JS.hide(to: "#target-url-#{@id}")
              |> JS.show(to: "#target-step1-#{@id}")
            }
            class="flex items-center gap-1 mb-1 text-xs text-base-content/50 hover:text-base-content"
          >
            <.icon name="chevron-left" class="size-3" />
            {dgettext("scenes", "Back")}
          </button>
          <input
            type="url"
            value={if @current_type == "url", do: @current_target_id, else: ""}
            phx-blur={@event}
            phx-value-id={@element_id}
            phx-value-field="target_id"
            placeholder="https://..."
            class="input input-xs input-bordered w-full"
            disabled={@disabled}
          />
        </div>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Size Picker (dropdown selector)
  # ---------------------------------------------------------------------------

  attr :id, :string, required: true
  attr :event, :string, required: true
  attr :element_id, :any, required: true
  attr :field, :string, default: "size"
  attr :current, :string, default: "md"
  attr :disabled, :boolean, default: false

  @size_options [
    {"sm", "S"},
    {"md", "M"},
    {"lg", "L"}
  ]

  @doc "Size selector dropdown for pins and annotations."
  def toolbar_size_picker(assigns) do
    assigns =
      assigns
      |> assign(:options, @size_options)
      |> assign(:current_label, size_label(assigns.current))

    ~H"""
    <div class="relative">
      <button
        type="button"
        class="toolbar-btn gap-1 px-1.5"
        title={dgettext("scenes", "Size")}
        disabled={@disabled}
        phx-click={JS.toggle(to: "#popover-size-#{@id}", display: "block")}
      >
        <span class="text-xs font-medium">{@current_label}</span>
        <.icon name="chevron-down" class="size-2.5 opacity-50" />
      </button>

      <div
        id={"popover-size-#{@id}"}
        class="toolbar-popover"
        style="display:none"
        phx-click-away={JS.hide(to: "#popover-size-#{@id}")}
      >
        <div class="p-1 min-w-[120px]">
          <button
            :for={{value, short} <- @options}
            type="button"
            phx-click={
              JS.push(@event, value: %{id: @element_id, field: @field, value: value})
              |> JS.hide(to: "#popover-size-#{@id}")
            }
            class={"flex items-center gap-2 w-full px-2 py-1 rounded text-sm cursor-pointer hover:bg-base-content/10 #{if value == @current, do: "font-semibold text-primary"}"}
            disabled={@disabled}
          >
            {size_label(value)}
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp size_label("sm"), do: dgettext("scenes", "Small")
  defp size_label("md"), do: dgettext("scenes", "Medium")
  defp size_label("lg"), do: dgettext("scenes", "Large")
  defp size_label(_), do: dgettext("scenes", "Medium")

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp border_dash("solid"), do: "none"
  defp border_dash("dashed"), do: "6,3"
  defp border_dash("dotted"), do: "2,2"
  defp border_dash(_), do: "none"

  defp format_opacity(nil), do: "30%"
  defp format_opacity(val) when is_float(val), do: "#{round(val * 100)}%"
  defp format_opacity(val) when is_integer(val), do: "#{val * 100}%"

  defp format_opacity(val) when is_binary(val) do
    case Float.parse(val) do
      {f, _} -> "#{round(f * 100)}%"
      :error -> "30%"
    end
  end

  defp target_type_icon("sheet"), do: "file-text"
  defp target_type_icon("flow"), do: "git-branch"
  defp target_type_icon("scene"), do: "map"
  defp target_type_icon("url"), do: "external-link"
  defp target_type_icon(_), do: "link"

  defp target_type_label("sheet"), do: dgettext("scenes", "Sheet")
  defp target_type_label("flow"), do: dgettext("scenes", "Flow")
  defp target_type_label("scene"), do: dgettext("scenes", "Scene")
  defp target_type_label("url"), do: dgettext("scenes", "URL")
  defp target_type_label(other), do: other

  defp target_items("scene", maps, _sheets, _flows), do: maps
  defp target_items("sheet", _maps, sheets, _flows), do: flatten_sheets(sheets)
  defp target_items("flow", _maps, _sheets, flows), do: flows
  defp target_items(_, _, _, _), do: []

  defp target_display_name(type, target_id, maps, sheets, flows) do
    items = target_items(type, maps, sheets, flows)

    case Enum.find(items, fn item -> item.id == target_id end) do
      nil -> target_type_label(type)
      item -> item.name
    end
  end
end
