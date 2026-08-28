defmodule StoryarnWeb.ProjectLive.ShowTest do
  use StoryarnWeb.ConnCase, async: true

  import ExUnit.CaptureLog
  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Phoenix.LiveView.Socket
  alias Storyarn.Repo
  alias StoryarnWeb.ProjectLive.Show

  defp get_project_layout_vue(view) do
    LiveVue.Test.get_vue(view, name: "live/layouts/project/Layout")
  end

  defp get_dashboard_vue(view) do
    LiveVue.Test.get_vue(view, name: "live/project/dashboard/ProjectDashboard")
  end

  describe "Show" do
    setup :register_and_log_in_user

    test "renders project dashboard for owner", %{conn: conn, user: user} do
      project =
        user
        |> project_fixture(%{name: "My Project"})
        |> Repo.preload(:workspace)

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}")

      chrome = get_project_layout_vue(view).props["chrome"]
      assert chrome["projectName"] == "My Project"
      assert chrome["activeTool"] == "dashboard"
    end

    test "renders project dashboard for member", %{conn: conn, user: user} do
      owner = user_fixture()
      project = owner |> project_fixture(%{name: "Shared Project"}) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "editor")

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}")

      chrome = get_project_layout_vue(view).props["chrome"]
      assert chrome["projectName"] == "Shared Project"
    end

    test "redirects for non-member", %{conn: conn} do
      owner = user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)

      {:error, {:redirect, %{to: path, flash: flash}}} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}")

      assert path == "/workspaces"
      assert flash["error"] =~ "access"
    end

    test "shows tool switcher enabled", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}")

      chrome = get_project_layout_vue(view).props["chrome"]
      assert chrome["showToolSwitcher"] == true
    end
  end

  # ENG-25. The overview used to build `dgettext` sentences inside a `Task.async`
  # that does not inherit the Gettext locale, and cache them in a cross-user ETS
  # table. Sending counts makes both halves impossible.
  #
  # Note there is deliberately NO "renders in Spanish for a Spanish reader" test:
  # the bug was that the locale is *not* propagated into the task, so a broken
  # build serves English to everyone and an `en == es` assertion passes while
  # proving nothing. The guarantee that actually holds is that no string crosses
  # the boundary at all, which is what the first test asserts — verified by
  # injecting a `dgettext` sentence into the summary and watching it fail.
  describe "tool health payload" do
    setup :register_and_log_in_user

    test "sends per-tool counts and no server-rendered prose", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      flow = flow_fixture(project)

      entry =
        Repo.get_by(Storyarn.Projects.Persistence.FlowNodeRecord,
          flow_id: flow.id,
          type: "entry"
        )

      Repo.delete!(entry)

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}")

      render_async(view, 2000)
      tool_health = get_dashboard_vue(view).props["tool-health"]

      assert %{"flows" => flows, "sheets" => sheets, "scenes" => scenes} = tool_health

      # Every value is a number. A string here would be a sentence, and a
      # sentence is exactly the regression this replaced.
      for counts <- [flows, sheets, scenes], {_severity, value} <- counts do
        assert is_integer(value), "expected counts only, got #{inspect(value)}"
      end

      assert flows["error"] > 0
      assert flows["actionable"] >= flows["error"]
    end

    test "info-only findings leave a tool with nothing actionable", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      # An empty leaf sheet is `:info` — a note, not something to go fix.
      sheet_fixture(project)

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}")

      render_async(view, 2000)
      sheets = get_dashboard_vue(view).props["tool-health"]["sheets"]

      # The `:info` finding is still counted — it is not dropped, as the old
      # overview dropped every flow `:info` — it just does not read as a problem.
      assert sheets["info"] > 0
      assert sheets["actionable"] == 0
    end
  end

  # ENG-25. `handle_info(:load_dashboard_data)` was a `Task.await_many(15_000)`:
  # it blocked the LiveView process, and because a failure was never cached the
  # remount retried it into a crash loop. Loading is now async and each half
  # fails independently.
  describe "async loading" do
    setup :register_and_log_in_user

    test "mounts before the data arrives instead of blocking on it", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}")

      # Props are readable at mount — the process is not stuck inside an await.
      props = get_dashboard_vue(view).props
      assert props["overview-status"] in ["loading", "ready"]
      assert props["issues-status"] in ["loading", "ready"]

      render_async(view, 2000)
      props = get_dashboard_vue(view).props

      assert props["overview-status"] == "ready"
      assert props["issues-status"] == "ready"
      assert props["stats"]["sheet_count"] == 0
    end

    test "a crashed health load logs the reason and offers a retry, not a crash loop" do
      socket = %Socket{
        assigns: %{
          __changed__: %{},
          flash: %{},
          project: %{id: 4242},
          tool_health: nil,
          issues_status: :loading
        }
      }

      {result, log} =
        with_log(fn ->
          {:noreply, result} = Show.handle_async(:load_dashboard_issues, {:exit, :boom}, socket)
          result
        end)

      assert log =~ "Project dashboard health load failed for project 4242"
      assert log =~ ":boom"
      assert result.assigns.issues_status == :error
      assert result.assigns.tool_health == nil
    end

    test "a failed refresh keeps the last counts and marks them stale" do
      counts = %{flows: %{error: 1, warning: 0, info: 0, actionable: 1}}

      socket = %Socket{
        assigns: %{
          __changed__: %{},
          flash: %{},
          project: %{id: 4242},
          tool_health: counts,
          issues_status: :refreshing
        }
      }

      {:noreply, result} = Show.handle_async(:load_dashboard_issues, {:exit, :boom}, socket)

      assert result.assigns.tool_health == counts
      assert result.assigns.issues_status == :stale
    end

    test "retry returns the health section to loading" do
      socket = %Socket{
        assigns: %{
          __changed__: %{},
          project: %{id: 4242},
          issues_status: :error,
          dashboard_issues_running?: false,
          dashboard_issues_reload_pending?: false
        }
      }

      {:noreply, result} = Show.handle_event("retry_dashboard_issues", %{}, socket)

      assert result.assigns.issues_status == :loading
      assert result.assigns.dashboard_issues_running?
    end

    test "the overview and the health section fail independently" do
      socket = %Socket{
        assigns: %{
          __changed__: %{},
          flash: %{},
          project: %{id: 4242},
          stats: %{sheet_count: 3},
          activity: [],
          tool_health: nil,
          overview_status: :ready,
          issues_status: :loading
        }
      }

      {result, _log} =
        with_log(fn ->
          {:noreply, result} = Show.handle_async(:load_dashboard_issues, {:exit, :boom}, socket)
          result
        end)

      # Health died; the stats the reader can already see are untouched.
      assert result.assigns.issues_status == :error
      assert result.assigns.overview_status == :ready
      assert result.assigns.stats == %{sheet_count: 3}
    end
  end
end
