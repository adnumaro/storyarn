defmodule StoryarnWeb.MapLive.UndoRedoTest do
  @moduledoc """
  Integration tests for undo/redo in the map LiveView.

  Tests cover all action types:
  - Create/delete pins, zones, connections, annotations
  - Move pins, annotations (with coalescing)
  - Property updates (pins, zones, connections, annotations)
  - Zone vertex reshape, connection waypoints
  - Layer create/delete/rename/fog
  - Compound actions (pin delete cascading to connections)
  - Attr preservation (opacity, locked, icon_asset_id, line_width, show_label)
  """

  use StoryarnWeb.ConnCase

  import Phoenix.LiveViewTest
  import Storyarn.MapsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.{Maps, Repo}

  # ===========================================================================
  # Setup
  # ===========================================================================

  setup :register_and_log_in_user

  setup %{user: user} do
    project = project_fixture(user) |> Repo.preload(:workspace)
    map = map_fixture(project, %{name: "Test Map"})
    url = ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/maps/#{map.id}"
    %{project: project, map: map, url: url}
  end

  # ===========================================================================
  # Pin undo/redo
  # ===========================================================================

  describe "pin create undo/redo" do
    test "undo reverts pin creation", %{conn: conn, map: map, url: url} do
      {:ok, view, _html} = live(conn, url)

      render_click(view, "create_pin", %{"position_x" => 25.0, "position_y" => 75.0})
      assert length(Maps.list_pins(map.id)) == 1

      render_click(view, "undo", %{})
      assert Maps.list_pins(map.id) == []
    end

    test "redo restores pin after undo", %{conn: conn, map: map, url: url} do
      {:ok, view, _html} = live(conn, url)

      render_click(view, "create_pin", %{"position_x" => 25.0, "position_y" => 75.0})
      render_click(view, "undo", %{})
      assert Maps.list_pins(map.id) == []

      render_click(view, "redo", %{})
      pins = Maps.list_pins(map.id)
      assert length(pins) == 1
    end
  end

  describe "pin delete undo/redo" do
    test "undo restores deleted pin", %{conn: conn, map: map, url: url} do
      pin = pin_fixture(map, %{"label" => "My Pin"})

      {:ok, view, _html} = live(conn, url)

      render_click(view, "delete_pin", %{"id" => to_string(pin.id)})
      assert Maps.list_pins(map.id) == []

      render_click(view, "undo", %{})
      pins = Maps.list_pins(map.id)
      assert length(pins) == 1
      assert hd(pins).label == "My Pin"
    end

    test "undo preserves opacity and locked on deleted pin",
         %{conn: conn, map: map, url: url} do
      pin = pin_fixture(map, %{"opacity" => 0.5, "locked" => false})

      {:ok, view, _html} = live(conn, url)

      render_click(view, "delete_pin", %{"id" => to_string(pin.id)})
      render_click(view, "undo", %{})

      restored = hd(Maps.list_pins(map.id))
      assert restored.opacity == 0.5
      assert restored.locked == false
    end

    test "redo re-deletes the restored pin", %{conn: conn, map: map, url: url} do
      pin = pin_fixture(map)

      {:ok, view, _html} = live(conn, url)

      render_click(view, "delete_pin", %{"id" => to_string(pin.id)})
      render_click(view, "undo", %{})
      assert length(Maps.list_pins(map.id)) == 1

      render_click(view, "redo", %{})
      assert Maps.list_pins(map.id) == []
    end
  end

  describe "pin move undo/redo" do
    test "undo restores previous position", %{conn: conn, map: map, url: url} do
      pin = pin_fixture(map, %{"position_x" => 10.0, "position_y" => 20.0})

      {:ok, view, _html} = live(conn, url)

      render_click(view, "move_pin", %{
        "id" => to_string(pin.id),
        "position_x" => 80.0,
        "position_y" => 90.0
      })

      render_click(view, "undo", %{})

      restored = Maps.get_pin(map.id, pin.id)
      assert restored.position_x == 10.0
      assert restored.position_y == 20.0
    end

    test "consecutive moves coalesce into single undo entry",
         %{conn: conn, map: map, url: url} do
      pin = pin_fixture(map, %{"position_x" => 10.0, "position_y" => 10.0})

      {:ok, view, _html} = live(conn, url)

      # Simulate drag: multiple moves of the same pin
      render_click(view, "move_pin", %{
        "id" => to_string(pin.id),
        "position_x" => 30.0,
        "position_y" => 30.0
      })

      render_click(view, "move_pin", %{
        "id" => to_string(pin.id),
        "position_x" => 50.0,
        "position_y" => 50.0
      })

      render_click(view, "move_pin", %{
        "id" => to_string(pin.id),
        "position_x" => 80.0,
        "position_y" => 80.0
      })

      # Single undo should go back to original position (10, 10), not 50, 50
      render_click(view, "undo", %{})

      restored = Maps.get_pin(map.id, pin.id)
      assert restored.position_x == 10.0
      assert restored.position_y == 10.0
    end

    test "redo re-applies the move", %{conn: conn, map: map, url: url} do
      pin = pin_fixture(map, %{"position_x" => 10.0, "position_y" => 10.0})

      {:ok, view, _html} = live(conn, url)

      render_click(view, "move_pin", %{
        "id" => to_string(pin.id),
        "position_x" => 80.0,
        "position_y" => 80.0
      })

      render_click(view, "undo", %{})
      render_click(view, "redo", %{})

      updated = Maps.get_pin(map.id, pin.id)
      assert updated.position_x == 80.0
      assert updated.position_y == 80.0
    end
  end

  describe "pin property update undo/redo" do
    test "undo reverts label change", %{conn: conn, map: map, url: url} do
      pin = pin_fixture(map, %{"label" => "Original"})

      {:ok, view, _html} = live(conn, url)

      render_click(view, "update_pin", %{
        "id" => to_string(pin.id),
        "field" => "label",
        "value" => "Changed"
      })

      assert Maps.get_pin(map.id, pin.id).label == "Changed"

      render_click(view, "undo", %{})
      assert Maps.get_pin(map.id, pin.id).label == "Original"
    end

    test "redo re-applies label change", %{conn: conn, map: map, url: url} do
      pin = pin_fixture(map, %{"label" => "Original"})

      {:ok, view, _html} = live(conn, url)

      render_click(view, "update_pin", %{
        "id" => to_string(pin.id),
        "field" => "label",
        "value" => "Changed"
      })

      render_click(view, "undo", %{})
      render_click(view, "redo", %{})
      assert Maps.get_pin(map.id, pin.id).label == "Changed"
    end
  end

  # ===========================================================================
  # Zone undo/redo
  # ===========================================================================

  describe "zone create undo/redo" do
    @vertices [
      %{"x" => 10.0, "y" => 10.0},
      %{"x" => 50.0, "y" => 10.0},
      %{"x" => 30.0, "y" => 50.0}
    ]

    test "undo reverts zone creation", %{conn: conn, map: map, url: url} do
      {:ok, view, _html} = live(conn, url)

      render_click(view, "create_zone", %{"vertices" => @vertices})
      assert length(Maps.list_zones(map.id)) == 1

      render_click(view, "undo", %{})
      assert Maps.list_zones(map.id) == []
    end

    test "redo restores zone after undo", %{conn: conn, map: map, url: url} do
      {:ok, view, _html} = live(conn, url)

      render_click(view, "create_zone", %{"vertices" => @vertices})
      render_click(view, "undo", %{})
      render_click(view, "redo", %{})

      assert length(Maps.list_zones(map.id)) == 1
    end
  end

  describe "zone delete undo/redo" do
    test "undo restores deleted zone with locked field",
         %{conn: conn, map: map, url: url} do
      zone = zone_fixture(map, %{"name" => "Locked Zone", "locked" => false})

      {:ok, view, _html} = live(conn, url)

      render_click(view, "delete_zone", %{"id" => to_string(zone.id)})
      assert Maps.list_zones(map.id) == []

      render_click(view, "undo", %{})
      restored = hd(Maps.list_zones(map.id))
      assert restored.name == "Locked Zone"
      assert restored.locked == false
    end
  end

  describe "zone property update undo/redo" do
    test "undo reverts name change", %{conn: conn, map: map, url: url} do
      zone = zone_fixture(map, %{"name" => "Forest"})

      {:ok, view, _html} = live(conn, url)

      render_click(view, "update_zone", %{
        "id" => to_string(zone.id),
        "field" => "name",
        "value" => "Desert"
      })

      assert Maps.get_zone(map.id, zone.id).name == "Desert"

      render_click(view, "undo", %{})
      assert Maps.get_zone(map.id, zone.id).name == "Forest"
    end
  end

  describe "zone vertices undo/redo" do
    test "undo restores original vertices", %{conn: conn, map: map, url: url} do
      zone = zone_fixture(map)
      original_vertices = zone.vertices

      new_vertices = [
        %{"x" => 20.0, "y" => 20.0},
        %{"x" => 60.0, "y" => 20.0},
        %{"x" => 40.0, "y" => 60.0}
      ]

      {:ok, view, _html} = live(conn, url)

      render_click(view, "update_zone_vertices", %{
        "id" => to_string(zone.id),
        "vertices" => new_vertices
      })

      render_click(view, "undo", %{})

      restored = Maps.get_zone(map.id, zone.id)
      assert restored.vertices == original_vertices
    end

    test "redo re-applies vertex changes", %{conn: conn, map: map, url: url} do
      zone = zone_fixture(map)

      new_vertices = [
        %{"x" => 20.0, "y" => 20.0},
        %{"x" => 60.0, "y" => 20.0},
        %{"x" => 40.0, "y" => 60.0}
      ]

      {:ok, view, _html} = live(conn, url)

      render_click(view, "update_zone_vertices", %{
        "id" => to_string(zone.id),
        "vertices" => new_vertices
      })

      render_click(view, "undo", %{})
      render_click(view, "redo", %{})

      updated = Maps.get_zone(map.id, zone.id)
      assert updated.vertices == new_vertices
    end
  end

  # ===========================================================================
  # Connection undo/redo
  # ===========================================================================

  describe "connection create undo/redo" do
    test "undo reverts connection creation", %{conn: conn, map: map, url: url} do
      pin1 = pin_fixture(map, %{"position_x" => 20.0, "position_y" => 20.0})
      pin2 = pin_fixture(map, %{"position_x" => 80.0, "position_y" => 80.0})

      {:ok, view, _html} = live(conn, url)

      render_click(view, "create_connection", %{
        "from_pin_id" => pin1.id,
        "to_pin_id" => pin2.id
      })

      assert length(Maps.list_connections(map.id)) == 1

      render_click(view, "undo", %{})
      assert Maps.list_connections(map.id) == []
    end

    test "redo restores connection", %{conn: conn, map: map, url: url} do
      pin1 = pin_fixture(map, %{"position_x" => 20.0, "position_y" => 20.0})
      pin2 = pin_fixture(map, %{"position_x" => 80.0, "position_y" => 80.0})

      {:ok, view, _html} = live(conn, url)

      render_click(view, "create_connection", %{
        "from_pin_id" => pin1.id,
        "to_pin_id" => pin2.id
      })

      render_click(view, "undo", %{})
      render_click(view, "redo", %{})

      assert length(Maps.list_connections(map.id)) == 1
    end
  end

  describe "connection delete undo/redo" do
    test "undo restores deleted connection with line_width and show_label",
         %{conn: conn, map: map, url: url} do
      pin1 = pin_fixture(map, %{"position_x" => 20.0, "position_y" => 20.0})
      pin2 = pin_fixture(map, %{"position_x" => 80.0, "position_y" => 80.0})

      conn_el =
        connection_fixture(map, pin1, pin2, %{
          "line_width" => 5,
          "show_label" => false,
          "label" => "Route A"
        })

      {:ok, view, _html} = live(conn, url)

      render_click(view, "delete_connection", %{"id" => to_string(conn_el.id)})
      assert Maps.list_connections(map.id) == []

      render_click(view, "undo", %{})

      restored = hd(Maps.list_connections(map.id))
      assert restored.label == "Route A"
      assert restored.line_width == 5
      assert restored.show_label == false
    end
  end

  describe "connection property update undo/redo" do
    test "undo reverts label change", %{conn: conn, map: map, url: url} do
      pin1 = pin_fixture(map, %{"position_x" => 20.0, "position_y" => 20.0})
      pin2 = pin_fixture(map, %{"position_x" => 80.0, "position_y" => 80.0})
      conn_el = connection_fixture(map, pin1, pin2, %{"label" => "Old Route"})

      {:ok, view, _html} = live(conn, url)

      render_click(view, "update_connection", %{
        "id" => to_string(conn_el.id),
        "field" => "label",
        "value" => "New Route"
      })

      assert Maps.get_connection(map.id, conn_el.id).label == "New Route"

      render_click(view, "undo", %{})
      assert Maps.get_connection(map.id, conn_el.id).label == "Old Route"
    end
  end

  describe "connection waypoints undo/redo" do
    test "undo restores previous waypoints", %{conn: conn, map: map, url: url} do
      pin1 = pin_fixture(map, %{"position_x" => 20.0, "position_y" => 20.0})
      pin2 = pin_fixture(map, %{"position_x" => 80.0, "position_y" => 80.0})
      conn_el = connection_fixture(map, pin1, pin2)

      new_waypoints = [%{"x" => 50.0, "y" => 50.0}]

      {:ok, view, _html} = live(conn, url)

      render_click(view, "update_connection_waypoints", %{
        "id" => to_string(conn_el.id),
        "waypoints" => new_waypoints
      })

      assert Maps.get_connection(map.id, conn_el.id).waypoints == new_waypoints

      render_click(view, "undo", %{})
      assert Maps.get_connection(map.id, conn_el.id).waypoints == []
    end

    test "undo restores waypoints after clear", %{conn: conn, map: map, url: url} do
      pin1 = pin_fixture(map, %{"position_x" => 20.0, "position_y" => 20.0})
      pin2 = pin_fixture(map, %{"position_x" => 80.0, "position_y" => 80.0})

      conn_el =
        connection_fixture(map, pin1, pin2, %{
          "waypoints" => [%{"x" => 40.0, "y" => 40.0}]
        })

      {:ok, view, _html} = live(conn, url)

      render_click(view, "clear_connection_waypoints", %{"id" => to_string(conn_el.id)})
      assert Maps.get_connection(map.id, conn_el.id).waypoints == []

      render_click(view, "undo", %{})
      assert Maps.get_connection(map.id, conn_el.id).waypoints == [%{"x" => 40.0, "y" => 40.0}]
    end
  end

  # ===========================================================================
  # Annotation undo/redo
  # ===========================================================================

  describe "annotation create undo/redo" do
    test "undo reverts annotation creation", %{conn: conn, map: map, url: url} do
      {:ok, view, _html} = live(conn, url)

      render_click(view, "create_annotation", %{
        "position_x" => 50.0,
        "position_y" => 50.0,
        "text" => "A note"
      })

      assert length(Maps.list_annotations(map.id)) == 1

      render_click(view, "undo", %{})
      assert Maps.list_annotations(map.id) == []
    end
  end

  describe "annotation delete undo/redo" do
    test "undo restores deleted annotation with locked field",
         %{conn: conn, map: map, url: url} do
      ann = annotation_fixture(map, %{"text" => "Important", "locked" => false})

      {:ok, view, _html} = live(conn, url)

      render_click(view, "delete_annotation", %{"id" => to_string(ann.id)})
      assert Maps.list_annotations(map.id) == []

      render_click(view, "undo", %{})
      restored = hd(Maps.list_annotations(map.id))
      assert restored.text == "Important"
      assert restored.locked == false
    end
  end

  describe "annotation move undo/redo" do
    test "undo restores previous position", %{conn: conn, map: map, url: url} do
      ann = annotation_fixture(map, %{"position_x" => 10.0, "position_y" => 20.0})

      {:ok, view, _html} = live(conn, url)

      render_click(view, "move_annotation", %{
        "id" => to_string(ann.id),
        "position_x" => 80.0,
        "position_y" => 90.0
      })

      render_click(view, "undo", %{})

      restored = Maps.get_annotation(map.id, ann.id)
      assert restored.position_x == 10.0
      assert restored.position_y == 20.0
    end

    test "consecutive moves coalesce into single undo entry",
         %{conn: conn, map: map, url: url} do
      ann = annotation_fixture(map, %{"position_x" => 5.0, "position_y" => 5.0})

      {:ok, view, _html} = live(conn, url)

      render_click(view, "move_annotation", %{
        "id" => to_string(ann.id),
        "position_x" => 30.0,
        "position_y" => 30.0
      })

      render_click(view, "move_annotation", %{
        "id" => to_string(ann.id),
        "position_x" => 70.0,
        "position_y" => 70.0
      })

      render_click(view, "undo", %{})

      restored = Maps.get_annotation(map.id, ann.id)
      assert restored.position_x == 5.0
      assert restored.position_y == 5.0
    end
  end

  describe "annotation property update undo/redo" do
    test "undo reverts text change", %{conn: conn, map: map, url: url} do
      ann = annotation_fixture(map, %{"text" => "First"})

      {:ok, view, _html} = live(conn, url)

      render_click(view, "update_annotation", %{
        "id" => to_string(ann.id),
        "field" => "text",
        "value" => "Second"
      })

      assert Maps.get_annotation(map.id, ann.id).text == "Second"

      render_click(view, "undo", %{})
      assert Maps.get_annotation(map.id, ann.id).text == "First"
    end
  end

  # ===========================================================================
  # Layer undo/redo
  # ===========================================================================

  describe "layer create undo/redo" do
    test "undo reverts layer creation", %{conn: conn, map: map, url: url} do
      {:ok, view, _html} = live(conn, url)

      # Map starts with 1 default layer
      assert length(Maps.list_layers(map.id)) == 1

      render_click(view, "create_layer", %{})
      assert length(Maps.list_layers(map.id)) == 2

      render_click(view, "undo", %{})
      assert length(Maps.list_layers(map.id)) == 1
    end

    test "redo re-creates layer", %{conn: conn, map: map, url: url} do
      {:ok, view, _html} = live(conn, url)

      render_click(view, "create_layer", %{})
      render_click(view, "undo", %{})
      render_click(view, "redo", %{})

      assert length(Maps.list_layers(map.id)) == 2
    end
  end

  describe "layer delete undo/redo" do
    test "undo restores deleted layer", %{conn: conn, map: map, url: url} do
      layer = layer_fixture(map, %{"name" => "Extra Layer"})

      {:ok, view, _html} = live(conn, url)
      assert length(Maps.list_layers(map.id)) == 2

      render_click(view, "delete_layer", %{"id" => to_string(layer.id)})
      assert length(Maps.list_layers(map.id)) == 1

      render_click(view, "undo", %{})
      layers = Maps.list_layers(map.id)
      assert length(layers) == 2
      assert Enum.any?(layers, &(&1.name == "Extra Layer"))
    end
  end

  describe "layer rename undo/redo" do
    test "undo reverts rename", %{conn: conn, map: map, url: url} do
      layer = layer_fixture(map, %{"name" => "Original"})

      {:ok, view, _html} = live(conn, url)

      render_click(view, "rename_layer", %{
        "id" => to_string(layer.id),
        "value" => "Renamed"
      })

      assert Maps.get_layer(map.id, layer.id).name == "Renamed"

      render_click(view, "undo", %{})
      assert Maps.get_layer(map.id, layer.id).name == "Original"
    end
  end

  describe "layer fog undo/redo" do
    test "undo reverts fog_enabled change", %{conn: conn, map: map, url: url} do
      layer = layer_fixture(map)

      {:ok, view, _html} = live(conn, url)

      render_click(view, "update_layer_fog", %{
        "id" => to_string(layer.id),
        "field" => "fog_enabled",
        "value" => "true"
      })

      assert Maps.get_layer(map.id, layer.id).fog_enabled == true

      render_click(view, "undo", %{})
      assert Maps.get_layer(map.id, layer.id).fog_enabled == false
    end
  end

  # ===========================================================================
  # Compound actions (pin delete with connections)
  # ===========================================================================

  describe "compound undo (pin delete with connections)" do
    test "undo restores pin AND its connections", %{conn: conn, map: map, url: url} do
      pin1 = pin_fixture(map, %{"position_x" => 20.0, "position_y" => 20.0, "label" => "Hub"})
      pin2 = pin_fixture(map, %{"position_x" => 80.0, "position_y" => 20.0})
      pin3 = pin_fixture(map, %{"position_x" => 80.0, "position_y" => 80.0})

      _conn1 = connection_fixture(map, pin1, pin2, %{"label" => "Route 1"})
      _conn2 = connection_fixture(map, pin1, pin3, %{"label" => "Route 2"})

      {:ok, view, _html} = live(conn, url)

      assert length(Maps.list_connections(map.id)) == 2

      # Deleting pin1 should cascade-delete both connections as compound action
      render_click(view, "delete_pin", %{"id" => to_string(pin1.id)})
      assert Maps.list_pins(map.id) |> length() == 2
      assert Maps.list_connections(map.id) == []

      # Undo should restore pin AND both connections (with rebased FK IDs)
      render_click(view, "undo", %{})

      assert length(Maps.list_pins(map.id)) == 3
      connections = Maps.list_connections(map.id)
      assert length(connections) == 2

      # Connections should reference the newly created pin, not the old ID
      new_pin = Enum.find(Maps.list_pins(map.id), &(&1.label == "Hub"))
      assert new_pin != nil

      assert Enum.all?(connections, fn c ->
               c.from_pin_id == new_pin.id or c.to_pin_id == new_pin.id
             end)
    end

    test "redo re-deletes pin and connections after compound undo",
         %{conn: conn, map: map, url: url} do
      pin1 = pin_fixture(map, %{"position_x" => 20.0, "position_y" => 20.0})
      pin2 = pin_fixture(map, %{"position_x" => 80.0, "position_y" => 80.0})
      _conn = connection_fixture(map, pin1, pin2)

      {:ok, view, _html} = live(conn, url)

      render_click(view, "delete_pin", %{"id" => to_string(pin1.id)})
      render_click(view, "undo", %{})

      assert length(Maps.list_pins(map.id)) == 2
      assert length(Maps.list_connections(map.id)) == 1

      render_click(view, "redo", %{})

      assert length(Maps.list_pins(map.id)) == 1
      assert Maps.list_connections(map.id) == []
    end
  end

  # ===========================================================================
  # Stack behavior
  # ===========================================================================

  describe "stack behavior" do
    test "undo on empty stack is a no-op", %{conn: conn, url: url} do
      {:ok, view, _html} = live(conn, url)

      # Should not crash
      render_click(view, "undo", %{})
      render_click(view, "undo", %{})
    end

    test "redo on empty stack is a no-op", %{conn: conn, url: url} do
      {:ok, view, _html} = live(conn, url)

      render_click(view, "redo", %{})
      render_click(view, "redo", %{})
    end

    test "new action clears redo stack", %{conn: conn, map: map, url: url} do
      {:ok, view, _html} = live(conn, url)

      render_click(view, "create_pin", %{"position_x" => 25.0, "position_y" => 25.0})
      render_click(view, "undo", %{})
      assert Maps.list_pins(map.id) == []

      # New action should clear redo stack
      render_click(view, "create_pin", %{"position_x" => 75.0, "position_y" => 75.0})

      # Redo should do nothing now — stack was cleared
      render_click(view, "redo", %{})
      assert length(Maps.list_pins(map.id)) == 1
    end

    test "multiple undo/redo cycles work correctly", %{conn: conn, map: map, url: url} do
      {:ok, view, _html} = live(conn, url)

      render_click(view, "create_pin", %{"position_x" => 10.0, "position_y" => 10.0})
      render_click(view, "create_pin", %{"position_x" => 20.0, "position_y" => 20.0})
      assert length(Maps.list_pins(map.id)) == 2

      render_click(view, "undo", %{})
      assert length(Maps.list_pins(map.id)) == 1

      render_click(view, "undo", %{})
      assert Maps.list_pins(map.id) == []

      render_click(view, "redo", %{})
      assert length(Maps.list_pins(map.id)) == 1

      render_click(view, "redo", %{})
      assert length(Maps.list_pins(map.id)) == 2
    end
  end
end
