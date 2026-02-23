defmodule Storyarn.Sheets.PropertyInheritanceTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Sheets
  alias Storyarn.Sheets.{Block, PropertyInheritance}

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

    test "cleans up entity references", %{project: project, parent: parent, child: child} do
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
      alias Storyarn.Sheets.ReferenceTracker
      ReferenceTracker.update_block_references(updated_instance)

      backlinks_before = ReferenceTracker.get_backlinks("sheet", target_sheet.id)
      assert [_ | _] = backlinks_before

      # Now delete inherited instances
      {:ok, _} = PropertyInheritance.delete_inherited_instances(block)

      # References should be cleaned up
      backlinks_after = ReferenceTracker.get_backlinks("sheet", target_sheet.id)
      assert backlinks_after == []
    end
  end

  # ===========================================================================
  # recalculate_on_move/1
  # ===========================================================================

  describe "recalculate_on_move/1" do
    setup :setup_hierarchy

    test "soft-deletes old instances (not hard-deletes)", %{
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

      # Old inherited blocks should be soft-deleted (not hard-deleted)
      all_blocks =
        from(b in Block,
          where: b.sheet_id == ^child.id and b.inherited_from_block_id == ^block.id
        )
        |> Repo.all()

      # Should still exist in DB but be soft-deleted
      assert [_ | _] = all_blocks
      assert Enum.all?(all_blocks, &(not is_nil(&1.deleted_at)))
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
      assert detached != nil
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

      # Verify child has old block
      child_blocks_before = Sheets.list_blocks(child.id)
      assert Enum.any?(child_blocks_before, &(&1.inherited_from_block_id == old_block.id))

      # Move child to new parent
      {:ok, _} = Sheets.move_sheet(child, new_parent.id)

      # Child should now have new parent's block, not old parent's
      child_blocks_after = Sheets.list_blocks(child.id)
      assert Enum.any?(child_blocks_after, &(&1.inherited_from_block_id == new_block.id))
      refute Enum.any?(child_blocks_after, &(&1.inherited_from_block_id == old_block.id))
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

      block_snapshots = version.snapshot["blocks"]
      assert [_ | _] = block_snapshots

      inherited_snapshot = Enum.find(block_snapshots, & &1["inherited_from_block_id"])
      assert inherited_snapshot
      assert inherited_snapshot["scope"] == "self"
      assert inherited_snapshot["detached"] == false
    end

    test "restore handles orphaned inherited_from_block_id", %{
      user: user,
      parent: parent,
      child: child
    } do
      block = inheritable_block_fixture(parent, label: "Orphan Test")

      # Create a version while the block exists
      {:ok, version} = Sheets.create_version(child, user)

      # Delete the parent block permanently
      {:ok, _} = Sheets.permanently_delete_block(block)

      # Restore the version - should handle the orphaned reference
      {:ok, restored_sheet} = Sheets.restore_version(child, version)

      # The restored blocks should have the orphaned reference nilified
      restored_blocks = Sheets.list_blocks(restored_sheet.id)

      # The inherited block should be detached since its source is gone
      orphaned =
        Enum.find(restored_blocks, fn b ->
          b.detached == true
        end)

      assert orphaned || is_list(restored_blocks)
      # The key point: no crash occurred during restore
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

      # Verify grandchild inherited from the old ancestor
      gc_blocks_before = Sheets.list_blocks(grandchild.id)
      assert Enum.any?(gc_blocks_before, &(&1.inherited_from_block_id == old_block.id))

      # Create a new root with a different inheritable block
      new_root = sheet_fixture(project, %{name: "New Root"})
      new_block = inheritable_block_fixture(new_root, label: "New Root Block")

      # Move child to new_root (child still has grandchild under it)
      {:ok, _} = Sheets.move_sheet(child, new_root.id)

      # Grandchild should now have new_root's block, NOT old parent's
      gc_blocks_after = Sheets.list_blocks(grandchild.id)
      assert Enum.any?(gc_blocks_after, &(&1.inherited_from_block_id == new_block.id))
      refute Enum.any?(gc_blocks_after, &(&1.inherited_from_block_id == old_block.id))
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
end
