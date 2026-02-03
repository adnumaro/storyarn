defmodule Storyarn.PagesTest do
  use Storyarn.DataCase

  alias Storyarn.Pages

  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.PagesFixtures
  import Storyarn.ProjectsFixtures

  describe "page avatar" do
    test "create_page/2 with avatar_asset_id sets the avatar" do
      user = user_fixture()
      project = project_fixture(user)
      asset = image_asset_fixture(project, user)

      {:ok, page} = Pages.create_page(project, %{name: "Test Page", avatar_asset_id: asset.id})

      assert page.avatar_asset_id == asset.id
    end

    test "update_page/2 can set avatar_asset_id" do
      user = user_fixture()
      project = project_fixture(user)
      page = page_fixture(project)
      asset = image_asset_fixture(project, user)

      {:ok, updated} = Pages.update_page(page, %{avatar_asset_id: asset.id})

      assert updated.avatar_asset_id == asset.id
    end

    test "update_page/2 can remove avatar_asset_id" do
      user = user_fixture()
      project = project_fixture(user)
      asset = image_asset_fixture(project, user)
      {:ok, page} = Pages.create_page(project, %{name: "Test Page", avatar_asset_id: asset.id})

      {:ok, updated} = Pages.update_page(page, %{avatar_asset_id: nil})

      assert updated.avatar_asset_id == nil
    end

    test "get_page/2 preloads avatar_asset" do
      user = user_fixture()
      project = project_fixture(user)
      asset = image_asset_fixture(project, user)
      {:ok, page} = Pages.create_page(project, %{name: "Test Page", avatar_asset_id: asset.id})

      loaded_page = Pages.get_page(project.id, page.id)

      assert loaded_page.avatar_asset.id == asset.id
      assert loaded_page.avatar_asset.url == asset.url
    end

    test "list_pages_tree/1 preloads avatar_asset for all pages" do
      user = user_fixture()
      project = project_fixture(user)
      asset = image_asset_fixture(project, user)
      {:ok, _page} = Pages.create_page(project, %{name: "Test Page", avatar_asset_id: asset.id})

      [page] = Pages.list_pages_tree(project.id)

      assert page.avatar_asset.id == asset.id
    end
  end

  describe "pages tree operations" do
    test "list_pages_tree/1 returns root pages with children preloaded" do
      user = user_fixture()
      project = project_fixture(user)

      # Create root pages
      root1 = page_fixture(project, %{name: "Root 1", position: 0})
      _root2 = page_fixture(project, %{name: "Root 2", position: 1})

      # Create children
      _child1 = page_fixture(project, %{name: "Child 1", parent_id: root1.id, position: 0})
      _child2 = page_fixture(project, %{name: "Child 2", parent_id: root1.id, position: 1})

      pages = Pages.list_pages_tree(project.id)

      assert length(pages) == 2
      assert Enum.at(pages, 0).name == "Root 1"
      assert Enum.at(pages, 1).name == "Root 2"
      assert length(Enum.at(pages, 0).children) == 2
      assert Enum.at(pages, 1).children == []
    end

    test "get_page_with_ancestors/2 returns page with ancestor chain" do
      user = user_fixture()
      project = project_fixture(user)

      root = page_fixture(project, %{name: "Root"})
      child = page_fixture(project, %{name: "Child", parent_id: root.id})
      grandchild = page_fixture(project, %{name: "Grandchild", parent_id: child.id})

      ancestors = Pages.get_page_with_ancestors(project.id, grandchild.id)

      assert length(ancestors) == 3
      assert Enum.at(ancestors, 0).name == "Root"
      assert Enum.at(ancestors, 1).name == "Child"
      assert Enum.at(ancestors, 2).name == "Grandchild"
    end

    test "move_page/3 moves page to new parent" do
      user = user_fixture()
      project = project_fixture(user)

      root1 = page_fixture(project, %{name: "Root 1"})
      root2 = page_fixture(project, %{name: "Root 2"})
      child = page_fixture(project, %{name: "Child", parent_id: root1.id})

      # Move child to root2
      {:ok, moved_page} = Pages.move_page(child, root2.id)

      assert moved_page.parent_id == root2.id
    end

    test "move_page/3 prevents cycle creation" do
      user = user_fixture()
      project = project_fixture(user)

      root = page_fixture(project, %{name: "Root"})
      child = page_fixture(project, %{name: "Child", parent_id: root.id})
      grandchild = page_fixture(project, %{name: "Grandchild", parent_id: child.id})

      # Try to move root under grandchild (would create cycle)
      assert {:error, :would_create_cycle} = Pages.move_page(root, grandchild.id)
    end

    test "move_page/3 allows moving page to root level" do
      user = user_fixture()
      project = project_fixture(user)

      root = page_fixture(project, %{name: "Root"})
      child = page_fixture(project, %{name: "Child", parent_id: root.id})

      # Move child to root level
      {:ok, moved_page} = Pages.move_page(child, nil)

      assert moved_page.parent_id == nil
    end
  end

  describe "move_page_to_position/3" do
    test "moves page to specific position within same parent" do
      user = user_fixture()
      project = project_fixture(user)

      page1 = page_fixture(project, %{name: "Page 1", position: 0})
      page2 = page_fixture(project, %{name: "Page 2", position: 1})
      page3 = page_fixture(project, %{name: "Page 3", position: 2})

      # Move page3 to position 0
      {:ok, _moved_page} = Pages.move_page_to_position(page3, nil, 0)

      # Verify new order
      pages = Pages.list_pages_tree(project.id)
      assert Enum.at(pages, 0).id == page3.id
      assert Enum.at(pages, 1).id == page1.id
      assert Enum.at(pages, 2).id == page2.id
    end

    test "moves page to different parent at specific position" do
      user = user_fixture()
      project = project_fixture(user)

      parent1 = page_fixture(project, %{name: "Parent 1"})
      parent2 = page_fixture(project, %{name: "Parent 2"})
      child1 = page_fixture(project, %{name: "Child 1", parent_id: parent1.id, position: 0})
      child2 = page_fixture(project, %{name: "Child 2", parent_id: parent2.id, position: 0})

      # Move child1 to parent2 at position 0
      {:ok, moved_page} = Pages.move_page_to_position(child1, parent2.id, 0)

      assert moved_page.parent_id == parent2.id

      # Verify child1 is now first child of parent2
      parent2_with_children = Pages.get_page_with_descendants(project.id, parent2.id)
      assert length(parent2_with_children.children) == 2
      assert Enum.at(parent2_with_children.children, 0).id == child1.id
      assert Enum.at(parent2_with_children.children, 1).id == child2.id

      # Verify parent1 has no children
      parent1_with_children = Pages.get_page_with_descendants(project.id, parent1.id)
      assert parent1_with_children.children == []
    end

    test "prevents cycle when moving" do
      user = user_fixture()
      project = project_fixture(user)

      parent = page_fixture(project, %{name: "Parent"})
      child = page_fixture(project, %{name: "Child", parent_id: parent.id})

      # Try to move parent under its child
      assert {:error, :would_create_cycle} = Pages.move_page_to_position(parent, child.id, 0)
    end
  end

  describe "reorder_pages/3" do
    test "reorders pages within same parent" do
      user = user_fixture()
      project = project_fixture(user)

      page1 = page_fixture(project, %{name: "Page 1", position: 0})
      page2 = page_fixture(project, %{name: "Page 2", position: 1})
      page3 = page_fixture(project, %{name: "Page 3", position: 2})

      # Reorder: [3, 1, 2]
      {:ok, pages} = Pages.reorder_pages(project.id, nil, [page3.id, page1.id, page2.id])

      assert length(pages) == 3
      assert Enum.at(pages, 0).id == page3.id
      assert Enum.at(pages, 1).id == page1.id
      assert Enum.at(pages, 2).id == page2.id
    end

    test "reorders child pages within parent" do
      user = user_fixture()
      project = project_fixture(user)

      parent = page_fixture(project, %{name: "Parent"})
      child1 = page_fixture(project, %{name: "Child 1", parent_id: parent.id, position: 0})
      child2 = page_fixture(project, %{name: "Child 2", parent_id: parent.id, position: 1})
      child3 = page_fixture(project, %{name: "Child 3", parent_id: parent.id, position: 2})

      # Reorder: [2, 3, 1]
      {:ok, pages} = Pages.reorder_pages(project.id, parent.id, [child2.id, child3.id, child1.id])

      assert length(pages) == 3
      assert Enum.at(pages, 0).id == child2.id
      assert Enum.at(pages, 1).id == child3.id
      assert Enum.at(pages, 2).id == child1.id
    end
  end

  describe "blocks" do
    test "create_block/2 creates block with default config and value" do
      user = user_fixture()
      project = project_fixture(user)
      page = page_fixture(project)

      {:ok, block} = Pages.create_block(page, %{type: "text"})

      assert block.type == "text"
      assert block.page_id == page.id
      assert block.position == 0
    end

    test "reorder_blocks/2 reorders blocks within page" do
      user = user_fixture()
      project = project_fixture(user)
      page = page_fixture(project)

      block1 = block_fixture(page)
      block2 = block_fixture(page)
      block3 = block_fixture(page)

      {:ok, blocks} = Pages.reorder_blocks(page.id, [block3.id, block1.id, block2.id])

      assert Enum.at(blocks, 0).id == block3.id
      assert Enum.at(blocks, 1).id == block1.id
      assert Enum.at(blocks, 2).id == block2.id
    end
  end

  describe "get_block_in_project/2" do
    test "returns block when in correct project" do
      user = user_fixture()
      project = project_fixture(user)
      page = page_fixture(project)
      {:ok, block} = Pages.create_block(page, %{type: "text"})

      result = Pages.get_block_in_project(block.id, project.id)

      assert result.id == block.id
      assert result.type == "text"
    end

    test "returns nil when block is in different project" do
      user = user_fixture()
      project1 = project_fixture(user)
      project2 = project_fixture(user)
      page = page_fixture(project1)
      {:ok, block} = Pages.create_block(page, %{type: "text"})

      # Try to get block from project1 using project2's ID
      result = Pages.get_block_in_project(block.id, project2.id)

      assert result == nil
    end

    test "returns nil for deleted blocks" do
      user = user_fixture()
      project = project_fixture(user)
      page = page_fixture(project)
      {:ok, block} = Pages.create_block(page, %{type: "text"})

      # Soft delete the block
      {:ok, _} = Pages.delete_block(block)

      result = Pages.get_block_in_project(block.id, project.id)

      assert result == nil
    end

    test "returns nil for blocks on deleted pages" do
      user = user_fixture()
      project = project_fixture(user)
      page = page_fixture(project)
      {:ok, block} = Pages.create_block(page, %{type: "text"})

      # Soft delete the page
      {:ok, _} = Pages.delete_page(page)

      result = Pages.get_block_in_project(block.id, project.id)

      assert result == nil
    end

    test "returns nil for non-existent block" do
      user = user_fixture()
      project = project_fixture(user)

      result = Pages.get_block_in_project(-1, project.id)

      assert result == nil
    end
  end

  describe "get_block_in_project!/2" do
    test "returns block when in correct project" do
      user = user_fixture()
      project = project_fixture(user)
      page = page_fixture(project)
      {:ok, block} = Pages.create_block(page, %{type: "text"})

      result = Pages.get_block_in_project!(block.id, project.id)

      assert result.id == block.id
    end

    test "raises when block is in different project" do
      user = user_fixture()
      project1 = project_fixture(user)
      project2 = project_fixture(user)
      page = page_fixture(project1)
      {:ok, block} = Pages.create_block(page, %{type: "text"})

      assert_raise Ecto.NoResultsError, fn ->
        Pages.get_block_in_project!(block.id, project2.id)
      end
    end

    test "raises for deleted blocks" do
      user = user_fixture()
      project = project_fixture(user)
      page = page_fixture(project)
      {:ok, block} = Pages.create_block(page, %{type: "text"})

      {:ok, _} = Pages.delete_block(block)

      assert_raise Ecto.NoResultsError, fn ->
        Pages.get_block_in_project!(block.id, project.id)
      end
    end
  end

  describe "reference blocks" do
    test "create_block/2 creates reference block with default config" do
      user = user_fixture()
      project = project_fixture(user)
      page = page_fixture(project)

      {:ok, block} = Pages.create_block(page, %{type: "reference"})

      assert block.type == "reference"
      assert block.config["label"] == "Label"
      assert block.config["allowed_types"] == ["page", "flow"]
      assert block.value["target_type"] == nil
      assert block.value["target_id"] == nil
    end

    test "create_block/2 creates reference block with custom allowed_types" do
      user = user_fixture()
      project = project_fixture(user)
      page = page_fixture(project)

      {:ok, block} =
        Pages.create_block(page, %{
          type: "reference",
          config: %{"label" => "Location", "allowed_types" => ["page"]}
        })

      assert block.config["label"] == "Location"
      assert block.config["allowed_types"] == ["page"]
    end

    test "update_block_value/2 sets reference target" do
      user = user_fixture()
      project = project_fixture(user)
      page = page_fixture(project)
      target_page = page_fixture(project, %{name: "Target Page"})
      {:ok, block} = Pages.create_block(page, %{type: "reference"})

      {:ok, updated} =
        Pages.update_block_value(block, %{
          "target_type" => "page",
          "target_id" => target_page.id
        })

      assert updated.value["target_type"] == "page"
      assert updated.value["target_id"] == target_page.id
    end

    test "update_block_value/2 clears reference target" do
      user = user_fixture()
      project = project_fixture(user)
      page = page_fixture(project)
      target_page = page_fixture(project)

      {:ok, block} =
        Pages.create_block(page, %{
          type: "reference",
          value: %{"target_type" => "page", "target_id" => target_page.id}
        })

      {:ok, updated} =
        Pages.update_block_value(block, %{"target_type" => nil, "target_id" => nil})

      assert updated.value["target_type"] == nil
      assert updated.value["target_id"] == nil
    end
  end

  describe "search functions" do
    test "search_pages/2 finds pages by name" do
      user = user_fixture()
      project = project_fixture(user)
      _page1 = page_fixture(project, %{name: "Character Jaime"})
      _page2 = page_fixture(project, %{name: "Location Tavern"})

      results = Pages.PageCrud.search_pages(project.id, "Jaime")

      assert length(results) == 1
      assert Enum.at(results, 0).name == "Character Jaime"
    end

    test "search_pages/2 finds pages by shortcut" do
      user = user_fixture()
      project = project_fixture(user)
      {:ok, page1} = Pages.create_page(project, %{name: "Jaime", shortcut: "mc.jaime"})
      _page2 = page_fixture(project, %{name: "Tavern"})

      results = Pages.PageCrud.search_pages(project.id, "mc")

      assert length(results) == 1
      assert Enum.at(results, 0).id == page1.id
    end

    test "search_pages/2 returns recent pages when query is empty" do
      user = user_fixture()
      project = project_fixture(user)
      _page1 = page_fixture(project, %{name: "Page 1"})
      _page2 = page_fixture(project, %{name: "Page 2"})

      results = Pages.PageCrud.search_pages(project.id, "")

      assert length(results) == 2
    end

    test "search_referenceable/3 returns pages and flows" do
      user = user_fixture()
      project = project_fixture(user)
      page = page_fixture(project, %{name: "Test Page"})
      flow = flow_fixture(project, %{name: "Test Flow"})

      results = Pages.search_referenceable(project.id, "Test", ["page", "flow"])

      assert length(results) == 2
      assert Enum.any?(results, &(&1.type == "page" && &1.id == page.id))
      assert Enum.any?(results, &(&1.type == "flow" && &1.id == flow.id))
    end

    test "search_referenceable/3 filters by allowed_types" do
      user = user_fixture()
      project = project_fixture(user)
      _page = page_fixture(project, %{name: "Test Page"})
      _flow = flow_fixture(project, %{name: "Test Flow"})

      results = Pages.search_referenceable(project.id, "Test", ["page"])

      assert length(results) == 1
      assert Enum.at(results, 0).type == "page"
    end

    test "get_reference_target/3 returns page info" do
      user = user_fixture()
      project = project_fixture(user)
      {:ok, page} = Pages.create_page(project, %{name: "Target", shortcut: "target"})

      result = Pages.get_reference_target("page", page.id, project.id)

      assert result.type == "page"
      assert result.id == page.id
      assert result.name == "Target"
      assert result.shortcut == "target"
    end

    test "get_reference_target/3 returns flow info" do
      user = user_fixture()
      project = project_fixture(user)
      flow = flow_fixture(project, %{name: "Target Flow"})

      result = Pages.get_reference_target("flow", flow.id, project.id)

      assert result.type == "flow"
      assert result.id == flow.id
      assert result.name == "Target Flow"
    end

    test "get_reference_target/3 returns nil for non-existent target" do
      user = user_fixture()
      project = project_fixture(user)

      assert Pages.get_reference_target("page", -1, project.id) == nil
    end

    test "get_reference_target/3 returns nil for nil inputs" do
      user = user_fixture()
      project = project_fixture(user)

      assert Pages.get_reference_target(nil, 1, project.id) == nil
      assert Pages.get_reference_target("page", nil, project.id) == nil
    end
  end

  describe "reference tracking" do
    alias Storyarn.Pages.ReferenceTracker

    test "update_block_references/1 creates reference for reference block" do
      user = user_fixture()
      project = project_fixture(user)
      source_page = page_fixture(project, %{name: "Source Page"})
      target_page = page_fixture(project, %{name: "Target Page"})

      {:ok, block} =
        Pages.create_block(source_page, %{
          type: "reference",
          value: %{"target_type" => "page", "target_id" => target_page.id}
        })

      ReferenceTracker.update_block_references(block)

      backlinks = ReferenceTracker.get_backlinks("page", target_page.id)
      assert length(backlinks) == 1
      assert Enum.at(backlinks, 0).source_id == block.id
      assert Enum.at(backlinks, 0).target_id == target_page.id
    end

    test "update_block_references/1 creates reference for rich_text mention" do
      user = user_fixture()
      project = project_fixture(user)
      source_page = page_fixture(project, %{name: "Source Page"})
      target_page = page_fixture(project, %{name: "Target Page"})

      mention_html = """
      <p>See <span class="mention" data-type="page" data-id="#{target_page.id}" data-label="target">#target</span></p>
      """

      {:ok, block} =
        Pages.create_block(source_page, %{
          type: "rich_text",
          value: %{"content" => mention_html}
        })

      ReferenceTracker.update_block_references(block)

      backlinks = ReferenceTracker.get_backlinks("page", target_page.id)
      assert length(backlinks) == 1
    end

    test "update_block_references/1 replaces existing references" do
      user = user_fixture()
      project = project_fixture(user)
      source_page = page_fixture(project, %{name: "Source Page"})
      target1 = page_fixture(project, %{name: "Target 1"})
      target2 = page_fixture(project, %{name: "Target 2"})

      {:ok, block} =
        Pages.create_block(source_page, %{
          type: "reference",
          value: %{"target_type" => "page", "target_id" => target1.id}
        })

      ReferenceTracker.update_block_references(block)

      # Update to point to target2
      {:ok, updated_block} =
        Pages.update_block_value(block, %{"target_type" => "page", "target_id" => target2.id})

      ReferenceTracker.update_block_references(updated_block)

      # Old reference should be removed
      assert ReferenceTracker.get_backlinks("page", target1.id) == []
      # New reference should exist
      assert length(ReferenceTracker.get_backlinks("page", target2.id)) == 1
    end

    test "delete_block_references/1 removes all references from block" do
      user = user_fixture()
      project = project_fixture(user)
      source_page = page_fixture(project, %{name: "Source Page"})
      target_page = page_fixture(project, %{name: "Target Page"})

      {:ok, block} =
        Pages.create_block(source_page, %{
          type: "reference",
          value: %{"target_type" => "page", "target_id" => target_page.id}
        })

      ReferenceTracker.update_block_references(block)
      assert length(ReferenceTracker.get_backlinks("page", target_page.id)) == 1

      ReferenceTracker.delete_block_references(block.id)
      assert ReferenceTracker.get_backlinks("page", target_page.id) == []
    end

    test "count_backlinks/2 returns correct count" do
      user = user_fixture()
      project = project_fixture(user)
      source_page1 = page_fixture(project, %{name: "Source 1"})
      source_page2 = page_fixture(project, %{name: "Source 2"})
      target_page = page_fixture(project, %{name: "Target Page"})

      {:ok, block1} =
        Pages.create_block(source_page1, %{
          type: "reference",
          value: %{"target_type" => "page", "target_id" => target_page.id}
        })

      {:ok, block2} =
        Pages.create_block(source_page2, %{
          type: "reference",
          value: %{"target_type" => "page", "target_id" => target_page.id}
        })

      ReferenceTracker.update_block_references(block1)
      ReferenceTracker.update_block_references(block2)

      assert Pages.count_backlinks("page", target_page.id) == 2
    end

    test "get_backlinks_with_sources/3 returns source info" do
      user = user_fixture()
      project = project_fixture(user)
      source_page = page_fixture(project, %{name: "Source Page"})
      target_page = page_fixture(project, %{name: "Target Page"})

      {:ok, block} =
        Pages.create_block(source_page, %{
          type: "reference",
          config: %{"label" => "Location Reference"},
          value: %{"target_type" => "page", "target_id" => target_page.id}
        })

      ReferenceTracker.update_block_references(block)

      backlinks = Pages.get_backlinks_with_sources("page", target_page.id, project.id)

      assert length(backlinks) == 1
      backlink = Enum.at(backlinks, 0)
      assert backlink.source_type == "block"
      assert backlink.source_info.page_name == "Source Page"
      assert backlink.source_info.block_label == "Location Reference"
      assert backlink.source_info.block_type == "reference"
    end
  end

  describe "boolean blocks" do
    test "create_block/2 creates boolean block with two_state default config" do
      user = user_fixture()
      project = project_fixture(user)
      page = page_fixture(project)

      {:ok, block} = Pages.create_block(page, %{type: "boolean"})

      assert block.type == "boolean"
      assert block.config["mode"] == "two_state"
      assert block.config["label"] == "Label"
      assert block.value["content"] == false
    end

    test "create_block/2 creates boolean block with custom config" do
      user = user_fixture()
      project = project_fixture(user)
      page = page_fixture(project)

      {:ok, block} =
        Pages.create_block(page, %{
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
      page = page_fixture(project)
      {:ok, block} = Pages.create_block(page, %{type: "boolean"})

      {:ok, updated} = Pages.update_block_value(block, %{"content" => true})

      assert updated.value["content"] == true
    end

    test "update_block_value/2 updates boolean block value to false" do
      user = user_fixture()
      project = project_fixture(user)
      page = page_fixture(project)

      {:ok, block} =
        Pages.create_block(page, %{
          type: "boolean",
          value: %{"content" => true}
        })

      {:ok, updated} = Pages.update_block_value(block, %{"content" => false})

      assert updated.value["content"] == false
    end

    test "update_block_value/2 updates boolean block value to nil (tri-state)" do
      user = user_fixture()
      project = project_fixture(user)
      page = page_fixture(project)

      {:ok, block} =
        Pages.create_block(page, %{
          type: "boolean",
          config: %{"label" => "Tri-state Field", "mode" => "tri_state"},
          value: %{"content" => true}
        })

      {:ok, updated} = Pages.update_block_value(block, %{"content" => nil})

      assert updated.value["content"] == nil
    end

    test "update_block_config/2 changes mode from two_state to tri_state" do
      user = user_fixture()
      project = project_fixture(user)
      page = page_fixture(project)
      {:ok, block} = Pages.create_block(page, %{type: "boolean"})

      {:ok, updated} =
        Pages.update_block_config(block, %{"label" => "Test", "mode" => "tri_state"})

      assert updated.config["mode"] == "tri_state"
      assert updated.config["label"] == "Test"
    end
  end
end
