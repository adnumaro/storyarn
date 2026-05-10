defmodule StoryarnWeb.WorkspaceLive.ShowTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.Repo

  defp get_dashboard_vue(view) do
    LiveVue.Test.get_vue(view, name: "live/workspace/dashboard/Dashboard")
  end

  describe "Workspace show page" do
    setup :register_and_log_in_user

    test "renders workspace dashboard for owner", %{conn: conn, user: user} do
      workspace = workspace_fixture(user, %{name: "My Studio"})

      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.slug}")

      vue = get_dashboard_vue(view)
      assert vue.component == "live/workspace/dashboard/Dashboard"
      assert vue.props["workspace"]["name"] == "My Studio"
    end

    test "passes projects to Vue", %{conn: conn, user: user} do
      workspace = workspace_fixture(user, %{name: "Game Studio"})

      _project =
        user
        |> project_fixture(%{name: "Epic RPG", workspace: workspace})
        |> Repo.preload(:workspace)

      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.slug}")

      vue = get_dashboard_vue(view)
      assert Enum.any?(vue.props["projects"], fn p -> p["project"]["name"] == "Epic RPG" end)
    end

    test "passes empty projects list when no projects exist", %{conn: conn, user: user} do
      workspace = workspace_fixture(user)

      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.slug}")

      vue = get_dashboard_vue(view)
      assert vue.props["projects"] == []
    end

    test "renders for workspace member", %{conn: conn, user: user} do
      owner = user_fixture()
      workspace = workspace_fixture(owner, %{name: "Shared Studio"})
      _ws_membership = workspace_membership_fixture(workspace, user, "member")

      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.slug}")

      vue = get_dashboard_vue(view)
      assert vue.props["workspace"]["name"] == "Shared Studio"
      assert vue.props["membership"]["role"] == "member"
    end

    test "redirects non-member to workspaces", %{conn: conn} do
      owner = user_fixture()
      workspace = workspace_fixture(owner)

      {:error, {:live_redirect, %{to: path}}} =
        live(conn, ~p"/workspaces/#{workspace.slug}")

      assert path == "/workspaces"
    end

    test "passes can-create-project=true for owner", %{conn: conn, user: user} do
      workspace = workspace_fixture(user)

      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.slug}")

      vue = get_dashboard_vue(view)
      assert vue.props["can-create-project"] == true
    end

    test "passes settings-url for owner", %{conn: conn, user: user} do
      workspace = workspace_fixture(user)

      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.slug}")

      vue = get_dashboard_vue(view)
      assert vue.props["settings-url"] =~ "/users/settings/workspaces/"
      assert vue.props["membership"]["role"] == "owner"
    end

    test "admin member role passed to Vue", %{conn: conn, user: user} do
      owner = user_fixture()
      workspace = workspace_fixture(owner, %{name: "Admin Studio"})
      _ws_membership = workspace_membership_fixture(workspace, user, "admin")

      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.slug}")

      vue = get_dashboard_vue(view)
      assert vue.props["membership"]["role"] == "admin"
    end

    test "viewer membership role passed to Vue", %{conn: conn, user: user} do
      owner = user_fixture()
      workspace = workspace_fixture(owner, %{name: "Viewer Studio"})
      _ws_membership = workspace_membership_fixture(workspace, user, "viewer")

      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.slug}")

      vue = get_dashboard_vue(view)
      assert vue.props["membership"]["role"] == "viewer"
    end

    test "member role passed to Vue", %{conn: conn, user: user} do
      owner = user_fixture()
      workspace = workspace_fixture(owner, %{name: "Member Studio"})
      _ws_membership = workspace_membership_fixture(workspace, user, "member")

      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.slug}")

      vue = get_dashboard_vue(view)
      assert vue.props["membership"]["role"] == "member"
    end

    test "passes workspace banner_url to Vue", %{conn: conn, user: user} do
      workspace =
        workspace_fixture(user, %{
          name: "Banner Studio",
          banner_url: "https://example.com/banner.jpg"
        })

      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.slug}")

      vue = get_dashboard_vue(view)
      assert vue.props["workspace"]["banner_url"] == "https://example.com/banner.jpg"
    end

    test "passes workspace description to Vue", %{conn: conn, user: user} do
      workspace =
        workspace_fixture(user, %{
          name: "Described Studio",
          description: "A very creative workspace"
        })

      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.slug}")

      vue = get_dashboard_vue(view)
      assert vue.props["workspace"]["description"] == "A very creative workspace"
    end

    test "passes project name and description in projects list", %{conn: conn, user: user} do
      workspace = workspace_fixture(user, %{name: "Card Studio"})

      _project =
        user
        |> project_fixture(%{
          name: "Described Project",
          description: "An epic adventure game",
          workspace: workspace
        })
        |> Repo.preload(:workspace)

      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.slug}")

      vue = get_dashboard_vue(view)

      entry =
        Enum.find(vue.props["projects"], fn p -> p["project"]["name"] == "Described Project" end)

      assert entry["project"]["description"] == "An epic adventure game"
    end

    test "search event filters projects", %{conn: conn, user: user} do
      workspace = workspace_fixture(user, %{name: "Search Studio"})

      _p1 = project_fixture(user, %{name: "Alpha Game", workspace: workspace})
      _p2 = project_fixture(user, %{name: "Beta Game", workspace: workspace})

      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.slug}")

      render_change(view, "search", %{"search" => "Alpha"})

      vue = get_dashboard_vue(view)
      names = Enum.map(vue.props["projects"], & &1["project"]["name"])
      assert "Alpha Game" in names
      refute "Beta Game" in names
      assert vue.props["search-query"] == "Alpha"
    end

    test "includes project id in projects list", %{conn: conn, user: user} do
      workspace = workspace_fixture(user, %{name: "Link Studio"})

      project =
        user
        |> project_fixture(%{name: "Linked Project", workspace: workspace})
        |> Repo.preload(:workspace)

      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.slug}")

      vue = get_dashboard_vue(view)
      assert Enum.any?(vue.props["projects"], fn p -> p["project"]["id"] == project.id end)
    end
  end

  describe "billing limits" do
    setup :register_and_log_in_user

    test "passes can-create-project=false when project limit reached", %{conn: conn, user: user} do
      workspace = workspace_fixture(user)
      scope = Storyarn.Accounts.Scope.for_user(user)

      # Create 3 projects to reach the free plan limit
      for i <- 1..3 do
        {:ok, _} =
          Storyarn.Projects.create_project(scope, %{
            name: "Project #{i}",
            workspace_id: workspace.id
          })
      end

      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.slug}")

      vue = get_dashboard_vue(view)
      assert vue.props["can-create-project"] == false
    end
  end

  describe "Authentication" do
    test "unauthenticated user gets redirected to login", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/workspaces/some-workspace")

      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/log-in"
      assert %{"error" => "You must log in to access this page."} = flash
    end
  end
end
