defmodule Storyarn.Versioning.IntegrationTest do
  @moduledoc """
  Integration tests for the generalized versioning system.
  Tests the full workflow through domain facades (Sheets, Flows, Scenes).
  """
  use Storyarn.DataCase, async: true

  alias Storyarn.{Flows, Scenes, Sheets}

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures, except: [connection_fixture: 3, connection_fixture: 4]
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures, except: [connection_fixture: 3, connection_fixture: 4]
  import Storyarn.SheetsFixtures

  setup do
    user = user_fixture()
    project = project_fixture(user)
    %{user: user, project: project}
  end

  describe "sheet versioning through Versioning context" do
    test "create, list, restore, delete cycle", %{project: project, user: user} do
      sheet = sheet_fixture(project)

      _block =
        block_fixture(sheet, %{
          type: "text",
          config: %{"label" => "Name"},
          value: %{"content" => "Alice"}
        })

      sheet = Storyarn.Repo.preload(sheet, :blocks, force: true)

      # Create version via new system
      {:ok, version} =
        Storyarn.Versioning.create_version("sheet", sheet, project.id, user.id, title: "v1")

      assert version.entity_type == "sheet"
      assert version.version_number == 1

      # Modify sheet
      {:ok, sheet} = Sheets.update_sheet(sheet, %{name: "Modified Sheet"})

      # List versions
      versions = Storyarn.Versioning.list_versions("sheet", sheet.id)
      assert length(versions) == 1

      # Restore
      {:ok, restored} = Storyarn.Versioning.restore_version("sheet", sheet, version)
      assert restored.name != "Modified Sheet"

      # Delete
      {:ok, _} = Storyarn.Versioning.delete_version(version)
      assert Storyarn.Versioning.count_versions("sheet", sheet.id) == 0
    end
  end

  describe "flow versioning through facade" do
    test "create and restore flow version", %{project: project, user: user} do
      flow = flow_fixture(project, %{name: "Main Flow"})
      n1 = node_fixture(flow, %{type: "dialogue", position_x: 100.0, position_y: 100.0})
      n2 = node_fixture(flow, %{type: "hub", position_x: 200.0, position_y: 200.0})
      _conn = Storyarn.FlowsFixtures.connection_fixture(flow, n1, n2)

      # Create version
      {:ok, version} = Flows.create_version(flow, user.id, title: "Before refactor")
      assert version.entity_type == "flow"
      assert version.version_number == 1

      # Modify flow
      {:ok, modified_flow} = Flows.update_flow(flow, %{name: "Refactored Flow"})
      assert modified_flow.name == "Refactored Flow"

      # List
      assert Flows.count_versions(flow.id) == 1

      # Restore
      {:ok, restored} = Flows.restore_version(modified_flow, version)
      assert restored.name == "Main Flow"

      # Verify nodes and connections were restored
      restored = Storyarn.Repo.preload(restored, [:nodes, :connections], force: true)
      active_nodes = Enum.reject(restored.nodes, &(&1.deleted_at != nil))
      assert length(active_nodes) >= 2
      assert length(restored.connections) == 1

      # Set current version
      {:ok, updated_flow} = Flows.set_current_version(restored, version)
      assert updated_flow.current_version_id == version.id
    end
  end

  describe "scene versioning through facade" do
    test "create and restore scene version", %{project: project, user: user} do
      scene = scene_fixture(project, %{name: "World Map"})
      layer = layer_fixture(scene, %{"name" => "Points of Interest"})

      pin1 =
        pin_fixture(scene, %{
          "position_x" => 25.0,
          "position_y" => 25.0,
          "label" => "Town A",
          "layer_id" => layer.id
        })

      pin2 =
        pin_fixture(scene, %{
          "position_x" => 75.0,
          "position_y" => 75.0,
          "label" => "Town B",
          "layer_id" => layer.id
        })

      _conn = Storyarn.ScenesFixtures.connection_fixture(scene, pin1, pin2)

      # Create version
      {:ok, version} = Scenes.create_version(scene, user.id, title: "Initial map")
      assert version.entity_type == "scene"
      assert version.version_number == 1

      # Modify scene
      {:ok, modified_scene} = Scenes.update_scene(scene, %{"name" => "Modified Map"})
      assert modified_scene.name == "Modified Map"

      # Restore
      {:ok, restored} = Scenes.restore_version(modified_scene, version)
      assert restored.name == "World Map"

      # Verify layers and pins were restored
      restored = Storyarn.Repo.preload(restored, [:connections, {:layers, [:pins]}], force: true)
      total_pins = restored.layers |> Enum.flat_map(& &1.pins) |> length()
      assert total_pins >= 2
      assert length(restored.connections) == 1

      # Set current version
      {:ok, updated_scene} = Scenes.set_current_version(restored, version)
      assert updated_scene.current_version_id == version.id
    end
  end

  describe "cross-entity isolation" do
    test "versions are isolated per entity type and ID", %{project: project, user: user} do
      sheet = sheet_fixture(project)
      sheet = Storyarn.Repo.preload(sheet, :blocks)
      flow = flow_fixture(project)

      {:ok, _} = Storyarn.Versioning.create_version("sheet", sheet, project.id, user.id)
      {:ok, _} = Storyarn.Versioning.create_version("flow", flow, project.id, user.id)

      assert Storyarn.Versioning.count_versions("sheet", sheet.id) == 1
      assert Storyarn.Versioning.count_versions("flow", flow.id) == 1
      assert Storyarn.Versioning.count_versions("sheet", flow.id) == 0
    end
  end
end
