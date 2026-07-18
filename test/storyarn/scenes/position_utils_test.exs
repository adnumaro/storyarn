defmodule Storyarn.Scenes.PositionUtilsTest do
  use Storyarn.DataCase

  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures

  alias Storyarn.Repo
  alias Storyarn.Scenes
  alias Storyarn.Scenes.PositionUtils
  alias Storyarn.Scenes.SceneAnnotation
  alias Storyarn.Scenes.SceneLayer
  alias Storyarn.Scenes.ScenePin
  alias Storyarn.Scenes.SceneZone
  alias Storyarn.Scenes.ZoneCrud

  describe "next_position/2" do
    test "returns 0 when no items exist" do
      # Use a non-existent scene_id to ensure no rows match
      assert PositionUtils.next_position(SceneLayer, -1) == 0
    end

    test "returns max + 1 when items exist" do
      project = project_fixture()
      {:ok, map} = Scenes.create_scene(project, %{name: "Test Map"})

      # The map gets a default layer at position 0
      assert PositionUtils.next_position(SceneLayer, map.id) == 1
    end
  end

  test "scene lock serializes concurrent zone positions and shortcuts" do
    project = project_fixture()
    {:ok, scene} = Scenes.create_scene(project, %{name: "Concurrent Map"})

    attrs = %{
      "name" => "Shared Zone",
      "vertices" => [
        %{"x" => 0.0, "y" => 0.0},
        %{"x" => 100.0, "y" => 0.0},
        %{"x" => 50.0, "y" => 100.0}
      ]
    }

    zones =
      [attrs, attrs]
      |> Task.async_stream(&ZoneCrud.create_zone(scene.id, &1),
        max_concurrency: 2,
        ordered: false,
        timeout: :infinity
      )
      |> Enum.map(fn {:ok, {:ok, zone}} -> zone end)

    assert zones |> Enum.map(& &1.position) |> Enum.uniq() |> length() == 2
    assert zones |> Enum.map(& &1.shortcut) |> Enum.sort() == ["shared-zone", "shared-zone-1"]
  end

  describe "layer ownership invariant" do
    setup do
      project = project_fixture()
      scene = scene_fixture(project)
      own_layer = layer_fixture(scene)
      foreign_scene = scene_fixture(project)
      foreign_layer = layer_fixture(foreign_scene)

      %{
        scene: scene,
        own_layer: own_layer,
        foreign_scene: foreign_scene,
        foreign_layer: foreign_layer
      }
    end

    test "rejects creating pins, zones, and annotations on another scene's layer", %{
      scene: scene,
      foreign_scene: foreign_scene,
      foreign_layer: foreign_layer
    } do
      expected_error =
        {:error, {:scene_layer_ownership_mismatch, foreign_layer.id, scene.id, foreign_scene.id}}

      assert ^expected_error =
               Scenes.create_pin(scene.id, %{
                 "label" => "Foreign pin",
                 "position_x" => 10.0,
                 "position_y" => 20.0,
                 "layer_id" => foreign_layer.id
               })

      assert ^expected_error =
               Scenes.create_zone(scene.id, %{
                 "name" => "Foreign zone",
                 "vertices" => [
                   %{"x" => 0.0, "y" => 0.0},
                   %{"x" => 10.0, "y" => 0.0},
                   %{"x" => 0.0, "y" => 10.0}
                 ],
                 "layer_id" => foreign_layer.id
               })

      assert ^expected_error =
               Scenes.create_annotation(scene.id, %{
                 "text" => "Foreign annotation",
                 "position_x" => 10.0,
                 "position_y" => 20.0,
                 "layer_id" => foreign_layer.id
               })

      assert Scenes.list_pins(scene.id) == []
      assert Scenes.list_zones(scene.id) == []
      assert Scenes.list_annotations(scene.id) == []
    end

    test "rejects cross-scene layer updates without changing persisted children", %{
      scene: scene,
      own_layer: own_layer,
      foreign_scene: foreign_scene,
      foreign_layer: foreign_layer
    } do
      pin = pin_fixture(scene, %{"label" => "Original pin", "layer_id" => own_layer.id})
      zone = zone_fixture(scene, %{"name" => "Original zone", "layer_id" => own_layer.id})

      annotation =
        annotation_fixture(scene, %{
          "text" => "Original annotation",
          "layer_id" => own_layer.id
        })

      expected_error =
        {:error, {:scene_layer_ownership_mismatch, foreign_layer.id, scene.id, foreign_scene.id}}

      assert ^expected_error =
               Scenes.update_pin(pin, %{
                 "label" => "Changed pin",
                 "layer_id" => foreign_layer.id
               })

      assert ^expected_error =
               Scenes.update_zone(zone, %{
                 "name" => "Changed zone",
                 "layer_id" => foreign_layer.id
               })

      assert ^expected_error =
               Scenes.update_annotation(annotation, %{
                 "text" => "Changed annotation",
                 "layer_id" => foreign_layer.id
               })

      persisted_pin = Repo.get!(ScenePin, pin.id)
      assert persisted_pin.layer_id == own_layer.id
      assert persisted_pin.label == "Original pin"

      persisted_zone = Repo.get!(SceneZone, zone.id)
      assert persisted_zone.layer_id == own_layer.id
      assert persisted_zone.name == "Original zone"

      persisted_annotation = Repo.get!(SceneAnnotation, annotation.id)
      assert persisted_annotation.layer_id == own_layer.id
      assert persisted_annotation.text == "Original annotation"
    end

    test "accepts the owning layer as a form string and rejects missing layer ids", %{
      scene: scene,
      own_layer: own_layer
    } do
      assert {:ok, pin} =
               Scenes.create_pin(scene.id, %{
                 "label" => "Owned pin",
                 "position_x" => 10.0,
                 "position_y" => 20.0,
                 "layer_id" => to_string(own_layer.id)
               })

      assert pin.layer_id == own_layer.id

      missing_layer_id = own_layer.id + 10_000_000

      assert {:error, {:scene_layer_not_found, ^missing_layer_id}} =
               Scenes.update_pin(pin, %{"layer_id" => missing_layer_id})

      assert Repo.get!(ScenePin, pin.id).layer_id == own_layer.id
    end
  end
end
