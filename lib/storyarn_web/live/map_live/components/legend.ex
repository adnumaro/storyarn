defmodule StoryarnWeb.MapLive.Components.Legend do
  @moduledoc """
  Auto-generated legend component for the map canvas.

  Groups and displays pin types, zone colors, and connection styles
  currently present on the map. No manual configuration needed.
  """

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.Components.CoreComponents

  @pin_type_labels %{
    "location" => "Location",
    "character" => "Character",
    "event" => "Event",
    "custom" => "Custom"
  }

  @pin_type_icons %{
    "location" => "map-pin",
    "character" => "user",
    "event" => "zap",
    "custom" => "star"
  }

  @line_style_labels %{
    "solid" => "Solid",
    "dashed" => "Dashed",
    "dotted" => "Dotted"
  }

  attr :pins, :list, default: []
  attr :zones, :list, default: []
  attr :connections, :list, default: []
  attr :legend_open, :boolean, default: false

  def legend(assigns) do
    pin_groups = group_pins(assigns.pins)
    zone_groups = group_zones(assigns.zones)
    connection_groups = group_connections(assigns.connections)
    has_entries = pin_groups != [] or zone_groups != [] or connection_groups != []

    assigns =
      assigns
      |> assign(:pin_groups, pin_groups)
      |> assign(:zone_groups, zone_groups)
      |> assign(:connection_groups, connection_groups)
      |> assign(:has_entries, has_entries)

    ~H"""
    <div :if={@has_entries} id="map-legend" class="absolute bottom-3 right-3 z-[1000]">
      <%!-- Collapsed: just the toggle button --%>
      <button
        :if={!@legend_open}
        type="button"
        phx-click="toggle_legend"
        class="btn btn-sm bg-base-100 border-base-300 shadow-md gap-1.5"
        title={gettext("Show legend")}
      >
        <.icon name="list" class="size-4" />
        {gettext("Legend")}
      </button>

      <%!-- Expanded: full legend panel --%>
      <div
        :if={@legend_open}
        class="bg-base-100 rounded-lg border border-base-300 shadow-md w-56 max-h-64 overflow-hidden flex flex-col"
      >
        <div class="px-3 py-2 border-b border-base-300 flex items-center justify-between shrink-0">
          <span class="text-xs font-medium flex items-center gap-1.5">
            <.icon name="list" class="size-3.5" />
            {gettext("Legend")}
          </span>
          <button
            type="button"
            phx-click="toggle_legend"
            class="btn btn-ghost btn-xs btn-square"
          >
            <.icon name="chevron-down" class="size-3" />
          </button>
        </div>

        <div class="overflow-y-auto p-2 space-y-3">
          <%!-- Pin groups --%>
          <div :if={@pin_groups != []}>
            <div class="text-[10px] font-semibold text-base-content/40 uppercase tracking-wider mb-1">
              {gettext("Pins")}
            </div>
            <div :for={group <- @pin_groups} class="flex items-center gap-2 py-0.5">
              <div
                class="size-5 rounded-full flex items-center justify-center shrink-0"
                style={"background-color: #{group.color || "#6b7280"}20; color: #{group.color || "#6b7280"}"}
              >
                <.icon name={group.icon} class="size-3" />
              </div>
              <span class="text-xs flex-1 truncate">{group.label}</span>
              <span class="text-xs text-base-content/40 tabular-nums">{group.count}</span>
            </div>
          </div>

          <%!-- Zone groups --%>
          <div :if={@zone_groups != []}>
            <div class="text-[10px] font-semibold text-base-content/40 uppercase tracking-wider mb-1">
              {gettext("Zones")}
            </div>
            <div :for={group <- @zone_groups} class="flex items-center gap-2 py-0.5">
              <div
                class="size-5 rounded shrink-0 border border-base-300"
                style={"background-color: #{group.color}#{opacity_hex(group.opacity)}"}
              />
              <span class="text-xs flex-1 truncate">{group.label}</span>
              <span class="text-xs text-base-content/40 tabular-nums">{group.count}</span>
            </div>
          </div>

          <%!-- Connection groups --%>
          <div :if={@connection_groups != []}>
            <div class="text-[10px] font-semibold text-base-content/40 uppercase tracking-wider mb-1">
              {gettext("Connections")}
            </div>
            <div :for={group <- @connection_groups} class="flex items-center gap-2 py-0.5">
              <svg class="w-5 h-3 shrink-0" viewBox="0 0 20 12">
                <line
                  x1="0"
                  y1="6"
                  x2="20"
                  y2="6"
                  stroke={group.color}
                  stroke-width="2"
                  stroke-dasharray={line_dash(group.line_style)}
                />
              </svg>
              <span class="text-xs flex-1 truncate">{group.label}</span>
              <span class="text-xs text-base-content/40 tabular-nums">{group.count}</span>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Grouping helpers
  # ---------------------------------------------------------------------------

  defp group_pins(pins) do
    pins
    |> Enum.group_by(fn pin -> {pin.pin_type, pin.color} end)
    |> Enum.map(fn {{pin_type, color}, items} ->
      %{
        icon: Map.get(@pin_type_icons, pin_type, "map-pin"),
        label: Map.get(@pin_type_labels, pin_type, pin_type),
        color: color,
        count: length(items)
      }
    end)
    |> Enum.sort_by(& &1.label)
  end

  defp group_zones(zones) do
    zones
    |> Enum.group_by(fn zone -> zone.fill_color || "#3b82f6" end)
    |> Enum.map(fn {color, items} ->
      %{
        color: color,
        opacity: avg_opacity(items),
        label: color_label(color),
        count: length(items)
      }
    end)
    |> Enum.sort_by(& &1.color)
  end

  defp group_connections(connections) do
    connections
    |> Enum.group_by(fn conn -> {conn.line_style, conn.color || "#6b7280"} end)
    |> Enum.map(fn {{line_style, color}, items} ->
      %{
        line_style: line_style,
        color: color,
        label: Map.get(@line_style_labels, line_style, line_style),
        count: length(items)
      }
    end)
    |> Enum.sort_by(& &1.label)
  end

  # ---------------------------------------------------------------------------
  # Display helpers
  # ---------------------------------------------------------------------------

  defp avg_opacity(zones) do
    total = Enum.reduce(zones, 0, fn z, acc -> acc + (z.opacity || 0.3) end)
    total / max(length(zones), 1)
  end

  defp opacity_hex(opacity) when is_number(opacity) do
    hex = round(opacity * 255) |> Integer.to_string(16) |> String.pad_leading(2, "0")
    hex
  end

  defp opacity_hex(_), do: "4D"

  defp color_label(color) when is_binary(color), do: color
  defp color_label(_), do: "#3b82f6"

  defp line_dash("dashed"), do: "4,3"
  defp line_dash("dotted"), do: "2,3"
  defp line_dash(_), do: "none"
end
