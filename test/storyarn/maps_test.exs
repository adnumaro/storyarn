defmodule Storyarn.MapsTest do
  use Storyarn.DataCase

  alias Storyarn.Maps

  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.MapsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  # =============================================================================
  # Maps
  # =============================================================================

  describe "maps" do
    test "list_maps/1 returns all maps for a project" do
      user = user_fixture()
      project = project_fixture(user)

      map1 = map_fixture(project, %{name: "World Map"})
      map2 = map_fixture(project, %{name: "City Map"})

      maps = Maps.list_maps(project.id)

      assert length(maps) == 2
      assert Enum.any?(maps, &(&1.id == map1.id))
      assert Enum.any?(maps, &(&1.id == map2.id))
    end

    test "list_maps_tree/1 returns tree structure" do
      user = user_fixture()
      project = project_fixture(user)

      parent = map_fixture(project, %{name: "World"})
      _child = map_fixture(project, %{name: "Region", parent_id: parent.id})

      tree = Maps.list_maps_tree(project.id)

      assert length(tree) == 1
      assert hd(tree).id == parent.id
      assert length(hd(tree).children) == 1
    end

    test "get_map/2 returns map with preloads" do
      user = user_fixture()
      project = project_fixture(user)
      map = map_fixture(project)

      result = Maps.get_map(project.id, map.id)

      assert result.id == map.id
      assert is_list(result.layers)
      assert length(result.layers) == 1
      assert hd(result.layers).is_default == true
    end

    test "get_map/2 returns nil for non-existent map" do
      user = user_fixture()
      project = project_fixture(user)

      assert Maps.get_map(project.id, -1) == nil
    end

    test "create_map/2 creates a map with auto-generated shortcut" do
      user = user_fixture()
      project = project_fixture(user)

      {:ok, map} = Maps.create_map(project, %{name: "World Map", description: "The world"})

      assert map.name == "World Map"
      assert map.description == "The world"
      assert map.shortcut == "world-map"
      assert map.project_id == project.id
    end

    test "create_map/2 auto-creates default layer" do
      user = user_fixture()
      project = project_fixture(user)

      {:ok, map} = Maps.create_map(project, %{name: "Test Map"})

      layers = Maps.list_layers(map.id)
      assert length(layers) == 1
      assert hd(layers).name == "Default"
      assert hd(layers).is_default == true
    end

    test "create_map/2 auto-assigns position" do
      user = user_fixture()
      project = project_fixture(user)

      {:ok, map1} = Maps.create_map(project, %{name: "First"})
      {:ok, map2} = Maps.create_map(project, %{name: "Second"})

      assert map1.position == 0
      assert map2.position == 1
    end

    test "create_map/2 with parent_id" do
      user = user_fixture()
      project = project_fixture(user)
      parent = map_fixture(project, %{name: "World"})

      {:ok, child} = Maps.create_map(project, %{name: "Region", parent_id: parent.id})

      assert child.parent_id == parent.id
    end

    test "create_map/2 validates required fields" do
      user = user_fixture()
      project = project_fixture(user)

      {:error, changeset} = Maps.create_map(project, %{})

      assert "can't be blank" in errors_on(changeset).name
    end

    test "update_map/2 updates a map" do
      user = user_fixture()
      project = project_fixture(user)
      map = map_fixture(project)

      {:ok, updated} = Maps.update_map(map, %{name: "Updated Name"})

      assert updated.name == "Updated Name"
    end

    test "update_map/2 regenerates shortcut on name change" do
      user = user_fixture()
      project = project_fixture(user)
      map = map_fixture(project, %{name: "Old Name"})

      {:ok, updated} = Maps.update_map(map, %{name: "New Name"})

      assert updated.shortcut == "new-name"
    end

    test "delete_map/1 soft-deletes map" do
      user = user_fixture()
      project = project_fixture(user)
      map = map_fixture(project)

      {:ok, deleted_map} = Maps.delete_map(map)

      assert Maps.get_map(project.id, map.id) == nil
      assert deleted_map.id in Enum.map(Maps.list_deleted_maps(project.id), & &1.id)
    end

    test "delete_map/1 cascades soft-delete to children" do
      user = user_fixture()
      project = project_fixture(user)
      parent = map_fixture(project, %{name: "World"})
      child = map_fixture(project, %{name: "Region", parent_id: parent.id})

      {:ok, _} = Maps.delete_map(parent)

      assert Maps.get_map(project.id, parent.id) == nil
      assert Maps.get_map(project.id, child.id) == nil
    end

    test "restore_map/1 restores a soft-deleted map" do
      user = user_fixture()
      project = project_fixture(user)
      map = map_fixture(project)

      {:ok, _} = Maps.delete_map(map)
      assert Maps.get_map(project.id, map.id) == nil

      deleted_map = Enum.find(Maps.list_deleted_maps(project.id), &(&1.id == map.id))
      {:ok, restored} = Maps.restore_map(deleted_map)

      assert restored.deleted_at == nil
      assert Maps.get_map(project.id, map.id) != nil
    end

    test "hard_delete_map/1 permanently deletes map" do
      user = user_fixture()
      project = project_fixture(user)
      map = map_fixture(project)

      {:ok, _} = Maps.hard_delete_map(map)

      assert Maps.get_map(project.id, map.id) == nil
      assert Maps.list_deleted_maps(project.id) == []
    end

    test "search_maps/2 finds maps by name" do
      user = user_fixture()
      project = project_fixture(user)
      _map1 = map_fixture(project, %{name: "World Map"})
      _map2 = map_fixture(project, %{name: "City Map"})

      results = Maps.search_maps(project.id, "World")
      assert length(results) == 1
      assert hd(results).name == "World Map"
    end

    test "shortcut validation rejects invalid formats" do
      user = user_fixture()
      project = project_fixture(user)

      {:error, changeset} =
        Maps.create_map(project, %{name: "Test", shortcut: "INVALID SHORTCUT!"})

      assert "must be lowercase, alphanumeric, with dots or hyphens (e.g., world-map)" in errors_on(
               changeset
             ).shortcut
    end
  end

  # =============================================================================
  # Map Layers
  # =============================================================================

  describe "map layers" do
    test "list_layers/1 returns layers ordered by position" do
      user = user_fixture()
      project = project_fixture(user)
      map = map_fixture(project)

      _layer2 = layer_fixture(map, %{"name" => "Second Layer"})
      _layer3 = layer_fixture(map, %{"name" => "Third Layer"})

      layers = Maps.list_layers(map.id)
      # Default layer (position 0) + 2 created layers
      assert length(layers) == 3
      positions = Enum.map(layers, & &1.position)
      assert positions == Enum.sort(positions)
    end

    test "create_layer/2 auto-assigns position" do
      user = user_fixture()
      project = project_fixture(user)
      map = map_fixture(project)

      {:ok, layer} = Maps.create_layer(map.id, %{"name" => "New Layer"})

      # Default layer is at position 0, so new one should be 1
      assert layer.position == 1
    end

    test "update_layer/2 updates a layer" do
      user = user_fixture()
      project = project_fixture(user)
      map = map_fixture(project)
      layer = layer_fixture(map)

      {:ok, updated} = Maps.update_layer(layer, %{"name" => "Updated"})

      assert updated.name == "Updated"
    end

    test "delete_layer/1 nullifies zone and pin references" do
      user = user_fixture()
      project = project_fixture(user)
      map = map_fixture(project)
      layer = layer_fixture(map)

      # Create zone and pin on this layer
      _zone =
        zone_fixture(map, %{
          "name" => "Test Zone",
          "layer_id" => layer.id
        })

      _pin =
        pin_fixture(map, %{
          "label" => "Test Pin",
          "layer_id" => layer.id
        })

      {:ok, _} = Maps.delete_layer(layer)

      # Zone and pin should still exist but with nil layer_id
      [zone] = Maps.list_zones(map.id)
      assert zone.layer_id == nil

      [pin] = Maps.list_pins(map.id)
      assert pin.layer_id == nil
    end

    test "delete_layer/1 prevents deleting last layer" do
      user = user_fixture()
      project = project_fixture(user)
      map = map_fixture(project)

      # The default layer is the only one
      [default_layer] = Maps.list_layers(map.id)

      assert {:error, :cannot_delete_last_layer} = Maps.delete_layer(default_layer)
    end

    test "toggle_layer_visibility/1 toggles visibility" do
      user = user_fixture()
      project = project_fixture(user)
      map = map_fixture(project)
      layer = layer_fixture(map)

      assert layer.visible == true

      {:ok, toggled} = Maps.toggle_layer_visibility(layer)
      assert toggled.visible == false

      {:ok, toggled_back} = Maps.toggle_layer_visibility(toggled)
      assert toggled_back.visible == true
    end

    test "create_layer/2 with fog_enabled stores the flag" do
      user = user_fixture()
      project = project_fixture(user)
      map = map_fixture(project)

      {:ok, layer} =
        Maps.create_layer(map.id, %{
          "name" => "Fog Layer",
          "fog_enabled" => true,
          "fog_color" => "#1a1a2e",
          "fog_opacity" => 0.9
        })

      assert layer.fog_enabled == true
      assert layer.fog_color == "#1a1a2e"
      assert layer.fog_opacity == 0.9
    end

    test "update_layer/2 fog fields validation (opacity 0-1)" do
      user = user_fixture()
      project = project_fixture(user)
      map = map_fixture(project)
      layer = layer_fixture(map)

      {:error, changeset} = Maps.update_layer(layer, %{"fog_opacity" => 1.5})
      assert errors_on(changeset).fog_opacity != []

      {:error, changeset} = Maps.update_layer(layer, %{"fog_opacity" => -0.1})
      assert errors_on(changeset).fog_opacity != []

      {:ok, updated} = Maps.update_layer(layer, %{"fog_opacity" => 0.75})
      assert updated.fog_opacity == 0.75
    end

    test "reorder_layers/2 updates positions" do
      user = user_fixture()
      project = project_fixture(user)
      map = map_fixture(project)

      layer2 = layer_fixture(map, %{"name" => "Layer 2"})
      layer3 = layer_fixture(map, %{"name" => "Layer 3"})
      [default_layer | _] = Maps.list_layers(map.id)

      # Reverse the order
      {:ok, reordered} = Maps.reorder_layers(map.id, [layer3.id, layer2.id, default_layer.id])

      positions = Enum.map(reordered, & &1.id)
      assert positions == [layer3.id, layer2.id, default_layer.id]
    end
  end

  # =============================================================================
  # Map Zones
  # =============================================================================

  describe "map zones" do
    test "list_zones/1 returns all zones for a map" do
      user = user_fixture()
      project = project_fixture(user)
      map = map_fixture(project)

      zone = zone_fixture(map)

      zones = Maps.list_zones(map.id)
      assert length(zones) == 1
      assert hd(zones).id == zone.id
    end

    test "list_zones/2 filters by layer_id" do
      user = user_fixture()
      project = project_fixture(user)
      map = map_fixture(project)
      layer = layer_fixture(map)

      _zone_no_layer = zone_fixture(map, %{"name" => "No Layer"})
      _zone_with_layer = zone_fixture(map, %{"name" => "With Layer", "layer_id" => layer.id})

      all_zones = Maps.list_zones(map.id)
      assert length(all_zones) == 2

      filtered = Maps.list_zones(map.id, layer_id: layer.id)
      assert length(filtered) == 1
      assert hd(filtered).name == "With Layer"
    end

    test "create_zone/2 creates a zone" do
      user = user_fixture()
      project = project_fixture(user)
      map = map_fixture(project)

      {:ok, zone} =
        Maps.create_zone(map.id, %{
          "name" => "Kingdom",
          "vertices" => [
            %{"x" => 10.0, "y" => 10.0},
            %{"x" => 90.0, "y" => 10.0},
            %{"x" => 50.0, "y" => 90.0}
          ],
          "fill_color" => "#ff0000",
          "opacity" => 0.5
        })

      assert zone.name == "Kingdom"
      assert length(zone.vertices) == 3
      assert zone.fill_color == "#ff0000"
      assert zone.opacity == 0.5
    end

    test "create_zone/2 validates minimum 3 vertices" do
      user = user_fixture()
      project = project_fixture(user)
      map = map_fixture(project)

      {:error, changeset} =
        Maps.create_zone(map.id, %{
          "name" => "Bad Zone",
          "vertices" => [%{"x" => 10.0, "y" => 10.0}, %{"x" => 50.0, "y" => 50.0}]
        })

      assert "must have at least 3 points" in errors_on(changeset).vertices
    end

    test "create_zone/2 validates coordinates 0-100 range" do
      user = user_fixture()
      project = project_fixture(user)
      map = map_fixture(project)

      {:error, changeset} =
        Maps.create_zone(map.id, %{
          "name" => "Bad Zone",
          "vertices" => [
            %{"x" => -5.0, "y" => 10.0},
            %{"x" => 150.0, "y" => 10.0},
            %{"x" => 50.0, "y" => 50.0}
          ]
        })

      assert "all coordinates must have x and y between 0 and 100" in errors_on(changeset).vertices
    end

    test "create_zone/2 validates border_style" do
      user = user_fixture()
      project = project_fixture(user)
      map = map_fixture(project)

      {:error, changeset} =
        Maps.create_zone(map.id, %{
          "name" => "Bad Zone",
          "vertices" => [
            %{"x" => 10.0, "y" => 10.0},
            %{"x" => 50.0, "y" => 10.0},
            %{"x" => 30.0, "y" => 50.0}
          ],
          "border_style" => "wavy"
        })

      assert "is invalid" in errors_on(changeset).border_style
    end

    test "update_zone/2 updates a zone" do
      user = user_fixture()
      project = project_fixture(user)
      map = map_fixture(project)
      zone = zone_fixture(map)

      {:ok, updated} =
        Maps.update_zone(zone, %{"name" => "Updated Zone", "fill_color" => "#00ff00"})

      assert updated.name == "Updated Zone"
      assert updated.fill_color == "#00ff00"
    end

    test "update_zone_vertices/2 updates only vertices" do
      user = user_fixture()
      project = project_fixture(user)
      map = map_fixture(project)
      zone = zone_fixture(map)

      new_vertices = [
        %{"x" => 20.0, "y" => 20.0},
        %{"x" => 80.0, "y" => 20.0},
        %{"x" => 50.0, "y" => 80.0}
      ]

      {:ok, updated} = Maps.update_zone_vertices(zone, %{"vertices" => new_vertices})

      assert updated.vertices == new_vertices
    end

    test "delete_zone/1 hard-deletes a zone" do
      user = user_fixture()
      project = project_fixture(user)
      map = map_fixture(project)
      zone = zone_fixture(map)

      {:ok, _} = Maps.delete_zone(zone)

      assert Maps.get_zone(zone.id) == nil
    end

    test "zone with target" do
      user = user_fixture()
      project = project_fixture(user)
      map = map_fixture(project)

      {:ok, zone} =
        Maps.create_zone(map.id, %{
          "name" => "Kingdom",
          "vertices" => [
            %{"x" => 10.0, "y" => 10.0},
            %{"x" => 50.0, "y" => 10.0},
            %{"x" => 30.0, "y" => 50.0}
          ],
          "target_type" => "sheet",
          "target_id" => 42
        })

      assert zone.target_type == "sheet"
      assert zone.target_id == 42
    end
  end

  # =============================================================================
  # Actionable Zones
  # =============================================================================

  describe "actionable zones" do
    setup do
      user = user_fixture()
      project = project_fixture(user)
      map = map_fixture(project)
      %{map: map}
    end

    @triangle [
      %{"x" => 10.0, "y" => 10.0},
      %{"x" => 50.0, "y" => 10.0},
      %{"x" => 30.0, "y" => 50.0}
    ]

    test "default zone gets action_type navigate", %{map: map} do
      {:ok, zone} = Maps.create_zone(map.id, %{"name" => "Plain", "vertices" => @triangle})

      assert zone.action_type == "navigate"
      assert zone.action_data == %{}
    end

    test "create instruction zone with assignments", %{map: map} do
      {:ok, zone} =
        Maps.create_zone(map.id, %{
          "name" => "Set HP",
          "vertices" => @triangle,
          "action_type" => "instruction",
          "action_data" => %{"assignments" => [%{"var" => "hp", "op" => "set", "value" => 100}]}
        })

      assert zone.action_type == "instruction"
      assert is_list(zone.action_data["assignments"])
    end

    test "create display zone with variable_ref", %{map: map} do
      {:ok, zone} =
        Maps.create_zone(map.id, %{
          "name" => "Show HP",
          "vertices" => @triangle,
          "action_type" => "display",
          "action_data" => %{"variable_ref" => "mc.jaime.health"}
        })

      assert zone.action_type == "display"
      assert zone.action_data["variable_ref"] == "mc.jaime.health"
    end

    test "create event zone with event_name", %{map: map} do
      {:ok, zone} =
        Maps.create_zone(map.id, %{
          "name" => "Trigger",
          "vertices" => @triangle,
          "action_type" => "event",
          "action_data" => %{"event_name" => "battle_start"}
        })

      assert zone.action_type == "event"
      assert zone.action_data["event_name"] == "battle_start"
    end

    test "instruction requires assignments list", %{map: map} do
      {:error, changeset} =
        Maps.create_zone(map.id, %{
          "name" => "Bad Instruction",
          "vertices" => @triangle,
          "action_type" => "instruction",
          "action_data" => %{}
        })

      assert "must include \"assignments\" as a list" in errors_on(changeset).action_data
    end

    test "display requires variable_ref", %{map: map} do
      {:error, changeset} =
        Maps.create_zone(map.id, %{
          "name" => "Bad Display",
          "vertices" => @triangle,
          "action_type" => "display",
          "action_data" => %{}
        })

      assert "must include a non-empty \"variable_ref\"" in errors_on(changeset).action_data
    end

    test "event requires event_name", %{map: map} do
      {:error, changeset} =
        Maps.create_zone(map.id, %{
          "name" => "Bad Event",
          "vertices" => @triangle,
          "action_type" => "event",
          "action_data" => %{}
        })

      assert "must include a non-empty \"event_name\"" in errors_on(changeset).action_data
    end

    test "invalid action_type rejected", %{map: map} do
      {:error, changeset} =
        Maps.create_zone(map.id, %{
          "name" => "Bad Type",
          "vertices" => @triangle,
          "action_type" => "teleport"
        })

      assert "is invalid" in errors_on(changeset).action_type
    end

    test "switching to instruction clears target_type and target_id", %{map: map} do
      {:ok, zone} =
        Maps.create_zone(map.id, %{
          "name" => "Nav Zone",
          "vertices" => @triangle,
          "target_type" => "sheet",
          "target_id" => 42
        })

      assert zone.target_type == "sheet"
      assert zone.target_id == 42

      {:ok, updated} =
        Maps.update_zone(zone, %{
          "action_type" => "instruction",
          "action_data" => %{"assignments" => []}
        })

      assert updated.action_type == "instruction"
      assert is_nil(updated.target_type)
      assert is_nil(updated.target_id)
    end

    test "list_event_zones returns only event zones", %{map: map} do
      _nav = zone_fixture(map, %{"name" => "Nav"})

      _event =
        zone_fixture(map, %{
          "name" => "Evt",
          "action_type" => "event",
          "action_data" => %{"event_name" => "boom"}
        })

      _instruction =
        zone_fixture(map, %{
          "name" => "Inst",
          "action_type" => "instruction",
          "action_data" => %{"assignments" => []}
        })

      events = Maps.list_event_zones(map.id)
      assert length(events) == 1
      assert hd(events).name == "Evt"
    end

    test "list_actionable_zones returns only non-navigate zones", %{map: map} do
      _nav = zone_fixture(map, %{"name" => "Nav"})

      _event =
        zone_fixture(map, %{
          "name" => "Evt",
          "action_type" => "event",
          "action_data" => %{"event_name" => "boom"}
        })

      _display =
        zone_fixture(map, %{
          "name" => "Disp",
          "action_type" => "display",
          "action_data" => %{"variable_ref" => "mc.hp"}
        })

      actionable = Maps.list_actionable_zones(map.id)
      assert length(actionable) == 2
      names = Enum.map(actionable, & &1.name) |> Enum.sort()
      assert names == ["Disp", "Evt"]
    end
  end

  # =============================================================================
  # Map Pins
  # =============================================================================

  describe "map pins" do
    test "list_pins/1 returns all pins for a map" do
      user = user_fixture()
      project = project_fixture(user)
      map = map_fixture(project)

      pin = pin_fixture(map)

      pins = Maps.list_pins(map.id)
      assert length(pins) == 1
      assert hd(pins).id == pin.id
    end

    test "list_pins/2 filters by layer_id" do
      user = user_fixture()
      project = project_fixture(user)
      map = map_fixture(project)
      layer = layer_fixture(map)

      _pin_no_layer = pin_fixture(map, %{"label" => "No Layer"})
      _pin_with_layer = pin_fixture(map, %{"label" => "With Layer", "layer_id" => layer.id})

      all_pins = Maps.list_pins(map.id)
      assert length(all_pins) == 2

      filtered = Maps.list_pins(map.id, layer_id: layer.id)
      assert length(filtered) == 1
      assert hd(filtered).label == "With Layer"
    end

    test "create_pin/2 creates a pin" do
      user = user_fixture()
      project = project_fixture(user)
      map = map_fixture(project)

      {:ok, pin} =
        Maps.create_pin(map.id, %{
          "position_x" => 25.0,
          "position_y" => 75.0,
          "pin_type" => "character",
          "label" => "NPC",
          "color" => "#ff0000",
          "size" => "lg"
        })

      assert pin.position_x == 25.0
      assert pin.position_y == 75.0
      assert pin.pin_type == "character"
      assert pin.label == "NPC"
      assert pin.size == "lg"
    end

    test "create_pin/2 validates position 0-100" do
      user = user_fixture()
      project = project_fixture(user)
      map = map_fixture(project)

      {:error, changeset} =
        Maps.create_pin(map.id, %{
          "position_x" => 150.0,
          "position_y" => -10.0
        })

      assert errors_on(changeset).position_x != []
      assert errors_on(changeset).position_y != []
    end

    test "create_pin/2 validates pin_type" do
      user = user_fixture()
      project = project_fixture(user)
      map = map_fixture(project)

      {:error, changeset} =
        Maps.create_pin(map.id, %{
          "position_x" => 50.0,
          "position_y" => 50.0,
          "pin_type" => "invalid"
        })

      assert "is invalid" in errors_on(changeset).pin_type
    end

    test "create_pin/2 validates size" do
      user = user_fixture()
      project = project_fixture(user)
      map = map_fixture(project)

      {:error, changeset} =
        Maps.create_pin(map.id, %{
          "position_x" => 50.0,
          "position_y" => 50.0,
          "size" => "xl"
        })

      assert "is invalid" in errors_on(changeset).size
    end

    test "update_pin/2 updates a pin" do
      user = user_fixture()
      project = project_fixture(user)
      map = map_fixture(project)
      pin = pin_fixture(map)

      {:ok, updated} = Maps.update_pin(pin, %{"label" => "Updated", "color" => "#00ff00"})

      assert updated.label == "Updated"
      assert updated.color == "#00ff00"
    end

    test "move_pin/3 updates only position" do
      user = user_fixture()
      project = project_fixture(user)
      map = map_fixture(project)
      pin = pin_fixture(map)

      {:ok, moved} = Maps.move_pin(pin, 75.0, 25.0)

      assert moved.position_x == 75.0
      assert moved.position_y == 25.0
    end

    test "delete_pin/1 cascades to connections" do
      user = user_fixture()
      project = project_fixture(user)
      map = map_fixture(project)
      pin1 = pin_fixture(map, %{"label" => "Pin 1"})
      pin2 = pin_fixture(map, %{"label" => "Pin 2"})
      _conn = connection_fixture(map, pin1, pin2)

      {:ok, _} = Maps.delete_pin(pin1)

      assert Maps.get_pin(pin1.id) == nil
      assert Maps.list_connections(map.id) == []
    end

    test "pin with target" do
      user = user_fixture()
      project = project_fixture(user)
      map = map_fixture(project)

      {:ok, pin} =
        Maps.create_pin(map.id, %{
          "position_x" => 50.0,
          "position_y" => 50.0,
          "target_type" => "flow",
          "target_id" => 99
        })

      assert pin.target_type == "flow"
      assert pin.target_id == 99
    end

    test "create_pin/2 with sheet_id stores the reference" do
      user = user_fixture()
      project = project_fixture(user)
      map = map_fixture(project)
      sheet = sheet_fixture(project)

      {:ok, pin} =
        Maps.create_pin(map.id, %{
          "position_x" => 50.0,
          "position_y" => 50.0,
          "pin_type" => "character",
          "label" => sheet.name,
          "sheet_id" => sheet.id
        })

      assert pin.sheet_id == sheet.id
    end

    test "pin with sheet_id preloads sheet and avatar_asset via get_map" do
      user = user_fixture()
      project = project_fixture(user)
      map = map_fixture(project)
      avatar = image_asset_fixture(project, user, %{url: "https://example.com/avatar.png"})
      sheet = sheet_fixture(project, %{avatar_asset_id: avatar.id})

      {:ok, _pin} =
        Maps.create_pin(map.id, %{
          "position_x" => 50.0,
          "position_y" => 50.0,
          "sheet_id" => sheet.id
        })

      loaded_map = Maps.get_map!(project.id, map.id)
      [loaded_pin] = loaded_map.pins
      assert loaded_pin.sheet_id == sheet.id
      assert loaded_pin.sheet.id == sheet.id
      assert loaded_pin.sheet.avatar_asset.url == "https://example.com/avatar.png"
    end

    test "create_pin/2 with icon_asset_id stores the reference" do
      user = user_fixture()
      project = project_fixture(user)
      map = map_fixture(project)
      asset = image_asset_fixture(project, user, %{url: "https://example.com/castle.png"})

      {:ok, pin} =
        Maps.create_pin(map.id, %{
          "position_x" => 50.0,
          "position_y" => 50.0,
          "icon_asset_id" => asset.id
        })

      assert pin.icon_asset_id == asset.id
    end

    test "update_pin/2 sets and clears icon_asset_id" do
      user = user_fixture()
      project = project_fixture(user)
      map = map_fixture(project)
      asset = image_asset_fixture(project, user, %{url: "https://example.com/castle.png"})
      pin = pin_fixture(map)

      # Set icon
      {:ok, updated} = Maps.update_pin(pin, %{"icon_asset_id" => asset.id})
      assert updated.icon_asset_id == asset.id

      # Clear icon
      {:ok, cleared} = Maps.update_pin(updated, %{"icon_asset_id" => nil})
      assert is_nil(cleared.icon_asset_id)
    end

    test "pin with icon_asset preloads via get_map" do
      user = user_fixture()
      project = project_fixture(user)
      map = map_fixture(project)
      asset = image_asset_fixture(project, user, %{url: "https://example.com/castle.png"})

      {:ok, _pin} =
        Maps.create_pin(map.id, %{
          "position_x" => 50.0,
          "position_y" => 50.0,
          "icon_asset_id" => asset.id
        })

      loaded_map = Maps.get_map!(project.id, map.id)
      [loaded_pin] = loaded_map.pins
      assert loaded_pin.icon_asset_id == asset.id
      assert loaded_pin.icon_asset.url == "https://example.com/castle.png"
    end
  end

  # =============================================================================
  # Map Connections
  # =============================================================================

  describe "map connections" do
    test "list_connections/1 returns connections with preloads" do
      user = user_fixture()
      project = project_fixture(user)
      map = map_fixture(project)
      pin1 = pin_fixture(map, %{"label" => "Pin 1"})
      pin2 = pin_fixture(map, %{"label" => "Pin 2"})
      _conn = connection_fixture(map, pin1, pin2)

      connections = Maps.list_connections(map.id)
      assert length(connections) == 1

      conn = hd(connections)
      assert conn.from_pin.id == pin1.id
      assert conn.to_pin.id == pin2.id
    end

    test "create_connection/2 creates a connection" do
      user = user_fixture()
      project = project_fixture(user)
      map = map_fixture(project)
      pin1 = pin_fixture(map, %{"label" => "Pin 1"})
      pin2 = pin_fixture(map, %{"label" => "Pin 2"})

      {:ok, conn} =
        Maps.create_connection(map.id, %{
          "from_pin_id" => pin1.id,
          "to_pin_id" => pin2.id,
          "line_style" => "dashed",
          "label" => "Trade Route"
        })

      assert conn.from_pin_id == pin1.id
      assert conn.to_pin_id == pin2.id
      assert conn.line_style == "dashed"
      assert conn.label == "Trade Route"
    end

    test "create_connection/2 rejects self-connection" do
      user = user_fixture()
      project = project_fixture(user)
      map = map_fixture(project)
      pin = pin_fixture(map)

      {:error, changeset} =
        Maps.create_connection(map.id, %{
          "from_pin_id" => pin.id,
          "to_pin_id" => pin.id
        })

      assert "cannot connect a pin to itself" in errors_on(changeset).to_pin_id
    end

    test "create_connection/2 validates pins belong to same map" do
      user = user_fixture()
      project = project_fixture(user)
      map1 = map_fixture(project, %{name: "Map 1"})
      map2 = map_fixture(project, %{name: "Map 2"})
      pin1 = pin_fixture(map1)
      pin2 = pin_fixture(map2)

      assert {:error, :pin_belongs_to_different_map} =
               Maps.create_connection(map1.id, %{
                 "from_pin_id" => pin1.id,
                 "to_pin_id" => pin2.id
               })
    end

    test "create_connection/2 validates line_style" do
      user = user_fixture()
      project = project_fixture(user)
      map = map_fixture(project)
      pin1 = pin_fixture(map, %{"label" => "Pin 1"})
      pin2 = pin_fixture(map, %{"label" => "Pin 2"})

      {:error, changeset} =
        Maps.create_connection(map.id, %{
          "from_pin_id" => pin1.id,
          "to_pin_id" => pin2.id,
          "line_style" => "wavy"
        })

      assert "is invalid" in errors_on(changeset).line_style
    end

    test "update_connection/2 updates a connection" do
      user = user_fixture()
      project = project_fixture(user)
      map = map_fixture(project)
      pin1 = pin_fixture(map, %{"label" => "Pin 1"})
      pin2 = pin_fixture(map, %{"label" => "Pin 2"})
      conn = connection_fixture(map, pin1, pin2)

      {:ok, updated} =
        Maps.update_connection(conn, %{"label" => "New Route", "color" => "#3b82f6"})

      assert updated.label == "New Route"
      assert updated.color == "#3b82f6"
    end

    test "delete_connection/1 deletes a connection" do
      user = user_fixture()
      project = project_fixture(user)
      map = map_fixture(project)
      pin1 = pin_fixture(map, %{"label" => "Pin 1"})
      pin2 = pin_fixture(map, %{"label" => "Pin 2"})
      conn = connection_fixture(map, pin1, pin2)

      {:ok, _} = Maps.delete_connection(conn)

      assert Maps.get_connection(conn.id) == nil
    end

    test "create_connection/2 with waypoints stores them" do
      user = user_fixture()
      project = project_fixture(user)
      map = map_fixture(project)
      pin1 = pin_fixture(map, %{"label" => "Pin 1"})
      pin2 = pin_fixture(map, %{"label" => "Pin 2"})

      waypoints = [%{"x" => 30.0, "y" => 40.0}, %{"x" => 60.0, "y" => 20.0}]

      {:ok, conn} =
        Maps.create_connection(map.id, %{
          "from_pin_id" => pin1.id,
          "to_pin_id" => pin2.id,
          "waypoints" => waypoints
        })

      assert length(conn.waypoints) == 2
      assert hd(conn.waypoints)["x"] == 30.0
    end

    test "update_connection_waypoints/2 updates waypoints" do
      user = user_fixture()
      project = project_fixture(user)
      map = map_fixture(project)
      pin1 = pin_fixture(map, %{"label" => "Pin 1"})
      pin2 = pin_fixture(map, %{"label" => "Pin 2"})
      conn = connection_fixture(map, pin1, pin2)

      waypoints = [%{"x" => 25.0, "y" => 50.0}]
      {:ok, updated} = Maps.update_connection_waypoints(conn, %{"waypoints" => waypoints})

      assert length(updated.waypoints) == 1
      assert hd(updated.waypoints)["x"] == 25.0
    end

    test "update_connection_waypoints/2 validates coordinates" do
      user = user_fixture()
      project = project_fixture(user)
      map = map_fixture(project)
      pin1 = pin_fixture(map, %{"label" => "Pin 1"})
      pin2 = pin_fixture(map, %{"label" => "Pin 2"})
      conn = connection_fixture(map, pin1, pin2)

      {:error, changeset} =
        Maps.update_connection_waypoints(conn, %{
          "waypoints" => [%{"x" => 150.0, "y" => 50.0}]
        })

      assert "all waypoints must have x and y between 0 and 100" in errors_on(changeset).waypoints
    end

    test "connection defaults to empty waypoints" do
      user = user_fixture()
      project = project_fixture(user)
      map = map_fixture(project)
      pin1 = pin_fixture(map, %{"label" => "Pin 1"})
      pin2 = pin_fixture(map, %{"label" => "Pin 2"})
      conn = connection_fixture(map, pin1, pin2)

      assert conn.waypoints == []
    end
  end

  # =============================================================================
  # Scoped Queries
  # =============================================================================

  describe "scoped queries" do
    test "get_pin!/2 returns pin scoped to map" do
      user = user_fixture()
      project = project_fixture(user)
      map = map_fixture(project)
      pin = pin_fixture(map)

      result = Maps.get_pin!(map.id, pin.id)
      assert result.id == pin.id
    end

    test "get_pin!/2 raises for pin from another map" do
      user = user_fixture()
      project = project_fixture(user)
      map1 = map_fixture(project, %{name: "Map 1"})
      map2 = map_fixture(project, %{name: "Map 2"})
      pin = pin_fixture(map1)

      assert_raise Ecto.NoResultsError, fn ->
        Maps.get_pin!(map2.id, pin.id)
      end
    end

    test "get_pin/2 returns nil for pin from another map" do
      user = user_fixture()
      project = project_fixture(user)
      map1 = map_fixture(project, %{name: "Map 1"})
      map2 = map_fixture(project, %{name: "Map 2"})
      pin = pin_fixture(map1)

      assert Maps.get_pin(map2.id, pin.id) == nil
    end

    test "get_zone!/2 returns zone scoped to map" do
      user = user_fixture()
      project = project_fixture(user)
      map = map_fixture(project)
      zone = zone_fixture(map)

      result = Maps.get_zone!(map.id, zone.id)
      assert result.id == zone.id
    end

    test "get_zone!/2 raises for zone from another map" do
      user = user_fixture()
      project = project_fixture(user)
      map1 = map_fixture(project, %{name: "Map 1"})
      map2 = map_fixture(project, %{name: "Map 2"})
      zone = zone_fixture(map1)

      assert_raise Ecto.NoResultsError, fn ->
        Maps.get_zone!(map2.id, zone.id)
      end
    end

    test "get_connection!/2 returns connection scoped to map" do
      user = user_fixture()
      project = project_fixture(user)
      map = map_fixture(project)
      pin1 = pin_fixture(map, %{"label" => "A"})
      pin2 = pin_fixture(map, %{"label" => "B"})
      conn = connection_fixture(map, pin1, pin2)

      result = Maps.get_connection!(map.id, conn.id)
      assert result.id == conn.id
    end

    test "get_connection!/2 raises for connection from another map" do
      user = user_fixture()
      project = project_fixture(user)
      map1 = map_fixture(project, %{name: "Map 1"})
      map2 = map_fixture(project, %{name: "Map 2"})
      pin1 = pin_fixture(map1, %{"label" => "A"})
      pin2 = pin_fixture(map1, %{"label" => "B"})
      conn = connection_fixture(map1, pin1, pin2)

      assert_raise Ecto.NoResultsError, fn ->
        Maps.get_connection!(map2.id, conn.id)
      end
    end
  end

  # =============================================================================
  # Tree Operations
  # =============================================================================

  describe "move_map_to_position" do
    test "moves map to new parent" do
      user = user_fixture()
      project = project_fixture(user)
      parent = map_fixture(project, %{name: "Parent"})
      child = map_fixture(project, %{name: "Child"})

      {:ok, moved} = Maps.move_map_to_position(child, parent.id, 0)
      assert moved.parent_id == parent.id
    end

    test "rejects cyclic parent (moving to own descendant)" do
      user = user_fixture()
      project = project_fixture(user)
      parent = map_fixture(project, %{name: "Parent"})
      child = map_fixture(project, %{name: "Child", parent_id: parent.id})

      assert {:error, :cyclic_parent} = Maps.move_map_to_position(parent, child.id, 0)
    end

    test "rejects moving map under itself" do
      user = user_fixture()
      project = project_fixture(user)
      map = map_fixture(project, %{name: "Self"})

      assert {:error, :cyclic_parent} = Maps.move_map_to_position(map, map.id, 0)
    end

    test "allows moving to root (nil parent)" do
      user = user_fixture()
      project = project_fixture(user)
      parent = map_fixture(project, %{name: "Parent"})
      child = map_fixture(project, %{name: "Child", parent_id: parent.id})

      {:ok, moved} = Maps.move_map_to_position(child, nil, 0)
      assert moved.parent_id == nil
    end
  end

  # =============================================================================
  # Delete Layer Transaction
  # =============================================================================

  describe "delete_layer transaction" do
    test "delete_layer nullifies zone and pin references atomically" do
      user = user_fixture()
      project = project_fixture(user)
      map = map_fixture(project)
      layer = layer_fixture(map)

      _zone = zone_fixture(map, %{"name" => "Test", "layer_id" => layer.id})
      _pin = pin_fixture(map, %{"label" => "Test", "layer_id" => layer.id})

      {:ok, _} = Maps.delete_layer(layer)

      [zone] = Maps.list_zones(map.id)
      assert zone.layer_id == nil

      [pin] = Maps.list_pins(map.id)
      assert pin.layer_id == nil
    end
  end

  # =============================================================================
  # Target Queries
  # =============================================================================

  describe "target queries" do
    test "get_elements_for_target/2 returns pins and zones" do
      user = user_fixture()
      project = project_fixture(user)
      map = map_fixture(project)

      _zone =
        zone_fixture(map, %{
          "name" => "Kingdom Zone",
          "target_type" => "sheet",
          "target_id" => 42
        })

      _pin =
        pin_fixture(map, %{
          "label" => "Kingdom Pin",
          "target_type" => "sheet",
          "target_id" => 42
        })

      result = Maps.get_elements_for_target("sheet", 42)

      assert length(result.zones) == 1
      assert hd(result.zones).name == "Kingdom Zone"
      assert hd(result.zones).map.id == map.id

      assert length(result.pins) == 1
      assert hd(result.pins).label == "Kingdom Pin"
      assert hd(result.pins).map.id == map.id
    end

    test "get_elements_for_target/2 returns empty for unlinked targets" do
      result = Maps.get_elements_for_target("sheet", 999_999)

      assert result.zones == []
      assert result.pins == []
    end
  end

  # =============================================================================
  # Map Annotations
  # =============================================================================

  describe "map annotations" do
    test "create_annotation/2 creates an annotation" do
      user = user_fixture()
      project = project_fixture(user)
      map = map_fixture(project)

      {:ok, annotation} =
        Maps.create_annotation(map.id, %{
          "text" => "Important note",
          "position_x" => 30.0,
          "position_y" => 70.0,
          "font_size" => "lg",
          "color" => "#ff0000"
        })

      assert annotation.text == "Important note"
      assert annotation.position_x == 30.0
      assert annotation.position_y == 70.0
      assert annotation.font_size == "lg"
      assert annotation.color == "#ff0000"
    end

    test "create_annotation/2 validates text required" do
      user = user_fixture()
      project = project_fixture(user)
      map = map_fixture(project)

      {:error, changeset} =
        Maps.create_annotation(map.id, %{
          "position_x" => 50.0,
          "position_y" => 50.0,
          "text" => ""
        })

      assert errors_on(changeset).text != []
    end

    test "create_annotation/2 validates position 0-100" do
      user = user_fixture()
      project = project_fixture(user)
      map = map_fixture(project)

      {:error, changeset} =
        Maps.create_annotation(map.id, %{
          "text" => "Note",
          "position_x" => 150.0,
          "position_y" => -10.0
        })

      assert errors_on(changeset).position_x != []
      assert errors_on(changeset).position_y != []
    end

    test "create_annotation/2 validates font_size enum" do
      user = user_fixture()
      project = project_fixture(user)
      map = map_fixture(project)

      {:error, changeset} =
        Maps.create_annotation(map.id, %{
          "text" => "Note",
          "position_x" => 50.0,
          "position_y" => 50.0,
          "font_size" => "xl"
        })

      assert "is invalid" in errors_on(changeset).font_size
    end

    test "update_annotation/2 updates an annotation" do
      user = user_fixture()
      project = project_fixture(user)
      map = map_fixture(project)
      annotation = annotation_fixture(map)

      {:ok, updated} =
        Maps.update_annotation(annotation, %{"text" => "Updated", "color" => "#00ff00"})

      assert updated.text == "Updated"
      assert updated.color == "#00ff00"
    end

    test "move_annotation/3 updates only position" do
      user = user_fixture()
      project = project_fixture(user)
      map = map_fixture(project)
      annotation = annotation_fixture(map)

      {:ok, moved} = Maps.move_annotation(annotation, 75.0, 25.0)

      assert moved.position_x == 75.0
      assert moved.position_y == 25.0
    end

    test "delete_annotation/1 removes annotation" do
      user = user_fixture()
      project = project_fixture(user)
      map = map_fixture(project)
      annotation = annotation_fixture(map)

      {:ok, _} = Maps.delete_annotation(annotation)

      assert Maps.get_annotation(annotation.id) == nil
    end

    test "list_annotations/1 returns annotations for a map" do
      user = user_fixture()
      project = project_fixture(user)
      map = map_fixture(project)

      _a1 = annotation_fixture(map, %{"text" => "First"})
      _a2 = annotation_fixture(map, %{"text" => "Second"})

      annotations = Maps.list_annotations(map.id)
      assert length(annotations) == 2
    end

    test "annotation with layer association" do
      user = user_fixture()
      project = project_fixture(user)
      map = map_fixture(project)
      layer = layer_fixture(map)

      {:ok, annotation} =
        Maps.create_annotation(map.id, %{
          "text" => "On layer",
          "position_x" => 50.0,
          "position_y" => 50.0,
          "layer_id" => layer.id
        })

      assert annotation.layer_id == layer.id
    end
  end

  # =============================================================================
  # Locked field
  # =============================================================================

  describe "locked field" do
    test "create_pin/2 with locked: true persists the field" do
      user = user_fixture()
      project = project_fixture(user)
      map = map_fixture(project)

      {:ok, pin} =
        Maps.create_pin(map.id, %{
          "position_x" => 50.0,
          "position_y" => 50.0,
          "locked" => true
        })

      assert pin.locked == true
    end

    test "create_pin/2 defaults locked to false" do
      user = user_fixture()
      project = project_fixture(user)
      map = map_fixture(project)

      {:ok, pin} =
        Maps.create_pin(map.id, %{
          "position_x" => 50.0,
          "position_y" => 50.0
        })

      assert pin.locked == false
    end

    test "update_pin/2 toggles locked field" do
      user = user_fixture()
      project = project_fixture(user)
      map = map_fixture(project)
      pin = pin_fixture(map)

      assert pin.locked == false

      {:ok, locked} = Maps.update_pin(pin, %{"locked" => true})
      assert locked.locked == true

      {:ok, unlocked} = Maps.update_pin(locked, %{"locked" => false})
      assert unlocked.locked == false
    end

    test "create_zone/2 with locked: true persists the field" do
      user = user_fixture()
      project = project_fixture(user)
      map = map_fixture(project)

      {:ok, zone} =
        Maps.create_zone(map.id, %{
          "name" => "Locked Zone",
          "vertices" => [
            %{"x" => 10.0, "y" => 10.0},
            %{"x" => 50.0, "y" => 10.0},
            %{"x" => 30.0, "y" => 50.0}
          ],
          "locked" => true
        })

      assert zone.locked == true
    end

    test "update_zone/2 toggles locked field" do
      user = user_fixture()
      project = project_fixture(user)
      map = map_fixture(project)
      zone = zone_fixture(map)

      assert zone.locked == false

      {:ok, locked} = Maps.update_zone(zone, %{"locked" => true})
      assert locked.locked == true

      {:ok, unlocked} = Maps.update_zone(locked, %{"locked" => false})
      assert unlocked.locked == false
    end

    test "create_annotation/2 with locked: true persists the field" do
      user = user_fixture()
      project = project_fixture(user)
      map = map_fixture(project)

      {:ok, annotation} =
        Maps.create_annotation(map.id, %{
          "text" => "Locked note",
          "position_x" => 50.0,
          "position_y" => 50.0,
          "locked" => true
        })

      assert annotation.locked == true
    end

    test "update_annotation/2 toggles locked field" do
      user = user_fixture()
      project = project_fixture(user)
      map = map_fixture(project)
      annotation = annotation_fixture(map)

      assert annotation.locked == false

      {:ok, locked} = Maps.update_annotation(annotation, %{"locked" => true})
      assert locked.locked == true

      {:ok, unlocked} = Maps.update_annotation(locked, %{"locked" => false})
      assert unlocked.locked == false
    end
  end

  # =============================================================================
  # Map Scale
  # =============================================================================

  describe "map scale" do
    test "update_map/2 stores scale_unit and scale_value" do
      user = user_fixture()
      project = project_fixture(user)
      map = map_fixture(project)

      {:ok, updated} = Maps.update_map(map, %{scale_unit: "km", scale_value: 500.0})

      assert updated.scale_unit == "km"
      assert updated.scale_value == 500.0
    end

    test "update_map/2 allows clearing scale fields" do
      user = user_fixture()
      project = project_fixture(user)
      map = map_fixture(project, %{scale_unit: "miles", scale_value: 200.0})

      {:ok, updated} = Maps.update_map(map, %{scale_unit: nil, scale_value: nil})

      assert is_nil(updated.scale_unit)
      assert is_nil(updated.scale_value)
    end

    test "update_map/2 validates scale_value is positive" do
      user = user_fixture()
      project = project_fixture(user)
      map = map_fixture(project)

      {:error, changeset} = Maps.update_map(map, %{scale_value: -10.0})

      assert errors_on(changeset).scale_value != []
    end

    test "update_map/2 validates scale_unit max length" do
      user = user_fixture()
      project = project_fixture(user)
      map = map_fixture(project)

      {:error, changeset} = Maps.update_map(map, %{scale_unit: String.duplicate("a", 51)})

      assert errors_on(changeset).scale_unit != []
    end
  end
end
