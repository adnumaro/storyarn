defmodule Storyarn.Flows.ExitTargetScenesTest do
  use Storyarn.DataCase, async: true

  import Ecto.Query
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures

  alias Storyarn.Flows
  alias Storyarn.Flows.Editor.Projections.SceneRecord
  alias Storyarn.Repo
  alias Storyarn.Scenes

  describe "search_exit_target_scenes/3" do
    test "returns only id and name from the requested project" do
      user = user_fixture()
      project = project_fixture(user)
      other_project = project_fixture(user)
      scene = scene_fixture(project, %{name: "Shared target"})
      _foreign_scene = scene_fixture(other_project, %{name: "Shared target"})

      assert Flows.search_exit_target_scenes(project.id, "Shared") == [
               %{id: scene.id, name: "Shared target"}
             ]
    end

    test "excludes soft-deleted scenes" do
      project = project_fixture(user_fixture())
      active = scene_fixture(project, %{name: "Target active"})
      deleted = scene_fixture(project, %{name: "Target deleted"})
      {:ok, _deleted} = Scenes.delete_scene(deleted)

      assert Flows.search_exit_target_scenes(project.id, "Target") == [
               %{id: active.id, name: "Target active"}
             ]
    end

    test "empty and whitespace queries preserve the existing recent-first ordering" do
      project = project_fixture(user_fixture())
      oldest = scene_fixture(project, %{name: "Oldest"})
      newest = scene_fixture(project, %{name: "Newest"})

      set_updated_at(oldest.id, ~U[2026-01-01 00:00:00Z])
      set_updated_at(newest.id, ~U[2026-01-02 00:00:00Z])

      expected = [%{id: newest.id, name: newest.name}, %{id: oldest.id, name: oldest.name}]

      assert Flows.search_exit_target_scenes(project.id, "") == expected
      assert Flows.search_exit_target_scenes(project.id, "   ") == expected

      assert Flows.search_exit_target_scenes(project.id, "") ==
               scene_options(Scenes.search_scenes(project.id, ""))

      assert Flows.search_exit_target_scenes(project.id, "   ") ==
               scene_options(Scenes.search_scenes(project.id, "   "))

      assert Flows.search_exit_target_scenes(project.id, "", limit: 1, offset: 1) == [
               %{id: oldest.id, name: oldest.name}
             ]
    end

    test "empty searches keep the existing default limit of twenty" do
      project = project_fixture(user_fixture())

      for index <- 1..21 do
        scene_fixture(project, %{name: "Target #{index}"})
      end

      assert project.id |> Flows.search_exit_target_scenes("") |> length() == 20
    end

    test "non-empty searches preserve name ordering, limit, offset and result shape" do
      project = project_fixture(user_fixture())
      alpha = scene_fixture(project, %{name: "Target Alpha"})
      bravo = scene_fixture(project, %{name: "Target Bravo"})
      _charlie = scene_fixture(project, %{name: "Target Charlie"})

      opts = [limit: 2]
      results = Flows.search_exit_target_scenes(project.id, "Target", opts)

      assert results == [
               %{id: alpha.id, name: alpha.name},
               %{id: bravo.id, name: bravo.name}
             ]

      assert results == scene_options(Scenes.search_scenes(project.id, "Target", opts))

      offset_opts = [limit: 1, offset: 1]

      assert Flows.search_exit_target_scenes(project.id, "Target", offset_opts) ==
               scene_options(Scenes.search_scenes(project.id, "Target", offset_opts))

      assert Enum.all?(results, &(&1 |> Map.keys() |> Enum.sort() == [:id, :name]))
    end

    test "matches shortcuts and treats LIKE wildcard characters literally" do
      project = project_fixture(user_fixture())
      scene = scene_fixture(project, %{name: "Literal 100% Map"})
      _wildcard_distractor = scene_fixture(project, %{name: "Literal 1000 Map"})
      expected = [%{id: scene.id, name: scene.name}]

      assert Flows.search_exit_target_scenes(project.id, scene.shortcut) == expected
      assert Flows.search_exit_target_scenes(project.id, String.upcase(scene.shortcut)) == expected
      assert Flows.search_exit_target_scenes(project.id, "100%") == expected

      assert Flows.search_exit_target_scenes(project.id, "100%") ==
               scene_options(Scenes.search_scenes(project.id, "100%"))
    end
  end

  defp set_updated_at(scene_id, updated_at) do
    Repo.update_all(from(scene in SceneRecord, where: scene.id == ^scene_id), set: [updated_at: updated_at])
  end

  defp scene_options(scenes), do: Enum.map(scenes, &Map.take(&1, [:id, :name]))
end
