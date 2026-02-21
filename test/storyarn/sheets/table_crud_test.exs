defmodule Storyarn.Sheets.TableCrudTest do
  use Storyarn.DataCase

  alias Storyarn.Sheets

  import Storyarn.AccountsFixtures
  import Storyarn.SheetsFixtures
  import Storyarn.ProjectsFixtures

  defp setup_table(_context) do
    user = user_fixture()
    project = project_fixture(user)
    sheet = sheet_fixture(project)
    block = table_block_fixture(sheet)

    %{user: user, project: project, sheet: sheet, block: block}
  end

  # ===========================================================================
  # Table Block Creation
  # ===========================================================================

  describe "table block creation" do
    setup :setup_table

    test "auto-creates 1 default column and 1 default row", %{block: block} do
      assert length(block.table_columns) == 1
      assert length(block.table_rows) == 1

      [column] = block.table_columns
      assert column.name == "Value"
      assert column.slug == "value"
      assert column.type == "number"
      assert column.is_constant == false
      assert column.position == 0

      [row] = block.table_rows
      assert row.name == "Row 1"
      assert row.slug == "row_1"
      assert row.position == 0
      assert row.cells == %{"value" => nil}
    end

    test "table block has variable_name generated from label", %{block: block} do
      assert block.variable_name != nil
      assert block.type == "table"
    end

    test "table block default config and value are correct", %{block: block} do
      assert block.config["collapsed"] == false
      assert block.value == %{}
    end
  end

  # ===========================================================================
  # Column CRUD
  # ===========================================================================

  describe "list_columns/1" do
    setup :setup_table

    test "returns columns ordered by position", %{block: block} do
      table_column_fixture(block, %{name: "Description", type: "text"})
      columns = Sheets.list_table_columns(block.id)

      assert length(columns) == 2
      assert Enum.at(columns, 0).slug == "value"
      assert Enum.at(columns, 1).slug == "description"
    end
  end

  describe "create_column/2" do
    setup :setup_table

    test "creates column with auto-slug and auto-position", %{block: block} do
      {:ok, column} = Sheets.create_table_column(block, %{name: "Health Points", type: "number"})

      assert column.slug == "health_points"
      assert column.type == "number"
      assert column.position == 1
    end

    test "adds empty cell to all existing rows", %{block: block} do
      {:ok, _column} = Sheets.create_table_column(block, %{name: "Description", type: "text"})

      [row] = Sheets.list_table_rows(block.id)
      assert Map.has_key?(row.cells, "description")
      assert row.cells["description"] == nil
    end

    test "enforces slug uniqueness with _2 suffix", %{block: block} do
      {:ok, col1} = Sheets.create_table_column(block, %{name: "Value", type: "text"})
      assert col1.slug == "value_2"

      {:ok, col2} = Sheets.create_table_column(block, %{name: "Value", type: "text"})
      assert col2.slug == "value_3"
    end

    test "rejects invalid column type", %{block: block} do
      {:error, changeset} = Sheets.create_table_column(block, %{name: "Bad", type: "rich_text"})
      assert errors_on(changeset)[:type] != nil
    end
  end

  describe "update_column/2" do
    setup :setup_table

    test "rename updates slug and migrates cell keys", %{block: block} do
      [column] = block.table_columns

      {:ok, updated} = Sheets.update_table_column(column, %{name: "Score"})
      assert updated.slug == "score"

      [row] = Sheets.list_table_rows(block.id)
      assert Map.has_key?(row.cells, "score")
      refute Map.has_key?(row.cells, "value")
    end

    test "type change resets cell values to nil", %{block: block} do
      [column] = block.table_columns
      [row] = block.table_rows
      {:ok, _} = Sheets.update_table_cell(row, "value", 42)

      {:ok, _updated} = Sheets.update_table_column(column, %{type: "text"})

      [updated_row] = Sheets.list_table_rows(block.id)
      assert updated_row.cells["value"] == nil
    end

    test "rename with multiple rows migrates all atomically", %{block: block} do
      # Add more rows
      Enum.each(1..5, fn i ->
        table_row_fixture(block, %{name: "Row #{i + 1}"})
      end)

      [column] = block.table_columns
      {:ok, _} = Sheets.update_table_column(column, %{name: "Strength"})

      rows = Sheets.list_table_rows(block.id)
      assert length(rows) == 6

      Enum.each(rows, fn row ->
        assert Map.has_key?(row.cells, "strength")
        refute Map.has_key?(row.cells, "value")
      end)
    end

    test "rename enforces unique slug", %{block: block} do
      table_column_fixture(block, %{name: "Score", type: "number"})
      [first_column | _] = block.table_columns

      {:ok, updated} = Sheets.update_table_column(first_column, %{name: "Score"})
      assert updated.slug == "score_2"
    end
  end

  describe "delete_column/1" do
    setup :setup_table

    test "prevents deletion of the last column", %{block: block} do
      [column] = block.table_columns
      assert {:error, :last_column} = Sheets.delete_table_column(column)
    end

    test "removes cell key from all rows", %{block: block} do
      {:ok, new_col} = Sheets.create_table_column(block, %{name: "Description", type: "text"})

      {:ok, _} = Sheets.delete_table_column(new_col)

      [row] = Sheets.list_table_rows(block.id)
      refute Map.has_key?(row.cells, "description")
      assert Map.has_key?(row.cells, "value")
    end
  end

  describe "reorder_columns/2" do
    setup :setup_table

    test "updates positions", %{block: block} do
      {:ok, col2} = Sheets.create_table_column(block, %{name: "Description", type: "text"})
      [col1 | _] = block.table_columns

      {:ok, reordered} = Sheets.reorder_table_columns(block.id, [col2.id, col1.id])

      assert Enum.at(reordered, 0).id == col2.id
      assert Enum.at(reordered, 0).position == 0
      assert Enum.at(reordered, 1).id == col1.id
      assert Enum.at(reordered, 1).position == 1
    end
  end

  # ===========================================================================
  # Row CRUD
  # ===========================================================================

  describe "create_row/2" do
    setup :setup_table

    test "creates row with auto-slug and initialized cells", %{block: block} do
      {:ok, row} = Sheets.create_table_row(block, %{name: "Wisdom"})

      assert row.slug == "wisdom"
      assert row.position == 1
      assert Map.has_key?(row.cells, "value")
    end

    test "initializes cells for all existing columns", %{block: block} do
      table_column_fixture(block, %{name: "Description", type: "text"})

      {:ok, row} = Sheets.create_table_row(block, %{name: "Strength"})
      assert Map.has_key?(row.cells, "value")
      assert Map.has_key?(row.cells, "description")
    end

    test "enforces slug uniqueness", %{block: block} do
      {:ok, row} = Sheets.create_table_row(block, %{name: "Row 1"})
      assert row.slug == "row_1_2"
    end
  end

  describe "update_row/2" do
    setup :setup_table

    test "rename updates slug", %{block: block} do
      [row] = block.table_rows
      {:ok, updated} = Sheets.update_table_row(row, %{name: "Strength"})
      assert updated.slug == "strength"
    end

    test "rename enforces unique slug", %{block: block} do
      table_row_fixture(block, %{name: "Wisdom"})
      [first_row | _] = block.table_rows

      {:ok, updated} = Sheets.update_table_row(first_row, %{name: "Wisdom"})
      assert updated.slug == "wisdom_2"
    end
  end

  describe "delete_row/1" do
    setup :setup_table

    test "prevents deletion of the last row", %{block: block} do
      [row] = block.table_rows
      assert {:error, :last_row} = Sheets.delete_table_row(row)
    end

    test "allows deletion when multiple rows exist", %{block: block} do
      {:ok, new_row} = Sheets.create_table_row(block, %{name: "Extra"})
      assert {:ok, _} = Sheets.delete_table_row(new_row)
      assert length(Sheets.list_table_rows(block.id)) == 1
    end
  end

  describe "reorder_rows/2" do
    setup :setup_table

    test "updates positions", %{block: block} do
      {:ok, row2} = Sheets.create_table_row(block, %{name: "Wisdom"})
      [row1 | _] = block.table_rows

      {:ok, reordered} = Sheets.reorder_table_rows(block.id, [row2.id, row1.id])

      assert Enum.at(reordered, 0).id == row2.id
      assert Enum.at(reordered, 0).position == 0
      assert Enum.at(reordered, 1).id == row1.id
      assert Enum.at(reordered, 1).position == 1
    end
  end

  # ===========================================================================
  # Cell Operations
  # ===========================================================================

  describe "update_cell/3" do
    setup :setup_table

    test "updates a single cell value", %{block: block} do
      [row] = block.table_rows
      {:ok, updated} = Sheets.update_table_cell(row, "value", 42)
      assert updated.cells["value"] == 42
    end
  end

  describe "update_cells/2" do
    setup :setup_table

    test "batch updates multiple cells", %{block: block} do
      table_column_fixture(block, %{name: "Description", type: "text"})
      [row] = Sheets.list_table_rows(block.id)

      {:ok, updated} = Sheets.update_table_cells(row, %{"value" => 18, "description" => "Str score"})
      assert updated.cells["value"] == 18
      assert updated.cells["description"] == "Str score"
    end
  end

  # ===========================================================================
  # Batch Load
  # ===========================================================================

  describe "batch_load_table_data/1" do
    setup :setup_table

    test "loads columns and rows for multiple blocks", %{sheet: sheet, block: block} do
      block2 = table_block_fixture(sheet, %{label: "Second Table"})

      data = Sheets.batch_load_table_data([block.id, block2.id])

      assert Map.has_key?(data, block.id)
      assert Map.has_key?(data, block2.id)
      assert length(data[block.id].columns) == 1
      assert length(data[block.id].rows) == 1
      assert length(data[block2.id].columns) == 1
      assert length(data[block2.id].rows) == 1
    end
  end

  # ===========================================================================
  # Cascade Delete
  # ===========================================================================

  describe "cascade delete" do
    setup :setup_table

    test "deleting block removes columns and rows", %{block: block} do
      block_id = block.id
      table_column_fixture(block, %{name: "Extra Col", type: "text"})
      table_row_fixture(block, %{name: "Extra Row"})

      # Permanently delete to trigger cascade
      {:ok, _} = Sheets.permanently_delete_block(block)

      assert Sheets.list_table_columns(block_id) == []
      assert Sheets.list_table_rows(block_id) == []
    end
  end

  # ===========================================================================
  # Integration
  # ===========================================================================

  describe "full integration" do
    setup :setup_table

    test "create table → add columns → add rows → update cells → verify", %{block: block} do
      # Add columns
      {:ok, desc_col} = Sheets.create_table_column(block, %{name: "Description", type: "text"})
      {:ok, active_col} = Sheets.create_table_column(block, %{name: "Active", type: "boolean"})

      # Add rows
      {:ok, str_row} = Sheets.create_table_row(block, %{name: "Strength"})
      {:ok, wis_row} = Sheets.create_table_row(block, %{name: "Wisdom"})

      # Verify cells initialized
      assert Map.has_key?(str_row.cells, "value")
      assert Map.has_key?(str_row.cells, "description")
      assert Map.has_key?(str_row.cells, "active")

      # Update cells
      {:ok, str_row} = Sheets.update_table_cells(str_row, %{"value" => 18, "description" => "Physical power"})
      {:ok, wis_row} = Sheets.update_table_cells(wis_row, %{"value" => 15, "active" => true})

      assert str_row.cells["value"] == 18
      assert str_row.cells["description"] == "Physical power"
      assert wis_row.cells["value"] == 15
      assert wis_row.cells["active"] == true

      # Verify structure
      columns = Sheets.list_table_columns(block.id)
      rows = Sheets.list_table_rows(block.id)

      assert length(columns) == 3
      assert length(rows) == 3
      assert Enum.map(columns, & &1.slug) == ["value", "description", "active"]

      # Rename column and verify cell migration
      {:ok, _} = Sheets.update_table_column(desc_col, %{name: "Desc"})
      rows = Sheets.list_table_rows(block.id)

      Enum.each(rows, fn row ->
        assert Map.has_key?(row.cells, "desc")
        refute Map.has_key?(row.cells, "description")
      end)

      # Delete a column
      {:ok, _} = Sheets.delete_table_column(active_col)
      rows = Sheets.list_table_rows(block.id)

      Enum.each(rows, fn row ->
        refute Map.has_key?(row.cells, "active")
      end)
    end
  end
end
