defmodule Storyarn.PagesTest do
  use Storyarn.DataCase

  alias Storyarn.Pages

  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
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

  describe "boolean blocks" do
    test "create_block/2 creates boolean block with two_state default config" do
      user = user_fixture()
      project = project_fixture(user)
      page = page_fixture(project)

      {:ok, block} = Pages.create_block(page, %{type: "boolean"})

      assert block.type == "boolean"
      assert block.config["mode"] == "two_state"
      assert block.config["label"] == ""
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
          config: %{"label" => "", "mode" => "tri_state"},
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
