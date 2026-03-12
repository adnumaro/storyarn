defmodule Storyarn.Versioning.ConflictDetectorTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Versioning.ConflictDetector

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.SheetsFixtures

  setup do
    user = user_fixture()
    project = project_fixture(user)
    flow = flow_fixture(project)

    %{user: user, project: project, flow: flow}
  end

  describe "detect_conflicts/3" do
    test "returns empty report for snapshot with no external refs", %{flow: flow} do
      snapshot = %{
        "name" => "Test",
        "shortcut" => flow.shortcut,
        "nodes" => [],
        "connections" => []
      }

      report = ConflictDetector.detect_conflicts("flow", snapshot, flow)

      assert report.has_conflicts == false
      assert report.conflicts == []
      assert report.shortcut_collision == false
      assert report.summary == nil
    end

    test "returns no conflicts when referenced entities exist", %{
      flow: flow,
      project: project
    } do
      sheet = sheet_fixture(project)

      snapshot = %{
        "name" => "Test",
        "shortcut" => flow.shortcut,
        "scene_id" => nil,
        "nodes" => [
          %{
            "type" => "dialogue",
            "data" => %{"speaker_sheet_id" => sheet.id}
          }
        ],
        "connections" => []
      }

      report = ConflictDetector.detect_conflicts("flow", snapshot, flow)

      assert report.has_conflicts == false
      assert report.conflicts == []
    end

    test "detects missing sheet reference", %{flow: flow} do
      missing_id = 999_999

      snapshot = %{
        "name" => "Test",
        "shortcut" => flow.shortcut,
        "scene_id" => nil,
        "nodes" => [
          %{
            "type" => "dialogue",
            "data" => %{"speaker_sheet_id" => missing_id}
          }
        ],
        "connections" => []
      }

      report = ConflictDetector.detect_conflicts("flow", snapshot, flow)

      assert report.has_conflicts == true
      assert length(report.conflicts) == 1

      [conflict] = report.conflicts
      assert conflict.type == :sheet
      assert conflict.id == missing_id
      assert length(conflict.contexts) == 1
      assert hd(conflict.contexts) =~ "speaker"
    end

    test "groups multiple references to the same missing entity", %{flow: flow} do
      missing_id = 999_999

      snapshot = %{
        "name" => "Test",
        "shortcut" => flow.shortcut,
        "scene_id" => nil,
        "nodes" => [
          %{
            "type" => "dialogue",
            "data" => %{"speaker_sheet_id" => missing_id}
          },
          %{
            "type" => "dialogue",
            "data" => %{"speaker_sheet_id" => missing_id}
          }
        ],
        "connections" => []
      }

      report = ConflictDetector.detect_conflicts("flow", snapshot, flow)

      assert report.has_conflicts == true
      assert length(report.conflicts) == 1

      [conflict] = report.conflicts
      assert conflict.type == :sheet
      assert length(conflict.contexts) == 2
    end

    test "detects multiple missing refs of different types", %{flow: flow} do
      missing_sheet_id = 999_998
      missing_flow_id = 999_999

      snapshot = %{
        "name" => "Test",
        "shortcut" => flow.shortcut,
        "scene_id" => nil,
        "nodes" => [
          %{
            "type" => "dialogue",
            "data" => %{"speaker_sheet_id" => missing_sheet_id}
          },
          %{
            "type" => "subflow",
            "data" => %{"referenced_flow_id" => missing_flow_id}
          }
        ],
        "connections" => []
      }

      report = ConflictDetector.detect_conflicts("flow", snapshot, flow)

      assert report.has_conflicts == true
      assert length(report.conflicts) == 2
      types = Enum.map(report.conflicts, & &1.type) |> Enum.sort()
      assert types == [:flow, :sheet]
    end

    test "detects shortcut collision", %{flow: flow, project: project} do
      other_flow = flow_fixture(project)

      snapshot = %{
        "name" => "Test",
        "shortcut" => other_flow.shortcut,
        "nodes" => [],
        "connections" => []
      }

      report = ConflictDetector.detect_conflicts("flow", snapshot, flow)

      assert report.has_conflicts == true
      assert report.shortcut_collision == true
      assert report.resolved_shortcut == other_flow.shortcut <> "-restored"
    end

    test "no collision when shortcut matches current entity", %{flow: flow} do
      snapshot = %{
        "name" => "Test",
        "shortcut" => flow.shortcut,
        "nodes" => [],
        "connections" => []
      }

      report = ConflictDetector.detect_conflicts("flow", snapshot, flow)

      assert report.shortcut_collision == false
    end

    test "detects auto-resolved items for sheets with inherited blocks", %{project: project} do
      sheet = sheet_fixture(project)

      snapshot = %{
        "name" => "Test",
        "shortcut" => sheet.shortcut,
        "avatar_asset_id" => nil,
        "banner_asset_id" => nil,
        "blocks" => [
          %{"inherited_from_block_id" => 999_999, "type" => "text", "position" => 0}
        ]
      }

      report = ConflictDetector.detect_conflicts("sheet", snapshot, sheet)

      assert length(report.auto_resolved) == 1
      assert hd(report.auto_resolved) =~ "inherited"
    end
  end
end
