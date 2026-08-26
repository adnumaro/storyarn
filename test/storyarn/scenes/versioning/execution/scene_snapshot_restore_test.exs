defmodule Storyarn.Scenes.Versioning.Execution.SceneSnapshotRestoreTest do
  use Storyarn.DataCase, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures

  alias Storyarn.FlowsFixtures
  alias Storyarn.Scenes

  test "restores Scene-owned pin, zone, and ambient-flow sources" do
    user = user_fixture()
    project = project_fixture(user)
    scene = scene_fixture(project)
    flow = FlowsFixtures.flow_fixture(project)

    pin = pin_fixture(scene)
    zone = zone_fixture(scene)

    {:ok, ambient_flow} =
      Scenes.create_ambient_flow(scene.id, %{
        "flow_id" => flow.id,
        "trigger_type" => "on_enter"
      })

    assert {:ok, version} =
             Scenes.create_version(scene, user.id,
               title: "Scene sources",
               skip_diff: true
             )

    assert {:ok, _pin} = Scenes.delete_pin(pin)
    assert {:ok, _zone} = Scenes.delete_zone(zone)
    assert {:ok, _ambient_flow} = Scenes.delete_ambient_flow(ambient_flow)

    current_scene = Scenes.get_scene!(project.id, scene.id)

    assert {:ok, restored} =
             Scenes.restore_version(current_scene, version, user_id: user.id)

    assert restored.id == scene.id
    assert Enum.map(Scenes.list_pins(scene.id), & &1.id) == [pin.id]
    assert Enum.map(Scenes.list_zones(scene.id), & &1.id) == [zone.id]
    assert Enum.map(Scenes.list_ambient_flows(scene.id), & &1.id) == [ambient_flow.id]
  end
end
