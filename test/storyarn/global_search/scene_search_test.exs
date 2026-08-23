defmodule Storyarn.GlobalSearch.SceneSearchTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures

  alias Storyarn.GlobalSearch.SceneSearch
  alias Storyarn.Scenes

  setup do
    user = user_fixture()
    project = project_fixture(user)

    %{project: project}
  end

  test "scopes identity reads and searches to active Scenes in authorized projects", %{project: project} do
    scene = scene_fixture(project, %{name: "Moonlit Archive", shortcut: "moonlit-archive"})
    deleted = scene_fixture(project, %{name: "Moonlit Ruin", shortcut: "moonlit-ruin"})
    foreign_project = project_fixture(user_fixture())
    foreign = scene_fixture(foreign_project, %{name: "Moonlit Foreign", shortcut: "moonlit-foreign"})

    assert {:ok, _deleted} = Scenes.delete_scene(deleted)

    assert SceneSearch.get(project.id, scene.id).id == scene.id
    assert SceneSearch.get(project.id, foreign.id) == nil

    assert Enum.map(SceneSearch.search_in_projects([project.id], "Moonlit"), & &1.id) == [scene.id]
    assert SceneSearch.search_in_projects([], "Moonlit") == []
  end

  test "deep search reads every authored Scene text surface", %{project: project} do
    scene = scene_fixture(project, %{name: "Neutral scene", description: "No matching metadata"})
    _layer = layer_fixture(scene, %{"name" => "Layer needle"})
    first_pin = pin_fixture(scene, %{"label" => "Pin needle"})
    second_pin = pin_fixture(scene, %{"label" => "Second pin"})
    _zone = zone_fixture(scene, %{"name" => "Zone needle"})
    _annotation = annotation_fixture(scene, %{"text" => "Annotation needle"})
    _connection = connection_fixture(scene, first_pin, second_pin, %{"label" => "Connection needle"})

    for query <- ["Layer needle", "Pin needle", "Zone needle", "Annotation needle", "Connection needle"] do
      assert Enum.map(SceneSearch.search_deep(project.id, query), & &1.id) == [scene.id]
    end
  end
end
