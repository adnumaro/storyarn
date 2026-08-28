defmodule Storyarn.Scenes.Versioning.Queries.ConflictsTest do
  use Storyarn.DataCase, async: true

  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Scenes

  test "blocks restore preview for malformed Scene variable collections" do
    project = project_fixture()
    scene = scene_fixture(project)

    snapshot = %{
      "shortcut" => scene.shortcut,
      "background_asset_id" => nil,
      "layers" => [
        %{
          "pins" => [],
          "zones" => [
            %{
              "original_id" => 602,
              "action_type" => "collection",
              "action_data" => %{"items" => nil},
              "condition" => nil,
              "target_type" => nil,
              "target_id" => nil,
              "label_icon_asset_id" => nil
            }
          ]
        }
      ],
      "orphan_pins" => [],
      "orphan_zones" => [],
      "ambient_flows" => []
    }

    report = Scenes.detect_version_restore_conflicts(snapshot, scene)

    assert report.has_conflicts
    assert [%{type: :variable, id: nil, contexts: [context]}] = report.conflicts
    assert context =~ "Scene zone #602"
    assert context =~ "malformed variable reference"
  end

  test "reports unresolved Scene display variables from layered zones" do
    project = project_fixture()
    scene = scene_fixture(project)
    sheet = sheet_fixture(project)
    block = block_fixture(sheet)

    zone = %{
      "original_id" => 601,
      "action_type" => "display",
      "action_data" => %{
        "variable_ref" => "#{sheet.shortcut}.#{block.variable_name}"
      },
      "condition" => nil,
      "target_type" => nil,
      "target_id" => nil,
      "label_icon_asset_id" => nil
    }

    snapshot = %{
      "shortcut" => scene.shortcut,
      "background_asset_id" => nil,
      "layers" => [%{"pins" => [], "zones" => [zone]}],
      "orphan_pins" => [],
      "orphan_zones" => [],
      "ambient_flows" => []
    }

    valid_report = Scenes.detect_version_restore_conflicts(snapshot, scene)
    refute valid_report.has_conflicts

    missing_variable = "missing_scene_preview_variable"

    invalid_snapshot =
      put_in(
        snapshot,
        ["layers", Access.at(0), "zones", Access.at(0), "action_data", "variable_ref"],
        "#{sheet.shortcut}.#{missing_variable}"
      )

    report = Scenes.detect_version_restore_conflicts(invalid_snapshot, scene)

    assert [
             %{
               type: :variable,
               id: qualified_id,
               contexts: [context]
             }
           ] = report.conflicts

    assert qualified_id == "#{sheet.shortcut}.#{missing_variable}"
    assert context =~ "Scene zone #601"
    assert context =~ "unresolved read variable"
  end
end
