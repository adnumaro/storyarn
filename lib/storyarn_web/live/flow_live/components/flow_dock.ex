defmodule StoryarnWeb.FlowLive.Components.FlowDock do
  @moduledoc """
  Bottom dock for the flow canvas editor.

  Builds flow-specific tool groups and delegates rendering to `CanvasDock`.
  """

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext
  use StoryarnWeb, :verified_routes

  import StoryarnWeb.Components.CanvasDock

  alias StoryarnWeb.FlowLive.NodeTypeRegistry

  attr :flow, :map, required: true
  attr :workspace, :map, required: true
  attr :project, :map, required: true
  attr :can_edit, :boolean, required: true
  attr :debug_panel_open, :boolean, default: false

  def flow_dock(assigns) do
    assigns = assign(assigns, :groups, build_groups(assigns))

    ~H"""
    <.canvas_dock id="flow-dock" groups={@groups} />
    """
  end

  # ---------------------------------------------------------------------------
  # Group builders
  # ---------------------------------------------------------------------------

  defp build_groups(assigns) do
    groups = []

    groups =
      if assigns.can_edit do
        groups ++ [annotation_group(), node_type_group()]
      else
        groups
      end

    groups ++ [actions_group(assigns)]
  end

  defp annotation_group do
    [
      %{
        id: "note",
        icon: "sticky-note",
        tooltip_title: dgettext("flows", "Note"),
        tooltip: dgettext("flows", "Add a sticky note to the canvas"),
        click: "add_annotation"
      }
    ]
  end

  defp node_type_group do
    [
      %{
        id: "narrative",
        icon: "message-square",
        tooltip_title: dgettext("flows", "Narrative"),
        tooltip: dgettext("flows", "Story and dialogue nodes"),
        children: [
          node_child("dialogue"),
          node_child("slug_line")
        ]
      },
      %{
        id: "logic",
        icon: "zap",
        tooltip_title: dgettext("flows", "Logic"),
        tooltip: dgettext("flows", "Conditions and instructions"),
        children: [
          node_child("condition"),
          node_child("instruction")
        ]
      },
      %{
        id: "navigation",
        icon: "route",
        tooltip_title: dgettext("flows", "Navigation"),
        tooltip: dgettext("flows", "Flow control and routing"),
        children: [
          node_child("exit"),
          node_child("hub"),
          node_child("jump"),
          node_child("subflow")
        ]
      }
    ]
  end

  defp actions_group(assigns) do
    play_url =
      ~p"/workspaces/#{assigns.workspace.slug}/projects/#{assigns.project.slug}/flows/#{assigns.flow.id}/play"

    [
      %{
        id: "play",
        icon: "play",
        tooltip_title: dgettext("flows", "Play"),
        tooltip: dgettext("flows", "Run this flow in story player"),
        navigate: play_url
      },
      %{
        id: "debug",
        icon: "bug",
        tooltip_title: dgettext("flows", "Debug"),
        tooltip: dgettext("flows", "Step through flow execution"),
        click: if(assigns.debug_panel_open, do: "debug_stop", else: "debug_start"),
        active: assigns.debug_panel_open
      }
    ]
  end

  defp node_child(type) do
    %{
      id: type,
      icon: NodeTypeRegistry.icon_name(type),
      title: NodeTypeRegistry.label(type),
      description: NodeTypeRegistry.description(type),
      click: "add_node",
      value: type
    }
  end
end
