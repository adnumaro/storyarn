defmodule Storyarn.Sheets.TableInheritanceTest do
  use Storyarn.DataCase

  alias Storyarn.Sheets
  alias Storyarn.Sheets.{PropertyInheritance, TableCrud}

  import Storyarn.AccountsFixtures
  import Storyarn.SheetsFixtures
  import Storyarn.ProjectsFixtures

  defp setup_hierarchy(_context) do
    user = user_fixture()
    project = project_fixture(user)
    parent = sheet_fixture(project, %{name: "Parent"})
    child = child_sheet_fixture(project, parent, %{name: "Child"})
    grandchild = child_sheet_fixture(project, child, %{name: "Grandchild"})

    %{
      user: user,
      project: project,
      parent: parent,
      child: child,
      grandchild: grandchild
    }
  end

  defp create_inheritable_table(sheet, opts \\ []) do
    label = opts[:label] || "Attributes"

    {:ok, block} =
      Sheets.create_block(sheet, %{
        type: "table",
        scope: "children",
        config: %{"label" => label, "collapsed" => false}
      })

    block
  end

  # ===========================================================================
  # Task 6.1 — Copy table structure on inheritance
  # ===========================================================================

  describe "table structure copied on inheritance" do
    setup :setup_hierarchy

    test "child inherits default table column and row from parent", %{
      parent: parent,
      child: child
    } do
      # Create inheritable table on parent (auto-creates default column + row)
      parent_block = create_inheritable_table(parent)

      # Find child's instance block (auto-propagated)
      child_blocks = Sheets.list_blocks(child.id)
      instance = Enum.find(child_blocks, &(&1.inherited_from_block_id == parent_block.id))
      assert instance

      # Check default column was copied
      child_columns = TableCrud.list_columns(instance.id)
      assert length(child_columns) == 1

      [col] = child_columns
      assert col.name == "Value"
      assert col.slug == "value"
      assert col.type == "number"

      # Check default row was copied
      child_rows = TableCrud.list_rows(instance.id)
      assert length(child_rows) == 1

      [row] = child_rows
      assert row.name == "Row 1"
      assert row.slug == "row_1"
    end

    test "new child created after columns added inherits full structure", %{
      project: project,
      parent: parent
    } do
      parent_block = create_inheritable_table(parent)

      # Add more columns and rows to parent BEFORE creating child
      {:ok, col2} = Sheets.create_table_column(parent_block, %{name: "Name", type: "text"})
      {:ok, col3} = Sheets.create_table_column(parent_block, %{name: "Active", type: "boolean"})
      {:ok, _row2} = Sheets.create_table_row(parent_block, %{name: "Row 2"})

      # Now create a new child — should inherit the full structure
      new_child = child_sheet_fixture(project, parent, %{name: "Late Child"})

      child_blocks = Sheets.list_blocks(new_child.id)
      instance = Enum.find(child_blocks, &(&1.inherited_from_block_id == parent_block.id))
      assert instance

      # Check all 3 columns were copied
      child_columns = TableCrud.list_columns(instance.id)
      assert length(child_columns) == 3

      column_names = Enum.map(child_columns, & &1.name)
      assert "Value" in column_names
      assert "Name" in column_names
      assert "Active" in column_names

      # Column types preserved
      name_col = Enum.find(child_columns, &(&1.name == "Name"))
      assert name_col.type == "text"
      assert name_col.slug == col2.slug

      active_col = Enum.find(child_columns, &(&1.name == "Active"))
      assert active_col.type == "boolean"
      assert active_col.slug == col3.slug

      # Check 2 rows were copied
      child_rows = TableCrud.list_rows(instance.id)
      assert length(child_rows) == 2

      row_names = Enum.map(child_rows, & &1.name)
      assert "Row 1" in row_names
      assert "Row 2" in row_names
    end

    test "row cells are copied from parent", %{project: project, parent: parent} do
      parent_block = create_inheritable_table(parent)

      # Set a cell value on parent's row
      [parent_row] = TableCrud.list_rows(parent_block.id)
      {:ok, _} = TableCrud.update_cell(parent_row, "value", 42)

      # Create a new child AFTER setting the value
      new_child = child_sheet_fixture(project, parent, %{name: "Fresh Child"})

      child_blocks = Sheets.list_blocks(new_child.id)
      instance = Enum.find(child_blocks, &(&1.inherited_from_block_id == parent_block.id))

      child_rows = TableCrud.list_rows(instance.id)
      [child_row] = child_rows

      # Cells are copied with parent's current values
      assert child_row.cells["value"] == 42
    end

    test "multiple children each get independent copies", %{
      parent: parent,
      child: child,
      grandchild: grandchild
    } do
      parent_block = create_inheritable_table(parent)

      # Both child and grandchild should have inherited table structure
      child_blocks = Sheets.list_blocks(child.id)
      child_instance = Enum.find(child_blocks, &(&1.inherited_from_block_id == parent_block.id))

      gc_blocks = Sheets.list_blocks(grandchild.id)
      gc_instance = Enum.find(gc_blocks, &(&1.inherited_from_block_id == parent_block.id))

      assert child_instance
      assert gc_instance

      child_columns = TableCrud.list_columns(child_instance.id)
      gc_columns = TableCrud.list_columns(gc_instance.id)

      assert length(child_columns) == 1
      assert length(gc_columns) == 1

      # Column IDs should be different (independent copies)
      refute hd(child_columns).id == hd(gc_columns).id
    end

    test "new child sheet inherits table structure from ancestors", %{
      project: project,
      parent: parent
    } do
      parent_block = create_inheritable_table(parent)
      {:ok, _} = Sheets.create_table_column(parent_block, %{name: "Extra", type: "text"})

      # Create a new child — should inherit table structure
      new_child = child_sheet_fixture(project, parent, %{name: "New Child"})

      child_blocks = Sheets.list_blocks(new_child.id)
      instance = Enum.find(child_blocks, &(&1.inherited_from_block_id == parent_block.id))
      assert instance

      child_columns = TableCrud.list_columns(instance.id)
      assert length(child_columns) == 2

      child_rows = TableCrud.list_rows(instance.id)
      assert length(child_rows) == 1
    end
  end

  # ===========================================================================
  # Task 6.2 — Sync schema changes to children
  # ===========================================================================

  describe "sync column changes to children" do
    setup :setup_hierarchy

    test "parent adds column → children gain column + cell keys", %{
      parent: parent,
      child: child
    } do
      parent_block = create_inheritable_table(parent)

      # Add a new column on the parent
      {:ok, new_col} =
        Sheets.create_table_column(parent_block, %{name: "Speed", type: "number"})

      # Child instance should have the new column
      child_blocks = Sheets.list_blocks(child.id)
      instance = Enum.find(child_blocks, &(&1.inherited_from_block_id == parent_block.id))

      child_columns = TableCrud.list_columns(instance.id)
      column_names = Enum.map(child_columns, & &1.name)
      assert "Speed" in column_names

      # Rows should have the new cell key
      child_rows = TableCrud.list_rows(instance.id)

      Enum.each(child_rows, fn row ->
        assert Map.has_key?(row.cells, new_col.slug)
      end)
    end

    test "parent deletes column → children lose column + cell data", %{
      parent: parent,
      child: child
    } do
      parent_block = create_inheritable_table(parent)

      {:ok, extra_col} =
        Sheets.create_table_column(parent_block, %{name: "Temp", type: "text"})

      # Verify child has the column first
      child_blocks = Sheets.list_blocks(child.id)
      instance = Enum.find(child_blocks, &(&1.inherited_from_block_id == parent_block.id))
      assert Enum.any?(TableCrud.list_columns(instance.id), &(&1.slug == extra_col.slug))

      # Delete the column on parent
      {:ok, _} = Sheets.delete_table_column(extra_col)

      # Child should no longer have the column
      child_columns = TableCrud.list_columns(instance.id)
      refute Enum.any?(child_columns, &(&1.slug == extra_col.slug))

      # Cell key should be removed from rows
      child_rows = TableCrud.list_rows(instance.id)

      Enum.each(child_rows, fn row ->
        refute Map.has_key?(row.cells, extra_col.slug)
      end)
    end

    test "parent renames column → children column renamed, cell keys migrated", %{
      parent: parent,
      child: child
    } do
      parent_block = create_inheritable_table(parent)

      # Get the default column
      [default_col] = TableCrud.list_columns(parent_block.id)

      # Rename parent column
      {:ok, _} = Sheets.update_table_column(default_col, %{name: "Score"})

      # Child column should be renamed
      child_blocks = Sheets.list_blocks(child.id)
      instance = Enum.find(child_blocks, &(&1.inherited_from_block_id == parent_block.id))

      child_columns = TableCrud.list_columns(instance.id)
      assert Enum.any?(child_columns, &(&1.name == "Score" && &1.slug == "score"))

      # Old slug should not exist
      refute Enum.any?(child_columns, &(&1.slug == "value"))

      # Cell keys should be migrated
      child_rows = TableCrud.list_rows(instance.id)

      Enum.each(child_rows, fn row ->
        assert Map.has_key?(row.cells, "score")
        refute Map.has_key?(row.cells, "value")
      end)
    end

    test "parent changes column type → children cells reset to nil", %{
      parent: parent,
      child: child
    } do
      parent_block = create_inheritable_table(parent)

      # Set a value on child's cell first
      child_blocks = Sheets.list_blocks(child.id)
      instance = Enum.find(child_blocks, &(&1.inherited_from_block_id == parent_block.id))
      [child_row] = TableCrud.list_rows(instance.id)
      {:ok, _} = TableCrud.update_cell(child_row, "value", 42)

      # Change parent column type from number to text
      [parent_col] = TableCrud.list_columns(parent_block.id)
      {:ok, _} = Sheets.update_table_column(parent_col, %{type: "text"})

      # Child column should now be text
      child_columns = TableCrud.list_columns(instance.id)
      child_col = Enum.find(child_columns, &(&1.slug == "value"))
      assert child_col.type == "text"

      # Cell values should be reset
      [updated_row] = TableCrud.list_rows(instance.id)
      assert updated_row.cells["value"] == nil
    end

    test "detached children are unaffected by column changes", %{
      parent: parent,
      child: child
    } do
      parent_block = create_inheritable_table(parent)

      # Detach child's instance
      child_blocks = Sheets.list_blocks(child.id)
      instance = Enum.find(child_blocks, &(&1.inherited_from_block_id == parent_block.id))
      {:ok, _} = PropertyInheritance.detach_block(instance)

      # Add column on parent
      {:ok, _} = Sheets.create_table_column(parent_block, %{name: "New Col", type: "text"})

      # Detached child should NOT have the new column
      child_columns = TableCrud.list_columns(instance.id)
      refute Enum.any?(child_columns, &(&1.name == "New Col"))
    end

    test "parent with scope self does not sync", %{parent: parent, child: child} do
      # Create a non-inheritable table
      {:ok, block} =
        Sheets.create_block(parent, %{
          type: "table",
          scope: "self",
          config: %{"label" => "Local Table", "collapsed" => false}
        })

      # Child shouldn't have any instance of this block
      child_blocks = Sheets.list_blocks(child.id)
      refute Enum.any?(child_blocks, &(&1.inherited_from_block_id == block.id))
    end
  end

  describe "sync row changes to children" do
    setup :setup_hierarchy

    test "parent adds row → children gain row with parent cells", %{
      parent: parent,
      child: child
    } do
      parent_block = create_inheritable_table(parent)

      # Add row on parent with cell values
      {:ok, new_row} =
        Sheets.create_table_row(parent_block, %{name: "Hero", cells: %{"value" => 100}})

      # Child should have the new row
      child_blocks = Sheets.list_blocks(child.id)
      instance = Enum.find(child_blocks, &(&1.inherited_from_block_id == parent_block.id))

      child_rows = TableCrud.list_rows(instance.id)
      hero_row = Enum.find(child_rows, &(&1.slug == new_row.slug))
      assert hero_row
      assert hero_row.name == "Hero"
      assert hero_row.cells["value"] == 100
    end

    test "parent deletes row → children lose row", %{parent: parent, child: child} do
      parent_block = create_inheritable_table(parent)
      {:ok, extra_row} = Sheets.create_table_row(parent_block, %{name: "Extra"})

      # Verify child has it
      child_blocks = Sheets.list_blocks(child.id)
      instance = Enum.find(child_blocks, &(&1.inherited_from_block_id == parent_block.id))
      assert Enum.any?(TableCrud.list_rows(instance.id), &(&1.slug == extra_row.slug))

      # Delete on parent
      {:ok, _} = Sheets.delete_table_row(extra_row)

      # Child should not have it
      child_rows = TableCrud.list_rows(instance.id)
      refute Enum.any?(child_rows, &(&1.slug == extra_row.slug))
    end

    test "parent renames row → children row renamed but cells untouched", %{
      parent: parent,
      child: child
    } do
      parent_block = create_inheritable_table(parent)

      # Set a custom cell value on child's row
      child_blocks = Sheets.list_blocks(child.id)
      instance = Enum.find(child_blocks, &(&1.inherited_from_block_id == parent_block.id))
      [child_row] = TableCrud.list_rows(instance.id)
      {:ok, _} = TableCrud.update_cell(child_row, "value", 99)

      # Rename parent row
      [parent_row] = TableCrud.list_rows(parent_block.id)
      {:ok, _} = Sheets.update_table_row(parent_row, %{name: "Primary"})

      # Child row should be renamed
      [updated_child_row] = TableCrud.list_rows(instance.id)
      assert updated_child_row.name == "Primary"
      assert updated_child_row.slug == "primary"

      # Cell value should be preserved (not overwritten)
      assert updated_child_row.cells["value"] == 99
    end

    test "detached children unaffected by row changes", %{parent: parent, child: child} do
      parent_block = create_inheritable_table(parent)

      # Detach
      child_blocks = Sheets.list_blocks(child.id)
      instance = Enum.find(child_blocks, &(&1.inherited_from_block_id == parent_block.id))
      {:ok, _} = PropertyInheritance.detach_block(instance)

      # Parent adds row
      {:ok, _} = Sheets.create_table_row(parent_block, %{name: "New Row"})

      # Detached child should not have it
      child_rows = TableCrud.list_rows(instance.id)
      refute Enum.any?(child_rows, &(&1.name == "New Row"))
    end
  end

  # ===========================================================================
  # Task 6.3 — Detach/reattach for tables
  # ===========================================================================

  describe "detach table block" do
    setup :setup_hierarchy

    test "detached child can add/delete columns freely", %{parent: parent, child: child} do
      parent_block = create_inheritable_table(parent)

      child_blocks = Sheets.list_blocks(child.id)
      instance = Enum.find(child_blocks, &(&1.inherited_from_block_id == parent_block.id))

      # Detach
      {:ok, _} = PropertyInheritance.detach_block(instance)

      # Can add columns
      {:ok, _} = Sheets.create_table_column(instance, %{name: "Custom", type: "text"})
      child_columns = TableCrud.list_columns(instance.id)
      assert Enum.any?(child_columns, &(&1.name == "Custom"))
    end

    test "parent changes dont affect detached child", %{parent: parent, child: child} do
      parent_block = create_inheritable_table(parent)

      child_blocks = Sheets.list_blocks(child.id)
      instance = Enum.find(child_blocks, &(&1.inherited_from_block_id == parent_block.id))
      {:ok, _} = PropertyInheritance.detach_block(instance)

      # Parent modifies table
      {:ok, _} = Sheets.create_table_column(parent_block, %{name: "ParentOnly", type: "text"})
      {:ok, _} = Sheets.create_table_row(parent_block, %{name: "ParentRow"})

      # Child unchanged
      child_columns = TableCrud.list_columns(instance.id)
      refute Enum.any?(child_columns, &(&1.name == "ParentOnly"))

      child_rows = TableCrud.list_rows(instance.id)
      refute Enum.any?(child_rows, &(&1.name == "ParentRow"))
    end
  end

  describe "reattach table block" do
    setup :setup_hierarchy

    test "reattach resets table structure to parent's current state", %{
      parent: parent,
      child: child
    } do
      parent_block = create_inheritable_table(parent)

      child_blocks = Sheets.list_blocks(child.id)
      instance = Enum.find(child_blocks, &(&1.inherited_from_block_id == parent_block.id))

      # Detach
      {:ok, detached} = PropertyInheritance.detach_block(instance)

      # Child adds custom column
      {:ok, _} = Sheets.create_table_column(detached, %{name: "Custom", type: "text"})

      # Parent adds column while child is detached
      {:ok, _} = Sheets.create_table_column(parent_block, %{name: "Speed", type: "number"})

      # Reattach
      {:ok, _reattached} = PropertyInheritance.reattach_block(detached)

      # Child should have parent's current columns (Value + Speed), NOT custom
      child_columns = TableCrud.list_columns(instance.id)
      column_names = Enum.map(child_columns, & &1.name)
      assert "Value" in column_names
      assert "Speed" in column_names
      refute "Custom" in column_names
      assert length(child_columns) == 2
    end

    test "reattach resets cell values to parent defaults", %{parent: parent, child: child} do
      parent_block = create_inheritable_table(parent)

      child_blocks = Sheets.list_blocks(child.id)
      instance = Enum.find(child_blocks, &(&1.inherited_from_block_id == parent_block.id))

      # Detach and modify cell values
      {:ok, detached} = PropertyInheritance.detach_block(instance)
      [child_row] = TableCrud.list_rows(detached.id)
      {:ok, _} = TableCrud.update_cell(child_row, "value", 999)

      # Reattach
      {:ok, _} = PropertyInheritance.reattach_block(detached)

      # Rows should be reset from parent
      child_rows = TableCrud.list_rows(instance.id)
      [row] = child_rows
      assert row.cells["value"] == nil
    end

    test "reattach when parent was modified since detach", %{parent: parent, child: child} do
      parent_block = create_inheritable_table(parent)

      child_blocks = Sheets.list_blocks(child.id)
      instance = Enum.find(child_blocks, &(&1.inherited_from_block_id == parent_block.id))

      {:ok, detached} = PropertyInheritance.detach_block(instance)

      # Parent makes lots of changes
      {:ok, _} = Sheets.create_table_column(parent_block, %{name: "Col A", type: "text"})
      {:ok, _} = Sheets.create_table_column(parent_block, %{name: "Col B", type: "boolean"})
      {:ok, _} = Sheets.create_table_row(parent_block, %{name: "Row X"})

      # Reattach
      {:ok, _} = PropertyInheritance.reattach_block(detached)

      # Child should have parent's latest state
      child_columns = TableCrud.list_columns(instance.id)
      assert length(child_columns) == 3

      child_rows = TableCrud.list_rows(instance.id)
      assert length(child_rows) == 2
    end
  end
end
