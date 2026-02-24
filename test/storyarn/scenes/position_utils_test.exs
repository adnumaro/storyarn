defmodule Storyarn.Scenes.PositionUtilsTest do
  use Storyarn.DataCase

  alias Storyarn.Scenes.PositionUtils

  import Storyarn.ProjectsFixtures

  describe "next_position/2" do
    test "returns 0 when no items exist" do
      # Use a non-existent scene_id to ensure no rows match
      assert PositionUtils.next_position(Storyarn.Scenes.SceneLayer, -1) == 0
    end

    test "returns max + 1 when items exist" do
      project = project_fixture()
      {:ok, map} = Storyarn.Scenes.create_scene(project, %{name: "Test Map"})

      # The map gets a default layer at position 0
      assert PositionUtils.next_position(Storyarn.Scenes.SceneLayer, map.id) == 1
    end
  end
end
