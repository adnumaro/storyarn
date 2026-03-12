defmodule Storyarn.Versioning.ProjectRecoveryTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Versioning.Builders.ProjectSnapshotBuilder
  alias Storyarn.Versioning.ProjectRecovery

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.SheetsFixtures

  setup do
    user = user_fixture()
    project = project_fixture(user)
    workspace_id = project.workspace_id

    %{user: user, project: project, workspace_id: workspace_id}
  end

  describe "recover_project/4" do
    test "creates a new project from snapshot data", %{
      project: project,
      workspace_id: workspace_id,
      user: user
    } do
      sheet_fixture(project, %{name: "Hero Sheet"})
      flow_fixture(project, %{name: "Main Flow"})
      scene_fixture(project, %{name: "World Map"})

      snapshot_data = ProjectSnapshotBuilder.build_snapshot(project.id)

      assert {:ok, recovered} =
               ProjectRecovery.recover_project(workspace_id, snapshot_data, user.id,
                 name: "My RPG (Recovered)"
               )

      assert recovered.name == "My RPG (Recovered)"
      assert recovered.workspace_id == workspace_id
      assert recovered.id != project.id
    end

    test "entity counts match original", %{
      project: project,
      workspace_id: workspace_id,
      user: user
    } do
      sheet = sheet_fixture(project, %{name: "Hero Sheet"})
      block_fixture(sheet, %{type: "text", config: %{"label" => "Name"}})

      flow = flow_fixture(project, %{name: "Main Flow"})
      node_fixture(flow, %{type: "dialogue"})
      scene_fixture(project, %{name: "World Map"})

      snapshot_data = ProjectSnapshotBuilder.build_snapshot(project.id)

      {:ok, recovered} =
        ProjectRecovery.recover_project(workspace_id, snapshot_data, user.id)

      new_sheets = Storyarn.Sheets.list_all_sheets(recovered.id)
      new_flows = Storyarn.Flows.list_flows(recovered.id)
      new_scenes = Storyarn.Scenes.list_scenes(recovered.id)

      assert length(new_sheets) == 1
      assert length(new_flows) == 1
      assert length(new_scenes) == 1
    end

    test "entities have new IDs", %{
      project: project,
      workspace_id: workspace_id,
      user: user
    } do
      sheet = sheet_fixture(project, %{name: "Hero Sheet"})
      flow = flow_fixture(project, %{name: "Main Flow"})
      scene = scene_fixture(project, %{name: "World Map"})

      snapshot_data = ProjectSnapshotBuilder.build_snapshot(project.id)

      {:ok, recovered} =
        ProjectRecovery.recover_project(workspace_id, snapshot_data, user.id)

      [new_sheet] = Storyarn.Sheets.list_all_sheets(recovered.id)
      [new_flow] = Storyarn.Flows.list_flows(recovered.id)
      [new_scene] = Storyarn.Scenes.list_scenes(recovered.id)

      assert new_sheet.id != sheet.id
      assert new_flow.id != flow.id
      assert new_scene.id != scene.id

      assert new_sheet.name == "Hero Sheet"
      assert new_flow.name == "Main Flow"
      assert new_scene.name == "World Map"
    end

    test "creates owner membership for recovering user", %{
      project: project,
      workspace_id: workspace_id,
      user: user
    } do
      snapshot_data = ProjectSnapshotBuilder.build_snapshot(project.id)

      {:ok, recovered} =
        ProjectRecovery.recover_project(workspace_id, snapshot_data, user.id)

      membership = Storyarn.Projects.get_membership(recovered.id, user.id)
      assert membership != nil
      assert membership.role == "owner"
    end

    test "recovers empty project", %{
      project: project,
      workspace_id: workspace_id,
      user: user
    } do
      snapshot_data = ProjectSnapshotBuilder.build_snapshot(project.id)

      assert {:ok, recovered} =
               ProjectRecovery.recover_project(workspace_id, snapshot_data, user.id)

      assert Storyarn.Sheets.list_all_sheets(recovered.id) == []
      assert Storyarn.Flows.list_flows(recovered.id) == []
      assert Storyarn.Scenes.list_scenes(recovered.id) == []
    end

    test "restores tree hierarchy", %{
      project: project,
      workspace_id: workspace_id,
      user: user
    } do
      parent = sheet_fixture(project, %{name: "Parent Sheet"})
      child = sheet_fixture(project, %{name: "Child Sheet"})

      # Move child under parent
      {:ok, _} = Storyarn.Sheets.move_sheet(child, parent.id, 0)

      snapshot_data = ProjectSnapshotBuilder.build_snapshot(project.id)

      {:ok, recovered} =
        ProjectRecovery.recover_project(workspace_id, snapshot_data, user.id)

      new_sheets = Storyarn.Sheets.list_all_sheets(recovered.id)
      new_parent = Enum.find(new_sheets, &(&1.name == "Parent Sheet"))
      new_child = Enum.find(new_sheets, &(&1.name == "Child Sheet"))

      assert new_child.parent_id == new_parent.id
    end

    test "uses default name when not provided", %{
      project: project,
      workspace_id: workspace_id,
      user: user
    } do
      snapshot_data = ProjectSnapshotBuilder.build_snapshot(project.id)

      {:ok, recovered} =
        ProjectRecovery.recover_project(workspace_id, snapshot_data, user.id)

      assert recovered.name == "Recovered Project"
    end
  end
end
