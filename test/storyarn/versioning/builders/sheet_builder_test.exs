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

  describe "table data in snapshots" do
    test "captures table columns and rows in snapshot", %{sheet: sheet} do
      table_block = table_block_fixture(sheet)
      _col = table_column_fixture(table_block, %{name: "Age", type: "number"})

      [default_row] = Storyarn.Sheets.list_table_rows(table_block.id)

      Storyarn.Sheets.update_table_cell(default_row, "age", "25")

      snapshot = SheetBuilder.build_snapshot(sheet)

      table_snap =
        Enum.find(snapshot["blocks"], &(&1["type"] == "table"))

      assert is_map(table_snap["table_data"])
      assert table_snap["table_data"]["columns"] != []
      assert table_snap["table_data"]["rows"] != []

      age_col = Enum.find(table_snap["table_data"]["columns"], &(&1["name"] == "Age"))
      assert age_col["type"] == "number"
      assert age_col["slug"] == "age"
    end

    test "restores table columns and rows", %{sheet: sheet} do
      table_block = table_block_fixture(sheet)
      col = table_column_fixture(table_block, %{name: "Score", type: "number"})

      [default_row] = Storyarn.Sheets.list_table_rows(table_block.id)

      Storyarn.Sheets.update_table_cell(default_row, col.slug, "99")

      snapshot = SheetBuilder.build_snapshot(sheet)

      # Modify table data
      Storyarn.Sheets.delete_table_column(col)

      # Restore
      {:ok, _restored} = SheetBuilder.restore_snapshot(sheet, snapshot)

      # Verify table data was restored
      blocks = Storyarn.Sheets.list_blocks(sheet.id)
      table = Enum.find(blocks, &(&1.type == "table"))
      assert table != nil

      columns = Storyarn.Sheets.list_table_columns(table.id)
      assert Enum.any?(columns, &(&1.name == "Score"))

      rows = Storyarn.Sheets.list_table_rows(table.id)
      assert rows != []
      row = hd(rows)
      assert row.cells["score"] == "99"
    end

    test "non-table blocks have no table_data key", %{sheet: sheet} do
      _block = block_fixture(sheet, %{type: "text", config: %{"label" => "Name"}})
      snapshot = SheetBuilder.build_snapshot(sheet)

      text_snap = Enum.find(snapshot["blocks"], &(&1["type"] == "text"))
      refute Map.has_key?(text_snap, "table_data")
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

      changes = SheetBuilder.diff_snapshots(old, new)
      assert [%{category: :property, action: :modified, detail: detail}] = changes
      assert detail =~ "Renamed"
    end

    test "detects added blocks" do
      old = %{"name" => "S", "blocks" => []}
      new = %{"name" => "S", "blocks" => [%{"position" => 0, "type" => "text"}]}

      changes = SheetBuilder.diff_snapshots(old, new)
      assert Enum.any?(changes, &(&1.category == :block && &1.action == :added))
    end

    test "detects removed blocks" do
      old = %{
        "name" => "S",
        "blocks" => [%{"position" => 0, "type" => "text", "variable_name" => "name"}]
      }

      new = %{"name" => "S", "blocks" => []}

      changes = SheetBuilder.diff_snapshots(old, new)
      assert Enum.any?(changes, &(&1.category == :block && &1.action == :removed))
    end

    test "detects modified blocks by variable_name" do
      old = %{
        "name" => "S",
        "blocks" => [
          %{
            "position" => 0,
            "type" => "text",
            "variable_name" => "health",
            "value" => %{"content" => "100"}
          }
        ]
      }

      new = %{
        "name" => "S",
        "blocks" => [
          %{
            "position" => 0,
            "type" => "text",
            "variable_name" => "health",
            "value" => %{"content" => "200"}
          }
        ]
      }

      changes = SheetBuilder.diff_snapshots(old, new)
      assert Enum.any?(changes, &(&1.category == :block && &1.action == :modified))
    end

    test "returns empty list for identical snapshots" do
      snapshot = %{"name" => "S", "shortcut" => "s", "blocks" => []}
      assert SheetBuilder.diff_snapshots(snapshot, snapshot) == []
    end
  end
end
