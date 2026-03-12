defmodule Storyarn.Versioning.Builders.SheetBuilderTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Versioning.Builders.SheetBuilder

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  setup do
    user = user_fixture()
    project = project_fixture(user)
    sheet = sheet_fixture(project)

    %{user: user, project: project, sheet: sheet}
  end

  describe "build_snapshot/1" do
    test "captures sheet metadata", %{sheet: sheet} do
      snapshot = SheetBuilder.build_snapshot(sheet)

      assert snapshot["name"] == sheet.name
      assert snapshot["shortcut"] == sheet.shortcut
      assert is_list(snapshot["blocks"])
    end

    test "captures block data", %{sheet: sheet} do
      _block =
        block_fixture(sheet, %{
          type: "number",
          config: %{"label" => "Health"},
          value: %{"content" => "100"}
        })

      snapshot = SheetBuilder.build_snapshot(sheet)
      assert length(snapshot["blocks"]) == 1

      [block] = snapshot["blocks"]
      assert block["type"] == "number"
      assert block["config"]["label"] == "Health"
      assert block["value"]["content"] == "100"
    end

    test "excludes block IDs from snapshot", %{sheet: sheet} do
      _block = block_fixture(sheet)
      snapshot = SheetBuilder.build_snapshot(sheet)
      [block] = snapshot["blocks"]
      refute Map.has_key?(block, "id")
    end
  end

  describe "restore_snapshot/3" do
    test "restores sheet metadata and blocks", %{sheet: sheet} do
      _b1 =
        block_fixture(sheet, %{
          type: "text",
          config: %{"label" => "Name"},
          value: %{"content" => "Alice"}
        })

      _b2 =
        block_fixture(sheet, %{
          type: "number",
          config: %{"label" => "Health"},
          value: %{"content" => "100"}
        })

      snapshot = SheetBuilder.build_snapshot(sheet)

      # Modify the sheet
      {:ok, modified_sheet} = Storyarn.Sheets.update_sheet(sheet, %{name: "Modified"})
      Storyarn.Sheets.delete_block(hd(Storyarn.Sheets.list_blocks(sheet.id)))

      # Restore from snapshot
      {:ok, restored} = SheetBuilder.restore_snapshot(modified_sheet, snapshot)

      assert restored.name == sheet.name
      blocks = Storyarn.Sheets.list_blocks(sheet.id)
      assert length(blocks) == 2
    end
  end

  describe "scan_references/1" do
    test "extracts asset and block inheritance refs" do
      snapshot = %{
        "avatar_asset_id" => 10,
        "banner_asset_id" => 20,
        "blocks" => [
          %{"inherited_from_block_id" => 30, "type" => "text", "position" => 0},
          %{"inherited_from_block_id" => nil, "type" => "number", "position" => 1}
        ]
      }

      refs = SheetBuilder.scan_references(snapshot)

      types_and_ids = Enum.map(refs, &{&1.type, &1.id}) |> Enum.sort()

      assert {:asset, 10} in types_and_ids
      assert {:asset, 20} in types_and_ids
      assert {:block, 30} in types_and_ids
      assert length(refs) == 3
    end

    test "skips nil references" do
      snapshot = %{
        "avatar_asset_id" => nil,
        "banner_asset_id" => nil,
        "blocks" => [
          %{"inherited_from_block_id" => nil, "type" => "text", "position" => 0}
        ]
      }

      refs = SheetBuilder.scan_references(snapshot)
      assert refs == []
    end
  end

  describe "diff_snapshots/2" do
    test "detects name change" do
      old = %{"name" => "Old", "shortcut" => "old", "blocks" => []}
      new = %{"name" => "New", "shortcut" => "old", "blocks" => []}

      diff = SheetBuilder.diff_snapshots(old, new)
      assert diff =~ "Renamed"
    end

    test "detects added blocks" do
      old = %{"name" => "S", "blocks" => []}
      new = %{"name" => "S", "blocks" => [%{"position" => 0, "type" => "text"}]}

      diff = SheetBuilder.diff_snapshots(old, new)
      assert diff =~ "Added"
    end

    test "reports no changes for identical snapshots" do
      snapshot = %{"name" => "S", "shortcut" => "s", "blocks" => []}
      diff = SheetBuilder.diff_snapshots(snapshot, snapshot)
      assert diff =~ "No changes"
    end
  end
end
