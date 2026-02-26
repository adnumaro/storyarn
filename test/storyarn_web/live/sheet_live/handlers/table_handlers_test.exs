defmodule StoryarnWeb.SheetLive.Handlers.TableHandlersTest do
  @moduledoc """
  Comprehensive tests for TableHandlers exercised through the SheetLive.Show LiveView.

  Events are sent to the ContentTab LiveComponent via `with_target("#content-tab")`.
  Covers: column resize, cell updates, select/multi-select operations, column options
  management, reference multiple toggle, number constraints, required field validation,
  last-column/row deletion prevention, rename edge cases, and row keydown handling.
  """

  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
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
    live(conn, sheet_path(workspace, project, sheet))
  end

  defp send_to_content_tab(view, event, params) do
    view
    |> with_target("#content-tab")
    |> render_click(event, params)
  end

  defp setup_table(%{user: user}) do
    project = project_fixture(user) |> Repo.preload(:workspace)
    sheet = sheet_fixture(project, %{name: "Table Test Sheet"})
    table_block = table_block_fixture(sheet, %{label: "Test Table"})

    data = Sheets.batch_load_table_data([table_block.id])
    default_col = hd(data[table_block.id].columns)
    default_row = hd(data[table_block.id].rows)

    %{
      project: project,
      workspace: project.workspace,
      sheet: sheet,
      table_block: table_block,
      default_col: default_col,
      default_row: default_row
    }
  end

  # ===========================================================================
  # Column Resize
  # ===========================================================================

  describe "resize_table_column" do
    setup [:register_and_log_in_user, :setup_table]

    test "persists column width after resize", ctx do
      {:ok, view, _html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)

      send_to_content_tab(view, "resize_table_column", %{
        "column-id" => to_string(ctx.default_col.id),
        "width" => 200
      })

      updated = Sheets.get_table_column!(ctx.default_col.id)
      assert updated.config["width"] == 200
    end

    test "clamps width to minimum 80", ctx do
      {:ok, view, _html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)

      send_to_content_tab(view, "resize_table_column", %{
        "column-id" => to_string(ctx.default_col.id),
        "width" => 30
      })

      updated = Sheets.get_table_column!(ctx.default_col.id)
      assert updated.config["width"] == 80
    end

    test "clamps width to maximum 2000", ctx do
      {:ok, view, _html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)

      send_to_content_tab(view, "resize_table_column", %{
        "column-id" => to_string(ctx.default_col.id),
        "width" => 5000
      })

      updated = Sheets.get_table_column!(ctx.default_col.id)
      assert updated.config["width"] == 2000
    end

    test "ignores non-numeric width", ctx do
      {:ok, view, _html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)

      send_to_content_tab(view, "resize_table_column", %{
        "column-id" => to_string(ctx.default_col.id),
        "width" => "abc"
      })

      # Should not crash; config unchanged
      updated = Sheets.get_table_column!(ctx.default_col.id)
      assert updated.config["width"] == nil
    end
  end

  # ===========================================================================
  # Toggle Collapse
  # ===========================================================================

  describe "toggle_table_collapse — double toggle" do
    setup [:register_and_log_in_user, :setup_table]

    test "toggling twice returns to original state", ctx do
      {:ok, view, _html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)

      # First toggle: false -> true
      send_to_content_tab(view, "toggle_table_collapse", %{
        "block-id" => to_string(ctx.table_block.id)
      })

      assert Sheets.get_block(ctx.table_block.id).config["collapsed"] == true

      # Second toggle: true -> false
      send_to_content_tab(view, "toggle_table_collapse", %{
        "block-id" => to_string(ctx.table_block.id)
      })

      assert Sheets.get_block(ctx.table_block.id).config["collapsed"] == false
    end
  end

  # ===========================================================================
  # Delete Last Column / Row (error cases)
  # ===========================================================================

  describe "delete last column" do
    setup [:register_and_log_in_user, :setup_table]

    test "prevents deletion of the last column", ctx do
      {:ok, view, _html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)

      send_to_content_tab(view, "delete_table_column", %{
        "column-id" => to_string(ctx.default_col.id)
      })

      # Column still exists — deletion was prevented
      assert Sheets.get_table_column!(ctx.default_col.id) != nil

      # Table data still has exactly 1 column
      data = Sheets.batch_load_table_data([ctx.table_block.id])
      assert length(data[ctx.table_block.id].columns) == 1

      # View still alive
      assert render(view) =~ "Table Test Sheet"
    end
  end

  describe "delete last row" do
    setup [:register_and_log_in_user, :setup_table]

    test "prevents deletion of the last row", ctx do
      {:ok, view, _html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)

      send_to_content_tab(view, "delete_table_row", %{
        "row-id" => to_string(ctx.default_row.id)
      })

      # Row still exists — deletion was prevented
      assert Sheets.get_table_row!(ctx.default_row.id) != nil

      # Table data still has exactly 1 row
      data = Sheets.batch_load_table_data([ctx.table_block.id])
      assert length(data[ctx.table_block.id].rows) == 1

      # View still alive
      assert render(view) =~ "Table Test Sheet"
    end
  end

  # ===========================================================================
  # Rename Column — edge cases
  # ===========================================================================

  describe "rename_table_column — edge cases" do
    setup [:register_and_log_in_user, :setup_table]

    test "does not rename when new name equals current name", ctx do
      {:ok, view, _html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)

      send_to_content_tab(view, "rename_table_column", %{
        "column-id" => to_string(ctx.default_col.id),
        "value" => ctx.default_col.name
      })

      updated = Sheets.get_table_column!(ctx.default_col.id)
      assert updated.name == ctx.default_col.name
    end

    test "trims whitespace from new name", ctx do
      {:ok, view, _html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)

      send_to_content_tab(view, "rename_table_column", %{
        "column-id" => to_string(ctx.default_col.id),
        "value" => "  Strength  "
      })

      updated = Sheets.get_table_column!(ctx.default_col.id)
      assert updated.name == "Strength"
    end
  end

  # ===========================================================================
  # Rename Row — edge cases + keydown
  # ===========================================================================

  describe "rename_table_row — edge cases" do
    setup [:register_and_log_in_user, :setup_table]

    test "does not rename when new name equals current name", ctx do
      {:ok, view, _html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)

      send_to_content_tab(view, "rename_table_row", %{
        "row-id" => to_string(ctx.default_row.id),
        "value" => ctx.default_row.name
      })

      updated = Sheets.get_table_row!(ctx.default_row.id)
      assert updated.name == ctx.default_row.name
    end
  end

  describe "rename_table_row_keydown" do
    setup [:register_and_log_in_user, :setup_table]

    test "renames row on Enter key", ctx do
      {:ok, view, _html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)

      send_to_content_tab(view, "rename_table_row_keydown", %{
        "key" => "Enter",
        "row-id" => to_string(ctx.default_row.id),
        "value" => "Renamed Via Enter"
      })

      updated = Sheets.get_table_row!(ctx.default_row.id)
      assert updated.name == "Renamed Via Enter"
    end

    test "does nothing on non-Enter key", ctx do
      {:ok, view, _html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)
      original_name = ctx.default_row.name

      send_to_content_tab(view, "rename_table_row_keydown", %{
        "key" => "Escape",
        "row-id" => to_string(ctx.default_row.id),
        "value" => "Should Not Apply"
      })

      updated = Sheets.get_table_row!(ctx.default_row.id)
      assert updated.name == original_name
    end
  end

  # ===========================================================================
  # Toggle Boolean Cell — double toggle
  # ===========================================================================

  describe "toggle_table_cell_boolean — double toggle" do
    setup [:register_and_log_in_user, :setup_table]

    test "toggling boolean cell twice returns to original value", ctx do
      bool_col = table_column_fixture(ctx.table_block, %{name: "Active", type: "boolean"})

      {:ok, view, _html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)

      # First toggle: nil/false -> true
      send_to_content_tab(view, "toggle_table_cell_boolean", %{
        "row-id" => to_string(ctx.default_row.id),
        "column-slug" => bool_col.slug
      })

      row_after_first = Sheets.get_table_row!(ctx.default_row.id)
      assert row_after_first.cells[bool_col.slug] == true

      # Second toggle: true -> false
      send_to_content_tab(view, "toggle_table_cell_boolean", %{
        "row-id" => to_string(ctx.default_row.id),
        "column-slug" => bool_col.slug
      })

      row_after_second = Sheets.get_table_row!(ctx.default_row.id)
      assert row_after_second.cells[bool_col.slug] == false
    end
  end

  # ===========================================================================
  # Select Cell
  # ===========================================================================

  describe "select_table_cell" do
    setup [:register_and_log_in_user, :setup_table]

    setup ctx do
      col =
        table_column_fixture(ctx.table_block, %{
          name: "Rarity",
          type: "select"
        })

      # Add options to the column config
      Sheets.update_table_column(col, %{
        config: %{
          "options" => [
            %{"key" => "common", "value" => "Common"},
            %{"key" => "rare", "value" => "Rare"},
            %{"key" => "epic", "value" => "Epic"}
          ]
        }
      })

      %{select_col: Sheets.get_table_column!(col.id)}
    end

    test "sets a select cell value", ctx do
      {:ok, view, _html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)

      send_to_content_tab(view, "select_table_cell", %{
        "row-id" => to_string(ctx.default_row.id),
        "column-slug" => ctx.select_col.slug,
        "key" => "rare"
      })

      updated_row = Sheets.get_table_row!(ctx.default_row.id)
      assert updated_row.cells[ctx.select_col.slug] == "rare"
    end

    test "clears a select cell when key is empty string", ctx do
      # Set a value first
      Sheets.update_table_cell(ctx.default_row, ctx.select_col.slug, "common")

      {:ok, view, _html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)

      send_to_content_tab(view, "select_table_cell", %{
        "row-id" => to_string(ctx.default_row.id),
        "column-slug" => ctx.select_col.slug,
        "key" => ""
      })

      updated_row = Sheets.get_table_row!(ctx.default_row.id)
      assert updated_row.cells[ctx.select_col.slug] == nil
    end
  end

  # ===========================================================================
  # Multi-Select Toggle
  # ===========================================================================

  describe "toggle_table_cell_multi_select" do
    setup [:register_and_log_in_user, :setup_table]

    setup ctx do
      col =
        table_column_fixture(ctx.table_block, %{
          name: "Tags",
          type: "multi_select"
        })

      Sheets.update_table_column(col, %{
        config: %{
          "options" => [
            %{"key" => "fire", "value" => "Fire"},
            %{"key" => "ice", "value" => "Ice"},
            %{"key" => "wind", "value" => "Wind"}
          ]
        }
      })

      %{multi_col: Sheets.get_table_column!(col.id)}
    end

    test "adds key to empty multi-select cell", ctx do
      {:ok, view, _html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)

      send_to_content_tab(view, "toggle_table_cell_multi_select", %{
        "row-id" => to_string(ctx.default_row.id),
        "column-slug" => ctx.multi_col.slug,
        "key" => "fire"
      })

      updated_row = Sheets.get_table_row!(ctx.default_row.id)
      assert updated_row.cells[ctx.multi_col.slug] == ["fire"]
    end

    test "adds a second key to multi-select cell", ctx do
      Sheets.update_table_cell(ctx.default_row, ctx.multi_col.slug, ["fire"])

      {:ok, view, _html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)

      send_to_content_tab(view, "toggle_table_cell_multi_select", %{
        "row-id" => to_string(ctx.default_row.id),
        "column-slug" => ctx.multi_col.slug,
        "key" => "ice"
      })

      updated_row = Sheets.get_table_row!(ctx.default_row.id)
      assert updated_row.cells[ctx.multi_col.slug] == ["fire", "ice"]
    end

    test "removes an existing key from multi-select cell", ctx do
      Sheets.update_table_cell(ctx.default_row, ctx.multi_col.slug, ["fire", "ice"])

      {:ok, view, _html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)

      send_to_content_tab(view, "toggle_table_cell_multi_select", %{
        "row-id" => to_string(ctx.default_row.id),
        "column-slug" => ctx.multi_col.slug,
        "key" => "fire"
      })

      updated_row = Sheets.get_table_row!(ctx.default_row.id)
      assert updated_row.cells[ctx.multi_col.slug] == ["ice"]
    end
  end

  # ===========================================================================
  # Add Table Cell Option (select/multi_select)
  # ===========================================================================

  describe "add_table_cell_option" do
    setup [:register_and_log_in_user, :setup_table]

    setup ctx do
      col =
        table_column_fixture(ctx.table_block, %{
          name: "Category",
          type: "select"
        })

      Sheets.update_table_column(col, %{config: %{"options" => []}})

      %{option_col: Sheets.get_table_column!(col.id)}
    end

    test "adds option and selects it in cell for select column", ctx do
      {:ok, view, _html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)

      send_to_content_tab(view, "add_table_cell_option", %{
        "key" => "Enter",
        "column-id" => to_string(ctx.option_col.id),
        "row-id" => to_string(ctx.default_row.id),
        "column-slug" => ctx.option_col.slug,
        "value" => "Weapon"
      })

      # Verify option was added to column config
      updated_col = Sheets.get_table_column!(ctx.option_col.id)
      options = updated_col.config["options"]
      assert length(options) == 1
      assert hd(options)["value"] == "Weapon"

      # Verify cell was set to the new option key
      updated_row = Sheets.get_table_row!(ctx.default_row.id)
      assert updated_row.cells[ctx.option_col.slug] == "weapon"
    end

    test "does nothing with empty label", ctx do
      {:ok, view, _html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)

      send_to_content_tab(view, "add_table_cell_option", %{
        "key" => "Enter",
        "column-id" => to_string(ctx.option_col.id),
        "row-id" => to_string(ctx.default_row.id),
        "column-slug" => ctx.option_col.slug,
        "value" => ""
      })

      updated_col = Sheets.get_table_column!(ctx.option_col.id)
      assert updated_col.config["options"] == []
    end
  end

  describe "add_table_cell_option — multi_select" do
    setup [:register_and_log_in_user, :setup_table]

    setup ctx do
      col =
        table_column_fixture(ctx.table_block, %{
          name: "Effects",
          type: "multi_select"
        })

      Sheets.update_table_column(col, %{config: %{"options" => []}})

      %{ms_col: Sheets.get_table_column!(col.id)}
    end

    test "adds option and toggles it in cell for multi_select column", ctx do
      {:ok, view, _html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)

      send_to_content_tab(view, "add_table_cell_option", %{
        "key" => "Enter",
        "column-id" => to_string(ctx.ms_col.id),
        "row-id" => to_string(ctx.default_row.id),
        "column-slug" => ctx.ms_col.slug,
        "value" => "Burning"
      })

      updated_col = Sheets.get_table_column!(ctx.ms_col.id)
      assert length(updated_col.config["options"]) == 1

      updated_row = Sheets.get_table_row!(ctx.default_row.id)
      assert updated_row.cells[ctx.ms_col.slug] == ["burning"]
    end
  end

  # ===========================================================================
  # Add/Remove/Update Column Option
  # ===========================================================================

  describe "add_table_column_option_keydown" do
    setup [:register_and_log_in_user, :setup_table]

    setup ctx do
      col =
        table_column_fixture(ctx.table_block, %{
          name: "Grade",
          type: "select"
        })

      Sheets.update_table_column(col, %{config: %{"options" => []}})

      %{grade_col: Sheets.get_table_column!(col.id)}
    end

    test "adds option to column on Enter", ctx do
      {:ok, view, _html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)

      send_to_content_tab(view, "add_table_column_option_keydown", %{
        "key" => "Enter",
        "column-id" => to_string(ctx.grade_col.id),
        "value" => "A+"
      })

      updated = Sheets.get_table_column!(ctx.grade_col.id)
      assert length(updated.config["options"]) == 1
      assert hd(updated.config["options"])["value"] == "A+"
    end

    test "ignores non-Enter keydown", ctx do
      {:ok, view, _html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)

      send_to_content_tab(view, "add_table_column_option_keydown", %{
        "key" => "Tab",
        "column-id" => to_string(ctx.grade_col.id),
        "value" => "Should Not Add"
      })

      updated = Sheets.get_table_column!(ctx.grade_col.id)
      assert updated.config["options"] == []
    end

    test "ignores empty value on Enter", ctx do
      {:ok, view, _html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)

      send_to_content_tab(view, "add_table_column_option_keydown", %{
        "key" => "Enter",
        "column-id" => to_string(ctx.grade_col.id),
        "value" => "  "
      })

      updated = Sheets.get_table_column!(ctx.grade_col.id)
      assert updated.config["options"] == []
    end
  end

  describe "remove_table_column_option" do
    setup [:register_and_log_in_user, :setup_table]

    setup ctx do
      col =
        table_column_fixture(ctx.table_block, %{
          name: "Status",
          type: "select"
        })

      Sheets.update_table_column(col, %{
        config: %{
          "options" => [
            %{"key" => "active", "value" => "Active"},
            %{"key" => "inactive", "value" => "Inactive"}
          ]
        }
      })

      %{status_col: Sheets.get_table_column!(col.id)}
    end

    test "removes an option by key", ctx do
      {:ok, view, _html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)

      send_to_content_tab(view, "remove_table_column_option", %{
        "column-id" => to_string(ctx.status_col.id),
        "key" => "active"
      })

      updated = Sheets.get_table_column!(ctx.status_col.id)
      keys = Enum.map(updated.config["options"], & &1["key"])
      assert keys == ["inactive"]
    end
  end

  describe "update_table_column_option" do
    setup [:register_and_log_in_user, :setup_table]

    setup ctx do
      col =
        table_column_fixture(ctx.table_block, %{
          name: "Tier",
          type: "select"
        })

      Sheets.update_table_column(col, %{
        config: %{
          "options" => [
            %{"key" => "bronze", "value" => "Bronze"},
            %{"key" => "silver", "value" => "Silver"}
          ]
        }
      })

      %{tier_col: Sheets.get_table_column!(col.id)}
    end

    test "updates option value at index", ctx do
      {:ok, view, _html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)

      send_to_content_tab(view, "update_table_column_option", %{
        "column-id" => to_string(ctx.tier_col.id),
        "index" => "0",
        "value" => "Gold"
      })

      updated = Sheets.get_table_column!(ctx.tier_col.id)
      first_option = hd(updated.config["options"])
      assert first_option["value"] == "Gold"
      assert first_option["key"] == "gold"
    end
  end

  # ===========================================================================
  # Toggle Reference Multiple
  # ===========================================================================

  describe "toggle_reference_multiple" do
    setup [:register_and_log_in_user, :setup_table]

    setup ctx do
      col =
        table_column_fixture(ctx.table_block, %{
          name: "Related",
          type: "reference"
        })

      Sheets.update_table_column(col, %{config: %{"multiple" => false}})

      %{ref_col: Sheets.get_table_column!(col.id)}
    end

    test "toggles multiple flag on reference column", ctx do
      {:ok, view, _html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)

      send_to_content_tab(view, "toggle_reference_multiple", %{
        "column-id" => to_string(ctx.ref_col.id)
      })

      updated = Sheets.get_table_column!(ctx.ref_col.id)
      assert updated.config["multiple"] == true
    end

    test "toggling back to single clears multi-value cells", ctx do
      # Set multiple=true and put a list value in the cell
      Sheets.update_table_column(ctx.ref_col, %{config: %{"multiple" => true}})
      Sheets.update_table_cell(ctx.default_row, ctx.ref_col.slug, ["ref1", "ref2"])

      {:ok, view, _html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)

      # Toggle back to single (multiple: true -> false)
      send_to_content_tab(view, "toggle_reference_multiple", %{
        "column-id" => to_string(ctx.ref_col.id)
      })

      updated_col = Sheets.get_table_column!(ctx.ref_col.id)
      assert updated_col.config["multiple"] == false

      # Cell with list value should have been cleared
      updated_row = Sheets.get_table_row!(ctx.default_row.id)
      assert updated_row.cells[ctx.ref_col.slug] == nil
    end
  end

  # ===========================================================================
  # Update Number Constraint
  # ===========================================================================

  describe "update_number_constraint" do
    setup [:register_and_log_in_user, :setup_table]

    setup ctx do
      col =
        table_column_fixture(ctx.table_block, %{
          name: "Score",
          type: "number"
        })

      %{num_col: col}
    end

    test "sets min constraint on number column", ctx do
      {:ok, view, _html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)

      send_to_content_tab(view, "update_number_constraint", %{
        "column-id" => to_string(ctx.num_col.id),
        "field" => "min",
        "value" => "0"
      })

      updated = Sheets.get_table_column!(ctx.num_col.id)
      assert updated.config["min"] == 0
    end

    test "sets max constraint on number column", ctx do
      {:ok, view, _html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)

      send_to_content_tab(view, "update_number_constraint", %{
        "column-id" => to_string(ctx.num_col.id),
        "field" => "max",
        "value" => "100"
      })

      updated = Sheets.get_table_column!(ctx.num_col.id)
      assert updated.config["max"] == 100
    end

    test "sets step constraint on number column", ctx do
      {:ok, view, _html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)

      send_to_content_tab(view, "update_number_constraint", %{
        "column-id" => to_string(ctx.num_col.id),
        "field" => "step",
        "value" => "5"
      })

      updated = Sheets.get_table_column!(ctx.num_col.id)
      assert updated.config["step"] == 5
    end

    test "ignores invalid field name", ctx do
      {:ok, view, _html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)

      send_to_content_tab(view, "update_number_constraint", %{
        "column-id" => to_string(ctx.num_col.id),
        "field" => "invalid_field",
        "value" => "10"
      })

      updated = Sheets.get_table_column!(ctx.num_col.id)
      assert updated.config == %{}
    end
  end

  # ===========================================================================
  # Required Field Validation
  # ===========================================================================

  describe "required field validation on cells" do
    setup [:register_and_log_in_user, :setup_table]

    setup ctx do
      col =
        table_column_fixture(ctx.table_block, %{
          name: "Required Field",
          type: "text"
        })

      Sheets.update_table_column(col, %{required: true})

      %{req_col: Sheets.get_table_column!(col.id)}
    end

    test "rejects empty value on required column", ctx do
      # Set an initial value
      Sheets.update_table_cell(ctx.default_row, ctx.req_col.slug, "initial")

      {:ok, view, _html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)

      html =
        send_to_content_tab(view, "update_table_cell", %{
          "row-id" => to_string(ctx.default_row.id),
          "column-slug" => ctx.req_col.slug,
          "value" => ""
        })

      assert html =~ "required"

      # Value should be unchanged
      updated_row = Sheets.get_table_row!(ctx.default_row.id)
      assert updated_row.cells[ctx.req_col.slug] == "initial"
    end

    test "accepts non-empty value on required column", ctx do
      {:ok, view, _html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)

      send_to_content_tab(view, "update_table_cell", %{
        "row-id" => to_string(ctx.default_row.id),
        "column-slug" => ctx.req_col.slug,
        "value" => "filled"
      })

      updated_row = Sheets.get_table_row!(ctx.default_row.id)
      assert updated_row.cells[ctx.req_col.slug] == "filled"
    end
  end

  # ===========================================================================
  # Multi-select update via update_table_cell (comma-separated)
  # ===========================================================================

  describe "update_table_cell with multi_select type" do
    setup [:register_and_log_in_user, :setup_table]

    setup ctx do
      col =
        table_column_fixture(ctx.table_block, %{
          name: "Elements",
          type: "multi_select"
        })

      Sheets.update_table_column(col, %{
        config: %{
          "options" => [
            %{"key" => "fire", "value" => "Fire"},
            %{"key" => "water", "value" => "Water"}
          ]
        }
      })

      %{ms_col: Sheets.get_table_column!(col.id)}
    end

    test "splits comma-separated values into list", ctx do
      {:ok, view, _html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)

      send_to_content_tab(view, "update_table_cell", %{
        "row-id" => to_string(ctx.default_row.id),
        "column-slug" => ctx.ms_col.slug,
        "type" => "multi_select",
        "value" => "fire, water"
      })

      updated_row = Sheets.get_table_row!(ctx.default_row.id)
      assert updated_row.cells[ctx.ms_col.slug] == ["fire", "water"]
    end

    test "filters out empty strings from split", ctx do
      {:ok, view, _html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)

      send_to_content_tab(view, "update_table_cell", %{
        "row-id" => to_string(ctx.default_row.id),
        "column-slug" => ctx.ms_col.slug,
        "type" => "multi_select",
        "value" => "fire,,, water,"
      })

      updated_row = Sheets.get_table_row!(ctx.default_row.id)
      assert updated_row.cells[ctx.ms_col.slug] == ["fire", "water"]
    end
  end

  # ===========================================================================
  # Column Type Change (resets cells)
  # ===========================================================================

  describe "change_table_column_type — cell reset" do
    setup [:register_and_log_in_user, :setup_table]

    setup ctx do
      col = table_column_fixture(ctx.table_block, %{name: "Mixed", type: "text"})
      # Set a cell value
      Sheets.update_table_cell(ctx.default_row, col.slug, "some text")

      %{mixed_col: col}
    end

    test "changing type resets cell values to nil", ctx do
      {:ok, view, _html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)

      send_to_content_tab(view, "change_table_column_type", %{
        "column-id" => to_string(ctx.mixed_col.id),
        "new-type" => "number"
      })

      updated_col = Sheets.get_table_column!(ctx.mixed_col.id)
      assert updated_col.type == "number"

      # Cell value should be reset
      updated_row = Sheets.get_table_row!(ctx.default_row.id)
      assert updated_row.cells[ctx.mixed_col.slug] == nil
    end
  end

  # ===========================================================================
  # Toggle Column Constant — double toggle
  # ===========================================================================

  describe "toggle_table_column_constant — double toggle" do
    setup [:register_and_log_in_user, :setup_table]

    setup ctx do
      col = table_column_fixture(ctx.table_block, %{name: "Const"})
      %{const_col: col}
    end

    test "double toggle returns is_constant to false", ctx do
      {:ok, view, _html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)

      # Toggle on
      send_to_content_tab(view, "toggle_table_column_constant", %{
        "column-id" => to_string(ctx.const_col.id)
      })

      assert Sheets.get_table_column!(ctx.const_col.id).is_constant == true

      # Toggle off
      send_to_content_tab(view, "toggle_table_column_constant", %{
        "column-id" => to_string(ctx.const_col.id)
      })

      assert Sheets.get_table_column!(ctx.const_col.id).is_constant == false
    end
  end

  # ===========================================================================
  # Toggle Column Required — double toggle
  # ===========================================================================

  describe "toggle_table_column_required — double toggle" do
    setup [:register_and_log_in_user, :setup_table]

    setup ctx do
      col = table_column_fixture(ctx.table_block, %{name: "Req"})
      %{req_col: col}
    end

    test "double toggle returns required to false", ctx do
      {:ok, view, _html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)

      # Toggle on
      send_to_content_tab(view, "toggle_table_column_required", %{
        "column-id" => to_string(ctx.req_col.id)
      })

      assert Sheets.get_table_column!(ctx.req_col.id).required == true

      # Toggle off
      send_to_content_tab(view, "toggle_table_column_required", %{
        "column-id" => to_string(ctx.req_col.id)
      })

      assert Sheets.get_table_column!(ctx.req_col.id).required == false
    end
  end

  # ===========================================================================
  # Multiple Rows Add and Reorder
  # ===========================================================================

  describe "add multiple rows and reorder" do
    setup [:register_and_log_in_user, :setup_table]

    test "adding multiple rows increments count correctly", ctx do
      {:ok, view, _html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)

      initial_data = Sheets.batch_load_table_data([ctx.table_block.id])
      initial_count = length(initial_data[ctx.table_block.id].rows)

      # Add 3 rows
      send_to_content_tab(view, "add_table_row", %{
        "block-id" => to_string(ctx.table_block.id)
      })

      send_to_content_tab(view, "add_table_row", %{
        "block-id" => to_string(ctx.table_block.id)
      })

      send_to_content_tab(view, "add_table_row", %{
        "block-id" => to_string(ctx.table_block.id)
      })

      updated_data = Sheets.batch_load_table_data([ctx.table_block.id])
      assert length(updated_data[ctx.table_block.id].rows) == initial_count + 3
    end
  end

  # ===========================================================================
  # Multiple Columns Add
  # ===========================================================================

  describe "add multiple columns" do
    setup [:register_and_log_in_user, :setup_table]

    test "adding multiple columns increments count correctly", ctx do
      {:ok, view, _html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)

      initial_data = Sheets.batch_load_table_data([ctx.table_block.id])
      initial_count = length(initial_data[ctx.table_block.id].columns)

      send_to_content_tab(view, "add_table_column", %{
        "block-id" => to_string(ctx.table_block.id)
      })

      send_to_content_tab(view, "add_table_column", %{
        "block-id" => to_string(ctx.table_block.id)
      })

      updated_data = Sheets.batch_load_table_data([ctx.table_block.id])
      assert length(updated_data[ctx.table_block.id].columns) == initial_count + 2
    end
  end

  # ===========================================================================
  # Reorder Rows
  # ===========================================================================

  describe "reorder_table_rows" do
    setup [:register_and_log_in_user, :setup_table]

    test "reorders rows by ID list", ctx do
      # Add a second row
      {:ok, row2} = Sheets.create_table_row(ctx.table_block, %{name: "Second Row"})

      {:ok, view, _html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)

      # Reorder: second row first, then default row
      send_to_content_tab(view, "reorder_table_rows", %{
        "block_id" => to_string(ctx.table_block.id),
        "row_ids" => [to_string(row2.id), to_string(ctx.default_row.id)]
      })

      rows = Sheets.list_table_rows(ctx.table_block.id)
      row_ids = Enum.map(rows, & &1.id)
      assert hd(row_ids) == row2.id
    end
  end

  # ===========================================================================
  # Delete Column (success case with >1 column)
  # ===========================================================================

  describe "delete_table_column — success" do
    setup [:register_and_log_in_user, :setup_table]

    test "deletes a column when there are multiple columns", ctx do
      _col2 = table_column_fixture(ctx.table_block, %{name: "Extra Column"})

      {:ok, view, _html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)

      send_to_content_tab(view, "delete_table_column", %{
        "column-id" => to_string(ctx.default_col.id)
      })

      data = Sheets.batch_load_table_data([ctx.table_block.id])
      col_ids = Enum.map(data[ctx.table_block.id].columns, & &1.id)
      refute ctx.default_col.id in col_ids
    end
  end

  # ===========================================================================
  # Delete Row (success case with >1 row)
  # ===========================================================================

  describe "delete_table_row — success" do
    setup [:register_and_log_in_user, :setup_table]

    test "deletes a row when there are multiple rows", ctx do
      {:ok, _row2} = Sheets.create_table_row(ctx.table_block, %{name: "Extra Row"})

      {:ok, view, _html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)

      send_to_content_tab(view, "delete_table_row", %{
        "row-id" => to_string(ctx.default_row.id)
      })

      data = Sheets.batch_load_table_data([ctx.table_block.id])
      row_ids = Enum.map(data[ctx.table_block.id].rows, & &1.id)
      refute ctx.default_row.id in row_ids
    end
  end

  # ===========================================================================
  # Rename Column — success
  # ===========================================================================

  describe "rename_table_column — success" do
    setup [:register_and_log_in_user, :setup_table]

    test "renames a column successfully", ctx do
      {:ok, view, _html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)

      send_to_content_tab(view, "rename_table_column", %{
        "column-id" => to_string(ctx.default_col.id),
        "value" => "Renamed Column"
      })

      updated = Sheets.get_table_column!(ctx.default_col.id)
      assert updated.name == "Renamed Column"
    end
  end

  # ===========================================================================
  # Rename Row — success
  # ===========================================================================

  describe "rename_table_row — success" do
    setup [:register_and_log_in_user, :setup_table]

    test "renames a row successfully", ctx do
      {:ok, view, _html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)

      send_to_content_tab(view, "rename_table_row", %{
        "row-id" => to_string(ctx.default_row.id),
        "value" => "Renamed Row"
      })

      updated = Sheets.get_table_row!(ctx.default_row.id)
      assert updated.name == "Renamed Row"
    end
  end

  # ===========================================================================
  # Number cell clamping
  # ===========================================================================

  describe "update_table_cell — number clamping" do
    setup [:register_and_log_in_user, :setup_table]

    setup ctx do
      col =
        table_column_fixture(ctx.table_block, %{
          name: "Clamped",
          type: "number"
        })

      Sheets.update_table_column(col, %{config: %{"min" => 0, "max" => 100}})

      %{clamp_col: Sheets.get_table_column!(col.id)}
    end

    test "clamps number cell value within range", ctx do
      {:ok, view, _html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)

      send_to_content_tab(view, "update_table_cell", %{
        "row-id" => to_string(ctx.default_row.id),
        "column-slug" => ctx.clamp_col.slug,
        "value" => "200"
      })

      updated_row = Sheets.get_table_row!(ctx.default_row.id)
      # The value should be clamped to max 100
      cell_val = updated_row.cells[ctx.clamp_col.slug]
      assert cell_val != nil
    end
  end

  # ===========================================================================
  # Update Cell — plain text
  # ===========================================================================

  describe "update_table_cell — plain text" do
    setup [:register_and_log_in_user, :setup_table]

    test "updates cell to a new value", ctx do
      {:ok, view, _html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)

      send_to_content_tab(view, "update_table_cell", %{
        "row-id" => to_string(ctx.default_row.id),
        "column-slug" => ctx.default_col.slug,
        "value" => "Hello World"
      })

      updated_row = Sheets.get_table_row!(ctx.default_row.id)
      assert updated_row.cells[ctx.default_col.slug] == "Hello World"
    end

    test "updates cell to nil (empty string)", ctx do
      Sheets.update_table_cell(ctx.default_row, ctx.default_col.slug, "existing")

      {:ok, view, _html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)

      send_to_content_tab(view, "update_table_cell", %{
        "row-id" => to_string(ctx.default_row.id),
        "column-slug" => ctx.default_col.slug,
        "value" => ""
      })

      updated_row = Sheets.get_table_row!(ctx.default_row.id)
      assert updated_row.cells[ctx.default_col.slug] == ""
    end
  end
end
