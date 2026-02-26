defmodule StoryarnWeb.SheetLive.Handlers.UndoRedoHandlersTest do
  @moduledoc """
  Integration tests for undo/redo in the Sheet LiveView.

  Tests cover all action types dispatched through UndoRedoHandlers:
  - Sheet metadata: name, shortcut, color
  - Block CRUD: create, delete, reorder
  - Block values & config: update_block_value, update_block_config, toggle_constant
  - Table operations: column/row add/delete/rename, cell updates, column type change,
    column flag toggle, row reorder, column config update
  - Compound actions
  - Stack behavior: empty stacks, redo cleared by new action, multiple cycles
  - Coalescing helpers: name, shortcut, block value, table cell
  - Snapshot helpers: block_to_snapshot, table_column_to_snapshot, table_row_to_snapshot
  """

  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.{Repo, Sheets}
  alias StoryarnWeb.SheetLive.Handlers.UndoRedoHandlers

  # ===========================================================================
  # Setup
  # ===========================================================================

  setup :register_and_log_in_user

  setup %{user: user} do
    project = project_fixture(user) |> Repo.preload(:workspace)
    sheet = sheet_fixture(project, %{name: "Undo Redo Sheet"})
    ws = project.workspace

    url =
      ~p"/workspaces/#{ws.slug}/projects/#{project.slug}/sheets/#{sheet.id}"

    %{project: project, workspace: ws, sheet: sheet, url: url}
  end

  # ===========================================================================
  # Helpers
  # ===========================================================================

  defp mount_sheet(conn, url) do
    live(conn, url)
  end

  # Builds a minimal socket for unit testing coalescing helpers
  defp mock_socket(assigns \\ %{}) do
    %Phoenix.LiveView.Socket{
      assigns: Map.merge(%{__changed__: %{}, undo_stack: [], redo_stack: []}, assigns)
    }
  end

  defp send_to_content_tab(view, event, params \\ %{}) do
    view
    |> with_target("#content-tab")
    |> render_click(event, params)
  end

  # ===========================================================================
  # Stack behavior — empty stacks
  # ===========================================================================

  describe "stack behavior" do
    test "undo on empty stack is a no-op", %{conn: conn, url: url} do
      {:ok, view, _html} = mount_sheet(conn, url)

      # Should not crash
      render_hook(view, "undo", %{})
      render_hook(view, "undo", %{})

      assert render(view) =~ "Undo Redo Sheet"
    end

    test "redo on empty stack is a no-op", %{conn: conn, url: url} do
      {:ok, view, _html} = mount_sheet(conn, url)

      render_hook(view, "redo", %{})
      render_hook(view, "redo", %{})

      assert render(view) =~ "Undo Redo Sheet"
    end

    test "new action clears redo stack", %{conn: conn, url: url, sheet: sheet} do
      {:ok, view, _html} = mount_sheet(conn, url)

      # Set color (pushes to undo stack)
      render_hook(view, "set_sheet_color", %{"color" => "#ff0000"})

      # Undo it (pushes to redo stack)
      render_hook(view, "undo", %{})
      assert Sheets.get_sheet!(sheet.project_id, sheet.id).color == nil

      # New action should clear redo stack
      render_hook(view, "set_sheet_color", %{"color" => "#00ff00"})

      # Redo should do nothing now — stack was cleared
      render_hook(view, "redo", %{})
      assert Sheets.get_sheet!(sheet.project_id, sheet.id).color == "#00ff00"
    end

    test "multiple undo/redo cycles work correctly", %{conn: conn, url: url, sheet: sheet} do
      {:ok, view, _html} = mount_sheet(conn, url)

      # Two color changes
      render_hook(view, "set_sheet_color", %{"color" => "#111111"})
      render_hook(view, "set_sheet_color", %{"color" => "#222222"})

      assert Sheets.get_sheet!(sheet.project_id, sheet.id).color == "#222222"

      # Undo twice
      render_hook(view, "undo", %{})
      assert Sheets.get_sheet!(sheet.project_id, sheet.id).color == "#111111"

      render_hook(view, "undo", %{})
      assert Sheets.get_sheet!(sheet.project_id, sheet.id).color == nil

      # Redo twice
      render_hook(view, "redo", %{})
      assert Sheets.get_sheet!(sheet.project_id, sheet.id).color == "#111111"

      render_hook(view, "redo", %{})
      assert Sheets.get_sheet!(sheet.project_id, sheet.id).color == "#222222"
    end
  end

  # ===========================================================================
  # Sheet color undo/redo
  # ===========================================================================

  describe "sheet color undo/redo" do
    test "undo reverses a sheet color change", %{conn: conn, url: url, sheet: sheet} do
      {:ok, view, _html} = mount_sheet(conn, url)

      render_hook(view, "set_sheet_color", %{"color" => "#ff0000"})
      assert Sheets.get_sheet!(sheet.project_id, sheet.id).color == "#ff0000"

      render_hook(view, "undo", %{})
      assert Sheets.get_sheet!(sheet.project_id, sheet.id).color == nil
    end

    test "redo re-applies color change after undo", %{conn: conn, url: url, sheet: sheet} do
      {:ok, view, _html} = mount_sheet(conn, url)

      render_hook(view, "set_sheet_color", %{"color" => "#00ff00"})
      render_hook(view, "undo", %{})
      assert Sheets.get_sheet!(sheet.project_id, sheet.id).color == nil

      render_hook(view, "redo", %{})
      assert Sheets.get_sheet!(sheet.project_id, sheet.id).color == "#00ff00"
    end

    test "undo reverses clear_sheet_color", %{conn: conn, url: url, sheet: sheet} do
      # Set color first directly
      Sheets.update_sheet(sheet, %{color: "#ff0000"})

      {:ok, view, _html} = mount_sheet(conn, url)

      render_hook(view, "clear_sheet_color", %{})
      assert Sheets.get_sheet!(sheet.project_id, sheet.id).color == nil

      render_hook(view, "undo", %{})
      assert Sheets.get_sheet!(sheet.project_id, sheet.id).color == "#ff0000"
    end
  end

  # ===========================================================================
  # Block create undo/redo
  # ===========================================================================

  describe "block create undo/redo" do
    test "undo reverses block creation", %{conn: conn, url: url, sheet: sheet} do
      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "show_block_menu")
      send_to_content_tab(view, "add_block", %{"type" => "text"})
      assert length(Sheets.list_blocks(sheet.id)) == 1

      render_hook(view, "undo", %{})
      assert Sheets.list_blocks(sheet.id) == []
    end

    test "redo restores block after undo", %{conn: conn, url: url, sheet: sheet} do
      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "show_block_menu")
      send_to_content_tab(view, "add_block", %{"type" => "number"})
      assert length(Sheets.list_blocks(sheet.id)) == 1

      render_hook(view, "undo", %{})
      assert Sheets.list_blocks(sheet.id) == []

      render_hook(view, "redo", %{})
      blocks = Sheets.list_blocks(sheet.id)
      assert length(blocks) == 1
      assert hd(blocks).type == "number"
    end
  end

  # ===========================================================================
  # Block delete undo/redo
  # ===========================================================================

  describe "block delete undo/redo" do
    test "undo restores deleted block", %{conn: conn, url: url, sheet: sheet} do
      block = block_fixture(sheet, %{type: "text", config: %{"label" => "MyField"}})

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "delete_block", %{"id" => to_string(block.id)})
      assert Sheets.list_blocks(sheet.id) == []

      render_hook(view, "undo", %{})
      blocks = Sheets.list_blocks(sheet.id)
      assert length(blocks) == 1
      assert hd(blocks).type == "text"
    end

    test "redo re-deletes block after undo", %{conn: conn, url: url, sheet: sheet} do
      block = block_fixture(sheet, %{type: "text", config: %{"label" => "Deletable"}})

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "delete_block", %{"id" => to_string(block.id)})
      render_hook(view, "undo", %{})
      assert length(Sheets.list_blocks(sheet.id)) == 1

      render_hook(view, "redo", %{})
      assert Sheets.list_blocks(sheet.id) == []
    end
  end

  # ===========================================================================
  # Block value undo/redo
  # ===========================================================================

  describe "block value undo/redo" do
    test "undo reverses block value update", %{conn: conn, url: url, sheet: sheet} do
      block = block_fixture(sheet, %{type: "text", config: %{"label" => "Description"}})

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "update_block_value", %{
        "id" => to_string(block.id),
        "value" => "Hello World"
      })

      assert Sheets.get_block(block.id).value["content"] == "Hello World"

      render_hook(view, "undo", %{})
      assert Sheets.get_block(block.id).value["content"] == ""
    end

    test "undo restores original value after multiple updates", %{
      conn: conn,
      url: url,
      sheet: sheet
    } do
      block =
        block_fixture(sheet, %{
          type: "number",
          config: %{"label" => "HP"},
          value: %{"content" => "50"}
        })

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "update_block_value", %{
        "id" => to_string(block.id),
        "value" => "100"
      })

      assert Sheets.get_block(block.id).value["content"] == "100"

      render_hook(view, "undo", %{})
      assert Sheets.get_block(block.id).value["content"] == "50"
    end

    test "consecutive block value updates coalesce into single undo entry", %{
      conn: conn,
      url: url,
      sheet: sheet
    } do
      block = block_fixture(sheet, %{type: "text", config: %{"label" => "Typing"}})

      {:ok, view, _html} = mount_sheet(conn, url)

      # Simulate typing: multiple value updates for the same block
      send_to_content_tab(view, "update_block_value", %{
        "id" => to_string(block.id),
        "value" => "H"
      })

      send_to_content_tab(view, "update_block_value", %{
        "id" => to_string(block.id),
        "value" => "He"
      })

      send_to_content_tab(view, "update_block_value", %{
        "id" => to_string(block.id),
        "value" => "Hello"
      })

      # Single undo should go back to original value, not intermediate
      render_hook(view, "undo", %{})
      assert Sheets.get_block(block.id).value["content"] == ""
    end
  end

  # ===========================================================================
  # Block config undo/redo
  # ===========================================================================

  describe "block config undo/redo" do
    test "undo reverses block config update", %{conn: conn, url: url, sheet: sheet} do
      block = block_fixture(sheet, %{type: "text", config: %{"label" => "OldLabel"}})

      {:ok, view, _html} = mount_sheet(conn, url)

      # Open config panel then save new config
      send_to_content_tab(view, "configure_block", %{"id" => to_string(block.id)})

      send_to_content_tab(view, "save_block_config", %{
        "config" => %{"label" => "NewLabel", "placeholder" => "Type..."}
      })

      assert Sheets.get_block(block.id).config["label"] == "NewLabel"

      render_hook(view, "undo", %{})
      assert Sheets.get_block(block.id).config["label"] == "OldLabel"
    end

    test "redo re-applies config after undo", %{conn: conn, url: url, sheet: sheet} do
      block = block_fixture(sheet, %{type: "text", config: %{"label" => "Before"}})

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "configure_block", %{"id" => to_string(block.id)})

      send_to_content_tab(view, "save_block_config", %{
        "config" => %{"label" => "After", "placeholder" => ""}
      })

      render_hook(view, "undo", %{})
      assert Sheets.get_block(block.id).config["label"] == "Before"

      render_hook(view, "redo", %{})
      assert Sheets.get_block(block.id).config["label"] == "After"
    end
  end

  # ===========================================================================
  # Toggle constant undo/redo
  # ===========================================================================

  describe "toggle constant undo/redo" do
    test "undo reverses toggle_constant", %{conn: conn, url: url, sheet: sheet} do
      block = block_fixture(sheet, %{type: "text", config: %{"label" => "Name"}})
      assert block.is_constant == false

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "configure_block", %{"id" => to_string(block.id)})
      send_to_content_tab(view, "toggle_constant")
      assert Sheets.get_block(block.id).is_constant == true

      render_hook(view, "undo", %{})
      assert Sheets.get_block(block.id).is_constant == false
    end

    test "redo re-applies toggle_constant after undo", %{conn: conn, url: url, sheet: sheet} do
      block = block_fixture(sheet, %{type: "text", config: %{"label" => "Const"}})

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "configure_block", %{"id" => to_string(block.id)})
      send_to_content_tab(view, "toggle_constant")

      render_hook(view, "undo", %{})
      assert Sheets.get_block(block.id).is_constant == false

      render_hook(view, "redo", %{})
      assert Sheets.get_block(block.id).is_constant == true
    end
  end

  # ===========================================================================
  # Block reorder undo/redo
  # ===========================================================================

  describe "block reorder undo/redo" do
    test "undo reverses block reorder", %{conn: conn, url: url, sheet: sheet} do
      b1 = block_fixture(sheet, %{type: "text", config: %{"label" => "First"}})
      b2 = block_fixture(sheet, %{type: "text", config: %{"label" => "Second"}})
      b3 = block_fixture(sheet, %{type: "text", config: %{"label" => "Third"}})

      {:ok, view, _html} = mount_sheet(conn, url)

      # Reorder to b3, b1, b2
      new_order = [to_string(b3.id), to_string(b1.id), to_string(b2.id)]
      send_to_content_tab(view, "reorder", %{"ids" => new_order, "group" => "blocks"})

      ids = Sheets.list_blocks(sheet.id) |> Enum.map(& &1.id)
      assert ids == [b3.id, b1.id, b2.id]

      render_hook(view, "undo", %{})

      ids = Sheets.list_blocks(sheet.id) |> Enum.map(& &1.id)
      assert ids == [b1.id, b2.id, b3.id]
    end

    test "redo re-applies reorder after undo", %{conn: conn, url: url, sheet: sheet} do
      b1 = block_fixture(sheet, %{type: "text", config: %{"label" => "A"}})
      b2 = block_fixture(sheet, %{type: "text", config: %{"label" => "B"}})

      {:ok, view, _html} = mount_sheet(conn, url)

      new_order = [to_string(b2.id), to_string(b1.id)]
      send_to_content_tab(view, "reorder", %{"ids" => new_order, "group" => "blocks"})

      render_hook(view, "undo", %{})
      ids = Sheets.list_blocks(sheet.id) |> Enum.map(& &1.id)
      assert ids == [b1.id, b2.id]

      render_hook(view, "redo", %{})
      ids = Sheets.list_blocks(sheet.id) |> Enum.map(& &1.id)
      assert ids == [b2.id, b1.id]
    end
  end

  # ===========================================================================
  # Table column add/delete undo/redo
  # ===========================================================================

  describe "table column add undo/redo" do
    test "undo reverses table column creation", %{conn: conn, url: url, sheet: sheet} do
      table_block = table_block_fixture(sheet, %{label: "Items"})
      initial_data = Sheets.batch_load_table_data([table_block.id])
      initial_count = length(initial_data[table_block.id].columns)

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "add_table_column", %{"block-id" => to_string(table_block.id)})
      data = Sheets.batch_load_table_data([table_block.id])
      assert length(data[table_block.id].columns) == initial_count + 1

      render_hook(view, "undo", %{})
      data = Sheets.batch_load_table_data([table_block.id])
      assert length(data[table_block.id].columns) == initial_count
    end

    test "redo restores column after undo", %{conn: conn, url: url, sheet: sheet} do
      table_block = table_block_fixture(sheet, %{label: "Weapons"})
      initial_data = Sheets.batch_load_table_data([table_block.id])
      initial_count = length(initial_data[table_block.id].columns)

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "add_table_column", %{"block-id" => to_string(table_block.id)})
      render_hook(view, "undo", %{})
      data = Sheets.batch_load_table_data([table_block.id])
      assert length(data[table_block.id].columns) == initial_count

      render_hook(view, "redo", %{})
      data = Sheets.batch_load_table_data([table_block.id])
      assert length(data[table_block.id].columns) == initial_count + 1
    end
  end

  describe "table column delete undo/redo" do
    test "undo restores deleted column", %{conn: conn, url: url, sheet: sheet} do
      table_block = table_block_fixture(sheet, %{label: "Stats"})
      column = table_column_fixture(table_block, %{name: "Health"})
      initial_data = Sheets.batch_load_table_data([table_block.id])
      initial_count = length(initial_data[table_block.id].columns)

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "delete_table_column", %{"column-id" => to_string(column.id)})
      data = Sheets.batch_load_table_data([table_block.id])
      assert length(data[table_block.id].columns) == initial_count - 1

      render_hook(view, "undo", %{})
      data = Sheets.batch_load_table_data([table_block.id])
      assert length(data[table_block.id].columns) == initial_count
    end
  end

  # ===========================================================================
  # Table row add/delete undo/redo
  # ===========================================================================

  describe "table row add undo/redo" do
    test "undo reverses table row creation", %{conn: conn, url: url, sheet: sheet} do
      table_block = table_block_fixture(sheet, %{label: "Rows"})
      initial_data = Sheets.batch_load_table_data([table_block.id])
      initial_count = length(initial_data[table_block.id].rows)

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "add_table_row", %{"block-id" => to_string(table_block.id)})
      data = Sheets.batch_load_table_data([table_block.id])
      assert length(data[table_block.id].rows) == initial_count + 1

      render_hook(view, "undo", %{})
      data = Sheets.batch_load_table_data([table_block.id])
      assert length(data[table_block.id].rows) == initial_count
    end

    test "redo restores row after undo", %{conn: conn, url: url, sheet: sheet} do
      table_block = table_block_fixture(sheet, %{label: "Roster"})
      initial_data = Sheets.batch_load_table_data([table_block.id])
      initial_count = length(initial_data[table_block.id].rows)

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "add_table_row", %{"block-id" => to_string(table_block.id)})
      render_hook(view, "undo", %{})
      data = Sheets.batch_load_table_data([table_block.id])
      assert length(data[table_block.id].rows) == initial_count

      render_hook(view, "redo", %{})
      data = Sheets.batch_load_table_data([table_block.id])
      assert length(data[table_block.id].rows) == initial_count + 1
    end
  end

  describe "table row delete undo/redo" do
    test "undo restores deleted row", %{conn: conn, url: url, sheet: sheet} do
      table_block = table_block_fixture(sheet, %{label: "Characters"})
      row = table_row_fixture(table_block, %{name: "Warrior"})
      initial_data = Sheets.batch_load_table_data([table_block.id])
      initial_count = length(initial_data[table_block.id].rows)

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "delete_table_row", %{"row-id" => to_string(row.id)})
      data = Sheets.batch_load_table_data([table_block.id])
      assert length(data[table_block.id].rows) == initial_count - 1

      render_hook(view, "undo", %{})
      data = Sheets.batch_load_table_data([table_block.id])
      assert length(data[table_block.id].rows) == initial_count
    end
  end

  # ===========================================================================
  # Table cell update undo/redo
  # ===========================================================================

  describe "table cell update undo/redo" do
    test "undo reverses cell update", %{conn: conn, url: url, sheet: sheet} do
      table_block = table_block_fixture(sheet, %{label: "Cells"})
      data = Sheets.batch_load_table_data([table_block.id])
      default_col = hd(data[table_block.id].columns)
      default_row = hd(data[table_block.id].rows)

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "update_table_cell", %{
        "row-id" => to_string(default_row.id),
        "column-slug" => default_col.slug,
        "value" => "42"
      })

      assert Sheets.get_table_row!(default_row.id).cells[default_col.slug] == "42"

      render_hook(view, "undo", %{})
      assert Sheets.get_table_row!(default_row.id).cells[default_col.slug] == nil
    end

    test "redo re-applies cell update after undo", %{conn: conn, url: url, sheet: sheet} do
      table_block = table_block_fixture(sheet, %{label: "CellRedo"})
      data = Sheets.batch_load_table_data([table_block.id])
      default_col = hd(data[table_block.id].columns)
      default_row = hd(data[table_block.id].rows)

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "update_table_cell", %{
        "row-id" => to_string(default_row.id),
        "column-slug" => default_col.slug,
        "value" => "99"
      })

      render_hook(view, "undo", %{})
      assert Sheets.get_table_row!(default_row.id).cells[default_col.slug] == nil

      render_hook(view, "redo", %{})
      assert Sheets.get_table_row!(default_row.id).cells[default_col.slug] == "99"
    end

    test "consecutive cell updates coalesce into single undo entry", %{
      conn: conn,
      url: url,
      sheet: sheet
    } do
      table_block = table_block_fixture(sheet, %{label: "Coalesce"})
      data = Sheets.batch_load_table_data([table_block.id])
      default_col = hd(data[table_block.id].columns)
      default_row = hd(data[table_block.id].rows)

      {:ok, view, _html} = mount_sheet(conn, url)

      # Multiple updates to same cell
      send_to_content_tab(view, "update_table_cell", %{
        "row-id" => to_string(default_row.id),
        "column-slug" => default_col.slug,
        "value" => "1"
      })

      send_to_content_tab(view, "update_table_cell", %{
        "row-id" => to_string(default_row.id),
        "column-slug" => default_col.slug,
        "value" => "12"
      })

      send_to_content_tab(view, "update_table_cell", %{
        "row-id" => to_string(default_row.id),
        "column-slug" => default_col.slug,
        "value" => "123"
      })

      # Single undo should go back to original nil value
      render_hook(view, "undo", %{})
      assert Sheets.get_table_row!(default_row.id).cells[default_col.slug] == nil
    end
  end

  # ===========================================================================
  # Table column rename undo/redo
  # ===========================================================================

  describe "table column rename undo/redo" do
    test "undo reverses column rename", %{conn: conn, url: url, sheet: sheet} do
      table_block = table_block_fixture(sheet, %{label: "RenCol"})
      column = table_column_fixture(table_block, %{name: "Health"})

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "rename_table_column", %{
        "column-id" => to_string(column.id),
        "value" => "Mana"
      })

      assert Sheets.get_table_column!(column.id).name == "Mana"

      render_hook(view, "undo", %{})
      assert Sheets.get_table_column!(column.id).name == "Health"
    end

    test "redo re-applies column rename after undo", %{conn: conn, url: url, sheet: sheet} do
      table_block = table_block_fixture(sheet, %{label: "RedoRename"})
      column = table_column_fixture(table_block, %{name: "Strength"})

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "rename_table_column", %{
        "column-id" => to_string(column.id),
        "value" => "Power"
      })

      render_hook(view, "undo", %{})
      assert Sheets.get_table_column!(column.id).name == "Strength"

      render_hook(view, "redo", %{})
      assert Sheets.get_table_column!(column.id).name == "Power"
    end
  end

  # ===========================================================================
  # Table row rename undo/redo
  # ===========================================================================

  describe "table row rename undo/redo" do
    test "undo reverses row rename", %{conn: conn, url: url, sheet: sheet} do
      table_block = table_block_fixture(sheet, %{label: "RenRow"})
      row = table_row_fixture(table_block, %{name: "Warrior"})

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "rename_table_row", %{
        "row-id" => to_string(row.id),
        "value" => "Mage"
      })

      assert Sheets.get_table_row!(row.id).name == "Mage"

      render_hook(view, "undo", %{})
      assert Sheets.get_table_row!(row.id).name == "Warrior"
    end

    test "redo re-applies row rename after undo", %{conn: conn, url: url, sheet: sheet} do
      table_block = table_block_fixture(sheet, %{label: "RedoRow"})
      row = table_row_fixture(table_block, %{name: "Knight"})

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "rename_table_row", %{
        "row-id" => to_string(row.id),
        "value" => "Paladin"
      })

      render_hook(view, "undo", %{})
      assert Sheets.get_table_row!(row.id).name == "Knight"

      render_hook(view, "redo", %{})
      assert Sheets.get_table_row!(row.id).name == "Paladin"
    end
  end

  # ===========================================================================
  # Table row reorder undo/redo
  # ===========================================================================

  describe "table row reorder undo/redo" do
    test "undo reverses row reorder", %{conn: conn, url: url, sheet: sheet} do
      table_block = table_block_fixture(sheet, %{label: "ReorderRows"})
      row2 = table_row_fixture(table_block, %{name: "Second"})
      row3 = table_row_fixture(table_block, %{name: "Third"})

      data = Sheets.batch_load_table_data([table_block.id])
      default_row = hd(data[table_block.id].rows)

      original_order = Sheets.list_table_rows(table_block.id) |> Enum.map(& &1.id)

      {:ok, view, _html} = mount_sheet(conn, url)

      new_order = [row3.id, default_row.id, row2.id]

      send_to_content_tab(view, "reorder_table_rows", %{
        "block_id" => to_string(table_block.id),
        "row_ids" => Enum.map(new_order, &to_string/1)
      })

      ids = Sheets.list_table_rows(table_block.id) |> Enum.map(& &1.id)
      assert ids == new_order

      render_hook(view, "undo", %{})

      ids = Sheets.list_table_rows(table_block.id) |> Enum.map(& &1.id)
      assert ids == original_order
    end
  end

  # ===========================================================================
  # Table column type change undo/redo
  # ===========================================================================

  describe "table column type change undo/redo" do
    test "undo reverses column type change", %{conn: conn, url: url, sheet: sheet} do
      table_block = table_block_fixture(sheet, %{label: "TypeChange"})
      column = table_column_fixture(table_block, %{name: "Field"})
      # Default column type is "number" (from TableColumn schema)
      assert column.type == "number"

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "change_table_column_type", %{
        "column-id" => to_string(column.id),
        "new-type" => "text"
      })

      assert Sheets.get_table_column!(column.id).type == "text"

      render_hook(view, "undo", %{})
      assert Sheets.get_table_column!(column.id).type == "number"
    end

    test "redo re-applies column type change after undo", %{
      conn: conn,
      url: url,
      sheet: sheet
    } do
      table_block = table_block_fixture(sheet, %{label: "TypeRedo"})
      column = table_column_fixture(table_block, %{name: "Data"})
      assert column.type == "number"

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "change_table_column_type", %{
        "column-id" => to_string(column.id),
        "new-type" => "boolean"
      })

      render_hook(view, "undo", %{})
      assert Sheets.get_table_column!(column.id).type == "number"

      render_hook(view, "redo", %{})
      assert Sheets.get_table_column!(column.id).type == "boolean"
    end
  end

  # ===========================================================================
  # Table column constant toggle undo/redo
  # ===========================================================================

  describe "table column constant toggle undo/redo" do
    test "undo reverses column constant toggle", %{conn: conn, url: url, sheet: sheet} do
      table_block = table_block_fixture(sheet, %{label: "ConstToggle"})
      column = table_column_fixture(table_block, %{name: "Fixed"})
      assert column.is_constant == false

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "toggle_table_column_constant", %{
        "column-id" => to_string(column.id)
      })

      assert Sheets.get_table_column!(column.id).is_constant == true

      render_hook(view, "undo", %{})
      assert Sheets.get_table_column!(column.id).is_constant == false
    end
  end

  # ===========================================================================
  # Table column required toggle undo/redo
  # ===========================================================================

  describe "table column required toggle undo/redo" do
    test "undo reverses column required toggle", %{conn: conn, url: url, sheet: sheet} do
      table_block = table_block_fixture(sheet, %{label: "ReqToggle"})
      column = table_column_fixture(table_block, %{name: "Mandatory"})
      assert column.required == false

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "toggle_table_column_required", %{
        "column-id" => to_string(column.id)
      })

      assert Sheets.get_table_column!(column.id).required == true

      render_hook(view, "undo", %{})
      assert Sheets.get_table_column!(column.id).required == false
    end
  end

  # ===========================================================================
  # Table column config update undo/redo (via number constraint)
  # ===========================================================================

  describe "table column config update undo/redo" do
    test "undo reverses number constraint change", %{conn: conn, url: url, sheet: sheet} do
      table_block = table_block_fixture(sheet, %{label: "ConfCol"})
      column = table_column_fixture(table_block, %{name: "Level", type: "number"})
      original_config = column.config

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "update_number_constraint", %{
        "column-id" => to_string(column.id),
        "field" => "min",
        "value" => "0"
      })

      updated_config = Sheets.get_table_column!(column.id).config
      assert updated_config["min"] != nil

      render_hook(view, "undo", %{})
      assert Sheets.get_table_column!(column.id).config == original_config
    end
  end

  # ===========================================================================
  # Snapshot helpers (unit tests)
  # ===========================================================================

  describe "block_to_snapshot/1" do
    test "captures correct fields", %{sheet: sheet} do
      block =
        block_fixture(sheet, %{
          type: "number",
          config: %{"label" => "HP"},
          value: %{"content" => "100"}
        })

      snapshot = UndoRedoHandlers.block_to_snapshot(block)

      assert snapshot.id == block.id
      assert snapshot.sheet_id == block.sheet_id
      assert snapshot.type == "number"
      assert snapshot.value == %{"content" => "100"}
      assert snapshot.config == %{"label" => "HP"}
      assert snapshot.position == block.position
      assert snapshot.is_constant == block.is_constant
      assert snapshot.variable_name == block.variable_name
      assert snapshot.scope == block.scope
    end
  end

  describe "table_column_to_snapshot/1" do
    test "captures correct fields", %{sheet: sheet} do
      table_block = table_block_fixture(sheet, %{label: "Snap"})
      column = table_column_fixture(table_block, %{name: "Level"})

      snapshot = UndoRedoHandlers.table_column_to_snapshot(column)

      assert snapshot.id == column.id
      assert snapshot.block_id == column.block_id
      assert snapshot.name == "Level"
      assert snapshot.slug == column.slug
      assert snapshot.type == column.type
      assert snapshot.position == column.position
      assert snapshot.is_constant == column.is_constant
      assert snapshot.required == column.required
      assert snapshot.config == column.config
    end
  end

  describe "table_row_to_snapshot/1" do
    test "captures correct fields", %{sheet: sheet} do
      table_block = table_block_fixture(sheet, %{label: "RowSnap"})
      row = table_row_fixture(table_block, %{name: "Hero"})

      snapshot = UndoRedoHandlers.table_row_to_snapshot(row)

      assert snapshot.id == row.id
      assert snapshot.block_id == row.block_id
      assert snapshot.name == "Hero"
      assert snapshot.slug == row.slug
      assert snapshot.position == row.position
      assert snapshot.cells == row.cells
    end
  end

  describe "snapshot_column_cells/2" do
    test "captures cell values for all rows in a column", %{sheet: sheet} do
      table_block = table_block_fixture(sheet, %{label: "CellSnap"})
      column = table_column_fixture(table_block, %{name: "Value"})

      # Get default row and set a cell value
      data = Sheets.batch_load_table_data([table_block.id])
      default_row = hd(data[table_block.id].rows)
      Sheets.update_table_cell(default_row, column.slug, "hello")

      cells = UndoRedoHandlers.snapshot_column_cells(table_block.id, column.slug)

      assert is_list(cells)
      assert length(cells) >= 1

      # Should contain the row with value "hello"
      row_cell = Enum.find(cells, fn {id, _val} -> id == default_row.id end)
      assert row_cell != nil
      {_id, value} = row_cell
      assert value == "hello"
    end
  end

  # ===========================================================================
  # Coalescing helpers (unit tests with mock socket)
  # ===========================================================================

  describe "push_name_coalesced/3" do
    test "pushes new entry on empty stack" do
      socket = mock_socket()

      socket = UndoRedoHandlers.push_name_coalesced(socket, "Old", "New")

      assert socket.assigns.undo_stack == [{:update_sheet_name, "Old", "New"}]
      assert socket.assigns.redo_stack == []
    end

    test "coalesces consecutive name changes" do
      socket = mock_socket()

      socket = UndoRedoHandlers.push_name_coalesced(socket, "Original", "Mid")
      socket = UndoRedoHandlers.push_name_coalesced(socket, "Mid", "Final")

      assert socket.assigns.undo_stack == [{:update_sheet_name, "Original", "Final"}]
    end

    test "does not coalesce different action types" do
      socket =
        mock_socket(%{undo_stack: [{:update_sheet_color, nil, "#ff0000"}]})

      socket = UndoRedoHandlers.push_name_coalesced(socket, "Old", "New")

      assert length(socket.assigns.undo_stack) == 2
      assert hd(socket.assigns.undo_stack) == {:update_sheet_name, "Old", "New"}
    end
  end

  describe "push_shortcut_coalesced/3" do
    test "pushes new entry on empty stack" do
      socket = mock_socket()

      socket = UndoRedoHandlers.push_shortcut_coalesced(socket, "old", "new")

      assert socket.assigns.undo_stack == [{:update_sheet_shortcut, "old", "new"}]
    end

    test "coalesces consecutive shortcut changes" do
      socket = mock_socket()

      socket = UndoRedoHandlers.push_shortcut_coalesced(socket, "original", "mid")
      socket = UndoRedoHandlers.push_shortcut_coalesced(socket, "mid", "final")

      assert socket.assigns.undo_stack == [{:update_sheet_shortcut, "original", "final"}]
    end
  end

  describe "push_block_value_coalesced/4" do
    test "pushes new entry on empty stack" do
      socket = mock_socket()

      socket = UndoRedoHandlers.push_block_value_coalesced(socket, 123, "", "hello")

      assert socket.assigns.undo_stack == [{:update_block_value, 123, "", "hello"}]
    end

    test "coalesces consecutive updates for the same block" do
      socket = mock_socket()

      socket = UndoRedoHandlers.push_block_value_coalesced(socket, 123, "", "h")
      socket = UndoRedoHandlers.push_block_value_coalesced(socket, 123, "h", "he")
      socket = UndoRedoHandlers.push_block_value_coalesced(socket, 123, "he", "hello")

      assert socket.assigns.undo_stack == [{:update_block_value, 123, "", "hello"}]
    end

    test "does not coalesce updates for different blocks" do
      socket = mock_socket()

      socket = UndoRedoHandlers.push_block_value_coalesced(socket, 1, "", "a")
      socket = UndoRedoHandlers.push_block_value_coalesced(socket, 2, "", "b")

      assert length(socket.assigns.undo_stack) == 2
    end
  end

  describe "push_cell_coalesced/6" do
    test "pushes new entry on empty stack" do
      socket = mock_socket()

      socket = UndoRedoHandlers.push_cell_coalesced(socket, 10, 20, "col-a", nil, "val")

      assert socket.assigns.undo_stack == [{:update_table_cell, 10, 20, "col-a", nil, "val"}]
    end

    test "coalesces consecutive updates for the same cell" do
      socket = mock_socket()

      socket = UndoRedoHandlers.push_cell_coalesced(socket, 10, 20, "col-a", nil, "1")
      socket = UndoRedoHandlers.push_cell_coalesced(socket, 10, 20, "col-a", "1", "12")
      socket = UndoRedoHandlers.push_cell_coalesced(socket, 10, 20, "col-a", "12", "123")

      assert socket.assigns.undo_stack == [{:update_table_cell, 10, 20, "col-a", nil, "123"}]
    end

    test "does not coalesce updates for different cells" do
      socket = mock_socket()

      socket = UndoRedoHandlers.push_cell_coalesced(socket, 10, 20, "col-a", nil, "1")
      socket = UndoRedoHandlers.push_cell_coalesced(socket, 10, 20, "col-b", nil, "2")

      assert length(socket.assigns.undo_stack) == 2
    end

    test "does not coalesce updates for different rows" do
      socket = mock_socket()

      socket = UndoRedoHandlers.push_cell_coalesced(socket, 10, 20, "col-a", nil, "1")
      socket = UndoRedoHandlers.push_cell_coalesced(socket, 10, 30, "col-a", nil, "2")

      assert length(socket.assigns.undo_stack) == 2
    end
  end

  # ===========================================================================
  # Mixed action sequences
  # ===========================================================================

  describe "mixed undo/redo sequences" do
    test "interleaved block and color operations", %{conn: conn, url: url, sheet: sheet} do
      {:ok, view, _html} = mount_sheet(conn, url)

      # Action 1: Set color
      render_hook(view, "set_sheet_color", %{"color" => "#ff0000"})

      # Action 2: Add block
      send_to_content_tab(view, "show_block_menu")
      send_to_content_tab(view, "add_block", %{"type" => "text"})

      assert Sheets.get_sheet!(sheet.project_id, sheet.id).color == "#ff0000"
      assert length(Sheets.list_blocks(sheet.id)) == 1

      # Undo block creation
      render_hook(view, "undo", %{})
      assert Sheets.list_blocks(sheet.id) == []
      assert Sheets.get_sheet!(sheet.project_id, sheet.id).color == "#ff0000"

      # Undo color change
      render_hook(view, "undo", %{})
      assert Sheets.get_sheet!(sheet.project_id, sheet.id).color == nil

      # Redo both
      render_hook(view, "redo", %{})
      assert Sheets.get_sheet!(sheet.project_id, sheet.id).color == "#ff0000"

      render_hook(view, "redo", %{})
      assert length(Sheets.list_blocks(sheet.id)) == 1
    end
  end

  # ===========================================================================
  # Table boolean cell toggle undo/redo
  # ===========================================================================

  describe "table boolean cell toggle undo/redo" do
    test "undo reverses boolean cell toggle", %{conn: conn, url: url, sheet: sheet} do
      table_block = table_block_fixture(sheet, %{label: "BoolUndo"})
      bool_column = table_column_fixture(table_block, %{name: "Active", type: "boolean"})
      data = Sheets.batch_load_table_data([table_block.id])
      default_row = hd(data[table_block.id].rows)

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "toggle_table_cell_boolean", %{
        "row-id" => to_string(default_row.id),
        "column-slug" => bool_column.slug
      })

      assert Sheets.get_table_row!(default_row.id).cells[bool_column.slug] == true

      render_hook(view, "undo", %{})
      # Before toggle, the cell was nil/false
      cell_val = Sheets.get_table_row!(default_row.id).cells[bool_column.slug]
      assert cell_val == nil or cell_val == false
    end
  end

  # ===========================================================================
  # Sheet name undo/redo (via SheetTitle LiveComponent)
  # ===========================================================================

  describe "sheet name undo/redo" do
    test "undo reverses a sheet name change", %{conn: conn, url: url, sheet: sheet} do
      {:ok, view, _html} = mount_sheet(conn, url)

      # Update name directly, then simulate what SheetTitle component does
      {:ok, _} = Sheets.update_sheet(sheet, %{name: "Renamed Sheet"})
      updated = Sheets.get_sheet_full!(sheet.project_id, sheet.id)
      sheets_tree = Sheets.list_sheets_tree(sheet.project_id)
      send(view.pid, {:sheet_title, :name_saved, updated, sheets_tree})
      render(view)

      assert Sheets.get_sheet!(sheet.project_id, sheet.id).name == "Renamed Sheet"

      render_hook(view, "undo", %{})
      assert Sheets.get_sheet!(sheet.project_id, sheet.id).name == "Undo Redo Sheet"
    end

    test "redo re-applies name change after undo", %{conn: conn, url: url, sheet: sheet} do
      {:ok, view, _html} = mount_sheet(conn, url)

      {:ok, _} = Sheets.update_sheet(sheet, %{name: "New Name"})
      updated = Sheets.get_sheet_full!(sheet.project_id, sheet.id)
      sheets_tree = Sheets.list_sheets_tree(sheet.project_id)
      send(view.pid, {:sheet_title, :name_saved, updated, sheets_tree})
      render(view)

      render_hook(view, "undo", %{})
      assert Sheets.get_sheet!(sheet.project_id, sheet.id).name == "Undo Redo Sheet"

      render_hook(view, "redo", %{})
      assert Sheets.get_sheet!(sheet.project_id, sheet.id).name == "New Name"
    end
  end

  # ===========================================================================
  # Sheet shortcut undo/redo (via SheetTitle LiveComponent)
  # ===========================================================================

  describe "sheet shortcut undo/redo" do
    test "undo reverses a shortcut change", %{conn: conn, url: url, sheet: sheet} do
      {:ok, view, _html} = mount_sheet(conn, url)

      original_shortcut = Sheets.get_sheet!(sheet.project_id, sheet.id).shortcut

      {:ok, _} = Sheets.update_sheet(sheet, %{shortcut: "new-sc"})
      updated = Sheets.get_sheet_full!(sheet.project_id, sheet.id)
      send(view.pid, {:sheet_title, :shortcut_saved, updated})
      render(view)

      assert Sheets.get_sheet!(sheet.project_id, sheet.id).shortcut == "new-sc"

      render_hook(view, "undo", %{})
      assert Sheets.get_sheet!(sheet.project_id, sheet.id).shortcut == original_shortcut
    end

    test "redo re-applies shortcut change after undo", %{conn: conn, url: url, sheet: sheet} do
      {:ok, view, _html} = mount_sheet(conn, url)

      {:ok, _} = Sheets.update_sheet(sheet, %{shortcut: "redone"})
      updated = Sheets.get_sheet_full!(sheet.project_id, sheet.id)
      send(view.pid, {:sheet_title, :shortcut_saved, updated})
      render(view)

      assert Sheets.get_sheet!(sheet.project_id, sheet.id).shortcut == "redone"

      render_hook(view, "undo", %{})
      refute Sheets.get_sheet!(sheet.project_id, sheet.id).shortcut == "redone"

      render_hook(view, "redo", %{})
      assert Sheets.get_sheet!(sheet.project_id, sheet.id).shortcut == "redone"
    end
  end

  # ===========================================================================
  # Block reorder redo (explicit)
  # ===========================================================================

  describe "block reorder redo" do
    test "redo re-applies block reorder after undo", %{conn: conn, url: url, sheet: sheet} do
      b1 = block_fixture(sheet, %{type: "text", config: %{"label" => "RedoA"}})
      b2 = block_fixture(sheet, %{type: "text", config: %{"label" => "RedoB"}})

      {:ok, view, _html} = mount_sheet(conn, url)

      new_order = [to_string(b2.id), to_string(b1.id)]
      send_to_content_tab(view, "reorder", %{"ids" => new_order, "group" => "blocks"})

      render_hook(view, "undo", %{})
      ids = Sheets.list_blocks(sheet.id) |> Enum.map(& &1.id)
      assert ids == [b1.id, b2.id]

      render_hook(view, "redo", %{})
      ids = Sheets.list_blocks(sheet.id) |> Enum.map(& &1.id)
      assert ids == [b2.id, b1.id]
    end
  end

  # ===========================================================================
  # Table column delete redo
  # ===========================================================================

  describe "table column delete redo" do
    test "redo re-deletes column after undo", %{conn: conn, url: url, sheet: sheet} do
      table_block = table_block_fixture(sheet, %{label: "DelColRedo"})
      column = table_column_fixture(table_block, %{name: "Extra"})
      initial_data = Sheets.batch_load_table_data([table_block.id])
      initial_count = length(initial_data[table_block.id].columns)

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "delete_table_column", %{"column-id" => to_string(column.id)})
      data = Sheets.batch_load_table_data([table_block.id])
      assert length(data[table_block.id].columns) == initial_count - 1

      render_hook(view, "undo", %{})
      data = Sheets.batch_load_table_data([table_block.id])
      assert length(data[table_block.id].columns) == initial_count

      render_hook(view, "redo", %{})
      data = Sheets.batch_load_table_data([table_block.id])
      assert length(data[table_block.id].columns) == initial_count - 1
    end
  end

  # ===========================================================================
  # Table row delete redo
  # ===========================================================================

  describe "table row delete redo" do
    test "redo re-deletes row after undo", %{conn: conn, url: url, sheet: sheet} do
      table_block = table_block_fixture(sheet, %{label: "DelRowRedo"})
      row = table_row_fixture(table_block, %{name: "Temp"})
      initial_data = Sheets.batch_load_table_data([table_block.id])
      initial_count = length(initial_data[table_block.id].rows)

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "delete_table_row", %{"row-id" => to_string(row.id)})
      data = Sheets.batch_load_table_data([table_block.id])
      assert length(data[table_block.id].rows) == initial_count - 1

      render_hook(view, "undo", %{})
      data = Sheets.batch_load_table_data([table_block.id])
      assert length(data[table_block.id].rows) == initial_count

      render_hook(view, "redo", %{})
      data = Sheets.batch_load_table_data([table_block.id])
      assert length(data[table_block.id].rows) == initial_count - 1
    end
  end

  # ===========================================================================
  # Table row reorder redo
  # ===========================================================================

  describe "table row reorder redo" do
    test "redo re-applies row reorder after undo", %{conn: conn, url: url, sheet: sheet} do
      table_block = table_block_fixture(sheet, %{label: "ReorderRedo"})
      row2 = table_row_fixture(table_block, %{name: "Second"})
      row3 = table_row_fixture(table_block, %{name: "Third"})

      data = Sheets.batch_load_table_data([table_block.id])
      default_row = hd(data[table_block.id].rows)

      original_order = Sheets.list_table_rows(table_block.id) |> Enum.map(& &1.id)
      new_order = [row3.id, default_row.id, row2.id]

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "reorder_table_rows", %{
        "block_id" => to_string(table_block.id),
        "row_ids" => Enum.map(new_order, &to_string/1)
      })

      ids = Sheets.list_table_rows(table_block.id) |> Enum.map(& &1.id)
      assert ids == new_order

      render_hook(view, "undo", %{})
      ids = Sheets.list_table_rows(table_block.id) |> Enum.map(& &1.id)
      assert ids == original_order

      render_hook(view, "redo", %{})
      ids = Sheets.list_table_rows(table_block.id) |> Enum.map(& &1.id)
      assert ids == new_order
    end
  end

  # ===========================================================================
  # Table column config update redo
  # ===========================================================================

  describe "table column config update redo" do
    test "redo re-applies column config after undo", %{conn: conn, url: url, sheet: sheet} do
      table_block = table_block_fixture(sheet, %{label: "ConfRedo"})
      column = table_column_fixture(table_block, %{name: "Score", type: "number"})
      original_config = column.config

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "update_number_constraint", %{
        "column-id" => to_string(column.id),
        "field" => "min",
        "value" => "10"
      })

      updated_config = Sheets.get_table_column!(column.id).config
      assert updated_config != original_config

      render_hook(view, "undo", %{})
      assert Sheets.get_table_column!(column.id).config == original_config

      render_hook(view, "redo", %{})
      assert Sheets.get_table_column!(column.id).config == updated_config
    end
  end

  # ===========================================================================
  # Table column constant toggle redo
  # ===========================================================================

  describe "table column constant toggle redo" do
    test "redo re-applies column constant toggle after undo", %{
      conn: conn,
      url: url,
      sheet: sheet
    } do
      table_block = table_block_fixture(sheet, %{label: "ConstRedo"})
      column = table_column_fixture(table_block, %{name: "Locked"})
      assert column.is_constant == false

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "toggle_table_column_constant", %{
        "column-id" => to_string(column.id)
      })

      assert Sheets.get_table_column!(column.id).is_constant == true

      render_hook(view, "undo", %{})
      assert Sheets.get_table_column!(column.id).is_constant == false

      render_hook(view, "redo", %{})
      assert Sheets.get_table_column!(column.id).is_constant == true
    end
  end

  # ===========================================================================
  # Table column required toggle redo
  # ===========================================================================

  describe "table column required toggle redo" do
    test "redo re-applies column required toggle after undo", %{
      conn: conn,
      url: url,
      sheet: sheet
    } do
      table_block = table_block_fixture(sheet, %{label: "ReqRedo"})
      column = table_column_fixture(table_block, %{name: "Must"})
      assert column.required == false

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "toggle_table_column_required", %{
        "column-id" => to_string(column.id)
      })

      assert Sheets.get_table_column!(column.id).required == true

      render_hook(view, "undo", %{})
      assert Sheets.get_table_column!(column.id).required == false

      render_hook(view, "redo", %{})
      assert Sheets.get_table_column!(column.id).required == true
    end
  end

  # ===========================================================================
  # Compound action undo/redo (delete block with table data)
  # ===========================================================================

  describe "compound action undo/redo" do
    test "undo and redo compound action via add_table_cell_option", %{
      conn: conn,
      url: url,
      sheet: sheet
    } do
      # Create a select column — adding a new option at cell level creates a compound action
      table_block = table_block_fixture(sheet, %{label: "CompoundSelect"})
      column = table_column_fixture(table_block, %{name: "Status", type: "select"})
      data = Sheets.batch_load_table_data([table_block.id])
      default_row = hd(data[table_block.id].rows)

      {:ok, view, _html} = mount_sheet(conn, url)

      # Add a new option at cell level — this creates a compound action
      # (column config update + cell value update)
      send_to_content_tab(view, "add_table_cell_option", %{
        "key" => "Enter",
        "column-id" => to_string(column.id),
        "row-id" => to_string(default_row.id),
        "column-slug" => column.slug,
        "value" => "Active"
      })

      # Verify the option was added to column config
      updated_col = Sheets.get_table_column!(column.id)
      assert Enum.any?(updated_col.config["options"] || [], &(&1["value"] == "Active"))

      # Verify cell was set
      row = Sheets.get_table_row!(default_row.id)
      assert row.cells[column.slug] != nil

      # Undo the compound action — should revert both config and cell
      render_hook(view, "undo", %{})
      col_after_undo = Sheets.get_table_column!(column.id)
      refute Enum.any?(col_after_undo.config["options"] || [], &(&1["value"] == "Active"))

      row_after_undo = Sheets.get_table_row!(default_row.id)
      assert row_after_undo.cells[column.slug] == nil

      # Redo should restore both
      render_hook(view, "redo", %{})
      col_after_redo = Sheets.get_table_column!(column.id)
      assert Enum.any?(col_after_redo.config["options"] || [], &(&1["value"] == "Active"))
    end
  end

  # ===========================================================================
  # Undo/redo with deleted entities (error handling paths)
  # ===========================================================================

  describe "undo with deleted entities" do
    test "undo create_block when block was already deleted is no-op", %{
      conn: conn,
      url: url,
      sheet: sheet
    } do
      {:ok, view, _html} = mount_sheet(conn, url)

      # Create a block
      send_to_content_tab(view, "show_block_menu")
      send_to_content_tab(view, "add_block", %{"type" => "text"})
      [block] = Sheets.list_blocks(sheet.id)

      # Delete the block out-of-band (simulating a concurrent deletion)
      Sheets.delete_block(block)

      # Undo should handle the missing block gracefully
      render_hook(view, "undo", %{})
      # Should not crash — block was already gone
      assert render(view) =~ "Undo Redo Sheet"
    end

    test "undo update_block_value when block was deleted is no-op", %{
      conn: conn,
      url: url,
      sheet: sheet
    } do
      block = block_fixture(sheet, %{type: "text", config: %{"label" => "Ghost"}})

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "update_block_value", %{
        "id" => to_string(block.id),
        "value" => "Updated"
      })

      # Delete block out-of-band
      Sheets.delete_block(block)

      # Undo should not crash
      render_hook(view, "undo", %{})
      assert render(view) =~ "Undo Redo Sheet"
    end

    test "undo update_block_config when block was deleted is no-op", %{
      conn: conn,
      url: url,
      sheet: sheet
    } do
      block = block_fixture(sheet, %{type: "text", config: %{"label" => "Gone"}})

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "configure_block", %{"id" => to_string(block.id)})

      send_to_content_tab(view, "save_block_config", %{
        "config" => %{"label" => "NewConfig"}
      })

      # Delete block out-of-band
      Sheets.delete_block(block)

      # Undo should not crash
      render_hook(view, "undo", %{})
      assert render(view) =~ "Undo Redo Sheet"
    end

    test "undo toggle_constant when block was deleted is no-op", %{
      conn: conn,
      url: url,
      sheet: sheet
    } do
      block = block_fixture(sheet, %{type: "text", config: %{"label" => "Vanished"}})

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "configure_block", %{"id" => to_string(block.id)})
      send_to_content_tab(view, "toggle_constant")

      # Delete block out-of-band
      Sheets.delete_block(Sheets.get_block(block.id))

      # Undo should not crash
      render_hook(view, "undo", %{})
      assert render(view) =~ "Undo Redo Sheet"
    end

    test "undo add_table_column when column was already deleted is no-op", %{
      conn: conn,
      url: url,
      sheet: sheet
    } do
      table_block = table_block_fixture(sheet, %{label: "GhostCol"})

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "add_table_column", %{"block-id" => to_string(table_block.id)})
      data = Sheets.batch_load_table_data([table_block.id])
      new_column = List.last(data[table_block.id].columns)

      # Delete column out-of-band
      Sheets.delete_table_column(new_column)

      # Undo should not crash
      render_hook(view, "undo", %{})
      assert render(view) =~ "Undo Redo Sheet"
    end

    test "undo add_table_row when row was already deleted is no-op", %{
      conn: conn,
      url: url,
      sheet: sheet
    } do
      table_block = table_block_fixture(sheet, %{label: "GhostRow"})

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "add_table_row", %{"block-id" => to_string(table_block.id)})
      data = Sheets.batch_load_table_data([table_block.id])
      new_row = List.last(data[table_block.id].rows)

      # Delete row out-of-band
      Sheets.delete_table_row(new_row)

      # Undo should not crash
      render_hook(view, "undo", %{})
      assert render(view) =~ "Undo Redo Sheet"
    end

    test "undo update_table_cell when row was deleted is no-op", %{
      conn: conn,
      url: url,
      sheet: sheet
    } do
      table_block = table_block_fixture(sheet, %{label: "GhostCell"})
      column = table_column_fixture(table_block, %{name: "Val"})
      # Add a second row so we can delete the first one
      _extra_row = table_row_fixture(table_block, %{name: "Extra"})
      data = Sheets.batch_load_table_data([table_block.id])
      default_row = hd(data[table_block.id].rows)

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "update_table_cell", %{
        "row-id" => to_string(default_row.id),
        "column-slug" => column.slug,
        "value" => "deleted"
      })

      # Delete row out-of-band (need 2+ rows so delete_table_row succeeds)
      Sheets.delete_table_row(Sheets.get_table_row(default_row.id))

      # Undo should not crash
      render_hook(view, "undo", %{})
      assert render(view) =~ "Undo Redo Sheet"
    end

    test "undo rename_table_column when column was deleted is no-op", %{
      conn: conn,
      url: url,
      sheet: sheet
    } do
      table_block = table_block_fixture(sheet, %{label: "GhostRenCol"})
      column = table_column_fixture(table_block, %{name: "Original"})

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "rename_table_column", %{
        "column-id" => to_string(column.id),
        "value" => "Renamed"
      })

      # Delete column out-of-band
      Sheets.delete_table_column(Sheets.get_table_column(column.id))

      # Undo should not crash
      render_hook(view, "undo", %{})
      assert render(view) =~ "Undo Redo Sheet"
    end

    test "undo rename_table_row when row was deleted is no-op", %{
      conn: conn,
      url: url,
      sheet: sheet
    } do
      table_block = table_block_fixture(sheet, %{label: "GhostRenRow"})
      row = table_row_fixture(table_block, %{name: "Original"})

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "rename_table_row", %{
        "row-id" => to_string(row.id),
        "value" => "Renamed"
      })

      # Delete row out-of-band
      Sheets.delete_table_row(Sheets.get_table_row(row.id))

      # Undo should not crash
      render_hook(view, "undo", %{})
      assert render(view) =~ "Undo Redo Sheet"
    end

    test "undo update_table_column_config when column was deleted is no-op", %{
      conn: conn,
      url: url,
      sheet: sheet
    } do
      table_block = table_block_fixture(sheet, %{label: "GhostColConf"})
      column = table_column_fixture(table_block, %{name: "Cfg", type: "number"})

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "update_number_constraint", %{
        "column-id" => to_string(column.id),
        "field" => "min",
        "value" => "5"
      })

      # Delete column out-of-band
      Sheets.delete_table_column(Sheets.get_table_column(column.id))

      # Undo should not crash
      render_hook(view, "undo", %{})
      assert render(view) =~ "Undo Redo Sheet"
    end

    test "undo toggle_column_flag when column was deleted is no-op", %{
      conn: conn,
      url: url,
      sheet: sheet
    } do
      table_block = table_block_fixture(sheet, %{label: "GhostFlag"})
      column = table_column_fixture(table_block, %{name: "Flagged"})

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "toggle_table_column_constant", %{
        "column-id" => to_string(column.id)
      })

      # Delete column out-of-band
      Sheets.delete_table_column(Sheets.get_table_column(column.id))

      # Undo should not crash
      render_hook(view, "undo", %{})
      assert render(view) =~ "Undo Redo Sheet"
    end

    test "undo change_column_type when column was deleted is no-op", %{
      conn: conn,
      url: url,
      sheet: sheet
    } do
      table_block = table_block_fixture(sheet, %{label: "GhostType"})
      column = table_column_fixture(table_block, %{name: "Typed"})

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "change_table_column_type", %{
        "column-id" => to_string(column.id),
        "new-type" => "text"
      })

      # Delete column out-of-band
      Sheets.delete_table_column(Sheets.get_table_column(column.id))

      # Undo should not crash
      render_hook(view, "undo", %{})
      assert render(view) =~ "Undo Redo Sheet"
    end
  end

  # ===========================================================================
  # Redo with deleted entities (error handling paths)
  # ===========================================================================

  describe "redo with deleted entities" do
    test "redo delete_block when block was already deleted is no-op", %{
      conn: conn,
      url: url,
      sheet: sheet
    } do
      block = block_fixture(sheet, %{type: "text", config: %{"label" => "RedoGhost"}})

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "delete_block", %{"id" => to_string(block.id)})
      render_hook(view, "undo", %{})
      blocks = Sheets.list_blocks(sheet.id)
      assert length(blocks) == 1

      # Now re-delete out-of-band
      Sheets.delete_block(hd(blocks))

      # Redo should not crash even though block is gone
      render_hook(view, "redo", %{})
      assert render(view) =~ "Undo Redo Sheet"
    end

    test "redo update_block_value when block was deleted is no-op", %{
      conn: conn,
      url: url,
      sheet: sheet
    } do
      block = block_fixture(sheet, %{type: "text", config: %{"label" => "RedoVal"}})

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "update_block_value", %{
        "id" => to_string(block.id),
        "value" => "X"
      })

      render_hook(view, "undo", %{})
      # Delete block out-of-band
      Sheets.delete_block(Sheets.get_block(block.id))

      # Redo should not crash
      render_hook(view, "redo", %{})
      assert render(view) =~ "Undo Redo Sheet"
    end

    test "redo update_block_config when block was deleted is no-op", %{
      conn: conn,
      url: url,
      sheet: sheet
    } do
      block = block_fixture(sheet, %{type: "text", config: %{"label" => "RedoConf"}})

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "configure_block", %{"id" => to_string(block.id)})

      send_to_content_tab(view, "save_block_config", %{
        "config" => %{"label" => "Changed"}
      })

      render_hook(view, "undo", %{})
      Sheets.delete_block(Sheets.get_block(block.id))

      render_hook(view, "redo", %{})
      assert render(view) =~ "Undo Redo Sheet"
    end

    test "redo toggle_constant when block was deleted is no-op", %{
      conn: conn,
      url: url,
      sheet: sheet
    } do
      block = block_fixture(sheet, %{type: "text", config: %{"label" => "RedoConst"}})

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "configure_block", %{"id" => to_string(block.id)})
      send_to_content_tab(view, "toggle_constant")

      render_hook(view, "undo", %{})
      Sheets.delete_block(Sheets.get_block(block.id))

      render_hook(view, "redo", %{})
      assert render(view) =~ "Undo Redo Sheet"
    end

    test "redo delete_table_column when column was already deleted is no-op", %{
      conn: conn,
      url: url,
      sheet: sheet
    } do
      table_block = table_block_fixture(sheet, %{label: "RedoDelCol"})
      column = table_column_fixture(table_block, %{name: "ToDelete"})
      initial_data = Sheets.batch_load_table_data([table_block.id])
      _initial_count = length(initial_data[table_block.id].columns)

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "delete_table_column", %{"column-id" => to_string(column.id)})
      render_hook(view, "undo", %{})

      # After undo, column is recreated (possibly with new ID)
      # Delete ALL non-default columns out-of-band
      data = Sheets.batch_load_table_data([table_block.id])

      for col <- data[table_block.id].columns,
          col.id != hd(initial_data[table_block.id].columns).id do
        Sheets.delete_table_column(col)
      end

      # Redo should not crash even though column is gone
      render_hook(view, "redo", %{})
      assert render(view) =~ "Undo Redo Sheet"
    end

    test "redo delete_table_row when row was already deleted is no-op", %{
      conn: conn,
      url: url,
      sheet: sheet
    } do
      table_block = table_block_fixture(sheet, %{label: "RedoDelRow"})
      row = table_row_fixture(table_block, %{name: "ToDeleteRow"})

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "delete_table_row", %{"row-id" => to_string(row.id)})
      render_hook(view, "undo", %{})

      # After undo, row is recreated with possibly new ID - delete all rows
      for r <- Sheets.list_table_rows(table_block.id) do
        Sheets.delete_table_row(r)
      end

      # Redo should not crash even though row is gone
      render_hook(view, "redo", %{})
      assert render(view) =~ "Undo Redo Sheet"
    end

    test "redo update_table_cell when row was deleted is no-op", %{
      conn: conn,
      url: url,
      sheet: sheet
    } do
      table_block = table_block_fixture(sheet, %{label: "RedoGhostCell"})
      column = table_column_fixture(table_block, %{name: "CellVal"})
      data = Sheets.batch_load_table_data([table_block.id])
      default_row = hd(data[table_block.id].rows)

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "update_table_cell", %{
        "row-id" => to_string(default_row.id),
        "column-slug" => column.slug,
        "value" => "redo-me"
      })

      render_hook(view, "undo", %{})
      Sheets.delete_table_row(Sheets.get_table_row(default_row.id))

      render_hook(view, "redo", %{})
      assert render(view) =~ "Undo Redo Sheet"
    end

    test "redo rename_table_column when column was deleted is no-op", %{
      conn: conn,
      url: url,
      sheet: sheet
    } do
      table_block = table_block_fixture(sheet, %{label: "RedoRenCol"})
      column = table_column_fixture(table_block, %{name: "Before"})

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "rename_table_column", %{
        "column-id" => to_string(column.id),
        "value" => "After"
      })

      render_hook(view, "undo", %{})
      Sheets.delete_table_column(Sheets.get_table_column(column.id))

      render_hook(view, "redo", %{})
      assert render(view) =~ "Undo Redo Sheet"
    end

    test "redo rename_table_row when row was deleted is no-op", %{
      conn: conn,
      url: url,
      sheet: sheet
    } do
      table_block = table_block_fixture(sheet, %{label: "RedoRenRow"})
      row = table_row_fixture(table_block, %{name: "Before"})

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "rename_table_row", %{
        "row-id" => to_string(row.id),
        "value" => "After"
      })

      render_hook(view, "undo", %{})
      Sheets.delete_table_row(Sheets.get_table_row(row.id))

      render_hook(view, "redo", %{})
      assert render(view) =~ "Undo Redo Sheet"
    end

    test "redo update_table_column_config when column was deleted is no-op", %{
      conn: conn,
      url: url,
      sheet: sheet
    } do
      table_block = table_block_fixture(sheet, %{label: "RedoColConf"})
      column = table_column_fixture(table_block, %{name: "Conf", type: "number"})

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "update_number_constraint", %{
        "column-id" => to_string(column.id),
        "field" => "max",
        "value" => "100"
      })

      render_hook(view, "undo", %{})
      Sheets.delete_table_column(Sheets.get_table_column(column.id))

      render_hook(view, "redo", %{})
      assert render(view) =~ "Undo Redo Sheet"
    end

    test "redo toggle_column_flag when column was deleted is no-op", %{
      conn: conn,
      url: url,
      sheet: sheet
    } do
      table_block = table_block_fixture(sheet, %{label: "RedoFlag"})
      column = table_column_fixture(table_block, %{name: "FlagCol"})

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "toggle_table_column_constant", %{
        "column-id" => to_string(column.id)
      })

      render_hook(view, "undo", %{})
      Sheets.delete_table_column(Sheets.get_table_column(column.id))

      render_hook(view, "redo", %{})
      assert render(view) =~ "Undo Redo Sheet"
    end

    test "redo change_column_type when column was deleted is no-op", %{
      conn: conn,
      url: url,
      sheet: sheet
    } do
      table_block = table_block_fixture(sheet, %{label: "RedoType"})
      column = table_column_fixture(table_block, %{name: "TypeCol"})

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "change_table_column_type", %{
        "column-id" => to_string(column.id),
        "new-type" => "text"
      })

      render_hook(view, "undo", %{})
      Sheets.delete_table_column(Sheets.get_table_column(column.id))

      render_hook(view, "redo", %{})
      assert render(view) =~ "Undo Redo Sheet"
    end
  end

  # ===========================================================================
  # Fallback / unknown action types (unit tests)
  # ===========================================================================

  describe "unknown action fallback" do
    test "undo with unknown action type returns error tuple" do
      socket =
        mock_socket(%{
          undo_stack: [{:unknown_action, "data"}],
          redo_stack: [],
          sheet: %{id: Ecto.UUID.generate(), name: "Test"},
          project: %{id: Ecto.UUID.generate()}
        })

      # Directly call handle_undo — it should not crash
      result = UndoRedoHandlers.handle_undo(%{}, socket)
      assert {:noreply, _socket} = result
    end

    test "redo with unknown action type returns error tuple" do
      socket =
        mock_socket(%{
          undo_stack: [],
          redo_stack: [{:unknown_action, "data"}],
          sheet: %{id: Ecto.UUID.generate(), name: "Test"},
          project: %{id: Ecto.UUID.generate()}
        })

      result = UndoRedoHandlers.handle_redo(%{}, socket)
      assert {:noreply, _socket} = result
    end
  end

  # ===========================================================================
  # Coalescing edge cases (unit tests)
  # ===========================================================================

  describe "coalescing edge cases" do
    test "push_shortcut_coalesced does not coalesce with different action types" do
      socket =
        mock_socket(%{undo_stack: [{:update_sheet_name, "old", "new"}]})

      socket = UndoRedoHandlers.push_shortcut_coalesced(socket, "old-sc", "new-sc")

      # Should have two items — name action + shortcut action
      assert length(socket.assigns.undo_stack) == 2
      assert hd(socket.assigns.undo_stack) == {:update_sheet_shortcut, "old-sc", "new-sc"}
    end

    test "push_cell_coalesced does not coalesce updates for different blocks" do
      socket = mock_socket()

      socket = UndoRedoHandlers.push_cell_coalesced(socket, 10, 20, "col-a", nil, "1")
      socket = UndoRedoHandlers.push_cell_coalesced(socket, 99, 20, "col-a", nil, "2")

      assert length(socket.assigns.undo_stack) == 2
    end

    test "push_block_value_coalesced does not coalesce with non-block-value on stack" do
      socket =
        mock_socket(%{undo_stack: [{:update_sheet_color, nil, "#ff0000"}]})

      socket = UndoRedoHandlers.push_block_value_coalesced(socket, 42, "", "val")

      assert length(socket.assigns.undo_stack) == 2
    end
  end

  # ===========================================================================
  # Redo happy paths for action types only tested through undo
  # ===========================================================================

  describe "block value redo happy path" do
    test "redo re-applies block value after undo", %{conn: conn, url: url, sheet: sheet} do
      block = block_fixture(sheet, %{type: "text", config: %{"label" => "Redo"}})

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "update_block_value", %{
        "id" => to_string(block.id),
        "value" => "New Value"
      })

      assert Sheets.get_block(block.id).value["content"] == "New Value"

      render_hook(view, "undo", %{})
      assert Sheets.get_block(block.id).value["content"] == ""

      render_hook(view, "redo", %{})
      assert Sheets.get_block(block.id).value["content"] == "New Value"
    end
  end
end
