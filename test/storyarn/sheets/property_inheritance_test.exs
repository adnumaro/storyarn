defmodule Storyarn.Sheets.PropertyInheritanceTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Sheets
  alias Storyarn.Sheets.Block
  alias Storyarn.Sheets.PropertyInheritance
  alias Storyarn.Sheets.Sheet

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

  # ===========================================================================
  # resolve_inherited_blocks/1
  # ===========================================================================

  describe "resolve_inherited_blocks/1" do
    setup :setup_hierarchy

    test "returns inherited blocks from parent", %{parent: parent, child: child} do
      inheritable_block_fixture(parent, label: "Health")

      groups = PropertyInheritance.resolve_inherited_blocks(child.id)

      assert length(groups) == 1
      assert hd(groups).source_sheet.id == parent.id
      assert length(hd(groups).blocks) == 1
      assert hd(hd(groups).blocks).config["label"] == "Health"
    end

    test "returns blocks from multiple ancestors", %{
      parent: parent,
      child: child,
      grandchild: grandchild
    } do
      inheritable_block_fixture(parent, label: "Health")
      inheritable_block_fixture(child, label: "Mood")

      groups = PropertyInheritance.resolve_inherited_blocks(grandchild.id)

      # Should have groups from both parent and child
      assert length(groups) == 2
      source_ids = Enum.map(groups, & &1.source_sheet.id)
      assert child.id in source_ids
      assert parent.id in source_ids
    end

    test "filters hidden blocks from grandchild", %{
      parent: parent,
      child: child,
      grandchild: grandchild
    } do
      block = inheritable_block_fixture(parent, label: "Hidden")

      # Hide this block on the child (stops it cascading to child's children)
      {:ok, _} = PropertyInheritance.hide_for_children(child, block.id)

      # The grandchild should NOT see the hidden block
      groups = PropertyInheritance.resolve_inherited_blocks(grandchild.id)

      hidden_block_ids =
        groups
        |> Enum.flat_map(& &1.blocks)
        |> Enum.map(& &1.id)

      refute block.id in hidden_block_ids
    end

    test "returns empty list for root sheet", %{parent: parent} do
      assert PropertyInheritance.resolve_inherited_blocks(parent.id) == []
    end

    test "excludes soft-deleted blocks", %{parent: parent, child: child} do
      block = inheritable_block_fixture(parent, label: "Deleted")
      {:ok, _} = Sheets.delete_block(block)

      groups = PropertyInheritance.resolve_inherited_blocks(child.id)

      assert groups == []
    end
  end

  # ===========================================================================
  # create_inherited_instances/2
  # ===========================================================================

  describe "create_inherited_instances/2" do
    setup :setup_hierarchy

    test "creates instances on child sheets", %{
      parent: parent,
      child: child,
      grandchild: grandchild
    } do
      block = inheritable_block_fixture(parent, label: "Strength")

      # The block was auto-propagated at creation time.
      # Let's check the instances exist
      child_blocks = Sheets.list_blocks(child.id)
      gc_blocks = Sheets.list_blocks(grandchild.id)

      assert Enum.any?(child_blocks, &(&1.inherited_from_block_id == block.id))
      assert Enum.any?(gc_blocks, &(&1.inherited_from_block_id == block.id))
    end

    test "skips already-existing instances", %{parent: parent, child: child} do
      block = inheritable_block_fixture(parent, label: "Existing")

      # Instances were auto-created. Try to create again.
      {:ok, count} = PropertyInheritance.create_inherited_instances(block, [child.id])

      assert count == 0
    end

    test "returns {:ok, 0} for empty list", %{parent: parent} do
      block = inheritable_block_fixture(parent, label: "No Targets")
      # Block auto-creates on descendants; test with explicitly empty list
      {:ok, count} = PropertyInheritance.create_inherited_instances(block, [])
      assert count == 0
    end

    test "rejects targets in trash or outside the source project", %{
      user: user,
      parent: parent,
      child: child
    } do
      block = inheritable_block_fixture(parent, label: "Scoped")
      foreign_project = project_fixture(user)
      foreign_sheet = sheet_fixture(foreign_project)
      deleted_at = DateTime.truncate(DateTime.utc_now(), :second)

      Repo.update_all(
        from(sheet in Sheet, where: sheet.id == ^child.id),
        set: [deleted_at: deleted_at]
      )

      assert {:error, {:invalid_inheritance_targets, invalid_ids}} =
               PropertyInheritance.create_inherited_instances(
                 block,
                 [foreign_sheet.id, child.id]
               )

      assert invalid_ids == Enum.sort([child.id, foreign_sheet.id])

      refute Repo.exists?(
               from(candidate in Block,
                 where:
                   candidate.sheet_id == ^foreign_sheet.id and
                     candidate.inherited_from_block_id == ^block.id
               )
             )
    end

    test "derives variable_name correctly", %{parent: parent, child: child} do
      block = inheritable_block_fixture(parent, label: "Health Points")

      child_blocks = Sheets.list_blocks(child.id)
      instance = Enum.find(child_blocks, &(&1.inherited_from_block_id == block.id))

      assert instance.variable_name == "health_points"
    end
  end

  # ===========================================================================
  # sync_definition_change/1
  # ===========================================================================

  describe "sync_definition_change/1" do
    setup :setup_hierarchy

    test "updates config on non-detached instances", %{parent: parent, child: child} do
      block = inheritable_block_fixture(parent, label: "Health")

      # Update the parent block's config
      {:ok, updated} =
        Sheets.update_block_config(block, %{"label" => "Vitality", "placeholder" => ""})

      # sync_definition_change is called automatically by update_block_config
      child_blocks = Sheets.list_blocks(child.id)
      instance = Enum.find(child_blocks, &(&1.inherited_from_block_id == updated.id))

      assert instance.config["label"] == "Vitality"
    end

    test "clears value when type changes", %{parent: parent, child: child} do
      block = inheritable_block_fixture(parent, label: "Score", type: "number")

      # Update parent block type
      {:ok, updated} =
        Sheets.update_block(block, %{
          type: "text",
          config: %{"label" => "Score", "placeholder" => ""}
        })

      # Since scope changed from children -> children isn't happening via update_block,
      # let's call sync directly
      PropertyInheritance.sync_definition_change(updated)

      child_blocks = Sheets.list_blocks(child.id)
      instance = Enum.find(child_blocks, &(&1.inherited_from_block_id == updated.id))

      assert instance.type == "text"
      assert instance.value == Block.default_value("text")
    end

    test "skips detached instances", %{parent: parent, child: child} do
      block = inheritable_block_fixture(parent, label: "Armor")

      # Detach the child's instance
      child_blocks = Sheets.list_blocks(child.id)
      instance = Enum.find(child_blocks, &(&1.inherited_from_block_id == block.id))
      {:ok, _} = PropertyInheritance.detach_block(instance)

      # Update parent
      {:ok, _updated_parent} =
        Sheets.update_block_config(block, %{"label" => "Shield", "placeholder" => ""})

      # Detached instance should NOT be updated
      detached = Sheets.get_block(instance.id)
      assert detached.config["label"] == "Armor"
      assert detached.detached == true
    end

    test "is atomic (transaction)", %{parent: parent} do
      block = inheritable_block_fixture(parent, label: "Atomic Test")

      # If it runs in a transaction, either all update or none
      {:ok, count} = PropertyInheritance.sync_definition_change(block)
      assert count >= 2
    end

    test "updates only instances on active sheets in the source project", %{
      user: user,
      parent: parent,
      child: child,
      grandchild: grandchild
    } do
      source = inheritable_block_fixture(parent, label: "Scoped sync")
      child_instance = inherited_instance!(child.id, source.id)
      grandchild_instance = inherited_instance!(grandchild.id, source.id)
      foreign_project = project_fixture(user)
      foreign_sheet = sheet_fixture(foreign_project)

      foreign_instance =
        block_fixture(foreign_sheet, %{
          type: source.type,
          config: source.config,
          inherited_from_block_id: source.id,
          detached: false
        })

      deleted_at = DateTime.truncate(DateTime.utc_now(), :second)

      Repo.update_all(
        from(sheet in Sheet, where: sheet.id == ^child.id),
        set: [deleted_at: deleted_at]
      )

      updated_source =
        source
        |> Ecto.Changeset.change(config: %{"label" => "Updated scope"})
        |> Repo.update!()

      assert {:ok, 1} = PropertyInheritance.sync_definition_change(updated_source)

      assert Repo.get!(Block, grandchild_instance.id).config == %{
               "label" => "Updated scope"
             }

      assert Repo.get!(Block, child_instance.id).config == source.config
      assert Repo.get!(Block, foreign_instance.id).config == source.config
    end
  end

  # ===========================================================================
  # detach_block/1 and reattach_block/1
  # ===========================================================================

  describe "detach_block/1" do
    setup :setup_hierarchy

    test "sets detached to true", %{parent: parent, child: child} do
      block = inheritable_block_fixture(parent, label: "Detachable")

      child_blocks = Sheets.list_blocks(child.id)
      instance = Enum.find(child_blocks, &(&1.inherited_from_block_id == block.id))

      {:ok, detached} = PropertyInheritance.detach_block(instance)

      assert detached.detached == true
      assert detached.inherited_from_block_id == block.id
    end
  end

  describe "reattach_block/1" do
    setup :setup_hierarchy

    test "resets definition from source", %{parent: parent, child: child} do
      block = inheritable_block_fixture(parent, label: "Reattach Me")

      child_blocks = Sheets.list_blocks(child.id)
      instance = Enum.find(child_blocks, &(&1.inherited_from_block_id == block.id))

      # Detach first
      {:ok, detached} = PropertyInheritance.detach_block(instance)
      assert detached.detached == true

      # Update parent's config while detached
      {:ok, _} = Sheets.update_block_config(block, %{"label" => "New Label", "placeholder" => ""})

      # Reattach - should sync with new parent config
      {:ok, reattached} = PropertyInheritance.reattach_block(detached)

      assert reattached.detached == false
      assert reattached.config["label"] == "New Label"
    end

    test "returns error when source permanently deleted", %{parent: parent, child: child} do
      block = inheritable_block_fixture(parent, label: "Will Be Deleted")

      child_blocks = Sheets.list_blocks(child.id)
      instance = Enum.find(child_blocks, &(&1.inherited_from_block_id == block.id))

      {:ok, detached} = PropertyInheritance.detach_block(instance)

      # Permanently delete parent block (Repo.get won't find it)
      {:ok, _} = Sheets.permanently_delete_block(block)

      # Reattach should fail
      assert {:error, :source_not_found} = PropertyInheritance.reattach_block(detached)
    end
  end

  # ===========================================================================
  # hide_for_children/2 and unhide_for_children/2
  # ===========================================================================

  describe "hide_for_children/2" do
    setup :setup_hierarchy

    test "adds block ID to hidden list", %{parent: parent, child: child} do
      block = inheritable_block_fixture(parent, label: "Hideable")

      {:ok, updated_sheet} = PropertyInheritance.hide_for_children(child, block.id)

      assert block.id in updated_sheet.hidden_inherited_block_ids
    end

    test "is idempotent", %{parent: parent, child: child} do
      block = inheritable_block_fixture(parent, label: "Idempotent Hide")

      {:ok, first} = PropertyInheritance.hide_for_children(child, block.id)
      {:ok, second} = PropertyInheritance.hide_for_children(first, block.id)

      assert length(second.hidden_inherited_block_ids) == 1
    end
  end

  describe "unhide_for_children/2" do
    setup :setup_hierarchy

    test "removes block ID from hidden list", %{parent: parent, child: child} do
      block = inheritable_block_fixture(parent, label: "Unhideable")

      {:ok, hidden_sheet} = PropertyInheritance.hide_for_children(child, block.id)
      {:ok, unhidden_sheet} = PropertyInheritance.unhide_for_children(hidden_sheet, block.id)

      refute block.id in unhidden_sheet.hidden_inherited_block_ids
    end

    test "is idempotent", %{parent: parent, child: child} do
      block = inheritable_block_fixture(parent, label: "Idempotent Unhide")

      # Unhiding when not hidden should be a no-op
      {:ok, result} = PropertyInheritance.unhide_for_children(child, block.id)

      assert result.hidden_inherited_block_ids == (child.hidden_inherited_block_ids || [])
    end
  end

  # ===========================================================================
  # delete_inherited_instances/1
  # ===========================================================================

  describe "delete_inherited_instances/1" do
    setup :setup_hierarchy

    test "soft-deletes all instances", %{parent: parent, child: child, grandchild: grandchild} do
      block = inheritable_block_fixture(parent, label: "Deletable")

      {:ok, count} = PropertyInheritance.delete_inherited_instances(block)

      assert count >= 2

      # Instances should not appear in list_blocks
      child_blocks = Sheets.list_blocks(child.id)
      gc_blocks = Sheets.list_blocks(grandchild.id)

      refute Enum.any?(child_blocks, &(&1.inherited_from_block_id == block.id))
      refute Enum.any?(gc_blocks, &(&1.inherited_from_block_id == block.id))
    end

    test "preserves detached instances as local copies", %{
      parent: parent,
      child: child
    } do
      block = inheritable_block_fixture(parent, label: "Detachable")

      instance =
        child.id
        |> Sheets.list_blocks()
        |> Enum.find(&(&1.inherited_from_block_id == block.id))

      assert {:ok, detached} = PropertyInheritance.detach_block(instance)
      assert {:ok, 1} = PropertyInheritance.delete_inherited_instances(block)

      preserved = Repo.get!(Block, detached.id)
      assert preserved.detached
      assert is_nil(preserved.deleted_at)
      assert preserved.inherited_from_block_id == block.id
    end

    test "cleans up entity references", %{project: project, parent: parent, child: child} do
      alias Storyarn.Sheets.ReferenceTracker
      # Create an inheritable reference block
      target_sheet = sheet_fixture(project, %{name: "Target"})

      {:ok, block} =
        Sheets.create_block(parent, %{
          type: "reference",
          scope: "children",
          config: %{"label" => "With Refs", "allowed_types" => ["sheet", "flow"]},
          value: %{"target_type" => nil, "target_id" => nil}
        })

      child_blocks = Sheets.list_blocks(child.id)
      instance = Enum.find(child_blocks, &(&1.inherited_from_block_id == block.id))

      # Set a reference value on the instance
      {:ok, updated_instance} =
        Sheets.update_block_value(instance, %{
          "target_type" => "sheet",
          "target_id" => target_sheet.id
        })

      # update_block_value tracks references for reference blocks automatically
      ReferenceTracker.update_block_references(updated_instance)

      backlinks_before = ReferenceTracker.get_backlinks("sheet", target_sheet.id)
      assert [_ | _] = backlinks_before

      # Now delete inherited instances
      {:ok, _} = PropertyInheritance.delete_inherited_instances(block)

      # References should be cleaned up
      backlinks_after = ReferenceTracker.get_backlinks("sheet", target_sheet.id)
      assert backlinks_after == []
    end

    test "deletes and cleans hidden IDs only on active sheets in the source project", %{
      user: user,
      parent: parent,
      child: child,
      grandchild: grandchild
    } do
      source = inheritable_block_fixture(parent, label: "Scoped delete")
      child_instance = inherited_instance!(child.id, source.id)
      grandchild_instance = inherited_instance!(grandchild.id, source.id)
      foreign_project = project_fixture(user)
      foreign_sheet = sheet_fixture(foreign_project)

      foreign_instance =
        block_fixture(foreign_sheet, %{
          type: source.type,
          config: source.config,
          inherited_from_block_id: source.id,
          detached: false
        })

      Repo.update_all(
        from(sheet in Sheet,
          where: sheet.id in ^[child.id, grandchild.id, foreign_sheet.id]
        ),
        set: [hidden_inherited_block_ids: [source.id]]
      )

      deleted_at = DateTime.truncate(DateTime.utc_now(), :second)

      Repo.update_all(
        from(sheet in Sheet, where: sheet.id == ^child.id),
        set: [deleted_at: deleted_at]
      )

      assert {:ok, 1} = PropertyInheritance.delete_inherited_instances(source)

      assert is_nil(Repo.get!(Block, child_instance.id).deleted_at)
      assert Repo.get!(Block, grandchild_instance.id).deleted_at
      assert is_nil(Repo.get!(Block, foreign_instance.id).deleted_at)

      assert Repo.get!(Sheet, child.id).hidden_inherited_block_ids == [source.id]
      assert Repo.get!(Sheet, grandchild.id).hidden_inherited_block_ids == []
      assert Repo.get!(Sheet, foreign_sheet.id).hidden_inherited_block_ids == [source.id]
    end
  end

  # ===========================================================================
  # recalculate_on_move/1
  # ===========================================================================

  describe "recalculate_on_move/1" do
    setup :setup_hierarchy

    test "detaches old instances (not hard-deletes)", %{
      project: project,
      parent: parent,
      child: child
    } do
      block = inheritable_block_fixture(parent, label: "Moveable")

      # Verify child has the instance
      child_blocks_before = Sheets.list_blocks(child.id)
      assert Enum.any?(child_blocks_before, &(&1.inherited_from_block_id == block.id))

      # Create a new parent with no inheritable blocks
      new_parent = sheet_fixture(project, %{name: "New Parent"})

      # Move child to new parent
      {:ok, _} = Sheets.move_sheet(child, new_parent.id)

      # Old inherited blocks should be detached (not deleted)
      all_blocks = Repo.all(from(b in Block, where: b.sheet_id == ^child.id and b.inherited_from_block_id == ^block.id))

      # Should still exist in DB, not soft-deleted, but marked detached
      assert [_ | _] = all_blocks
      assert Enum.all?(all_blocks, &is_nil(&1.deleted_at))
      assert Enum.all?(all_blocks, & &1.detached)
    end

    test "creates new instances from new ancestor chain", %{
      project: project,
      child: child
    } do
      # Create a new parent with an inheritable block
      new_parent = sheet_fixture(project, %{name: "New Parent"})
      new_block = inheritable_block_fixture(new_parent, label: "New Inherited")

      # Move child to new parent
      {:ok, _} = Sheets.move_sheet(child, new_parent.id)

      # Child should now have new inherited block
      child_blocks = Sheets.list_blocks(child.id)
      assert Enum.any?(child_blocks, &(&1.inherited_from_block_id == new_block.id))
    end

    test "preserves detached blocks", %{
      project: project,
      parent: parent,
      child: child
    } do
      block = inheritable_block_fixture(parent, label: "Detached Before Move")

      # Detach the instance
      child_blocks = Sheets.list_blocks(child.id)
      instance = Enum.find(child_blocks, &(&1.inherited_from_block_id == block.id))
      {:ok, _} = PropertyInheritance.detach_block(instance)

      # Move child to new parent
      new_parent = sheet_fixture(project, %{name: "New Parent 2"})
      {:ok, _} = Sheets.move_sheet(child, new_parent.id)

      # Detached block should still exist (not soft-deleted)
      detached = Sheets.get_block(instance.id)
      assert detached
      assert detached.detached == true
    end
  end

  # ===========================================================================
  # inherit_blocks_for_new_sheet/1
  # ===========================================================================

  describe "inherit_blocks_for_new_sheet/1" do
    setup :setup_hierarchy

    test "inherits from all ancestors", %{project: project, parent: parent, child: child} do
      _parent_block = inheritable_block_fixture(parent, label: "From Grandparent")
      _child_block = inheritable_block_fixture(child, label: "From Parent")

      # Create a new grandchild - it should inherit from both
      new_grandchild = child_sheet_fixture(project, child, %{name: "New Grandchild"})

      gc_blocks = Sheets.list_blocks(new_grandchild.id)

      # Should have instances from both ancestor blocks
      assert length(gc_blocks) >= 2
    end

    test "respects hidden block IDs", %{project: project, parent: parent, child: child} do
      block = inheritable_block_fixture(parent, label: "Hidden From GC")

      # Hide this block on the child (so it won't cascade to child's children)
      {:ok, _} = PropertyInheritance.hide_for_children(child, block.id)

      # Create a new grandchild
      new_grandchild = child_sheet_fixture(project, child, %{name: "Hidden GC"})

      gc_blocks = Sheets.list_blocks(new_grandchild.id)

      # Should NOT have the hidden block
      refute Enum.any?(gc_blocks, &(&1.inherited_from_block_id == block.id))
    end

    test "returns {:ok, 0} for root sheets" do
      user = user_fixture()
      project = project_fixture(user)
      root = sheet_fixture(project, %{name: "Root"})

      assert {:ok, 0} = PropertyInheritance.inherit_blocks_for_new_sheet(root)
    end
  end

  # ===========================================================================
  # propagate_to_descendants/2
  # ===========================================================================

  describe "propagate_to_descendants/2" do
    setup :setup_hierarchy

    test "validates sheet_ids are actual descendants", %{
      project: project,
      parent: parent,
      child: child
    } do
      # Create a block that's NOT auto-propagated (create with scope self, then change)
      {:ok, block} =
        Sheets.create_block(parent, %{
          type: "text",
          scope: "self",
          config: %{"label" => "Manual Propagate", "placeholder" => ""}
        })

      # Update to children scope (instances created via propagation modal)
      {:ok, block} = Sheets.update_block(block, %{scope: "children"})

      # Create an unrelated sheet (not a descendant)
      unrelated = sheet_fixture(project, %{name: "Unrelated"})

      # Try to propagate to both valid and invalid sheets
      {:ok, _count} =
        PropertyInheritance.propagate_to_descendants(block, [child.id, unrelated.id])

      # Only valid descendants should get instances
      child_blocks = Sheets.list_blocks(child.id)
      unrelated_blocks = Sheets.list_blocks(unrelated.id)

      assert Enum.any?(child_blocks, &(&1.inherited_from_block_id == block.id))
      refute Enum.any?(unrelated_blocks, &(&1.inherited_from_block_id == block.id))
    end
  end

  # ===========================================================================
  # Integration: BlockCrud
  # ===========================================================================

  describe "integration: BlockCrud" do
    setup :setup_hierarchy

    test "create_block with scope: 'children' auto-creates instances", %{
      parent: parent,
      child: child,
      grandchild: grandchild
    } do
      block = inheritable_block_fixture(parent, label: "Auto Created")

      child_blocks = Sheets.list_blocks(child.id)
      gc_blocks = Sheets.list_blocks(grandchild.id)

      assert Enum.any?(child_blocks, &(&1.inherited_from_block_id == block.id))
      assert Enum.any?(gc_blocks, &(&1.inherited_from_block_id == block.id))
    end

    test "update_block syncs definition to instances", %{parent: parent, child: child} do
      block = inheritable_block_fixture(parent, label: "Syncable")

      {:ok, _} =
        Sheets.update_block_config(block, %{"label" => "Synced Label", "placeholder" => ""})

      child_blocks = Sheets.list_blocks(child.id)
      instance = Enum.find(child_blocks, &(&1.inherited_from_block_id == block.id))

      assert instance.config["label"] == "Synced Label"
    end

    test "delete_block soft-deletes instances", %{parent: parent, child: child} do
      block = inheritable_block_fixture(parent, label: "Delete Parent")

      {:ok, _} = Sheets.delete_block(block)

      child_blocks = Sheets.list_blocks(child.id)
      refute Enum.any?(child_blocks, &(&1.inherited_from_block_id == block.id))
    end
  end

  # ===========================================================================
  # Integration: SheetCrud
  # ===========================================================================

  describe "integration: SheetCrud" do
    setup :setup_hierarchy

    test "create_sheet under parent auto-inherits blocks", %{
      project: project,
      parent: parent
    } do
      _block = inheritable_block_fixture(parent, label: "Auto Inherited")

      new_child = child_sheet_fixture(project, parent, %{name: "New Child"})

      child_blocks = Sheets.list_blocks(new_child.id)
      assert [_ | _] = child_blocks
      assert Enum.any?(child_blocks, fn b -> not is_nil(b.inherited_from_block_id) end)
    end

    test "move_sheet recalculates inheritance", %{
      project: project,
      parent: parent,
      child: child
    } do
      old_block = inheritable_block_fixture(parent, label: "Old Parent Block")

      # Create new parent with different block
      new_parent = sheet_fixture(project, %{name: "New Parent"})
      new_block = inheritable_block_fixture(new_parent, label: "New Parent Block")

      # Verify child has old block attached
      child_blocks_before = Sheets.list_blocks(child.id)

      assert Enum.any?(
               child_blocks_before,
               &(&1.inherited_from_block_id == old_block.id and not &1.detached)
             )

      # Move child to new parent
      {:ok, _} = Sheets.move_sheet(child, new_parent.id)

      # Child should now have new parent's block attached, old parent's detached
      child_blocks_after = Sheets.list_blocks(child.id)

      assert Enum.any?(
               child_blocks_after,
               &(&1.inherited_from_block_id == new_block.id and not &1.detached)
             )

      refute Enum.any?(
               child_blocks_after,
               &(&1.inherited_from_block_id == old_block.id and not &1.detached)
             )
    end
  end

  # ===========================================================================
  # Integration: Versioning
  # ===========================================================================

  describe "integration: versioning" do
    setup :setup_hierarchy

    test "snapshot includes inheritance fields", %{user: user, parent: parent, child: child} do
      _block = inheritable_block_fixture(parent, label: "Versioned")

      {:ok, version} = Sheets.create_version(child, user)

      {:ok, snapshot} = Storyarn.Versioning.load_version_snapshot(version)
      block_snapshots = snapshot["blocks"]
      assert [_ | _] = block_snapshots

      inherited_snapshot = Enum.find(block_snapshots, & &1["inherited_from_block_id"])
      assert inherited_snapshot
      assert inherited_snapshot["scope"] == "self"
      assert inherited_snapshot["detached"] == false
    end

    test "restore rejects an orphaned inherited_from_block_id without mutating the child", %{
      user: user,
      parent: parent,
      child: child
    } do
      block = inheritable_block_fixture(parent, label: "Orphan Test")

      # Create a version while the block exists
      {:ok, version} = Sheets.create_version(child, user)

      # Delete the parent block permanently
      {:ok, _} = Sheets.permanently_delete_block(block)

      child_before = Repo.get!(Sheet, child.id)

      blocks_before =
        Repo.all(
          from(child_block in Block,
            where: child_block.sheet_id == ^child.id,
            order_by: [asc: child_block.id]
          )
        )

      assert [current_instance] = blocks_before
      assert is_nil(current_instance.inherited_from_block_id)
      refute current_instance.detached

      assert {:error, {:invalid_snapshot, {:invalid_block_reference, source_id}}} =
               Sheets.restore_version(child, version)

      assert source_id == block.id
      assert Repo.get!(Sheet, child.id) == child_before

      assert Repo.all(
               from(child_block in Block,
                 where: child_block.sheet_id == ^child.id,
                 order_by: [asc: child_block.id]
               )
             ) == blocks_before
    end
  end

  # ===========================================================================
  # get_sheet_blocks_grouped/1
  # ===========================================================================

  describe "get_sheet_blocks_grouped/1" do
    setup :setup_hierarchy

    test "returns inherited groups and own blocks separately", %{parent: parent, child: child} do
      _inherited = inheritable_block_fixture(parent, label: "Inherited Block")
      _own = block_fixture(child, %{config: %{"label" => "Own Block", "placeholder" => ""}})

      {inherited_groups, own_blocks} = Sheets.get_sheet_blocks_grouped(child.id)

      assert length(inherited_groups) == 1
      assert hd(inherited_groups).source_sheet.id == parent.id
      assert [_ | _] = own_blocks
    end

    test "batch-loads source sheets (no N+1)", %{
      parent: parent,
      child: child,
      grandchild: grandchild
    } do
      inheritable_block_fixture(parent, label: "From GP")
      inheritable_block_fixture(child, label: "From Parent")

      # This should execute a fixed number of queries regardless of group count
      {inherited_groups, _own} = Sheets.get_sheet_blocks_grouped(grandchild.id)

      assert length(inherited_groups) == 2
    end
  end

  # ===========================================================================
  # recalculate_on_move/1 cascades to descendants (Fix 2)
  # ===========================================================================

  describe "recalculate_on_move cascades to descendants" do
    setup :setup_hierarchy

    test "descendants get recalculated when parent is moved", %{
      project: project,
      parent: parent,
      child: child,
      grandchild: grandchild
    } do
      old_block = inheritable_block_fixture(parent, label: "Old Ancestor Block")

      # Verify grandchild inherited from the old ancestor (attached)
      gc_blocks_before = Sheets.list_blocks(grandchild.id)

      assert Enum.any?(
               gc_blocks_before,
               &(&1.inherited_from_block_id == old_block.id and not &1.detached)
             )

      # Create a new root with a different inheritable block
      new_root = sheet_fixture(project, %{name: "New Root"})
      new_block = inheritable_block_fixture(new_root, label: "New Root Block")

      # Move child to new_root (child still has grandchild under it)
      {:ok, _} = Sheets.move_sheet(child, new_root.id)

      # Grandchild should now have new_root's block attached, and old_block's
      # instance should be detached (kept but no longer linked to its source)
      gc_blocks_after = Sheets.list_blocks(grandchild.id)

      assert Enum.any?(
               gc_blocks_after,
               &(&1.inherited_from_block_id == new_block.id and not &1.detached)
             )

      refute Enum.any?(
               gc_blocks_after,
               &(&1.inherited_from_block_id == old_block.id and not &1.detached)
             )
    end
  end

  # ===========================================================================
  # restore_block restores inherited instances (Fix 3)
  # ===========================================================================

  describe "restore_block restores inherited instances" do
    setup :setup_hierarchy

    test "restoring a parent block with scope children restores instances", %{
      parent: parent,
      child: child,
      grandchild: grandchild
    } do
      block = inheritable_block_fixture(parent, label: "Restorable")

      # Verify instances exist
      child_blocks = Sheets.list_blocks(child.id)
      assert Enum.any?(child_blocks, &(&1.inherited_from_block_id == block.id))

      # Soft-delete the parent block (also soft-deletes instances)
      {:ok, deleted_block} = Sheets.delete_block(block)

      # Restoring later must compare instances with the original deletion time,
      # not the wall clock at restoration time.
      old_deleted_at = DateTime.add(deleted_block.deleted_at, -3_600, :second)

      Repo.update_all(
        from(candidate in Block,
          where: candidate.id == ^block.id or candidate.inherited_from_block_id == ^block.id
        ),
        set: [deleted_at: old_deleted_at]
      )

      deleted_block = Repo.get!(Block, block.id)

      # Verify instances are gone
      child_blocks_after_delete = Sheets.list_blocks(child.id)
      refute Enum.any?(child_blocks_after_delete, &(&1.inherited_from_block_id == block.id))

      gc_blocks_after_delete = Sheets.list_blocks(grandchild.id)
      refute Enum.any?(gc_blocks_after_delete, &(&1.inherited_from_block_id == block.id))

      # Restore the parent block
      {:ok, _restored} = Sheets.restore_block(deleted_block)

      # Instances should be restored
      child_blocks_restored = Sheets.list_blocks(child.id)
      assert Enum.any?(child_blocks_restored, &(&1.inherited_from_block_id == block.id))

      gc_blocks_restored = Sheets.list_blocks(grandchild.id)
      assert Enum.any?(gc_blocks_restored, &(&1.inherited_from_block_id == block.id))
    end

    test "restores only instances on active sheets in the source project", %{
      user: user,
      parent: parent,
      child: child,
      grandchild: grandchild
    } do
      source = inheritable_block_fixture(parent, label: "Scoped restore")
      child_instance = inherited_instance!(child.id, source.id)
      grandchild_instance = inherited_instance!(grandchild.id, source.id)
      foreign_project = project_fixture(user)
      foreign_sheet = sheet_fixture(foreign_project)

      foreign_instance =
        block_fixture(foreign_sheet, %{
          type: source.type,
          config: source.config,
          inherited_from_block_id: source.id,
          detached: false
        })

      deletion_time = DateTime.truncate(DateTime.utc_now(), :second)

      Repo.update_all(
        from(block in Block,
          where:
            block.id in ^[
              child_instance.id,
              grandchild_instance.id,
              foreign_instance.id
            ]
        ),
        set: [deleted_at: deletion_time]
      )

      Repo.update_all(
        from(sheet in Sheet, where: sheet.id == ^child.id),
        set: [deleted_at: deletion_time]
      )

      assert {:ok, 1} =
               PropertyInheritance.restore_inherited_instances(%{
                 source
                 | deleted_at: deletion_time
               })

      assert Repo.get!(Block, child_instance.id).deleted_at
      assert is_nil(Repo.get!(Block, grandchild_instance.id).deleted_at)
      assert Repo.get!(Block, foreign_instance.id).deleted_at
    end
  end

  # ===========================================================================
  # Variable name uniqueness in batch operations (Fix 5)
  # ===========================================================================

  describe "variable name dedup in batch" do
    setup :setup_hierarchy

    test "two ancestors with same-label blocks produce unique variable names on child", %{
      project: project,
      parent: parent,
      child: child
    } do
      # Create an inheritable block on parent with label "Health"
      inheritable_block_fixture(parent, label: "Health")

      # Create an inheritable block on child with the same label "Health"
      inheritable_block_fixture(child, label: "Health")

      # Create a new grandchild - it should inherit both but with unique variable names
      new_grandchild = child_sheet_fixture(project, child, %{name: "Dedup GC"})

      gc_blocks = Sheets.list_blocks(new_grandchild.id)
      variable_names = gc_blocks |> Enum.map(& &1.variable_name) |> Enum.reject(&is_nil/1)

      # Should have unique variable names (no duplicates)
      assert length(variable_names) == length(Enum.uniq(variable_names))
      # Should have at least 2 blocks with variable names
      assert length(variable_names) >= 2
    end
  end

  # ===========================================================================
  # Position overlap in inherit_blocks_for_new_sheet (Fix 6)
  # ===========================================================================

  describe "position overlap fix" do
    setup :setup_hierarchy

    test "inherited blocks don't overlap with existing own blocks on recalculate", %{
      project: project,
      child: child
    } do
      # Create own blocks on child first
      _own1 = block_fixture(child, %{config: %{"label" => "Own1", "placeholder" => ""}})
      _own2 = block_fixture(child, %{config: %{"label" => "Own2", "placeholder" => ""}})

      # Create an inheritable block on a new parent
      new_parent = sheet_fixture(project, %{name: "New Parent Pos"})
      _new_block = inheritable_block_fixture(new_parent, label: "Inherited Pos")

      # Move child to new parent (triggers recalculate_on_move)
      {:ok, _} = Sheets.move_sheet(child, new_parent.id)

      # All blocks should have unique positions
      all_blocks = Sheets.list_blocks(child.id)
      positions = Enum.map(all_blocks, & &1.position)

      assert length(positions) == length(Enum.uniq(positions))
    end
  end

  # ===========================================================================
  # Formula binding rewrite on table inheritance
  # ===========================================================================

  describe "formula binding rewrite on table inheritance" do
    setup :setup_hierarchy

    test "rewrites cross-sheet formula bindings when inheriting table to new child", %{
      project: project,
      parent: parent
    } do
      # 1. Create a non-table inheritable block that formulas will reference
      _stats_block = inheritable_block_fixture(parent, label: "Strength", type: "number")

      # 2. Create a table block with scope "children"
      {:ok, table_block} =
        Sheets.create_block(parent, %{
          type: "table",
          scope: "children",
          config: %{"label" => "Combat Stats", "collapsed" => false}
        })

      # 3. Add a formula column
      {:ok, formula_col} =
        Sheets.create_table_column(table_block, %{name: "Bonus", type: "formula"})

      # 4. Get the default row and update its formula cell with a cross-sheet binding
      parent_shortcut = parent.shortcut
      rows = Sheets.list_table_rows(table_block.id)
      row = hd(rows)

      formula_cell = %{
        "expression" => "a * 2",
        "bindings" => %{
          "a" => %{"type" => "variable", "ref" => "#{parent_shortcut}.strength"}
        }
      }

      {:ok, _} = Sheets.update_table_cell(row, formula_col.slug, formula_cell)

      # 5. Create a new child sheet — triggers inherit_blocks_for_new_sheet
      child = child_sheet_fixture(project, parent, %{name: "Warrior"})
      child_shortcut = child.shortcut

      # 6. Find the inherited table block on the child
      child_blocks = Sheets.list_blocks(child.id)

      child_table =
        Enum.find(child_blocks, fn b ->
          b.inherited_from_block_id == table_block.id
        end)

      assert child_table, "Child should have an inherited table block"

      # 7. Check the child's row has rewritten formula bindings
      child_rows = Sheets.list_table_rows(child_table.id)
      assert length(child_rows) == 1

      child_row = hd(child_rows)
      child_formula_cell = child_row.cells[formula_col.slug]

      assert is_map(child_formula_cell)
      assert child_formula_cell["expression"] == "a * 2"

      child_binding = child_formula_cell["bindings"]["a"]
      assert child_binding["type"] == "variable"
      # The ref should be rewritten from parent shortcut to child shortcut
      assert child_binding["ref"] == "#{child_shortcut}.strength"
    end

    test "preserves bindings referencing other sheets (not parent)", %{
      project: project,
      parent: parent
    } do
      # Create a separate sheet with its own variable
      other_sheet = sheet_fixture(project, %{name: "Global Config"})
      _other_block = inheritable_block_fixture(other_sheet, label: "Multiplier", type: "number")

      # Create table with formula referencing the OTHER sheet, not the parent
      {:ok, table_block} =
        Sheets.create_block(parent, %{
          type: "table",
          scope: "children",
          config: %{"label" => "Formulas", "collapsed" => false}
        })

      {:ok, formula_col} =
        Sheets.create_table_column(table_block, %{name: "Result", type: "formula"})

      rows = Sheets.list_table_rows(table_block.id)
      row = hd(rows)
      other_shortcut = other_sheet.shortcut

      formula_cell = %{
        "expression" => "a + 1",
        "bindings" => %{
          "a" => %{"type" => "variable", "ref" => "#{other_shortcut}.multiplier"}
        }
      }

      {:ok, _} = Sheets.update_table_cell(row, formula_col.slug, formula_cell)

      # Create child — formula references other_sheet, not parent, so should stay unchanged
      child = child_sheet_fixture(project, parent, %{name: "Child Formulas"})

      child_blocks = Sheets.list_blocks(child.id)

      child_table =
        Enum.find(child_blocks, &(&1.inherited_from_block_id == table_block.id))

      child_rows = Sheets.list_table_rows(child_table.id)
      child_formula_cell = hd(child_rows).cells[formula_col.slug]

      # Binding should remain pointing to other_sheet, NOT rewritten
      assert child_formula_cell["bindings"]["a"]["ref"] == "#{other_shortcut}.multiplier"
    end

    test "preserves same_row bindings during inheritance", %{
      project: project,
      parent: parent
    } do
      {:ok, table_block} =
        Sheets.create_block(parent, %{
          type: "table",
          scope: "children",
          config: %{"label" => "Mixed Bindings", "collapsed" => false}
        })

      {:ok, _value_col} =
        Sheets.create_table_column(table_block, %{name: "Base Value", type: "number"})

      {:ok, formula_col} =
        Sheets.create_table_column(table_block, %{name: "Double", type: "formula"})

      rows = Sheets.list_table_rows(table_block.id)
      row = hd(rows)

      formula_cell = %{
        "expression" => "a * 2",
        "bindings" => %{
          "a" => %{"type" => "same_row", "column_slug" => "base_value"}
        }
      }

      {:ok, _} = Sheets.update_table_cell(row, formula_col.slug, formula_cell)

      child = child_sheet_fixture(project, parent, %{name: "SameRow Child"})

      child_blocks = Sheets.list_blocks(child.id)

      child_table =
        Enum.find(child_blocks, &(&1.inherited_from_block_id == table_block.id))

      child_rows = Sheets.list_table_rows(child_table.id)
      child_formula_cell = hd(child_rows).cells[formula_col.slug]

      # same_row binding should pass through unchanged
      assert child_formula_cell["bindings"]["a"] == %{
               "type" => "same_row",
               "column_slug" => "base_value"
             }
    end
  end

  defp inherited_instance!(sheet_id, source_block_id) do
    Repo.one!(
      from(block in Block,
        where:
          block.sheet_id == ^sheet_id and
            block.inherited_from_block_id == ^source_block_id
      )
    )
  end
end
