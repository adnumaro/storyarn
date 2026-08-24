defmodule Storyarn.Sheets.Versioning.ConflictDetectorTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Projects.Assets
  alias Storyarn.Sheets.Versioning.ConflictDetector

  @max_pg_bigint 9_223_372_036_854_775_807

  setup do
    user = user_fixture()
    project = project_fixture(user)

    %{user: user, project: project}
  end

  describe "detect_conflicts/3" do
    test "does not block a deleted sheet asset with a complete portable catalog entry", %{
      user: user,
      project: project
    } do
      sheet = sheet_fixture(project)
      asset = image_asset_fixture(project, user)
      soft_delete!(asset)

      snapshot = portable_sheet_asset_snapshot(sheet, asset, project.id)

      report = ConflictDetector.detect(snapshot, sheet)

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
        ConflictDetector.detect(matching_snapshot, sheet)

      refute matching_report.has_conflicts
      assert matching_report.conflicts == []

      mismatched_snapshot =
        put_in(
          matching_snapshot,
          ["asset_metadata", asset_id, "filename"],
          "different.png"
        )

      mismatch_report =
        ConflictDetector.detect(mismatched_snapshot, sheet)

      assert [%{type: :asset, id: id}] = mismatch_report.conflicts
      assert id == asset.id

      incomplete_snapshot =
        matching_snapshot
        |> put_in(["asset_blob_hashes"], %{})
        |> put_in(["asset_metadata"], %{})

      incomplete_report =
        ConflictDetector.detect(incomplete_snapshot, sheet)

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

      report = ConflictDetector.detect(snapshot, sheet)

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
        report = ConflictDetector.detect(snapshot, sheet)

        assert report.has_conflicts
        assert [%{type: :asset, id: id}] = report.conflicts
        assert id == asset.id
      end
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

      report = ConflictDetector.detect(snapshot, sheet)

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

      report = ConflictDetector.detect(snapshot, sheet)

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

      report = ConflictDetector.detect(snapshot, sheet)

      assert report.has_conflicts
      assert Enum.all?(report.conflicts, &(&1.type == :reference))
      assert Enum.any?(report.conflicts, &(&1.id == 123))
      assert Enum.any?(report.conflicts, &is_binary(&1.id))
    end

    test "does not accept an oversized asset ID through a portable catalog", %{project: project} do
      sheet = sheet_fixture(project)
      oversized_id = @max_pg_bigint + 1
      catalog_id = to_string(oversized_id)

      snapshot = %{
        "name" => "Test",
        "shortcut" => sheet.shortcut,
        "avatar_asset_id" => nil,
        "banner_asset_id" => oversized_id,
        "blocks" => [],
        "asset_blob_hashes" => %{catalog_id => String.duplicate("a", 64)},
        "asset_metadata" => %{
          catalog_id => %{
            "filename" => "oversized.png",
            "content_type" => "image/png",
            "size" => 123,
            "project_id" => project.id
          }
        }
      }

      report = ConflictDetector.detect(snapshot, sheet)

      assert [%{type: :asset, id: ^oversized_id}] = report.conflicts
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

      report = ConflictDetector.detect(snapshot, sheet)

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
