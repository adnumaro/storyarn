defmodule Storyarn.Versioning.SnapshotViewerTest do
  use ExUnit.Case, async: true

  alias Storyarn.Versioning.SnapshotViewer

  describe "serialize_flow/1" do
    test "produces flow canvas shape with negative IDs" do
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
            "source_pin" => "default",
            "target_pin" => "input",
            "label" => nil
          }
        ]
      }

      result = SnapshotViewer.serialize_flow(snapshot)

      assert result.id == -1
      assert result.name == "Test Flow"
      assert length(result.nodes) == 2
      assert length(result.connections) == 1

      [node1, node2] = result.nodes
      assert node1.id < 0
      assert node2.id < 0
      assert node1.type == "dialogue"
      assert node1.position == %{x: 100.0, y: 200.0}

      [conn] = result.connections
      assert conn.id < 0
      assert conn.source_node_id == node1.id
      assert conn.target_node_id == node2.id
      assert conn.source_pin == "default"
    end

    test "filters out connections with invalid node indexes" do
      snapshot = %{
        "nodes" => [%{"type" => "dialogue", "data" => %{}}],
        "connections" => [
          %{"source_node_index" => 0, "target_node_index" => 99}
        ]
      }

      result = SnapshotViewer.serialize_flow(snapshot)
      assert result.connections == []
    end

    test "resolves hub color hex" do
      snapshot = %{
        "nodes" => [
          %{"type" => "hub", "data" => %{"color" => "blue"}}
        ],
        "connections" => []
      }

      result = SnapshotViewer.serialize_flow(snapshot)
      [node] = result.nodes
      assert is_binary(node.data["color_hex"])
    end

    test "handles empty snapshot" do
      result = SnapshotViewer.serialize_flow(%{})
      assert result.nodes == []
      assert result.connections == []
    end
  end

  describe "serialize_scene/1" do
    test "produces scene canvas shape with can_edit: false" do
      snapshot = %{
        "name" => "Test Scene",
        "width" => 1920,
        "height" => 1080,
        "layers" => [
          %{
            "name" => "Layer 1",
            "pins" => [
              %{
                "position_x" => 100,
                "position_y" => 200,
                "label" => "Pin A"
              }
            ],
            "zones" => [
              %{
                "name" => "Zone A",
                "vertices" => [[0, 0], [100, 0], [100, 100]]
              }
            ],
            "annotations" => [
              %{"text" => "Note", "position_x" => 50, "position_y" => 50}
            ]
          }
        ],
        "connections" => [],
        "asset_metadata" => %{}
      }

      result = SnapshotViewer.serialize_scene(snapshot)

      assert result.can_edit == false
      assert result.name == "Test Scene"
      assert result.width == 1920
      assert length(result.layers) == 1
      assert length(result.pins) == 1
      assert length(result.zones) == 1
      assert length(result.annotations) == 1

      [layer] = result.layers
      assert layer.id < 0
      assert layer.name == "Layer 1"

      [pin] = result.pins
      assert pin.id < 0
      assert pin.label == "Pin A"
      assert pin.layer_id == layer.id

      [zone] = result.zones
      assert zone.id < 0
      assert zone.name == "Zone A"

      [ann] = result.annotations
      assert ann.id < 0
      assert ann.text == "Note"
    end

    test "resolves scene connections via pin_id_map" do
      snapshot = %{
        "layers" => [
          %{
            "name" => "L1",
            "pins" => [
              %{"position_x" => 0, "position_y" => 0, "label" => "A"},
              %{"position_x" => 100, "position_y" => 100, "label" => "B"}
            ],
            "zones" => [],
            "annotations" => []
          }
        ],
        "connections" => [
          %{
            "from_layer_index" => 0,
            "from_pin_index" => 0,
            "to_layer_index" => 0,
            "to_pin_index" => 1
          }
        ],
        "asset_metadata" => %{}
      }

      result = SnapshotViewer.serialize_scene(snapshot)

      assert length(result.connections) == 1
      [conn] = result.connections
      assert conn.from_pin_id < 0
      assert conn.to_pin_id < 0
      assert conn.from_pin_id != conn.to_pin_id
    end

    test "resolves asset URLs from metadata" do
      snapshot = %{
        "background_asset_id" => 42,
        "layers" => [
          %{
            "name" => "L1",
            "pins" => [%{"icon_asset_id" => 7, "position_x" => 0, "position_y" => 0}],
            "zones" => [],
            "annotations" => []
          }
        ],
        "connections" => [],
        "asset_metadata" => %{
          "42" => %{"url" => "https://example.com/bg.png"},
          "7" => %{"url" => "https://example.com/icon.png"}
        }
      }

      result = SnapshotViewer.serialize_scene(snapshot)
      assert result.background_url == "https://example.com/bg.png"

      [pin] = result.pins
      assert pin.icon_asset_url == "https://example.com/icon.png"
    end

    test "handles empty scene" do
      result = SnapshotViewer.serialize_scene(%{})
      assert result.layers == []
      assert result.pins == []
      assert result.connections == []
      assert result.can_edit == false
    end
  end

  describe "serialize_sheet/1" do
    test "produces block list with negative IDs" do
      snapshot = %{
        "blocks" => [
          %{
            "type" => "text",
            "position" => 0,
            "config" => %{"label" => "Name"},
            "value" => %{"content" => "Hello"},
            "variable_name" => "name",
            "is_constant" => false,
            "scope" => "self",
            "required" => true
          },
          %{
            "type" => "number",
            "position" => 1,
            "config" => %{},
            "value" => %{"number" => 42},
            "variable_name" => "health"
          }
        ]
      }

      result = SnapshotViewer.serialize_sheet(snapshot)

      assert length(result) == 2

      [block1, block2] = result
      assert block1.id < 0
      assert block1.type == "text"
      assert block1.value == %{"content" => "Hello"}
      assert block1.variable_name == "name"
      assert block1.required == true

      assert block2.id < 0
      assert block2.type == "number"
      assert block2.variable_name == "health"
    end

    test "serializes table data" do
      snapshot = %{
        "blocks" => [
          %{
            "type" => "table",
            "config" => %{},
            "value" => %{},
            "table_data" => %{
              "columns" => [
                %{"name" => "Col1", "slug" => "col1", "type" => "text"}
              ],
              "rows" => [
                %{"name" => "Row1", "slug" => "row1", "cells" => %{"col1" => %{"text" => "hi"}}}
              ]
            }
          }
        ]
      }

      result = SnapshotViewer.serialize_sheet(snapshot)
      [block] = result

      assert length(block.table_columns) == 1
      assert length(block.table_rows) == 1
      assert hd(block.table_columns).name == "Col1"
      assert hd(block.table_rows).cells == %{"col1" => %{"text" => "hi"}}
    end

    test "handles empty sheet" do
      result = SnapshotViewer.serialize_sheet(%{})
      assert result == []
    end

    test "applies defaults for missing fields" do
      snapshot = %{
        "blocks" => [%{"type" => "text"}]
      }

      result = SnapshotViewer.serialize_sheet(snapshot)
      [block] = result

      assert block.config == %{}
      assert block.value == %{}
      assert block.is_constant == false
      assert block.scope == "self"
      assert block.required == false
      assert block.table_columns == []
      assert block.table_rows == []
    end
  end
end
