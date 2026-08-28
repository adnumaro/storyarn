defmodule StoryarnWeb.SceneLive.VersionSnapshotSerializerTest do
  use ExUnit.Case, async: true

  alias StoryarnWeb.PrivateMedia
  alias StoryarnWeb.SceneLive.VersionSnapshotSerializer

  @project_id 9

  test "produces the read-only Scene surface shape" do
    snapshot = %{
      "name" => "Test Scene",
      "width" => 1920,
      "height" => 1080,
      "layers" => [
        %{
          "name" => "Layer 1",
          "pins" => [%{"position_x" => 100, "position_y" => 200, "label" => "Pin A"}],
          "zones" => [
            %{
              "name" => "Zone A",
              "vertices" => [[0, 0], [100, 0], [100, 100]],
              "action_type" => "walkable",
              "is_walkable" => true
            }
          ],
          "annotations" => [%{"text" => "Note", "position_x" => 50, "position_y" => 50}]
        }
      ],
      "connections" => [],
      "asset_metadata" => %{}
    }

    result = VersionSnapshotSerializer.serialize(snapshot, @project_id)

    assert result.can_edit == false
    assert result.name == "Test Scene"
    assert result.width == 1920
    assert [layer] = result.layers
    assert layer.id < 0
    assert layer.name == "Layer 1"
    assert [pin] = result.pins
    assert pin.id < 0
    assert pin.label == "Pin A"
    assert pin.layer_id == layer.id
    assert [zone] = result.zones
    assert zone.name == "Zone A"
    assert zone.action_type == "walkable"
    assert zone.is_walkable == true
    assert zone.label_mode == "text"
    assert zone.label_font_size == 12
    assert [annotation] = result.annotations
    assert annotation.text == "Note"
  end

  test "resolves connections through snapshot pin coordinates" do
    snapshot = %{
      "layers" => [
        %{
          "name" => "L1",
          "pins" => [
            %{"position_x" => 0, "position_y" => 0, "label" => "A"},
            %{"position_x" => 100, "position_y" => 100, "label" => "B"}
          ]
        }
      ],
      "connections" => [
        %{
          "from_layer_index" => 0,
          "from_pin_index" => 0,
          "to_layer_index" => 0,
          "to_pin_index" => 1
        }
      ]
    }

    result = VersionSnapshotSerializer.serialize(snapshot, @project_id)

    assert [connection] = result.connections
    assert connection.from_pin_id < 0
    assert connection.to_pin_id < 0
    refute connection.from_pin_id == connection.to_pin_id
  end

  test "preserves free routes and route stop metadata" do
    snapshot = %{
      "layers" => [],
      "connections" => [
        %{
          "waypoints" => [
            %{"x" => 10.0, "y" => 10.0, "stop" => true, "pauseMs" => 500},
            %{"x" => 90.0, "y" => 90.0, "stop" => true}
          ],
          "from_stop" => false,
          "to_stop" => true,
          "to_pause_ms" => 1200
        }
      ]
    }

    result = VersionSnapshotSerializer.serialize(snapshot, @project_id)

    assert [connection] = result.connections
    assert is_nil(connection.from_pin_id)
    assert is_nil(connection.to_pin_id)
    assert length(connection.waypoints) == 2
    assert connection.from_stop == false
    assert connection.to_stop == true
    assert connection.to_pause_ms == 1200
  end

  test "keeps a route from a pin to a free waypoint" do
    snapshot = %{
      "layers" => [%{"pins" => [%{"position_x" => 0, "position_y" => 0}]}],
      "connections" => [
        %{
          "from_layer_index" => 0,
          "from_pin_index" => 0,
          "waypoints" => [%{"x" => 60.0, "y" => 60.0}]
        }
      ]
    }

    result = VersionSnapshotSerializer.serialize(snapshot, @project_id)

    assert [connection] = result.connections
    assert connection.from_pin_id < 0
    assert is_nil(connection.to_pin_id)
    assert connection.waypoints == [%{"x" => 60.0, "y" => 60.0}]
  end

  test "maps snapshot assets to private same-origin URLs and preserves zone icon presentation" do
    background_key = "projects/#{@project_id}/assets/bg.png"
    pin_icon_key = "projects/#{@project_id}/blobs/icon.png"
    zone_icon_key = "projects/#{@project_id}/assets/zone.png"

    snapshot = %{
      "background_asset_id" => 42,
      "layers" => [
        %{
          "pins" => [%{"icon_asset_id" => 7}],
          "zones" => [
            %{
              "label_mode" => "both",
              "label_font_family" => "serif",
              "label_font_size" => 18,
              "label_font_style" => "italic",
              "label_font_weight" => "700",
              "label_icon_asset_id" => 8
            }
          ]
        }
      ],
      "asset_metadata" => %{
        "42" => %{"key" => background_key, "url" => "https://storage.example/private-bg.png"},
        "7" => %{"key" => pin_icon_key, "url" => "https://storage.example/private-pin.png"},
        "8" => %{"key" => zone_icon_key, "url" => "https://storage.example/private-zone.png"}
      }
    }

    result = VersionSnapshotSerializer.serialize(snapshot, @project_id)

    assert result.background_url == PrivateMedia.project_file_url(@project_id, background_key)
    assert [pin] = result.pins
    assert pin.icon_asset_url == PrivateMedia.project_file_url(@project_id, pin_icon_key)
    assert [zone] = result.zones
    assert zone.label_mode == "both"
    assert zone.label_font_family == "serif"
    assert zone.label_font_size == 18
    assert zone.label_font_style == "italic"
    assert zone.label_font_weight == "700"
    assert zone.label_icon_asset_id == 8
    assert zone.label_icon_asset_url == PrivateMedia.project_file_url(@project_id, zone_icon_key)
    refute inspect(result) =~ "storage.example"
  end

  test "handles an empty Scene snapshot" do
    result = VersionSnapshotSerializer.serialize(%{}, @project_id)

    assert result.layers == []
    assert result.pins == []
    assert result.connections == []
    assert result.can_edit == false
  end
end
