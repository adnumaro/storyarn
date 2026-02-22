defmodule Storyarn.SheetsTest do
  use Storyarn.DataCase

  import Ecto.Query

  alias Storyarn.Sheets

  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.SheetsFixtures
  import Storyarn.ProjectsFixtures

  describe "sheet avatar" do
    test "create_sheet/2 with avatar_asset_id sets the avatar" do
      user = user_fixture()
      project = project_fixture(user)
      asset = image_asset_fixture(project, user)

      {:ok, sheet} =
        Sheets.create_sheet(project, %{name: "Test Sheet", avatar_asset_id: asset.id})

      assert sheet.avatar_asset_id == asset.id
    end

    test "update_sheet/2 can set avatar_asset_id" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project)
      asset = image_asset_fixture(project, user)

      {:ok, updated} = Sheets.update_sheet(sheet, %{avatar_asset_id: asset.id})

      assert updated.avatar_asset_id == asset.id
    end

    test "update_sheet/2 can remove avatar_asset_id" do
      user = user_fixture()
      project = project_fixture(user)
      asset = image_asset_fixture(project, user)

      {:ok, sheet} =
        Sheets.create_sheet(project, %{name: "Test Sheet", avatar_asset_id: asset.id})

      {:ok, updated} = Sheets.update_sheet(sheet, %{avatar_asset_id: nil})

      assert updated.avatar_asset_id == nil
    end

    test "get_sheet/2 preloads avatar_asset" do
      user = user_fixture()
      project = project_fixture(user)
      asset = image_asset_fixture(project, user)

      {:ok, sheet} =
        Sheets.create_sheet(project, %{name: "Test Sheet", avatar_asset_id: asset.id})

      loaded_sheet = Sheets.get_sheet(project.id, sheet.id)

      assert loaded_sheet.avatar_asset.id == asset.id
      assert loaded_sheet.avatar_asset.url == asset.url
    end

    test "list_sheets_tree/1 preloads avatar_asset for all sheets" do
      user = user_fixture()
      project = project_fixture(user)
      asset = image_asset_fixture(project, user)

      {:ok, _sheet} =
        Sheets.create_sheet(project, %{name: "Test Sheet", avatar_asset_id: asset.id})

      [sheet] = Sheets.list_sheets_tree(project.id)

      assert sheet.avatar_asset.id == asset.id
    end
  end

  describe "sheets tree operations" do
    test "list_sheets_tree/1 returns root sheets with children preloaded" do
      user = user_fixture()
      project = project_fixture(user)

      # Create root sheets
      root1 = sheet_fixture(project, %{name: "Root 1", position: 0})
      _root2 = sheet_fixture(project, %{name: "Root 2", position: 1})

      # Create children
      _child1 = sheet_fixture(project, %{name: "Child 1", parent_id: root1.id, position: 0})
      _child2 = sheet_fixture(project, %{name: "Child 2", parent_id: root1.id, position: 1})

      sheets = Sheets.list_sheets_tree(project.id)

      assert length(sheets) == 2
      assert Enum.at(sheets, 0).name == "Root 1"
      assert Enum.at(sheets, 1).name == "Root 2"
      assert length(Enum.at(sheets, 0).children) == 2
      assert Enum.at(sheets, 1).children == []
    end

    test "get_sheet_with_ancestors/2 returns sheet with ancestor chain" do
      user = user_fixture()
      project = project_fixture(user)

      root = sheet_fixture(project, %{name: "Root"})
      child = sheet_fixture(project, %{name: "Child", parent_id: root.id})
      grandchild = sheet_fixture(project, %{name: "Grandchild", parent_id: child.id})

      ancestors = Sheets.get_sheet_with_ancestors(project.id, grandchild.id)

      assert length(ancestors) == 3
      assert Enum.at(ancestors, 0).name == "Root"
      assert Enum.at(ancestors, 1).name == "Child"
      assert Enum.at(ancestors, 2).name == "Grandchild"
    end

    test "move_sheet/3 moves sheet to new parent" do
      user = user_fixture()
      project = project_fixture(user)

      root1 = sheet_fixture(project, %{name: "Root 1"})
      root2 = sheet_fixture(project, %{name: "Root 2"})
      child = sheet_fixture(project, %{name: "Child", parent_id: root1.id})

      # Move child to root2
      {:ok, moved_sheet} = Sheets.move_sheet(child, root2.id)

      assert moved_sheet.parent_id == root2.id
    end

    test "move_sheet/3 prevents cycle creation" do
      user = user_fixture()
      project = project_fixture(user)

      root = sheet_fixture(project, %{name: "Root"})
      child = sheet_fixture(project, %{name: "Child", parent_id: root.id})
      grandchild = sheet_fixture(project, %{name: "Grandchild", parent_id: child.id})

      # Try to move root under grandchild (would create cycle)
      assert {:error, :would_create_cycle} = Sheets.move_sheet(root, grandchild.id)
    end

    test "move_sheet/3 allows moving sheet to root level" do
      user = user_fixture()
      project = project_fixture(user)

      root = sheet_fixture(project, %{name: "Root"})
      child = sheet_fixture(project, %{name: "Child", parent_id: root.id})

      # Move child to root level
      {:ok, moved_sheet} = Sheets.move_sheet(child, nil)

      assert moved_sheet.parent_id == nil
    end
  end

  describe "move_sheet_to_position/3" do
    test "moves sheet to specific position within same parent" do
      user = user_fixture()
      project = project_fixture(user)

      sheet1 = sheet_fixture(project, %{name: "Sheet 1", position: 0})
      sheet2 = sheet_fixture(project, %{name: "Sheet 2", position: 1})
      sheet3 = sheet_fixture(project, %{name: "Sheet 3", position: 2})

      # Move sheet3 to position 0
      {:ok, _moved_sheet} = Sheets.move_sheet_to_position(sheet3, nil, 0)

      # Verify new order
      sheets = Sheets.list_sheets_tree(project.id)
      assert Enum.at(sheets, 0).id == sheet3.id
      assert Enum.at(sheets, 1).id == sheet1.id
      assert Enum.at(sheets, 2).id == sheet2.id
    end

    test "moves sheet to different parent at specific position" do
      user = user_fixture()
      project = project_fixture(user)

      parent1 = sheet_fixture(project, %{name: "Parent 1"})
      parent2 = sheet_fixture(project, %{name: "Parent 2"})
      child1 = sheet_fixture(project, %{name: "Child 1", parent_id: parent1.id, position: 0})
      child2 = sheet_fixture(project, %{name: "Child 2", parent_id: parent2.id, position: 0})

      # Move child1 to parent2 at position 0
      {:ok, moved_sheet} = Sheets.move_sheet_to_position(child1, parent2.id, 0)

      assert moved_sheet.parent_id == parent2.id

      # Verify child1 is now first child of parent2
      parent2_with_children = Sheets.get_sheet_with_descendants(project.id, parent2.id)
      assert length(parent2_with_children.children) == 2
      assert Enum.at(parent2_with_children.children, 0).id == child1.id
      assert Enum.at(parent2_with_children.children, 1).id == child2.id

      # Verify parent1 has no children
      parent1_with_children = Sheets.get_sheet_with_descendants(project.id, parent1.id)
      assert parent1_with_children.children == []
    end

    test "prevents cycle when moving" do
      user = user_fixture()
      project = project_fixture(user)

      parent = sheet_fixture(project, %{name: "Parent"})
      child = sheet_fixture(project, %{name: "Child", parent_id: parent.id})

      # Try to move parent under its child
      assert {:error, :would_create_cycle} = Sheets.move_sheet_to_position(parent, child.id, 0)
    end
  end

  describe "reorder_sheets/3" do
    test "reorders sheets within same parent" do
      user = user_fixture()
      project = project_fixture(user)

      sheet1 = sheet_fixture(project, %{name: "Sheet 1", position: 0})
      sheet2 = sheet_fixture(project, %{name: "Sheet 2", position: 1})
      sheet3 = sheet_fixture(project, %{name: "Sheet 3", position: 2})

      # Reorder: [3, 1, 2]
      {:ok, sheets} = Sheets.reorder_sheets(project.id, nil, [sheet3.id, sheet1.id, sheet2.id])

      assert length(sheets) == 3
      assert Enum.at(sheets, 0).id == sheet3.id
      assert Enum.at(sheets, 1).id == sheet1.id
      assert Enum.at(sheets, 2).id == sheet2.id
    end

    test "reorders child sheets within parent" do
      user = user_fixture()
      project = project_fixture(user)

      parent = sheet_fixture(project, %{name: "Parent"})
      child1 = sheet_fixture(project, %{name: "Child 1", parent_id: parent.id, position: 0})
      child2 = sheet_fixture(project, %{name: "Child 2", parent_id: parent.id, position: 1})
      child3 = sheet_fixture(project, %{name: "Child 3", parent_id: parent.id, position: 2})

      # Reorder: [2, 3, 1]
      {:ok, sheets} =
        Sheets.reorder_sheets(project.id, parent.id, [child2.id, child3.id, child1.id])

      assert length(sheets) == 3
      assert Enum.at(sheets, 0).id == child2.id
      assert Enum.at(sheets, 1).id == child3.id
      assert Enum.at(sheets, 2).id == child1.id
    end
  end

  describe "blocks" do
    test "create_block/2 creates block with default config and value" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project)

      {:ok, block} = Sheets.create_block(sheet, %{type: "text"})

      assert block.type == "text"
      assert block.sheet_id == sheet.id
      assert block.position == 0
    end

    test "reorder_blocks/2 reorders blocks within sheet" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project)

      block1 = block_fixture(sheet)
      block2 = block_fixture(sheet)
      block3 = block_fixture(sheet)

      {:ok, blocks} = Sheets.reorder_blocks(sheet.id, [block3.id, block1.id, block2.id])

      assert Enum.at(blocks, 0).id == block3.id
      assert Enum.at(blocks, 1).id == block1.id
      assert Enum.at(blocks, 2).id == block2.id
    end
  end

  describe "get_block_in_project/2" do
    test "returns block when in correct project" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project)
      {:ok, block} = Sheets.create_block(sheet, %{type: "text"})

      result = Sheets.get_block_in_project(block.id, project.id)

      assert result.id == block.id
      assert result.type == "text"
    end

    test "returns nil when block is in different project" do
      user = user_fixture()
      project1 = project_fixture(user)
      project2 = project_fixture(user)
      sheet = sheet_fixture(project1)
      {:ok, block} = Sheets.create_block(sheet, %{type: "text"})

      # Try to get block from project1 using project2's ID
      result = Sheets.get_block_in_project(block.id, project2.id)

      assert result == nil
    end

    test "returns nil for deleted blocks" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project)
      {:ok, block} = Sheets.create_block(sheet, %{type: "text"})

      # Soft delete the block
      {:ok, _} = Sheets.delete_block(block)

      result = Sheets.get_block_in_project(block.id, project.id)

      assert result == nil
    end

    test "returns nil for blocks on deleted sheets" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project)
      {:ok, block} = Sheets.create_block(sheet, %{type: "text"})

      # Soft delete the sheet
      {:ok, _} = Sheets.delete_sheet(sheet)

      result = Sheets.get_block_in_project(block.id, project.id)

      assert result == nil
    end

    test "returns nil for non-existent block" do
      user = user_fixture()
      project = project_fixture(user)

      result = Sheets.get_block_in_project(-1, project.id)

      assert result == nil
    end
  end

  describe "get_block_in_project!/2" do
    test "returns block when in correct project" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project)
      {:ok, block} = Sheets.create_block(sheet, %{type: "text"})

      result = Sheets.get_block_in_project!(block.id, project.id)

      assert result.id == block.id
    end

    test "raises when block is in different project" do
      user = user_fixture()
      project1 = project_fixture(user)
      project2 = project_fixture(user)
      sheet = sheet_fixture(project1)
      {:ok, block} = Sheets.create_block(sheet, %{type: "text"})

      assert_raise Ecto.NoResultsError, fn ->
        Sheets.get_block_in_project!(block.id, project2.id)
      end
    end

    test "raises for deleted blocks" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project)
      {:ok, block} = Sheets.create_block(sheet, %{type: "text"})

      {:ok, _} = Sheets.delete_block(block)

      assert_raise Ecto.NoResultsError, fn ->
        Sheets.get_block_in_project!(block.id, project.id)
      end
    end
  end

  describe "reference blocks" do
    test "create_block/2 creates reference block with default config" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project)

      {:ok, block} = Sheets.create_block(sheet, %{type: "reference"})

      assert block.type == "reference"
      assert block.config["label"] == "Label"
      assert block.config["allowed_types"] == ["sheet", "flow"]
      assert block.value["target_type"] == nil
      assert block.value["target_id"] == nil
    end

    test "create_block/2 creates reference block with custom allowed_types" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project)

      {:ok, block} =
        Sheets.create_block(sheet, %{
          type: "reference",
          config: %{"label" => "Location", "allowed_types" => ["sheet"]}
        })

      assert block.config["label"] == "Location"
      assert block.config["allowed_types"] == ["sheet"]
    end

    test "update_block_value/2 sets reference target" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project)
      target_sheet = sheet_fixture(project, %{name: "Target Sheet"})
      {:ok, block} = Sheets.create_block(sheet, %{type: "reference"})

      {:ok, updated} =
        Sheets.update_block_value(block, %{
          "target_type" => "sheet",
          "target_id" => target_sheet.id
        })

      assert updated.value["target_type"] == "sheet"
      assert updated.value["target_id"] == target_sheet.id
    end

    test "update_block_value/2 clears reference target" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project)
      target_sheet = sheet_fixture(project)

      {:ok, block} =
        Sheets.create_block(sheet, %{
          type: "reference",
          value: %{"target_type" => "sheet", "target_id" => target_sheet.id}
        })

      {:ok, updated} =
        Sheets.update_block_value(block, %{"target_type" => nil, "target_id" => nil})

      assert updated.value["target_type"] == nil
      assert updated.value["target_id"] == nil
    end
  end

  describe "search functions" do
    test "search_sheets/2 finds sheets by name" do
      user = user_fixture()
      project = project_fixture(user)
      _sheet1 = sheet_fixture(project, %{name: "Character Jaime"})
      _sheet2 = sheet_fixture(project, %{name: "Location Tavern"})

      results = Sheets.SheetQueries.search_sheets(project.id, "Jaime")

      assert length(results) == 1
      assert Enum.at(results, 0).name == "Character Jaime"
    end

    test "search_sheets/2 finds sheets by shortcut" do
      user = user_fixture()
      project = project_fixture(user)
      {:ok, sheet1} = Sheets.create_sheet(project, %{name: "Jaime", shortcut: "mc.jaime"})
      _sheet2 = sheet_fixture(project, %{name: "Tavern"})

      results = Sheets.SheetQueries.search_sheets(project.id, "mc")

      assert length(results) == 1
      assert Enum.at(results, 0).id == sheet1.id
    end

    test "search_sheets/2 returns recent sheets when query is empty" do
      user = user_fixture()
      project = project_fixture(user)
      _sheet1 = sheet_fixture(project, %{name: "Sheet 1"})
      _sheet2 = sheet_fixture(project, %{name: "Sheet 2"})

      results = Sheets.SheetQueries.search_sheets(project.id, "")

      assert length(results) == 2
    end

    test "search_referenceable/3 returns sheets and flows" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project, %{name: "Test Sheet"})
      flow = flow_fixture(project, %{name: "Test Flow"})

      results = Sheets.search_referenceable(project.id, "Test", ["sheet", "flow"])

      assert length(results) == 2
      assert Enum.any?(results, &(&1.type == "sheet" && &1.id == sheet.id))
      assert Enum.any?(results, &(&1.type == "flow" && &1.id == flow.id))
    end

    test "search_referenceable/3 filters by allowed_types" do
      user = user_fixture()
      project = project_fixture(user)
      _sheet = sheet_fixture(project, %{name: "Test Sheet"})
      _flow = flow_fixture(project, %{name: "Test Flow"})

      results = Sheets.search_referenceable(project.id, "Test", ["sheet"])

      assert length(results) == 1
      assert Enum.at(results, 0).type == "sheet"
    end

    test "get_reference_target/3 returns sheet info" do
      user = user_fixture()
      project = project_fixture(user)
      {:ok, sheet} = Sheets.create_sheet(project, %{name: "Target", shortcut: "target"})

      result = Sheets.get_reference_target("sheet", sheet.id, project.id)

      assert result.type == "sheet"
      assert result.id == sheet.id
      assert result.name == "Target"
      assert result.shortcut == "target"
    end

    test "get_reference_target/3 returns flow info" do
      user = user_fixture()
      project = project_fixture(user)
      flow = flow_fixture(project, %{name: "Target Flow"})

      result = Sheets.get_reference_target("flow", flow.id, project.id)

      assert result.type == "flow"
      assert result.id == flow.id
      assert result.name == "Target Flow"
    end

    test "get_reference_target/3 returns nil for non-existent target" do
      user = user_fixture()
      project = project_fixture(user)

      assert Sheets.get_reference_target("sheet", -1, project.id) == nil
    end

    test "get_reference_target/3 returns nil for nil inputs" do
      user = user_fixture()
      project = project_fixture(user)

      assert Sheets.get_reference_target(nil, 1, project.id) == nil
      assert Sheets.get_reference_target("sheet", nil, project.id) == nil
    end
  end

  describe "validate_reference_target/3" do
    test "returns {:ok, sheet} for valid sheet in project" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project, %{name: "Target Sheet"})

      assert {:ok, result} = Sheets.validate_reference_target("sheet", sheet.id, project.id)
      assert result.id == sheet.id
    end

    test "returns {:ok, flow} for valid flow in project" do
      user = user_fixture()
      project = project_fixture(user)
      flow = flow_fixture(project, %{name: "Target Flow"})

      assert {:ok, result} = Sheets.validate_reference_target("flow", flow.id, project.id)
      assert result.id == flow.id
    end

    test "returns {:error, :not_found} for sheet in different project" do
      user = user_fixture()
      project1 = project_fixture(user)
      project2 = project_fixture(user)
      sheet = sheet_fixture(project1, %{name: "Target Sheet"})

      assert {:error, :not_found} =
               Sheets.validate_reference_target("sheet", sheet.id, project2.id)
    end

    test "returns {:error, :not_found} for flow in different project" do
      user = user_fixture()
      project1 = project_fixture(user)
      project2 = project_fixture(user)
      flow = flow_fixture(project1, %{name: "Target Flow"})

      assert {:error, :not_found} = Sheets.validate_reference_target("flow", flow.id, project2.id)
    end

    test "returns {:error, :not_found} for deleted sheet" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project, %{name: "Target Sheet"})

      {:ok, _} = Sheets.delete_sheet(sheet)

      assert {:error, :not_found} =
               Sheets.validate_reference_target("sheet", sheet.id, project.id)
    end

    test "returns {:error, :not_found} for non-existent target" do
      user = user_fixture()
      project = project_fixture(user)

      assert {:error, :not_found} = Sheets.validate_reference_target("sheet", -1, project.id)
    end

    test "returns {:error, :invalid_type} for unknown type" do
      user = user_fixture()
      project = project_fixture(user)

      assert {:error, :invalid_type} = Sheets.validate_reference_target("unknown", 1, project.id)
    end
  end

  describe "reference tracking" do
    alias Storyarn.Sheets.ReferenceTracker

    test "update_block_references/1 creates reference for reference block" do
      user = user_fixture()
      project = project_fixture(user)
      source_sheet = sheet_fixture(project, %{name: "Source Sheet"})
      target_sheet = sheet_fixture(project, %{name: "Target Sheet"})

      {:ok, block} =
        Sheets.create_block(source_sheet, %{
          type: "reference",
          value: %{"target_type" => "sheet", "target_id" => target_sheet.id}
        })

      ReferenceTracker.update_block_references(block)

      backlinks = ReferenceTracker.get_backlinks("sheet", target_sheet.id)
      assert length(backlinks) == 1
      assert Enum.at(backlinks, 0).source_id == block.id
      assert Enum.at(backlinks, 0).target_id == target_sheet.id
    end

    test "update_block_references/1 creates reference for rich_text mention" do
      user = user_fixture()
      project = project_fixture(user)
      source_sheet = sheet_fixture(project, %{name: "Source Sheet"})
      target_sheet = sheet_fixture(project, %{name: "Target Sheet"})

      mention_html = """
      <p>See <span class="mention" data-type="sheet" data-id="#{target_sheet.id}" data-label="target">#target</span></p>
      """

      {:ok, block} =
        Sheets.create_block(source_sheet, %{
          type: "rich_text",
          value: %{"content" => mention_html}
        })

      ReferenceTracker.update_block_references(block)

      backlinks = ReferenceTracker.get_backlinks("sheet", target_sheet.id)
      assert length(backlinks) == 1
    end

    test "update_block_references/1 replaces existing references" do
      user = user_fixture()
      project = project_fixture(user)
      source_sheet = sheet_fixture(project, %{name: "Source Sheet"})
      target1 = sheet_fixture(project, %{name: "Target 1"})
      target2 = sheet_fixture(project, %{name: "Target 2"})

      {:ok, block} =
        Sheets.create_block(source_sheet, %{
          type: "reference",
          value: %{"target_type" => "sheet", "target_id" => target1.id}
        })

      ReferenceTracker.update_block_references(block)

      # Update to point to target2
      {:ok, updated_block} =
        Sheets.update_block_value(block, %{"target_type" => "sheet", "target_id" => target2.id})

      ReferenceTracker.update_block_references(updated_block)

      # Old reference should be removed
      assert ReferenceTracker.get_backlinks("sheet", target1.id) == []
      # New reference should exist
      assert length(ReferenceTracker.get_backlinks("sheet", target2.id)) == 1
    end

    test "delete_block_references/1 removes all references from block" do
      user = user_fixture()
      project = project_fixture(user)
      source_sheet = sheet_fixture(project, %{name: "Source Sheet"})
      target_sheet = sheet_fixture(project, %{name: "Target Sheet"})

      {:ok, block} =
        Sheets.create_block(source_sheet, %{
          type: "reference",
          value: %{"target_type" => "sheet", "target_id" => target_sheet.id}
        })

      ReferenceTracker.update_block_references(block)
      assert length(ReferenceTracker.get_backlinks("sheet", target_sheet.id)) == 1

      ReferenceTracker.delete_block_references(block.id)
      assert ReferenceTracker.get_backlinks("sheet", target_sheet.id) == []
    end

    test "count_backlinks/2 returns correct count" do
      user = user_fixture()
      project = project_fixture(user)
      source_sheet1 = sheet_fixture(project, %{name: "Source 1"})
      source_sheet2 = sheet_fixture(project, %{name: "Source 2"})
      target_sheet = sheet_fixture(project, %{name: "Target Sheet"})

      {:ok, block1} =
        Sheets.create_block(source_sheet1, %{
          type: "reference",
          value: %{"target_type" => "sheet", "target_id" => target_sheet.id}
        })

      {:ok, block2} =
        Sheets.create_block(source_sheet2, %{
          type: "reference",
          value: %{"target_type" => "sheet", "target_id" => target_sheet.id}
        })

      ReferenceTracker.update_block_references(block1)
      ReferenceTracker.update_block_references(block2)

      assert Sheets.count_backlinks("sheet", target_sheet.id) == 2
    end

    test "get_backlinks_with_sources/3 returns source info" do
      user = user_fixture()
      project = project_fixture(user)
      source_sheet = sheet_fixture(project, %{name: "Source Sheet"})
      target_sheet = sheet_fixture(project, %{name: "Target Sheet"})

      {:ok, block} =
        Sheets.create_block(source_sheet, %{
          type: "reference",
          config: %{"label" => "Location Reference"},
          value: %{"target_type" => "sheet", "target_id" => target_sheet.id}
        })

      ReferenceTracker.update_block_references(block)

      backlinks = Sheets.get_backlinks_with_sources("sheet", target_sheet.id, project.id)

      assert length(backlinks) == 1
      backlink = Enum.at(backlinks, 0)
      assert backlink.source_type == "block"
      assert backlink.source_info.sheet_name == "Source Sheet"
      assert backlink.source_info.block_label == "Location Reference"
      assert backlink.source_info.block_type == "reference"
    end
  end

  describe "boolean blocks" do
    test "create_block/2 creates boolean block with two_state default config" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project)

      {:ok, block} = Sheets.create_block(sheet, %{type: "boolean"})

      assert block.type == "boolean"
      assert block.config["mode"] == "two_state"
      assert block.config["label"] == "Label"
      assert block.value["content"] == nil
    end

    test "create_block/2 creates boolean block with custom config" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project)

      {:ok, block} =
        Sheets.create_block(sheet, %{
          type: "boolean",
          config: %{"label" => "Is Active", "mode" => "tri_state"},
          value: %{"content" => nil}
        })

      assert block.type == "boolean"
      assert block.config["label"] == "Is Active"
      assert block.config["mode"] == "tri_state"
      assert block.value["content"] == nil
    end

    test "update_block_value/2 updates boolean block value to true" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project)
      {:ok, block} = Sheets.create_block(sheet, %{type: "boolean"})

      {:ok, updated} = Sheets.update_block_value(block, %{"content" => true})

      assert updated.value["content"] == true
    end

    test "update_block_value/2 updates boolean block value to false" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project)

      {:ok, block} =
        Sheets.create_block(sheet, %{
          type: "boolean",
          value: %{"content" => true}
        })

      {:ok, updated} = Sheets.update_block_value(block, %{"content" => false})

      assert updated.value["content"] == false
    end

    test "update_block_value/2 updates boolean block value to nil (tri-state)" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project)

      {:ok, block} =
        Sheets.create_block(sheet, %{
          type: "boolean",
          config: %{"label" => "Tri-state Field", "mode" => "tri_state"},
          value: %{"content" => true}
        })

      {:ok, updated} = Sheets.update_block_value(block, %{"content" => nil})

      assert updated.value["content"] == nil
    end

    test "update_block_config/2 changes mode from two_state to tri_state" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project)
      {:ok, block} = Sheets.create_block(sheet, %{type: "boolean"})

      {:ok, updated} =
        Sheets.update_block_config(block, %{"label" => "Test", "mode" => "tri_state"})

      assert updated.config["mode"] == "tri_state"
      assert updated.config["label"] == "Test"
    end
  end

  # ===========================================================================
  # Soft Delete Tests (5.2)
  # ===========================================================================

  describe "trash_sheet/1" do
    test "sets deleted_at on sheet" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project)

      {:ok, deleted} = Sheets.trash_sheet(sheet)

      assert deleted.deleted_at != nil
    end

    test "sets deleted_at on all descendant sheets" do
      user = user_fixture()
      project = project_fixture(user)
      root = sheet_fixture(project, %{name: "Root"})
      child = sheet_fixture(project, %{name: "Child", parent_id: root.id})
      grandchild = sheet_fixture(project, %{name: "Grandchild", parent_id: child.id})

      {:ok, _} = Sheets.trash_sheet(root)

      # Verify descendants are also deleted
      trashed = Sheets.list_trashed_sheets(project.id)
      trashed_ids = Enum.map(trashed, & &1.id)

      assert root.id in trashed_ids
      assert child.id in trashed_ids
      assert grandchild.id in trashed_ids
    end

    test "does not affect non-descendant sheets" do
      user = user_fixture()
      project = project_fixture(user)
      sheet1 = sheet_fixture(project, %{name: "Sheet 1"})
      sheet2 = sheet_fixture(project, %{name: "Sheet 2"})

      {:ok, _} = Sheets.trash_sheet(sheet1)

      # sheet2 should still be accessible
      assert Sheets.get_sheet(project.id, sheet2.id) != nil
      assert Sheets.get_sheet(project.id, sheet1.id) == nil
    end
  end

  describe "list_trashed_sheets/1" do
    test "returns only deleted sheets" do
      user = user_fixture()
      project = project_fixture(user)
      sheet1 = sheet_fixture(project, %{name: "Active Sheet"})
      sheet2 = sheet_fixture(project, %{name: "Trashed Sheet"})

      {:ok, _} = Sheets.trash_sheet(sheet2)

      trashed = Sheets.list_trashed_sheets(project.id)

      assert length(trashed) == 1
      assert Enum.at(trashed, 0).id == sheet2.id
      refute sheet1.id in Enum.map(trashed, & &1.id)
    end

    test "scopes to project" do
      user = user_fixture()
      project1 = project_fixture(user)
      project2 = project_fixture(user)
      sheet1 = sheet_fixture(project1, %{name: "Project 1 Sheet"})
      sheet2 = sheet_fixture(project2, %{name: "Project 2 Sheet"})

      {:ok, _} = Sheets.trash_sheet(sheet1)
      {:ok, _} = Sheets.trash_sheet(sheet2)

      trashed1 = Sheets.list_trashed_sheets(project1.id)
      trashed2 = Sheets.list_trashed_sheets(project2.id)

      assert length(trashed1) == 1
      assert length(trashed2) == 1
      assert Enum.at(trashed1, 0).id == sheet1.id
      assert Enum.at(trashed2, 0).id == sheet2.id
    end

    test "orders by deleted_at desc" do
      user = user_fixture()
      project = project_fixture(user)
      sheet1 = sheet_fixture(project, %{name: "First Deleted"})
      sheet2 = sheet_fixture(project, %{name: "Second Deleted"})

      {:ok, _} = Sheets.trash_sheet(sheet1)
      {:ok, _} = Sheets.trash_sheet(sheet2)

      # Set explicit timestamps to ensure deterministic ordering
      earlier = ~U[2024-01-01 10:00:00Z]
      later = ~U[2024-01-01 11:00:00Z]

      Storyarn.Repo.update_all(
        from(s in Storyarn.Sheets.Sheet, where: s.id == ^sheet1.id),
        set: [deleted_at: earlier]
      )

      Storyarn.Repo.update_all(
        from(s in Storyarn.Sheets.Sheet, where: s.id == ^sheet2.id),
        set: [deleted_at: later]
      )

      trashed = Sheets.list_trashed_sheets(project.id)

      # More recently deleted should come first
      assert length(trashed) == 2
      assert Enum.at(trashed, 0).id == sheet2.id
      assert Enum.at(trashed, 1).id == sheet1.id
    end
  end

  describe "get_trashed_sheet/2" do
    test "returns deleted sheet by id" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project)

      {:ok, _} = Sheets.trash_sheet(sheet)

      trashed = Sheets.get_trashed_sheet(project.id, sheet.id)

      assert trashed.id == sheet.id
      assert trashed.deleted_at != nil
    end

    test "returns nil for non-deleted sheet" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project)

      assert Sheets.get_trashed_sheet(project.id, sheet.id) == nil
    end
  end

  describe "restore_sheet/1" do
    test "clears deleted_at" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project)

      {:ok, trashed} = Sheets.trash_sheet(sheet)
      assert trashed.deleted_at != nil

      {:ok, restored} = Sheets.restore_sheet(trashed)

      assert restored.deleted_at == nil
      assert Sheets.get_sheet(project.id, sheet.id) != nil
    end

    test "restores soft-deleted blocks" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project)
      block = block_fixture(sheet)

      # Delete the block first
      {:ok, _} = Sheets.delete_block(block)
      assert Sheets.get_block(block.id) == nil

      # Trash and restore the sheet
      {:ok, trashed} = Sheets.trash_sheet(sheet)
      {:ok, _} = Sheets.restore_sheet(trashed)

      # Block should be restored
      restored_block = Sheets.get_block(block.id)
      assert restored_block != nil
      assert restored_block.deleted_at == nil
    end
  end

  describe "permanently_delete_sheet/1" do
    test "removes sheet from database" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project)
      sheet_id = sheet.id

      {:ok, _} = Sheets.permanently_delete_sheet(sheet)

      # Sheet should not exist anywhere
      assert Sheets.get_sheet(project.id, sheet_id) == nil
      assert Sheets.get_trashed_sheet(project.id, sheet_id) == nil
    end

    test "removes all versions" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project)

      {:ok, _} = Sheets.create_version(sheet, user)
      {:ok, _} = Sheets.create_version(sheet, user)
      assert Sheets.count_versions(sheet.id) == 2

      {:ok, _} = Sheets.permanently_delete_sheet(sheet)

      assert Sheets.count_versions(sheet.id) == 0
    end
  end

  describe "soft delete query filtering" do
    test "list_sheets_tree excludes deleted sheets" do
      user = user_fixture()
      project = project_fixture(user)
      sheet1 = sheet_fixture(project, %{name: "Active"})
      sheet2 = sheet_fixture(project, %{name: "Deleted"})

      {:ok, _} = Sheets.trash_sheet(sheet2)

      tree = Sheets.list_sheets_tree(project.id)

      assert length(tree) == 1
      assert Enum.at(tree, 0).id == sheet1.id
    end

    test "get_sheet returns nil for deleted sheets" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project)

      {:ok, _} = Sheets.trash_sheet(sheet)

      assert Sheets.get_sheet(project.id, sheet.id) == nil
    end

    test "search_sheets excludes deleted sheets" do
      user = user_fixture()
      project = project_fixture(user)
      _sheet1 = sheet_fixture(project, %{name: "Active Character"})
      sheet2 = sheet_fixture(project, %{name: "Deleted Character"})

      {:ok, _} = Sheets.trash_sheet(sheet2)

      results = Sheets.SheetQueries.search_sheets(project.id, "Character")

      assert length(results) == 1
      assert Enum.at(results, 0).name == "Active Character"
    end
  end

  describe "block soft delete" do
    test "delete_block/1 sets deleted_at" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project)
      {:ok, block} = Sheets.create_block(sheet, %{type: "text"})

      {:ok, deleted} = Sheets.delete_block(block)

      assert deleted.deleted_at != nil
    end

    test "list_blocks/1 excludes deleted blocks" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project)
      {:ok, block1} = Sheets.create_block(sheet, %{type: "text"})
      {:ok, block2} = Sheets.create_block(sheet, %{type: "number"})

      {:ok, _} = Sheets.delete_block(block2)

      blocks = Sheets.list_blocks(sheet.id)

      assert length(blocks) == 1
      assert Enum.at(blocks, 0).id == block1.id
    end

    test "get_block/1 returns nil for deleted blocks" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project)
      {:ok, block} = Sheets.create_block(sheet, %{type: "text"})

      {:ok, _} = Sheets.delete_block(block)

      assert Sheets.get_block(block.id) == nil
    end

    test "restore_block/1 clears deleted_at" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project)
      {:ok, block} = Sheets.create_block(sheet, %{type: "text"})

      {:ok, deleted} = Sheets.delete_block(block)
      assert deleted.deleted_at != nil

      {:ok, restored} = Sheets.restore_block(deleted)

      assert restored.deleted_at == nil
      assert Sheets.get_block(block.id) != nil
    end

    test "permanently_delete_block/1 removes from database" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project)
      {:ok, block} = Sheets.create_block(sheet, %{type: "text"})
      block_id = block.id

      {:ok, _} = Sheets.permanently_delete_block(block)

      # Block should not exist at all
      assert Storyarn.Repo.get(Storyarn.Sheets.Block, block_id) == nil
    end
  end

  # ===========================================================================
  # Shortcut Tests (5.3)
  # ===========================================================================

  describe "shortcut auto-generation" do
    test "generates shortcut from sheet name on create" do
      user = user_fixture()
      project = project_fixture(user)

      {:ok, sheet} = Sheets.create_sheet(project, %{name: "My Character"})

      assert sheet.shortcut == "my-character"
    end

    test "generates unique shortcut when collision exists" do
      user = user_fixture()
      project = project_fixture(user)

      {:ok, sheet1} = Sheets.create_sheet(project, %{name: "Character"})
      {:ok, sheet2} = Sheets.create_sheet(project, %{name: "Character"})
      {:ok, sheet3} = Sheets.create_sheet(project, %{name: "Character"})

      assert sheet1.shortcut == "character"
      assert sheet2.shortcut == "character-1"
      assert sheet3.shortcut == "character-2"
    end

    test "preserves explicit shortcut when provided" do
      user = user_fixture()
      project = project_fixture(user)

      {:ok, sheet} = Sheets.create_sheet(project, %{name: "My Character", shortcut: "mc.jaime"})

      assert sheet.shortcut == "mc.jaime"
    end

    test "regenerates shortcut when name changes and no explicit shortcut" do
      user = user_fixture()
      project = project_fixture(user)
      {:ok, sheet} = Sheets.create_sheet(project, %{name: "Original Name"})

      assert sheet.shortcut == "original-name"

      {:ok, updated} = Sheets.update_sheet(sheet, %{name: "New Name"})

      assert updated.shortcut == "new-name"
    end

    test "does not regenerate when explicit shortcut provided" do
      user = user_fixture()
      project = project_fixture(user)

      {:ok, sheet} =
        Sheets.create_sheet(project, %{name: "Original", shortcut: "custom-shortcut"})

      {:ok, updated} =
        Sheets.update_sheet(sheet, %{name: "New Name", shortcut: "custom-shortcut"})

      assert updated.shortcut == "custom-shortcut"
    end

    test "handles empty name gracefully" do
      user = user_fixture()
      project = project_fixture(user)

      # Empty name should fail validation (required field)
      {:error, changeset} = Sheets.create_sheet(project, %{name: ""})

      assert changeset.errors[:name] != nil
    end

    test "slugifies name correctly (spaces, special chars)" do
      user = user_fixture()
      project = project_fixture(user)

      {:ok, sheet1} = Sheets.create_sheet(project, %{name: "Chapter 1: The Beginning"})
      {:ok, sheet2} = Sheets.create_sheet(project, %{name: "MC.Jaime"})
      {:ok, sheet3} = Sheets.create_sheet(project, %{name: "Test   Multiple   Spaces"})

      assert sheet1.shortcut == "chapter-1-the-beginning"
      assert sheet2.shortcut == "mc.jaime"
      assert sheet3.shortcut == "test-multiple-spaces"
    end
  end

  describe "shortcut validation" do
    alias Storyarn.Shared.NameNormalizer

    test "accepts lowercase alphanumeric" do
      assert NameNormalizer.shortcutify("test123") == "test123"
    end

    test "accepts dots and hyphens" do
      assert NameNormalizer.shortcutify("mc.jaime") == "mc.jaime"
      assert NameNormalizer.shortcutify("chapter-one") == "chapter-one"
    end

    test "rejects uppercase by converting to lowercase" do
      assert NameNormalizer.shortcutify("UPPERCASE") == "uppercase"
      assert NameNormalizer.shortcutify("MixedCase") == "mixedcase"
    end

    test "rejects spaces by converting to hyphens" do
      assert NameNormalizer.shortcutify("has spaces") == "has-spaces"
    end

    test "rejects special characters" do
      assert NameNormalizer.shortcutify("test@#$%^&*") == "test"
      assert NameNormalizer.shortcutify("emoji😀test") == "emojitest"
    end

    test "rejects leading/trailing dots or hyphens" do
      assert NameNormalizer.shortcutify(".leading-dot") == "leading-dot"
      assert NameNormalizer.shortcutify("trailing-dot.") == "trailing-dot"
      assert NameNormalizer.shortcutify("-leading-hyphen") == "leading-hyphen"
      assert NameNormalizer.shortcutify("trailing-hyphen-") == "trailing-hyphen"
    end

    test "collapses consecutive dots" do
      assert NameNormalizer.shortcutify("mc..jaime") == "mc.jaime"
      assert NameNormalizer.shortcutify("test...multiple") == "test.multiple"
    end

    test "collapses consecutive hyphens" do
      assert NameNormalizer.shortcutify("test--multiple") == "test-multiple"
      assert NameNormalizer.shortcutify("test---hyphens") == "test-hyphens"
    end

    test "enforces uniqueness within project" do
      user = user_fixture()
      project = project_fixture(user)

      {:ok, _} = Sheets.create_sheet(project, %{name: "Test", shortcut: "unique-shortcut"})
      {:ok, sheet2} = Sheets.create_sheet(project, %{name: "Test 2"})

      # Trying to manually set the same shortcut should fail
      {:error, changeset} = Sheets.update_sheet(sheet2, %{shortcut: "unique-shortcut"})

      assert changeset.errors[:shortcut] != nil
      assert {msg, _} = changeset.errors[:shortcut]
      assert msg =~ "already taken"
    end

    test "allows same shortcut in different projects" do
      user = user_fixture()
      project1 = project_fixture(user)
      project2 = project_fixture(user)

      {:ok, sheet1} = Sheets.create_sheet(project1, %{name: "Test", shortcut: "same-shortcut"})
      {:ok, sheet2} = Sheets.create_sheet(project2, %{name: "Test", shortcut: "same-shortcut"})

      assert sheet1.shortcut == "same-shortcut"
      assert sheet2.shortcut == "same-shortcut"
    end

    test "allows reuse after soft delete" do
      user = user_fixture()
      project = project_fixture(user)

      {:ok, sheet1} = Sheets.create_sheet(project, %{name: "Test", shortcut: "reused-shortcut"})
      {:ok, _} = Sheets.trash_sheet(sheet1)

      # Should be able to create a new sheet with the same shortcut
      {:ok, sheet2} = Sheets.create_sheet(project, %{name: "Test 2", shortcut: "reused-shortcut"})

      assert sheet2.shortcut == "reused-shortcut"
    end
  end

  describe "list_project_variables/1" do
    test "returns variable blocks with correct shape" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project, %{name: "MC", shortcut: "mc"})
      block_fixture(sheet, %{type: "number", config: %{"label" => "Health"}})

      [var] = Sheets.list_project_variables(project.id)

      assert var.sheet_name == "MC"
      assert var.sheet_shortcut == "mc"
      assert var.variable_name == "health"
      assert var.block_type == "number"
      assert var.options == nil
      assert Map.has_key?(var, :sheet_id)
      assert Map.has_key?(var, :block_id)
      refute Map.has_key?(var, :config)
    end

    test "excludes constant blocks" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project, %{name: "MC", shortcut: "mc"})
      block_fixture(sheet, %{type: "number", config: %{"label" => "Health"}})
      block_fixture(sheet, %{type: "text", config: %{"label" => "Bio"}, is_constant: true})

      vars = Sheets.list_project_variables(project.id)

      assert length(vars) == 1
      assert hd(vars).variable_name == "health"
    end

    test "excludes non-variable types like divider" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project, %{name: "MC", shortcut: "mc"})
      block_fixture(sheet, %{type: "number", config: %{"label" => "Health"}})
      block_fixture(sheet, %{type: "divider", config: %{"label" => "---"}})

      vars = Sheets.list_project_variables(project.id)

      assert length(vars) == 1
    end

    test "returns empty list for project with no sheets" do
      user = user_fixture()
      project = project_fixture(user)

      assert Sheets.list_project_variables(project.id) == []
    end

    test "includes select options in result" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project, %{name: "MC", shortcut: "mc"})

      block_fixture(sheet, %{
        type: "select",
        config: %{"label" => "Class", "options" => ["Warrior", "Mage"]}
      })

      [var] = Sheets.list_project_variables(project.id)

      assert var.block_type == "select"
      assert var.options == ["Warrior", "Mage"]
    end

    test "table generates variables for non-constant cells" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project, %{name: "Jaime", shortcut: "mc.jaime"})

      # table_block_fixture auto-creates 1 default column ("Value", number) + 1 default row ("Row 1")
      table = table_block_fixture(sheet, %{label: "Attributes"})
      _col1 = table_column_fixture(table, %{name: "Strength", type: "number"})
      _col2 = table_column_fixture(table, %{name: "Agility", type: "number"})
      _row = table_row_fixture(table, %{name: "Extra"})

      vars = Sheets.list_project_variables(project.id)
      table_vars = Enum.filter(vars, &(&1.table_name != nil))

      # 3 columns (default "Value" + "Strength" + "Agility") × 2 rows (default "Row 1" + "Extra") = 6
      assert length(table_vars) == 6

      var_names = Enum.map(table_vars, & &1.variable_name)
      assert "attributes.row_1.strength" in var_names
      assert "attributes.row_1.agility" in var_names
      assert "attributes.extra.strength" in var_names
      assert "attributes.extra.agility" in var_names
    end

    test "table constant columns excluded from variables" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project, %{name: "Jaime", shortcut: "mc.jaime"})
      # Auto-creates default column "Value" (number, non-constant) + default row "Row 1"
      table = table_block_fixture(sheet, %{label: "Stats"})
      _col_var = table_column_fixture(table, %{name: "HP", type: "number"})
      _col_const = table_column_fixture(table, %{name: "Label", type: "text", is_constant: true})

      vars = Sheets.list_project_variables(project.id)
      table_vars = Enum.filter(vars, &(&1.table_name != nil))

      # Default "Value" + "HP" = 2 non-constant columns × 1 default row = 2 vars
      # "Label" is constant so excluded
      assert length(table_vars) == 2
      col_names = Enum.map(table_vars, & &1.column_name) |> Enum.sort()
      assert col_names == ["hp", "value"]
    end

    test "regular vars have nil table fields" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project, %{name: "MC", shortcut: "mc"})
      block_fixture(sheet, %{type: "number", config: %{"label" => "Health"}})

      [var] = Sheets.list_project_variables(project.id)

      assert var.table_name == nil
      assert var.row_name == nil
      assert var.column_name == nil
    end

    test "table variables have table fields populated" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project, %{name: "Jaime", shortcut: "mc.jaime"})
      # Auto-creates default column "Value" (number) + default row "Row 1"
      table = table_block_fixture(sheet, %{label: "Attributes"})
      _col = table_column_fixture(table, %{name: "Strength", type: "number"})

      vars = Sheets.list_project_variables(project.id)
      table_vars = Enum.filter(vars, &(&1.table_name != nil))

      # 2 columns (default "Value" + "Strength") × 1 row (default "Row 1") = 2
      assert length(table_vars) == 2

      strength_var = Enum.find(table_vars, &(&1.column_name == "strength"))
      assert strength_var.table_name == "attributes"
      assert strength_var.row_name == "row_1"
      assert strength_var.column_name == "strength"
    end

    test "table select column options included" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project, %{name: "Jaime", shortcut: "mc.jaime"})
      # Auto-creates default column "Value" (number) + default row "Row 1"
      table = table_block_fixture(sheet, %{label: "Traits"})

      _col =
        table_column_fixture(table, %{
          name: "Class",
          type: "select",
          config: %{"options" => ["Warrior", "Mage", "Thief"]}
        })

      vars = Sheets.list_project_variables(project.id)
      table_vars = Enum.filter(vars, &(&1.table_name != nil))

      # 2 columns (default "Value" + "Class") × 1 row (default "Row 1") = 2
      assert length(table_vars) == 2

      class_var = Enum.find(table_vars, &(&1.column_name == "class"))
      assert class_var.options == ["Warrior", "Mage", "Thief"]
    end

    test "mixed regular and table variables returned together" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project, %{name: "Jaime", shortcut: "mc.jaime"})

      # Regular variable
      block_fixture(sheet, %{type: "number", config: %{"label" => "Health"}})

      # Table variable (auto-creates default "Value" column + "Row 1" row)
      table = table_block_fixture(sheet, %{label: "Attributes"})
      _col = table_column_fixture(table, %{name: "Strength", type: "number"})

      vars = Sheets.list_project_variables(project.id)

      regular_vars = Enum.filter(vars, &(&1.table_name == nil))
      table_vars = Enum.filter(vars, &(&1.table_name != nil))

      assert length(regular_vars) == 1
      # 2 columns (default "Value" + "Strength") × 1 row = 2
      assert length(table_vars) == 2
      assert hd(regular_vars).variable_name == "health"

      strength_var = Enum.find(table_vars, &(&1.column_name == "strength"))
      assert strength_var.variable_name == "attributes.row_1.strength"
    end

    test "block variable includes constraints when set" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project, %{name: "MC", shortcut: "mc"})

      block_fixture(sheet, %{
        type: "number",
        config: %{"label" => "Health", "min" => 0, "max" => 100, "step" => 1}
      })

      [var] = Sheets.list_project_variables(project.id)

      assert var.constraints == %{"min" => 0, "max" => 100, "step" => 1}
    end

    test "block variable has nil constraints when none set" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project, %{name: "MC", shortcut: "mc"})
      block_fixture(sheet, %{type: "number", config: %{"label" => "Health"}})

      [var] = Sheets.list_project_variables(project.id)

      assert var.constraints == nil
    end

    test "non-number block variable has nil constraints" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project, %{name: "MC", shortcut: "mc"})
      block_fixture(sheet, %{type: "text", config: %{"label" => "Name"}})

      [var] = Sheets.list_project_variables(project.id)

      assert var.constraints == nil
    end

    test "table variable includes constraints from column config" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project, %{name: "MC", shortcut: "mc.jaime"})
      table = table_block_fixture(sheet, %{label: "Stats"})

      _col =
        table_column_fixture(table, %{
          name: "Health",
          type: "number",
          config: %{"min" => 0, "max" => 10}
        })

      vars = Sheets.list_project_variables(project.id)
      table_vars = Enum.filter(vars, &(&1.table_name != nil))

      health_var = Enum.find(table_vars, &(&1.column_name == "health"))
      assert health_var.constraints == %{"min" => 0, "max" => 10, "step" => nil}
    end

    test "table non-number column has nil constraints" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project, %{name: "MC", shortcut: "mc.jaime"})
      table = table_block_fixture(sheet, %{label: "Stats"})
      _col = table_column_fixture(table, %{name: "Name", type: "text"})

      vars = Sheets.list_project_variables(project.id)
      table_vars = Enum.filter(vars, &(&1.table_name != nil))

      name_var = Enum.find(table_vars, &(&1.column_name == "name"))
      assert name_var.constraints == nil
    end
  end
end
