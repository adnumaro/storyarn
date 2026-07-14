defmodule StoryarnWeb.SheetLive.IndexTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Repo
  alias Storyarn.Sheets

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
end
