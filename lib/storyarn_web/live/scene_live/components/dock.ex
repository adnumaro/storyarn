defmodule StoryarnWeb.SceneLive.Components.Dock do
  @moduledoc """
  Bottom dock component for the scene canvas editor.
  Renders the tool palette for Edit mode using the shared CanvasDock.
  """

  use Phoenix.Component
  use StoryarnWeb, :verified_routes
  use Gettext, backend: Storyarn.Gettext

  alias Phoenix.LiveView.JS

  import StoryarnWeb.Components.CanvasDock
  import StoryarnWeb.Components.CoreComponents

  @shape_tools [
    {:rectangle, "square", :rectangle},
    {:triangle, "triangle", :triangle},
    {:circle, "circle", :circle},
    {:freeform, "pentagon", :freeform}
  ]

  attr :active_tool, :atom, required: true
  attr :pending_sheet, :any, default: nil
  attr :workspace, :map, required: true
  attr :project, :map, required: true
  attr :scene, :map, required: true
  attr :compact, :boolean, default: false

  def dock(assigns) do
    assigns = assign(assigns, :groups, build_groups(assigns))

    ~H"""
    <.canvas_dock id="scene-dock" groups={@groups}>
      <:extra>
        <div
          :if={@pending_sheet}
          class="absolute bottom-24 left-1/2 -translate-x-1/2 z-[1000] bg-info/10 border border-info/30 rounded-lg px-3 py-1.5 text-xs text-info-content flex items-center gap-2"
        >
          <.icon name="map-pin" class="size-3.5" />
          <span>
            {dgettext("scenes", "Click on canvas to place")} <strong>{@pending_sheet.name}</strong>
          </span>
          <button
            type="button"
            phx-click="cancel_sheet_picker"
            class="btn btn-ghost btn-xs btn-square"
          >
            <.icon name="x" class="size-3" />
          </button>
        </div>
      </:extra>
    </.canvas_dock>
    """
  end

  # ---------------------------------------------------------------------------
  # Group builders
  # ---------------------------------------------------------------------------

  defp build_groups(assigns) do
    active_tool = assigns.active_tool

    groups = [
      navigation_group(active_tool),
      creation_group(active_tool),
      [connector_item(active_tool)],
      [ruler_item(active_tool)]
    ]

    if assigns.compact do
      groups
    else
      groups ++ [[history_item(assigns), play_item(assigns)]]
    end
  end

  defp navigation_group(active_tool) do
    [
      %{
        id: "select",
        icon: "mouse-pointer-2",
        tooltip_title: dgettext("scenes", "Select"),
        tooltip: dgettext("scenes", "Select elements on the canvas"),
        click: "set_tool",
        value: "select",
        active: active_tool == :select
      },
      %{
        id: "pan",
        icon: "hand",
        tooltip_title: dgettext("scenes", "Pan"),
        tooltip: dgettext("scenes", "Pan and scroll around the map"),
        click: "set_tool",
        value: "pan",
        active: active_tool == :pan
      }
    ]
  end

  defp creation_group(active_tool) do
    active_shape = active_shape(active_tool)

    [
      %{
        id: "shapes",
        icon: if(active_shape, do: active_shape.icon, else: "pentagon"),
        tooltip_title: dgettext("scenes", "Zones"),
        tooltip: dgettext("scenes", "Draw shapes to define areas on the map"),
        active: active_shape != nil,
        dropdown_title: dgettext("scenes", "Zone Shapes"),
        children:
          Enum.map(shape_tools(), fn shape ->
            %{
              id: shape.id,
              icon: shape.icon,
              title: shape.title,
              click: "set_tool",
              value: shape.id
            }
          end)
      },
      %{
        id: "pins",
        icon: "map-pin",
        tooltip_title: dgettext("scenes", "Pin"),
        tooltip: dgettext("scenes", "Place markers on the map, optionally linked to a sheet"),
        active: active_tool == :pin,
        dropdown_title: dgettext("scenes", "Place a Pin"),
        children: [
          %{
            id: "free_pin",
            icon: "map-pin",
            title: dgettext("scenes", "Free Pin"),
            description: dgettext("scenes", "Place anywhere on the map"),
            click: "set_tool",
            value: "pin"
          },
          %{
            id: "sheet_pin",
            icon: "user",
            title: dgettext("scenes", "From Sheet"),
            description: dgettext("scenes", "Link a character or item"),
            click: "show_sheet_picker"
          }
        ]
      },
      %{
        id: "annotation",
        icon: "sticky-note",
        tooltip_title: dgettext("scenes", "Annotation"),
        tooltip: dgettext("scenes", "Add text notes directly on the canvas"),
        click: "set_tool",
        value: "annotation",
        active: active_tool == :annotation
      }
    ]
  end

  defp connector_item(active_tool) do
    %{
      id: "connector",
      icon: "cable",
      tooltip_title: dgettext("scenes", "Connector"),
      tooltip:
        dgettext(
          "scenes",
          "Draw connections between two pins. Click the source pin, then the target."
        ),
      click: "set_tool",
      value: "connector",
      active: active_tool == :connector
    }
  end

  defp ruler_item(active_tool) do
    %{
      id: "ruler",
      icon: "ruler",
      tooltip_title: dgettext("scenes", "Ruler"),
      tooltip: dgettext("scenes", "Measure distances between two points on the map"),
      click: "set_tool",
      value: "ruler",
      active: active_tool == :ruler
    }
  end

  defp history_item(_assigns) do
    %{
      id: "history",
      icon: "history",
      tooltip_title: dgettext("scenes", "Version History"),
      tooltip: dgettext("scenes", "View and manage version history"),
      click: JS.dispatch("panel:toggle", to: "#scene-versions-panel"),
      panel_trigger: "scene-versions-panel"
    }
  end

  defp play_item(assigns) do
    %{
      id: "play",
      icon: "play",
      tooltip_title: dgettext("scenes", "Play"),
      tooltip: dgettext("scenes", "Play exploration mode"),
      navigate:
        ~p"/workspaces/#{assigns.workspace.slug}/projects/#{assigns.project.slug}/scenes/#{assigns.scene.id}/explore"
    }
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

  defp tool_title(:rectangle), do: dgettext("scenes", "Rectangle")
  defp tool_title(:triangle), do: dgettext("scenes", "Triangle")
  defp tool_title(:circle), do: dgettext("scenes", "Circle")
  defp tool_title(:freeform), do: dgettext("scenes", "Freeform")
end
