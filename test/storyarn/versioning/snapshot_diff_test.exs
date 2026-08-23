defmodule Storyarn.Versioning.SnapshotDiffTest do
  use ExUnit.Case, async: true

  alias Storyarn.Versioning.SnapshotDiff

  describe "diff/3" do
    test "returns structured result for sheet snapshots" do
      old = %{"name" => "S", "blocks" => []}
      new = %{"name" => "S", "blocks" => [%{"position" => 0, "type" => "number"}]}

      result = SnapshotDiff.diff("sheet", old, new)

      assert %{stats: stats, has_changes: true} = result
      assert stats.added == 1
    end

    test "returns structured result for sheet property changes" do
      old = %{"name" => "Old", "shortcut" => "sheet", "blocks" => []}
      new = %{"name" => "New", "shortcut" => "sheet", "blocks" => []}

      result = SnapshotDiff.diff("sheet", old, new)

      assert %{has_changes: true} = result
      assert Enum.any?(result.changes, &(&1.category == :property))
    end
  end

  describe "has_changes?/3" do
    test "returns false for identical snapshots" do
      snapshot = %{"name" => "S", "shortcut" => "s", "blocks" => []}

      refute SnapshotDiff.has_changes?("sheet", snapshot, snapshot)
    end

    test "returns true when properties differ" do
      old = %{"name" => "Old", "shortcut" => "sheet", "blocks" => []}
      new = %{"name" => "New", "shortcut" => "sheet", "blocks" => []}

      assert SnapshotDiff.has_changes?("sheet", old, new)
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
