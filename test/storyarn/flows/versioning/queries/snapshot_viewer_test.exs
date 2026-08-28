defmodule Storyarn.Flows.Versioning.SnapshotViewerTest do
  use ExUnit.Case, async: true

  alias Storyarn.Flows.Versioning

  test "produces the read-only Flow canvas shape with stable negative IDs" do
    snapshot = %{
      "name" => "Test Flow",
      "nodes" => [
        %{"type" => "dialogue", "position_x" => 100.0, "position_y" => 200.0, "data" => %{}},
        %{"type" => "hub", "position_x" => 300.0, "position_y" => 400.0, "data" => %{}}
      ],
      "connections" => [
        %{
          "source_node_index" => 0,
          "target_node_index" => 1,
          "source_pin" => "output",
          "target_pin" => "input",
          "label" => nil
        }
      ]
    }

    result = Versioning.serialize_version_snapshot(snapshot)

    assert result.id == -1
    assert result.name == "Test Flow"
    assert length(result.nodes) == 2
    assert length(result.connections) == 1

    [first_node, second_node] = result.nodes
    assert first_node.id < 0
    assert second_node.id < 0
    assert first_node.type == "dialogue"
    assert first_node.position == %{x: 100.0, y: 200.0}

    [connection] = result.connections
    assert connection.id < 0
    assert connection.source_node_id == first_node.id
    assert connection.target_node_id == second_node.id
    assert connection.source_pin == "output"
  end

  test "filters connections whose snapshot indexes do not resolve" do
    snapshot = %{
      "nodes" => [%{"type" => "dialogue", "data" => %{}}],
      "connections" => [%{"source_node_index" => 0, "target_node_index" => 99}]
    }

    assert Versioning.serialize_version_snapshot(snapshot).connections == []
  end

  test "resolves Flow-owned hub colors" do
    snapshot = %{
      "nodes" => [%{"type" => "hub", "data" => %{"color" => "#3b82f6"}}],
      "connections" => []
    }

    [node] = Versioning.serialize_version_snapshot(snapshot).nodes
    assert node.data["color_hex"] == "#3b82f6"
  end

  test "handles an empty snapshot" do
    result = Versioning.serialize_version_snapshot(%{})
    assert result.nodes == []
    assert result.connections == []
  end
end
