defmodule StoryarnWeb.SheetLive.IndexTest do
  use StoryarnWeb.ConnCase, async: true

  import Ecto.Query
  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Phoenix.LiveView.Socket
  alias Storyarn.Platform.Dashboards.Cache, as: DashboardCache
  alias Storyarn.Repo
  alias Storyarn.Sheets
  alias StoryarnWeb.SheetLive.Index

  defp get_dashboard_vue(view) do
    LiveVue.Test.get_vue(view, name: "live/sheet/dashboard/SheetDashboard")
  end

  defp get_sidebar_live(view, project) do
    find_live_child(view, "sidebar-sheets-#{project.id}")
  end

  describe "Sheet index page" do
    setup :register_and_log_in_user

    test "redirects non-member", %{conn: conn} do
      owner = user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)

      {:error, {:redirect, %{to: path, flash: flash}}} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets"
        )

      assert path == "/workspaces"
      assert flash["error"] =~ "access"
    end

    test "completes the async overview for an empty project", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets")

      await_async(view)

      props = get_dashboard_vue(view).props
      assert props["overview-status"] == "ready"
      assert props["stats"]["sheet_count"] == 0
      assert props["pagination"]["total"] == 0
    end

    test "exposes the exact localizable word total to the dashboard", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Main Hero"})

      block_fixture(sheet, %{
        type: "rich_text",
        value: %{"content" => "<p>Brave northern explorer</p>"}
      })

      block_fixture(sheet, %{
        type: "text",
        is_constant: true,
        value: %{"content" => "Editor only words"}
      })

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets")

      await_async(view)

      vue = get_dashboard_vue(view)
      assert vue.props["stats"]["word_count"] == 5

      assert Enum.any?(vue.props["table-data"], fn row ->
               row["name"] == "Main Hero" and row["word_count"] == 5
             end)
    end

    test "refreshes the visible dashboard after a committed sheet update", %{
      conn: conn,
      user: user
    } do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Before"})

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets")

      await_async(view)
      assert "Before" in sheet_names(view)

      assert {:ok, _sheet} = Sheets.update_sheet(sheet, %{name: "After"})

      assert_dashboard_eventually(view, fn ->
        assert "After" in sheet_names(view)
        refute "Before" in sheet_names(view)
      end)
    end

    test "uses canonical sheet health codes and severities in the dashboard", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      missing_shortcut = sheet_fixture(project, %{name: "Missing Shortcut"})
      variable_sheet = sheet_fixture(project, %{name: "Unused Variable"})
      block_fixture(variable_sheet, %{type: "number", is_constant: false})

      Repo.update_all(
        from(sheet in Storyarn.Sheets.Sheet, where: sheet.id == ^missing_shortcut.id),
        set: [shortcut: nil]
      )

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets")

      await_async(view)

      issues = get_dashboard_vue(view).props["issues"]
      ids = Enum.map(issues, & &1["id"])

      assert %{"severity" => "error", "label" => "Missing Shortcut"} =
               Enum.find(issues, &(&1["code"] == "missing_sheet_shortcut"))

      assert %{"severity" => "info", "label" => "Missing Shortcut"} =
               Enum.find(issues, &(&1["code"] == "empty_leaf_sheet"))

      assert %{"severity" => "info", "label" => label} =
               Enum.find(issues, &(&1["code"] == "no_internal_variable_usages"))

      assert String.starts_with?(label, "Unused Variable · ")
      assert Enum.all?(ids, &is_binary/1)
      assert length(ids) == length(Enum.uniq(ids))

      assert %{"count" => 1} =
               Enum.find(
                 get_dashboard_vue(view).props["issue-filter-options"]["codes"],
                 &(&1["value"] == "missing_sheet_shortcut")
               )

      render_click(view, "filter_sheet_issues", %{
        "filter" => "code",
        "value" => "missing_sheet_shortcut"
      })

      props = get_dashboard_vue(view).props
      assert props["issue-pagination"]["page"] == 1
      assert props["issue-pagination"]["total"] == 1
      assert Enum.all?(props["issues"], &(&1["code"] == "missing_sheet_shortcut"))

      assert %{"value" => "error", "count" => 1} =
               Enum.find(
                 props["issue-filter-options"]["severities"],
                 &(&1["value"] == "error")
               )
    end

    test "keeps a total issue order and stable IDs across a real cache recomputation", %{
      conn: conn,
      user: user
    } do
      project = user |> project_fixture() |> Repo.preload(:workspace)

      for _index <- 1..26 do
        sheet_fixture(project, %{name: "Same Name", position: 0})
      end

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets")

      await_async(view)

      render_click(view, "filter_sheet_issues", %{
        "filter" => "code",
        "value" => "empty_leaf_sheet"
      })

      first_page_before = issue_identity(view)
      assert length(first_page_before) == 25

      render_click(view, "page_sheet_issues", %{"page" => 2})
      second_page_before = issue_identity(view)
      assert length(second_page_before) == 1

      ordered_before = first_page_before ++ second_page_before
      assert ordered_before == Enum.sort_by(ordered_before, &elem(&1, 0))

      DashboardCache.invalidate(project.id)
      send(view.pid, :load_dashboard_data)
      await_async(view)

      assert get_dashboard_vue(view).props["issue-pagination"]["page"] == 2
      assert issue_identity(view) == second_page_before

      render_click(view, "page_sheet_issues", %{"page" => 1})
      assert issue_identity(view) == first_page_before
    end

    test "an issues failure does not block the independently loaded overview", %{
      conn: conn,
      user: user
    } do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      sheet_fixture(project, %{name: "Any Sheet"})

      # The dashboard renders a skeleton until `stats` is non-nil, so ANY crash in
      # the async load used to show as "still loading", forever, with nothing in
      # the error tracker. How it crashes is incidental — poisoning one cached
      # value is just the cheapest way to make the real code path raise.
      DashboardCache.fetch(project.id, :sheet_issues, fn -> :not_a_list_of_findings end)

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets")

      await_async(view)

      stats = get_dashboard_vue(view).props["stats"]

      refute is_nil(stats), "the overview should finish even when the issues task fails"
      assert stats["sheet_count"] == 1
      assert get_dashboard_vue(view).props["issues"] == []
      assert get_dashboard_vue(view).props["issues-status"] == "error"
    end
  end

  describe "dashboard overview state" do
    test "an initial crash is an explicit error without fabricated stats" do
      socket = %Socket{
        assigns: %{
          __changed__: %{},
          flash: %{},
          project: %{id: 4242},
          dashboard_stats: nil,
          overview_status: :loading
        }
      }

      {:noreply, result} =
        Index.handle_async(:load_dashboard_overview, {:exit, :boom}, socket)

      assert result.assigns.dashboard_stats == nil
      assert result.assigns.overview_status == :error
    end

    test "retry immediately returns the overview to loading" do
      socket = %Socket{
        assigns: %{
          __changed__: %{},
          project: %{id: 4242, slug: "project"},
          workspace: %{slug: "workspace"},
          locale: "en",
          overview_status: :error,
          dashboard_overview_running?: false,
          dashboard_overview_reload_pending?: false
        }
      }

      {:noreply, result} = Index.handle_event("retry_dashboard_overview", %{}, socket)

      assert result.assigns.overview_status == :loading
      assert result.assigns.dashboard_overview_running?
      refute result.assigns.dashboard_overview_reload_pending?
    end
  end

  describe "Authentication" do
    test "unauthenticated user gets redirected to login", %{conn: conn} do
      assert {:error, redirect} =
               live(conn, ~p"/workspaces/some-ws/projects/some-proj/sheets")

      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/log-in"
      assert %{"error" => "You must log in to access this page."} = flash
    end
  end

  describe "create_sheet" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      ws = project.workspace
      url = ~p"/workspaces/#{ws.slug}/projects/#{project.slug}/sheets"
      %{project: project, workspace: ws, url: url}
    end

    test "creates a root sheet and navigates to it", %{conn: conn, url: url, project: project} do
      {:ok, view, _html} = live(conn, url)
      sidebar = get_sidebar_live(view, project)
      _ = await_async(view)

      render_click(sidebar, "create_sheet")
      {redirect_path, _flash} = assert_redirect(view)

      # Should redirect to the new sheet's show page
      assert redirect_path =~ "/sheets/"

      # Verify the sheet was created in the database
      sheets = Sheets.list_sheets_tree(project.id)
      assert length(sheets) == 1
      assert hd(sheets).name == "Untitled"
    end

    test "viewer cannot create sheet", %{conn: conn, user: user} do
      owner = user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      ws = project.workspace

      url = ~p"/workspaces/#{ws.slug}/projects/#{project.slug}/sheets"
      {:ok, view, _html} = live(conn, url)
      sidebar = get_sidebar_live(view, project)

      render_click(sidebar, "create_sheet")

      assert Sheets.list_sheets_tree(project.id) == []
    end
  end

  describe "delete_sheet" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      ws = project.workspace
      url = ~p"/workspaces/#{ws.slug}/projects/#{project.slug}/sheets"
      %{project: project, workspace: ws, url: url}
    end

    test "confirm_delete_sheet without pending id does nothing", %{
      conn: conn,
      url: url,
      project: project
    } do
      sheet = sheet_fixture(project, %{name: "Should Remain"})

      {:ok, view, _html} = live(conn, url)
      _ = await_async(view)
      sidebar = get_sidebar_live(view, project)

      render_click(sidebar, "confirm_delete_sheet")

      assert Sheets.get_sheet(project.id, sheet.id)
    end

    test "viewer cannot delete sheet", %{conn: conn, user: user} do
      owner = user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      ws = project.workspace

      sheet = sheet_fixture(project, %{name: "Protected Sheet"})
      url = ~p"/workspaces/#{ws.slug}/projects/#{project.slug}/sheets"

      {:ok, view, _html} = live(conn, url)
      _ = await_async(view)
      sidebar = get_sidebar_live(view, project)

      render_click(sidebar, "set_pending_delete_sheet", %{"id" => sheet.id})
      render_click(sidebar, "confirm_delete_sheet")

      assert Sheets.get_sheet(project.id, sheet.id)
    end
  end

  describe "move_sheet" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      ws = project.workspace
      url = ~p"/workspaces/#{ws.slug}/projects/#{project.slug}/sheets"
      %{project: project, workspace: ws, url: url}
    end

    test "moves a sheet to a new parent", %{
      conn: conn,
      url: url,
      project: project
    } do
      parent = sheet_fixture(project, %{name: "Parent"})
      child = sheet_fixture(project, %{name: "Child"})

      {:ok, view, _html} = live(conn, url)
      sidebar = get_sidebar_live(view, project)

      render_click(sidebar, "move_to_parent", %{
        "item_id" => child.id,
        "new_parent_id" => parent.id,
        "position" => 0
      })

      # Verify the tree updated: child is now under parent
      tree = Sheets.list_sheets_tree(project.id)
      parent_in_tree = Enum.find(tree, &(&1.id == parent.id))
      assert parent_in_tree
      assert Enum.any?(parent_in_tree.children, &(&1.id == child.id))
    end

    test "moves a sheet to root (nil parent)", %{
      conn: conn,
      url: url,
      project: project
    } do
      parent = sheet_fixture(project, %{name: "Parent"})
      child = child_sheet_fixture(project, parent, %{name: "Child"})

      {:ok, view, _html} = live(conn, url)
      sidebar = get_sidebar_live(view, project)

      render_click(sidebar, "move_to_parent", %{
        "item_id" => child.id,
        "new_parent_id" => nil,
        "position" => 0
      })

      # Verify both sheets are now at root level
      tree = Sheets.list_sheets_tree(project.id)
      root_ids = Enum.map(tree, & &1.id)
      assert parent.id in root_ids
      assert child.id in root_ids
    end

    test "rejects cyclic move (moving parent into own child)", %{
      conn: conn,
      url: url,
      project: project
    } do
      parent = sheet_fixture(project, %{name: "Parent"})
      child = child_sheet_fixture(project, parent, %{name: "Child"})

      {:ok, view, _html} = live(conn, url)
      sidebar = get_sidebar_live(view, project)

      render_click(sidebar, "move_to_parent", %{
        "item_id" => parent.id,
        "new_parent_id" => child.id,
        "position" => 0
      })

      updated_parent = Sheets.get_sheet(project.id, parent.id)
      assert updated_parent.parent_id == nil
    end

    test "viewer cannot move sheet", %{conn: conn, user: user} do
      owner = user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      ws = project.workspace

      sheet = sheet_fixture(project, %{name: "Immovable"})
      url = ~p"/workspaces/#{ws.slug}/projects/#{project.slug}/sheets"

      {:ok, view, _html} = live(conn, url)
      sidebar = get_sidebar_live(view, project)

      render_click(sidebar, "move_to_parent", %{
        "item_id" => sheet.id,
        "new_parent_id" => nil,
        "position" => 0
      })

      updated_sheet = Sheets.get_sheet(project.id, sheet.id)
      assert updated_sheet.parent_id == nil
    end
  end

  defp sheet_names(view) do
    view
    |> get_dashboard_vue()
    |> then(& &1.props["table-data"])
    |> Enum.map(& &1["name"])
  end

  defp issue_identity(view) do
    view
    |> get_dashboard_vue()
    |> then(& &1.props["issues"])
    |> Enum.map(&{&1["resource_id"], &1["id"]})
  end

  defp assert_dashboard_eventually(view, assertion, attempts \\ 200)

  defp assert_dashboard_eventually(view, assertion, attempts) when attempts > 1 do
    render(view)
    await_async(view)
    assertion.()
  rescue
    ExUnit.AssertionError ->
      Process.sleep(10)
      assert_dashboard_eventually(view, assertion, attempts - 1)
  end

  defp assert_dashboard_eventually(view, assertion, 1) do
    render(view)
    await_async(view)
    assertion.()
  end
end
