defmodule StoryarnWeb.FlowLive.IndexTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Repo

  defp get_dashboard_vue(view) do
    LiveVue.Test.get_vue(view, name: "modules/flows/dashboard/FlowDashboard")
  end

  describe "Flow index page" do
    setup :register_and_log_in_user

    test "renders page for owner", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      flow_fixture(project, %{name: "Chapter One"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows"
        )

      await_async(view)

      vue = get_dashboard_vue(view)
      assert vue.component == "modules/flows/dashboard/FlowDashboard"
      table_data = vue.props["table-data"]
      assert Enum.any?(table_data, fn row -> row["name"] == "Chapter One" end)
    end

    test "renders page for editor member", %{conn: conn, user: user} do
      owner = user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "editor")
      flow_fixture(project, %{name: "Shared Flow"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows"
        )

      await_async(view)

      vue = get_dashboard_vue(view)
      table_data = vue.props["table-data"]
      assert Enum.any?(table_data, fn row -> row["name"] == "Shared Flow" end)
    end

    test "redirects non-member", %{conn: conn} do
      owner = user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)

      {:error, {:redirect, %{to: path, flash: flash}}} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows"
        )

      assert path == "/workspaces"
      assert flash["error"] =~ "access"
    end

    test "renders empty table when no flows exist", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows"
        )

      await_async(view)

      vue = get_dashboard_vue(view)
      assert vue.props["table-data"] == []
    end

    test "passes stats to Vue when flows exist", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Main Story"})

      # Add a dialogue node to get word counts
      node_fixture(flow, %{type: "dialogue", data: %{"text" => "Hello world"}})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows"
        )

      await_async(view)

      vue = get_dashboard_vue(view)
      stats = vue.props["stats"]
      assert is_map(stats)
      table_data = vue.props["table-data"]
      assert Enum.any?(table_data, fn row -> row["name"] == "Main Story" end)
    end

    test "sort_flows event toggles table order", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      flow_fixture(project, %{name: "Alpha Flow"})
      flow_fixture(project, %{name: "Zeta Flow"})

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows")

      await_async(view)

      # Default: name asc — Alpha before Zeta
      vue = get_dashboard_vue(view)
      names = Enum.map(vue.props["table-data"], & &1["name"])
      alpha_pos = Enum.find_index(names, &(&1 == "Alpha Flow"))
      zeta_pos = Enum.find_index(names, &(&1 == "Zeta Flow"))
      assert alpha_pos < zeta_pos

      # Toggle sort via event — Zeta before Alpha
      render_click(view, "sort_flows", %{"column" => "name"})

      vue = get_dashboard_vue(view)
      names = Enum.map(vue.props["table-data"], & &1["name"])
      alpha_pos = Enum.find_index(names, &(&1 == "Alpha Flow"))
      zeta_pos = Enum.find_index(names, &(&1 == "Zeta Flow"))
      assert zeta_pos < alpha_pos
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
