defmodule Storyarn.Flows.Versioning.ConflictDetectorTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Assets
  alias Storyarn.Flows
  alias Storyarn.Flows.Versioning.FlowSnapshot
  alias Storyarn.Repo
  alias Storyarn.Sheets

  @max_pg_bigint 9_223_372_036_854_775_807

  setup do
    user = user_fixture()
    project = project_fixture(user)
    flow = flow_fixture(project)

    %{user: user, project: project, flow: flow}
  end

  describe "detect_version_restore_conflicts/2" do
    test "returns empty report for snapshot with no external refs", %{flow: flow} do
      snapshot = %{
        "name" => "Test",
        "shortcut" => flow.shortcut,
        "nodes" => [],
        "connections" => []
      }

      report = Flows.detect_version_restore_conflicts(snapshot, flow)

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
          flow_snapshot_node(101, "dialogue", %{"speaker_sheet_id" => sheet.id})
        ],
        "connections" => []
      }

      report = Flows.detect_version_restore_conflicts(snapshot, flow)

      assert report.has_conflicts == false
      assert report.conflicts == []
    end

    test "validates a Flow avatar together with its selected speaker", %{
      user: user,
      project: project,
      flow: flow
    } do
      avatar_owner = sheet_fixture(project)
      other_speaker = sheet_fixture(project)
      avatar_asset = image_asset_fixture(project, user)
      assert {:ok, avatar} = Sheets.add_avatar(avatar_owner, avatar_asset.id)

      matching_snapshot = %{
        "name" => "Test",
        "shortcut" => flow.shortcut,
        "scene_id" => nil,
        "nodes" => [
          flow_snapshot_node(102, "dialogue", %{
            "speaker_sheet_id" => avatar_owner.id,
            "avatar_id" => avatar.id
          })
        ],
        "connections" => []
      }

      assert [%{speaker_sheet_id: speaker_sheet_id}] =
               matching_snapshot
               |> FlowSnapshot.scan_references()
               |> Enum.filter(&(&1.type == :avatar and &1.id == avatar.id))

      assert speaker_sheet_id == avatar_owner.id

      matching_report =
        Flows.detect_version_restore_conflicts(matching_snapshot, flow)

      refute matching_report.has_conflicts
      assert matching_report.conflicts == []

      mismatched_snapshot =
        put_in(
          matching_snapshot,
          ["nodes", Access.at(0), "data", "speaker_sheet_id"],
          other_speaker.id
        )

      mismatch_report =
        Flows.detect_version_restore_conflicts(mismatched_snapshot, flow)

      assert mismatch_report.has_conflicts
      assert [%{type: :avatar, id: id}] = mismatch_report.conflicts
      assert id == avatar.id
    end

    test "accepts a Flow avatar when the optional speaker is absent", %{
      user: user,
      project: project,
      flow: flow
    } do
      avatar_owner = sheet_fixture(project)
      avatar_asset = image_asset_fixture(project, user)
      assert {:ok, avatar} = Sheets.add_avatar(avatar_owner, avatar_asset.id)

      snapshot = %{
        "name" => "Test",
        "shortcut" => flow.shortcut,
        "scene_id" => nil,
        "nodes" => [
          flow_snapshot_node(103, "dialogue", %{
            "speaker_sheet_id" => nil,
            "avatar_id" => avatar.id
          })
        ],
        "connections" => []
      }

      report = Flows.detect_version_restore_conflicts(snapshot, flow)

      refute report.has_conflicts
      assert report.conflicts == []
    end

    test "reports the same unresolved Flow variable that strict restore validation rejects", %{
      project: project,
      flow: flow
    } do
      sheet = sheet_fixture(project)
      block = block_fixture(sheet)

      snapshot = %{
        "name" => "Test",
        "shortcut" => flow.shortcut,
        "scene_id" => nil,
        "nodes" => [
          %{
            "original_id" => 501,
            "type" => "instruction",
            "data" => %{
              "assignments" => [
                %{
                  "sheet" => sheet.shortcut,
                  "variable" => block.variable_name,
                  "value_type" => "literal"
                }
              ]
            }
          }
        ],
        "connections" => []
      }

      valid_report = Flows.detect_version_restore_conflicts(snapshot, flow)
      refute valid_report.has_conflicts

      missing_variable = "missing_preview_variable"

      invalid_snapshot =
        put_in(
          snapshot,
          ["nodes", Access.at(0), "data", "assignments", Access.at(0), "variable"],
          missing_variable
        )

      report = Flows.detect_version_restore_conflicts(invalid_snapshot, flow)

      assert report.has_conflicts

      assert [
               %{
                 type: :variable,
                 id: qualified_id,
                 contexts: [context]
               }
             ] = report.conflicts

      assert qualified_id == "#{sheet.shortcut}.#{missing_variable}"
      assert context =~ "Flow node #501"
      assert context =~ "unresolved write variable"

      malformed_snapshot =
        put_in(
          snapshot,
          ["nodes", Access.at(0), "data", "assignments", Access.at(0), "sheet"],
          nil
        )

      malformed_report =
        Flows.detect_version_restore_conflicts(malformed_snapshot, flow)

      assert [
               %{
                 type: :variable,
                 id: nil,
                 contexts: [malformed_context]
               }
             ] = malformed_report.conflicts

      assert malformed_context =~ "Flow node #501"
      assert malformed_context =~ "malformed variable reference"
    end

    test "blocks restore preview for malformed Flow variable collections", %{
      flow: flow
    } do
      snapshot = %{
        "name" => "Test",
        "shortcut" => flow.shortcut,
        "scene_id" => nil,
        "nodes" => [
          %{
            "original_id" => 502,
            "type" => "instruction",
            "data" => %{"assignments" => nil}
          }
        ],
        "connections" => []
      }

      report = Flows.detect_version_restore_conflicts(snapshot, flow)

      assert report.has_conflicts
      assert [%{type: :variable, id: nil, contexts: [context]}] = report.conflicts
      assert context =~ "Flow node #502"
      assert context =~ "malformed variable reference"
    end

    test "treats references to another project as missing", %{
      user: user,
      flow: flow
    } do
      other_project = project_fixture(user)
      foreign_sheet = sheet_fixture(other_project)

      snapshot = %{
        "name" => "Test",
        "shortcut" => flow.shortcut,
        "scene_id" => nil,
        "nodes" => [
          flow_snapshot_node(104, "dialogue", %{"speaker_sheet_id" => foreign_sheet.id})
        ],
        "connections" => []
      }

      report = Flows.detect_version_restore_conflicts(snapshot, flow)

      assert [%{type: :sheet, id: id}] = report.conflicts
      assert id == foreign_sheet.id
    end

    test "treats soft-deleted references as missing", %{flow: flow, project: project} do
      deleted_sheet = sheet_fixture(project)

      deleted_sheet
      |> Ecto.Changeset.change(deleted_at: DateTime.utc_now(:second))
      |> Repo.update!()

      snapshot = %{
        "name" => "Test",
        "shortcut" => flow.shortcut,
        "scene_id" => nil,
        "nodes" => [
          flow_snapshot_node(105, "dialogue", %{"speaker_sheet_id" => deleted_sheet.id})
        ],
        "connections" => []
      }

      report = Flows.detect_version_restore_conflicts(snapshot, flow)

      assert [%{type: :sheet, id: id}] = report.conflicts
      assert id == deleted_sheet.id
    end

    test "uses the Flow asset slot MIME contract before trusting the portable catalog", %{
      user: user,
      project: project,
      flow: flow
    } do
      asset = image_asset_fixture(project, user)
      soft_delete!(asset)
      asset_id = to_string(asset.id)

      snapshot = %{
        "name" => "Test",
        "shortcut" => flow.shortcut,
        "scene_id" => nil,
        "nodes" => [
          flow_snapshot_node(106, "dialogue", %{"audio_asset_id" => asset.id})
        ],
        "connections" => [],
        "asset_blob_hashes" => %{asset_id => String.duplicate("b", 64)},
        "asset_metadata" => %{
          asset_id => %{
            "filename" => asset.filename,
            "content_type" => "audio/mpeg",
            "size" => asset.size,
            "project_id" => project.id
          }
        }
      }

      assert [%{expected_content_type_prefix: "audio/"}] =
               snapshot
               |> FlowSnapshot.scan_references()
               |> Enum.filter(&(&1.type == :asset and &1.id == asset.id))

      report = Flows.detect_version_restore_conflicts(snapshot, flow)

      refute report.has_conflicts
      assert report.conflicts == []

      invalid_snapshot =
        put_in(
          snapshot,
          ["asset_metadata", asset_id, "content_type"],
          "image/png"
        )

      invalid_report = Flows.detect_version_restore_conflicts(invalid_snapshot, flow)

      assert [%{type: :asset, id: id}] = invalid_report.conflicts
      assert id == asset.id
    end

    test "Flow reference scanning exposes every asset slot MIME contract", %{flow: flow} do
      snapshot = %{
        "name" => "Test",
        "shortcut" => flow.shortcut,
        "scene_id" => nil,
        "nodes" => [
          flow_snapshot_node(107, "dialogue", %{"audio_asset_id" => 999_991}),
          flow_snapshot_node(108, "sequence", %{}, %{
            "sequence_tracks" => [%{"asset_id" => 999_992}],
            "sequence_visual_layers" => [%{"asset_id" => 999_993}]
          })
        ],
        "connections" => [],
        "localization" => [%{"vo_asset_id" => 999_994}]
      }

      asset_prefixes =
        snapshot
        |> FlowSnapshot.scan_references()
        |> Enum.filter(&(&1.type == :asset))
        |> Map.new(&{&1.id, &1.expected_content_type_prefix})

      assert asset_prefixes == %{
               999_991 => "audio/",
               999_992 => "audio/",
               999_993 => "image/",
               999_994 => "audio/"
             }
    end

    test "detects missing sheet reference", %{flow: flow} do
      missing_id = 999_999

      snapshot = %{
        "name" => "Test",
        "shortcut" => flow.shortcut,
        "scene_id" => nil,
        "nodes" => [
          flow_snapshot_node(109, "dialogue", %{"speaker_sheet_id" => missing_id})
        ],
        "connections" => []
      }

      report = Flows.detect_version_restore_conflicts(snapshot, flow)

      assert report.has_conflicts == true
      assert length(report.conflicts) == 1

      [conflict] = report.conflicts
      assert conflict.type == :sheet
      assert conflict.id == missing_id
      assert length(conflict.contexts) == 1
      assert hd(conflict.contexts) =~ "speaker"
    end

    test "reports a malformed reference instead of silently omitting it", %{flow: flow} do
      snapshot = %{
        "name" => "Test",
        "shortcut" => flow.shortcut,
        "scene_id" => nil,
        "nodes" => [
          flow_snapshot_node(110, "dialogue", %{"speaker_sheet_id" => "not-an-id"})
        ],
        "connections" => []
      }

      report = Flows.detect_version_restore_conflicts(snapshot, flow)

      assert [%{type: :sheet, id: "not-an-id"}] = report.conflicts
    end

    test "reports out-of-range and nonscalar IDs without binding them to queries", %{flow: flow} do
      malformed_ids = [
        0,
        -1,
        "0",
        "-1",
        @max_pg_bigint + 1,
        to_string(@max_pg_bigint + 1),
        [1],
        %{"id" => 1}
      ]

      for malformed_id <- malformed_ids do
        snapshot = %{
          "name" => "Test",
          "shortcut" => flow.shortcut,
          "scene_id" => nil,
          "nodes" => [
            flow_snapshot_node(111, "dialogue", %{"speaker_sheet_id" => malformed_id})
          ],
          "connections" => []
        }

        report = Flows.detect_version_restore_conflicts(snapshot, flow)

        assert [%{type: :sheet, id: ^malformed_id}] = report.conflicts
      end
    end

    test "groups multiple references to the same missing entity", %{flow: flow} do
      missing_id = 999_999

      snapshot = %{
        "name" => "Test",
        "shortcut" => flow.shortcut,
        "scene_id" => nil,
        "nodes" => [
          flow_snapshot_node(112, "dialogue", %{"speaker_sheet_id" => missing_id}),
          flow_snapshot_node(113, "dialogue", %{"speaker_sheet_id" => missing_id})
        ],
        "connections" => []
      }

      report = Flows.detect_version_restore_conflicts(snapshot, flow)

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
          flow_snapshot_node(114, "dialogue", %{"speaker_sheet_id" => missing_sheet_id}),
          flow_snapshot_node(115, "subflow", %{"referenced_flow_id" => missing_flow_id})
        ],
        "connections" => []
      }

      report = Flows.detect_version_restore_conflicts(snapshot, flow)

      assert report.has_conflicts == true
      assert length(report.conflicts) == 2
      types = report.conflicts |> Enum.map(& &1.type) |> Enum.sort()
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

      report = Flows.detect_version_restore_conflicts(snapshot, flow)

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

      report = Flows.detect_version_restore_conflicts(snapshot, flow)

      assert report.shortcut_collision == false
    end
  end

  defp flow_snapshot_node(original_id, type, data, extra \\ %{}) do
    data = if type == "dialogue", do: Map.put_new(data, "responses", []), else: data

    Map.merge(
      %{"original_id" => original_id, "type" => type, "data" => data},
      extra
    )
  end

  defp soft_delete!(asset) do
    assert {:ok, deleted_asset} = Assets.delete_asset(asset)
    deleted_asset
  end
end
