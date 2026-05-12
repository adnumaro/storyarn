defmodule StoryarnWeb.FlowLive.ShowTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  alias Phoenix.LiveView.Socket
  alias Storyarn.Repo
  alias StoryarnWeb.FlowLive.Show

  describe "flow editor layout" do
    setup :register_and_log_in_user

    test "renders header, surface, and panels on the canonical route",
         %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Canonical Flow"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
        )

      render_async(view, 2000)

      surface = LiveVue.Test.get_vue(view, name: "live/flow/show/FlowSurface")
      panels = LiveVue.Test.get_vue(view, name: "live/flow/show/FlowPanels")
      header = LiveVue.Test.get_vue(view, name: "live/flow/show/FlowHeader")

      assert header.props["flow-name"] == "Canonical Flow"
      assert surface.props["surface"]["canvas"]["canvasId"] == "flow-canvas-#{flow.id}"
      assert surface.props["surface"]["dock"]["flowId"] == flow.id
      assert panels.props["panels"]["debug"]["open"] == false
    end

    test "compact route keeps the canvas boundary mounted while data loads",
         %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Compact Flow"})

      {:ok, view, html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}?layout=compact"
        )

      layout = LiveVue.Test.get_vue(html, name: "live/layouts/compare/Layout")
      initial_canvas = LiveVue.Test.get_vue(html, name: "live/flow/show/FlowCanvas")

      assert layout.id == "compare-layout"
      assert initial_canvas.id == "flow-editor-compact-#{flow.id}"
      assert initial_canvas.props["loading"] == true
      assert initial_canvas.props["flow-data"] == nil

      render_async(view, 2000)

      loaded_canvas = LiveVue.Test.get_vue(view, name: "live/flow/show/FlowCanvas")

      assert loaded_canvas.props["loading"] == false
      assert loaded_canvas.props["flow-data"] =~ "Compact Flow"
      assert loaded_canvas.props["canvas-id"] == "flow-canvas-#{flow.id}"
    end
  end

  describe "async flow loading" do
    setup :register_and_log_in_user

    test "ignores stale load results after navigating to another flow", %{user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      current_flow = flow_fixture(project, %{name: "Current Flow"})
      stale_flow = flow_fixture(project, %{name: "Stale Flow"})

      socket = %Socket{
        assigns: %{
          __changed__: %{},
          flow: current_flow,
          loading: true,
          selected_node: :keep
        }
      }

      {:noreply, result} =
        Show.handle_async(:load_flow_data, {:ok, %{flow: stale_flow}}, socket)

      assert result.assigns.flow.id == current_flow.id
      assert result.assigns.loading == true
      assert result.assigns.selected_node == :keep
    end
  end
end
