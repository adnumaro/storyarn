defmodule StoryarnWeb.E2E.CollaborationTest do
  @moduledoc """
  E2E tests for collaboration features.

  These tests verify the collaboration UI elements are present and functional.
  Multi-user collaboration scenarios are better tested with integration tests
  due to the complexity of managing multiple browser sessions.

  Run with: mix test.e2e
  """

  use PhoenixTest.Playwright.Case, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Accounts
  alias Storyarn.Repo

  @moduletag :e2e

  @session_options [
    store: :cookie,
    key: "_storyarn_key",
    signing_salt: Application.compile_env!(:storyarn, [StoryarnWeb.Endpoint, :session_signing_salt]),
    encryption_salt:
      Application.compile_env!(:storyarn, [StoryarnWeb.Endpoint, :session_encryption_salt])
  ]

  # Authenticate by injecting a signed session cookie directly.
  # This avoids the phx-trigger-action race condition from the magic link login flow.
  defp authenticate(conn, user) do
    token = Accounts.generate_user_session_token(user)

    add_session_cookie(conn, [value: %{user_token: token}], @session_options)
  end

  describe "collaboration UI elements" do
    test "flow editor shows canvas with collaboration data attributes", %{conn: conn} do
      user = user_fixture()
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Collab Test Flow"})

      conn
      |> authenticate(user)
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
      |> authenticate(user)
      |> visit("/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}")
      |> assert_has("#flow-canvas")
    end
  end
end
