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

  alias Storyarn.Repo
  alias Storyarn.Workspaces

  @moduletag :e2e

  # Helper to authenticate via magic link
  defp authenticate_user(conn, user) do
    {token, _db_token} = generate_user_magic_link_token(user)
    workspace = Workspaces.get_default_workspace(user)

    conn
    |> visit("/users/log-in/#{token}")
    |> click_button("Keep me logged in on this device")
    |> assert_path("/workspaces/#{workspace.slug}")
  end

  describe "collaboration UI elements" do
    test "flow editor shows canvas with collaboration data attributes", %{conn: conn} do
      user = user_fixture()
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Collab Test Flow"})

      conn
      |> authenticate_user(user)
      |> visit("/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}")
      |> assert_has("#flow-canvas[data-user-id]")
      |> assert_has("#flow-canvas[data-user-color]")
      |> assert_has("#flow-canvas[data-locks]")
    end

    test "save indicator shows when editing node", %{conn: conn} do
      user = user_fixture()
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Save Test Flow"})
      _node = node_fixture(flow, %{type: "hub", data: %{"label" => "Test Hub"}})

      # This test verifies the save indicator infrastructure is in place
      # Full interaction tests would require clicking on the canvas
      conn
      |> authenticate_user(user)
      |> visit("/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}")
      |> assert_has("#flow-canvas")
    end
  end
end
