defmodule StoryarnWeb.FlowLive.ShowTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Repo

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

      surface = LiveVue.Test.get_vue(view, name: "live/flow/show/Surface")
      panels = LiveVue.Test.get_vue(view, name: "live/flow/show/Panels")
      header = LiveVue.Test.get_vue(view, name: "live/flow/show/Header")

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
      initial_canvas = LiveVue.Test.get_vue(html, name: "live/flow/show/Canvas")

      assert layout.id == "compare-layout"
      assert initial_canvas.id == "flow-editor-compact-#{flow.id}"
      assert initial_canvas.props["loading"] == true
      assert initial_canvas.props["flow-data"] == nil

      render_async(view, 2000)

      loaded_canvas = LiveVue.Test.get_vue(view, name: "live/flow/show/Canvas")

      assert loaded_canvas.props["loading"] == false
      assert loaded_canvas.props["flow-data"] =~ "Compact Flow"
      assert loaded_canvas.props["canvas-id"] == "flow-canvas-#{flow.id}"
    end
  end
end
