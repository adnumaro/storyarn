defmodule StoryarnWeb.E2E.WorkspaceVisibilityTest do
  @moduledoc """
  E2E tests for workspace visibility via ProjectMembership.

  Verifies that a user invited to specific projects can see
  only those projects, while the owner sees all of them.

  Run with: mix test.e2e
  """

  use PhoenixTest.Playwright.Case, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.Accounts

  @moduletag :e2e

  @session_options [
    store: :cookie,
    key: "_storyarn_key",
    signing_salt:
      Application.compile_env!(:storyarn, [StoryarnWeb.Endpoint, :session_signing_salt]),
    encryption_salt:
      Application.compile_env!(:storyarn, [StoryarnWeb.Endpoint, :session_encryption_salt])
  ]

  defp authenticate(conn, user) do
    token = Accounts.generate_user_session_token(user)
    add_session_cookie(conn, [value: %{user_token: token}], @session_options)
  end

  setup do
    owner = user_fixture()
    workspace = workspace_fixture(owner)

    project_a = project_fixture(owner, %{name: "Alpha Project", workspace: workspace})
    project_b = project_fixture(owner, %{name: "Beta Project", workspace: workspace})
    project_c = project_fixture(owner, %{name: "Gamma Project", workspace: workspace})

    member = user_fixture()
    membership_fixture(project_a, member, "editor")
    membership_fixture(project_b, member, "viewer")
    # member has NO access to project_c

    %{
      owner: owner,
      member: member,
      workspace: workspace,
      project_a: project_a,
      project_b: project_b,
      project_c: project_c
    }
  end

  describe "project-only member visibility" do
    test "member sees only the 2 projects they belong to", %{conn: conn} = ctx do
      conn
      |> authenticate(ctx.member)
      |> visit("/workspaces/#{ctx.workspace.slug}")
      |> assert_has("h3", text: "Alpha Project")
      |> assert_has("h3", text: "Beta Project")
      |> refute_has("h3", text: "Gamma Project")
    end

    test "owner sees all projects", %{conn: conn} = ctx do
      conn
      |> authenticate(ctx.owner)
      |> visit("/workspaces/#{ctx.workspace.slug}")
      |> assert_has("h3", text: "Alpha Project")
      |> assert_has("h3", text: "Beta Project")
      |> assert_has("h3", text: "Gamma Project")
    end
  end
end
