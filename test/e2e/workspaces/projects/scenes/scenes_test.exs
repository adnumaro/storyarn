defmodule StoryarnWeb.E2E.ScenesTest do
  @moduledoc """
  E2E tests for scene-related functionality.

  These tests use Playwright to run in a real browser.

  Run with: mix test.e2e
  """

  use PhoenixTest.Playwright.Case, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures

  alias Storyarn.Accounts
  alias Storyarn.Repo

  @moduletag :e2e

  @session_options [
    store: :cookie,
    key: "_storyarn_key",
    signing_salt: Application.compile_env!(:storyarn, [StoryarnWeb.Endpoint, :session_signing_salt]),
    encryption_salt: Application.compile_env!(:storyarn, [StoryarnWeb.Endpoint, :session_encryption_salt])
  ]

  # Authenticate by injecting a signed session cookie directly.
  # This avoids the phx-trigger-action race condition from the magic link login flow.
  defp authenticate(conn, user) do
    token = Accounts.generate_user_session_token(user)

    add_session_cookie(conn, [value: %{user_token: token}], @session_options)
  end

  describe "scenes list (authenticated)" do
    test "shows scene dashboard rows with real scene data", %{conn: conn} do
      user = user_fixture()
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "Harbor District"})
      zone_fixture(scene, %{"name" => "Market Zone"})
      pin_fixture(scene, %{"label" => "Gate"})

      conn
      |> authenticate(user)
      |> visit("/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes")
      |> assert_has("a", text: "Harbor District")
      |> assert_has("td", text: "1")
    end
  end

  describe "scene editor (authenticated)" do
    test "loads scene canvas chrome and layers", %{conn: conn} do
      user = user_fixture()
      project = user |> project_fixture() |> Repo.preload(:workspace)
      scene = scene_fixture(project, %{name: "Dungeon Map"})
      pin_fixture(scene, %{"label" => "Entrance"})
      annotation_fixture(scene, %{"text" => "First room"})

      conn
      |> authenticate(user)
      |> visit("/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}")
      |> assert_has("#scene-toolbar")
      |> assert_has("#scene-toolbar", text: "Dungeon Map")
      |> assert_has("#scene-canvas-wrapper")
      |> assert_has("#scene-layers-popover")
    end
  end
end
