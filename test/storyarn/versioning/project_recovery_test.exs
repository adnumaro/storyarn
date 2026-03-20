defmodule Storyarn.Versioning.ProjectRecoveryTest do
  use Storyarn.DataCase, async: true

  import Ecto.Query, warn: false

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

    test "remaps cross-entity references across recovered flows and scenes", %{
      project: project,
      workspace_id: workspace_id,
      user: user
    } do
      speaker = sheet_fixture(project, %{name: "Speaker Sheet"})
      scene = scene_fixture(project, %{name: "World Map"})
      target_scene = scene_fixture(project, %{name: "Dungeon Map"})
      flow = flow_fixture(project, %{name: "Main Flow"})
      subflow = flow_fixture(project, %{name: "Sub Flow"})

      {:ok, flow} = Storyarn.Flows.update_flow(flow, %{scene_id: scene.id})

      _dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "speaker_sheet_id" => speaker.id,
            "location_sheet_id" => speaker.id,
            "text" => "Hello"
          }
        })

      _subflow_node =
        node_fixture(flow, %{
          type: "subflow",
          data: %{"referenced_flow_id" => subflow.id}
        })

      _pin =
        pin_fixture(scene, %{
          "label" => "Gate",
          "sheet_id" => speaker.id,
          "flow_id" => flow.id
        })

      _zone =
        zone_fixture(scene, %{
          "name" => "Portal",
          "target_type" => "scene",
          "target_id" => target_scene.id
        })

      snapshot_data = ProjectSnapshotBuilder.build_snapshot(project.id)

      {:ok, recovered} =
        ProjectRecovery.recover_project(workspace_id, snapshot_data, user.id)

      recovered_sheets = Storyarn.Sheets.list_all_sheets(recovered.id)
      recovered_flows = Storyarn.Flows.list_flows(recovered.id)
      recovered_scenes = Storyarn.Scenes.list_scenes(recovered.id)

      recovered_speaker = Enum.find(recovered_sheets, &(&1.name == "Speaker Sheet"))
      recovered_flow = Enum.find(recovered_flows, &(&1.name == "Main Flow"))
      recovered_subflow = Enum.find(recovered_flows, &(&1.name == "Sub Flow"))
      recovered_scene = Enum.find(recovered_scenes, &(&1.name == "World Map"))
      recovered_target_scene = Enum.find(recovered_scenes, &(&1.name == "Dungeon Map"))

      recovered_flow = Storyarn.Repo.preload(recovered_flow, :nodes, force: true)
      recovered_scene = Storyarn.Repo.preload(recovered_scene, [:pins, :zones], force: true)

      recovered_dialogue = Enum.find(recovered_flow.nodes, &(&1.type == "dialogue"))
      recovered_subflow_node = Enum.find(recovered_flow.nodes, &(&1.type == "subflow"))
      recovered_pin = Enum.find(recovered_scene.pins, &(&1.label == "Gate"))
      recovered_zone = Enum.find(recovered_scene.zones, &(&1.name == "Portal"))

      assert recovered_flow.scene_id == recovered_scene.id
      assert recovered_pin.sheet_id == recovered_speaker.id
      assert recovered_pin.flow_id == recovered_flow.id
      assert recovered_zone.target_id == recovered_target_scene.id
      assert recovered_dialogue.data["speaker_sheet_id"] == recovered_speaker.id
      assert recovered_dialogue.data["location_sheet_id"] == recovered_speaker.id
      assert recovered_subflow_node.data["referenced_flow_id"] == recovered_subflow.id
    end

    test "remaps inherited blocks across recovered sheets", %{
      project: project,
      workspace_id: workspace_id,
      user: user
    } do
      parent = sheet_fixture(project, %{name: "Parent Sheet"})

      source_block =
        block_fixture(parent, %{
          type: "text",
          position: 0,
          variable_name: "ancestor",
          config: %{"label" => "Ancestor"}
        })

      child = sheet_fixture(project, %{name: "Child Sheet"})

      inherited_block =
        block_fixture(child, %{
          type: "text",
          position: 0,
          variable_name: "descendant",
          config: %{"label" => "Descendant"}
        })

      from(b in Storyarn.Sheets.Block, where: b.id == ^inherited_block.id)
      |> Storyarn.Repo.update_all(set: [inherited_from_block_id: source_block.id])

      from(s in Storyarn.Sheets.Sheet, where: s.id == ^child.id)
      |> Storyarn.Repo.update_all(set: [hidden_inherited_block_ids: [source_block.id]])

      snapshot_data = ProjectSnapshotBuilder.build_snapshot(project.id)

      {:ok, recovered} =
        ProjectRecovery.recover_project(workspace_id, snapshot_data, user.id)

      recovered_sheets = Storyarn.Sheets.list_all_sheets(recovered.id)
      recovered_parent = Enum.find(recovered_sheets, &(&1.name == "Parent Sheet"))
      recovered_child = Enum.find(recovered_sheets, &(&1.name == "Child Sheet"))

      parent_blocks = Storyarn.Sheets.list_blocks(recovered_parent.id)
      child_blocks = Storyarn.Sheets.list_blocks(recovered_child.id)

      recovered_source_block = Enum.find(parent_blocks, &(&1.variable_name == "ancestor"))
      recovered_inherited_block = Enum.find(child_blocks, &(&1.variable_name == "descendant"))
      recovered_child = Storyarn.Repo.get!(Storyarn.Sheets.Sheet, recovered_child.id)

      assert recovered_inherited_block.inherited_from_block_id == recovered_source_block.id
      assert recovered_child.hidden_inherited_block_ids == [recovered_source_block.id]
    end
  end
end
