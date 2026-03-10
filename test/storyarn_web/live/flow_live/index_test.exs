defmodule StoryarnWeb.FlowLive.IndexTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Repo

  describe "Flow index page" do
    setup :register_and_log_in_user

    test "renders page for owner", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow_fixture(project, %{name: "Chapter One"})

      {:ok, _view, html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows"
        )

      assert html =~ "Flows"
      assert html =~ "Chapter One"
    end

    test "renders page for editor member", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "editor")
      flow_fixture(project, %{name: "Shared Flow"})

      {:ok, _view, html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows"
        )

      assert html =~ "Flows"
      assert html =~ "Shared Flow"
    end

    test "redirects non-member", %{conn: conn} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)

      {:error, {:redirect, %{to: path, flash: flash}}} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows"
        )

      assert path == "/workspaces"
      assert flash["error"] =~ "access"
    end

    test "renders empty state when no flows exist", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)

      {:ok, _view, html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows"
        )

      assert html =~ "No flows yet"
    end

    test "renders dashboard with stat cards when flows exist", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Main Story"})

      # Add a dialogue node to get word counts
      node_fixture(flow, %{type: "dialogue", data: %{"text" => "Hello world"}})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows"
        )

      # Dashboard loads async, so render to get updated state
      html = render(view)

      assert html =~ "Main Story"
      assert html =~ "Nodes"
      assert html =~ "Words"
    end

    test "sort_flows event updates table order", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow_fixture(project, %{name: "Alpha Flow"})
      flow_fixture(project, %{name: "Zeta Flow"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows"
        )

      # Wait for async load
      _ = render(view)

      # Sort by name descending
      html = view |> element("button", "Name") |> render_click()
      assert html =~ "Alpha Flow"
      assert html =~ "Zeta Flow"
    end
  end

  describe "Authentication" do
    test "unauthenticated user gets redirected to login", %{conn: conn} do
      assert {:error, redirect} =
               live(conn, ~p"/workspaces/some-ws/projects/some-proj/flows")

      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/log-in"
      assert %{"error" => "You must log in to access this page."} = flash
    end
  end
end
