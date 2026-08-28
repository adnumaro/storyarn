defmodule Storyarn.Projects.SceneReadModelTest do
  use Storyarn.DataCase, async: true

  import Storyarn.ProjectsFixtures

  alias Storyarn.Projects
  alias Storyarn.Projects.Persistence.SceneAnnotationRecord
  alias Storyarn.Projects.Persistence.SceneLayerRecord
  alias Storyarn.Projects.Persistence.ScenePinRecord
  alias Storyarn.Projects.Persistence.SceneRecord
  alias Storyarn.Projects.Persistence.SceneZoneRecord
  alias Storyarn.Projects.SceneProjectTrash
  alias Storyarn.Projects.SceneReadModel
  alias Storyarn.Repo

  test "Project-owned export reads preserve the active Scene graph and ordering" do
    project = project_fixture()
    second = scene_record_fixture(project.id, %{name: "Second", shortcut: "second", position: 20})
    first = scene_record_fixture(project.id, %{name: "First", shortcut: "first", position: 10})
    layer = layer_record_fixture(first.id, %{name: "Details"})
    pin = pin_record_fixture(first.id, %{label: "Gate", layer_id: layer.id})
    zone = zone_record_fixture(first.id, %{name: "Square", layer_id: layer.id})
    annotation = annotation_record_fixture(first.id, %{text: "North", layer_id: layer.id})

    [local_first, local_second] = SceneReadModel.list_for_export(project.id)

    assert %SceneRecord{} = local_first
    assert [local_first.id, local_second.id] == [first.id, second.id]
    assert Enum.any?(local_first.layers, &(&1.id == layer.id))
    assert Enum.any?(local_first.pins, &(&1.id == pin.id))
    assert Enum.any?(local_first.zones, &(&1.id == zone.id))
    assert Enum.any?(local_first.annotations, &(&1.id == annotation.id))
  end

  test "export reads honor filter_ids and exclude trashed Scenes" do
    project = project_fixture()
    kept = scene_record_fixture(project.id, %{name: "Kept", shortcut: "kept", position: 10})
    filtered = scene_record_fixture(project.id, %{name: "Filtered", shortcut: "filtered", position: 20})
    trashed = scene_record_fixture(project.id, %{name: "Trashed", shortcut: "trashed", position: 30})
    {:ok, _trashed} = trashed |> SceneRecord.delete_changeset() |> Repo.update()

    all_ids = project.id |> SceneReadModel.list_for_export(filter_ids: :all) |> Enum.map(& &1.id)
    assert all_ids == [kept.id, filtered.id]

    assert [only] = SceneReadModel.list_for_export(project.id, filter_ids: [kept.id])
    assert only.id == kept.id

    assert SceneReadModel.count(project.id) == 2
  end

  test "Project-owned dashboard health emits its stable consumer contract" do
    project = project_fixture()
    scene = scene_record_fixture(project.id, %{name: "Health parity", shortcut: "health-parity"})
    layer = layer_record_fixture(scene.id, %{name: "Default", is_default: true})
    pin = pin_record_fixture(scene.id, %{label: "Entrance", layer_id: layer.id})

    assert [finding] = Projects.list_scene_dashboard_health_findings(project.id)

    assert finding == %{
             severity: :warning,
             code: :missing_background,
             scene_id: scene.id,
             entity_type: "scene",
             entity_id: nil,
             details: %{scene_name: scene.name}
           }

    refute finding.entity_id == pin.id
  end

  test "Project-owned trash restore reactivates the Scene cascade" do
    project = project_fixture()
    parent = scene_record_fixture(project.id, %{name: "World", shortcut: "world"})

    child =
      scene_record_fixture(project.id, %{
        name: "Region",
        shortcut: "region",
        parent_id: parent.id
      })

    assert {:ok, %{entity: _deleted, deleted_ids: deleted_ids}} =
             Repo.transaction(fn -> SceneProjectTrash.delete_subtree_in_transaction(parent) end)

    assert parent.id in deleted_ids
    assert child.id in deleted_ids

    trashed = Projects.get_scene_including_deleted(project.id, parent.id)
    assert {:ok, restored} = Projects.restore_trashed_scene(trashed)
    assert restored.id == parent.id
    assert Projects.get_scene_brief(project.id, child.id)
  end

  defp scene_record_fixture(project_id, attrs) do
    defaults = %{name: "Scene", shortcut: "scene-#{System.unique_integer([:positive])}"}

    %SceneRecord{project_id: project_id}
    |> SceneRecord.create_changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp layer_record_fixture(scene_id, attrs) do
    %SceneLayerRecord{scene_id: scene_id}
    |> SceneLayerRecord.create_changeset(Map.merge(%{name: "Layer"}, attrs))
    |> Repo.insert!()
  end

  defp pin_record_fixture(scene_id, attrs) do
    defaults = %{position_x: 10.0, position_y: 20.0}

    %ScenePinRecord{scene_id: scene_id}
    |> ScenePinRecord.create_changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp zone_record_fixture(scene_id, attrs) do
    defaults = %{
      name: "Zone",
      vertices: [
        %{"x" => 0.0, "y" => 0.0},
        %{"x" => 10.0, "y" => 0.0},
        %{"x" => 0.0, "y" => 10.0}
      ]
    }

    %SceneZoneRecord{scene_id: scene_id}
    |> SceneZoneRecord.create_changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp annotation_record_fixture(scene_id, attrs) do
    defaults = %{text: "Note", position_x: 10.0, position_y: 20.0}

    %SceneAnnotationRecord{scene_id: scene_id}
    |> SceneAnnotationRecord.create_changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end
end
