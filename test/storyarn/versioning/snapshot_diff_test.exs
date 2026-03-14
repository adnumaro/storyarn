defmodule Storyarn.Versioning.SnapshotDiffTest do
  use ExUnit.Case, async: true

  alias Storyarn.Versioning.SnapshotDiff

  describe "diff/3" do
    test "returns structured result for flow snapshots" do
      old = %{"name" => "Old", "shortcut" => "old", "nodes" => [], "connections" => []}
      new = %{"name" => "New", "shortcut" => "old", "nodes" => [], "connections" => []}

      result = SnapshotDiff.diff("flow", old, new)

      assert %{changes: [_change], stats: stats, has_changes: true} = result
      assert stats.modified == 1
      assert stats.added == 0
      assert stats.removed == 0
    end

    test "returns structured result for sheet snapshots" do
      old = %{"name" => "S", "blocks" => []}
      new = %{"name" => "S", "blocks" => [%{"position" => 0, "type" => "number"}]}

      result = SnapshotDiff.diff("sheet", old, new)

      assert %{stats: stats, has_changes: true} = result
      assert stats.added == 1
    end

    test "returns structured result for scene snapshots" do
      old = %{"name" => "S", "layers" => [], "connections" => []}
      layer = %{"position" => 0, "name" => "L1", "pins" => [], "zones" => [], "annotations" => []}
      new = %{"name" => "S", "layers" => [layer], "connections" => []}

      result = SnapshotDiff.diff("scene", old, new)

      assert %{has_changes: true} = result
      assert Enum.any?(result.changes, &(&1.category == :layer))
    end

    test "returns no changes for identical snapshots" do
      snapshot = %{"name" => "F", "shortcut" => "f", "nodes" => [], "connections" => []}

      result = SnapshotDiff.diff("flow", snapshot, snapshot)

      assert %{changes: [], stats: %{added: 0, modified: 0, removed: 0}, has_changes: false} =
               result
    end

    test "computes correct stats with mixed change types" do
      old = %{
        "name" => "F",
        "nodes" => [
          %{
            "type" => "dialogue",
            "original_id" => 1,
            "data" => %{"text" => "Hello"},
            "position_x" => 0,
            "position_y" => 0
          },
          %{
            "type" => "hub",
            "original_id" => 2,
            "data" => %{},
            "position_x" => 0,
            "position_y" => 0
          }
        ],
        "connections" => []
      }

      new = %{
        "name" => "F",
        "nodes" => [
          %{
            "type" => "dialogue",
            "original_id" => 1,
            "data" => %{"text" => "Goodbye"},
            "position_x" => 0,
            "position_y" => 0
          },
          %{
            "type" => "condition",
            "original_id" => 3,
            "data" => %{},
            "position_x" => 0,
            "position_y" => 0
          }
        ],
        "connections" => []
      }

      result = SnapshotDiff.diff("flow", old, new)

      assert result.stats.modified >= 1
      assert result.stats.added >= 1
      assert result.stats.removed >= 1
    end
  end

  describe "has_changes?/3" do
    test "returns false for identical snapshots" do
      snapshot = %{"name" => "S", "shortcut" => "s", "blocks" => []}

      refute SnapshotDiff.has_changes?("sheet", snapshot, snapshot)
    end

    test "returns true when properties differ" do
      old = %{"name" => "Old", "layers" => [], "connections" => []}
      new = %{"name" => "New", "layers" => [], "connections" => []}

      assert SnapshotDiff.has_changes?("scene", old, new)
    end
  end

  describe "format_summary/1" do
    test "returns no changes message for empty changes" do
      result =
        SnapshotDiff.format_summary(%{
          changes: [],
          stats: %{added: 0, modified: 0, removed: 0},
          has_changes: false
        })

      assert result =~ "No changes"
    end

    test "joins change details with commas" do
      changes = [
        %{category: :property, action: :modified, detail: "Renamed flow"},
        %{category: :node, action: :added, detail: "Added dialogue node"}
      ]

      result = SnapshotDiff.format_summary(changes)

      assert result == "Renamed flow, Added dialogue node"
    end

    test "accepts diff_result map" do
      diff_result = %{
        changes: [%{category: :property, action: :modified, detail: "Changed name"}],
        stats: %{added: 0, modified: 1, removed: 0},
        has_changes: true
      }

      assert SnapshotDiff.format_summary(diff_result) == "Changed name"
    end

    test "accepts raw change list" do
      changes = [%{category: :block, action: :added, detail: "Added text block"}]

      assert SnapshotDiff.format_summary(changes) == "Added text block"
    end

    test "deduplicates identical details with count" do
      changes = [
        %{category: :node, action: :added, detail: "Added dialogue node"},
        %{category: :node, action: :added, detail: "Added dialogue node"}
      ]

      assert SnapshotDiff.format_summary(changes) == "Added dialogue node (×2)"
    end
  end
end
