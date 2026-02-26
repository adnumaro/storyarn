defmodule Storyarn.Flows.FlowCrudTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Flows
  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures

  # ===========================================================================
  # Setup helpers
  # ===========================================================================

  defp create_project_and_flow(_context \\ %{}) do
    user = user_fixture()
    project = project_fixture(user)
    flow = flow_fixture(project)
    %{user: user, project: project, flow: flow}
  end

  # ===========================================================================
  # list_flows/1
  # ===========================================================================

  describe "list_flows/1" do
    test "returns all non-deleted flows for a project" do
      %{project: project} = create_project_and_flow()
      flow1 = flow_fixture(project, %{name: "Alpha"})
      flow2 = flow_fixture(project, %{name: "Beta"})

      flows = Flows.list_flows(project.id)
      flow_ids = Enum.map(flows, & &1.id)
      assert flow1.id in flow_ids
      assert flow2.id in flow_ids
    end

    test "excludes soft-deleted flows" do
      %{project: project, flow: flow} = create_project_and_flow()
      Flows.delete_flow(flow)

      flows = Flows.list_flows(project.id)
      flow_ids = Enum.map(flows, & &1.id)
      refute flow.id in flow_ids
    end

    test "returns empty list for project with no flows" do
      user = user_fixture()
      project = project_fixture(user)
      assert Flows.list_flows(project.id) == []
    end

    test "orders by is_main descending then name ascending" do
      user = user_fixture()
      project = project_fixture(user)
      flow_a = flow_fixture(project, %{name: "Zebra"})
      _flow_b = flow_fixture(project, %{name: "Alpha"})
      {:ok, _} = Flows.set_main_flow(flow_a)

      flows = Flows.list_flows(project.id)
      names = Enum.map(flows, & &1.name)

      # Main flow (Zebra) should come first despite alphabetical ordering
      assert hd(names) == "Zebra"
    end
  end

  # ===========================================================================
  # list_flows_tree/1
  # ===========================================================================

  describe "list_flows_tree/1" do
    test "returns flows in tree structure with children" do
      user = user_fixture()
      project = project_fixture(user)
      parent = flow_fixture(project, %{name: "Parent"})
      _child = flow_fixture(project, %{name: "Child", parent_id: parent.id})

      tree = Flows.list_flows_tree(project.id)
      root_names = Enum.map(tree, & &1.name)
      assert "Parent" in root_names

      parent_in_tree = Enum.find(tree, &(&1.name == "Parent"))
      assert length(parent_in_tree.children) == 1
      assert hd(parent_in_tree.children).name == "Child"
    end

    test "returns empty list for empty project" do
      user = user_fixture()
      project = project_fixture(user)
      assert Flows.list_flows_tree(project.id) == []
    end
  end

  # ===========================================================================
  # search_flows/3
  # ===========================================================================

  describe "search_flows/3" do
    test "returns all flows when query is empty string" do
      %{project: project} = create_project_and_flow()
      flow_fixture(project, %{name: "My Test Flow"})

      results = Flows.search_flows(project.id, "")
      assert results != []
    end

    test "searches by name" do
      %{project: project} = create_project_and_flow()
      flow_fixture(project, %{name: "Unique Searchable Name"})

      results = Flows.search_flows(project.id, "Unique Searchable")
      assert length(results) == 1
      assert hd(results).name == "Unique Searchable Name"
    end

    test "searches by shortcut" do
      %{project: project} = create_project_and_flow()
      flow_fixture(project, %{name: "Some Flow", shortcut: "special-shortcut"})

      results = Flows.search_flows(project.id, "special-shortcut")
      assert length(results) == 1
    end

    test "respects limit option" do
      user = user_fixture()
      project = project_fixture(user)

      for i <- 1..5, do: flow_fixture(project, %{name: "SearchTest #{i}"})

      results = Flows.search_flows(project.id, "SearchTest", limit: 2)
      assert length(results) == 2
    end

    test "respects offset option" do
      user = user_fixture()
      project = project_fixture(user)

      for i <- 1..5, do: flow_fixture(project, %{name: "SearchOffset #{i}"})

      all_results = Flows.search_flows(project.id, "SearchOffset")
      offset_results = Flows.search_flows(project.id, "SearchOffset", offset: 2)

      assert length(offset_results) == length(all_results) - 2
    end

    test "respects exclude_id option" do
      %{project: project, flow: flow} = create_project_and_flow()

      results = Flows.search_flows(project.id, "", exclude_id: flow.id)
      flow_ids = Enum.map(results, & &1.id)
      refute flow.id in flow_ids
    end

    test "excludes soft-deleted flows" do
      %{project: project, flow: flow} = create_project_and_flow()
      Flows.delete_flow(flow)

      results = Flows.search_flows(project.id, flow.name)
      flow_ids = Enum.map(results, & &1.id)
      refute flow.id in flow_ids
    end

    test "is case-insensitive" do
      %{project: project} = create_project_and_flow()
      flow_fixture(project, %{name: "CaseSensitive"})

      results = Flows.search_flows(project.id, "casesensitive")
      assert length(results) == 1
    end
  end

  # ===========================================================================
  # search_flows_deep/3
  # ===========================================================================

  describe "search_flows_deep/3" do
    test "falls back to search_flows when query is empty" do
      %{project: project} = create_project_and_flow()

      results = Flows.search_flows_deep(project.id, "")
      assert results != []
    end

    test "searches flow names" do
      %{project: project} = create_project_and_flow()
      flow_fixture(project, %{name: "DeepSearchTarget"})

      results = Flows.search_flows_deep(project.id, "DeepSearchTarget")
      assert length(results) == 1
    end

    test "searches node content (dialogue text)" do
      %{project: project} = create_project_and_flow()
      flow = flow_fixture(project, %{name: "NodeSearch Flow"})
      node_fixture(flow, %{type: "dialogue", data: %{"text" => "UniqueNodeDialogue999"}})

      results = Flows.search_flows_deep(project.id, "UniqueNodeDialogue999")
      assert results != []
      assert Enum.any?(results, &(&1.id == flow.id))
    end

    test "respects exclude_id option" do
      %{project: project, flow: flow} = create_project_and_flow()

      results = Flows.search_flows_deep(project.id, flow.name, exclude_id: flow.id)
      flow_ids = Enum.map(results, & &1.id)
      refute flow.id in flow_ids
    end
  end

  # ===========================================================================
  # get_flow/2
  # ===========================================================================

  describe "get_flow/2" do
    test "returns flow with nodes and connections preloaded" do
      %{project: project, flow: flow} = create_project_and_flow()

      result = Flows.get_flow(project.id, flow.id)
      assert result.id == flow.id
      # Every flow starts with entry + exit nodes
      assert length(result.nodes) == 2
      assert result.connections == []
    end

    test "returns nil when flow does not exist" do
      %{project: project} = create_project_and_flow()
      assert Flows.get_flow(project.id, 0) == nil
    end

    test "returns nil for soft-deleted flow" do
      %{project: project, flow: flow} = create_project_and_flow()
      Flows.delete_flow(flow)

      assert Flows.get_flow(project.id, flow.id) == nil
    end

    test "returns nil when flow belongs to different project" do
      %{flow: flow} = create_project_and_flow()
      user2 = user_fixture()
      project2 = project_fixture(user2)

      assert Flows.get_flow(project2.id, flow.id) == nil
    end

    test "excludes soft-deleted nodes from preload" do
      %{project: project, flow: flow} = create_project_and_flow()
      dialogue = node_fixture(flow, %{type: "dialogue"})
      Flows.delete_node(dialogue)

      result = Flows.get_flow(project.id, flow.id)
      node_ids = Enum.map(result.nodes, & &1.id)
      refute dialogue.id in node_ids
    end
  end

  # ===========================================================================
  # get_flow_brief/2
  # ===========================================================================

  describe "get_flow_brief/2" do
    test "returns flow without preloads" do
      %{project: project, flow: flow} = create_project_and_flow()

      result = Flows.get_flow_brief(project.id, flow.id)
      assert result.id == flow.id
      assert %Ecto.Association.NotLoaded{} = result.nodes
    end

    test "returns nil for non-existent flow" do
      %{project: project} = create_project_and_flow()
      assert Flows.get_flow_brief(project.id, 0) == nil
    end

    test "returns nil for soft-deleted flow" do
      %{project: project, flow: flow} = create_project_and_flow()
      Flows.delete_flow(flow)
      assert Flows.get_flow_brief(project.id, flow.id) == nil
    end
  end

  # ===========================================================================
  # get_flow!/2
  # ===========================================================================

  describe "get_flow!/2" do
    test "returns flow when it exists" do
      %{project: project, flow: flow} = create_project_and_flow()

      result = Flows.get_flow!(project.id, flow.id)
      assert result.id == flow.id
    end

    test "raises when flow does not exist" do
      %{project: project} = create_project_and_flow()

      assert_raise Ecto.NoResultsError, fn ->
        Flows.get_flow!(project.id, 0)
      end
    end
  end

  # ===========================================================================
  # get_flow_including_deleted/2
  # ===========================================================================

  describe "get_flow_including_deleted/2" do
    test "returns a non-deleted flow" do
      %{project: project, flow: flow} = create_project_and_flow()

      result = Flows.get_flow_including_deleted(project.id, flow.id)
      assert result.id == flow.id
    end

    test "returns a soft-deleted flow" do
      %{project: project, flow: flow} = create_project_and_flow()
      Flows.delete_flow(flow)

      result = Flows.get_flow_including_deleted(project.id, flow.id)
      assert result.id == flow.id
      assert result.deleted_at != nil
    end

    test "returns nil when flow does not exist" do
      %{project: project} = create_project_and_flow()
      assert Flows.get_flow_including_deleted(project.id, 0) == nil
    end
  end

  # ===========================================================================
  # create_flow/2
  # ===========================================================================

  describe "create_flow/2" do
    test "creates a flow with name" do
      user = user_fixture()
      project = project_fixture(user)

      {:ok, flow} = Flows.create_flow(project, %{name: "My Flow"})
      assert flow.name == "My Flow"
      assert flow.project_id == project.id
    end

    test "auto-generates shortcut from name" do
      user = user_fixture()
      project = project_fixture(user)

      {:ok, flow} = Flows.create_flow(project, %{name: "Chapter One"})
      assert flow.shortcut != nil
      assert flow.shortcut =~ ~r/^[a-z0-9]/
    end

    test "auto-creates entry and exit nodes" do
      user = user_fixture()
      project = project_fixture(user)

      {:ok, flow} = Flows.create_flow(project, %{name: "New Flow"})
      full = Flows.get_flow!(project.id, flow.id)
      types = Enum.map(full.nodes, & &1.type) |> Enum.sort()
      assert types == ["entry", "exit"]
    end

    test "auto-assigns position" do
      user = user_fixture()
      project = project_fixture(user)

      {:ok, flow1} = Flows.create_flow(project, %{name: "First"})
      {:ok, flow2} = Flows.create_flow(project, %{name: "Second"})

      assert flow1.position != nil
      assert flow2.position > flow1.position
    end

    test "creates flow with parent_id" do
      user = user_fixture()
      project = project_fixture(user)
      parent = flow_fixture(project, %{name: "Parent"})

      {:ok, child} = Flows.create_flow(project, %{name: "Child", parent_id: parent.id})
      assert child.parent_id == parent.id
    end

    test "fails when name is missing" do
      user = user_fixture()
      project = project_fixture(user)

      {:error, changeset} = Flows.create_flow(project, %{})
      assert errors_on(changeset).name
    end

    test "fails when name is too long" do
      user = user_fixture()
      project = project_fixture(user)

      {:error, changeset} = Flows.create_flow(project, %{name: String.duplicate("a", 201)})
      assert errors_on(changeset).name
    end

    test "works with string keys" do
      user = user_fixture()
      project = project_fixture(user)

      {:ok, flow} = Flows.create_flow(project, %{"name" => "String Keys"})
      assert flow.name == "String Keys"
    end

    test "respects provided shortcut" do
      user = user_fixture()
      project = project_fixture(user)

      {:ok, flow} = Flows.create_flow(project, %{name: "Flow", shortcut: "custom-shortcut"})
      assert flow.shortcut == "custom-shortcut"
    end
  end

  # ===========================================================================
  # update_flow/2
  # ===========================================================================

  describe "update_flow/2" do
    test "updates flow name" do
      %{flow: flow} = create_project_and_flow()

      {:ok, updated} = Flows.update_flow(flow, %{name: "Updated Name"})
      assert updated.name == "Updated Name"
    end

    test "updates flow description" do
      %{flow: flow} = create_project_and_flow()

      {:ok, updated} = Flows.update_flow(flow, %{description: "New description"})
      assert updated.description == "New description"
    end

    test "fails with empty name" do
      %{flow: flow} = create_project_and_flow()

      {:error, changeset} = Flows.update_flow(flow, %{name: ""})
      assert errors_on(changeset).name
    end

    test "auto-generates shortcut when flow has none and name changes" do
      %{flow: flow} = create_project_and_flow()
      # Clear the shortcut first
      flow
      |> Ecto.Changeset.change(%{shortcut: nil})
      |> Storyarn.Repo.update!()

      flow_without_shortcut = %{flow | shortcut: nil}
      {:ok, updated} = Flows.update_flow(flow_without_shortcut, %{name: "New Name"})
      assert updated.shortcut != nil
    end
  end

  # ===========================================================================
  # delete_flow/1
  # ===========================================================================

  describe "delete_flow/1" do
    test "soft-deletes a flow" do
      %{project: project, flow: flow} = create_project_and_flow()

      {:ok, deleted} = Flows.delete_flow(flow)
      assert deleted.deleted_at != nil

      assert Flows.get_flow(project.id, flow.id) == nil
    end

    test "soft-deletes children recursively" do
      %{project: project} = create_project_and_flow()
      parent = flow_fixture(project, %{name: "Parent"})
      child = flow_fixture(project, %{name: "Child", parent_id: parent.id})

      {:ok, _} = Flows.delete_flow(parent)

      assert Flows.get_flow(project.id, child.id) == nil
    end
  end

  # ===========================================================================
  # hard_delete_flow/1
  # ===========================================================================

  describe "hard_delete_flow/1" do
    test "permanently deletes a flow from the database" do
      %{project: project, flow: flow} = create_project_and_flow()

      {:ok, _} = Flows.hard_delete_flow(flow)

      assert Flows.get_flow_including_deleted(project.id, flow.id) == nil
    end
  end

  # ===========================================================================
  # restore_flow/1
  # ===========================================================================

  describe "restore_flow/1" do
    test "restores a soft-deleted flow" do
      %{project: project, flow: flow} = create_project_and_flow()
      {:ok, deleted} = Flows.delete_flow(flow)

      deleted_flow = Flows.get_flow_including_deleted(project.id, deleted.id)
      {:ok, restored} = Flows.restore_flow(deleted_flow)

      assert restored.deleted_at == nil
      assert Flows.get_flow(project.id, restored.id) != nil
    end
  end

  # ===========================================================================
  # list_deleted_flows/1
  # ===========================================================================

  describe "list_deleted_flows/1" do
    test "returns soft-deleted flows" do
      %{project: project, flow: flow} = create_project_and_flow()
      {:ok, _} = Flows.delete_flow(flow)

      deleted = Flows.list_deleted_flows(project.id)
      deleted_ids = Enum.map(deleted, & &1.id)
      assert flow.id in deleted_ids
    end

    test "does not return active flows" do
      %{project: project, flow: flow} = create_project_and_flow()

      deleted = Flows.list_deleted_flows(project.id)
      deleted_ids = Enum.map(deleted, & &1.id)
      refute flow.id in deleted_ids
    end
  end

  # ===========================================================================
  # change_flow/2
  # ===========================================================================

  describe "change_flow/2" do
    test "returns a changeset for a flow" do
      %{flow: flow} = create_project_and_flow()

      changeset = Flows.change_flow(flow, %{name: "Changed"})
      assert changeset.valid?
    end

    test "returns changeset with no changes when called with empty attrs" do
      %{flow: flow} = create_project_and_flow()

      changeset = Flows.change_flow(flow)
      assert changeset.valid?
    end
  end

  # ===========================================================================
  # update_flow_scene/2
  # ===========================================================================

  describe "update_flow_scene/2" do
    test "sets scene_id on a flow" do
      %{project: project, flow: flow} = create_project_and_flow()
      scene = scene_fixture(project)

      {:ok, updated} = Flows.update_flow_scene(flow, %{scene_id: scene.id})
      assert updated.scene_id == scene.id
    end

    test "clears scene_id when set to nil" do
      %{project: project, flow: flow} = create_project_and_flow()
      scene = scene_fixture(project)

      {:ok, with_scene} = Flows.update_flow_scene(flow, %{scene_id: scene.id})
      {:ok, cleared} = Flows.update_flow_scene(with_scene, %{scene_id: nil})
      assert cleared.scene_id == nil
    end

    test "rejects scene from different project" do
      %{flow: flow} = create_project_and_flow()
      user2 = user_fixture()
      other_project = project_fixture(user2)
      other_scene = scene_fixture(other_project)

      {:error, changeset} = Flows.update_flow_scene(flow, %{scene_id: other_scene.id})
      assert errors_on(changeset).scene_id
    end

    test "works with string keys" do
      %{project: project, flow: flow} = create_project_and_flow()
      scene = scene_fixture(project)

      {:ok, updated} = Flows.update_flow_scene(flow, %{"scene_id" => to_string(scene.id)})
      assert updated.scene_id == scene.id
    end
  end

  # ===========================================================================
  # set_main_flow/1
  # ===========================================================================

  describe "set_main_flow/1" do
    test "sets a flow as main" do
      %{flow: flow} = create_project_and_flow()

      {:ok, main_flow} = Flows.set_main_flow(flow)
      assert main_flow.is_main == true
    end

    test "unsets previous main flow" do
      %{project: project} = create_project_and_flow()
      flow1 = flow_fixture(project, %{name: "First Main"})
      flow2 = flow_fixture(project, %{name: "Second Main"})

      {:ok, _} = Flows.set_main_flow(flow1)
      {:ok, _} = Flows.set_main_flow(flow2)

      updated_flow1 = Flows.get_flow_brief(project.id, flow1.id)
      updated_flow2 = Flows.get_flow_brief(project.id, flow2.id)

      assert updated_flow1.is_main == false
      assert updated_flow2.is_main == true
    end
  end

  # ===========================================================================
  # get_flow_project_id/1
  # ===========================================================================

  describe "get_flow_project_id/1" do
    test "returns project_id for a flow" do
      %{project: project, flow: flow} = create_project_and_flow()

      assert Flows.get_flow_project_id(flow.id) == project.id
    end

    test "returns nil for non-existent flow" do
      assert Flows.get_flow_project_id(0) == nil
    end
  end

  # ===========================================================================
  # list_flows_for_export/2
  # ===========================================================================

  describe "list_flows_for_export/2" do
    test "returns flows with nodes and connections preloaded" do
      %{project: project, flow: flow} = create_project_and_flow()

      results = Flows.list_flows_for_export(project.id)
      assert results != []

      exported = Enum.find(results, &(&1.id == flow.id))
      assert is_list(exported.nodes)
      assert is_list(exported.connections)
    end

    test "filters by flow IDs when provided" do
      %{project: project} = create_project_and_flow()
      flow1 = flow_fixture(project, %{name: "Export1"})
      _flow2 = flow_fixture(project, %{name: "Export2"})

      results = Flows.list_flows_for_export(project.id, filter_ids: [flow1.id])
      assert length(results) == 1
      assert hd(results).id == flow1.id
    end

    test "returns all flows when filter_ids is :all" do
      %{project: project} = create_project_and_flow()
      flow_fixture(project, %{name: "ExportAll1"})
      flow_fixture(project, %{name: "ExportAll2"})

      results = Flows.list_flows_for_export(project.id, filter_ids: :all)
      assert length(results) >= 3
    end

    test "excludes soft-deleted flows" do
      %{project: project, flow: flow} = create_project_and_flow()
      Flows.delete_flow(flow)

      results = Flows.list_flows_for_export(project.id)
      ids = Enum.map(results, & &1.id)
      refute flow.id in ids
    end
  end

  # ===========================================================================
  # count_flows/1
  # ===========================================================================

  describe "count_flows/1" do
    test "counts non-deleted flows" do
      user = user_fixture()
      project = project_fixture(user)
      flow_fixture(project)
      flow_fixture(project)

      assert Flows.count_flows(project.id) == 2
    end

    test "excludes soft-deleted flows from count" do
      user = user_fixture()
      project = project_fixture(user)
      flow1 = flow_fixture(project)
      flow_fixture(project)
      Flows.delete_flow(flow1)

      assert Flows.count_flows(project.id) == 1
    end

    test "returns 0 for empty project" do
      user = user_fixture()
      project = project_fixture(user)
      assert Flows.count_flows(project.id) == 0
    end
  end

  # ===========================================================================
  # count_nodes_for_project/1
  # ===========================================================================

  describe "count_nodes_for_project/1" do
    test "counts all non-deleted nodes across flows" do
      user = user_fixture()
      project = project_fixture(user)
      flow = flow_fixture(project)
      # flow_fixture creates entry + exit = 2 nodes
      node_fixture(flow, %{type: "dialogue"})

      assert Flows.count_nodes_for_project(project.id) == 3
    end

    test "excludes nodes from soft-deleted flows" do
      user = user_fixture()
      project = project_fixture(user)
      flow = flow_fixture(project)
      node_fixture(flow, %{type: "dialogue"})
      Flows.delete_flow(flow)

      assert Flows.count_nodes_for_project(project.id) == 0
    end
  end

  # ===========================================================================
  # list_nodes_for_flow_ids/1
  # ===========================================================================

  describe "list_nodes_for_flow_ids/1" do
    test "returns nodes for given flow IDs" do
      %{flow: flow} = create_project_and_flow()
      node_fixture(flow, %{type: "dialogue"})

      nodes = Flows.list_nodes_for_flow_ids([flow.id])
      # entry + exit + dialogue = 3
      assert length(nodes) == 3
    end

    test "returns nodes from multiple flows" do
      %{project: project} = create_project_and_flow()
      flow1 = flow_fixture(project)
      flow2 = flow_fixture(project)

      nodes = Flows.list_nodes_for_flow_ids([flow1.id, flow2.id])
      # Each flow has entry + exit = 2 nodes each = 4 total
      assert length(nodes) == 4
    end

    test "returns empty for empty flow IDs list" do
      assert Flows.list_nodes_for_flow_ids([]) == []
    end
  end

  # ===========================================================================
  # list_shortcuts/1
  # ===========================================================================

  describe "list_flow_shortcuts/1" do
    test "returns MapSet of flow shortcuts" do
      user = user_fixture()
      project = project_fixture(user)
      flow = flow_fixture(project, %{name: "My Flow"})

      shortcuts = Flows.list_flow_shortcuts(project.id)
      assert is_struct(shortcuts, MapSet)
      assert flow.shortcut in shortcuts
    end

    test "excludes soft-deleted flow shortcuts" do
      user = user_fixture()
      project = project_fixture(user)
      flow = flow_fixture(project, %{name: "Deleted Flow"})
      Flows.delete_flow(flow)

      shortcuts = Flows.list_flow_shortcuts(project.id)
      refute flow.shortcut in shortcuts
    end
  end

  # ===========================================================================
  # detect_shortcut_conflicts/2
  # ===========================================================================

  describe "detect_flow_shortcut_conflicts/2" do
    test "returns conflicting shortcuts" do
      user = user_fixture()
      project = project_fixture(user)
      _flow = flow_fixture(project, %{name: "Conflict", shortcut: "conflict-shortcut"})

      conflicts = Flows.detect_flow_shortcut_conflicts(project.id, ["conflict-shortcut"])
      assert "conflict-shortcut" in conflicts
    end

    test "returns empty list when no conflicts" do
      user = user_fixture()
      project = project_fixture(user)

      conflicts = Flows.detect_flow_shortcut_conflicts(project.id, ["nonexistent"])
      assert conflicts == []
    end

    test "returns empty list for empty input" do
      user = user_fixture()
      project = project_fixture(user)

      conflicts = Flows.detect_flow_shortcut_conflicts(project.id, [])
      assert conflicts == []
    end
  end

  # ===========================================================================
  # soft_delete_by_shortcut/2
  # ===========================================================================

  describe "soft_delete_flow_by_shortcut/2" do
    test "soft-deletes flows by shortcut" do
      user = user_fixture()
      project = project_fixture(user)
      flow = flow_fixture(project, %{name: "To Delete", shortcut: "to-delete"})

      {count, _} = Flows.soft_delete_flow_by_shortcut(project.id, "to-delete")
      assert count == 1

      assert Flows.get_flow(project.id, flow.id) == nil
    end

    test "returns {0, nil} when no matching shortcut" do
      user = user_fixture()
      project = project_fixture(user)

      {count, _} = Flows.soft_delete_flow_by_shortcut(project.id, "nonexistent")
      assert count == 0
    end
  end

  # ===========================================================================
  # import_flow/2
  # ===========================================================================

  describe "import_flow/2" do
    test "creates a flow without auto-entry/exit nodes" do
      user = user_fixture()
      project = project_fixture(user)

      {:ok, flow} = Flows.import_flow(project.id, %{name: "Imported Flow", shortcut: "imported"})
      assert flow.name == "Imported Flow"

      # import_flow does NOT auto-create entry/exit nodes
      full = Flows.get_flow(project.id, flow.id)
      assert full.nodes == []
    end

    test "fails with invalid attrs" do
      user = user_fixture()
      project = project_fixture(user)

      {:error, changeset} = Flows.import_flow(project.id, %{})
      assert errors_on(changeset).name
    end
  end

  # ===========================================================================
  # import_node/2
  # ===========================================================================

  describe "import_node/2" do
    test "creates a node without side effects" do
      %{project: project} = create_project_and_flow()
      flow = flow_fixture(project)

      {:ok, node} =
        Flows.import_node(flow.id, %{
          type: "dialogue",
          position_x: 200.0,
          position_y: 300.0,
          data: %{"text" => "Imported dialogue"}
        })

      assert node.type == "dialogue"
      assert node.flow_id == flow.id
    end
  end

  # ===========================================================================
  # link_import_parent/2
  # ===========================================================================

  describe "link_flow_import_parent/2" do
    test "sets the parent_id on a flow" do
      user = user_fixture()
      project = project_fixture(user)
      parent = flow_fixture(project, %{name: "Parent"})
      child = flow_fixture(project, %{name: "Child"})

      updated = Flows.link_flow_import_parent(child, parent.id)
      assert updated.parent_id == parent.id
    end
  end

  # ===========================================================================
  # bulk_import_connections/1
  # ===========================================================================

  describe "bulk_import_connections/1" do
    test "bulk-inserts connections" do
      %{project: project} = create_project_and_flow()
      flow = flow_fixture(project)
      entry = Flows.list_nodes(flow.id) |> Enum.find(&(&1.type == "entry"))
      exit_node = Flows.list_nodes(flow.id) |> Enum.find(&(&1.type == "exit"))

      now = Storyarn.Shared.TimeHelpers.now()

      attrs_list = [
        %{
          flow_id: flow.id,
          source_node_id: entry.id,
          target_node_id: exit_node.id,
          source_pin: "output",
          target_pin: "input",
          inserted_at: now,
          updated_at: now
        }
      ]

      result = Flows.bulk_import_connections(attrs_list)
      assert length(result) == 1
    end

    test "handles empty list" do
      result = Flows.bulk_import_connections([])
      assert result == []
    end
  end

  # ===========================================================================
  # default_search_limit/0
  # ===========================================================================

  describe "default_search_limit/0" do
    test "returns 25" do
      assert Flows.default_search_limit() == 25
    end
  end

  # ===========================================================================
  # create_linked_flow/4
  # ===========================================================================

  describe "create_linked_flow/4" do
    setup do
      user = user_fixture()
      project = project_fixture(user)
      parent_flow = flow_fixture(project, %{name: "Parent Flow"})
      %{project: project, parent_flow: parent_flow}
    end

    test "creates child flow with parent_id set", %{project: project, parent_flow: parent_flow} do
      node =
        node_fixture(parent_flow, %{
          type: "exit",
          data: %{
            "label" => "",
            "exit_mode" => "flow_reference",
            "referenced_flow_id" => nil
          }
        })

      {:ok, %{flow: new_flow, node: updated_node}} =
        Flows.create_linked_flow(project, parent_flow, node)

      assert new_flow.parent_id == parent_flow.id
      assert updated_node.data["referenced_flow_id"] == new_flow.id
    end

    test "uses node label as flow name when present", %{
      project: project,
      parent_flow: parent_flow
    } do
      node =
        node_fixture(parent_flow, %{
          type: "exit",
          data: %{
            "label" => "Victory Ending",
            "exit_mode" => "flow_reference",
            "referenced_flow_id" => nil
          }
        })

      {:ok, %{flow: new_flow}} = Flows.create_linked_flow(project, parent_flow, node)

      assert new_flow.name == "Victory Ending"
    end

    test "uses fallback name when no label", %{project: project, parent_flow: parent_flow} do
      node =
        node_fixture(parent_flow, %{
          type: "exit",
          data: %{
            "label" => "",
            "exit_mode" => "flow_reference",
            "referenced_flow_id" => nil
          }
        })

      {:ok, %{flow: new_flow}} = Flows.create_linked_flow(project, parent_flow, node)

      assert new_flow.name == "Parent Flow - Sub"
    end

    test "new flow has entry + exit nodes from create_flow/2", %{
      project: project,
      parent_flow: parent_flow
    } do
      node =
        node_fixture(parent_flow, %{
          type: "subflow",
          data: %{"referenced_flow_id" => nil}
        })

      {:ok, %{flow: new_flow}} = Flows.create_linked_flow(project, parent_flow, node)

      full_flow = Flows.get_flow!(project.id, new_flow.id)
      types = Enum.map(full_flow.nodes, & &1.type) |> Enum.sort()
      assert types == ["entry", "exit"]
    end

    test "accepts custom name via opts", %{project: project, parent_flow: parent_flow} do
      node =
        node_fixture(parent_flow, %{
          type: "exit",
          data: %{"label" => "Ignored", "referenced_flow_id" => nil}
        })

      {:ok, %{flow: new_flow}} =
        Flows.create_linked_flow(project, parent_flow, node, name: "Custom Name")

      assert new_flow.name == "Custom Name"
    end
  end

  # ===========================================================================
  # flow_deleted?/1
  # ===========================================================================

  describe "flow_deleted?/1" do
    test "returns false for active flow" do
      %{flow: flow} = create_project_and_flow()
      refute Flows.flow_deleted?(flow)
    end

    test "returns true for soft-deleted flow" do
      %{project: project, flow: flow} = create_project_and_flow()
      {:ok, _} = Flows.delete_flow(flow)

      deleted_flow = Flows.get_flow_including_deleted(project.id, flow.id)
      assert Flows.flow_deleted?(deleted_flow)
    end
  end
end
