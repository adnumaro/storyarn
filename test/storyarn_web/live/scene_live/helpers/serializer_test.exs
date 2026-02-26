defmodule StoryarnWeb.SceneLive.Helpers.SerializerTest do
  use ExUnit.Case, async: true

  alias StoryarnWeb.SceneLive.Helpers.Serializer

  # ── serialize_layer/1 ────────────────────────────────────────────────

  describe "serialize_layer/1" do
    test "serializes all expected fields" do
      layer = %{
        id: 1,
        name: "Background",
        visible: true,
        is_default: true,
        position: 0,
        fog_enabled: false,
        fog_color: "#000000",
        fog_opacity: 0.5
      }

      result = Serializer.serialize_layer(layer)

      assert result == %{
               id: 1,
               name: "Background",
               visible: true,
               is_default: true,
               position: 0,
               fog_enabled: false,
               fog_color: "#000000",
               fog_opacity: 0.5
             }
    end
  end

  # ── serialize_pin/1 ─────────────────────────────────────────────────

  describe "serialize_pin/1" do
    test "serializes pin with all fields including computed avatar_url" do
      pin = %{
        id: 10,
        position_x: 100.0,
        position_y: 200.0,
        pin_type: "default",
        icon: "map-pin",
        color: "#ff0000",
        opacity: 1.0,
        label: "Castle",
        tooltip: "Enter the castle",
        size: 24,
        layer_id: 1,
        target_type: "flow",
        target_id: 5,
        sheet_id: 3,
        sheet: %{avatar_asset: %{url: "https://cdn.test/avatar.png"}},
        icon_asset: nil,
        position: 0,
        locked: false,
        action_type: "navigate",
        action_data: %{"scene_id" => 2},
        condition: nil,
        condition_effect: "hide"
      }

      result = Serializer.serialize_pin(pin)

      assert result.id == 10
      assert result.label == "Castle"
      assert result.avatar_url == "https://cdn.test/avatar.png"
      assert result.icon_asset_url == nil
      assert result.action_type == "navigate"
      assert result.locked == false
    end

    test "handles nil optional fields with defaults" do
      pin = %{
        id: 1,
        position_x: 0.0,
        position_y: 0.0,
        pin_type: "default",
        icon: nil,
        color: nil,
        opacity: nil,
        label: nil,
        tooltip: nil,
        size: nil,
        layer_id: nil,
        target_type: nil,
        target_id: nil,
        sheet_id: nil,
        sheet: nil,
        icon_asset: nil,
        position: nil,
        locked: nil,
        action_type: nil,
        action_data: nil,
        condition: nil,
        condition_effect: nil
      }

      result = Serializer.serialize_pin(pin)

      assert result.locked == false
      assert result.action_type == "none"
      assert result.action_data == %{}
      assert result.condition_effect == "hide"
      assert result.avatar_url == nil
      assert result.icon_asset_url == nil
    end
  end

  # ── serialize_zone/1 ────────────────────────────────────────────────

  describe "serialize_zone/1" do
    test "serializes zone with all fields" do
      zone = %{
        id: 5,
        name: "Forest",
        vertices: [[0, 0], [100, 0], [100, 100]],
        fill_color: "#00ff00",
        border_color: "#000000",
        border_width: 2,
        border_style: "solid",
        opacity: 0.8,
        tooltip: "Dense forest",
        layer_id: 1,
        target_type: nil,
        target_id: nil,
        position: 0,
        locked: false,
        action_type: "navigate",
        action_data: %{},
        condition: nil,
        condition_effect: "hide"
      }

      result = Serializer.serialize_zone(zone)

      assert result.id == 5
      assert result.name == "Forest"
      assert result.vertices == [[0, 0], [100, 0], [100, 100]]
      assert result.locked == false
    end

    test "defaults locked to false when nil" do
      zone = %{
        id: 1,
        name: "Z",
        vertices: [],
        fill_color: nil,
        border_color: nil,
        border_width: nil,
        border_style: nil,
        opacity: nil,
        tooltip: nil,
        layer_id: nil,
        target_type: nil,
        target_id: nil,
        position: nil,
        locked: nil,
        action_type: nil,
        action_data: nil,
        condition: nil,
        condition_effect: nil
      }

      result = Serializer.serialize_zone(zone)
      assert result.locked == false
      assert result.condition_effect == "hide"
    end
  end

  # ── serialize_connection/1 ──────────────────────────────────────────

  describe "serialize_connection/1" do
    test "serializes connection with all fields" do
      conn = %{
        id: 7,
        from_pin_id: 1,
        to_pin_id: 2,
        line_style: "dashed",
        line_width: 3,
        color: "#0000ff",
        label: "Path",
        show_label: true,
        bidirectional: false,
        waypoints: [[50, 50]]
      }

      result = Serializer.serialize_connection(conn)

      assert result == %{
               id: 7,
               from_pin_id: 1,
               to_pin_id: 2,
               line_style: "dashed",
               line_width: 3,
               color: "#0000ff",
               label: "Path",
               show_label: true,
               bidirectional: false,
               waypoints: [[50, 50]]
             }
    end

    test "defaults waypoints to empty list when nil" do
      conn = %{
        id: 1,
        from_pin_id: 1,
        to_pin_id: 2,
        line_style: "solid",
        line_width: 1,
        color: "#000",
        label: nil,
        show_label: false,
        bidirectional: false,
        waypoints: nil
      }

      result = Serializer.serialize_connection(conn)
      assert result.waypoints == []
    end
  end

  # ── serialize_annotation/1 ──────────────────────────────────────────

  describe "serialize_annotation/1" do
    test "serializes annotation with all fields" do
      annotation = %{
        id: 3,
        text: "Important marker",
        position_x: 150.0,
        position_y: 250.0,
        font_size: 16,
        color: "#333333",
        layer_id: 1,
        position: 0,
        locked: true
      }

      result = Serializer.serialize_annotation(annotation)

      assert result == %{
               id: 3,
               text: "Important marker",
               position_x: 150.0,
               position_y: 250.0,
               font_size: 16,
               color: "#333333",
               layer_id: 1,
               position: 0,
               locked: true
             }
    end

    test "defaults locked to false when nil" do
      annotation = %{
        id: 1,
        text: "Note",
        position_x: 0.0,
        position_y: 0.0,
        font_size: 12,
        color: nil,
        layer_id: nil,
        position: nil,
        locked: nil
      }

      result = Serializer.serialize_annotation(annotation)
      assert result.locked == false
    end
  end

  # ── background_url/1 ────────────────────────────────────────────────

  describe "background_url/1" do
    test "extracts url from background_asset" do
      scene = %{background_asset: %{url: "https://cdn.test/bg.png"}}
      assert Serializer.background_url(scene) == "https://cdn.test/bg.png"
    end

    test "returns nil for nil background_asset" do
      assert Serializer.background_url(%{background_asset: nil}) == nil
    end

    test "returns nil for missing background_asset" do
      assert Serializer.background_url(%{}) == nil
    end

    test "returns nil for nil url" do
      assert Serializer.background_url(%{background_asset: %{url: nil}}) == nil
    end
  end

  # ── pin_avatar_url/1 ────────────────────────────────────────────────

  describe "pin_avatar_url/1" do
    test "extracts url from nested sheet avatar" do
      pin = %{sheet: %{avatar_asset: %{url: "https://cdn.test/avatar.png"}}}
      assert Serializer.pin_avatar_url(pin) == "https://cdn.test/avatar.png"
    end

    test "returns nil for nil sheet" do
      assert Serializer.pin_avatar_url(%{sheet: nil}) == nil
    end

    test "returns nil for nil avatar_asset" do
      assert Serializer.pin_avatar_url(%{sheet: %{avatar_asset: nil}}) == nil
    end

    test "returns nil for non-binary url" do
      assert Serializer.pin_avatar_url(%{sheet: %{avatar_asset: %{url: nil}}}) == nil
    end
  end

  # ── pin_icon_asset_url/1 ────────────────────────────────────────────

  describe "pin_icon_asset_url/1" do
    test "extracts url from icon_asset" do
      pin = %{icon_asset: %{url: "https://cdn.test/icon.png"}}
      assert Serializer.pin_icon_asset_url(pin) == "https://cdn.test/icon.png"
    end

    test "returns nil for nil icon_asset" do
      assert Serializer.pin_icon_asset_url(%{icon_asset: nil}) == nil
    end

    test "returns nil when no icon_asset key" do
      assert Serializer.pin_icon_asset_url(%{}) == nil
    end
  end

  # ── zone_error_message/1 ────────────────────────────────────────────

  describe "zone_error_message/1" do
    test "extracts vertices error from changeset" do
      changeset = %Ecto.Changeset{
        errors: [vertices: {"must have at least 3 vertices", []}],
        valid?: false
      }

      result = Serializer.zone_error_message(changeset)

      assert is_binary(result)
      assert result =~ "3 vertices"
    end

    test "returns generic message for changeset without vertices error" do
      changeset = %Ecto.Changeset{
        errors: [name: {"is required", []}],
        valid?: false
      }

      result = Serializer.zone_error_message(changeset)
      assert is_binary(result)
    end

    test "returns generic message for non-changeset" do
      result = Serializer.zone_error_message(:some_error)
      assert is_binary(result)
    end
  end

  # ── default_layer_id/1 ──────────────────────────────────────────────

  describe "default_layer_id/1" do
    test "returns nil for nil" do
      assert Serializer.default_layer_id(nil) == nil
    end

    test "returns nil for empty list" do
      assert Serializer.default_layer_id([]) == nil
    end

    test "returns id of default layer" do
      layers = [
        %{id: 1, is_default: false},
        %{id: 2, is_default: true},
        %{id: 3, is_default: false}
      ]

      assert Serializer.default_layer_id(layers) == 2
    end

    test "returns first layer id when no default" do
      layers = [
        %{id: 10, is_default: false},
        %{id: 20, is_default: false}
      ]

      assert Serializer.default_layer_id(layers) == 10
    end
  end

  # ── build_scene_data/2 ──────────────────────────────────────────────

  describe "build_scene_data/2" do
    test "serializes full scene structure" do
      scene = %{
        id: 1,
        name: "Main Scene",
        width: 1920,
        height: 1080,
        default_zoom: 1.0,
        default_center_x: 960.0,
        default_center_y: 540.0,
        background_asset: %{url: "https://cdn.test/bg.png"},
        scale_unit: "meters",
        scale_value: 10.0,
        parent_id: nil,
        layers: [
          %{
            id: 1,
            name: "BG",
            visible: true,
            is_default: true,
            position: 0,
            fog_enabled: false,
            fog_color: nil,
            fog_opacity: nil
          }
        ],
        pins: [],
        zones: [],
        connections: [],
        annotations: []
      }

      result = Serializer.build_scene_data(scene, true)

      assert result.id == 1
      assert result.name == "Main Scene"
      assert result.background_url == "https://cdn.test/bg.png"
      assert result.can_edit == true
      assert length(result.layers) == 1
      assert hd(result.layers).name == "BG"
      assert result.pins == []
      assert result.boundary_vertices == nil
    end

    test "handles nil collections" do
      scene = %{
        id: 1,
        name: "Empty",
        width: 800,
        height: 600,
        default_zoom: 1.0,
        default_center_x: 400.0,
        default_center_y: 300.0,
        background_asset: nil,
        scale_unit: nil,
        scale_value: nil,
        parent_id: nil,
        layers: nil,
        pins: nil,
        zones: nil,
        connections: nil,
        annotations: nil
      }

      result = Serializer.build_scene_data(scene, false)

      assert result.background_url == nil
      assert result.can_edit == false
      assert result.layers == []
      assert result.pins == []
      assert result.zones == []
      assert result.connections == []
      assert result.annotations == []
    end
  end
end
