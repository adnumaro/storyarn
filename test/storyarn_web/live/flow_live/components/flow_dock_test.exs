defmodule StoryarnWeb.FlowLive.Components.FlowDockTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias StoryarnWeb.FlowLive.Components.FlowDock

  defp make_flow(opts \\ []) do
    %{
      id: Keyword.get(opts, :id, 1),
      name: Keyword.get(opts, :name, "Test Flow"),
      shortcut: Keyword.get(opts, :shortcut, "test-flow"),
      is_main: Keyword.get(opts, :is_main, false)
    }
  end

  defp make_workspace, do: %{slug: "test-ws"}
  defp make_project, do: %{slug: "test-proj"}

  defp render_dock(opts \\ []) do
    render_component(&FlowDock.flow_dock/1,
      flow: Keyword.get(opts, :flow, make_flow()),
      workspace: make_workspace(),
      project: make_project(),
      can_edit: Keyword.get(opts, :can_edit, true),
      debug_panel_open: Keyword.get(opts, :debug_panel_open, false)
    )
  end

  describe "flow_dock/1" do
    test "renders play link" do
      html = render_dock()
      assert html =~ "/play"
      assert html =~ "test-ws"
      assert html =~ "test-proj"
    end

    test "renders debug button in default state" do
      html = render_dock(debug_panel_open: false)
      assert html =~ "debug_start"
    end

    test "debug button toggles to stop when panel is open" do
      html = render_dock(debug_panel_open: true)
      assert html =~ "debug_stop"
      assert html =~ "dock-btn-active"
    end

    test "shows node type dropdowns when can_edit" do
      html = render_dock(can_edit: true)
      assert html =~ "add_node"
      assert html =~ ~s(phx-value-type="dialogue")
      assert html =~ ~s(phx-value-type="condition")
      assert html =~ ~s(phx-value-type="instruction")
      assert html =~ ~s(phx-value-type="exit")
      assert html =~ ~s(phx-value-type="hub")
      assert html =~ ~s(phx-value-type="jump")
      assert html =~ ~s(phx-value-type="subflow")
      assert html =~ ~s(phx-value-type="slug_line")
    end

    test "shows note button when can_edit" do
      html = render_dock(can_edit: true)
      assert html =~ "add_annotation"
    end

    test "hides node types and note when cannot edit" do
      html = render_dock(can_edit: false)
      refute html =~ "add_node"
      refute html =~ "add_annotation"
    end

    test "always shows play and debug regardless of can_edit" do
      html = render_dock(can_edit: false)
      assert html =~ "/play"
      assert html =~ "debug_start"
    end
  end
end
