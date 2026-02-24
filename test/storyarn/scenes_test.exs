defmodule Storyarn.ScenesTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Scenes

  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  # =============================================================================
  # Scenes
  # =============================================================================

  describe "scenes" do
    test "list_scenes/1 returns all scenes for a project" do
      user = user_fixture()
      project = project_fixture(user)

      scene1 = scene_fixture(project, %{name: "World Map"})
      scene2 = scene_fixture(project, %{name: "City Map"})

      scenes = Scenes.list_scenes(project.id)

      assert length(scenes) == 2
      assert Enum.any?(scenes, &(&1.id == scene1.id))
      assert Enum.any?(scenes, &(&1.id == scene2.id))
    end

    test "list_scenes_tree/1 returns tree structure" do
      user = user_fixture()
      project = project_fixture(user)

      parent = scene_fixture(project, %{name: "World"})
      _child = scene_fixture(project, %{name: "Region", parent_id: parent.id})

      tree = Scenes.list_scenes_tree(project.id)

      assert length(tree) == 1
      assert hd(tree).id == parent.id
      assert length(hd(tree).children) == 1
    end

    test "get_scene/2 returns scene with preloads" do
      user = user_fixture()
      project = project_fixture(user)
      scene = scene_fixture(project)

      result = Scenes.get_scene(project.id, scene.id)

      assert result.id == scene.id
      assert is_list(result.layers)
      assert length(result.layers) == 1
      assert hd(result.layers).is_default == true
    end

    test "get_scene/2 returns nil for non-existent scene" do
      user = user_fixture()
      project = project_fixture(user)

      assert Scenes.get_scene(project.id, -1) == nil
    end

    test "create_scene/2 creates a scene with auto-generated shortcut" do
      user = user_fixture()
      project = project_fixture(user)

      {:ok, scene} = Scenes.create_scene(project, %{name: "World Map", description: "The world"})

      assert scene.name == "World Map"
      assert scene.description == "The world"
      assert scene.shortcut == "world-map"
      assert scene.project_id == project.id
    end

    test "create_scene/2 auto-creates default layer" do
      user = user_fixture()
      project = project_fixture(user)

      {:ok, scene} = Scenes.create_scene(project, %{name: "Test Map"})

      layers = Scenes.list_layers(scene.id)
      assert length(layers) == 1
      assert hd(layers).name == "Default"
      assert hd(layers).is_default == true
    end

    test "create_scene/2 auto-assigns position" do
      user = user_fixture()
      project = project_fixture(user)

      {:ok, scene1} = Scenes.create_scene(project, %{name: "First"})
      {:ok, scene2} = Scenes.create_scene(project, %{name: "Second"})

      assert scene1.position == 0
      assert scene2.position == 1
    end

    test "create_scene/2 with parent_id" do
      user = user_fixture()
      project = project_fixture(user)
      parent = scene_fixture(project, %{name: "World"})

      {:ok, child} = Scenes.create_scene(project, %{name: "Region", parent_id: parent.id})

      assert child.parent_id == parent.id
    end

    test "create_scene/2 validates required fields" do
      user = user_fixture()
      project = project_fixture(user)

      {:error, changeset} = Scenes.create_scene(project, %{})

      assert "can't be blank" in errors_on(changeset).name
    end

    test "update_scene/2 updates a scene" do
      user = user_fixture()
      project = project_fixture(user)
      scene = scene_fixture(project)

      {:ok, updated} = Scenes.update_scene(scene, %{name: "Updated Name"})

      assert updated.name == "Updated Name"
    end

    test "update_scene/2 regenerates shortcut on name change" do
      user = user_fixture()
      project = project_fixture(user)
      scene = scene_fixture(project, %{name: "Old Name"})

      {:ok, updated} = Scenes.update_scene(scene, %{name: "New Name"})

      assert updated.shortcut == "new-name"
    end

    test "delete_scene/1 soft-deletes scene" do
      user = user_fixture()
      project = project_fixture(user)
      scene = scene_fixture(project)

      {:ok, deleted_scene} = Scenes.delete_scene(scene)

      assert Scenes.get_scene(project.id, scene.id) == nil
      assert deleted_scene.id in Enum.map(Scenes.list_deleted_scenes(project.id), & &1.id)
    end

    test "delete_scene/1 cascades soft-delete to children" do
      user = user_fixture()
      project = project_fixture(user)
      parent = scene_fixture(project, %{name: "World"})
      child = scene_fixture(project, %{name: "Region", parent_id: parent.id})

      {:ok, _} = Scenes.delete_scene(parent)

      assert Scenes.get_scene(project.id, parent.id) == nil
      assert Scenes.get_scene(project.id, child.id) == nil
    end

    test "restore_scene/1 restores a soft-deleted scene" do
      user = user_fixture()
      project = project_fixture(user)
      scene = scene_fixture(project)

      {:ok, _} = Scenes.delete_scene(scene)
      assert Scenes.get_scene(project.id, scene.id) == nil

      deleted_scene = Enum.find(Scenes.list_deleted_scenes(project.id), &(&1.id == scene.id))
      {:ok, restored} = Scenes.restore_scene(deleted_scene)

      assert restored.deleted_at == nil
      assert Scenes.get_scene(project.id, scene.id) != nil
    end

    test "hard_delete_scene/1 permanently deletes scene" do
      user = user_fixture()
      project = project_fixture(user)
      scene = scene_fixture(project)

      {:ok, _} = Scenes.hard_delete_scene(scene)

      assert Scenes.get_scene(project.id, scene.id) == nil
      assert Scenes.list_deleted_scenes(project.id) == []
    end

    test "search_scenes/2 finds scenes by name" do
      user = user_fixture()
      project = project_fixture(user)
      _scene1 = scene_fixture(project, %{name: "World Map"})
      _scene2 = scene_fixture(project, %{name: "City Map"})

      results = Scenes.search_scenes(project.id, "World")
      assert length(results) == 1
      assert hd(results).name == "World Map"
    end

    test "shortcut validation rejects invalid formats" do
      user = user_fixture()
      project = project_fixture(user)

      {:error, changeset} =
        Scenes.create_scene(project, %{name: "Test", shortcut: "INVALID SHORTCUT!"})

      assert "must be lowercase, alphanumeric, with dots or hyphens (e.g., world-map)" in errors_on(
               changeset
             ).shortcut
    end
  end

  # =============================================================================
  # Scene Layers
  # =============================================================================

  describe "scene layers" do
    test "list_layers/1 returns layers ordered by position" do
      user = user_fixture()
      project = project_fixture(user)
      scene = scene_fixture(project)

      _layer2 = layer_fixture(scene, %{"name" => "Second Layer"})
      _layer3 = layer_fixture(scene, %{"name" => "Third Layer"})

      layers = Scenes.list_layers(scene.id)
      # Default layer (position 0) + 2 created layers
      assert length(layers) == 3
      positions = Enum.map(layers, & &1.position)
      assert positions == Enum.sort(positions)
    end

    test "create_layer/2 auto-assigns position" do
      user = user_fixture()
      project = project_fixture(user)
      scene = scene_fixture(project)

      {:ok, layer} = Scenes.create_layer(scene.id, %{"name" => "New Layer"})

      # Default layer is at position 0, so new one should be 1
      assert layer.position == 1
    end

    test "update_layer/2 updates a layer" do
      user = user_fixture()
      project = project_fixture(user)
      scene = scene_fixture(project)
      layer = layer_fixture(scene)

      {:ok, updated} = Scenes.update_layer(layer, %{"name" => "Updated"})

      assert updated.name == "Updated"
    end

    test "delete_layer/1 nullifies zone and pin references" do
      user = user_fixture()
      project = project_fixture(user)
      scene = scene_fixture(project)
      layer = layer_fixture(scene)

      # Create zone and pin on this layer
      _zone =
        zone_fixture(scene, %{
          "name" => "Test Zone",
          "layer_id" => layer.id
        })

      _pin =
        pin_fixture(scene, %{
          "label" => "Test Pin",
          "layer_id" => layer.id
        })

      {:ok, _} = Scenes.delete_layer(layer)

      # Zone and pin should still exist but with nil layer_id
      [zone] = Scenes.list_zones(scene.id)
      assert zone.layer_id == nil

      [pin] = Scenes.list_pins(scene.id)
      assert pin.layer_id == nil
    end

    test "delete_layer/1 prevents deleting last layer" do
      user = user_fixture()
      project = project_fixture(user)
      scene = scene_fixture(project)

      # The default layer is the only one
      [default_layer] = Scenes.list_layers(scene.id)

      assert {:error, :cannot_delete_last_layer} = Scenes.delete_layer(default_layer)
    end

    test "toggle_layer_visibility/1 toggles visibility" do
      user = user_fixture()
      project = project_fixture(user)
      scene = scene_fixture(project)
      layer = layer_fixture(scene)

      assert layer.visible == true

      {:ok, toggled} = Scenes.toggle_layer_visibility(layer)
      assert toggled.visible == false

      {:ok, toggled_back} = Scenes.toggle_layer_visibility(toggled)
      assert toggled_back.visible == true
    end

    test "create_layer/2 with fog_enabled stores the flag" do
      user = user_fixture()
      project = project_fixture(user)
      scene = scene_fixture(project)

      {:ok, layer} =
        Scenes.create_layer(scene.id, %{
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
      scene = scene_fixture(project)
      layer = layer_fixture(scene)

      {:error, changeset} = Scenes.update_layer(layer, %{"fog_opacity" => 1.5})
      assert errors_on(changeset).fog_opacity != []

      {:error, changeset} = Scenes.update_layer(layer, %{"fog_opacity" => -0.1})
      assert errors_on(changeset).fog_opacity != []

      {:ok, updated} = Scenes.update_layer(layer, %{"fog_opacity" => 0.75})
      assert updated.fog_opacity == 0.75
    end

    test "reorder_layers/2 updates positions" do
      user = user_fixture()
      project = project_fixture(user)
      scene = scene_fixture(project)

      layer2 = layer_fixture(scene, %{"name" => "Layer 2"})
      layer3 = layer_fixture(scene, %{"name" => "Layer 3"})
      [default_layer | _] = Scenes.list_layers(scene.id)

      # Reverse the order
      {:ok, reordered} = Scenes.reorder_layers(scene.id, [layer3.id, layer2.id, default_layer.id])

      positions = Enum.map(reordered, & &1.id)
      assert positions == [layer3.id, layer2.id, default_layer.id]
    end
  end

  # =============================================================================
  # Scene Zones
  # =============================================================================

  describe "scene zones" do
    test "list_zones/1 returns all zones for a scene" do
      user = user_fixture()
      project = project_fixture(user)
      scene = scene_fixture(project)

      zone = zone_fixture(scene)

      zones = Scenes.list_zones(scene.id)
      assert length(zones) == 1
      assert hd(zones).id == zone.id
    end

    test "list_zones/2 filters by layer_id" do
      user = user_fixture()
      project = project_fixture(user)
      scene = scene_fixture(project)
      layer = layer_fixture(scene)

      _zone_no_layer = zone_fixture(scene, %{"name" => "No Layer"})
      _zone_with_layer = zone_fixture(scene, %{"name" => "With Layer", "layer_id" => layer.id})

      all_zones = Scenes.list_zones(scene.id)
      assert length(all_zones) == 2

      filtered = Scenes.list_zones(scene.id, layer_id: layer.id)
      assert length(filtered) == 1
      assert hd(filtered).name == "With Layer"
    end

    test "create_zone/2 creates a zone" do
      user = user_fixture()
      project = project_fixture(user)
      scene = scene_fixture(project)

      {:ok, zone} =
        Scenes.create_zone(scene.id, %{
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
      scene = scene_fixture(project)

      {:error, changeset} =
        Scenes.create_zone(scene.id, %{
          "name" => "Bad Zone",
          "vertices" => [%{"x" => 10.0, "y" => 10.0}, %{"x" => 50.0, "y" => 50.0}]
        })

      assert "must have at least 3 points" in errors_on(changeset).vertices
    end

    test "create_zone/2 validates coordinates 0-100 range" do
      user = user_fixture()
      project = project_fixture(user)
      scene = scene_fixture(project)

      {:error, changeset} =
        Scenes.create_zone(scene.id, %{
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
      scene = scene_fixture(project)

      {:error, changeset} =
        Scenes.create_zone(scene.id, %{
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
      scene = scene_fixture(project)
      zone = zone_fixture(scene)

      {:ok, updated} =
        Scenes.update_zone(zone, %{"name" => "Updated Zone", "fill_color" => "#00ff00"})

      assert updated.name == "Updated Zone"
      assert updated.fill_color == "#00ff00"
    end

    test "update_zone_vertices/2 updates only vertices" do
      user = user_fixture()
      project = project_fixture(user)
      scene = scene_fixture(project)
      zone = zone_fixture(scene)

      new_vertices = [
        %{"x" => 20.0, "y" => 20.0},
        %{"x" => 80.0, "y" => 20.0},
        %{"x" => 50.0, "y" => 80.0}
      ]

      {:ok, updated} = Scenes.update_zone_vertices(zone, %{"vertices" => new_vertices})

      assert updated.vertices == new_vertices
    end

    test "delete_zone/1 hard-deletes a zone" do
      user = user_fixture()
      project = project_fixture(user)
      scene = scene_fixture(project)
      zone = zone_fixture(scene)

      {:ok, _} = Scenes.delete_zone(zone)

      assert Scenes.get_zone(zone.id) == nil
    end

    test "zone with target" do
      user = user_fixture()
      project = project_fixture(user)
      scene = scene_fixture(project)

      {:ok, zone} =
        Scenes.create_zone(scene.id, %{
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
      scene = scene_fixture(project)
      %{scene: scene}
    end

    @triangle [
      %{"x" => 10.0, "y" => 10.0},
      %{"x" => 50.0, "y" => 10.0},
      %{"x" => 30.0, "y" => 50.0}
    ]

    test "default zone gets action_type none", %{scene: scene} do
      {:ok, zone} = Scenes.create_zone(scene.id, %{"name" => "Plain", "vertices" => @triangle})

      assert zone.action_type == "none"
      assert zone.action_data == %{}
    end

    test "create instruction zone with assignments", %{scene: scene} do
      {:ok, zone} =
        Scenes.create_zone(scene.id, %{
          "name" => "Set HP",
          "vertices" => @triangle,
          "action_type" => "instruction",
          "action_data" => %{"assignments" => [%{"var" => "hp", "op" => "set", "value" => 100}]}
        })

      assert zone.action_type == "instruction"
      assert is_list(zone.action_data["assignments"])
    end

    test "create display zone with variable_ref", %{scene: scene} do
      {:ok, zone} =
        Scenes.create_zone(scene.id, %{
          "name" => "Show HP",
          "vertices" => @triangle,
          "action_type" => "display",
          "action_data" => %{"variable_ref" => "mc.jaime.health"}
        })

      assert zone.action_type == "display"
      assert zone.action_data["variable_ref"] == "mc.jaime.health"
    end

    test "create zone with action_type none", %{scene: scene} do
      {:ok, zone} =
        Scenes.create_zone(scene.id, %{
          "name" => "Simple",
          "vertices" => @triangle,
          "action_type" => "none"
        })

      assert zone.action_type == "none"
    end

    test "instruction requires assignments list", %{scene: scene} do
      {:error, changeset} =
        Scenes.create_zone(scene.id, %{
          "name" => "Bad Instruction",
          "vertices" => @triangle,
          "action_type" => "instruction",
          "action_data" => %{}
        })

      assert "must include \"assignments\" as a list" in errors_on(changeset).action_data
    end

    test "display requires variable_ref", %{scene: scene} do
      {:error, changeset} =
        Scenes.create_zone(scene.id, %{
          "name" => "Bad Display",
          "vertices" => @triangle,
          "action_type" => "display",
          "action_data" => %{}
        })

      assert "must include \"variable_ref\"" in errors_on(changeset).action_data
    end

    test "event action_type is no longer valid", %{scene: scene} do
      {:error, changeset} =
        Scenes.create_zone(scene.id, %{
          "name" => "Bad Event",
          "vertices" => @triangle,
          "action_type" => "event",
          "action_data" => %{"event_name" => "boom"}
        })

      assert "is invalid" in errors_on(changeset).action_type
    end

    test "invalid action_type rejected", %{scene: scene} do
      {:error, changeset} =
        Scenes.create_zone(scene.id, %{
          "name" => "Bad Type",
          "vertices" => @triangle,
          "action_type" => "teleport"
        })

      assert "is invalid" in errors_on(changeset).action_type
    end

    test "switching action_type preserves target_type and target_id", %{scene: scene} do
      {:ok, zone} =
        Scenes.create_zone(scene.id, %{
          "name" => "Nav Zone",
          "vertices" => @triangle,
          "target_type" => "sheet",
          "target_id" => 42
        })

      assert zone.target_type == "sheet"
      assert zone.target_id == 42

      {:ok, updated} =
        Scenes.update_zone(zone, %{
          "action_type" => "instruction",
          "action_data" => %{"assignments" => []}
        })

      assert updated.action_type == "instruction"
      assert updated.target_type == "sheet"
      assert updated.target_id == 42
    end

    test "list_actionable_zones returns only non-none zones", %{scene: scene} do
      _plain = zone_fixture(scene, %{"name" => "Plain"})

      _instruction =
        zone_fixture(scene, %{
          "name" => "Inst",
          "action_type" => "instruction",
          "action_data" => %{"assignments" => []}
        })

      _display =
        zone_fixture(scene, %{
          "name" => "Disp",
          "action_type" => "display",
          "action_data" => %{"variable_ref" => "mc.hp"}
        })

      actionable = Scenes.list_actionable_zones(scene.id)
      assert length(actionable) == 2
      names = Enum.map(actionable, & &1.name) |> Enum.sort()
      assert names == ["Disp", "Inst"]
    end
  end

  # =============================================================================
  # Scene Pins
  # =============================================================================

  describe "scene pins" do
    test "list_pins/1 returns all pins for a scene" do
      user = user_fixture()
      project = project_fixture(user)
      scene = scene_fixture(project)

      pin = pin_fixture(scene)

      pins = Scenes.list_pins(scene.id)
      assert length(pins) == 1
      assert hd(pins).id == pin.id
    end

    test "list_pins/2 filters by layer_id" do
      user = user_fixture()
      project = project_fixture(user)
      scene = scene_fixture(project)
      layer = layer_fixture(scene)

      _pin_no_layer = pin_fixture(scene, %{"label" => "No Layer"})
      _pin_with_layer = pin_fixture(scene, %{"label" => "With Layer", "layer_id" => layer.id})

      all_pins = Scenes.list_pins(scene.id)
      assert length(all_pins) == 2

      filtered = Scenes.list_pins(scene.id, layer_id: layer.id)
      assert length(filtered) == 1
      assert hd(filtered).label == "With Layer"
    end

    test "create_pin/2 creates a pin" do
      user = user_fixture()
      project = project_fixture(user)
      scene = scene_fixture(project)

      {:ok, pin} =
        Scenes.create_pin(scene.id, %{
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
      scene = scene_fixture(project)

      {:error, changeset} =
        Scenes.create_pin(scene.id, %{
          "position_x" => 150.0,
          "position_y" => -10.0
        })

      assert errors_on(changeset).position_x != []
      assert errors_on(changeset).position_y != []
    end

    test "create_pin/2 validates pin_type" do
      user = user_fixture()
      project = project_fixture(user)
      scene = scene_fixture(project)

      {:error, changeset} =
        Scenes.create_pin(scene.id, %{
          "position_x" => 50.0,
          "position_y" => 50.0,
          "pin_type" => "invalid"
        })

      assert "is invalid" in errors_on(changeset).pin_type
    end

    test "create_pin/2 validates size" do
      user = user_fixture()
      project = project_fixture(user)
      scene = scene_fixture(project)

      {:error, changeset} =
        Scenes.create_pin(scene.id, %{
          "position_x" => 50.0,
          "position_y" => 50.0,
          "size" => "xl"
        })

      assert "is invalid" in errors_on(changeset).size
    end

    test "update_pin/2 updates a pin" do
      user = user_fixture()
      project = project_fixture(user)
      scene = scene_fixture(project)
      pin = pin_fixture(scene)

      {:ok, updated} = Scenes.update_pin(pin, %{"label" => "Updated", "color" => "#00ff00"})

      assert updated.label == "Updated"
      assert updated.color == "#00ff00"
    end

    test "move_pin/3 updates only position" do
      user = user_fixture()
      project = project_fixture(user)
      scene = scene_fixture(project)
      pin = pin_fixture(scene)

      {:ok, moved} = Scenes.move_pin(pin, 75.0, 25.0)

      assert moved.position_x == 75.0
      assert moved.position_y == 25.0
    end

    test "delete_pin/1 cascades to connections" do
      user = user_fixture()
      project = project_fixture(user)
      scene = scene_fixture(project)
      pin1 = pin_fixture(scene, %{"label" => "Pin 1"})
      pin2 = pin_fixture(scene, %{"label" => "Pin 2"})
      _conn = connection_fixture(scene, pin1, pin2)

      {:ok, _} = Scenes.delete_pin(pin1)

      assert Scenes.get_pin(pin1.id) == nil
      assert Scenes.list_connections(scene.id) == []
    end

    test "pin with target" do
      user = user_fixture()
      project = project_fixture(user)
      scene = scene_fixture(project)

      {:ok, pin} =
        Scenes.create_pin(scene.id, %{
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
      scene = scene_fixture(project)
      sheet = sheet_fixture(project)

      {:ok, pin} =
        Scenes.create_pin(scene.id, %{
          "position_x" => 50.0,
          "position_y" => 50.0,
          "pin_type" => "character",
          "label" => sheet.name,
          "sheet_id" => sheet.id
        })

      assert pin.sheet_id == sheet.id
    end

    test "pin with sheet_id preloads sheet and avatar_asset via get_scene" do
      user = user_fixture()
      project = project_fixture(user)
      scene = scene_fixture(project)
      avatar = image_asset_fixture(project, user, %{url: "https://example.com/avatar.png"})
      sheet = sheet_fixture(project, %{avatar_asset_id: avatar.id})

      {:ok, _pin} =
        Scenes.create_pin(scene.id, %{
          "position_x" => 50.0,
          "position_y" => 50.0,
          "sheet_id" => sheet.id
        })

      loaded_scene = Scenes.get_scene!(project.id, scene.id)
      [loaded_pin] = loaded_scene.pins
      assert loaded_pin.sheet_id == sheet.id
      assert loaded_pin.sheet.id == sheet.id
      assert loaded_pin.sheet.avatar_asset.url == "https://example.com/avatar.png"
    end

    test "create_pin/2 with icon_asset_id stores the reference" do
      user = user_fixture()
      project = project_fixture(user)
      scene = scene_fixture(project)
      asset = image_asset_fixture(project, user, %{url: "https://example.com/castle.png"})

      {:ok, pin} =
        Scenes.create_pin(scene.id, %{
          "position_x" => 50.0,
          "position_y" => 50.0,
          "icon_asset_id" => asset.id
        })

      assert pin.icon_asset_id == asset.id
    end

    test "update_pin/2 sets and clears icon_asset_id" do
      user = user_fixture()
      project = project_fixture(user)
      scene = scene_fixture(project)
      asset = image_asset_fixture(project, user, %{url: "https://example.com/castle.png"})
      pin = pin_fixture(scene)

      # Set icon
      {:ok, updated} = Scenes.update_pin(pin, %{"icon_asset_id" => asset.id})
      assert updated.icon_asset_id == asset.id

      # Clear icon
      {:ok, cleared} = Scenes.update_pin(updated, %{"icon_asset_id" => nil})
      assert is_nil(cleared.icon_asset_id)
    end

    test "pin with icon_asset preloads via get_scene" do
      user = user_fixture()
      project = project_fixture(user)
      scene = scene_fixture(project)
      asset = image_asset_fixture(project, user, %{url: "https://example.com/castle.png"})

      {:ok, _pin} =
        Scenes.create_pin(scene.id, %{
          "position_x" => 50.0,
          "position_y" => 50.0,
          "icon_asset_id" => asset.id
        })

      loaded_scene = Scenes.get_scene!(project.id, scene.id)
      [loaded_pin] = loaded_scene.pins
      assert loaded_pin.icon_asset_id == asset.id
      assert loaded_pin.icon_asset.url == "https://example.com/castle.png"
    end
  end

  # =============================================================================
  # Scene Connections
  # =============================================================================

  describe "scene connections" do
    test "list_connections/1 returns connections with preloads" do
      user = user_fixture()
      project = project_fixture(user)
      scene = scene_fixture(project)
      pin1 = pin_fixture(scene, %{"label" => "Pin 1"})
      pin2 = pin_fixture(scene, %{"label" => "Pin 2"})
      _conn = connection_fixture(scene, pin1, pin2)

      connections = Scenes.list_connections(scene.id)
      assert length(connections) == 1

      conn = hd(connections)
      assert conn.from_pin.id == pin1.id
      assert conn.to_pin.id == pin2.id
    end

    test "create_connection/2 creates a connection" do
      user = user_fixture()
      project = project_fixture(user)
      scene = scene_fixture(project)
      pin1 = pin_fixture(scene, %{"label" => "Pin 1"})
      pin2 = pin_fixture(scene, %{"label" => "Pin 2"})

      {:ok, conn} =
        Scenes.create_connection(scene.id, %{
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
      scene = scene_fixture(project)
      pin = pin_fixture(scene)

      {:error, changeset} =
        Scenes.create_connection(scene.id, %{
          "from_pin_id" => pin.id,
          "to_pin_id" => pin.id
        })

      assert "cannot connect a pin to itself" in errors_on(changeset).to_pin_id
    end

    test "create_connection/2 validates pins belong to same scene" do
      user = user_fixture()
      project = project_fixture(user)
      scene1 = scene_fixture(project, %{name: "Map 1"})
      scene2 = scene_fixture(project, %{name: "Map 2"})
      pin1 = pin_fixture(scene1)
      pin2 = pin_fixture(scene2)

      assert {:error, :pin_belongs_to_different_scene} =
               Scenes.create_connection(scene1.id, %{
                 "from_pin_id" => pin1.id,
                 "to_pin_id" => pin2.id
               })
    end

    test "create_connection/2 validates line_style" do
      user = user_fixture()
      project = project_fixture(user)
      scene = scene_fixture(project)
      pin1 = pin_fixture(scene, %{"label" => "Pin 1"})
      pin2 = pin_fixture(scene, %{"label" => "Pin 2"})

      {:error, changeset} =
        Scenes.create_connection(scene.id, %{
          "from_pin_id" => pin1.id,
          "to_pin_id" => pin2.id,
          "line_style" => "wavy"
        })

      assert "is invalid" in errors_on(changeset).line_style
    end

    test "update_connection/2 updates a connection" do
      user = user_fixture()
      project = project_fixture(user)
      scene = scene_fixture(project)
      pin1 = pin_fixture(scene, %{"label" => "Pin 1"})
      pin2 = pin_fixture(scene, %{"label" => "Pin 2"})
      conn = connection_fixture(scene, pin1, pin2)

      {:ok, updated} =
        Scenes.update_connection(conn, %{"label" => "New Route", "color" => "#3b82f6"})

      assert updated.label == "New Route"
      assert updated.color == "#3b82f6"
    end

    test "delete_connection/1 deletes a connection" do
      user = user_fixture()
      project = project_fixture(user)
      scene = scene_fixture(project)
      pin1 = pin_fixture(scene, %{"label" => "Pin 1"})
      pin2 = pin_fixture(scene, %{"label" => "Pin 2"})
      conn = connection_fixture(scene, pin1, pin2)

      {:ok, _} = Scenes.delete_connection(conn)

      assert Scenes.get_connection(conn.id) == nil
    end

    test "create_connection/2 with waypoints stores them" do
      user = user_fixture()
      project = project_fixture(user)
      scene = scene_fixture(project)
      pin1 = pin_fixture(scene, %{"label" => "Pin 1"})
      pin2 = pin_fixture(scene, %{"label" => "Pin 2"})

      waypoints = [%{"x" => 30.0, "y" => 40.0}, %{"x" => 60.0, "y" => 20.0}]

      {:ok, conn} =
        Scenes.create_connection(scene.id, %{
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
      scene = scene_fixture(project)
      pin1 = pin_fixture(scene, %{"label" => "Pin 1"})
      pin2 = pin_fixture(scene, %{"label" => "Pin 2"})
      conn = connection_fixture(scene, pin1, pin2)

      waypoints = [%{"x" => 25.0, "y" => 50.0}]
      {:ok, updated} = Scenes.update_connection_waypoints(conn, %{"waypoints" => waypoints})

      assert length(updated.waypoints) == 1
      assert hd(updated.waypoints)["x"] == 25.0
    end

    test "update_connection_waypoints/2 validates coordinates" do
      user = user_fixture()
      project = project_fixture(user)
      scene = scene_fixture(project)
      pin1 = pin_fixture(scene, %{"label" => "Pin 1"})
      pin2 = pin_fixture(scene, %{"label" => "Pin 2"})
      conn = connection_fixture(scene, pin1, pin2)

      {:error, changeset} =
        Scenes.update_connection_waypoints(conn, %{
          "waypoints" => [%{"x" => 150.0, "y" => 50.0}]
        })

      assert "all waypoints must have x and y between 0 and 100" in errors_on(changeset).waypoints
    end

    test "connection defaults to empty waypoints" do
      user = user_fixture()
      project = project_fixture(user)
      scene = scene_fixture(project)
      pin1 = pin_fixture(scene, %{"label" => "Pin 1"})
      pin2 = pin_fixture(scene, %{"label" => "Pin 2"})
      conn = connection_fixture(scene, pin1, pin2)

      assert conn.waypoints == []
    end
  end

  # =============================================================================
  # Scoped Queries
  # =============================================================================

  describe "scoped queries" do
    test "get_pin!/2 returns pin scoped to scene" do
      user = user_fixture()
      project = project_fixture(user)
      scene = scene_fixture(project)
      pin = pin_fixture(scene)

      result = Scenes.get_pin!(scene.id, pin.id)
      assert result.id == pin.id
    end

    test "get_pin!/2 raises for pin from another scene" do
      user = user_fixture()
      project = project_fixture(user)
      scene1 = scene_fixture(project, %{name: "Map 1"})
      scene2 = scene_fixture(project, %{name: "Map 2"})
      pin = pin_fixture(scene1)

      assert_raise Ecto.NoResultsError, fn ->
        Scenes.get_pin!(scene2.id, pin.id)
      end
    end

    test "get_pin/2 returns nil for pin from another scene" do
      user = user_fixture()
      project = project_fixture(user)
      scene1 = scene_fixture(project, %{name: "Map 1"})
      scene2 = scene_fixture(project, %{name: "Map 2"})
      pin = pin_fixture(scene1)

      assert Scenes.get_pin(scene2.id, pin.id) == nil
    end

    test "get_zone!/2 returns zone scoped to scene" do
      user = user_fixture()
      project = project_fixture(user)
      scene = scene_fixture(project)
      zone = zone_fixture(scene)

      result = Scenes.get_zone!(scene.id, zone.id)
      assert result.id == zone.id
    end

    test "get_zone!/2 raises for zone from another scene" do
      user = user_fixture()
      project = project_fixture(user)
      scene1 = scene_fixture(project, %{name: "Map 1"})
      scene2 = scene_fixture(project, %{name: "Map 2"})
      zone = zone_fixture(scene1)

      assert_raise Ecto.NoResultsError, fn ->
        Scenes.get_zone!(scene2.id, zone.id)
      end
    end

    test "get_connection!/2 returns connection scoped to scene" do
      user = user_fixture()
      project = project_fixture(user)
      scene = scene_fixture(project)
      pin1 = pin_fixture(scene, %{"label" => "A"})
      pin2 = pin_fixture(scene, %{"label" => "B"})
      conn = connection_fixture(scene, pin1, pin2)

      result = Scenes.get_connection!(scene.id, conn.id)
      assert result.id == conn.id
    end

    test "get_connection!/2 raises for connection from another scene" do
      user = user_fixture()
      project = project_fixture(user)
      scene1 = scene_fixture(project, %{name: "Map 1"})
      scene2 = scene_fixture(project, %{name: "Map 2"})
      pin1 = pin_fixture(scene1, %{"label" => "A"})
      pin2 = pin_fixture(scene1, %{"label" => "B"})
      conn = connection_fixture(scene1, pin1, pin2)

      assert_raise Ecto.NoResultsError, fn ->
        Scenes.get_connection!(scene2.id, conn.id)
      end
    end
  end

  # =============================================================================
  # Tree Operations
  # =============================================================================

  describe "move_scene_to_position" do
    test "moves scene to new parent" do
      user = user_fixture()
      project = project_fixture(user)
      parent = scene_fixture(project, %{name: "Parent"})
      child = scene_fixture(project, %{name: "Child"})

      {:ok, moved} = Scenes.move_scene_to_position(child, parent.id, 0)
      assert moved.parent_id == parent.id
    end

    test "rejects cyclic parent (moving to own descendant)" do
      user = user_fixture()
      project = project_fixture(user)
      parent = scene_fixture(project, %{name: "Parent"})
      child = scene_fixture(project, %{name: "Child", parent_id: parent.id})

      assert {:error, :cyclic_parent} = Scenes.move_scene_to_position(parent, child.id, 0)
    end

    test "rejects moving scene under itself" do
      user = user_fixture()
      project = project_fixture(user)
      scene = scene_fixture(project, %{name: "Self"})

      assert {:error, :cyclic_parent} = Scenes.move_scene_to_position(scene, scene.id, 0)
    end

    test "allows moving to root (nil parent)" do
      user = user_fixture()
      project = project_fixture(user)
      parent = scene_fixture(project, %{name: "Parent"})
      child = scene_fixture(project, %{name: "Child", parent_id: parent.id})

      {:ok, moved} = Scenes.move_scene_to_position(child, nil, 0)
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
      scene = scene_fixture(project)
      layer = layer_fixture(scene)

      _zone = zone_fixture(scene, %{"name" => "Test", "layer_id" => layer.id})
      _pin = pin_fixture(scene, %{"label" => "Test", "layer_id" => layer.id})

      {:ok, _} = Scenes.delete_layer(layer)

      [zone] = Scenes.list_zones(scene.id)
      assert zone.layer_id == nil

      [pin] = Scenes.list_pins(scene.id)
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
      scene = scene_fixture(project)

      _zone =
        zone_fixture(scene, %{
          "name" => "Kingdom Zone",
          "target_type" => "sheet",
          "target_id" => 42
        })

      _pin =
        pin_fixture(scene, %{
          "label" => "Kingdom Pin",
          "target_type" => "sheet",
          "target_id" => 42
        })

      result = Scenes.get_elements_for_target("sheet", 42)

      assert length(result.zones) == 1
      assert hd(result.zones).name == "Kingdom Zone"
      assert hd(result.zones).scene.id == scene.id

      assert length(result.pins) == 1
      assert hd(result.pins).label == "Kingdom Pin"
      assert hd(result.pins).scene.id == scene.id
    end

    test "get_elements_for_target/2 returns empty for unlinked targets" do
      result = Scenes.get_elements_for_target("sheet", 999_999)

      assert result.zones == []
      assert result.pins == []
    end
  end

  # =============================================================================
  # Scene Annotations
  # =============================================================================

  describe "scene annotations" do
    test "create_annotation/2 creates an annotation" do
      user = user_fixture()
      project = project_fixture(user)
      scene = scene_fixture(project)

      {:ok, annotation} =
        Scenes.create_annotation(scene.id, %{
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
      scene = scene_fixture(project)

      {:error, changeset} =
        Scenes.create_annotation(scene.id, %{
          "position_x" => 50.0,
          "position_y" => 50.0,
          "text" => ""
        })

      assert errors_on(changeset).text != []
    end

    test "create_annotation/2 validates position 0-100" do
      user = user_fixture()
      project = project_fixture(user)
      scene = scene_fixture(project)

      {:error, changeset} =
        Scenes.create_annotation(scene.id, %{
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
      scene = scene_fixture(project)

      {:error, changeset} =
        Scenes.create_annotation(scene.id, %{
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
      scene = scene_fixture(project)
      annotation = annotation_fixture(scene)

      {:ok, updated} =
        Scenes.update_annotation(annotation, %{"text" => "Updated", "color" => "#00ff00"})

      assert updated.text == "Updated"
      assert updated.color == "#00ff00"
    end

    test "move_annotation/3 updates only position" do
      user = user_fixture()
      project = project_fixture(user)
      scene = scene_fixture(project)
      annotation = annotation_fixture(scene)

      {:ok, moved} = Scenes.move_annotation(annotation, 75.0, 25.0)

      assert moved.position_x == 75.0
      assert moved.position_y == 25.0
    end

    test "delete_annotation/1 removes annotation" do
      user = user_fixture()
      project = project_fixture(user)
      scene = scene_fixture(project)
      annotation = annotation_fixture(scene)

      {:ok, _} = Scenes.delete_annotation(annotation)

      assert Scenes.get_annotation(annotation.id) == nil
    end

    test "list_annotations/1 returns annotations for a scene" do
      user = user_fixture()
      project = project_fixture(user)
      scene = scene_fixture(project)

      _a1 = annotation_fixture(scene, %{"text" => "First"})
      _a2 = annotation_fixture(scene, %{"text" => "Second"})

      annotations = Scenes.list_annotations(scene.id)
      assert length(annotations) == 2
    end

    test "annotation with layer association" do
      user = user_fixture()
      project = project_fixture(user)
      scene = scene_fixture(project)
      layer = layer_fixture(scene)

      {:ok, annotation} =
        Scenes.create_annotation(scene.id, %{
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
      scene = scene_fixture(project)

      {:ok, pin} =
        Scenes.create_pin(scene.id, %{
          "position_x" => 50.0,
          "position_y" => 50.0,
          "locked" => true
        })

      assert pin.locked == true
    end

    test "create_pin/2 defaults locked to false" do
      user = user_fixture()
      project = project_fixture(user)
      scene = scene_fixture(project)

      {:ok, pin} =
        Scenes.create_pin(scene.id, %{
          "position_x" => 50.0,
          "position_y" => 50.0
        })

      assert pin.locked == false
    end

    test "update_pin/2 toggles locked field" do
      user = user_fixture()
      project = project_fixture(user)
      scene = scene_fixture(project)
      pin = pin_fixture(scene)

      assert pin.locked == false

      {:ok, locked} = Scenes.update_pin(pin, %{"locked" => true})
      assert locked.locked == true

      {:ok, unlocked} = Scenes.update_pin(locked, %{"locked" => false})
      assert unlocked.locked == false
    end

    test "create_zone/2 with locked: true persists the field" do
      user = user_fixture()
      project = project_fixture(user)
      scene = scene_fixture(project)

      {:ok, zone} =
        Scenes.create_zone(scene.id, %{
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
      scene = scene_fixture(project)
      zone = zone_fixture(scene)

      assert zone.locked == false

      {:ok, locked} = Scenes.update_zone(zone, %{"locked" => true})
      assert locked.locked == true

      {:ok, unlocked} = Scenes.update_zone(locked, %{"locked" => false})
      assert unlocked.locked == false
    end

    test "create_annotation/2 with locked: true persists the field" do
      user = user_fixture()
      project = project_fixture(user)
      scene = scene_fixture(project)

      {:ok, annotation} =
        Scenes.create_annotation(scene.id, %{
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
      scene = scene_fixture(project)
      annotation = annotation_fixture(scene)

      assert annotation.locked == false

      {:ok, locked} = Scenes.update_annotation(annotation, %{"locked" => true})
      assert locked.locked == true

      {:ok, unlocked} = Scenes.update_annotation(locked, %{"locked" => false})
      assert unlocked.locked == false
    end
  end

  # =============================================================================
  # Scene Scale
  # =============================================================================

  describe "scene scale" do
    test "update_scene/2 stores scale_unit and scale_value" do
      user = user_fixture()
      project = project_fixture(user)
      scene = scene_fixture(project)

      {:ok, updated} = Scenes.update_scene(scene, %{scale_unit: "km", scale_value: 500.0})

      assert updated.scale_unit == "km"
      assert updated.scale_value == 500.0
    end

    test "update_scene/2 allows clearing scale fields" do
      user = user_fixture()
      project = project_fixture(user)
      scene = scene_fixture(project, %{scale_unit: "miles", scale_value: 200.0})

      {:ok, updated} = Scenes.update_scene(scene, %{scale_unit: nil, scale_value: nil})

      assert is_nil(updated.scale_unit)
      assert is_nil(updated.scale_value)
    end

    test "update_scene/2 validates scale_value is positive" do
      user = user_fixture()
      project = project_fixture(user)
      scene = scene_fixture(project)

      {:error, changeset} = Scenes.update_scene(scene, %{scale_value: -10.0})

      assert errors_on(changeset).scale_value != []
    end

    test "update_scene/2 validates scale_unit max length" do
      user = user_fixture()
      project = project_fixture(user)
      scene = scene_fixture(project)

      {:error, changeset} = Scenes.update_scene(scene, %{scale_unit: String.duplicate("a", 51)})

      assert errors_on(changeset).scale_unit != []
    end
  end
end
