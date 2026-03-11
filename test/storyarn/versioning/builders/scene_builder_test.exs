defmodule Storyarn.Versioning.Builders.SceneBuilderTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Versioning.Builders.SceneBuilder

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures

  setup do
    user = user_fixture()
    project = project_fixture(user)
    scene = scene_fixture(project)

    %{user: user, project: project, scene: scene}
  end

  describe "build_snapshot/1" do
    test "captures scene metadata", %{scene: scene} do
      snapshot = SceneBuilder.build_snapshot(scene)

      assert snapshot["name"] == scene.name
      assert snapshot["shortcut"] == scene.shortcut
      assert is_list(snapshot["layers"])
      assert is_list(snapshot["connections"])
    end

    test "captures layers with zones and pins", %{scene: scene} do
      layer = layer_fixture(scene, %{"name" => "Combat Layer"})

      _zone =
        zone_fixture(scene, %{
          "name" => "Zone 1",
          "layer_id" => layer.id,
          "vertices" => [
            %{"x" => 10.0, "y" => 10.0},
            %{"x" => 50.0, "y" => 10.0},
            %{"x" => 30.0, "y" => 50.0}
          ]
        })

      _pin =
        pin_fixture(scene, %{"position_x" => 50.0, "position_y" => 50.0, "layer_id" => layer.id})

      snapshot = SceneBuilder.build_snapshot(scene)

      # Should have default layer + our new layer
      assert length(snapshot["layers"]) >= 2

      # Check that at least one layer has zones or pins
      has_content =
        Enum.any?(snapshot["layers"], fn l ->
          length(l["zones"] || []) > 0 or length(l["pins"] || []) > 0
        end)

      assert has_content
    end

    test "captures connections with layer/pin indexes", %{scene: scene} do
      layer = layer_fixture(scene)

      pin1 =
        pin_fixture(scene, %{"position_x" => 20.0, "position_y" => 20.0, "layer_id" => layer.id})

      pin2 =
        pin_fixture(scene, %{"position_x" => 80.0, "position_y" => 80.0, "layer_id" => layer.id})

      _conn = connection_fixture(scene, pin1, pin2)

      snapshot = SceneBuilder.build_snapshot(scene)
      assert length(snapshot["connections"]) == 1

      [conn] = snapshot["connections"]
      assert is_integer(conn["from_layer_index"])
      assert is_integer(conn["from_pin_index"])
      assert is_integer(conn["to_layer_index"])
      assert is_integer(conn["to_pin_index"])
    end
  end

  describe "restore_snapshot/3" do
    test "restores scene with layers, pins, and connections", %{scene: scene} do
      layer = layer_fixture(scene)

      pin1 =
        pin_fixture(scene, %{
          "position_x" => 20.0,
          "position_y" => 20.0,
          "label" => "A",
          "layer_id" => layer.id
        })

      pin2 =
        pin_fixture(scene, %{
          "position_x" => 80.0,
          "position_y" => 80.0,
          "label" => "B",
          "layer_id" => layer.id
        })

      _conn = connection_fixture(scene, pin1, pin2)

      snapshot = SceneBuilder.build_snapshot(scene)

      # Modify the scene
      {:ok, modified_scene} = Storyarn.Scenes.update_scene(scene, %{"name" => "Modified"})

      # Restore
      {:ok, restored} = SceneBuilder.restore_snapshot(modified_scene, snapshot)

      assert restored.name == scene.name

      restored =
        Storyarn.Repo.preload(
          restored,
          [:connections, {:layers, [:zones, :pins]}],
          force: true
        )

      total_pins = restored.layers |> Enum.flat_map(& &1.pins) |> length()
      assert total_pins >= 2
      assert length(restored.connections) == 1
    end
  end

  describe "diff_snapshots/2" do
    test "detects name change" do
      old = %{"name" => "Old", "shortcut" => "old", "layers" => [], "connections" => []}
      new = %{"name" => "New", "shortcut" => "old", "layers" => [], "connections" => []}

      diff = SceneBuilder.diff_snapshots(old, new)
      assert diff =~ "Renamed"
    end

    test "detects added pins" do
      old = %{"name" => "S", "layers" => [%{"pins" => []}], "connections" => []}

      new = %{
        "name" => "S",
        "layers" => [%{"pins" => [%{"label" => "A"}]}],
        "connections" => []
      }

      diff = SceneBuilder.diff_snapshots(old, new)
      assert diff =~ "Added"
    end

    test "reports no changes for identical snapshots" do
      snapshot = %{"name" => "S", "shortcut" => "s", "layers" => [], "connections" => []}
      diff = SceneBuilder.diff_snapshots(snapshot, snapshot)
      assert diff =~ "No changes"
    end
  end
end
