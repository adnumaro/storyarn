defmodule Storyarn.Flows.Versioning.FlowSnapshotDiffTest do
  use ExUnit.Case, async: true

  alias Storyarn.Flows.Versioning.FlowSnapshot

  describe "diff_snapshots/2" do
    test "detects name change" do
      old = %{"name" => "Old", "shortcut" => "old", "nodes" => [], "connections" => []}
      new = %{"name" => "New", "shortcut" => "old", "nodes" => [], "connections" => []}

      changes = FlowSnapshot.diff_snapshots(old, new)
      assert [%{category: :property, action: :modified, detail: detail}] = changes
      assert detail =~ "Renamed"
    end

    test "detects added nodes" do
      old = %{"name" => "F", "nodes" => [], "connections" => []}
      new = %{"name" => "F", "nodes" => [%{"type" => "dialogue"}], "connections" => []}

      changes = FlowSnapshot.diff_snapshots(old, new)
      assert Enum.any?(changes, &(&1.category == :node && &1.action == :added))
    end

    test "detects removed nodes" do
      old = %{"name" => "F", "nodes" => [%{"type" => "hub"}], "connections" => []}
      new = %{"name" => "F", "nodes" => [], "connections" => []}

      changes = FlowSnapshot.diff_snapshots(old, new)
      assert Enum.any?(changes, &(&1.category == :node && &1.action == :removed))
    end

    test "detects modified nodes" do
      node_old = %{
        "type" => "dialogue",
        "original_id" => 1,
        "data" => %{"text" => "Hello"},
        "position_x" => 0,
        "position_y" => 0
      }

      node_new = %{
        "type" => "dialogue",
        "original_id" => 1,
        "data" => %{"text" => "Goodbye"},
        "position_x" => 0,
        "position_y" => 0
      }

      old = %{"name" => "F", "nodes" => [node_old], "connections" => []}
      new = %{"name" => "F", "nodes" => [node_new], "connections" => []}

      changes = FlowSnapshot.diff_snapshots(old, new)
      assert Enum.any?(changes, &(&1.category == :node && &1.action == :modified))
    end

    test "ignores position-only changes" do
      node_old = %{
        "type" => "dialogue",
        "original_id" => 1,
        "data" => %{"text" => "Hi"},
        "position_x" => 0,
        "position_y" => 0
      }

      node_new = %{
        "type" => "dialogue",
        "original_id" => 1,
        "data" => %{"text" => "Hi"},
        "position_x" => 100,
        "position_y" => 200
      }

      old = %{"name" => "F", "nodes" => [node_old], "connections" => []}
      new = %{"name" => "F", "nodes" => [node_new], "connections" => []}

      changes = FlowSnapshot.diff_snapshots(old, new)
      assert changes == []
    end

    test "returns empty list for identical snapshots" do
      snapshot = %{"name" => "F", "shortcut" => "f", "nodes" => [], "connections" => []}
      assert FlowSnapshot.diff_snapshots(snapshot, snapshot) == []
    end

    test "reports mixed changes through the Flow-owned diff contract" do
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

      changes = FlowSnapshot.diff_snapshots(old, new)
      actions = Enum.frequencies_by(changes, & &1.action)

      assert actions.modified >= 1
      assert actions.added >= 1
      assert actions.removed >= 1
    end

    test "detects connection changes" do
      conn = %{
        "source_node_index" => 0,
        "target_node_index" => 1,
        "source_pin" => "out",
        "target_pin" => "in",
        "label" => nil
      }

      old = %{"name" => "F", "nodes" => [], "connections" => []}
      new = %{"name" => "F", "nodes" => [], "connections" => [conn]}

      changes = FlowSnapshot.diff_snapshots(old, new)
      assert Enum.any?(changes, &(&1.category == :connection && &1.action == :added))
    end
  end
end
