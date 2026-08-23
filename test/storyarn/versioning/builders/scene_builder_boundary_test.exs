defmodule Storyarn.Versioning.Builders.SceneBuilderBoundaryTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures

  alias Storyarn.Projects.Persistence.SceneRecord
  alias Storyarn.Repo
  alias Storyarn.Versioning.Builders.SceneBuilder

  test "accepts only the Projects-owned Scene projection" do
    user = user_fixture()
    project = project_fixture(user)
    scene = scene_fixture(project)

    assert_raise FunctionClauseError, fn -> SceneBuilder.build_snapshot(scene) end

    project_scene = Repo.get!(SceneRecord, scene.id)
    scene_id = scene.id
    assert %{"original_id" => ^scene_id} = SceneBuilder.build_snapshot(project_scene)
  end
end
