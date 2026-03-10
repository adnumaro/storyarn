defmodule Storyarn.Scenes.SceneStatsTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures

  alias Storyarn.Repo
  alias Storyarn.Scenes.SceneStats

  setup do
    user = user_fixture()
    project = project_fixture(user) |> Repo.preload(:workspace)
    %{project: project}
  end

  describe "scene_stats_for_project/1" do
    test "returns correct zone, pin, and connection counts per scene", %{project: project} do
      scene = scene_fixture(project, %{name: "Stats Scene"})
      zone_fixture(scene)
      zone_fixture(scene)
      pin1 = pin_fixture(scene)
      pin2 = pin_fixture(scene)
      _pin3 = pin_fixture(scene)
      connection_fixture(scene, pin1, pin2)

      stats = SceneStats.scene_stats_for_project(project.id)

      assert Map.has_key?(stats, scene.id)
      scene_stats = stats[scene.id]
      assert scene_stats.zone_count == 2
      assert scene_stats.pin_count == 3
      assert scene_stats.connection_count == 1
    end

    test "returns zeros for scenes with no elements", %{project: project} do
      scene = scene_fixture(project, %{name: "Empty Scene"})

      stats = SceneStats.scene_stats_for_project(project.id)

      assert stats[scene.id].zone_count == 0
      assert stats[scene.id].pin_count == 0
      assert stats[scene.id].connection_count == 0
    end
  end

  describe "scenes_with_background_count/1" do
    test "counts scenes with background images", %{project: project} do
      _no_bg = scene_fixture(project, %{name: "No BG"})
      _no_bg2 = scene_fixture(project, %{name: "No BG 2"})

      count = SceneStats.scenes_with_background_count(project.id)

      # Both scenes have no background
      assert count == 0
    end
  end

  describe "detect_scene_issues/1" do
    test "detects empty scenes (no zones or pins)", %{project: project} do
      scene_fixture(project, %{name: "Empty One"})

      issues = SceneStats.detect_scene_issues(project.id)

      empty_issues = Enum.filter(issues, &(&1.issue_type == :empty_scene))
      assert empty_issues != []
      assert Enum.any?(empty_issues, &(&1.scene_name == "Empty One"))
    end

    test "does not flag scenes with zones as empty", %{project: project} do
      scene = scene_fixture(project, %{name: "Has Zones"})
      zone_fixture(scene)

      issues = SceneStats.detect_scene_issues(project.id)

      empty_issues = Enum.filter(issues, &(&1.issue_type == :empty_scene))
      refute Enum.any?(empty_issues, &(&1.scene_name == "Has Zones"))
    end

    test "detects scenes without background images", %{project: project} do
      scene_fixture(project, %{name: "No Background"})

      issues = SceneStats.detect_scene_issues(project.id)

      bg_issues = Enum.filter(issues, &(&1.issue_type == :no_background))
      assert bg_issues != []
      assert Enum.any?(bg_issues, &(&1.scene_name == "No Background"))
    end

    test "detects missing shortcuts", %{project: project} do
      scene = scene_fixture(project, %{name: "No Shortcut"})

      import Ecto.Query

      Repo.update_all(
        from(s in Storyarn.Scenes.Scene, where: s.id == ^scene.id),
        set: [shortcut: nil]
      )

      issues = SceneStats.detect_scene_issues(project.id)

      missing_issues = Enum.filter(issues, &(&1.issue_type == :missing_shortcut))
      assert missing_issues != []
      assert Enum.any?(missing_issues, &(&1.scene_name == "No Shortcut"))
    end
  end
end
