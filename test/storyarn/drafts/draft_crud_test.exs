defmodule Storyarn.Drafts.DraftCrudTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Drafts

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
  # create_draft/5
  # ===========================================================================

  describe "create_draft/5" do
    test "creates a draft for a flow" do
      %{user: user, project: project} = setup_project()
      flow = flow_fixture(project)

      assert {:ok, draft} = Drafts.create_draft(project.id, "flow", flow.id, user.id)
      assert draft.entity_type == "flow"
      assert draft.source_entity_id == flow.id
      assert draft.status == "active"
      assert draft.created_by_id == user.id
      assert draft.name == flow.name <> " (Draft)"
    end

    test "creates a draft for a sheet" do
      %{user: user, project: project} = setup_project()
      sheet = sheet_fixture(project)

      assert {:ok, draft} = Drafts.create_draft(project.id, "sheet", sheet.id, user.id)
      assert draft.entity_type == "sheet"
      assert draft.source_entity_id == sheet.id
    end

    test "creates a draft for a scene" do
      %{user: user, project: project} = setup_project()
      scene = scene_fixture(project)

      assert {:ok, draft} = Drafts.create_draft(project.id, "scene", scene.id, user.id)
      assert draft.entity_type == "scene"
      assert draft.source_entity_id == scene.id
    end

    test "allows custom name" do
      %{user: user, project: project} = setup_project()
      flow = flow_fixture(project)

      assert {:ok, draft} =
               Drafts.create_draft(project.id, "flow", flow.id, user.id, name: "My Draft")

      assert draft.name == "My Draft"
    end

    test "enforces draft limit per user" do
      %{user: user, project: project} = setup_project()
      flow1 = flow_fixture(project, %{name: "Flow 1"})
      flow2 = flow_fixture(project, %{name: "Flow 2"})
      flow3 = flow_fixture(project, %{name: "Flow 3"})

      assert {:ok, _} = Drafts.create_draft(project.id, "flow", flow1.id, user.id)
      assert {:ok, _} = Drafts.create_draft(project.id, "flow", flow2.id, user.id)

      assert {:error, :draft_limit_reached} =
               Drafts.create_draft(project.id, "flow", flow3.id, user.id)
    end

    test "different users have independent draft limits" do
      %{user: user1, project: project} = setup_project()
      user2 = user_fixture()
      membership_fixture(project, user2, "editor")
      flow1 = flow_fixture(project, %{name: "Flow 1"})
      flow2 = flow_fixture(project, %{name: "Flow 2"})

      assert {:ok, _} = Drafts.create_draft(project.id, "flow", flow1.id, user1.id)
      assert {:ok, _} = Drafts.create_draft(project.id, "flow", flow2.id, user1.id)
      # user2 still has room
      assert {:ok, _} = Drafts.create_draft(project.id, "flow", flow1.id, user2.id)
    end

    test "returns error for non-existent source entity" do
      %{user: user, project: project} = setup_project()

      assert {:error, _} = Drafts.create_draft(project.id, "flow", -1, user.id)
    end
  end

  # ===========================================================================
  # list_my_drafts/2
  # ===========================================================================

  describe "list_my_drafts/2" do
    test "returns active drafts for the user" do
      %{user: user, project: project} = setup_project()
      flow = flow_fixture(project)

      {:ok, draft} = Drafts.create_draft(project.id, "flow", flow.id, user.id)
      drafts = Drafts.list_my_drafts(project.id, user.id)

      assert length(drafts) == 1
      assert hd(drafts).id == draft.id
    end

    test "excludes discarded drafts" do
      %{user: user, project: project} = setup_project()
      flow = flow_fixture(project)

      {:ok, draft} = Drafts.create_draft(project.id, "flow", flow.id, user.id)
      {:ok, _} = Drafts.discard_draft(draft)

      assert Drafts.list_my_drafts(project.id, user.id) == []
    end

    test "excludes other users' drafts" do
      %{user: user1, project: project} = setup_project()
      user2 = user_fixture()
      membership_fixture(project, user2, "editor")
      flow = flow_fixture(project)

      {:ok, _} = Drafts.create_draft(project.id, "flow", flow.id, user1.id)

      assert Drafts.list_my_drafts(project.id, user2.id) == []
    end
  end

  # ===========================================================================
  # get_draft/1
  # ===========================================================================

  describe "get_draft/1" do
    test "returns draft with preloaded creator" do
      %{user: user, project: project} = setup_project()
      flow = flow_fixture(project)

      {:ok, draft} = Drafts.create_draft(project.id, "flow", flow.id, user.id)
      fetched = Drafts.get_draft(draft.id)

      assert fetched.id == draft.id
      assert fetched.created_by.id == user.id
    end

    test "returns nil for non-existent draft" do
      assert Drafts.get_draft(-1) == nil
    end
  end

  # ===========================================================================
  # get_draft_entity/1
  # ===========================================================================

  describe "get_draft_entity/1" do
    test "returns the cloned flow entity" do
      %{user: user, project: project} = setup_project()
      flow = flow_fixture(project)

      {:ok, draft} = Drafts.create_draft(project.id, "flow", flow.id, user.id)
      entity = Drafts.get_draft_entity(draft)

      assert entity != nil
      assert entity.id != flow.id
      assert entity.draft_id == draft.id
    end

    test "returns the cloned sheet entity" do
      %{user: user, project: project} = setup_project()
      sheet = sheet_fixture(project)

      {:ok, draft} = Drafts.create_draft(project.id, "sheet", sheet.id, user.id)
      entity = Drafts.get_draft_entity(draft)

      assert entity != nil
      assert entity.id != sheet.id
      assert entity.draft_id == draft.id
    end

    test "returns the cloned scene entity" do
      %{user: user, project: project} = setup_project()
      scene = scene_fixture(project)

      {:ok, draft} = Drafts.create_draft(project.id, "scene", scene.id, user.id)
      entity = Drafts.get_draft_entity(draft)

      assert entity != nil
      assert entity.id != scene.id
      assert entity.draft_id == draft.id
    end
  end

  # ===========================================================================
  # discard_draft/1
  # ===========================================================================

  describe "discard_draft/1" do
    test "discards an active draft" do
      %{user: user, project: project} = setup_project()
      flow = flow_fixture(project)

      {:ok, draft} = Drafts.create_draft(project.id, "flow", flow.id, user.id)
      assert {:ok, discarded} = Drafts.discard_draft(draft)
      assert discarded.status == "discarded"
    end

    test "deletes the cloned entity on discard" do
      %{user: user, project: project} = setup_project()
      flow = flow_fixture(project)

      {:ok, draft} = Drafts.create_draft(project.id, "flow", flow.id, user.id)
      entity = Drafts.get_draft_entity(draft)
      assert entity != nil

      {:ok, _} = Drafts.discard_draft(draft)

      # Refresh draft to get updated status
      updated_draft = Drafts.get_draft(draft.id)
      assert Drafts.get_draft_entity(updated_draft) == nil
    end

    test "frees up draft slot after discard" do
      %{user: user, project: project} = setup_project()
      flow1 = flow_fixture(project, %{name: "Flow 1"})
      flow2 = flow_fixture(project, %{name: "Flow 2"})
      flow3 = flow_fixture(project, %{name: "Flow 3"})

      {:ok, draft1} = Drafts.create_draft(project.id, "flow", flow1.id, user.id)
      {:ok, _} = Drafts.create_draft(project.id, "flow", flow2.id, user.id)

      assert {:error, :draft_limit_reached} =
               Drafts.create_draft(project.id, "flow", flow3.id, user.id)

      {:ok, _} = Drafts.discard_draft(draft1)
      assert {:ok, _} = Drafts.create_draft(project.id, "flow", flow3.id, user.id)
    end

    test "returns error for already discarded draft" do
      %{user: user, project: project} = setup_project()
      flow = flow_fixture(project)

      {:ok, draft} = Drafts.create_draft(project.id, "flow", flow.id, user.id)
      {:ok, discarded} = Drafts.discard_draft(draft)
      assert {:error, :not_active} = Drafts.discard_draft(discarded)
    end

    test "returns error for merged draft" do
      %{user: user, project: project} = setup_project()
      flow = flow_fixture(project)

      {:ok, draft} = Drafts.create_draft(project.id, "flow", flow.id, user.id)

      # Manually set status to merged to simulate a merged draft
      draft
      |> Ecto.Changeset.change(status: "merged")
      |> Storyarn.Repo.update!()

      merged_draft = Drafts.get_draft(draft.id)
      assert {:error, :not_active} = Drafts.discard_draft(merged_draft)
    end
  end

  # ===========================================================================
  # get_my_draft/2
  # ===========================================================================

  describe "get_my_draft/2" do
    test "returns draft owned by the user" do
      %{user: user, project: project} = setup_project()
      flow = flow_fixture(project)

      {:ok, draft} = Drafts.create_draft(project.id, "flow", flow.id, user.id)
      fetched = Drafts.get_my_draft(draft.id, user.id)

      assert fetched.id == draft.id
      assert fetched.created_by.id == user.id
    end

    test "returns nil for draft owned by another user" do
      %{user: user1, project: project} = setup_project()
      user2 = user_fixture()
      membership_fixture(project, user2, "editor")
      flow = flow_fixture(project)

      {:ok, draft} = Drafts.create_draft(project.id, "flow", flow.id, user1.id)

      assert Drafts.get_my_draft(draft.id, user2.id) == nil
    end

    test "returns nil for non-existent draft" do
      assert Drafts.get_my_draft(-1, -1) == nil
    end
  end

  # ===========================================================================
  # can_create_draft?/2
  # ===========================================================================

  describe "can_create_draft?/2" do
    test "returns true when under the limit" do
      %{user: user, project: project} = setup_project()
      assert Drafts.can_create_draft?(project.id, user.id) == true
    end

    test "returns false when at the limit" do
      %{user: user, project: project} = setup_project()
      flow1 = flow_fixture(project, %{name: "Flow 1"})
      flow2 = flow_fixture(project, %{name: "Flow 2"})

      {:ok, _} = Drafts.create_draft(project.id, "flow", flow1.id, user.id)
      {:ok, _} = Drafts.create_draft(project.id, "flow", flow2.id, user.id)

      assert Drafts.can_create_draft?(project.id, user.id) == false
    end
  end
end
