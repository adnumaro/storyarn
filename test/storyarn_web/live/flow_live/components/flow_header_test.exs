defmodule StoryarnWeb.FlowLive.Components.FlowHeaderTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias StoryarnWeb.FlowLive.Components.FlowHeader

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

  defp render_actions(opts \\ []) do
    render_component(&FlowHeader.flow_actions/1,
      flow: Keyword.get(opts, :flow, make_flow()),
      workspace: make_workspace(),
      project: make_project(),
      can_edit: Keyword.get(opts, :can_edit, true),
      debug_panel_open: Keyword.get(opts, :debug_panel_open, false),
      node_types: Keyword.get(opts, :node_types, ["dialogue", "condition", "instruction"])
    )
  end

  defp render_info_bar(opts) do
    render_component(&FlowHeader.flow_info_bar/1,
      flow: Keyword.get(opts, :flow, make_flow()),
      can_edit: Keyword.get(opts, :can_edit, true),
      save_status: Keyword.get(opts, :save_status, :idle),
      nav_history: Keyword.get(opts, :nav_history, nil),
      scene_name: Keyword.get(opts, :scene_name, nil),
      scene_inherited: Keyword.get(opts, :scene_inherited, false),
      available_scenes: Keyword.get(opts, :available_scenes, [])
    )
  end

  # ── flow_actions ────────────────────────────────────────────────

  describe "flow_actions/1" do
    test "renders play button" do
      html = render_actions()
      assert html =~ "Play"
    end

    test "play link includes path segments" do
      html = render_actions()
      assert html =~ "/play"
      assert html =~ "test-ws"
      assert html =~ "test-proj"
    end

    test "renders debug button in default state" do
      html = render_actions(debug_panel_open: false)
      assert html =~ "debug_start"
      assert html =~ "Debug"
    end

    test "debug button shows Stop when panel is open" do
      html = render_actions(debug_panel_open: true)
      assert html =~ "debug_stop"
      assert html =~ "Stop"
      assert html =~ "btn-accent"
    end

    test "shows Add Node dropdown when can_edit" do
      html = render_actions(can_edit: true)
      assert html =~ "Add Node"
      assert html =~ "add_node"
    end

    test "hides Add Node when cannot edit" do
      html = render_actions(can_edit: false)
      refute html =~ "Add Node"
    end

    test "renders node type options in dropdown" do
      html = render_actions(node_types: ["dialogue", "condition"])
      assert html =~ ~s(phx-value-type="dialogue")
      assert html =~ ~s(phx-value-type="condition")
    end

    test "renders empty dropdown when no node_types" do
      html = render_actions(node_types: [])
      assert html =~ "Add Node"
      # No list items
      refute html =~ "phx-value-type"
    end
  end

  # ── flow_info_bar ───────────────────────────────────────────────

  describe "flow_info_bar/1" do
    test "renders flow name" do
      html = render_info_bar(flow: make_flow(name: "My Cool Flow"))
      assert html =~ "My Cool Flow"
    end

    test "renders editable title when can_edit" do
      html = render_info_bar(can_edit: true)
      assert html =~ "EditableTitle"
      assert html =~ ~s(contenteditable="true")
    end

    test "renders read-only title when cannot edit" do
      html = render_info_bar(can_edit: false)
      refute html =~ "EditableTitle"
      assert html =~ "Test Flow"
    end

    test "renders shortcut when can_edit" do
      html = render_info_bar(can_edit: true, flow: make_flow(shortcut: "my-shortcut"))
      assert html =~ "EditableShortcut"
      assert html =~ "my-shortcut"
    end

    test "renders shortcut read-only when cannot edit" do
      html = render_info_bar(can_edit: false, flow: make_flow(shortcut: "my-shortcut"))
      assert html =~ "my-shortcut"
      refute html =~ "EditableShortcut"
    end

    test "shows Main badge for main flow" do
      html = render_info_bar(flow: make_flow(is_main: true))
      assert html =~ "Main"
      assert html =~ "badge-primary"
    end

    test "hides Main badge for non-main flow" do
      html = render_info_bar(flow: make_flow(is_main: false))
      refute html =~ "badge-primary"
    end

    test "shows scene name" do
      html = render_info_bar(scene_name: "Forest", can_edit: true)
      assert html =~ "Forest"
    end

    test "shows No scene when no scene" do
      html = render_info_bar(scene_name: nil, can_edit: true)
      assert html =~ "No scene"
    end

    test "shows inherited indicator" do
      html = render_info_bar(scene_name: "Village", scene_inherited: true, can_edit: true)
      assert html =~ "inherited"
    end

    test "scene dropdown lists available scenes" do
      scenes = [%{id: 1, name: "Forest"}, %{id: 2, name: "Cave"}]
      html = render_info_bar(available_scenes: scenes, can_edit: true)
      assert html =~ "Forest"
      assert html =~ "Cave"
      assert html =~ "update_scene"
    end

    test "scene dropdown shows inherit option" do
      html = render_info_bar(can_edit: true)
      assert html =~ "No scene (inherit)"
    end

    test "no nav history buttons when history is nil" do
      html = render_info_bar(nav_history: nil)
      refute html =~ "nav_back"
      refute html =~ "nav_forward"
    end

    test "hides scene dropdown when cannot edit" do
      html = render_info_bar(can_edit: false, scene_name: nil)
      refute html =~ "update_scene"
    end
  end
end
