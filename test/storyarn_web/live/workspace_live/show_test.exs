defmodule StoryarnWeb.WorkspaceLive.ShowTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.Repo

  describe "Workspace show page" do
    setup :register_and_log_in_user

    test "renders workspace for owner", %{conn: conn, user: user} do
      workspace = workspace_fixture(user, %{name: "My Studio"})

      {:ok, _view, html} = live(conn, ~p"/workspaces/#{workspace.slug}")

      assert html =~ "My Studio"
    end

    test "renders workspace with projects", %{conn: conn, user: user} do
      workspace = workspace_fixture(user, %{name: "Game Studio"})

      _project =
        project_fixture(user, %{name: "Epic RPG", workspace: workspace})
        |> Repo.preload(:workspace)

      {:ok, _view, html} = live(conn, ~p"/workspaces/#{workspace.slug}")

      assert html =~ "Game Studio"
      assert html =~ "Epic RPG"
    end

    test "renders empty state when no projects", %{conn: conn, user: user} do
      workspace = workspace_fixture(user)

      {:ok, _view, html} = live(conn, ~p"/workspaces/#{workspace.slug}")

      assert html =~ "No projects yet"
    end

    test "renders for workspace member", %{conn: conn, user: user} do
      owner = user_fixture()
      workspace = workspace_fixture(owner, %{name: "Shared Studio"})
      _ws_membership = workspace_membership_fixture(workspace, user, "member")

      {:ok, _view, html} = live(conn, ~p"/workspaces/#{workspace.slug}")

      assert html =~ "Shared Studio"
    end

    test "redirects non-member to workspaces", %{conn: conn} do
      owner = user_fixture()
      workspace = workspace_fixture(owner)

      {:error, {:live_redirect, %{to: path}}} =
        live(conn, ~p"/workspaces/#{workspace.slug}")

      assert path == "/workspaces"
    end

    test "shows new project button for owner", %{conn: conn, user: user} do
      workspace = workspace_fixture(user)

      {:ok, _view, html} = live(conn, ~p"/workspaces/#{workspace.slug}")

      assert html =~ "New Project"
    end

    test "shows settings link for owner/admin", %{conn: conn, user: user} do
      workspace = workspace_fixture(user)

      {:ok, _view, html} = live(conn, ~p"/workspaces/#{workspace.slug}")

      assert html =~ "settings"
    end

    test "admin member sees settings link", %{conn: conn, user: user} do
      owner = user_fixture()
      workspace = workspace_fixture(owner, %{name: "Admin Studio"})
      _ws_membership = workspace_membership_fixture(workspace, user, "admin")

      {:ok, _view, html} = live(conn, ~p"/workspaces/#{workspace.slug}")

      assert html =~ "settings"
    end

    test "viewer does not see settings link", %{conn: conn, user: user} do
      owner = user_fixture()
      workspace = workspace_fixture(owner, %{name: "Viewer Studio"})
      _ws_membership = workspace_membership_fixture(workspace, user, "viewer")

      {:ok, _view, html} = live(conn, ~p"/workspaces/#{workspace.slug}")

      # The settings icon/link in the workspace header should not be present for viewers
      refute html =~ ~p"/users/settings/workspaces/#{workspace.slug}/general"
    end

    test "viewer does not see new project button", %{conn: conn, user: user} do
      owner = user_fixture()
      workspace = workspace_fixture(owner, %{name: "Read Only Studio"})
      _ws_membership = workspace_membership_fixture(workspace, user, "viewer")

      {:ok, _view, html} = live(conn, ~p"/workspaces/#{workspace.slug}")

      refute html =~ "New Project"
    end

    test "member sees new project button", %{conn: conn, user: user} do
      owner = user_fixture()
      workspace = workspace_fixture(owner, %{name: "Member Studio"})
      _ws_membership = workspace_membership_fixture(workspace, user, "member")

      {:ok, _view, html} = live(conn, ~p"/workspaces/#{workspace.slug}")

      assert html =~ "New Project"
    end

    test "renders workspace with banner image", %{conn: conn, user: user} do
      workspace =
        workspace_fixture(user, %{
          name: "Banner Studio",
          banner_url: "https://example.com/banner.jpg"
        })

      {:ok, _view, html} = live(conn, ~p"/workspaces/#{workspace.slug}")

      assert html =~ "https://example.com/banner.jpg"
      assert html =~ "<img"
    end

    test "renders workspace without banner uses gradient", %{conn: conn, user: user} do
      workspace = workspace_fixture(user, %{name: "No Banner Studio"})

      {:ok, _view, html} = live(conn, ~p"/workspaces/#{workspace.slug}")

      # Banner img should not be present (class="w-full h-full object-cover" is unique to banner)
      refute html =~ "object-cover"
      assert html =~ "bg-gradient-to-r"
    end

    test "renders workspace description", %{conn: conn, user: user} do
      workspace =
        workspace_fixture(user, %{
          name: "Described Studio",
          description: "A very creative workspace"
        })

      {:ok, _view, html} = live(conn, ~p"/workspaces/#{workspace.slug}")

      assert html =~ "A very creative workspace"
    end

    test "renders project card with description", %{conn: conn, user: user} do
      workspace = workspace_fixture(user, %{name: "Card Studio"})

      _project =
        project_fixture(user, %{
          name: "Described Project",
          description: "An epic adventure game",
          workspace: workspace
        })
        |> Repo.preload(:workspace)

      {:ok, _view, html} = live(conn, ~p"/workspaces/#{workspace.slug}")

      assert html =~ "Described Project"
      assert html =~ "An epic adventure game"
    end

    test "renders project card with creation date", %{conn: conn, user: user} do
      workspace = workspace_fixture(user, %{name: "Date Studio"})

      project =
        project_fixture(user, %{name: "Dated Project", workspace: workspace})
        |> Repo.preload(:workspace)

      {:ok, _view, html} = live(conn, ~p"/workspaces/#{workspace.slug}")

      expected_date = Calendar.strftime(project.inserted_at, "%b %d, %Y")
      assert html =~ expected_date
    end

    test "renders time_ago as 'just now' for recently updated projects", %{conn: conn, user: user} do
      workspace = workspace_fixture(user, %{name: "Time Studio"})

      _project =
        project_fixture(user, %{name: "Fresh Project", workspace: workspace})
        |> Repo.preload(:workspace)

      {:ok, _view, html} = live(conn, ~p"/workspaces/#{workspace.slug}")

      assert html =~ "just now"
    end

    test "renders time_ago as minutes for projects updated minutes ago", %{conn: conn, user: user} do
      workspace = workspace_fixture(user, %{name: "Minutes Studio"})

      project =
        project_fixture(user, %{name: "Minutes Project", workspace: workspace})
        |> Repo.preload(:workspace)

      # Update updated_at to 15 minutes ago
      minutes_ago =
        DateTime.add(DateTime.utc_now(), -15 * 60, :second) |> DateTime.truncate(:second)

      Ecto.Changeset.change(project, %{updated_at: minutes_ago})
      |> Repo.update!()

      {:ok, _view, html} = live(conn, ~p"/workspaces/#{workspace.slug}")

      assert html =~ "min ago"
    end

    test "renders time_ago as hours for projects updated hours ago", %{conn: conn, user: user} do
      workspace = workspace_fixture(user, %{name: "Hours Studio"})

      project =
        project_fixture(user, %{name: "Hours Project", workspace: workspace})
        |> Repo.preload(:workspace)

      # Update updated_at to 5 hours ago
      hours_ago =
        DateTime.add(DateTime.utc_now(), -5 * 3600, :second) |> DateTime.truncate(:second)

      Ecto.Changeset.change(project, %{updated_at: hours_ago})
      |> Repo.update!()

      {:ok, _view, html} = live(conn, ~p"/workspaces/#{workspace.slug}")

      assert html =~ "hours ago"
    end

    test "renders time_ago as days for projects updated days ago", %{conn: conn, user: user} do
      workspace = workspace_fixture(user, %{name: "Days Studio"})

      project =
        project_fixture(user, %{name: "Days Project", workspace: workspace})
        |> Repo.preload(:workspace)

      # Update updated_at to 3 days ago
      days_ago =
        DateTime.add(DateTime.utc_now(), -3 * 86_400, :second) |> DateTime.truncate(:second)

      Ecto.Changeset.change(project, %{updated_at: days_ago})
      |> Repo.update!()

      {:ok, _view, html} = live(conn, ~p"/workspaces/#{workspace.slug}")

      assert html =~ "days ago"
    end

    test "opens new project modal via live_patch", %{conn: conn, user: user} do
      workspace = workspace_fixture(user, %{name: "Modal Studio"})

      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.slug}")

      assert view
             |> element("a", "New Project")
             |> render_click()

      assert render(view) =~ "Project Name"
      assert render(view) =~ "new-project-modal"
    end

    test "new project modal renders via direct navigation", %{conn: conn, user: user} do
      workspace = workspace_fixture(user, %{name: "Direct Modal Studio"})

      {:ok, _view, html} = live(conn, ~p"/workspaces/#{workspace.slug}/projects/new")

      assert html =~ "New Project"
      assert html =~ "Project Name"
      assert html =~ "new-project-modal"
    end

    test "search event renders without crash", %{conn: conn, user: user} do
      workspace = workspace_fixture(user, %{name: "Search Studio"})

      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.slug}")

      html = render_change(view, "search", %{"search" => "some query"})
      assert html =~ "Search Studio"
    end

    test "project card links to project page", %{conn: conn, user: user} do
      workspace = workspace_fixture(user, %{name: "Link Studio"})

      project =
        project_fixture(user, %{name: "Linked Project", workspace: workspace})
        |> Repo.preload(:workspace)

      {:ok, _view, html} = live(conn, ~p"/workspaces/#{workspace.slug}")

      assert html =~ ~p"/workspaces/#{workspace.slug}/projects/#{project.slug}"
    end

    test "handle_info saved project redirects to project page", %{conn: conn, user: user} do
      workspace = workspace_fixture(user, %{name: "Save Studio"})

      {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.slug}/projects/new")

      # Submit the project form to trigger the handle_info callback
      view
      |> form("#project-form", project: %{name: "Created Project"})
      |> render_submit()

      {path, flash} = assert_redirect(view)
      assert path =~ "/workspaces/"
      assert path =~ "/projects/"
      assert flash["info"] =~ "Project created successfully"
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
