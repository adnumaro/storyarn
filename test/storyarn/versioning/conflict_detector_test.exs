defmodule Storyarn.Versioning.ConflictDetectorTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Assets
  alias Storyarn.Repo
  alias Storyarn.Sheets
  alias Storyarn.Versioning.Builders.FlowBuilder
  alias Storyarn.Versioning.ConflictDetector

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
          %{
            "type" => "dialogue",
            "data" => %{
              "speaker_sheet_id" => avatar_owner.id,
              "avatar_id" => avatar.id
            }
          }
        ],
        "connections" => []
      }

      assert [%{speaker_sheet_id: speaker_sheet_id}] =
               matching_snapshot
               |> FlowBuilder.scan_references()
               |> Enum.filter(&(&1.type == :avatar and &1.id == avatar.id))

      assert speaker_sheet_id == avatar_owner.id

      matching_report =
        ConflictDetector.detect_conflicts("flow", matching_snapshot, flow)

      refute matching_report.has_conflicts
      assert matching_report.conflicts == []

      mismatched_snapshot =
        put_in(
          matching_snapshot,
          ["nodes", Access.at(0), "data", "speaker_sheet_id"],
          other_speaker.id
        )

      mismatch_report =
        ConflictDetector.detect_conflicts("flow", mismatched_snapshot, flow)

      assert mismatch_report.has_conflicts
      assert [%{type: :avatar, id: id}] = mismatch_report.conflicts
      assert id == avatar.id
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
          %{
            "type" => "dialogue",
            "data" => %{"speaker_sheet_id" => foreign_sheet.id}
          }
        ],
        "connections" => []
      }

      report = ConflictDetector.detect_conflicts("flow", snapshot, flow)

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
          %{
            "type" => "dialogue",
            "data" => %{"speaker_sheet_id" => deleted_sheet.id}
          }
        ],
        "connections" => []
      }

      report = ConflictDetector.detect_conflicts("flow", snapshot, flow)

      assert [%{type: :sheet, id: id}] = report.conflicts
      assert id == deleted_sheet.id
    end

    test "does not block a deleted sheet asset with a complete portable catalog entry", %{
      user: user,
      project: project
    } do
      sheet = sheet_fixture(project)
      asset = image_asset_fixture(project, user)
      soft_delete!(asset)

      snapshot = portable_sheet_asset_snapshot(sheet, asset, project.id)

      report = ConflictDetector.detect_conflicts("sheet", snapshot, sheet)

      refute report.has_conflicts
      assert report.conflicts == []
    end

    test "requires an active asset to match its complete portable catalog entry", %{
      user: user,
      project: project
    } do
      sheet = sheet_fixture(project)
      blob_hash = String.duplicate("c", 64)

      asset =
        image_asset_fixture(project, user, %{
          blob_hash: blob_hash,
          filename: "active-banner.png",
          content_type: "image/png",
          size: 123
        })

      asset_id = to_string(asset.id)

      matching_snapshot =
        sheet
        |> portable_sheet_asset_snapshot(asset, project.id)
        |> put_in(["asset_blob_hashes", asset_id], blob_hash)

      matching_report =
        ConflictDetector.detect_conflicts("sheet", matching_snapshot, sheet)

      refute matching_report.has_conflicts
      assert matching_report.conflicts == []

      mismatched_snapshot =
        put_in(
          matching_snapshot,
          ["asset_metadata", asset_id, "filename"],
          "different.png"
        )

      mismatch_report =
        ConflictDetector.detect_conflicts("sheet", mismatched_snapshot, sheet)

      assert [%{type: :asset, id: id}] = mismatch_report.conflicts
      assert id == asset.id

      incomplete_snapshot =
        matching_snapshot
        |> put_in(["asset_blob_hashes"], %{})
        |> put_in(["asset_metadata"], %{})

      incomplete_report =
        ConflictDetector.detect_conflicts("sheet", incomplete_snapshot, sheet)

      assert [%{type: :asset, id: id}] = incomplete_report.conflicts
      assert id == asset.id
    end

    test "accepts a sanitized SVG catalog entry for an image-only sheet slot", %{
      user: user,
      project: project
    } do
      sheet = sheet_fixture(project)
      asset = image_asset_fixture(project, user)
      soft_delete!(asset)

      snapshot =
        sheet
        |> portable_sheet_asset_snapshot(asset, project.id)
        |> put_in(
          ["asset_metadata", to_string(asset.id), "content_type"],
          "image/svg+xml"
        )
        |> put_in(
          ["asset_metadata", to_string(asset.id), "sanitized_svg"],
          true
        )

      report = ConflictDetector.detect_conflicts("sheet", snapshot, sheet)

      refute report.has_conflicts
      assert report.conflicts == []
    end

    test "fails closed for incomplete or invalid portable sheet asset entries", %{
      user: user,
      project: project
    } do
      sheet = sheet_fixture(project)
      asset = image_asset_fixture(project, user)
      soft_delete!(asset)
      asset_id = to_string(asset.id)
      valid_snapshot = portable_sheet_asset_snapshot(sheet, asset, project.id)

      invalid_snapshots = [
        put_in(valid_snapshot, ["asset_blob_hashes", asset_id], "not-a-sha256"),
        update_in(valid_snapshot, ["asset_metadata", asset_id], &Map.delete(&1, "size")),
        put_in(valid_snapshot, ["asset_metadata", asset_id, "project_id"], project.id + 1),
        put_in(valid_snapshot, ["asset_metadata", asset_id, "content_type"], "audio/mpeg"),
        put_in(valid_snapshot, ["asset_metadata", asset_id, "size"], 52_428_801),
        put_in(valid_snapshot, ["asset_metadata", asset_id, "filename"], "   "),
        valid_snapshot
        |> put_in(["asset_metadata", asset_id, "content_type"], "image/svg+xml")
        |> put_in(["asset_metadata", asset_id, "sanitized_svg"], false)
      ]

      for snapshot <- invalid_snapshots do
        report = ConflictDetector.detect_conflicts("sheet", snapshot, sheet)

        assert report.has_conflicts
        assert [%{type: :asset, id: id}] = report.conflicts
        assert id == asset.id
      end
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
          %{
            "type" => "dialogue",
            "data" => %{"audio_asset_id" => asset.id}
          }
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
               |> FlowBuilder.scan_references()
               |> Enum.filter(&(&1.type == :asset and &1.id == asset.id))

      report = ConflictDetector.detect_conflicts("flow", snapshot, flow)

      refute report.has_conflicts
      assert report.conflicts == []

      invalid_snapshot =
        put_in(
          snapshot,
          ["asset_metadata", asset_id, "content_type"],
          "image/png"
        )

      invalid_report = ConflictDetector.detect_conflicts("flow", invalid_snapshot, flow)

      assert [%{type: :asset, id: id}] = invalid_report.conflicts
      assert id == asset.id
    end

    test "Flow reference scanning exposes every asset slot MIME contract", %{flow: flow} do
      snapshot = %{
        "name" => "Test",
        "shortcut" => flow.shortcut,
        "scene_id" => nil,
        "nodes" => [
          %{
            "type" => "dialogue",
            "data" => %{"audio_asset_id" => 999_991}
          },
          %{
            "type" => "sequence",
            "data" => %{},
            "sequence_tracks" => [%{"asset_id" => 999_992}],
            "sequence_visual_layers" => [%{"asset_id" => 999_993}]
          }
        ],
        "connections" => [],
        "localization" => [%{"vo_asset_id" => 999_994}]
      }

      asset_prefixes =
        snapshot
        |> FlowBuilder.scan_references()
        |> Enum.filter(&(&1.type == :asset))
        |> Map.new(&{&1.id, &1.expected_content_type_prefix})

      assert asset_prefixes == %{
               999_991 => "audio/",
               999_992 => "audio/",
               999_993 => "image/",
               999_994 => "audio/"
             }
    end

    test "requires inherited blocks and their parent sheets to belong to the project", %{
      user: user,
      project: project
    } do
      sheet = sheet_fixture(project)
      foreign_sheet = user |> project_fixture() |> sheet_fixture()
      foreign_block = block_fixture(foreign_sheet)

      snapshot = %{
        "name" => "Test",
        "shortcut" => sheet.shortcut,
        "avatar_asset_id" => nil,
        "banner_asset_id" => nil,
        "blocks" => [
          %{
            "type" => "text",
            "position" => 0,
            "inherited_from_block_id" => foreign_block.id
          }
        ]
      }

      report = ConflictDetector.detect_conflicts("sheet", snapshot, sheet)

      assert [%{type: :block, id: id}] = report.conflicts
      assert id == foreign_block.id
    end

    test "detects missing reference-block targets and rich-text mentions", %{
      project: project
    } do
      sheet = sheet_fixture(project)
      missing_sheet_id = 999_997
      missing_flow_id = 999_996

      snapshot = %{
        "name" => "Test",
        "shortcut" => sheet.shortcut,
        "avatar_asset_id" => nil,
        "banner_asset_id" => nil,
        "blocks" => [
          %{
            "type" => "reference",
            "value" => %{"target_type" => "flow", "target_id" => missing_flow_id}
          },
          %{
            "type" => "rich_text",
            "value" => %{
              "content" => ~s(<p><span class="mention" data-type="sheet" data-id="#{missing_sheet_id}">Missing</span></p>)
            }
          }
        ]
      }

      report = ConflictDetector.detect_conflicts("sheet", snapshot, sheet)

      assert report.has_conflicts
      assert Enum.any?(report.conflicts, &(&1.type == :flow and &1.id == missing_flow_id))
      assert Enum.any?(report.conflicts, &(&1.type == :sheet and &1.id == missing_sheet_id))
    end

    test "surfaces malformed embedded sheet references", %{project: project} do
      sheet = sheet_fixture(project)

      snapshot = %{
        "name" => "Test",
        "shortcut" => sheet.shortcut,
        "avatar_asset_id" => nil,
        "banner_asset_id" => nil,
        "blocks" => [
          %{
            "type" => "reference",
            "value" => %{"target_type" => "scene", "target_id" => 123}
          },
          %{
            "type" => "rich_text",
            "value" => %{
              "content" => ~s(<p><span class="mention" data-type="sheet">Missing ID</span></p>)
            }
          }
        ]
      }

      report = ConflictDetector.detect_conflicts("sheet", snapshot, sheet)

      assert report.has_conflicts
      assert Enum.all?(report.conflicts, &(&1.type == :reference))
      assert Enum.any?(report.conflicts, &(&1.id == 123))
      assert Enum.any?(report.conflicts, &is_binary(&1.id))
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

    test "reports a malformed reference instead of silently omitting it", %{flow: flow} do
      snapshot = %{
        "name" => "Test",
        "shortcut" => flow.shortcut,
        "scene_id" => nil,
        "nodes" => [
          %{
            "type" => "dialogue",
            "data" => %{"speaker_sheet_id" => "not-an-id"}
          }
        ],
        "connections" => []
      }

      report = ConflictDetector.detect_conflicts("flow", snapshot, flow)

      assert [%{type: :sheet, id: "not-an-id"}] = report.conflicts
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

    test "does not promise to auto-detach missing inheritance sources", %{project: project} do
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

      assert report.auto_resolved == []
      assert [%{type: :block, id: 999_999}] = report.conflicts
    end
  end

  defp portable_sheet_asset_snapshot(sheet, asset, project_id) do
    asset_id = to_string(asset.id)

    %{
      "name" => "Test",
      "shortcut" => sheet.shortcut,
      "avatar_asset_id" => nil,
      "banner_asset_id" => asset.id,
      "blocks" => [],
      "asset_blob_hashes" => %{asset_id => String.duplicate("a", 64)},
      "asset_metadata" => %{
        asset_id => %{
          "filename" => asset.filename,
          "content_type" => "image/png",
          "size" => asset.size,
          "project_id" => project_id
        }
      }
    }
  end

  defp soft_delete!(asset) do
    assert {:ok, deleted_asset} = Assets.delete_asset(asset)
    deleted_asset
  end
end
