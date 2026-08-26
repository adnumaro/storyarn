defmodule Storyarn.Scenes.Exploration.Commands.SessionsTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures

  alias Storyarn.Scenes.Exploration

  test "save/get/delete preserves the former exploration-session contract" do
    user = user_fixture()
    project = project_fixture(user)
    scene = scene_fixture(project)

    assert {:ok, saved} =
             Exploration.save_session(user.id, project.id, %{
               scene_id: scene.id,
               variable_values: %{"world.score" => 3},
               collected_ids: ["key"]
             })

    assert saved.scene_id == scene.id
    assert saved.variable_values == %{"world.score" => 3}
    assert saved.collected_ids == ["key"]

    loaded = Exploration.get_session(user.id, project.id)
    assert loaded.id == saved.id
    assert loaded.scene.id == scene.id

    assert {:ok, nil} = Exploration.delete_session(user.id, project.id)
    assert Exploration.get_session(user.id, project.id) == nil
  end

  test "upsert keeps the same row while replacing the historical field set" do
    user = user_fixture()
    project = project_fixture(user)
    scene = scene_fixture(project)

    assert {:ok, first} =
             Exploration.save_session(user.id, project.id, %{
               scene_id: scene.id,
               variable_values: %{"score" => 1},
               completed_ambient_ids: [11]
             })

    assert {:ok, second} =
             Exploration.save_session(user.id, project.id, %{
               scene_id: scene.id,
               variable_values: %{"score" => 2},
               completed_ambient_ids: [22]
             })

    assert second.id == first.id
    assert second.variable_values == %{"score" => 2}

    loaded = Exploration.get_session(user.id, project.id)
    assert loaded.completed_ambient_ids == [11]
  end
end
