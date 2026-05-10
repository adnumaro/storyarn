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

      surface = LiveVue.Test.get_vue(view, name: "modules/flows/editor/FlowSurface")
      panels = LiveVue.Test.get_vue(view, name: "modules/flows/editor/FlowPanels")
      header = LiveVue.Test.get_vue(view, name: "modules/flows/editor/FlowHeader")

      assert header.props["flow-name"] == "Canonical Flow"
      assert surface.props["surface"]["canvas"]["canvasId"] == "flow-canvas-#{flow.id}"
      assert surface.props["surface"]["dock"]["flowId"] == flow.id
      assert panels.props["panels"]["debug"]["open"] == false
    end
  end
end
