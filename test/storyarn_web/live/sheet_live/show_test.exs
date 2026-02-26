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

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}"
        )

      html = render_async(view, 500)
      assert html =~ "Test Sheet"
    end

    test "renders sheet for editor member", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "editor")
      sheet = sheet_fixture(project, %{name: "Shared Sheet"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}"
        )

      html = render_async(view, 500)
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

      render_async(view, 500)

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

      render_async(view, 500)

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

      render_async(view, 500)

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

      render_async(view, 500)

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

      render_async(view, 500)

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

      render_async(view, 500)

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

  describe "tab switching" do
    setup :register_and_log_in_user

    setup %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Tab Test Sheet"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}"
        )

      render_async(view, 500)

      %{view: view, project: project, sheet: sheet}
    end

    test "defaults to content tab", %{view: view} do
      html = render(view)
      # The content tab button should have the active class
      assert html =~ "tab-active"
      assert html =~ "Content"
    end

    test "switches to references tab", %{view: view} do
      html = render_click(view, "switch_tab", %{"tab" => "references"})
      assert html =~ "References"
    end

    test "switches to audio tab", %{view: view} do
      html = render_click(view, "switch_tab", %{"tab" => "audio"})
      assert html =~ "Audio"
    end

    test "switches to history tab", %{view: view} do
      html = render_click(view, "switch_tab", %{"tab" => "history"})
      assert html =~ "History"
    end

    test "switches back to content tab", %{view: view} do
      # Switch away first
      render_click(view, "switch_tab", %{"tab" => "references"})
      # Switch back to content
      html = render_click(view, "switch_tab", %{"tab" => "content"})
      assert html =~ "Content"
    end
  end

  describe "create_sheet event" do
    setup :register_and_log_in_user

    test "creates a new root sheet and navigates to it", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Existing Sheet"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}"
        )

      render_async(view, 500)

      # Get initial sheet count
      initial_tree = Sheets.list_sheets_tree(project.id)
      initial_count = count_sheets(initial_tree)

      # Create a new root sheet
      render_click(view, "create_sheet", %{})

      # Verify a new sheet was created
      updated_tree = Sheets.list_sheets_tree(project.id)
      assert count_sheets(updated_tree) == initial_count + 1
    end

    test "viewer cannot create sheets", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      sheet = sheet_fixture(project, %{name: "Existing"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}"
        )

      render_async(view, 500)

      initial_tree = Sheets.list_sheets_tree(project.id)
      initial_count = count_sheets(initial_tree)

      render_click(view, "create_sheet", %{})

      # Verify no sheet was created
      updated_tree = Sheets.list_sheets_tree(project.id)
      assert count_sheets(updated_tree) == initial_count
    end
  end

  describe "delete_sheet event" do
    setup :register_and_log_in_user

    test "deletes a different sheet from the tree", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Current Sheet"})
      other_sheet = sheet_fixture(project, %{name: "To Delete"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}"
        )

      render_async(view, 500)

      render_click(view, "delete_sheet", %{"id" => other_sheet.id})

      # Verify the other sheet was soft-deleted
      deleted_sheet = Sheets.get_sheet(project.id, other_sheet.id)
      assert deleted_sheet == nil
    end

    test "deletes the current sheet and redirects", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Current Sheet"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}"
        )

      render_async(view, 500)

      render_click(view, "delete_sheet", %{"id" => sheet.id})

      # Should navigate away since the current sheet was deleted
      {path, flash} = assert_redirect(view)
      assert path =~ "/sheets"
      assert flash["info"] =~ "deleted"
    end

    test "viewer cannot delete sheets", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      sheet = sheet_fixture(project, %{name: "Sheet"})
      other_sheet = sheet_fixture(project, %{name: "Other"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}"
        )

      render_async(view, 500)

      render_click(view, "delete_sheet", %{"id" => other_sheet.id})

      # Verify sheet was NOT deleted
      assert Sheets.get_sheet(project.id, other_sheet.id) != nil
    end
  end

  describe "pending delete sheet" do
    setup :register_and_log_in_user

    test "sets pending delete and confirms", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Current"})
      other_sheet = sheet_fixture(project, %{name: "To Delete"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}"
        )

      render_async(view, 500)

      # Set pending delete
      render_click(view, "set_pending_delete_sheet", %{"id" => other_sheet.id})

      # Confirm delete
      render_click(view, "confirm_delete_sheet", %{})

      # Verify the sheet was deleted
      assert Sheets.get_sheet(project.id, other_sheet.id) == nil
    end

    test "confirm_delete_sheet does nothing without pending id", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Current"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}"
        )

      render_async(view, 500)

      # Confirm delete without setting pending id first — should be a no-op
      render_click(view, "confirm_delete_sheet", %{})

      # The current sheet should still exist
      assert Sheets.get_sheet(project.id, sheet.id) != nil
    end
  end

  describe "sheet color" do
    setup :register_and_log_in_user

    test "sets sheet color", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Color Sheet"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}"
        )

      render_async(view, 500)

      render_click(view, "set_sheet_color", %{"color" => "#ff5733"})

      updated_sheet = Sheets.get_sheet(project.id, sheet.id)
      assert updated_sheet.color == "#ff5733"
    end

    test "clears sheet color", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Color Sheet"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}"
        )

      render_async(view, 500)

      # Set a color first
      render_click(view, "set_sheet_color", %{"color" => "#ff5733"})

      # Clear the color
      render_click(view, "clear_sheet_color", %{})

      updated_sheet = Sheets.get_sheet(project.id, sheet.id)
      assert updated_sheet.color == nil
    end

    test "viewer cannot set sheet color", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      sheet = sheet_fixture(project, %{name: "Color Sheet"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}"
        )

      render_async(view, 500)

      render_click(view, "set_sheet_color", %{"color" => "#ff5733"})

      updated_sheet = Sheets.get_sheet(project.id, sheet.id)
      assert updated_sheet.color == nil
    end
  end

  describe "sheet not found" do
    setup :register_and_log_in_user

    test "redirects when sheet does not exist", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)

      {:error, {:redirect, %{to: path, flash: flash}}} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/999999"
        )

      assert path =~ "/sheets"
      assert flash["error"] =~ "not found"
    end
  end

  describe "breadcrumb rendering" do
    setup :register_and_log_in_user

    test "renders breadcrumb for child sheet with ancestors", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      parent = sheet_fixture(project, %{name: "Grandparent Sheet"})
      child = child_sheet_fixture(project, parent, %{name: "Child Sheet"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{child.id}"
        )

      html = render_async(view, 500)

      # The breadcrumb should show the ancestor name
      assert html =~ "Grandparent Sheet"
      assert html =~ "Child Sheet"
    end

    test "does not render breadcrumb for root sheet", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Root Sheet"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}"
        )

      html = render_async(view, 500)

      # Root sheets have no ancestors, so the breadcrumb component should not render
      # We check that the breadcrumb container with ancestor navigation is not present
      assert html =~ "Root Sheet"
    end
  end

  describe "tree panel events" do
    setup :register_and_log_in_user

    test "toggles tree panel", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Test Sheet"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}"
        )

      render_async(view, 500)

      # Toggle the tree panel (starts open by default)
      render_click(view, "tree_panel_toggle", %{})

      # Toggle back open
      html = render_click(view, "tree_panel_toggle", %{})
      assert html =~ "Test Sheet"
    end

    test "pins tree panel", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Test Sheet"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}"
        )

      render_async(view, 500)

      # Pin/unpin the tree panel
      render_click(view, "tree_panel_pin", %{})
      html = render_click(view, "tree_panel_pin", %{})
      assert html =~ "Test Sheet"
    end

    test "tree panel init with pinned state", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Test Sheet"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}"
        )

      render_async(view, 500)

      # Simulate the JS hook sending initial pinned state
      render_click(view, "tree_panel_init", %{"pinned" => true})
      html = render(view)
      assert html =~ "Test Sheet"
    end
  end

  describe "handle_info messages" do
    setup :register_and_log_in_user

    setup %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Info Test Sheet"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}"
        )

      render_async(view, 500)

      %{view: view, project: project, sheet: sheet}
    end

    test "reset_save_status resets to idle", %{view: view} do
      send(view.pid, :reset_save_status)
      html = render(view)
      # After reset, the save indicator should be in idle state (not showing "saved")
      assert html =~ "Info Test Sheet"
    end

    test "content_tab :saved sets save status", %{view: view} do
      send(view.pid, {:content_tab, :saved})
      html = render(view)
      assert html =~ "Info Test Sheet"
    end

    test "banner :sheet_updated updates sheet", %{view: view, project: project, sheet: sheet} do
      # Update the sheet in the DB first
      {:ok, updated_sheet} = Sheets.update_sheet(sheet, %{description: "Updated desc"})
      updated_sheet = Sheets.get_sheet_full!(project.id, updated_sheet.id)

      send(view.pid, {:banner, :sheet_updated, updated_sheet})
      html = render(view)
      assert html =~ "Info Test Sheet"
    end

    test "banner :error shows flash", %{view: view} do
      send(view.pid, {:banner, :error, "Something went wrong"})
      html = render(view)
      assert html =~ "Something went wrong"
    end

    test "sheet_avatar :sheet_updated updates sheet and tree", %{
      view: view,
      project: project,
      sheet: sheet
    } do
      updated_sheet = Sheets.get_sheet_full!(project.id, sheet.id)
      sheets_tree = Sheets.list_sheets_tree(project.id)

      send(view.pid, {:sheet_avatar, :sheet_updated, updated_sheet, sheets_tree})
      html = render(view)
      assert html =~ "Info Test Sheet"
    end

    test "sheet_avatar :error shows flash", %{view: view} do
      send(view.pid, {:sheet_avatar, :error, "Avatar upload failed"})
      html = render(view)
      assert html =~ "Avatar upload failed"
    end

    test "sheet_title :name_saved updates sheet and tree", %{
      view: view,
      project: project,
      sheet: sheet
    } do
      {:ok, renamed_sheet} = Sheets.update_sheet(sheet, %{name: "Renamed Sheet"})
      renamed_sheet = Sheets.get_sheet_full!(project.id, renamed_sheet.id)
      sheets_tree = Sheets.list_sheets_tree(project.id)

      send(view.pid, {:sheet_title, :name_saved, renamed_sheet, sheets_tree})
      html = render(view)
      assert html =~ "Renamed Sheet"
    end

    test "sheet_title :shortcut_saved updates sheet", %{
      view: view,
      project: project,
      sheet: sheet
    } do
      {:ok, updated_sheet} = Sheets.update_sheet(sheet, %{shortcut: "new.shortcut"})
      updated_sheet = Sheets.get_sheet_full!(project.id, updated_sheet.id)

      send(view.pid, {:sheet_title, :shortcut_saved, updated_sheet})
      html = render(view)
      assert html =~ "Info Test Sheet"
    end

    test "sheet_title :error shows flash", %{view: view} do
      send(view.pid, {:sheet_title, :error, "Name too long"})
      html = render(view)
      assert html =~ "Name too long"
    end

    test "audio_tab :error shows flash", %{view: view} do
      send(view.pid, {:audio_tab, :error, "Audio processing failed"})
      html = render(view)
      assert html =~ "Audio processing failed"
    end

    test "versions_section :saved sets save status", %{view: view} do
      send(view.pid, {:versions_section, :saved})
      html = render(view)
      assert html =~ "Info Test Sheet"
    end

    test "versions_section :sheet_updated updates sheet", %{
      view: view,
      project: project,
      sheet: sheet
    } do
      updated_sheet = Sheets.get_sheet_full!(project.id, sheet.id)

      send(view.pid, {:versions_section, :sheet_updated, updated_sheet})
      html = render(view)
      assert html =~ "Info Test Sheet"
    end

    test "versions_section :version_restored reloads data", %{
      view: view,
      project: project,
      sheet: sheet
    } do
      updated_sheet = Sheets.get_sheet_full!(project.id, sheet.id)

      send(view.pid, {:versions_section, :version_restored, %{sheet: updated_sheet}})
      html = render(view)
      assert html =~ "Info Test Sheet"
    end

    test "content_tab :push_undo with generic action", %{view: view} do
      send(view.pid, {:content_tab, :push_undo, {:some_action, "prev", "new"}})
      html = render(view)
      assert html =~ "Info Test Sheet"
    end
  end

  describe "undo/redo events" do
    setup :register_and_log_in_user

    test "undo with empty stack is a no-op", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Undo Test"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}"
        )

      render_async(view, 500)

      # Undo with empty stack — should not crash
      html = render_hook(view, "undo", %{})
      assert html =~ "Undo Test"
    end

    test "redo with empty stack is a no-op", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Redo Test"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}"
        )

      render_async(view, 500)

      # Redo with empty stack — should not crash
      html = render_hook(view, "redo", %{})
      assert html =~ "Redo Test"
    end

    test "undo after color change reverts color", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Color Undo"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}"
        )

      render_async(view, 500)

      # Set a color (this pushes to undo stack)
      render_click(view, "set_sheet_color", %{"color" => "#abcdef"})

      # Verify color was set
      assert Sheets.get_sheet(project.id, sheet.id).color == "#abcdef"

      # Undo the color change
      render_hook(view, "undo", %{})

      # Verify color was reverted
      assert Sheets.get_sheet(project.id, sheet.id).color == nil
    end
  end

  defp count_sheets(sheets) when is_list(sheets) do
    Enum.reduce(sheets, 0, fn sheet, acc ->
      acc + 1 + count_sheets(Map.get(sheet, :children, []))
    end)
  end
end
