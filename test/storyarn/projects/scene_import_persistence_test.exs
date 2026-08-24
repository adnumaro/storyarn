defmodule Storyarn.Projects.SceneImportPersistenceTest do
  use Storyarn.DataCase, async: true

  import Ecto.Query
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Projects.FlowImportPersistence
  alias Storyarn.Projects.Persistence.SceneAnnotationRecord
  alias Storyarn.Projects.Persistence.SceneConnectionRecord
  alias Storyarn.Projects.Persistence.SceneLayerRecord
  alias Storyarn.Projects.Persistence.ScenePinRecord
  alias Storyarn.Projects.Persistence.SceneRecord
  alias Storyarn.Projects.Persistence.SceneZoneRecord
  alias Storyarn.Projects.SceneImportPersistence
  alias Storyarn.Projects.SceneReadModel
  alias Storyarn.Repo

  setup do
    project = project_fixture(user_fixture())
    %{project: project}
  end

  describe "shortcut persistence" do
    test "lists active shortcuts and detects only existing conflicts", %{project: project} do
      active = import_scene!(project, %{name: "Active", shortcut: "active"})
      deleted = import_scene!(project, %{name: "Deleted", shortcut: "deleted"})

      assert {1, nil} =
               SceneImportPersistence.soft_delete_by_shortcut(project.id, deleted.shortcut)

      assert %SceneRecord{deleted_at: deleted_at} = Repo.get!(SceneRecord, deleted.id)
      assert deleted_at

      assert SceneReadModel.list_shortcuts(project.id) == MapSet.new([active.shortcut])

      assert SceneReadModel.detect_shortcut_conflicts(project.id, [
               "active",
               "deleted",
               "missing"
             ]) == ["active"]

      assert SceneReadModel.detect_shortcut_conflicts(project.id, []) == []
    end

    test "returns an empty update result for a missing shortcut", %{project: project} do
      assert {0, nil} =
               SceneImportPersistence.soft_delete_by_shortcut(project.id, "missing")
    end
  end

  describe "raw entity import" do
    test "inserts a scene without editor side effects", %{project: project} do
      scene =
        import_scene!(project, %{
          name: "Imported Scene",
          shortcut: "explicit-shortcut",
          position: 7
        })

      assert %SceneRecord{
               project_id: project_id,
               name: "Imported Scene",
               shortcut: "explicit-shortcut",
               position: 7
             } = scene

      assert project_id == project.id

      assert Repo.aggregate(
               from(layer in SceneLayerRecord, where: layer.scene_id == ^scene.id),
               :count
             ) == 0
    end

    test "returns a changeset for invalid scene input", %{project: project} do
      assert {:error, changeset} = SceneImportPersistence.import_scene(project.id, %{})
      assert errors_on(changeset).name
    end

    test "inserts layers, pins, and zones directly", %{project: project} do
      scene = import_scene!(project)

      assert {:ok, layer} =
               SceneImportPersistence.import_layer(scene.id, %{
                 name: "Imported Layer",
                 position: 3,
                 is_default: true
               })

      assert %SceneLayerRecord{
               scene_id: scene_id,
               name: "Imported Layer",
               position: 3,
               is_default: true
             } = layer

      assert scene_id == scene.id

      assert {:ok, pin} =
               SceneImportPersistence.import_pin(scene.id, %{
                 position_x: 25.0,
                 position_y: 75.0,
                 label: "Imported Pin",
                 layer_id: layer.id
               })

      assert %ScenePinRecord{
               scene_id: pin_scene_id,
               layer_id: layer_id,
               label: "Imported Pin"
             } = pin

      assert pin_scene_id == scene.id
      assert layer_id == layer.id

      assert {:ok, zone} =
               SceneImportPersistence.import_zone(scene.id, %{
                 name: "Imported Zone",
                 vertices: triangle(),
                 layer_id: layer.id
               })

      assert %SceneZoneRecord{
               scene_id: zone_scene_id,
               layer_id: zone_layer_id,
               name: "Imported Zone"
             } = zone

      assert zone_scene_id == scene.id
      assert zone_layer_id == layer.id
    end
  end

  describe "deferred linking" do
    test "links a scene parent after IDs have been remapped", %{project: project} do
      parent = import_scene!(project, %{name: "Parent", shortcut: "parent"})
      child = import_scene!(project, %{name: "Child", shortcut: "child"})

      assert %SceneRecord{parent_id: parent_id} =
               SceneImportPersistence.link_parent(child, parent.id)

      assert parent_id == parent.id
      assert Repo.get!(SceneRecord, child.id).parent_id == parent.id
    end

    test "links pin flows and zone targets after IDs have been remapped", %{project: project} do
      scene = import_scene!(project)

      assert {:ok, pin} =
               SceneImportPersistence.import_pin(scene.id, %{
                 position_x: 10.0,
                 position_y: 20.0
               })

      assert {:ok, zone} =
               SceneImportPersistence.import_zone(scene.id, %{
                 name: "Portal",
                 vertices: triangle()
               })

      {:ok, flow} =
        FlowImportPersistence.import_flow(project.id, %{
          name: "Target Flow",
          shortcut: "target-flow"
        })

      assert %ScenePinRecord{flow_id: flow_id} =
               SceneImportPersistence.link_pin_flow_id(pin.id, flow.id)

      assert flow_id == flow.id
      assert Repo.get!(ScenePinRecord, pin.id).flow_id == flow.id

      assert %SceneZoneRecord{target_type: "scene", target_id: target_id} =
               SceneImportPersistence.link_zone_target(zone.id, "scene", scene.id)

      assert target_id == scene.id

      assert %SceneZoneRecord{target_type: "scene", target_id: ^target_id} =
               Repo.get!(SceneZoneRecord, zone.id)
    end
  end

  describe "bulk import" do
    test "inserts connections in chunks and handles an empty batch", %{project: project} do
      scene = import_scene!(project)
      pin_a = import_pin!(scene, %{label: "A"})
      pin_b = import_pin!(scene, %{label: "B"})
      now = TimeHelpers.now()

      attrs = [
        %{
          scene_id: scene.id,
          from_pin_id: pin_a.id,
          to_pin_id: pin_b.id,
          inserted_at: now,
          updated_at: now
        }
      ]

      assert [%{id: id}] = SceneImportPersistence.bulk_insert_connections(attrs)
      assert %SceneConnectionRecord{} = Repo.get!(SceneConnectionRecord, id)
      assert SceneImportPersistence.bulk_insert_connections([]) == []
    end

    test "inserts annotations in chunks and handles an empty batch", %{project: project} do
      scene = import_scene!(project)
      now = TimeHelpers.now()

      attrs = [
        %{
          scene_id: scene.id,
          text: "Bulk note",
          position_x: 50.0,
          position_y: 50.0,
          inserted_at: now,
          updated_at: now
        }
      ]

      assert [%{id: id}] = SceneImportPersistence.bulk_insert_annotations(attrs)
      assert %SceneAnnotationRecord{} = Repo.get!(SceneAnnotationRecord, id)
      assert SceneImportPersistence.bulk_insert_annotations([]) == []
    end
  end

  defp import_scene!(project, attrs \\ %{}) do
    unique = System.unique_integer([:positive])

    attrs =
      Enum.into(attrs, %{
        name: "Imported Scene #{unique}",
        shortcut: "imported-scene-#{unique}"
      })

    {:ok, scene} = SceneImportPersistence.import_scene(project.id, attrs)
    scene
  end

  defp import_pin!(scene, attrs) do
    attrs =
      Enum.into(attrs, %{
        position_x: 10.0,
        position_y: 20.0
      })

    {:ok, pin} = SceneImportPersistence.import_pin(scene.id, attrs)
    pin
  end

  defp triangle do
    [
      %{"x" => 10.0, "y" => 10.0},
      %{"x" => 50.0, "y" => 10.0},
      %{"x" => 30.0, "y" => 50.0}
    ]
  end
end
