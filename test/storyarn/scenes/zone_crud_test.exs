defmodule Storyarn.Scenes.ZoneCrudTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Flows.VariableReference
  alias Storyarn.Scenes.SceneZone
  alias Storyarn.Scenes.ZoneCrud
  alias Storyarn.Sheets.EntityReference

  defp create_scene(_context \\ %{}) do
    user = user_fixture()
    project = project_fixture(user)
    scene = scene_fixture(project)
    %{user: user, project: project, scene: scene}
  end

  # =============================================================================
  # create_zone/2
  # =============================================================================

  describe "create_zone/2" do
    test "creates a zone with valid attributes" do
      %{scene: scene} = create_scene()

      assert {:ok, zone} =
               ZoneCrud.create_zone(scene.id, %{
                 "name" => "Test Zone",
                 "vertices" => [
                   %{"x" => 0.0, "y" => 0.0},
                   %{"x" => 100.0, "y" => 0.0},
                   %{"x" => 50.0, "y" => 100.0}
                 ]
               })

      assert zone.name == "Test Zone"
      assert zone.scene_id == scene.id
      assert length(zone.vertices) == 3
    end
  end

  # =============================================================================
  # list_zones/1
  # =============================================================================

  describe "list_zones/1" do
    test "returns empty list when no zones" do
      %{scene: scene} = create_scene()
      assert ZoneCrud.list_zones(scene.id) == []
    end

    test "returns zones for a scene" do
      %{scene: scene} = create_scene()
      zone_fixture(scene, %{"name" => "Zone A"})
      zone_fixture(scene, %{"name" => "Zone B"})

      zones = ZoneCrud.list_zones(scene.id)
      assert length(zones) == 2
    end
  end

  # =============================================================================
  # list_zones/2 (with layer filter)
  # =============================================================================

  describe "list_zones/2 with layer_id" do
    test "filters zones by layer" do
      %{scene: scene} = create_scene()
      layer = layer_fixture(scene)
      zone_fixture(scene, %{"name" => "In Layer", "layer_id" => layer.id})
      zone_fixture(scene, %{"name" => "No Layer"})

      zones = ZoneCrud.list_zones(scene.id, layer_id: layer.id)
      assert length(zones) == 1
      assert hd(zones).name == "In Layer"
    end
  end

  # =============================================================================
  # get_zone/1 and get_zone/2
  # =============================================================================

  describe "get_zone/1" do
    test "returns zone by id" do
      %{scene: scene} = create_scene()
      zone = zone_fixture(scene)

      assert result = ZoneCrud.get_zone(zone.id)
      assert result.id == zone.id
    end

    test "returns nil for non-existent zone" do
      assert ZoneCrud.get_zone(-1) == nil
    end
  end

  describe "get_zone/2" do
    test "returns zone scoped to scene" do
      %{scene: scene} = create_scene()
      zone = zone_fixture(scene)

      assert result = ZoneCrud.get_zone(scene.id, zone.id)
      assert result.id == zone.id
    end

    test "returns nil when zone is in different scene" do
      %{scene: scene} = create_scene()
      %{scene: other_scene} = create_scene()
      zone = zone_fixture(other_scene)

      assert ZoneCrud.get_zone(scene.id, zone.id) == nil
    end
  end

  # =============================================================================
  # update_zone/2
  # =============================================================================

  describe "update_zone/2" do
    test "updates zone attributes" do
      %{scene: scene} = create_scene()
      zone = zone_fixture(scene)

      assert {:ok, updated} = ZoneCrud.update_zone(zone, %{"name" => "Updated Zone"})
      assert updated.name == "Updated Zone"
    end

    test "reloads a stale zone under the scene lock before replacing its references" do
      %{project: project, scene: scene} = create_scene()
      flow = flow_fixture(project)
      sheet = sheet_fixture(project, %{shortcut: "global.state"})

      block =
        block_fixture(sheet, %{
          type: "number",
          config: %{"label" => "Score"}
        })

      assignment = variable_assignment(sheet.shortcut, block.variable_name)
      zone = zone_fixture(scene)
      stale_zone = zone

      assert {:ok, _updated_zone} =
               ZoneCrud.update_zone(zone, %{
                 "target_type" => "flow",
                 "target_id" => flow.id,
                 "action_type" => "action",
                 "action_data" => %{"assignments" => [assignment]}
               })

      assert {:ok, updated_zone} =
               ZoneCrud.update_zone(stale_zone, %{"name" => "Renamed from stale state"})

      assert updated_zone.target_type == "flow"
      assert updated_zone.target_id == flow.id
      assert updated_zone.action_data == %{"assignments" => [assignment]}

      persisted_zone = Repo.get!(SceneZone, zone.id)
      assert persisted_zone.target_type == "flow"
      assert persisted_zone.target_id == flow.id
      assert persisted_zone.action_data == %{"assignments" => [assignment]}

      entity_targets =
        EntityReference
        |> where(
          [reference],
          reference.source_type == "scene_zone" and
            reference.source_id == ^zone.id
        )
        |> Repo.all()
        |> MapSet.new(&{&1.target_type, &1.target_id, &1.context})

      assert entity_targets ==
               MapSet.new([
                 {"flow", flow.id, "target"},
                 {"sheet", sheet.id, "assignment"}
               ])

      assert [
               %VariableReference{
                 block_id: block_id,
                 kind: "write"
               }
             ] =
               Repo.all(
                 from(reference in VariableReference,
                   where:
                     reference.source_type == "scene_zone" and
                       reference.source_id == ^zone.id
                 )
               )

      assert block_id == block.id
    end
  end

  # =============================================================================
  # update_zone_vertices/2
  # =============================================================================

  describe "update_zone_vertices/2" do
    test "updates only vertices" do
      %{scene: scene} = create_scene()
      zone = zone_fixture(scene)

      new_vertices = [
        %{"x" => 0.0, "y" => 0.0},
        %{"x" => 50.0, "y" => 50.0},
        %{"x" => 100.0, "y" => 0.0}
      ]

      assert {:ok, updated} = ZoneCrud.update_zone_vertices(zone, %{"vertices" => new_vertices})
      assert length(updated.vertices) == 3
    end
  end

  # =============================================================================
  # delete_zone/1
  # =============================================================================

  describe "delete_zone/1" do
    test "deletes a zone" do
      %{scene: scene} = create_scene()
      zone = zone_fixture(scene)

      assert {:ok, _deleted} = ZoneCrud.delete_zone(zone)
      assert ZoneCrud.get_zone(zone.id) == nil
    end
  end

  # =============================================================================
  # list_actionable_zones/1
  # =============================================================================

  describe "list_actionable_zones/1" do
    test "returns only action and collection zones" do
      %{scene: scene} = create_scene()

      zone_fixture(scene, %{"name" => "Walkable", "action_type" => "walkable", "is_walkable" => true})

      zone_fixture(scene, %{
        "name" => "Display",
        "action_type" => "display",
        "action_data" => %{"variable_ref" => "mc.hp"}
      })

      zone_fixture(scene, %{
        "name" => "With Action",
        "action_type" => "action",
        "action_data" => %{"assignments" => []}
      })

      zone_fixture(scene, %{
        "name" => "Collection",
        "action_type" => "collection",
        "action_data" => %{"items" => []}
      })

      actionable = ZoneCrud.list_actionable_zones(scene.id)
      assert Enum.map(actionable, & &1.name) == ["With Action", "Collection"]
    end

    test "returns empty list when no actionable zones" do
      %{scene: scene} = create_scene()
      zone_fixture(scene, %{"name" => "Walkable", "action_type" => "walkable", "is_walkable" => true})

      zone_fixture(scene, %{
        "name" => "Display",
        "action_type" => "display",
        "action_data" => %{"variable_ref" => "mc.hp"}
      })

      assert ZoneCrud.list_actionable_zones(scene.id) == []
    end
  end

  defp variable_assignment(sheet_shortcut, variable_name) do
    %{
      "id" => Ecto.UUID.generate(),
      "sheet" => sheet_shortcut,
      "variable" => variable_name,
      "operator" => "set",
      "value" => "100",
      "value_type" => "literal"
    }
  end
end
