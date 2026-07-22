defmodule Storyarn.Scenes.SceneStatsTest do
  use Storyarn.DataCase, async: true

  import Ecto.Query
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures

  alias Storyarn.Repo
  alias Storyarn.Scenes.Scene
  alias Storyarn.Scenes.SceneStats

  setup do
    user = user_fixture()
    project = user |> project_fixture() |> Repo.preload(:workspace)
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

  describe "list_dashboard_health_findings/1" do
    test "detects empty scenes (no zones or pins)", %{project: project} do
      scene_fixture(project, %{name: "Empty One"})

      issues = SceneStats.list_dashboard_health_findings(project.id)

      empty_issues = Enum.filter(issues, &(&1.code == :empty_scene))
      assert empty_issues != []
      assert Enum.any?(empty_issues, &(&1.details.scene_name == "Empty One"))
      assert Enum.all?(empty_issues, &(&1.severity == :info))
    end

    test "does not flag scenes with zones as empty", %{project: project} do
      scene = scene_fixture(project, %{name: "Has Zones"})
      zone_fixture(scene)

      issues = SceneStats.list_dashboard_health_findings(project.id)

      empty_issues = Enum.filter(issues, &(&1.code == :empty_scene))
      refute Enum.any?(empty_issues, &(&1.details.scene_name == "Has Zones"))
    end

    test "detects scenes without background images", %{project: project} do
      scene_fixture(project, %{name: "No Background"})

      issues = SceneStats.list_dashboard_health_findings(project.id)

      bg_issues = Enum.filter(issues, &(&1.code == :missing_background))
      assert bg_issues != []
      assert Enum.any?(bg_issues, &(&1.details.scene_name == "No Background"))
      assert Enum.all?(bg_issues, &(&1.severity == :warning))
    end

    test "detects missing shortcuts", %{project: project} do
      scene = scene_fixture(project, %{name: "No Shortcut"})

      Repo.update_all(
        from(s in Scene, where: s.id == ^scene.id),
        set: [shortcut: nil]
      )

      issues = SceneStats.list_dashboard_health_findings(project.id)

      missing_issues = Enum.filter(issues, &(&1.code == :missing_scene_shortcut))
      assert missing_issues != []
      assert Enum.any?(missing_issues, &(&1.details.scene_name == "No Shortcut"))
      assert Enum.all?(missing_issues, &(&1.severity == :warning))
    end

    test "treats whitespace-only shortcuts as missing", %{project: project} do
      scene = scene_fixture(project, %{name: "Blank Shortcut"})

      Repo.update_all(
        from(s in Scene, where: s.id == ^scene.id),
        set: [shortcut: "   "]
      )

      findings = SceneStats.list_dashboard_health_findings(project.id)

      assert Enum.any?(findings, fn finding ->
               finding.code == :missing_scene_shortcut and
                 finding.scene_id == scene.id
             end)
    end

    test "returns canonical error metadata for elements using a foreign scene layer", %{
      project: project
    } do
      scene = scene_fixture(project, %{name: "Layer Integrity"})
      other_scene = scene_fixture(project, %{name: "Other Scene"})
      pin = pin_fixture(scene, %{"label" => "Lost Pin"})

      foreign_layer_id =
        Repo.one!(
          from(layer in Storyarn.Scenes.SceneLayer,
            where: layer.scene_id == ^other_scene.id,
            select: layer.id
          )
        )

      Repo.update_all(
        from(scene_pin in Storyarn.Scenes.ScenePin, where: scene_pin.id == ^pin.id),
        set: [layer_id: foreign_layer_id]
      )

      findings = SceneStats.list_dashboard_health_findings(project.id)

      assert %{
               severity: :error,
               code: :invalid_layer_reference,
               scene_id: scene_id,
               entity_type: "pin",
               entity_id: pin_id,
               details: %{scene_name: "Layer Integrity", entity_label: "Lost Pin"}
             } = Enum.find(findings, &(&1.code == :invalid_layer_reference))

      assert scene_id == scene.id
      assert pin_id == pin.id
    end
  end
end
