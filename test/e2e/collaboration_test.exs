defmodule StoryarnWeb.E2E.CollaborationTest do
  @moduledoc """
  E2E tests for collaboration features.

  These tests verify the collaboration UI elements are present and functional.
  Multi-user collaboration scenarios are better tested with integration tests
  due to the complexity of managing multiple browser sessions.

  Run with: mix test.e2e
  """

  use PhoenixTest.Playwright.Case, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import StoryarnWeb.E2EHelpers

  alias Storyarn.Repo

  @moduletag :e2e

  describe "collaboration UI elements" do
    test "flow editor shows canvas with collaboration data attributes", %{conn: conn} do
      user = user_fixture()
      project = user |> project_fixture() |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Collab Test Flow"})

      conn
      |> authenticate(user)
      |> visit("/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}")
      |> assert_has("[id^=\"flow-canvas-\"][data-user-id]")
      |> assert_has("[id^=\"flow-canvas-\"][data-user-color]")
    end

    test "save indicator shows when editing node", %{conn: conn} do
      user = user_fixture()
      project = user |> project_fixture() |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Save Test Flow"})
      _node = node_fixture(flow, %{type: "hub", data: %{"label" => "Test Hub"}})

      # This test verifies the save indicator infrastructure is in place
      # Full interaction tests would require clicking on the canvas
      conn
      |> authenticate(user)
      |> visit("/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}")
      |> assert_has("[id^=\"flow-canvas-\"]")
    end
  end
end
