defmodule StoryarnWeb.FlowLive.Components.DebugPanelTest do
  use ExUnit.Case, async: true

  alias StoryarnWeb.FlowLive.Components.DebugPanel

  # ===========================================================================
  # Test helpers
  # ===========================================================================

  defp console_entry(node_id, message, opts \\ []) do
    %{
      ts: Keyword.get(opts, :ts, 0),
      level: Keyword.get(opts, :level, :info),
      node_id: node_id,
      node_label: Keyword.get(opts, :node_label, ""),
      message: message,
      rule_details: nil
    }
  end

  defp node(id, type, data \\ %{}) do
    %{id: id, type: type, data: data}
  end

  # Converts a list of node IDs or {node_id, depth} tuples to execution_log format
  defp log(entries) do
    Enum.map(entries, fn
      {id, depth} -> %{node_id: id, depth: depth}
      id when is_integer(id) -> %{node_id: id, depth: 0}
    end)
  end

  # ===========================================================================
  # build_path_entries/3
  # ===========================================================================

  describe "build_path_entries/3" do
    test "returns empty list for empty path" do
      assert DebugPanel.build_path_entries([], %{}, []) == []
    end

    test "builds entries with sequential step numbers" do
      nodes = %{
        1 => node(1, "entry"),
        2 => node(2, "hub"),
        3 => node(3, "exit")
      }

      console = [
        console_entry(nil, "Debug session started"),
        console_entry(1, "Execution started"),
        console_entry(2, "Hub — pass through"),
        console_entry(3, "Execution finished")
      ]

      entries = DebugPanel.build_path_entries(log([1, 2, 3]), nodes, console)

      assert length(entries) == 3
      assert Enum.at(entries, 0).step == 1
      assert Enum.at(entries, 1).step == 2
      assert Enum.at(entries, 2).step == 3
    end

    test "maps node types from nodes map" do
      nodes = %{
        1 => node(1, "entry"),
        2 => node(2, "dialogue", %{"text" => "Hello"}),
        3 => node(3, "exit")
      }

      entries = DebugPanel.build_path_entries(log([1, 2, 3]), nodes, [])

      assert Enum.at(entries, 0).type == "entry"
      assert Enum.at(entries, 1).type == "dialogue"
      assert Enum.at(entries, 2).type == "exit"
    end

    test "extracts node labels from text data, stripping HTML" do
      nodes = %{
        1 => node(1, "entry"),
        2 => node(2, "dialogue", %{"text" => "<p>Hello World</p>"})
      }

      entries = DebugPanel.build_path_entries(log([1, 2]), nodes, [])

      assert Enum.at(entries, 0).label == nil
      assert Enum.at(entries, 1).label == "Hello World"
    end

    test "matches console outcomes to path steps in order" do
      nodes = %{1 => node(1, "entry"), 2 => node(2, "exit")}

      console = [
        console_entry(nil, "Debug session started"),
        console_entry(1, "Execution started"),
        console_entry(2, "Execution finished")
      ]

      entries = DebugPanel.build_path_entries(log([1, 2]), nodes, console)

      assert Enum.at(entries, 0).outcome == "Execution started"
      assert Enum.at(entries, 1).outcome == "Execution finished"
    end

    test "marks only the last entry as current" do
      nodes = %{
        1 => node(1, "entry"),
        2 => node(2, "hub"),
        3 => node(3, "exit")
      }

      entries = DebugPanel.build_path_entries(log([1, 2, 3]), nodes, [])

      refute Enum.at(entries, 0).is_current
      refute Enum.at(entries, 1).is_current
      assert Enum.at(entries, 2).is_current
    end

    test "single entry is marked as current" do
      nodes = %{1 => node(1, "entry")}

      entries = DebugPanel.build_path_entries(log([1]), nodes, [])

      assert length(entries) == 1
      assert Enum.at(entries, 0).is_current
    end

    test "handles repeated node visits by consuming console entries in order" do
      nodes = %{
        1 => node(1, "entry"),
        2 => node(2, "hub"),
        3 => node(3, "hub")
      }

      console = [
        console_entry(nil, "Debug session started"),
        console_entry(1, "Execution started"),
        console_entry(2, "Hub — first visit"),
        console_entry(3, "Hub — pass through"),
        console_entry(2, "Hub — second visit")
      ]

      entries = DebugPanel.build_path_entries(log([1, 2, 3, 2]), nodes, console)

      assert length(entries) == 4
      assert Enum.at(entries, 0).outcome == "Execution started"
      assert Enum.at(entries, 1).outcome == "Hub — first visit"
      assert Enum.at(entries, 2).outcome == "Hub — pass through"
      assert Enum.at(entries, 3).outcome == "Hub — second visit"
    end

    test "handles missing nodes gracefully with unknown type" do
      entries = DebugPanel.build_path_entries(log([999]), %{}, [])

      assert length(entries) == 1
      assert Enum.at(entries, 0).type == "unknown"
      assert Enum.at(entries, 0).label == nil
    end

    test "returns nil outcome when no console entry matches" do
      nodes = %{1 => node(1, "entry")}

      entries = DebugPanel.build_path_entries(log([1]), nodes, [])

      assert Enum.at(entries, 0).outcome == nil
    end

    test "ignores console entries with nil node_id" do
      nodes = %{1 => node(1, "entry")}

      console = [
        console_entry(nil, "Debug session started"),
        console_entry(nil, "Stepped back")
      ]

      entries = DebugPanel.build_path_entries(log([1]), nodes, console)

      assert Enum.at(entries, 0).outcome == nil
    end

    test "truncates long labels to 30 characters" do
      long_text = String.duplicate("abcde ", 10)
      nodes = %{1 => node(1, "dialogue", %{"text" => long_text})}

      entries = DebugPanel.build_path_entries(log([1]), nodes, [])

      assert String.length(Enum.at(entries, 0).label) <= 30
    end

    test "returns nil label for nodes with empty text" do
      nodes = %{1 => node(1, "dialogue", %{"text" => ""})}

      entries = DebugPanel.build_path_entries(log([1]), nodes, [])

      assert Enum.at(entries, 0).label == nil
    end

    test "returns nil label for nodes with HTML-only text" do
      nodes = %{1 => node(1, "dialogue", %{"text" => "<p> </p>"})}

      entries = DebugPanel.build_path_entries(log([1]), nodes, [])

      assert Enum.at(entries, 0).label == nil
    end

    test "preserves node_id in each entry" do
      nodes = %{
        10 => node(10, "entry"),
        20 => node(20, "exit")
      }

      entries = DebugPanel.build_path_entries(log([10, 20]), nodes, [])

      assert Enum.at(entries, 0).node_id == 10
      assert Enum.at(entries, 1).node_id == 20
    end
  end

  # ===========================================================================
  # build_path_entries/3 — depth and flow separators
  # ===========================================================================

  describe "build_path_entries/3 with depth" do
    test "entries include depth field" do
      nodes = %{1 => node(1, "entry"), 2 => node(2, "hub")}

      entries = DebugPanel.build_path_entries(log([1, 2]), nodes, [])

      assert Enum.at(entries, 0).depth == 0
      assert Enum.at(entries, 1).depth == 0
    end

    test "sub-flow entries have depth 1" do
      nodes = %{
        1 => node(1, "entry"),
        10 => node(10, "entry"),
        11 => node(11, "exit")
      }

      execution_log = log([{1, 0}, {10, 1}, {11, 1}])
      entries = DebugPanel.build_path_entries(execution_log, nodes, [])

      # Should be: entry(depth 0), separator(:enter), entry(depth 1), exit(depth 1)
      normal = Enum.reject(entries, & &1[:separator])
      assert length(normal) == 3
      assert Enum.at(normal, 0).depth == 0
      assert Enum.at(normal, 1).depth == 1
      assert Enum.at(normal, 2).depth == 1
    end

    test "inserts enter separator when depth increases" do
      nodes = %{1 => node(1, "entry"), 10 => node(10, "entry")}

      execution_log = log([{1, 0}, {10, 1}])
      entries = DebugPanel.build_path_entries(execution_log, nodes, [])

      separators = Enum.filter(entries, & &1[:separator])
      assert length(separators) == 1
      assert hd(separators).direction == :enter
      assert hd(separators).depth == 1
    end

    test "inserts return separator when depth decreases" do
      nodes = %{
        1 => node(1, "entry"),
        10 => node(10, "entry"),
        2 => node(2, "hub")
      }

      execution_log = log([{1, 0}, {10, 1}, {2, 0}])
      entries = DebugPanel.build_path_entries(execution_log, nodes, [])

      separators = Enum.filter(entries, & &1[:separator])
      assert length(separators) == 2

      [enter_sep, return_sep] = separators
      assert enter_sep.direction == :enter
      assert return_sep.direction == :return
    end

    test "full cross-flow roundtrip produces enter and return separators" do
      # Parent: entry(1) -> subflow_node(2)
      # Sub-flow: entry(10) -> exit(11)
      # Parent continued: hub(3) -> exit(4)
      nodes = %{
        1 => node(1, "entry"),
        2 => node(2, "subflow"),
        10 => node(10, "entry"),
        11 => node(11, "exit"),
        3 => node(3, "hub"),
        4 => node(4, "exit")
      }

      execution_log = log([{1, 0}, {2, 0}, {10, 1}, {11, 1}, {3, 0}, {4, 0}])
      entries = DebugPanel.build_path_entries(execution_log, nodes, [])

      normal = Enum.reject(entries, & &1[:separator])
      separators = Enum.filter(entries, & &1[:separator])

      assert length(normal) == 6
      assert length(separators) == 2

      # Check order: ..., enter_sep, sub-flow entries, return_sep, parent entries
      types = Enum.map(entries, fn e -> if e[:separator], do: {:sep, e.direction}, else: {:node, e.depth} end)

      assert types == [
               {:node, 0},
               {:node, 0},
               {:sep, :enter},
               {:node, 1},
               {:node, 1},
               {:sep, :return},
               {:node, 0},
               {:node, 0}
             ]
    end

    test "nested sub-flows produce separators at each depth change" do
      # depth 0 -> 1 -> 2 -> 1 -> 0
      execution_log = log([{1, 0}, {10, 1}, {20, 2}, {11, 1}, {2, 0}])
      entries = DebugPanel.build_path_entries(execution_log, %{}, [])

      separators = Enum.filter(entries, & &1[:separator])
      assert length(separators) == 4

      directions = Enum.map(separators, & &1.direction)
      assert directions == [:enter, :enter, :return, :return]
    end

    test "no separators when all entries at same depth" do
      nodes = %{1 => node(1, "entry"), 2 => node(2, "exit")}

      entries = DebugPanel.build_path_entries(log([1, 2]), nodes, [])

      separators = Enum.filter(entries, & &1[:separator])
      assert separators == []
    end

    test "step numbers are continuous regardless of depth" do
      execution_log = log([{1, 0}, {10, 1}, {11, 1}, {2, 0}])
      entries = DebugPanel.build_path_entries(execution_log, %{}, [])

      normal = Enum.reject(entries, & &1[:separator])
      steps = Enum.map(normal, & &1.step)
      assert steps == [1, 2, 3, 4]
    end

    test "is_current is based on execution_log length, not entry count" do
      execution_log = log([{1, 0}, {10, 1}, {11, 1}])
      entries = DebugPanel.build_path_entries(execution_log, %{}, [])

      normal = Enum.reject(entries, & &1[:separator])
      current_entries = Enum.filter(normal, & &1.is_current)
      assert length(current_entries) == 1
      assert hd(current_entries).step == 3
    end
  end
end
