defmodule Storyarn.Versioning.SnapshotViewerTest do
  use ExUnit.Case, async: true

  alias Storyarn.Versioning.SnapshotViewer

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
                "vertices" => [[0, 0], [100, 0], [100, 100]],
                "action_type" => "walkable",
                "is_walkable" => true
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
      assert zone.action_type == "walkable"
      assert zone.is_walkable == true

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

    test "keeps free scene routes and route stop metadata" do
      snapshot = %{
        "layers" => [],
        "connections" => [
          %{
            "from_layer_index" => nil,
            "from_pin_index" => nil,
            "to_layer_index" => nil,
            "to_pin_index" => nil,
            "waypoints" => [
              %{"x" => 10.0, "y" => 10.0, "stop" => true, "pauseMs" => 500},
              %{"x" => 90.0, "y" => 90.0, "stop" => true}
            ],
            "from_stop" => false,
            "to_stop" => true,
            "from_pause_ms" => nil,
            "to_pause_ms" => 1200
          }
        ],
        "asset_metadata" => %{}
      }

      result = SnapshotViewer.serialize_scene(snapshot)

      assert length(result.connections) == 1
      [conn] = result.connections
      assert is_nil(conn.from_pin_id)
      assert is_nil(conn.to_pin_id)
      assert length(conn.waypoints) == 2
      assert conn.from_stop == false
      assert conn.to_stop == true
      assert conn.from_pause_ms == nil
      assert conn.to_pause_ms == 1200
    end

    test "keeps pin to free scene routes" do
      snapshot = %{
        "layers" => [
          %{
            "name" => "L1",
            "pins" => [%{"position_x" => 0, "position_y" => 0, "label" => "A"}],
            "zones" => [],
            "annotations" => []
          }
        ],
        "connections" => [
          %{
            "from_layer_index" => 0,
            "from_pin_index" => 0,
            "to_layer_index" => nil,
            "to_pin_index" => nil,
            "waypoints" => [%{"x" => 60.0, "y" => 60.0}]
          }
        ],
        "asset_metadata" => %{}
      }

      result = SnapshotViewer.serialize_scene(snapshot)

      assert length(result.connections) == 1
      [conn] = result.connections
      assert conn.from_pin_id < 0
      assert is_nil(conn.to_pin_id)
      assert conn.waypoints == [%{"x" => 60.0, "y" => 60.0}]
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
