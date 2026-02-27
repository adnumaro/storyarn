defmodule Storyarn.Sheets.BlockCrudTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Sheets
  alias Storyarn.Sheets.Block

  import Storyarn.AccountsFixtures
  import Storyarn.SheetsFixtures
  import Storyarn.ProjectsFixtures

  defp setup_context(_context) do
    user = user_fixture()
    project = project_fixture(user)
    sheet = sheet_fixture(project)

    %{user: user, project: project, sheet: sheet}
  end

  # ===========================================================================
  # list_blocks/1
  # ===========================================================================

  describe "list_blocks/1" do
    setup :setup_context

    test "returns empty list for a sheet with no blocks", %{project: project} do
      empty_sheet = sheet_fixture(project, %{name: "Empty Sheet"})
      assert Sheets.list_blocks(empty_sheet.id) == []
    end

    test "returns blocks ordered by position", %{sheet: sheet} do
      b1 = block_fixture(sheet, %{config: %{"label" => "First"}, position: 0})
      b2 = block_fixture(sheet, %{config: %{"label" => "Second"}, position: 1})
      b3 = block_fixture(sheet, %{config: %{"label" => "Third"}, position: 2})

      blocks = Sheets.list_blocks(sheet.id)
      assert length(blocks) == 3
      assert Enum.map(blocks, & &1.id) == [b1.id, b2.id, b3.id]
    end

    test "excludes soft-deleted blocks", %{sheet: sheet} do
      block = block_fixture(sheet)
      {:ok, _} = Sheets.delete_block(block)

      assert Sheets.list_blocks(sheet.id) == []
    end

    test "only returns blocks belonging to the specified sheet", %{project: project, sheet: sheet} do
      _block = block_fixture(sheet)
      other_sheet = sheet_fixture(project, %{name: "Other"})
      _other_block = block_fixture(other_sheet)

      blocks = Sheets.list_blocks(sheet.id)
      assert length(blocks) == 1
    end
  end

  # ===========================================================================
  # get_block/1 and get_block!/1
  # ===========================================================================

  describe "get_block/1" do
    setup :setup_context

    test "returns block by ID", %{sheet: sheet} do
      block = block_fixture(sheet)
      fetched = Sheets.get_block(block.id)
      assert fetched.id == block.id
    end

    test "returns nil for non-existent ID", _context do
      assert Sheets.get_block(0) == nil
    end

    test "returns nil for soft-deleted block", %{sheet: sheet} do
      block = block_fixture(sheet)
      {:ok, _} = Sheets.delete_block(block)

      assert Sheets.get_block(block.id) == nil
    end
  end

  describe "get_block!/1" do
    setup :setup_context

    test "returns block by ID", %{sheet: sheet} do
      block = block_fixture(sheet)
      fetched = Sheets.get_block!(block.id)
      assert fetched.id == block.id
    end

    test "raises for non-existent ID", _context do
      assert_raise Ecto.NoResultsError, fn ->
        Sheets.get_block!(0)
      end
    end

    test "raises for soft-deleted block", %{sheet: sheet} do
      block = block_fixture(sheet)
      {:ok, _} = Sheets.delete_block(block)

      assert_raise Ecto.NoResultsError, fn ->
        Sheets.get_block!(block.id)
      end
    end
  end

  # ===========================================================================
  # get_block_in_project/2 and get_block_in_project!/2
  # ===========================================================================

  describe "get_block_in_project/2" do
    setup :setup_context

    test "returns block when it belongs to the project", %{sheet: sheet, project: project} do
      block = block_fixture(sheet)
      fetched = Sheets.get_block_in_project(block.id, project.id)
      assert fetched.id == block.id
    end

    test "returns nil when block belongs to a different project", %{sheet: sheet} do
      block = block_fixture(sheet)
      other_user = user_fixture()
      other_project = project_fixture(other_user)

      assert Sheets.get_block_in_project(block.id, other_project.id) == nil
    end

    test "returns nil for soft-deleted block", %{sheet: sheet, project: project} do
      block = block_fixture(sheet)
      {:ok, _} = Sheets.delete_block(block)

      assert Sheets.get_block_in_project(block.id, project.id) == nil
    end

    test "returns nil for block in soft-deleted sheet", %{sheet: sheet, project: project} do
      block = block_fixture(sheet)
      {:ok, _} = Sheets.delete_sheet(sheet)

      assert Sheets.get_block_in_project(block.id, project.id) == nil
    end
  end

  describe "get_block_in_project!/2" do
    setup :setup_context

    test "returns block when it belongs to the project", %{sheet: sheet, project: project} do
      block = block_fixture(sheet)
      fetched = Sheets.get_block_in_project!(block.id, project.id)
      assert fetched.id == block.id
    end

    test "raises when block belongs to a different project", %{sheet: sheet} do
      block = block_fixture(sheet)
      other_user = user_fixture()
      other_project = project_fixture(other_user)

      assert_raise Ecto.NoResultsError, fn ->
        Sheets.get_block_in_project!(block.id, other_project.id)
      end
    end
  end

  # ===========================================================================
  # create_block/2
  # ===========================================================================

  describe "create_block/2 - text block" do
    setup :setup_context

    test "creates a text block with defaults", %{sheet: sheet} do
      {:ok, block} = Sheets.create_block(sheet, %{type: "text", config: %{"label" => "Name"}})

      assert block.type == "text"
      assert block.config["label"] == "Name"
      assert block.value == %{"content" => ""}
      assert block.variable_name == "name"
      assert block.is_constant == false
      assert block.scope == "self"
      assert is_nil(block.deleted_at)
    end

    test "auto-assigns position", %{sheet: sheet} do
      {:ok, b1} = Sheets.create_block(sheet, %{type: "text", config: %{"label" => "A"}})
      {:ok, b2} = Sheets.create_block(sheet, %{type: "text", config: %{"label" => "B"}})
      {:ok, b3} = Sheets.create_block(sheet, %{type: "text", config: %{"label" => "C"}})

      assert b1.position == 0
      assert b2.position == 1
      assert b3.position == 2
    end

    test "respects explicit position", %{sheet: sheet} do
      {:ok, block} =
        Sheets.create_block(sheet, %{type: "text", config: %{"label" => "X"}, position: 10})

      assert block.position == 10
    end
  end

  describe "create_block/2 - number block" do
    setup :setup_context

    test "creates a number block with defaults", %{sheet: sheet} do
      {:ok, block} =
        Sheets.create_block(sheet, %{
          type: "number",
          config: %{"label" => "Health", "placeholder" => "0"}
        })

      assert block.type == "number"
      assert block.config["label"] == "Health"
      assert block.value == %{"content" => nil}
      assert block.variable_name == "health"
    end
  end

  describe "create_block/2 - select block" do
    setup :setup_context

    test "creates a select block with options", %{sheet: sheet} do
      options = [
        %{"key" => "warrior", "value" => "Warrior"},
        %{"key" => "mage", "value" => "Mage"}
      ]

      {:ok, block} =
        Sheets.create_block(sheet, %{
          type: "select",
          config: %{"label" => "Class", "options" => options}
        })

      assert block.type == "select"
      assert block.config["options"] == options
      assert block.value == %{"content" => nil}
      assert block.variable_name == "class"
    end
  end

  describe "create_block/2 - multi_select block" do
    setup :setup_context

    test "creates a multi_select block", %{sheet: sheet} do
      {:ok, block} =
        Sheets.create_block(sheet, %{
          type: "multi_select",
          config: %{"label" => "Tags", "options" => []}
        })

      assert block.type == "multi_select"
      assert block.value == %{"content" => []}
    end
  end

  describe "create_block/2 - boolean block" do
    setup :setup_context

    test "creates a boolean block", %{sheet: sheet} do
      {:ok, block} =
        Sheets.create_block(sheet, %{
          type: "boolean",
          config: %{"label" => "Is Active", "mode" => "two_state"}
        })

      assert block.type == "boolean"
      assert block.value == %{"content" => nil}
      assert block.variable_name == "is_active"
    end
  end

  describe "create_block/2 - date block" do
    setup :setup_context

    test "creates a date block", %{sheet: sheet} do
      {:ok, block} =
        Sheets.create_block(sheet, %{type: "date", config: %{"label" => "Birthday"}})

      assert block.type == "date"
      assert block.value == %{"content" => nil}
      assert block.variable_name == "birthday"
    end
  end

  describe "create_block/2 - rich_text block" do
    setup :setup_context

    test "creates a rich_text block", %{sheet: sheet} do
      {:ok, block} =
        Sheets.create_block(sheet, %{type: "rich_text", config: %{"label" => "Bio"}})

      assert block.type == "rich_text"
      assert block.value == %{"content" => ""}
      assert block.variable_name == "bio"
    end
  end

  describe "create_block/2 - divider block" do
    setup :setup_context

    test "creates a divider block with no variable name", %{sheet: sheet} do
      {:ok, block} = Sheets.create_block(sheet, %{type: "divider"})

      assert block.type == "divider"
      assert block.variable_name == nil
    end
  end

  describe "create_block/2 - reference block" do
    setup :setup_context

    test "creates a reference block with no variable name", %{sheet: sheet} do
      {:ok, block} =
        Sheets.create_block(sheet, %{
          type: "reference",
          config: %{"label" => "Related Sheet", "allowed_types" => ["sheet"]}
        })

      assert block.type == "reference"
      assert block.variable_name == nil
    end
  end

  describe "create_block/2 - table block" do
    setup :setup_context

    test "creates a table block with default column and row", %{sheet: sheet} do
      {:ok, block} =
        Sheets.create_block(sheet, %{type: "table", config: %{"label" => "Stats"}})

      block = Repo.preload(block, [:table_columns, :table_rows])
      assert length(block.table_columns) == 1
      assert length(block.table_rows) == 1
      assert block.variable_name == "stats"
    end
  end

  describe "create_block/2 - validation" do
    setup :setup_context

    test "rejects invalid block type", %{sheet: sheet} do
      {:error, changeset} =
        Sheets.create_block(sheet, %{type: "invalid", config: %{"label" => "X"}})

      assert errors_on(changeset)[:type] != nil
    end

    test "rejects missing type", %{sheet: sheet} do
      {:error, changeset} = Sheets.create_block(sheet, %{config: %{"label" => "X"}})
      assert errors_on(changeset)[:type] != nil
    end

    test "rejects empty label for non-divider blocks", %{sheet: sheet} do
      {:error, changeset} =
        Sheets.create_block(sheet, %{type: "text", config: %{"label" => ""}})

      assert errors_on(changeset)[:config] != nil
    end

    test "rejects missing label for non-divider blocks", %{sheet: sheet} do
      {:error, changeset} = Sheets.create_block(sheet, %{type: "text", config: %{}})
      assert errors_on(changeset)[:config] != nil
    end
  end

  describe "create_block/2 - variable name uniqueness" do
    setup :setup_context

    test "auto-deduplicates variable names within a sheet", %{sheet: sheet} do
      {:ok, b1} = Sheets.create_block(sheet, %{type: "text", config: %{"label" => "Name"}})
      {:ok, b2} = Sheets.create_block(sheet, %{type: "text", config: %{"label" => "Name"}})

      assert b1.variable_name == "name"
      assert b2.variable_name == "name_2"
    end

    test "handles triple collision", %{sheet: sheet} do
      {:ok, _b1} = Sheets.create_block(sheet, %{type: "text", config: %{"label" => "Health"}})
      {:ok, _b2} = Sheets.create_block(sheet, %{type: "text", config: %{"label" => "Health"}})
      {:ok, b3} = Sheets.create_block(sheet, %{type: "text", config: %{"label" => "Health"}})

      assert b3.variable_name == "health_3"
    end
  end

  describe "create_block/2 - is_constant" do
    setup :setup_context

    test "creates a constant block", %{sheet: sheet} do
      {:ok, block} =
        Sheets.create_block(sheet, %{
          type: "text",
          config: %{"label" => "Constant"},
          is_constant: true
        })

      assert block.is_constant == true
    end
  end

  # ===========================================================================
  # update_block/2
  # ===========================================================================

  describe "update_block/2" do
    setup :setup_context

    test "updates block type", %{sheet: sheet} do
      block = block_fixture(sheet)
      {:ok, updated} = Sheets.update_block(block, %{type: "number"})
      assert updated.type == "number"
    end

    test "updates block config", %{sheet: sheet} do
      block = block_fixture(sheet)
      {:ok, updated} = Sheets.update_block(block, %{config: %{"label" => "New Label"}})
      assert updated.config["label"] == "New Label"
    end

    test "updates is_constant flag", %{sheet: sheet} do
      block = block_fixture(sheet)
      {:ok, updated} = Sheets.update_block(block, %{is_constant: true})
      assert updated.is_constant == true
    end

    test "rejects invalid block type on update", %{sheet: sheet} do
      block = block_fixture(sheet)
      {:error, changeset} = Sheets.update_block(block, %{type: "invalid_type"})
      assert errors_on(changeset)[:type] != nil
    end

    test "updates scope", %{sheet: sheet} do
      block = block_fixture(sheet)
      {:ok, updated} = Sheets.update_block(block, %{scope: "children"})
      assert updated.scope == "children"
    end

    test "rejects invalid scope", %{sheet: sheet} do
      block = block_fixture(sheet)
      {:error, changeset} = Sheets.update_block(block, %{scope: "invalid"})
      assert errors_on(changeset)[:scope] != nil
    end
  end

  # ===========================================================================
  # update_block_value/2
  # ===========================================================================

  describe "update_block_value/2" do
    setup :setup_context

    test "updates text block value", %{sheet: sheet} do
      block = block_fixture(sheet)
      {:ok, updated} = Sheets.update_block_value(block, %{"content" => "Hello"})
      assert updated.value["content"] == "Hello"
    end

    test "updates number block value", %{sheet: sheet} do
      {:ok, block} =
        Sheets.create_block(sheet, %{
          type: "number",
          config: %{"label" => "Health"}
        })

      {:ok, updated} = Sheets.update_block_value(block, %{"content" => 42})
      assert updated.value["content"] == 42
    end

    test "updates boolean block value", %{sheet: sheet} do
      {:ok, block} =
        Sheets.create_block(sheet, %{
          type: "boolean",
          config: %{"label" => "Active"}
        })

      {:ok, updated} = Sheets.update_block_value(block, %{"content" => true})
      assert updated.value["content"] == true
    end

    test "updates select block value", %{sheet: sheet} do
      {:ok, block} =
        Sheets.create_block(sheet, %{
          type: "select",
          config: %{
            "label" => "Class",
            "options" => [%{"key" => "warrior", "value" => "Warrior"}]
          }
        })

      {:ok, updated} = Sheets.update_block_value(block, %{"content" => "warrior"})
      assert updated.value["content"] == "warrior"
    end

    test "updates multi_select block value", %{sheet: sheet} do
      {:ok, block} =
        Sheets.create_block(sheet, %{
          type: "multi_select",
          config: %{"label" => "Tags", "options" => []}
        })

      {:ok, updated} = Sheets.update_block_value(block, %{"content" => ["a", "b"]})
      assert updated.value["content"] == ["a", "b"]
    end
  end

  # ===========================================================================
  # update_block_config/2
  # ===========================================================================

  describe "update_block_config/2" do
    setup :setup_context

    test "updates config label", %{sheet: sheet} do
      block = block_fixture(sheet)
      {:ok, updated} = Sheets.update_block_config(block, %{"label" => "Renamed"})
      assert updated.config["label"] == "Renamed"
    end

    test "updates config options for select", %{sheet: sheet} do
      {:ok, block} =
        Sheets.create_block(sheet, %{
          type: "select",
          config: %{"label" => "Class", "options" => []}
        })

      new_options = [%{"key" => "warrior", "value" => "Warrior"}]

      {:ok, updated} =
        Sheets.update_block_config(block, %{"label" => "Class", "options" => new_options})

      assert updated.config["options"] == new_options
    end

    test "rejects empty label", %{sheet: sheet} do
      block = block_fixture(sheet)
      {:error, changeset} = Sheets.update_block_config(block, %{"label" => ""})
      assert errors_on(changeset)[:config] != nil
    end
  end

  # ===========================================================================
  # delete_block/1 (soft delete)
  # ===========================================================================

  describe "delete_block/1" do
    setup :setup_context

    test "soft-deletes a block", %{sheet: sheet} do
      block = block_fixture(sheet)
      {:ok, deleted} = Sheets.delete_block(block)

      assert deleted.deleted_at != nil
      assert Sheets.get_block(block.id) == nil
    end

    test "soft-deleted block is excluded from list_blocks", %{sheet: sheet} do
      block = block_fixture(sheet)
      {:ok, _} = Sheets.delete_block(block)

      assert Sheets.list_blocks(sheet.id) == []
    end

    test "can still be found with Repo.get", %{sheet: sheet} do
      block = block_fixture(sheet)
      {:ok, _} = Sheets.delete_block(block)

      found = Repo.get(Block, block.id)
      assert found != nil
      assert found.deleted_at != nil
    end
  end

  # ===========================================================================
  # permanently_delete_block/1
  # ===========================================================================

  describe "permanently_delete_block/1" do
    setup :setup_context

    test "permanently removes block from database", %{sheet: sheet} do
      block = block_fixture(sheet)
      {:ok, _} = Sheets.permanently_delete_block(block)

      assert Repo.get(Block, block.id) == nil
    end
  end

  # ===========================================================================
  # restore_block/1
  # ===========================================================================

  describe "restore_block/1" do
    setup :setup_context

    test "restores a soft-deleted block", %{sheet: sheet} do
      block = block_fixture(sheet)
      {:ok, deleted} = Sheets.delete_block(block)
      {:ok, restored} = Sheets.restore_block(deleted)

      assert restored.deleted_at == nil
      assert Sheets.get_block(block.id) != nil
    end

    test "restored block appears in list_blocks", %{sheet: sheet} do
      block = block_fixture(sheet)
      {:ok, deleted} = Sheets.delete_block(block)
      {:ok, _} = Sheets.restore_block(deleted)

      blocks = Sheets.list_blocks(sheet.id)
      assert length(blocks) == 1
      assert hd(blocks).id == block.id
    end
  end

  # ===========================================================================
  # reorder_blocks/2
  # ===========================================================================

  describe "reorder_blocks/2" do
    setup :setup_context

    test "reorders blocks to new positions", %{sheet: sheet} do
      b1 = block_fixture(sheet, %{config: %{"label" => "A"}})
      b2 = block_fixture(sheet, %{config: %{"label" => "B"}})
      b3 = block_fixture(sheet, %{config: %{"label" => "C"}})

      {:ok, reordered} = Sheets.reorder_blocks(sheet.id, [b3.id, b1.id, b2.id])

      assert length(reordered) == 3
      assert Enum.at(reordered, 0).id == b3.id
      assert Enum.at(reordered, 0).position == 0
      assert Enum.at(reordered, 1).id == b1.id
      assert Enum.at(reordered, 1).position == 1
      assert Enum.at(reordered, 2).id == b2.id
      assert Enum.at(reordered, 2).position == 2
    end

    test "filters out nil IDs", %{sheet: sheet} do
      b1 = block_fixture(sheet, %{config: %{"label" => "A"}})
      b2 = block_fixture(sheet, %{config: %{"label" => "B"}})

      {:ok, reordered} = Sheets.reorder_blocks(sheet.id, [nil, b2.id, nil, b1.id])

      assert length(reordered) == 2
      assert Enum.at(reordered, 0).id == b2.id
      assert Enum.at(reordered, 0).position == 0
    end

    test "ignores blocks from other sheets", %{project: project, sheet: sheet} do
      b1 = block_fixture(sheet, %{config: %{"label" => "A"}})
      other_sheet = sheet_fixture(project, %{name: "Other"})
      b_other = block_fixture(other_sheet, %{config: %{"label" => "X"}})

      {:ok, reordered} = Sheets.reorder_blocks(sheet.id, [b_other.id, b1.id])

      # Only our block should be in the list
      assert length(reordered) == 1
      assert hd(reordered).id == b1.id
    end
  end

  # ===========================================================================
  # reorder_blocks_with_columns/2
  # ===========================================================================

  describe "reorder_blocks_with_columns/2" do
    setup :setup_context

    test "reorders blocks with column layout info", %{sheet: sheet} do
      b1 = block_fixture(sheet, %{config: %{"label" => "A"}})
      b2 = block_fixture(sheet, %{config: %{"label" => "B"}})
      group_id = Ecto.UUID.generate()

      items = [
        %{id: b2.id, column_group_id: group_id, column_index: 0},
        %{id: b1.id, column_group_id: group_id, column_index: 1}
      ]

      {:ok, blocks} = Sheets.reorder_blocks_with_columns(sheet.id, items)

      assert length(blocks) == 2
      first = Enum.find(blocks, &(&1.id == b2.id))
      second = Enum.find(blocks, &(&1.id == b1.id))

      assert first.position == 0
      assert first.column_group_id == group_id
      assert first.column_index == 0

      assert second.position == 1
      assert second.column_group_id == group_id
      assert second.column_index == 1
    end

    test "clamps column_index to 0..2", %{sheet: sheet} do
      b1 = block_fixture(sheet, %{config: %{"label" => "A"}})
      group_id = Ecto.UUID.generate()

      items = [%{id: b1.id, column_group_id: group_id, column_index: 5}]
      {:ok, blocks} = Sheets.reorder_blocks_with_columns(sheet.id, items)

      assert hd(blocks).column_index == 2
    end

    test "clamps negative column_index to 0", %{sheet: sheet} do
      b1 = block_fixture(sheet, %{config: %{"label" => "A"}})
      group_id = Ecto.UUID.generate()

      items = [%{id: b1.id, column_group_id: group_id, column_index: -1}]
      {:ok, blocks} = Sheets.reorder_blocks_with_columns(sheet.id, items)

      assert hd(blocks).column_index == 0
    end
  end

  # ===========================================================================
  # create_column_group/2 and dissolve_column_group/2
  # ===========================================================================

  describe "create_column_group/2" do
    setup :setup_context

    test "creates a column group from 2+ blocks", %{sheet: sheet} do
      b1 = block_fixture(sheet, %{config: %{"label" => "A"}})
      b2 = block_fixture(sheet, %{config: %{"label" => "B"}})

      {:ok, group_id} = Sheets.create_column_group(sheet.id, [b1.id, b2.id])
      assert is_binary(group_id)

      blocks = Sheets.list_blocks(sheet.id)
      first = Enum.find(blocks, &(&1.id == b1.id))
      second = Enum.find(blocks, &(&1.id == b2.id))

      assert first.column_group_id == group_id
      assert first.column_index == 0
      assert second.column_group_id == group_id
      assert second.column_index == 1
    end

    test "fails with fewer than 2 valid blocks", %{sheet: sheet} do
      b1 = block_fixture(sheet, %{config: %{"label" => "A"}})

      {:error, :not_enough_blocks} = Sheets.create_column_group(sheet.id, [b1.id])
    end

    test "fails with empty list", %{sheet: sheet} do
      {:error, :not_enough_blocks} = Sheets.create_column_group(sheet.id, [])
    end
  end

  # ===========================================================================
  # next_block_position/1
  # ===========================================================================

  describe "next_block_position/1" do
    setup :setup_context

    test "returns 0 for empty sheet", %{project: project} do
      empty_sheet = sheet_fixture(project, %{name: "Empty"})

      assert Storyarn.Sheets.BlockCrud.next_block_position(empty_sheet.id) == 0
    end

    test "returns max + 1", %{sheet: sheet} do
      _b1 = block_fixture(sheet, %{config: %{"label" => "A"}, position: 0})
      _b2 = block_fixture(sheet, %{config: %{"label" => "B"}, position: 5})

      assert Storyarn.Sheets.BlockCrud.next_block_position(sheet.id) == 6
    end
  end

  # ===========================================================================
  # list_variable_names/2
  # ===========================================================================

  describe "list_variable_names/2" do
    setup :setup_context

    test "returns all variable names for a sheet", %{sheet: sheet} do
      {:ok, _} = Sheets.create_block(sheet, %{type: "text", config: %{"label" => "Health"}})
      {:ok, _} = Sheets.create_block(sheet, %{type: "number", config: %{"label" => "Strength"}})

      names = Storyarn.Sheets.BlockCrud.list_variable_names(sheet.id)
      assert "health" in names
      assert "strength" in names
    end

    test "excludes divider blocks (they have nil variable_name)", %{sheet: sheet} do
      {:ok, _} = Sheets.create_block(sheet, %{type: "text", config: %{"label" => "Health"}})
      {:ok, _} = Sheets.create_block(sheet, %{type: "divider"})

      names = Storyarn.Sheets.BlockCrud.list_variable_names(sheet.id)
      assert length(names) == 1
      assert "health" in names
    end

    test "excludes specific block ID", %{sheet: sheet} do
      {:ok, b1} = Sheets.create_block(sheet, %{type: "text", config: %{"label" => "Health"}})
      {:ok, _b2} = Sheets.create_block(sheet, %{type: "text", config: %{"label" => "Mana"}})

      names = Storyarn.Sheets.BlockCrud.list_variable_names(sheet.id, b1.id)
      assert length(names) == 1
      assert "mana" in names
    end

    test "excludes soft-deleted blocks", %{sheet: sheet} do
      {:ok, block} = Sheets.create_block(sheet, %{type: "text", config: %{"label" => "Health"}})
      {:ok, _} = Sheets.delete_block(block)

      names = Storyarn.Sheets.BlockCrud.list_variable_names(sheet.id)
      assert names == []
    end
  end

  # ===========================================================================
  # find_unique_variable_name/2
  # ===========================================================================

  describe "find_unique_variable_name/2" do
    test "returns base name when no collision" do
      result = Storyarn.Sheets.BlockCrud.find_unique_variable_name("health", [])
      assert result == "health"
    end

    test "returns name_2 on first collision (list)" do
      result = Storyarn.Sheets.BlockCrud.find_unique_variable_name("health", ["health"])
      assert result == "health_2"
    end

    test "returns name_3 when name_2 also taken (list)" do
      existing = ["health", "health_2"]
      result = Storyarn.Sheets.BlockCrud.find_unique_variable_name("health", existing)
      assert result == "health_3"
    end

    test "works with MapSet" do
      existing = MapSet.new(["health", "health_2"])
      result = Storyarn.Sheets.BlockCrud.find_unique_variable_name("health", existing)
      assert result == "health_3"
    end

    test "returns base name when no collision (MapSet)" do
      existing = MapSet.new(["mana", "strength"])
      result = Storyarn.Sheets.BlockCrud.find_unique_variable_name("health", existing)
      assert result == "health"
    end
  end

  # ===========================================================================
  # create_block_from_snapshot/2
  # ===========================================================================

  describe "create_block_from_snapshot/2" do
    setup :setup_context

    test "restores a soft-deleted block from snapshot", %{sheet: sheet} do
      block = block_fixture(sheet)
      {:ok, deleted} = Sheets.delete_block(block)

      snapshot = %{
        id: deleted.id,
        type: deleted.type,
        position: deleted.position,
        config: deleted.config,
        value: deleted.value,
        variable_name: deleted.variable_name,
        is_constant: false,
        scope: "self",
        column_group_id: nil,
        column_index: 0
      }

      {:ok, restored} = Sheets.create_block_from_snapshot(sheet, snapshot)
      assert restored.id == block.id
      assert restored.deleted_at == nil
    end

    test "creates new block when original doesn't exist", %{sheet: sheet} do
      snapshot = %{
        id: 0,
        type: "text",
        position: 0,
        config: %{"label" => "Restored"},
        value: %{"content" => "hello"},
        variable_name: "restored",
        is_constant: false,
        scope: "self",
        column_group_id: nil,
        column_index: 0
      }

      {:ok, created} = Sheets.create_block_from_snapshot(sheet, snapshot)
      assert created.type == "text"
      assert created.config["label"] == "Restored"
    end

    test "returns error when block already exists and is active", %{sheet: sheet} do
      block = block_fixture(sheet)

      snapshot = %{
        id: block.id,
        type: block.type,
        position: block.position,
        config: block.config,
        value: block.value,
        variable_name: block.variable_name,
        is_constant: false,
        scope: "self",
        column_group_id: nil,
        column_index: 0
      }

      assert {:error, :block_already_exists} = Sheets.create_block_from_snapshot(sheet, snapshot)
    end
  end

  # ===========================================================================
  # change_block/2
  # ===========================================================================

  describe "change_block/2" do
    setup :setup_context

    test "returns a changeset", %{sheet: sheet} do
      block = block_fixture(sheet)
      changeset = Sheets.change_block(block, %{})
      assert %Ecto.Changeset{} = changeset
    end

    test "returns a changeset with changes", %{sheet: sheet} do
      block = block_fixture(sheet)
      changeset = Sheets.change_block(block, %{is_constant: true})
      assert changeset.changes[:is_constant] == true
    end
  end

  # ===========================================================================
  # import_block/2
  # ===========================================================================

  describe "import_block/2" do
    setup :setup_context

    test "creates a block without side effects", %{sheet: sheet} do
      {:ok, block} =
        Sheets.import_block(sheet.id, %{
          type: "text",
          config: %{"label" => "Imported"},
          value: %{"content" => ""},
          variable_name: "imported",
          position: 0
        })

      assert block.type == "text"
      assert block.config["label"] == "Imported"
    end

    test "does not auto-deduplicate variable names (relies on DB constraint)", %{sheet: sheet} do
      {:ok, _b1} =
        Sheets.import_block(sheet.id, %{
          type: "text",
          config: %{"label" => "Name"},
          variable_name: "name",
          position: 0
        })

      # import_block does NOT deduplicate in code, but the DB has a unique
      # constraint on (sheet_id, variable_name), so a duplicate raises
      assert_raise Ecto.ConstraintError, fn ->
        Sheets.import_block(sheet.id, %{
          type: "text",
          config: %{"label" => "Name"},
          variable_name: "name",
          position: 1
        })
      end
    end

    test "allows different variable names", %{sheet: sheet} do
      {:ok, b1} =
        Sheets.import_block(sheet.id, %{
          type: "text",
          config: %{"label" => "Name"},
          variable_name: "name",
          position: 0
        })

      {:ok, b2} =
        Sheets.import_block(sheet.id, %{
          type: "number",
          config: %{"label" => "Age"},
          variable_name: "age",
          position: 1
        })

      assert b1.variable_name == "name"
      assert b2.variable_name == "age"
    end
  end

  # ===========================================================================
  # ensure_unique_variable_name (via public wrapper)
  # ===========================================================================

  describe "ensure_unique_variable_name_public/3" do
    setup :setup_context

    test "leaves changeset unchanged when no collision", %{sheet: sheet} do
      changeset =
        %Block{sheet_id: sheet.id}
        |> Block.create_changeset(%{type: "text", config: %{"label" => "Unique"}})

      result =
        Storyarn.Sheets.BlockCrud.ensure_unique_variable_name_public(changeset, sheet.id, nil)

      assert Ecto.Changeset.get_field(result, :variable_name) == "unique"
    end

    test "appends suffix when collision exists", %{sheet: sheet} do
      {:ok, _} = Sheets.create_block(sheet, %{type: "text", config: %{"label" => "Health"}})

      changeset =
        %Block{sheet_id: sheet.id}
        |> Block.create_changeset(%{type: "text", config: %{"label" => "Health"}})

      result =
        Storyarn.Sheets.BlockCrud.ensure_unique_variable_name_public(changeset, sheet.id, nil)

      assert Ecto.Changeset.get_field(result, :variable_name) == "health_2"
    end

    test "skips self when exclude_block_id is provided", %{sheet: sheet} do
      {:ok, block} = Sheets.create_block(sheet, %{type: "text", config: %{"label" => "Health"}})

      changeset =
        block
        |> Block.update_changeset(%{config: %{"label" => "Health"}})

      result =
        Storyarn.Sheets.BlockCrud.ensure_unique_variable_name_public(
          changeset,
          sheet.id,
          block.id
        )

      assert Ecto.Changeset.get_field(result, :variable_name) == "health"
    end

    test "handles nil variable_name (divider)", %{sheet: sheet} do
      changeset =
        %Block{sheet_id: sheet.id}
        |> Block.create_changeset(%{type: "divider"})

      result =
        Storyarn.Sheets.BlockCrud.ensure_unique_variable_name_public(changeset, sheet.id, nil)

      assert Ecto.Changeset.get_field(result, :variable_name) == nil
    end
  end

  # ===========================================================================
  # Column group auto-dissolution on delete
  # ===========================================================================

  describe "column group dissolution on block delete" do
    setup :setup_context

    test "dissolves column group when fewer than 2 blocks remain", %{sheet: sheet} do
      b1 = block_fixture(sheet, %{config: %{"label" => "A"}})
      b2 = block_fixture(sheet, %{config: %{"label" => "B"}})

      {:ok, _group_id} = Sheets.create_column_group(sheet.id, [b1.id, b2.id])

      # Delete one block from the group
      b1_fresh = Sheets.get_block(b1.id)
      {:ok, _} = Sheets.delete_block(b1_fresh)

      # The remaining block should have its column_group dissolved
      remaining = Sheets.get_block(b2.id)
      assert remaining.column_group_id == nil
    end

    test "does not dissolve group when 2+ blocks remain", %{sheet: sheet} do
      b1 = block_fixture(sheet, %{config: %{"label" => "A"}})
      b2 = block_fixture(sheet, %{config: %{"label" => "B"}})
      b3 = block_fixture(sheet, %{config: %{"label" => "C"}})

      {:ok, group_id} = Sheets.create_column_group(sheet.id, [b1.id, b2.id, b3.id])

      # Delete one block
      b1_fresh = Sheets.get_block(b1.id)
      {:ok, _} = Sheets.delete_block(b1_fresh)

      # Remaining blocks should still have the group
      remaining_b2 = Sheets.get_block(b2.id)
      remaining_b3 = Sheets.get_block(b3.id)
      assert remaining_b2.column_group_id == group_id
      assert remaining_b3.column_group_id == group_id
    end
  end

  # ===========================================================================
  # duplicate_block/1
  # ===========================================================================

  describe "duplicate_block/1" do
    setup :setup_context

    test "creates copy with same type, config, value, and scope", %{sheet: sheet} do
      block =
        block_fixture(sheet, %{
          type: "number",
          config: %{"label" => "Health", "placeholder" => "0"},
          value: %{"content" => 42},
          scope: "children"
        })

      {:ok, copy} = Sheets.duplicate_block(block)

      assert copy.type == block.type
      assert copy.config == block.config
      assert copy.value == block.value
      assert copy.scope == block.scope
    end

    test "position is original + 1", %{sheet: sheet} do
      block = block_fixture(sheet, %{config: %{"label" => "A"}, position: 0})

      {:ok, copy} = Sheets.duplicate_block(block)

      assert copy.position == 1
    end

    test "shifts subsequent block positions", %{sheet: sheet} do
      b1 = block_fixture(sheet, %{config: %{"label" => "A"}, position: 0})
      b2 = block_fixture(sheet, %{config: %{"label" => "B"}, position: 1})
      b3 = block_fixture(sheet, %{config: %{"label" => "C"}, position: 2})

      {:ok, _copy} = Sheets.duplicate_block(b1)

      blocks = Sheets.list_blocks(sheet.id)
      positions = Map.new(blocks, &{&1.id, &1.position})

      assert positions[b1.id] == 0
      # copy is at position 1
      assert positions[b2.id] == 2
      assert positions[b3.id] == 3
    end

    test "generates unique variable_name", %{sheet: sheet} do
      block = block_fixture(sheet, %{config: %{"label" => "Health"}, position: 0})

      {:ok, copy} = Sheets.duplicate_block(block)

      assert copy.variable_name != nil
      assert copy.variable_name != block.variable_name
    end

    test "does NOT copy inherited_from_block_id", %{sheet: sheet} do
      block = block_fixture(sheet, %{config: %{"label" => "A"}, position: 0})

      {:ok, copy} = Sheets.duplicate_block(block)

      assert copy.inherited_from_block_id == nil
    end
  end

  # ===========================================================================
  # move_block_up/2
  # ===========================================================================

  describe "move_block_up/2" do
    setup :setup_context

    test "swaps with previous block", %{sheet: sheet} do
      b1 = block_fixture(sheet, %{config: %{"label" => "A"}, position: 0})
      b2 = block_fixture(sheet, %{config: %{"label" => "B"}, position: 1})

      {:ok, :moved} = Sheets.move_block_up(b2.id, sheet.id)

      blocks = Sheets.list_blocks(sheet.id)
      ids = Enum.map(blocks, & &1.id)
      assert ids == [b2.id, b1.id]
    end

    test "returns {:ok, :already_first} for first block", %{sheet: sheet} do
      b1 = block_fixture(sheet, %{config: %{"label" => "A"}, position: 0})
      _b2 = block_fixture(sheet, %{config: %{"label" => "B"}, position: 1})

      assert {:ok, :already_first} = Sheets.move_block_up(b1.id, sheet.id)
    end

    test "returns {:error, :not_found} for invalid id", %{sheet: sheet} do
      _b1 = block_fixture(sheet, %{config: %{"label" => "A"}, position: 0})

      assert {:error, :not_found} = Sheets.move_block_up(0, sheet.id)
    end
  end

  # ===========================================================================
  # move_block_down/2
  # ===========================================================================

  describe "move_block_down/2" do
    setup :setup_context

    test "swaps with next block", %{sheet: sheet} do
      b1 = block_fixture(sheet, %{config: %{"label" => "A"}, position: 0})
      b2 = block_fixture(sheet, %{config: %{"label" => "B"}, position: 1})

      {:ok, :moved} = Sheets.move_block_down(b1.id, sheet.id)

      blocks = Sheets.list_blocks(sheet.id)
      ids = Enum.map(blocks, & &1.id)
      assert ids == [b2.id, b1.id]
    end

    test "returns {:ok, :already_last} for last block", %{sheet: sheet} do
      _b1 = block_fixture(sheet, %{config: %{"label" => "A"}, position: 0})
      b2 = block_fixture(sheet, %{config: %{"label" => "B"}, position: 1})

      assert {:ok, :already_last} = Sheets.move_block_down(b2.id, sheet.id)
    end

    test "returns {:error, :not_found} for invalid id", %{sheet: sheet} do
      _b1 = block_fixture(sheet, %{config: %{"label" => "A"}, position: 0})

      assert {:error, :not_found} = Sheets.move_block_down(0, sheet.id)
    end
  end
end
