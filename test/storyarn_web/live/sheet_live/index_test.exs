defmodule StoryarnWeb.SheetLive.IndexTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.SheetsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Repo

  describe "Sheet index page" do
    setup :register_and_log_in_user

    test "renders page for owner", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet_fixture(project, %{name: "Character Sheet"})

      {:ok, _view, html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets"
        )

      assert html =~ "Sheets"
      assert html =~ "Character Sheet"
    end

    test "renders page for editor member", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "editor")
      sheet_fixture(project, %{name: "Shared Sheet"})

      {:ok, _view, html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets"
        )

      assert html =~ "Sheets"
      assert html =~ "Shared Sheet"
    end

    test "redirects non-member", %{conn: conn} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)

      {:error, {:redirect, %{to: path, flash: flash}}} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets"
        )

      assert path == "/workspaces"
      assert flash["error"] =~ "access"
    end

    test "renders empty state when no sheets exist", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)

      {:ok, _view, html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets"
        )

      assert html =~ "No sheets yet"
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
      project = project_fixture(user) |> Repo.preload(:workspace)
      ws = project.workspace
      url = ~p"/workspaces/#{ws.slug}/projects/#{project.slug}/sheets"
      %{project: project, workspace: ws, url: url}
    end

    test "creates a root sheet and navigates to it", %{conn: conn, url: url, project: project} do
      {:ok, view, _html} = live(conn, url)

      assert {:error, {:live_redirect, %{to: redirect_path}}} =
               render_click(view, "create_sheet")

      # Should redirect to the new sheet's show page
      assert redirect_path =~ "/sheets/"

      # Verify the sheet was created in the database
      sheets = Storyarn.Sheets.list_sheets_tree(project.id)
      assert length(sheets) == 1
      assert hd(sheets).name == "Untitled"
    end

    test "viewer cannot create sheet", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      ws = project.workspace

      url = ~p"/workspaces/#{ws.slug}/projects/#{project.slug}/sheets"
      {:ok, view, _html} = live(conn, url)

      view |> render_click("create_sheet")

      assert render(view) =~ "permission"
    end
  end

  describe "create_child_sheet" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      ws = project.workspace
      url = ~p"/workspaces/#{ws.slug}/projects/#{project.slug}/sheets"
      %{project: project, workspace: ws, url: url}
    end

    test "creates a child sheet under a parent", %{
      conn: conn,
      url: url,
      project: project
    } do
      parent = sheet_fixture(project, %{name: "Parent Sheet"})

      {:ok, view, _html} = live(conn, url)

      assert {:error, {:live_redirect, %{to: redirect_path}}} =
               render_click(view, "create_child_sheet", %{"parent-id" => parent.id})

      assert redirect_path =~ "/sheets/"

      # Verify the child sheet exists in the database
      tree = Storyarn.Sheets.list_sheets_tree(project.id)
      parent_in_tree = Enum.find(tree, &(&1.id == parent.id))
      assert length(parent_in_tree.children) == 1
      assert hd(parent_in_tree.children).name == "New Sheet"
    end
  end

  describe "delete_sheet" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      ws = project.workspace
      url = ~p"/workspaces/#{ws.slug}/projects/#{project.slug}/sheets"
      %{project: project, workspace: ws, url: url}
    end

    test "set_pending_delete_sheet assigns the pending delete id", %{
      conn: conn,
      url: url,
      project: project
    } do
      sheet = sheet_fixture(project, %{name: "To Delete"})

      {:ok, view, _html} = live(conn, url)

      render_click(view, "set_pending_delete_sheet", %{"id" => sheet.id})

      # The assign is internal, but we can verify by confirming the delete afterwards
      # which reads the pending_delete_id
      view |> render_click("confirm_delete_sheet")

      html = render(view)
      assert html =~ "Sheet deleted successfully"
      refute html =~ "To Delete"
    end

    test "confirm_delete_sheet without pending id does nothing", %{
      conn: conn,
      url: url,
      project: project
    } do
      sheet_fixture(project, %{name: "Should Remain"})

      {:ok, view, _html} = live(conn, url)

      render_click(view, "confirm_delete_sheet")

      html = render(view)
      assert html =~ "Should Remain"
    end

    test "delete_sheet removes sheet and updates tree", %{
      conn: conn,
      url: url,
      project: project
    } do
      sheet = sheet_fixture(project, %{name: "Delete Me"})

      {:ok, view, _html} = live(conn, url)
      assert render(view) =~ "Delete Me"

      render_click(view, "delete_sheet", %{"id" => sheet.id})

      html = render(view)
      assert html =~ "Sheet deleted successfully"
      refute html =~ "Delete Me"
    end

    test "viewer cannot delete sheet", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      ws = project.workspace

      sheet = sheet_fixture(project, %{name: "Protected Sheet"})
      url = ~p"/workspaces/#{ws.slug}/projects/#{project.slug}/sheets"

      {:ok, view, _html} = live(conn, url)

      render_click(view, "delete_sheet", %{"id" => sheet.id})

      html = render(view)
      assert html =~ "permission"
      assert html =~ "Protected Sheet"
    end
  end

  describe "move_sheet" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
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

      render_click(view, "move_sheet", %{
        "sheet_id" => child.id,
        "parent_id" => parent.id,
        "position" => 0
      })

      # Verify the tree updated: child is now under parent
      tree = Storyarn.Sheets.list_sheets_tree(project.id)
      parent_in_tree = Enum.find(tree, &(&1.id == parent.id))
      assert parent_in_tree != nil
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

      render_click(view, "move_sheet", %{
        "sheet_id" => child.id,
        "parent_id" => nil,
        "position" => 0
      })

      # Verify both sheets are now at root level
      tree = Storyarn.Sheets.list_sheets_tree(project.id)
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

      render_click(view, "move_sheet", %{
        "sheet_id" => parent.id,
        "parent_id" => child.id,
        "position" => 0
      })

      html = render(view)
      assert html =~ "Cannot move a sheet into its own children"
    end

    test "viewer cannot move sheet", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      ws = project.workspace

      sheet = sheet_fixture(project, %{name: "Immovable"})
      url = ~p"/workspaces/#{ws.slug}/projects/#{project.slug}/sheets"

      {:ok, view, _html} = live(conn, url)

      render_click(view, "move_sheet", %{
        "sheet_id" => sheet.id,
        "parent_id" => nil,
        "position" => 0
      })

      html = render(view)
      assert html =~ "permission"
    end
  end
end
