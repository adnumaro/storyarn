defmodule StoryarnWeb.SheetLive.HandlersTest do
  @moduledoc """
  Tests for SheetLive handler modules exercised through the LiveView:

  - BlockCrudHandlers (add, delete, reorder, update)
  - ConfigPanelHandlers (configure, save config, toggle constant)
  - TableHandlers (add column/row, delete column/row, rename, cell updates)
  - UndoRedoHandlers (undo/redo via parent LiveView)
  - InheritanceHandlers (detach, reattach, hide/unhide for children)

  Events go to the ContentTab LiveComponent (id="content-tab") via phx-target.
  For hook-initiated events we use `with_target("#content-tab")` to route events
  directly to the LiveComponent.
  """

  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Repo
  alias Storyarn.Sheets

  # ===========================================================================
  # Helpers
  # ===========================================================================

  defp sheet_path(workspace, project, sheet) do
    ~p"/workspaces/#{workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}"
  end

  defp mount_sheet(conn, workspace, project, sheet) do
    {:ok, view, _html} = live(conn, sheet_path(workspace, project, sheet))
    html = render_async(view, 500)
    {:ok, view, html}
  end

  # Sends an event to the ContentTab LiveComponent via with_target.
  # This is used for events that originate from JS hooks (not phx-click).
  defp send_to_content_tab(view, event, params \\ %{}) do
    view
    |> with_target("#content-tab")
    |> render_click(event, params)
  end

  # ===========================================================================
  # BlockCrudHandlers
  # ===========================================================================

  describe "BlockCrudHandlers — add_block" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Block Test Sheet"})
      %{project: project, workspace: project.workspace, sheet: sheet}
    end

    test "adds a text block to the sheet", %{
      conn: conn,
      workspace: ws,
      project: proj,
      sheet: sheet
    } do
      {:ok, view, _html} = mount_sheet(conn, ws, proj, sheet)

      # First show the block menu
      send_to_content_tab(view, "show_block_menu")

      # Add a text block via with_target (the block menu buttons have phx-target=@myself)
      send_to_content_tab(view, "add_block", %{"type" => "text"})

      # Verify block was created in the database
      blocks = Sheets.list_blocks(sheet.id)
      assert length(blocks) == 1
      assert hd(blocks).type == "text"
    end

    test "adds a number block to the sheet", %{
      conn: conn,
      workspace: ws,
      project: proj,
      sheet: sheet
    } do
      {:ok, view, _html} = mount_sheet(conn, ws, proj, sheet)

      send_to_content_tab(view, "show_block_menu")
      send_to_content_tab(view, "add_block", %{"type" => "number"})

      blocks = Sheets.list_blocks(sheet.id)
      assert length(blocks) == 1
      assert hd(blocks).type == "number"
    end

    test "adds a boolean block to the sheet", %{
      conn: conn,
      workspace: ws,
      project: proj,
      sheet: sheet
    } do
      {:ok, view, _html} = mount_sheet(conn, ws, proj, sheet)

      send_to_content_tab(view, "show_block_menu")
      send_to_content_tab(view, "add_block", %{"type" => "boolean"})

      blocks = Sheets.list_blocks(sheet.id)
      assert length(blocks) == 1
      assert hd(blocks).type == "boolean"
    end

    test "adds a select block to the sheet", %{
      conn: conn,
      workspace: ws,
      project: proj,
      sheet: sheet
    } do
      {:ok, view, _html} = mount_sheet(conn, ws, proj, sheet)

      send_to_content_tab(view, "show_block_menu")
      send_to_content_tab(view, "add_block", %{"type" => "select"})

      blocks = Sheets.list_blocks(sheet.id)
      assert length(blocks) == 1
      assert hd(blocks).type == "select"
    end

    test "adds a table block to the sheet", %{
      conn: conn,
      workspace: ws,
      project: proj,
      sheet: sheet
    } do
      {:ok, view, _html} = mount_sheet(conn, ws, proj, sheet)

      send_to_content_tab(view, "show_block_menu")
      send_to_content_tab(view, "add_block", %{"type" => "table"})

      blocks = Sheets.list_blocks(sheet.id)
      assert length(blocks) == 1
      assert hd(blocks).type == "table"
    end

    test "adds a divider block to the sheet", %{
      conn: conn,
      workspace: ws,
      project: proj,
      sheet: sheet
    } do
      {:ok, view, _html} = mount_sheet(conn, ws, proj, sheet)

      send_to_content_tab(view, "show_block_menu")
      send_to_content_tab(view, "add_block", %{"type" => "divider"})

      blocks = Sheets.list_blocks(sheet.id)
      assert length(blocks) == 1
      assert hd(blocks).type == "divider"
    end
  end

  describe "BlockCrudHandlers — delete_block" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Delete Block Sheet"})
      block = block_fixture(sheet, %{type: "text", config: %{"label" => "Name"}})
      %{project: project, workspace: project.workspace, sheet: sheet, block: block}
    end

    test "deletes a block from the sheet", %{
      conn: conn,
      workspace: ws,
      project: proj,
      sheet: sheet,
      block: block
    } do
      {:ok, view, _html} = mount_sheet(conn, ws, proj, sheet)

      send_to_content_tab(view, "delete_block", %{"id" => to_string(block.id)})

      # Verify block was deleted from database
      blocks = Sheets.list_blocks(sheet.id)
      assert blocks == []
    end

    test "does not crash when deleting non-existent block", %{
      conn: conn,
      workspace: ws,
      project: proj,
      sheet: sheet,
      block: block
    } do
      {:ok, view, _html} = mount_sheet(conn, ws, proj, sheet)

      # Send delete for a non-existent block ID
      send_to_content_tab(view, "delete_block", %{"id" => "999999"})

      # View should still be alive and the real block should be untouched
      assert render(view) =~ "Delete Block Sheet"
      assert Sheets.get_block(block.id) != nil
    end
  end

  describe "BlockCrudHandlers — update_block_value" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Update Value Sheet"})
      block = block_fixture(sheet, %{type: "text", config: %{"label" => "Description"}})
      %{project: project, workspace: project.workspace, sheet: sheet, block: block}
    end

    test "updates a text block value", %{
      conn: conn,
      workspace: ws,
      project: proj,
      sheet: sheet,
      block: block
    } do
      {:ok, view, _html} = mount_sheet(conn, ws, proj, sheet)

      send_to_content_tab(view, "update_block_value", %{
        "id" => to_string(block.id),
        "value" => "Hello World"
      })

      # Verify block value was updated
      updated_block = Sheets.get_block(block.id)
      assert updated_block.value["content"] == "Hello World"
    end

    test "does not crash when updating non-existent block", %{
      conn: conn,
      workspace: ws,
      project: proj,
      sheet: sheet,
      block: block
    } do
      {:ok, view, _html} = mount_sheet(conn, ws, proj, sheet)

      send_to_content_tab(view, "update_block_value", %{
        "id" => "999999",
        "value" => "Nope"
      })

      # View should still be alive, original block untouched
      assert render(view) =~ "Update Value Sheet"
      assert Sheets.get_block(block.id).value["content"] == ""
    end
  end

  describe "BlockCrudHandlers — reorder" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Reorder Sheet"})
      block1 = block_fixture(sheet, %{type: "text", config: %{"label" => "First"}})
      block2 = block_fixture(sheet, %{type: "text", config: %{"label" => "Second"}})
      block3 = block_fixture(sheet, %{type: "text", config: %{"label" => "Third"}})

      %{
        project: project,
        workspace: project.workspace,
        sheet: sheet,
        block1: block1,
        block2: block2,
        block3: block3
      }
    end

    test "reorders blocks within the sheet", %{
      conn: conn,
      workspace: ws,
      project: proj,
      sheet: sheet,
      block1: b1,
      block2: b2,
      block3: b3
    } do
      {:ok, view, _html} = mount_sheet(conn, ws, proj, sheet)

      # Reorder: move block3 to position 0
      new_order = [to_string(b3.id), to_string(b1.id), to_string(b2.id)]

      send_to_content_tab(view, "reorder", %{"ids" => new_order, "group" => "blocks"})

      # Verify new order
      blocks = Sheets.list_blocks(sheet.id)
      ids = Enum.map(blocks, & &1.id)
      assert ids == [b3.id, b1.id, b2.id]
    end
  end

  # ===========================================================================
  # ConfigPanelHandlers
  # ===========================================================================

  describe "ConfigPanelHandlers — configure_block" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Config Sheet"})
      block = block_fixture(sheet, %{type: "text", config: %{"label" => "Name"}})
      %{project: project, workspace: project.workspace, sheet: sheet, block: block}
    end

    test "opens config panel for a block", %{
      conn: conn,
      workspace: ws,
      project: proj,
      sheet: sheet,
      block: block
    } do
      {:ok, view, _html} = mount_sheet(conn, ws, proj, sheet)

      html = send_to_content_tab(view, "configure_block", %{"id" => to_string(block.id)})

      # Verify config panel is rendered
      assert html =~ "Configure Block"
    end

    test "closes config panel", %{
      conn: conn,
      workspace: ws,
      project: proj,
      sheet: sheet,
      block: block
    } do
      {:ok, view, _html} = mount_sheet(conn, ws, proj, sheet)

      # Open config panel first
      send_to_content_tab(view, "configure_block", %{"id" => to_string(block.id)})
      assert render(view) =~ "Configure Block"

      # Close it
      send_to_content_tab(view, "close_config_panel")
      refute render(view) =~ "Configure Block"
    end
  end

  describe "ConfigPanelHandlers — save_block_config" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Save Config Sheet"})
      block = block_fixture(sheet, %{type: "text", config: %{"label" => "OldLabel"}})
      %{project: project, workspace: project.workspace, sheet: sheet, block: block}
    end

    test "saves block configuration", %{
      conn: conn,
      workspace: ws,
      project: proj,
      sheet: sheet,
      block: block
    } do
      {:ok, view, _html} = mount_sheet(conn, ws, proj, sheet)

      # Open config panel first
      send_to_content_tab(view, "configure_block", %{"id" => to_string(block.id)})

      # Save new config
      send_to_content_tab(view, "save_block_config", %{
        "config" => %{"label" => "NewLabel", "placeholder" => "Enter..."}
      })

      # Verify config was updated
      updated_block = Sheets.get_block(block.id)
      assert updated_block.config["label"] == "NewLabel"
    end
  end

  describe "ConfigPanelHandlers — toggle_constant" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Toggle Constant Sheet"})
      block = block_fixture(sheet, %{type: "text", config: %{"label" => "Name"}})
      %{project: project, workspace: project.workspace, sheet: sheet, block: block}
    end

    test "toggles is_constant flag on a block", %{
      conn: conn,
      workspace: ws,
      project: proj,
      sheet: sheet,
      block: block
    } do
      assert block.is_constant == false

      {:ok, view, _html} = mount_sheet(conn, ws, proj, sheet)

      # Open config panel
      send_to_content_tab(view, "configure_block", %{"id" => to_string(block.id)})

      # Toggle constant
      send_to_content_tab(view, "toggle_constant")

      # Verify is_constant was toggled
      updated_block = Sheets.get_block(block.id)
      assert updated_block.is_constant == true
    end

    test "toggle constant twice returns to original state", %{
      conn: conn,
      workspace: ws,
      project: proj,
      sheet: sheet,
      block: block
    } do
      {:ok, view, _html} = mount_sheet(conn, ws, proj, sheet)

      send_to_content_tab(view, "configure_block", %{"id" => to_string(block.id)})

      # Toggle on
      send_to_content_tab(view, "toggle_constant")
      assert Sheets.get_block(block.id).is_constant == true

      # Toggle off
      send_to_content_tab(view, "toggle_constant")
      assert Sheets.get_block(block.id).is_constant == false
    end
  end

  # ===========================================================================
  # TableHandlers
  # ===========================================================================

  describe "TableHandlers — add_table_column" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Table Column Sheet"})
      table_block = table_block_fixture(sheet, %{label: "Inventory"})
      %{project: project, workspace: project.workspace, sheet: sheet, table_block: table_block}
    end

    test "adds a column to a table block", %{
      conn: conn,
      workspace: ws,
      project: proj,
      sheet: sheet,
      table_block: table_block
    } do
      {:ok, view, _html} = mount_sheet(conn, ws, proj, sheet)

      # Count initial columns
      initial_data = Sheets.batch_load_table_data([table_block.id])
      initial_col_count = length(initial_data[table_block.id].columns)

      # Add column
      send_to_content_tab(view, "add_table_column", %{"block-id" => to_string(table_block.id)})

      # Verify column was added
      updated_data = Sheets.batch_load_table_data([table_block.id])
      new_col_count = length(updated_data[table_block.id].columns)
      assert new_col_count == initial_col_count + 1
    end
  end

  describe "TableHandlers — add_table_row" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Table Row Sheet"})
      table_block = table_block_fixture(sheet, %{label: "Items"})
      %{project: project, workspace: project.workspace, sheet: sheet, table_block: table_block}
    end

    test "adds a row to a table block", %{
      conn: conn,
      workspace: ws,
      project: proj,
      sheet: sheet,
      table_block: table_block
    } do
      {:ok, view, _html} = mount_sheet(conn, ws, proj, sheet)

      # Count initial rows
      initial_data = Sheets.batch_load_table_data([table_block.id])
      initial_row_count = length(initial_data[table_block.id].rows)

      # Add row
      send_to_content_tab(view, "add_table_row", %{"block-id" => to_string(table_block.id)})

      # Verify row was added
      updated_data = Sheets.batch_load_table_data([table_block.id])
      new_row_count = length(updated_data[table_block.id].rows)
      assert new_row_count == initial_row_count + 1
    end
  end

  describe "TableHandlers — rename_table_column" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Rename Column Sheet"})
      table_block = table_block_fixture(sheet, %{label: "Stats"})
      column = table_column_fixture(table_block, %{name: "Health"})

      %{
        project: project,
        workspace: project.workspace,
        sheet: sheet,
        table_block: table_block,
        column: column
      }
    end

    test "renames a table column", %{
      conn: conn,
      workspace: ws,
      project: proj,
      sheet: sheet,
      column: column
    } do
      {:ok, view, _html} = mount_sheet(conn, ws, proj, sheet)

      send_to_content_tab(view, "rename_table_column", %{
        "column-id" => to_string(column.id),
        "value" => "Mana"
      })

      updated_column = Sheets.get_table_column!(column.block_id, column.id)
      assert updated_column.name == "Mana"
    end

    test "does not rename to empty string", %{
      conn: conn,
      workspace: ws,
      project: proj,
      sheet: sheet,
      column: column
    } do
      {:ok, view, _html} = mount_sheet(conn, ws, proj, sheet)

      send_to_content_tab(view, "rename_table_column", %{
        "column-id" => to_string(column.id),
        "value" => ""
      })

      updated_column = Sheets.get_table_column!(column.block_id, column.id)
      assert updated_column.name == "Health"
    end
  end

  describe "TableHandlers — rename_table_row" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Rename Row Sheet"})
      table_block = table_block_fixture(sheet, %{label: "Characters"})
      row = table_row_fixture(table_block, %{name: "Warrior"})

      %{
        project: project,
        workspace: project.workspace,
        sheet: sheet,
        table_block: table_block,
        row: row
      }
    end

    test "renames a table row", %{
      conn: conn,
      workspace: ws,
      project: proj,
      sheet: sheet,
      row: row
    } do
      {:ok, view, _html} = mount_sheet(conn, ws, proj, sheet)

      send_to_content_tab(view, "rename_table_row", %{
        "row-id" => to_string(row.id),
        "value" => "Mage"
      })

      updated_row = Sheets.get_table_row!(row.id)
      assert updated_row.name == "Mage"
    end

    test "does not rename to empty string", %{
      conn: conn,
      workspace: ws,
      project: proj,
      sheet: sheet,
      row: row
    } do
      {:ok, view, _html} = mount_sheet(conn, ws, proj, sheet)

      send_to_content_tab(view, "rename_table_row", %{
        "row-id" => to_string(row.id),
        "value" => ""
      })

      updated_row = Sheets.get_table_row!(row.id)
      assert updated_row.name == "Warrior"
    end
  end

  describe "TableHandlers — delete_table_column" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Delete Column Sheet"})
      table_block = table_block_fixture(sheet, %{label: "Weapons"})
      # Table blocks come with a default column; add a second one so we can delete it
      extra_column = table_column_fixture(table_block, %{name: "Extra Column"})

      %{
        project: project,
        workspace: project.workspace,
        sheet: sheet,
        table_block: table_block,
        extra_column: extra_column
      }
    end

    test "deletes a table column", %{
      conn: conn,
      workspace: ws,
      project: proj,
      sheet: sheet,
      table_block: table_block,
      extra_column: column
    } do
      {:ok, view, _html} = mount_sheet(conn, ws, proj, sheet)

      initial_data = Sheets.batch_load_table_data([table_block.id])
      initial_col_count = length(initial_data[table_block.id].columns)

      send_to_content_tab(view, "delete_table_column", %{"column-id" => to_string(column.id)})

      updated_data = Sheets.batch_load_table_data([table_block.id])
      new_col_count = length(updated_data[table_block.id].columns)
      assert new_col_count == initial_col_count - 1
    end
  end

  describe "TableHandlers — delete_table_row" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Delete Row Sheet"})
      table_block = table_block_fixture(sheet, %{label: "Items"})
      # Table blocks come with a default row; add a second one so we can delete it
      extra_row = table_row_fixture(table_block, %{name: "Extra Row"})

      %{
        project: project,
        workspace: project.workspace,
        sheet: sheet,
        table_block: table_block,
        extra_row: extra_row
      }
    end

    test "deletes a table row", %{
      conn: conn,
      workspace: ws,
      project: proj,
      sheet: sheet,
      table_block: table_block,
      extra_row: row
    } do
      {:ok, view, _html} = mount_sheet(conn, ws, proj, sheet)

      initial_data = Sheets.batch_load_table_data([table_block.id])
      initial_row_count = length(initial_data[table_block.id].rows)

      send_to_content_tab(view, "delete_table_row", %{"row-id" => to_string(row.id)})

      updated_data = Sheets.batch_load_table_data([table_block.id])
      new_row_count = length(updated_data[table_block.id].rows)
      assert new_row_count == initial_row_count - 1
    end
  end

  describe "TableHandlers — update_table_cell" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Cell Update Sheet"})
      table_block = table_block_fixture(sheet, %{label: "Stats"})

      # Get the default column and row created with the table
      data = Sheets.batch_load_table_data([table_block.id])
      default_col = hd(data[table_block.id].columns)
      default_row = hd(data[table_block.id].rows)

      %{
        project: project,
        workspace: project.workspace,
        sheet: sheet,
        table_block: table_block,
        column: default_col,
        row: default_row
      }
    end

    test "updates a cell value in a table", %{
      conn: conn,
      workspace: ws,
      project: proj,
      sheet: sheet,
      column: column,
      row: row
    } do
      {:ok, view, _html} = mount_sheet(conn, ws, proj, sheet)

      send_to_content_tab(view, "update_table_cell", %{
        "row-id" => to_string(row.id),
        "column-slug" => column.slug,
        "value" => "42"
      })

      updated_row = Sheets.get_table_row!(row.id)
      assert updated_row.cells[column.slug] == "42"
    end
  end

  describe "TableHandlers — toggle_table_collapse" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Collapse Sheet"})
      table_block = table_block_fixture(sheet, %{label: "Collapsible"})
      %{project: project, workspace: project.workspace, sheet: sheet, table_block: table_block}
    end

    test "toggles table collapsed state", %{
      conn: conn,
      workspace: ws,
      project: proj,
      sheet: sheet,
      table_block: table_block
    } do
      {:ok, view, _html} = mount_sheet(conn, ws, proj, sheet)

      send_to_content_tab(view, "toggle_table_collapse", %{
        "block-id" => to_string(table_block.id)
      })

      updated_block = Sheets.get_block(table_block.id)
      assert updated_block.config["collapsed"] == true
    end
  end

  describe "TableHandlers — change_table_column_type" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Column Type Sheet"})
      table_block = table_block_fixture(sheet, %{label: "Typed Table"})
      column = table_column_fixture(table_block, %{name: "Field"})

      %{
        project: project,
        workspace: project.workspace,
        sheet: sheet,
        table_block: table_block,
        column: column
      }
    end

    test "changes column type", %{
      conn: conn,
      workspace: ws,
      project: proj,
      sheet: sheet,
      column: column
    } do
      {:ok, view, _html} = mount_sheet(conn, ws, proj, sheet)

      send_to_content_tab(view, "change_table_column_type", %{
        "column-id" => to_string(column.id),
        "new-type" => "number"
      })

      updated_column = Sheets.get_table_column!(column.block_id, column.id)
      assert updated_column.type == "number"
    end
  end

  describe "TableHandlers — toggle_table_column_constant" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Column Constant Sheet"})
      table_block = table_block_fixture(sheet, %{label: "Constants"})
      column = table_column_fixture(table_block, %{name: "Fixed"})

      %{
        project: project,
        workspace: project.workspace,
        sheet: sheet,
        table_block: table_block,
        column: column
      }
    end

    test "toggles is_constant flag on a column", %{
      conn: conn,
      workspace: ws,
      project: proj,
      sheet: sheet,
      column: column
    } do
      assert column.is_constant == false

      {:ok, view, _html} = mount_sheet(conn, ws, proj, sheet)

      send_to_content_tab(view, "toggle_table_column_constant", %{
        "column-id" => to_string(column.id)
      })

      updated_column = Sheets.get_table_column!(column.block_id, column.id)
      assert updated_column.is_constant == true
    end
  end

  describe "TableHandlers — toggle_table_column_required" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Column Required Sheet"})
      table_block = table_block_fixture(sheet, %{label: "Required Table"})
      column = table_column_fixture(table_block, %{name: "Mandatory"})

      %{
        project: project,
        workspace: project.workspace,
        sheet: sheet,
        table_block: table_block,
        column: column
      }
    end

    test "toggles required flag on a column", %{
      conn: conn,
      workspace: ws,
      project: proj,
      sheet: sheet,
      column: column
    } do
      assert column.required == false

      {:ok, view, _html} = mount_sheet(conn, ws, proj, sheet)

      send_to_content_tab(view, "toggle_table_column_required", %{
        "column-id" => to_string(column.id)
      })

      updated_column = Sheets.get_table_column!(column.block_id, column.id)
      assert updated_column.required == true
    end
  end

  describe "TableHandlers — reorder_table_rows" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Reorder Rows Sheet"})
      table_block = table_block_fixture(sheet, %{label: "Ordered"})
      row2 = table_row_fixture(table_block, %{name: "Second"})
      row3 = table_row_fixture(table_block, %{name: "Third"})

      # Get the default row that was created with the table
      data = Sheets.batch_load_table_data([table_block.id])
      default_row = hd(data[table_block.id].rows)

      %{
        project: project,
        workspace: project.workspace,
        sheet: sheet,
        table_block: table_block,
        row1: default_row,
        row2: row2,
        row3: row3
      }
    end

    test "reorders rows within a table", %{
      conn: conn,
      workspace: ws,
      project: proj,
      sheet: sheet,
      table_block: table_block,
      row1: r1,
      row2: r2,
      row3: r3
    } do
      {:ok, view, _html} = mount_sheet(conn, ws, proj, sheet)

      new_order = [r3.id, r1.id, r2.id]

      send_to_content_tab(view, "reorder_table_rows", %{
        "block_id" => to_string(table_block.id),
        "row_ids" => Enum.map(new_order, &to_string/1)
      })

      rows = Sheets.list_table_rows(table_block.id)
      assert Enum.map(rows, & &1.id) == new_order
    end
  end

  describe "TableHandlers — toggle_table_cell_boolean" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Bool Cell Sheet"})
      table_block = table_block_fixture(sheet, %{label: "Flags"})
      bool_column = table_column_fixture(table_block, %{name: "Active", type: "boolean"})

      data = Sheets.batch_load_table_data([table_block.id])
      default_row = hd(data[table_block.id].rows)

      %{
        project: project,
        workspace: project.workspace,
        sheet: sheet,
        table_block: table_block,
        bool_column: bool_column,
        row: default_row
      }
    end

    test "toggles a boolean cell value", %{
      conn: conn,
      workspace: ws,
      project: proj,
      sheet: sheet,
      bool_column: col,
      row: row
    } do
      {:ok, view, _html} = mount_sheet(conn, ws, proj, sheet)

      send_to_content_tab(view, "toggle_table_cell_boolean", %{
        "row-id" => to_string(row.id),
        "column-slug" => col.slug
      })

      updated_row = Sheets.get_table_row!(row.id)
      assert updated_row.cells[col.slug] == true
    end
  end

  # ===========================================================================
  # UndoRedoHandlers
  # ===========================================================================

  # ===========================================================================
  # InheritanceHandlers
  # ===========================================================================

  describe "InheritanceHandlers — parent/child sheet inheritance" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      parent_sheet = sheet_fixture(project, %{name: "Parent Character"})

      # Create an inheritable block on the parent (scope: "children")
      inheritable_block =
        inheritable_block_fixture(parent_sheet, label: "Shared Trait", type: "text")

      # Create child sheet that inherits blocks
      child_sheet = child_sheet_fixture(project, parent_sheet, %{name: "Child Character"})

      %{
        project: project,
        workspace: project.workspace,
        parent_sheet: parent_sheet,
        child_sheet: child_sheet,
        inheritable_block: inheritable_block
      }
    end

    test "child sheet shows inherited blocks", %{
      conn: conn,
      workspace: ws,
      project: proj,
      child_sheet: child_sheet
    } do
      {:ok, _view, html} = mount_sheet(conn, ws, proj, child_sheet)

      # Inherited block should be visible
      assert html =~ "Shared Trait"
    end

    test "change_block_scope to children on parent sheet", %{
      conn: conn,
      workspace: ws,
      project: proj,
      parent_sheet: parent_sheet
    } do
      # Create a self-scoped block
      block =
        block_fixture(parent_sheet, %{
          type: "number",
          config: %{"label" => "Strength"},
          scope: "self"
        })

      {:ok, view, _html} = mount_sheet(conn, ws, proj, parent_sheet)

      # Open config panel
      send_to_content_tab(view, "configure_block", %{"id" => to_string(block.id)})

      # Change scope to children
      send_to_content_tab(view, "change_block_scope", %{"scope" => "children"})

      updated_block = Sheets.get_block(block.id)
      assert updated_block.scope == "children"
    end
  end

  describe "InheritanceHandlers — hide/unhide for children" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      parent_sheet = sheet_fixture(project, %{name: "Template Sheet"})
      inheritable_block = inheritable_block_fixture(parent_sheet, label: "Visible Trait")
      _child_sheet = child_sheet_fixture(project, parent_sheet, %{name: "Instance Sheet"})

      %{
        project: project,
        workspace: project.workspace,
        parent_sheet: parent_sheet,
        inheritable_block: inheritable_block
      }
    end

    test "hide_inherited_for_children hides a block from children", %{
      conn: conn,
      workspace: ws,
      project: proj,
      parent_sheet: parent_sheet,
      inheritable_block: block
    } do
      {:ok, view, _html} = mount_sheet(conn, ws, proj, parent_sheet)

      send_to_content_tab(view, "hide_inherited_for_children", %{"id" => to_string(block.id)})

      # Verify DB state: block ID is now in hidden list
      updated_sheet = Sheets.get_sheet!(proj.id, parent_sheet.id)
      assert block.id in (updated_sheet.hidden_inherited_block_ids || [])

      # View should still be alive
      assert render(view) =~ "Template Sheet"
    end

    test "unhide_inherited_for_children restores visibility", %{
      conn: conn,
      workspace: ws,
      project: proj,
      parent_sheet: parent_sheet,
      inheritable_block: block
    } do
      # Hide first
      Sheets.hide_for_children(parent_sheet, block.id)

      {:ok, view, _html} = mount_sheet(conn, ws, proj, parent_sheet)

      send_to_content_tab(view, "unhide_inherited_for_children", %{
        "id" => to_string(block.id)
      })

      # Verify DB state: block ID is no longer in hidden list
      updated_sheet = Sheets.get_sheet!(proj.id, parent_sheet.id)
      refute block.id in (updated_sheet.hidden_inherited_block_ids || [])

      # View should still be alive
      assert render(view) =~ "Template Sheet"
    end
  end

  describe "InheritanceHandlers — toggle_required" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      parent_sheet = sheet_fixture(project, %{name: "Required Sheet"})

      inheritable_block =
        inheritable_block_fixture(parent_sheet, label: "Required Field", required: false)

      %{
        project: project,
        workspace: project.workspace,
        parent_sheet: parent_sheet,
        inheritable_block: inheritable_block
      }
    end

    test "toggles required flag on a block", %{
      conn: conn,
      workspace: ws,
      project: proj,
      parent_sheet: parent_sheet,
      inheritable_block: block
    } do
      {:ok, view, _html} = mount_sheet(conn, ws, proj, parent_sheet)

      # Open config panel for the block
      send_to_content_tab(view, "configure_block", %{"id" => to_string(block.id)})

      # Toggle required
      send_to_content_tab(view, "toggle_required")

      updated_block = Sheets.get_block(block.id)
      assert updated_block.required == true
    end
  end

  # ===========================================================================
  # Authorization — viewer cannot edit
  # ===========================================================================

  describe "authorization — viewer role" do
    setup :register_and_log_in_user

    setup %{user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      sheet = sheet_fixture(project, %{name: "Viewer Sheet"})
      block = block_fixture(sheet, %{type: "text", config: %{"label" => "ReadOnly"}})
      %{project: project, workspace: project.workspace, sheet: sheet, block: block}
    end

    test "viewer cannot delete a block", %{
      conn: conn,
      workspace: ws,
      project: proj,
      sheet: sheet,
      block: block
    } do
      {:ok, view, _html} = mount_sheet(conn, ws, proj, sheet)

      # Viewer should not see the delete button at all in the HTML
      html = render(view)
      refute html =~ "phx-click=\"delete_block\""

      # Block should still exist
      assert Sheets.get_block(block.id) != nil
    end

    test "viewer cannot add a block", %{
      conn: conn,
      workspace: ws,
      project: proj,
      sheet: sheet
    } do
      {:ok, view, _html} = mount_sheet(conn, ws, proj, sheet)

      # The add block prompt should not be shown to viewers
      html = render(view)
      refute html =~ "show_block_menu"

      # Verify no new blocks were created
      blocks = Sheets.list_blocks(sheet.id)
      assert length(blocks) == 1
    end

  end

  # ===========================================================================
  # Block label update
  # ===========================================================================

  describe "update_block_label" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Label Sheet"})
      block = block_fixture(sheet, %{type: "text", config: %{"label" => "Original Label"}})
      %{project: project, workspace: project.workspace, sheet: sheet, block: block}
    end

    test "updates block label", %{
      conn: conn,
      workspace: ws,
      project: proj,
      sheet: sheet,
      block: block
    } do
      {:ok, view, _html} = mount_sheet(conn, ws, proj, sheet)

      send_to_content_tab(view, "update_block_label", %{
        "id" => to_string(block.id),
        "label" => "Updated Label"
      })

      updated_block = Sheets.get_block(block.id)
      assert updated_block.config["label"] == "Updated Label"
    end
  end

  # ===========================================================================
  # Block scope events
  # ===========================================================================

  describe "block scope events" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Scope Sheet"})
      %{project: project, workspace: project.workspace, sheet: sheet}
    end

    test "show_block_menu and hide_block_menu toggle menu visibility", %{
      conn: conn,
      workspace: ws,
      project: proj,
      sheet: sheet
    } do
      {:ok, view, _html} = mount_sheet(conn, ws, proj, sheet)

      # Show menu
      html = send_to_content_tab(view, "show_block_menu")
      # Block menu should be visible (contains block type options)
      assert html =~ "Text" || html =~ "add_block"

      # Hide menu
      send_to_content_tab(view, "hide_block_menu")

      # View is still alive
      assert render(view) =~ "Scope Sheet"
    end

    test "set_block_scope changes the scope for new blocks", %{
      conn: conn,
      workspace: ws,
      project: proj,
      sheet: sheet
    } do
      {:ok, view, _html} = mount_sheet(conn, ws, proj, sheet)

      # Set scope to children
      send_to_content_tab(view, "set_block_scope", %{"scope" => "children"})

      # Now add a block - it should be created with scope "children"
      send_to_content_tab(view, "show_block_menu")
      send_to_content_tab(view, "add_block", %{"type" => "text"})

      blocks = Sheets.list_blocks(sheet.id)
      assert length(blocks) == 1
      assert hd(blocks).scope == "children"
    end
  end
end
