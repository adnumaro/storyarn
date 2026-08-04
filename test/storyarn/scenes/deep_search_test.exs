defmodule Storyarn.Scenes.DeepSearchTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures

  alias Storyarn.Scenes

  setup do
    user = user_fixture()
    project = project_fixture(user)

    %{project: project}
  end

  describe "search_scenes_deep/3" do
    test "searches scene name, shortcut, and description", %{project: project} do
      target =
        scene_fixture(project, %{
          name: "Moonlit Causeway",
          shortcut: "world.private-crossing",
          description: "Mapped by the silver cartographer"
        })

      assert result_ids(Scenes.search_scenes_deep(project.id, "Moonlit")) == [target.id]
      assert result_ids(Scenes.search_scenes_deep(project.id, "private-crossing")) == [target.id]
      assert result_ids(Scenes.search_scenes_deep(project.id, "silver cartographer")) == [target.id]
    end

    test "searches authored layer, pin, zone, and annotation text without duplicates", %{
      project: project
    } do
      scene = scene_fixture(project, %{name: "Canvas"})

      layer_fixture(scene, %{"name" => "Cerulean undercroft"})

      pin_fixture(scene, %{
        "label" => "Vermilion beacon",
        "shortcut" => "pin.private-beacon",
        "tooltip" => "Signals from the northern lighthouse"
      })

      zone_fixture(scene, %{
        "name" => "Amber observatory",
        "shortcut" => "zone.private-observatory",
        "tooltip" => "The glass moon is visible here"
      })

      annotation_fixture(scene, %{"text" => "Promises beneath the silent constellation"})

      assert result_ids(Scenes.search_scenes_deep(project.id, "Cerulean undercroft")) == [scene.id]
      assert result_ids(Scenes.search_scenes_deep(project.id, "Vermilion beacon")) == [scene.id]
      assert result_ids(Scenes.search_scenes_deep(project.id, "private-beacon")) == [scene.id]
      assert result_ids(Scenes.search_scenes_deep(project.id, "northern lighthouse")) == [scene.id]
      assert result_ids(Scenes.search_scenes_deep(project.id, "Amber observatory")) == [scene.id]
      assert result_ids(Scenes.search_scenes_deep(project.id, "private-observatory")) == [scene.id]
      assert result_ids(Scenes.search_scenes_deep(project.id, "glass moon")) == [scene.id]

      assert result_ids(Scenes.search_scenes_deep(project.id, "silent constellation")) == [
               scene.id
             ]
    end

    test "searches connection labels", %{project: project} do
      scene = scene_fixture(project, %{name: "Connection Canvas"})
      origin = pin_fixture(scene, %{"label" => "Origin"})
      destination = pin_fixture(scene, %{"label" => "Destination"})

      connection_fixture(scene, origin, destination, %{
        "label" => "Road beneath the copper viaduct"
      })

      assert result_ids(Scenes.search_scenes_deep(project.id, "copper viaduct")) == [scene.id]
    end

    test "excludes other projects and deleted scenes", %{project: project} do
      other_project = project_fixture()
      other_scene = scene_fixture(other_project, %{name: "Foreign Scene"})
      annotation_fixture(other_scene, %{"text" => "scoped raven phrase"})

      deleted_scene = scene_fixture(project, %{name: "Deleted Scene"})
      annotation_fixture(deleted_scene, %{"text" => "scoped raven phrase"})
      assert {:ok, _deleted} = Scenes.delete_scene(deleted_scene)

      assert Scenes.search_scenes_deep(project.id, "scoped raven phrase") == []
    end

    test "treats LIKE wildcard characters as literal text", %{project: project} do
      literal = scene_fixture(project, %{name: "100% Complete"})
      scene_fixture(project, %{name: "1000 Complete"})

      assert result_ids(Scenes.search_scenes_deep(project.id, "%")) == [literal.id]
    end

    test "applies deterministic pagination and clamps negative bounds", %{project: project} do
      alpha = scene_fixture(project, %{name: "Deep Alpha"})
      bravo = scene_fixture(project, %{name: "Deep Bravo"})
      scene_fixture(project, %{name: "Deep Charlie"})

      assert result_ids(Scenes.search_scenes_deep(project.id, "Deep", limit: 1, offset: 1)) == [
               bravo.id
             ]

      assert result_ids(Scenes.search_scenes_deep(project.id, "Deep", limit: 0, offset: -10)) == [
               alpha.id
             ]
    end
  end

  defp result_ids(results), do: Enum.map(results, & &1.id)
end
