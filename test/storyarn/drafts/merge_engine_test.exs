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
    test "merges draft into original sheet" do
      %{user: user, project: project} = setup_project()
      sheet = sheet_fixture(project)

      {:ok, draft} = Drafts.create_draft(project.id, "sheet", sheet.id, user.id)
      assert {:ok, updated} = Drafts.merge_draft(draft, user.id)
      assert updated.id == sheet.id

      merged_draft = Drafts.get_draft(draft.id)
      assert merged_draft.status == "merged"
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
