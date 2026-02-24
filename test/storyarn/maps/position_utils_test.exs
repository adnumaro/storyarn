defmodule Storyarn.Maps.PositionUtilsTest do
  use Storyarn.DataCase

  alias Storyarn.Maps.PositionUtils

  import Storyarn.ProjectsFixtures

  describe "next_position/2" do
    test "returns 0 when no items exist" do
      # Use a non-existent map_id to ensure no rows match
      assert PositionUtils.next_position(Storyarn.Maps.MapLayer, -1) == 0
    end

    test "returns max + 1 when items exist" do
      project = project_fixture()
      {:ok, map} = Storyarn.Maps.create_map(project, %{name: "Test Map"})

      # The map gets a default layer at position 0
      assert PositionUtils.next_position(Storyarn.Maps.MapLayer, map.id) == 1
    end
  end
end
