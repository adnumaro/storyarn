defmodule Storyarn.Drafts.MergeEngineTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Drafts
  alias Storyarn.Flows
  alias Storyarn.Versioning

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures
  import Storyarn.ScenesFixtures

  defp setup_project(_context \\ %{}) do
    user = user_fixture()
    project = project_fixture(user)
    %{user: user, project: project}
  end

  # ===========================================================================
  # merge_draft/2 — Flows
  # ===========================================================================

  describe "merge_draft/2 with flows" do
    test "merges draft into original flow" do
      %{user: user, project: project} = setup_project()
      flow = flow_fixture(project)

      # Add a node to original
      {:ok, _node} =
        Flows.create_node(flow, %{
          "type" => "dialogue",
          "position_x" => 100,
          "position_y" => 100
        })

      # Create draft
      {:ok, draft} = Drafts.create_draft(project.id, "flow", flow.id, user.id)
      draft_entity = Drafts.get_draft_entity(draft)

      # Add a new node to draft
      {:ok, _draft_node} =
        Flows.create_node(draft_entity, %{
          "type" => "hub",
          "position_x" => 200,
          "position_y" => 200
        })

      # Merge
      assert {:ok, updated_flow} = Drafts.merge_draft(draft, user.id)
      assert updated_flow.id == flow.id

      # Draft should be marked as merged
      merged_draft = Drafts.get_draft(draft.id)
      assert merged_draft.status == "merged"
      assert merged_draft.merged_at != nil

      # Draft entity should be deleted
      assert Drafts.get_draft_entity(merged_draft) == nil

      # Pre-merge + post-merge versions should exist
      versions = Versioning.list_versions("flow", flow.id)
      assert length(versions) >= 2
      titles = Enum.map(versions, & &1.title)
      assert Enum.any?(titles, &String.contains?(&1, "Before merge"))
      assert Enum.any?(titles, &String.contains?(&1, "Merged from"))
    end

    test "returns error when source entity is deleted" do
      %{user: user, project: project} = setup_project()
      flow = flow_fixture(project)

      {:ok, draft} = Drafts.create_draft(project.id, "flow", flow.id, user.id)

      # Soft-delete the original
      Flows.delete_flow(flow)

      assert {:error, :source_not_found} = Drafts.merge_draft(draft, user.id)
    end

    test "returns error for non-active draft" do
      %{user: user, project: project} = setup_project()
      flow = flow_fixture(project)

      {:ok, draft} = Drafts.create_draft(project.id, "flow", flow.id, user.id)
      {:ok, discarded} = Drafts.discard_draft(draft)

      assert {:error, :not_active} = Drafts.merge_draft(discarded, user.id)
    end
  end

  # ===========================================================================
  # merge_draft/2 — Sheets
  # ===========================================================================

  describe "merge_draft/2 with sheets" do
    test "merges draft into original sheet preserving shortcut" do
      %{user: user, project: project} = setup_project()
      sheet = sheet_fixture(project)
      original_shortcut = sheet.shortcut
      assert original_shortcut != nil

      {:ok, draft} = Drafts.create_draft(project.id, "sheet", sheet.id, user.id)
      assert {:ok, updated} = Drafts.merge_draft(draft, user.id)
      assert updated.id == sheet.id
      assert updated.shortcut == original_shortcut

      merged_draft = Drafts.get_draft(draft.id)
      assert merged_draft.status == "merged"
    end

    test "preserves blocks added to original after draft creation" do
      %{user: user, project: project} = setup_project()
      sheet = sheet_fixture(project)
      _original_block = block_fixture(sheet, config: %{"label" => "Original"})

      # Create draft (captures baseline with _original_block)
      {:ok, draft} = Drafts.create_draft(project.id, "sheet", sheet.id, user.id)

      # Add a new block to the ORIGINAL after draft was created
      post_draft_block =
        block_fixture(sheet, config: %{"label" => "Added After Draft"})

      # Merge the draft
      assert {:ok, updated} = Drafts.merge_draft(draft, user.id)

      # The block added after draft creation should still exist
      blocks = Storyarn.Sheets.list_blocks(updated.id)
      block_var_names = Enum.map(blocks, & &1.variable_name)
      assert post_draft_block.variable_name in block_var_names
    end

    test "deletes blocks removed from draft during merge" do
      %{user: user, project: project} = setup_project()
      sheet = sheet_fixture(project)
      block_to_delete = block_fixture(sheet, config: %{"label" => "Will Delete"})

      # Create draft
      {:ok, draft} = Drafts.create_draft(project.id, "sheet", sheet.id, user.id)
      draft_entity = Drafts.get_draft_entity(draft)

      # Delete the block from the draft
      draft_blocks = Storyarn.Sheets.list_blocks(draft_entity.id)

      cloned_block =
        Enum.find(draft_blocks, fn b ->
          b.variable_name == block_to_delete.variable_name
        end)

      assert cloned_block
      Storyarn.Sheets.delete_block(cloned_block)

      # Merge
      assert {:ok, updated} = Drafts.merge_draft(draft, user.id)

      # The block should be gone from the original
      blocks = Storyarn.Sheets.list_blocks(updated.id)
      block_var_names = Enum.map(blocks, & &1.variable_name)
      refute block_to_delete.variable_name in block_var_names
    end

    test "stores baseline_entity_ids on draft creation" do
      %{user: user, project: project} = setup_project()
      sheet = sheet_fixture(project)
      block = block_fixture(sheet)

      {:ok, draft} = Drafts.create_draft(project.id, "sheet", sheet.id, user.id)
      assert is_list(draft.baseline_entity_ids["block_ids"])
      assert block.id in draft.baseline_entity_ids["block_ids"]
    end
  end

  # ===========================================================================
  # merge_draft/2 — Scenes
  # ===========================================================================

  describe "merge_draft/2 with scenes" do
    test "merges draft into original scene" do
      %{user: user, project: project} = setup_project()
      scene = scene_fixture(project)

      {:ok, draft} = Drafts.create_draft(project.id, "scene", scene.id, user.id)
      assert {:ok, updated} = Drafts.merge_draft(draft, user.id)
      assert updated.id == scene.id

      merged_draft = Drafts.get_draft(draft.id)
      assert merged_draft.status == "merged"
    end
  end
end
