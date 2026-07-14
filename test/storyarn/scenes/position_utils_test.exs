defmodule Storyarn.Scenes.PositionUtilsTest do
  use Storyarn.DataCase

  import Storyarn.ProjectsFixtures

  alias Storyarn.Scenes.PositionUtils
  alias Storyarn.Scenes.SceneLayer
  alias Storyarn.Scenes.ZoneCrud

  describe "next_position/2" do
    test "returns 0 when no items exist" do
      # Use a non-existent scene_id to ensure no rows match
      assert PositionUtils.next_position(SceneLayer, -1) == 0
    end

    test "returns max + 1 when items exist" do
      project = project_fixture()
      {:ok, map} = Storyarn.Scenes.create_scene(project, %{name: "Test Map"})

      # The map gets a default layer at position 0
      assert PositionUtils.next_position(SceneLayer, map.id) == 1
    end
  end

  test "scene lock serializes concurrent zone positions and shortcuts" do
    project = project_fixture()
    {:ok, scene} = Storyarn.Scenes.create_scene(project, %{name: "Concurrent Map"})

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
end
