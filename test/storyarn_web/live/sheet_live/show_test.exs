defmodule StoryarnWeb.SheetLive.ShowTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.SheetsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Repo
  alias Storyarn.Sheets

  describe "Sheet show" do
    setup :register_and_log_in_user

    test "renders sheet for owner", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Test Sheet"})

      {:ok, _view, html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}"
        )

      assert html =~ "Test Sheet"
    end

    test "renders sheet for editor member", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "editor")
      sheet = sheet_fixture(project, %{name: "Shared Sheet"})

      {:ok, _view, html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}"
        )

      assert html =~ "Shared Sheet"
    end

    test "redirects for non-member", %{conn: conn} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project)

      {:error, {:redirect, %{to: path, flash: flash}}} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}"
        )

      assert path == "/workspaces"
      assert flash["error"] =~ "access"
    end
  end

  describe "move_sheet event" do
    setup :register_and_log_in_user

    test "moves sheet to new parent", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet1 = sheet_fixture(project, %{name: "Sheet 1"})
      sheet2 = sheet_fixture(project, %{name: "Sheet 2"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{sheet1.id}"
        )

      # Simulate move_sheet event
      render_hook(view, "move_sheet", %{
        "sheet_id" => sheet2.id,
        "parent_id" => sheet1.id,
        "position" => 0
      })

      # Verify sheet was moved
      updated_sheet = Sheets.get_sheet(project.id, sheet2.id)
      assert updated_sheet.parent_id == sheet1.id
    end

    test "moves sheet to root level", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      parent = sheet_fixture(project, %{name: "Parent"})
      child = sheet_fixture(project, %{name: "Child", parent_id: parent.id})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{child.id}"
        )

      # Move to root level (empty parent_id)
      render_hook(view, "move_sheet", %{
        "sheet_id" => child.id,
        "parent_id" => "",
        "position" => 0
      })

      # Verify sheet was moved to root
      updated_sheet = Sheets.get_sheet(project.id, child.id)
      assert updated_sheet.parent_id == nil
    end

    test "prevents cycle creation", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      parent = sheet_fixture(project, %{name: "Parent"})
      child = sheet_fixture(project, %{name: "Child", parent_id: parent.id})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{parent.id}"
        )

      # Try to move parent under its child (would create cycle)
      render_hook(view, "move_sheet", %{
        "sheet_id" => parent.id,
        "parent_id" => child.id,
        "position" => 0
      })

      # Verify sheet was NOT moved
      updated_sheet = Sheets.get_sheet(project.id, parent.id)
      assert updated_sheet.parent_id == nil
    end

    test "viewer cannot move sheets", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      sheet1 = sheet_fixture(project, %{name: "Sheet 1"})
      sheet2 = sheet_fixture(project, %{name: "Sheet 2"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{sheet1.id}"
        )

      # Try to move sheet
      render_hook(view, "move_sheet", %{
        "sheet_id" => sheet2.id,
        "parent_id" => sheet1.id,
        "position" => 0
      })

      # Verify sheet was NOT moved
      updated_sheet = Sheets.get_sheet(project.id, sheet2.id)
      assert updated_sheet.parent_id == nil
    end
  end

  describe "create_child_sheet event" do
    setup :register_and_log_in_user

    test "creates child sheet", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      parent = sheet_fixture(project, %{name: "Parent"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{parent.id}"
        )

      # Get initial sheet count
      initial_tree = Sheets.list_sheets_tree(project.id)
      initial_count = count_sheets(initial_tree)

      # Create child sheet
      render_hook(view, "create_child_sheet", %{"parent-id" => parent.id})

      # Verify new sheet was created
      updated_tree = Sheets.list_sheets_tree(project.id)
      assert count_sheets(updated_tree) == initial_count + 1

      # Verify it's a child of parent
      parent_sheet = Sheets.get_sheet_with_descendants(project.id, parent.id)
      assert length(parent_sheet.children) == 1
    end

    test "viewer cannot create child sheets", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      parent = sheet_fixture(project, %{name: "Parent"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{parent.id}"
        )

      # Get initial sheet count
      initial_tree = Sheets.list_sheets_tree(project.id)
      initial_count = count_sheets(initial_tree)

      # Try to create child sheet
      render_hook(view, "create_child_sheet", %{"parent-id" => parent.id})

      # Verify sheet was NOT created
      updated_tree = Sheets.list_sheets_tree(project.id)
      assert count_sheets(updated_tree) == initial_count
    end
  end

  defp count_sheets(sheets) when is_list(sheets) do
    Enum.reduce(sheets, 0, fn sheet, acc ->
      acc + 1 + count_sheets(Map.get(sheet, :children, []))
    end)
  end
end
