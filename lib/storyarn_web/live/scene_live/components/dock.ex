defmodule StoryarnWeb.SceneLive.Components.Dock do
  @moduledoc """
  Bottom dock component for the scene canvas editor.
  Renders the tool palette for Edit mode.
  """

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.Components.CoreComponents

  @shape_tools [
    {:rectangle, "square", :rectangle},
    {:triangle, "triangle", :triangle},
    {:circle, "circle", :circle},
    {:freeform, "pentagon", :freeform}
  ]

  attr :active_tool, :atom, required: true
  attr :pending_sheet, :any, default: nil

  def dock(assigns) do
    assigns =
      assigns
      |> assign(:shape_tools, shape_tools())
      |> assign(:active_shape, active_shape(assigns.active_tool))

    ~H"""
    <div
      id="scene-dock"
      class="absolute bottom-3 left-1/2 -translate-x-1/2 z-[1000] flex items-center gap-1 surface-panel px-2 py-2"
    >
      <%!-- Group 1: Navigation --%>
      <.dock_button
        tool="select"
        icon="mouse-pointer-2"
        active={@active_tool == :select}
        tooltip={dgettext("scenes", "Select elements on the canvas")}
        tooltip_title={dgettext("scenes", "Select")}
      />
      <.dock_button
        tool="pan"
        icon="hand"
        active={@active_tool == :pan}
        tooltip={dgettext("scenes", "Pan and scroll around the map")}
        tooltip_title={dgettext("scenes", "Pan")}
      />

      <.dock_separator />

      <%!-- Group 2: Shapes — single dropdown --%>
      <div class="dock-item group relative">
        <div class="dropdown dropdown-top">
          <div
            tabindex="0"
            role="button"
            class={"dock-btn #{if @active_shape, do: "dock-btn-active", else: ""}"}
          >
            <.icon name={if(@active_shape, do: @active_shape.icon, else: "pentagon")} class="size-6" />
          </div>
          <div
            tabindex="0"
            class="dropdown-content mb-3 p-3 bg-base-100 rounded-xl border border-base-300 shadow-xl w-52"
          >
            <div class="text-xs font-semibold text-base-content/50 uppercase tracking-wider mb-2 px-1">
              {dgettext("scenes", "Zone Shapes")}
            </div>
            <div class="flex flex-col gap-0.5">
              <button
                :for={shape <- @shape_tools}
                type="button"
                phx-click="set_tool"
                phx-value-tool={shape.id}
                class={"flex items-center gap-2.5 px-2.5 py-2 rounded-lg text-sm transition-colors #{if @active_tool == shape.atom, do: "bg-primary text-primary-content", else: "hover:bg-base-200"}"}
              >
                <.icon name={shape.icon} class="size-5" />
                {shape.title}
              </button>
            </div>
          </div>
        </div>
        <%!-- Hover tooltip (hidden when dropdown opens via CSS :focus-within) --%>
        <div class="dock-tooltip">
          <div class="text-sm font-semibold mb-0.5">{dgettext("scenes", "Zones")}</div>
          <div class="text-xs text-base-content/60 leading-relaxed">
            {dgettext("scenes", "Draw shapes to define areas on the map")}
          </div>
        </div>
      </div>

      <.dock_separator />

      <%!-- Group 3: Elements --%>
      <%!-- Pin dropdown --%>
      <div class="dock-item group relative">
        <div class="dropdown dropdown-top">
          <div
            tabindex="0"
            role="button"
            class={"dock-btn #{if @active_tool == :pin, do: "dock-btn-active", else: ""}"}
          >
            <.icon name="map-pin" class="size-6" />
          </div>
          <div
            tabindex="0"
            class="dropdown-content mb-3 p-3 bg-base-100 rounded-xl border border-base-300 shadow-xl w-52"
          >
            <div class="text-xs font-semibold text-base-content/50 uppercase tracking-wider mb-2 px-1">
              {dgettext("scenes", "Place a Pin")}
            </div>
            <button
              type="button"
              phx-click="set_tool"
              phx-value-tool="pin"
              class="w-full flex items-center gap-2.5 px-2.5 py-2 rounded-lg text-sm hover:bg-base-200 transition-colors"
            >
              <.icon name="map-pin" class="size-4" />
              <div>
                <div class="font-medium">{dgettext("scenes", "Free Pin")}</div>
                <div class="text-xs text-base-content/50">
                  {dgettext("scenes", "Place anywhere on the map")}
                </div>
              </div>
            </button>
            <button
              type="button"
              phx-click="show_sheet_picker"
              class="w-full flex items-center gap-2.5 px-2.5 py-2 rounded-lg text-sm hover:bg-base-200 transition-colors"
            >
              <.icon name="user" class="size-4" />
              <div>
                <div class="font-medium">{dgettext("scenes", "From Sheet")}</div>
                <div class="text-xs text-base-content/50">
                  {dgettext("scenes", "Link a character or item")}
                </div>
              </div>
            </button>
          </div>
        </div>
        <%!-- Hover tooltip (hidden when dropdown opens via CSS :focus-within) --%>
        <div class="dock-tooltip">
          <div class="text-sm font-semibold mb-0.5">{dgettext("scenes", "Pin")}</div>
          <div class="text-xs text-base-content/60 leading-relaxed">
            {dgettext("scenes", "Place markers on the map, optionally linked to a sheet")}
          </div>
        </div>
      </div>

      <%!-- Annotation --%>
      <.dock_button
        tool="annotation"
        icon="sticky-note"
        active={@active_tool == :annotation}
        tooltip={dgettext("scenes", "Add text notes directly on the canvas")}
        tooltip_title={dgettext("scenes", "Annotation")}
      />

      <.dock_separator />

      <%!-- Group 4: Connector --%>
      <.dock_button
        tool="connector"
        icon="cable"
        active={@active_tool == :connector}
        tooltip={
          dgettext(
            "maps",
            "Draw connections between two pins. Click the source pin, then the target."
          )
        }
        tooltip_title={dgettext("scenes", "Connector")}
      />

      <.dock_separator />

      <%!-- Group 5: Ruler --%>
      <.dock_button
        tool="ruler"
        icon="ruler"
        active={@active_tool == :ruler}
        tooltip={dgettext("scenes", "Measure distances between two points on the map")}
        tooltip_title={dgettext("scenes", "Ruler")}
      />
    </div>

    <%!-- Pending sheet indicator --%>
    <div
      :if={@pending_sheet}
      class="absolute bottom-24 left-1/2 -translate-x-1/2 z-[1000] bg-info/10 border border-info/30 rounded-lg px-3 py-1.5 text-xs text-info-content flex items-center gap-2"
    >
      <.icon name="map-pin" class="size-3.5" />
      <span>
        {dgettext("scenes", "Click on canvas to place")} <strong>{@pending_sheet.name}</strong>
      </span>
      <button type="button" phx-click="cancel_sheet_picker" class="btn btn-ghost btn-xs btn-square">
        <.icon name="x" class="size-3" />
      </button>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Sub-components
  # ---------------------------------------------------------------------------

  attr :tool, :string, required: true
  attr :icon, :string, required: true
  attr :active, :boolean, default: false
  attr :tooltip, :string, required: true
  attr :tooltip_title, :string, required: true

  defp dock_button(assigns) do
    ~H"""
    <div class="dock-item group relative">
      <button
        type="button"
        phx-click="set_tool"
        phx-value-tool={@tool}
        class={"dock-btn #{if @active, do: "dock-btn-active", else: ""}"}
      >
        <.icon name={@icon} class="size-6" />
      </button>
      <%!-- Hover mega-tooltip --%>
      <div class="dock-tooltip">
        <div class="text-sm font-semibold mb-0.5">{@tooltip_title}</div>
        <div class="text-xs text-base-content/60 leading-relaxed">{@tooltip}</div>
      </div>
    </div>
    """
  end

  defp dock_separator(assigns) do
    ~H"""
    <div class="w-px h-8 bg-base-300 mx-0.5 shrink-0"></div>
    """
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp shape_tools do
    Enum.map(@shape_tools, fn {atom, icon, title_key} ->
      %{atom: atom, id: Atom.to_string(atom), icon: icon, title: tool_title(title_key)}
    end)
  end

  defp active_shape(tool) when tool in [:rectangle, :triangle, :circle, :freeform] do
    Enum.find(shape_tools(), &(&1.atom == tool))
  end

  defp active_shape(_), do: nil

  defp tool_title(:select), do: dgettext("scenes", "Select")
  defp tool_title(:pan), do: dgettext("scenes", "Pan")
  defp tool_title(:rectangle), do: dgettext("scenes", "Rectangle")
  defp tool_title(:triangle), do: dgettext("scenes", "Triangle")
  defp tool_title(:circle), do: dgettext("scenes", "Circle")
  defp tool_title(:freeform), do: dgettext("scenes", "Freeform")
  defp tool_title(:pin), do: dgettext("scenes", "Pin")
  defp tool_title(:annotation), do: dgettext("scenes", "Annotation")
  defp tool_title(:connector), do: dgettext("scenes", "Connector")
  defp tool_title(:ruler), do: dgettext("scenes", "Ruler")
end
