defmodule Storyarn.Versioning.Builders.SceneBuilderTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Assets
  alias Storyarn.Assets.Asset
  alias Storyarn.Assets.BlobStore
  alias Storyarn.FlowsFixtures
  alias Storyarn.Projects.Project
  alias Storyarn.References.EntityReference
  alias Storyarn.References.VariableReference
  alias Storyarn.Repo
  alias Storyarn.Scenes.Scene
  alias Storyarn.Scenes.SceneAmbientFlow
  alias Storyarn.Scenes.SceneAnnotation
  alias Storyarn.Scenes.SceneConnection
  alias Storyarn.Scenes.SceneLayer
  alias Storyarn.Scenes.ScenePin
  alias Storyarn.Scenes.SceneZone
  alias Storyarn.Versioning.Builders.SceneBuilder

  setup do
    user = user_fixture()
    project = project_fixture(user)
    scene = scene_fixture(project)

    %{user: user, project: project, scene: scene}
  end

  describe "build_snapshot/1" do
    test "captures scene metadata", %{scene: scene} do
      snapshot = SceneBuilder.build_snapshot(scene)

      assert snapshot["name"] == scene.name
      assert snapshot["shortcut"] == scene.shortcut
      assert is_list(snapshot["layers"])
      assert is_list(snapshot["connections"])
    end

    test "reloads and locks the root instead of snapshotting stale root fields", %{
      scene: scene
    } do
      stale_scene = scene

      Repo.update_all(
        from(current in Scene, where: current.id == ^scene.id),
        set: [name: "Fresh database name"]
      )

      snapshot = SceneBuilder.build_snapshot(stale_scene)

      assert snapshot["name"] == "Fresh database name"
    end

    test "rejects a scene in trash", %{scene: scene} do
      deleted_at = DateTime.truncate(DateTime.utc_now(), :second)
      Repo.update_all(from(current in Scene, where: current.id == ^scene.id), set: [deleted_at: deleted_at])

      assert_raise ArgumentError, "cannot snapshot inactive scene #{scene.id}", fn ->
        SceneBuilder.build_snapshot(scene)
      end
    end

    test "rejects a scene whose project is in trash", %{project: project, scene: scene} do
      deleted_at = DateTime.truncate(DateTime.utc_now(), :second)

      Repo.update_all(
        from(current in Project, where: current.id == ^project.id),
        set: [deleted_at: deleted_at]
      )

      assert_raise ArgumentError,
                   "cannot snapshot scene under inactive project #{project.id}",
                   fn ->
                     SceneBuilder.build_snapshot(scene)
                   end
    end

    test "fails closed when persisted scene structure has no layer", %{scene: scene} do
      Repo.delete_all(from(layer in SceneLayer, where: layer.scene_id == ^scene.id))

      assert_raise ArgumentError, ~r/scene_snapshot_requires_at_least_one_layer/, fn ->
        SceneBuilder.build_snapshot(scene)
      end
    end

    test "fails closed when a layer relationship crosses scene ownership", %{
      project: project,
      scene: scene
    } do
      own_layer = layer_fixture(scene)
      other_scene = scene_fixture(project)
      other_layer = layer_fixture(other_scene)
      own_pin = pin_fixture(scene, %{"layer_id" => own_layer.id})

      Repo.update_all(
        from(pin in ScenePin, where: pin.id == ^own_pin.id),
        set: [layer_id: other_layer.id]
      )

      assert_raise ArgumentError, ~r/inconsistent layer ownership/, fn ->
        SceneBuilder.build_snapshot(scene)
      end

      Repo.update_all(
        from(pin in ScenePin, where: pin.id == ^own_pin.id),
        set: [layer_id: own_layer.id]
      )

      foreign_pin = pin_fixture(other_scene, %{"layer_id" => other_layer.id})

      Repo.update_all(
        from(pin in ScenePin, where: pin.id == ^foreign_pin.id),
        set: [layer_id: own_layer.id]
      )

      assert_raise ArgumentError, ~r/inconsistent layer ownership/, fn ->
        SceneBuilder.build_snapshot(scene)
      end
    end

    test "reloads preloaded associations so snapshots reflect current database state", %{
      scene: scene
    } do
      layer = layer_fixture(scene, %{"name" => "Reloaded layer"})
      stale_pin = pin_fixture(scene, %{"label" => "Stale pin", "layer_id" => layer.id})

      stale_scene =
        Repo.preload(scene, [
          {:layers, [:zones, :pins]},
          :zones,
          :pins,
          :annotations,
          :connections
        ])

      stale_layer = Enum.find(stale_scene.layers, &(&1.id == layer.id))
      assert Enum.map(stale_layer.pins, & &1.id) == [stale_pin.id]

      Repo.delete!(stale_pin)
      current_pin = pin_fixture(scene, %{"label" => "Current pin", "layer_id" => layer.id})

      snapshot = SceneBuilder.build_snapshot(stale_scene)
      snapshot_layer = Enum.find(snapshot["layers"], &(&1["original_id"] == layer.id))

      assert Enum.map(snapshot_layer["pins"], & &1["original_id"]) == [current_pin.id]
    end

    test "captures ambient flows exactly and reloads a stale preload", %{
      project: project,
      scene: scene
    } do
      historical_flow = FlowsFixtures.flow_fixture(project, %{name: "Historical ambience"})

      {:ok, historical_ambient} =
        Storyarn.Scenes.create_ambient_flow(scene.id, %{
          "flow_id" => historical_flow.id,
          "trigger_type" => "on_enter",
          "priority" => 1,
          "enabled" => true,
          "position" => 0
        })

      stale_scene = Repo.preload(scene, :ambient_flows)
      assert Enum.map(stale_scene.ambient_flows, & &1.id) == [historical_ambient.id]

      Repo.delete!(historical_ambient)
      current_flow = FlowsFixtures.flow_fixture(project, %{name: "Current ambience"})

      {:ok, current_ambient} =
        Storyarn.Scenes.create_ambient_flow(scene.id, %{
          "flow_id" => current_flow.id,
          "trigger_type" => "on_event",
          "trigger_config" => %{"variable_ref" => "hero.health"},
          "priority" => 9,
          "enabled" => false,
          "position" => 3
        })

      snapshot = SceneBuilder.build_snapshot(stale_scene)

      assert snapshot["ambient_flows"] == [
               %{
                 "original_id" => current_ambient.id,
                 "flow_id" => current_flow.id,
                 "trigger_type" => "on_event",
                 "trigger_config" => %{"variable_ref" => "hero.health"},
                 "priority" => 9,
                 "enabled" => false,
                 "position" => 3
               }
             ]
    end

    test "captures layers with zones and pins", %{scene: scene} do
      layer = layer_fixture(scene, %{"name" => "Combat Layer"})

      _zone =
        zone_fixture(scene, %{
          "name" => "Zone 1",
          "layer_id" => layer.id,
          "vertices" => [
            %{"x" => 10.0, "y" => 10.0},
            %{"x" => 50.0, "y" => 10.0},
            %{"x" => 30.0, "y" => 50.0}
          ]
        })

      _pin =
        pin_fixture(scene, %{"position_x" => 50.0, "position_y" => 50.0, "layer_id" => layer.id})

      snapshot = SceneBuilder.build_snapshot(scene)

      # Should have default layer + our new layer
      assert length(snapshot["layers"]) == 2

      # Check that at least one layer has zones or pins
      has_content =
        Enum.any?(snapshot["layers"], fn l ->
          (l["zones"] || []) != [] or (l["pins"] || []) != []
        end)

      assert has_content
    end

    test "captures connections with layer/pin indexes", %{scene: scene} do
      layer = layer_fixture(scene)

      pin1 =
        pin_fixture(scene, %{"position_x" => 20.0, "position_y" => 20.0, "layer_id" => layer.id})

      pin2 =
        pin_fixture(scene, %{"position_x" => 80.0, "position_y" => 80.0, "layer_id" => layer.id})

      _connection = connection_fixture(scene, pin1, pin2)

      snapshot = SceneBuilder.build_snapshot(scene)
      assert length(snapshot["connections"]) == 1

      [conn] = snapshot["connections"]
      assert is_integer(conn["from_layer_index"])
      assert is_integer(conn["from_pin_index"])
      assert is_integer(conn["to_layer_index"])
      assert is_integer(conn["to_pin_index"])
      assert conn["from_pin_original_id"] == pin1.id
      assert conn["to_pin_original_id"] == pin2.id
    end

    test "captures orphan entities and orphan-pin connections", %{scene: scene} do
      _zone = zone_fixture(scene, %{"name" => "Loose Zone"})
      pin1 = pin_fixture(scene, %{"label" => "Loose A"})
      pin2 = pin_fixture(scene, %{"label" => "Loose B"})
      _annotation = annotation_fixture(scene, %{"text" => "Loose Note"})
      _conn = connection_fixture(scene, pin1, pin2)

      snapshot = SceneBuilder.build_snapshot(scene)

      assert length(snapshot["orphan_zones"]) == 1
      assert length(snapshot["orphan_pins"]) == 2
      assert length(snapshot["orphan_annotations"]) == 1

      [conn] = snapshot["connections"]
      assert conn["from_layer_index"] == -1
      assert conn["to_layer_index"] == -1
    end

    test "captures valid free routes instead of dropping them", %{scene: scene} do
      {:ok, connection} =
        Storyarn.Scenes.create_connection(scene.id, %{
          "waypoints" => [
            %{"x" => 10.0, "y" => 20.0},
            %{"x" => 80.0, "y" => 90.0}
          ]
        })

      snapshot = SceneBuilder.build_snapshot(scene)

      assert [
               %{
                 "original_id" => connection_id,
                 "from_pin_original_id" => nil,
                 "to_pin_original_id" => nil,
                 "from_layer_index" => nil,
                 "from_pin_index" => nil,
                 "to_layer_index" => nil,
                 "to_pin_index" => nil
               }
             ] = snapshot["connections"]

      assert connection_id == connection.id
    end

    test "fails explicitly instead of silently omitting an invalid persisted connection", %{
      scene: scene
    } do
      connection = Repo.insert!(%SceneConnection{scene_id: scene.id, waypoints: []})

      assert_raise ArgumentError,
                   "cannot snapshot scene connection #{connection.id}: route has fewer than two points",
                   fn ->
                     SceneBuilder.build_snapshot(scene)
                   end
    end

    test "fails closed when a persisted zone violates the normalized target contract", %{
      scene: scene
    } do
      zone =
        zone_fixture(scene, %{
          "name" => "Portal",
          "target_type" => "scene",
          "target_id" => scene.id,
          "action_type" => "action",
          "action_data" => %{"assignments" => []}
        })

      Repo.update_all(
        from(current in SceneZone, where: current.id == ^zone.id),
        set: [
          action_type: "display",
          action_data: %{"variable_ref" => "hero.health"}
        ]
      )

      assert_raise ArgumentError, ~r/invalid_scene_zone_target_contract/, fn ->
        SceneBuilder.build_snapshot(scene)
      end

      Repo.update_all(
        from(current in SceneZone, where: current.id == ^zone.id),
        set: [action_type: "action", target_type: "scene", target_id: nil]
      )

      assert_raise ArgumentError, ~r/invalid_scene_zone_target_contract/, fn ->
        SceneBuilder.build_snapshot(scene)
      end
    end
  end

  describe "restore_snapshot/3" do
    test "restores scene with layers, pins, and connections", %{scene: scene} do
      layer = layer_fixture(scene)

      pin1 =
        pin_fixture(scene, %{
          "position_x" => 20.0,
          "position_y" => 20.0,
          "label" => "A",
          "layer_id" => layer.id
        })

      pin2 =
        pin_fixture(scene, %{
          "position_x" => 80.0,
          "position_y" => 80.0,
          "label" => "B",
          "layer_id" => layer.id
        })

      conn = connection_fixture(scene, pin1, pin2)

      snapshot = SceneBuilder.build_snapshot(scene)
      expected_layer_ids = Enum.map(snapshot["layers"], & &1["original_id"])

      # Modify the scene
      {:ok, modified_scene} = Storyarn.Scenes.update_scene(scene, %{"name" => "Modified"})

      # Restore
      {:ok, restored} =
        SceneBuilder.restore_snapshot(modified_scene, snapshot, restore_action: {:entity_version_restore, "scene"})

      assert restored.name == scene.name

      restored =
        Repo.preload(
          restored,
          [:connections, {:layers, [:zones, :pins]}],
          force: true
        )

      total_pins = restored.layers |> Enum.flat_map(& &1.pins) |> length()
      assert total_pins == 2
      assert length(restored.connections) == 1

      assert MapSet.new(Enum.map(restored.layers, & &1.id)) ==
               MapSet.new(expected_layer_ids)

      assert MapSet.new(Enum.flat_map(restored.layers, &Enum.map(&1.pins, fn pin -> pin.id end))) ==
               MapSet.new([pin1.id, pin2.id])

      assert Enum.map(restored.connections, & &1.id) == [conn.id]
    end

    test "rejects in-place restore for a scene in trash without mutating it", %{scene: scene} do
      layer = layer_fixture(scene)
      pin = pin_fixture(scene, %{"label" => "Versioned pin", "layer_id" => layer.id})
      snapshot = SceneBuilder.build_snapshot(scene)
      deleted_at = DateTime.truncate(DateTime.utc_now(), :second)

      Repo.update_all(
        from(current in Scene, where: current.id == ^scene.id),
        set: [name: "Current trashed scene", deleted_at: deleted_at]
      )

      Repo.update_all(
        from(current in ScenePin, where: current.id == ^pin.id),
        set: [label: "Current pin"]
      )

      trashed_scene = Repo.get!(Scene, scene.id)

      assert {:error, {:scene_not_active, scene_id}} =
               SceneBuilder.restore_snapshot(trashed_scene, snapshot, restore_action: {:entity_version_restore, "scene"})

      assert scene_id == scene.id
      assert Repo.get!(Scene, scene.id).name == "Current trashed scene"
      assert Repo.get!(Scene, scene.id).deleted_at == deleted_at
      assert Repo.get!(ScenePin, pin.id).label == "Current pin"
    end

    test "rejects cross-scene children attached to an owned layer without mutating either scene", %{
      project: project,
      scene: scene
    } do
      own_layer = layer_fixture(scene)
      snapshot = SceneBuilder.build_snapshot(scene)
      other_scene = scene_fixture(project)
      other_layer = layer_fixture(other_scene)
      foreign_pin = pin_fixture(other_scene, %{"label" => "Foreign pin", "layer_id" => other_layer.id})

      Repo.update_all(
        from(pin in ScenePin, where: pin.id == ^foreign_pin.id),
        set: [layer_id: own_layer.id]
      )

      {:ok, current_scene} = Storyarn.Scenes.update_scene(scene, %{"name" => "Current scene"})

      assert {:error, reason} =
               SceneBuilder.restore_snapshot(current_scene, snapshot, restore_action: {:entity_version_restore, "scene"})

      assert {:scene_layer_ownership_mismatch, :scene_pin, pin_id, owner_scene_id, layer_id, restored_scene_id} = reason

      assert pin_id == foreign_pin.id
      assert owner_scene_id == other_scene.id
      assert layer_id == own_layer.id
      assert restored_scene_id == scene.id
      assert Repo.get!(Scene, scene.id).name == "Current scene"
      assert Repo.get!(ScenePin, foreign_pin.id).layer_id == own_layer.id
      assert Repo.get!(ScenePin, foreign_pin.id).scene_id == other_scene.id
    end

    test "rejects missing top-level and nested collections without mutation", %{
      scene: scene
    } do
      layer = layer_fixture(scene, %{"name" => "Protected layer"})
      _pin = pin_fixture(scene, %{"label" => "Protected pin", "layer_id" => layer.id})
      snapshot = SceneBuilder.build_snapshot(scene)

      {:ok, modified_scene} =
        Storyarn.Scenes.update_scene(scene, %{"name" => "Current scene must survive"})

      before_restore = persisted_scene_state(scene.id)

      truncated_snapshots = [
        {Map.delete(snapshot, "orphan_pins"), "orphan_pins"},
        {Map.delete(snapshot, "ambient_flows"), "ambient_flows"},
        {update_snapshot_layer(snapshot, layer.id, &Map.delete(&1, "pins")), "pins"}
      ]

      for {truncated_snapshot, missing_collection} <- truncated_snapshots do
        assert {:error, {:missing_scene_snapshot_collection, ^missing_collection}} =
                 SceneBuilder.restore_snapshot(modified_scene, truncated_snapshot,
                   restore_action: {:entity_version_restore, "scene"}
                 )

        assert persisted_scene_state(scene.id) == before_restore
      end
    end

    test "rejects invalid layer, zone, pin, and annotation payloads without mutation", %{
      scene: scene
    } do
      layer = layer_fixture(scene, %{"name" => "Valid layer"})
      zone = zone_fixture(scene, %{"name" => "Valid zone", "layer_id" => layer.id})
      pin = pin_fixture(scene, %{"label" => "Valid pin", "layer_id" => layer.id})

      annotation =
        annotation_fixture(scene, %{"text" => "Valid note", "layer_id" => layer.id})

      snapshot = SceneBuilder.build_snapshot(scene)

      {:ok, modified_scene} =
        Storyarn.Scenes.update_scene(scene, %{"name" => "Current scene must survive"})

      before_restore = persisted_scene_state(scene.id)

      invalid_snapshots = [
        {:scene_layer, layer.id, update_snapshot_layer(snapshot, layer.id, &Map.put(&1, "name", ""))},
        {:scene_zone, zone.id,
         update_snapshot_layer_child(snapshot, "zones", zone.id, fn zone_snapshot ->
           Map.put(zone_snapshot, "action_type", "legacy_instruction")
         end)},
        {:scene_pin, pin.id,
         update_snapshot_layer_child(snapshot, "pins", pin.id, fn pin_snapshot ->
           Map.put(pin_snapshot, "patrol_speed", 0.0)
         end)},
        {:scene_annotation, annotation.id,
         update_snapshot_layer_child(snapshot, "annotations", annotation.id, fn annotation_snapshot ->
           Map.put(annotation_snapshot, "font_size", "xxl")
         end)}
      ]

      for {child_type, child_id, invalid_snapshot} <- invalid_snapshots do
        assert {:error, {:invalid_scene_child_snapshot, ^child_type, ^child_id, validation_errors}} =
                 SceneBuilder.restore_snapshot(modified_scene, invalid_snapshot,
                   restore_action: {:entity_version_restore, "scene"}
                 )

        assert validation_errors != %{}
        assert persisted_scene_state(scene.id) == before_restore
      end
    end

    test "rejects incoherent zone target contracts without mutation", %{scene: scene} do
      layer = layer_fixture(scene, %{"name" => "Portal layer"})

      zone =
        zone_fixture(scene, %{
          "name" => "Portal",
          "layer_id" => layer.id,
          "target_type" => "scene",
          "target_id" => scene.id,
          "action_type" => "action",
          "action_data" => %{"assignments" => []}
        })

      snapshot = SceneBuilder.build_snapshot(scene)

      {:ok, current_scene} =
        Storyarn.Scenes.update_scene(scene, %{"name" => "Current scene must survive"})

      before_restore = persisted_scene_state(scene.id)

      invalid_contracts = [
        {"display", "scene", scene.id,
         %{
           "action_type" => "display",
           "action_data" => %{"variable_ref" => "hero.health"}
         }},
        {"action", "scene", nil, %{"target_id" => nil}},
        {"action", nil, scene.id, %{"target_type" => nil}},
        {"action", "sheet", scene.id, %{"target_type" => "sheet"}}
      ]

      for {normalized_action_type, target_type, target_id, changes} <- invalid_contracts do
        invalid_snapshot =
          update_snapshot_layer_child(snapshot, "zones", zone.id, &Map.merge(&1, changes))

        expected_error =
          {:invalid_scene_zone_target_contract, zone.id, normalized_action_type, target_type, target_id}

        assert {:error, ^expected_error} =
                 SceneBuilder.restore_snapshot(current_scene, invalid_snapshot,
                   restore_action: {:entity_version_restore, "scene"}
                 )

        assert persisted_scene_state(scene.id) == before_restore
      end
    end

    test "rejects restoring a collection whose referenced sheet is no longer active", %{
      project: project,
      scene: scene
    } do
      target_sheet = sheet_fixture(project)
      item_id = Ecto.UUID.generate()

      zone_fixture(scene, %{
        "name" => "Roster",
        "action_type" => "collection",
        "action_data" => %{
          "items" => [
            %{"id" => item_id, "label" => "Target", "sheet_id" => target_sheet.id}
          ]
        }
      })

      snapshot = SceneBuilder.build_snapshot(scene)

      {:ok, current_scene} =
        Storyarn.Scenes.update_scene(scene, %{
          "name" => "Current scene must survive"
        })

      {:ok, _deleted_sheet} = Storyarn.Sheets.delete_sheet(target_sheet)
      before_restore = persisted_scene_state(scene.id)

      assert {:error, {:scene_reference_not_found, :sheet, sheet_id}} =
               SceneBuilder.restore_snapshot(
                 current_scene,
                 snapshot,
                 restore_action: {:entity_version_restore, "scene"}
               )

      assert sheet_id == target_sheet.id
      assert persisted_scene_state(scene.id) == before_restore
      assert Repo.get!(Scene, scene.id).name == "Current scene must survive"
    end

    test "reconciles exact child state with stable ids and is idempotent", %{
      scene: scene
    } do
      {:ok, scene} =
        Storyarn.Scenes.update_scene(scene, %{
          "exploration_display_mode" => "scaled"
        })

      layer = layer_fixture(scene, %{"name" => "Snapshot layer"})

      zone =
        zone_fixture(scene, %{
          "name" => "Snapshot zone",
          "layer_id" => layer.id
        })

      pin_a =
        pin_fixture(scene, %{
          "label" => "Snapshot A",
          "layer_id" => layer.id,
          "patrol_mode" => "ping_pong",
          "patrol_speed" => 2.25,
          "patrol_pause_ms" => 750
        })

      pin_b =
        pin_fixture(scene, %{
          "label" => "Snapshot B",
          "layer_id" => layer.id
        })

      annotation =
        annotation_fixture(scene, %{
          "text" => "Snapshot note",
          "layer_id" => layer.id
        })

      connection = connection_fixture(scene, pin_a, pin_b)
      snapshot = SceneBuilder.build_snapshot(scene)

      {:ok, _updated_pin} =
        Storyarn.Scenes.update_pin(pin_a, %{
          "patrol_mode" => "none",
          "patrol_speed" => 1.0,
          "patrol_pause_ms" => 0
        })

      {:ok, modified_scene} =
        Storyarn.Scenes.update_scene(scene, %{
          "name" => "Modified scene",
          "exploration_display_mode" => "fit"
        })

      extra_layer = layer_fixture(scene, %{"name" => "Post snapshot layer"})
      extra_zone = zone_fixture(scene, %{"name" => "Post snapshot zone"})
      extra_pin = pin_fixture(scene, %{"label" => "Post snapshot pin"})
      extra_annotation = annotation_fixture(scene, %{"text" => "Post snapshot note"})
      extra_connection = connection_fixture(scene, extra_pin, pin_b)

      assert {:ok, restored} =
               SceneBuilder.restore_snapshot(modified_scene, snapshot, restore_action: {:entity_version_restore, "scene"})

      assert restored.exploration_display_mode == "scaled"

      assert %SceneLayer{id: layer_id} = Repo.get(SceneLayer, layer.id)
      assert layer_id == layer.id
      assert %SceneZone{id: zone_id} = Repo.get(SceneZone, zone.id)
      assert zone_id == zone.id

      assert %ScenePin{
               id: pin_id,
               patrol_mode: "ping_pong",
               patrol_speed: 2.25,
               patrol_pause_ms: 750
             } = Repo.get(ScenePin, pin_a.id)

      assert pin_id == pin_a.id
      assert %SceneAnnotation{id: annotation_id} = Repo.get(SceneAnnotation, annotation.id)
      assert annotation_id == annotation.id
      assert %SceneConnection{id: connection_id} = Repo.get(SceneConnection, connection.id)
      assert connection_id == connection.id

      assert is_nil(Repo.get(SceneLayer, extra_layer.id))
      assert is_nil(Repo.get(SceneZone, extra_zone.id))
      assert is_nil(Repo.get(ScenePin, extra_pin.id))
      assert is_nil(Repo.get(SceneAnnotation, extra_annotation.id))
      assert is_nil(Repo.get(SceneConnection, extra_connection.id))

      assert {:ok, _restored_again} =
               SceneBuilder.restore_snapshot(restored, snapshot, restore_action: {:entity_version_restore, "scene"})

      assert Repo.get!(ScenePin, pin_a.id).patrol_mode == "ping_pong"
      assert Repo.get!(SceneConnection, connection.id).from_pin_id == pin_a.id
      assert Repo.get!(SceneConnection, connection.id).to_pin_id == pin_b.id
    end

    test "reconciles ambient flows exactly with stable ids and is idempotent", %{
      project: project,
      scene: scene
    } do
      timed_flow = FlowsFixtures.flow_fixture(project, %{name: "Timed ambience"})
      event_flow = FlowsFixtures.flow_fixture(project, %{name: "Event ambience"})
      extra_flow = FlowsFixtures.flow_fixture(project, %{name: "Post-snapshot ambience"})

      {:ok, timed_ambient} =
        Storyarn.Scenes.create_ambient_flow(scene.id, %{
          "flow_id" => timed_flow.id,
          "trigger_type" => "timed",
          "trigger_config" => %{"interval_ms" => 2_500},
          "priority" => 7,
          "enabled" => false,
          "position" => 4
        })

      {:ok, event_ambient} =
        Storyarn.Scenes.create_ambient_flow(scene.id, %{
          "flow_id" => event_flow.id,
          "trigger_type" => "on_event",
          "trigger_config" => %{"variable_ref" => "world.alert"},
          "priority" => 2,
          "enabled" => true,
          "position" => 1
        })

      snapshot = SceneBuilder.build_snapshot(scene)

      {:ok, _mutated} =
        Storyarn.Scenes.update_ambient_flow(timed_ambient, %{
          "trigger_type" => "on_enter",
          "trigger_config" => %{},
          "priority" => 0,
          "enabled" => true,
          "position" => 0
        })

      Repo.delete!(event_ambient)

      {:ok, extra_ambient} =
        Storyarn.Scenes.create_ambient_flow(scene.id, %{
          "flow_id" => extra_flow.id,
          "trigger_type" => "one_shot",
          "priority" => 99,
          "enabled" => true,
          "position" => 8
        })

      assert {:ok, restored} =
               SceneBuilder.restore_snapshot(scene, snapshot, restore_action: {:entity_version_restore, "scene"})

      assert Ecto.assoc_loaded?(restored.ambient_flows)

      assert %SceneAmbientFlow{
               id: timed_id,
               flow_id: timed_flow_id,
               trigger_type: "timed",
               trigger_config: %{"interval_ms" => 2_500},
               priority: 7,
               enabled: false,
               position: 4
             } = Repo.get(SceneAmbientFlow, timed_ambient.id)

      assert timed_id == timed_ambient.id
      assert timed_flow_id == timed_flow.id

      assert %SceneAmbientFlow{
               id: event_id,
               flow_id: event_flow_id,
               trigger_type: "on_event",
               trigger_config: %{"variable_ref" => "world.alert"},
               priority: 2,
               enabled: true,
               position: 1
             } = Repo.get(SceneAmbientFlow, event_ambient.id)

      assert event_id == event_ambient.id
      assert event_flow_id == event_flow.id
      assert is_nil(Repo.get(SceneAmbientFlow, extra_ambient.id))

      assert {:ok, restored_again} =
               SceneBuilder.restore_snapshot(restored, snapshot, restore_action: {:entity_version_restore, "scene"})

      assert Ecto.assoc_loaded?(restored_again.ambient_flows)

      assert Enum.sort(Enum.map(restored_again.ambient_flows, & &1.id)) ==
               Enum.sort([timed_ambient.id, event_ambient.id])
    end

    test "rejects ambient ids and flows owned outside the scene project before mutation", %{
      user: user,
      project: project,
      scene: scene
    } do
      local_flow = FlowsFixtures.flow_fixture(project, %{name: "Local ambience"})

      {:ok, local_ambient} =
        Storyarn.Scenes.create_ambient_flow(scene.id, %{
          "flow_id" => local_flow.id,
          "trigger_type" => "on_enter"
        })

      snapshot = SceneBuilder.build_snapshot(scene)
      other_scene = scene_fixture(project)
      other_flow = FlowsFixtures.flow_fixture(project, %{name: "Other scene ambience"})

      {:ok, foreign_ambient} =
        Storyarn.Scenes.create_ambient_flow(other_scene.id, %{
          "flow_id" => other_flow.id,
          "trigger_type" => "on_enter"
        })

      {:ok, modified_scene} =
        Storyarn.Scenes.update_scene(scene, %{"name" => "Must survive ambient validation"})

      foreign_id_snapshot =
        Map.update!(snapshot, "ambient_flows", fn ambient_flows ->
          Enum.map(
            ambient_flows,
            &Map.put(&1, "original_id", foreign_ambient.id)
          )
        end)

      assert {:error, {:snapshot_original_id_ownership_mismatch, :scene_ambient_flow, foreign_id, scene_id}} =
               SceneBuilder.restore_snapshot(modified_scene, foreign_id_snapshot,
                 restore_action: {:entity_version_restore, "scene"}
               )

      assert foreign_id == foreign_ambient.id
      assert scene_id == scene.id
      assert Repo.get!(Scene, scene.id).name == "Must survive ambient validation"
      assert Repo.get!(SceneAmbientFlow, local_ambient.id).flow_id == local_flow.id

      foreign_project = project_fixture(user)

      foreign_flow =
        FlowsFixtures.flow_fixture(foreign_project, %{name: "Foreign project ambience"})

      foreign_flow_snapshot =
        Map.update!(snapshot, "ambient_flows", fn ambient_flows ->
          Enum.map(ambient_flows, &Map.put(&1, "flow_id", foreign_flow.id))
        end)

      assert {:error,
              {:scene_ambient_flow_flow_project_mismatch, foreign_flow_id, expected_project_id, actual_project_id}} =
               SceneBuilder.restore_snapshot(modified_scene, foreign_flow_snapshot,
                 restore_action: {:entity_version_restore, "scene"}
               )

      assert foreign_flow_id == foreign_flow.id
      assert expected_project_id == project.id
      assert actual_project_id == foreign_project.id
      assert Repo.get!(Scene, scene.id).name == "Must survive ambient validation"
      assert Repo.get!(SceneAmbientFlow, local_ambient.id).flow_id == local_flow.id
    end

    test "rejects duplicate ambient flow ids before mutation", %{
      project: project,
      scene: scene
    } do
      first_flow = FlowsFixtures.flow_fixture(project, %{name: "First ambience"})
      second_flow = FlowsFixtures.flow_fixture(project, %{name: "Second ambience"})

      {:ok, first_ambient} =
        Storyarn.Scenes.create_ambient_flow(scene.id, %{
          "flow_id" => first_flow.id,
          "trigger_type" => "on_enter"
        })

      {:ok, second_ambient} =
        Storyarn.Scenes.create_ambient_flow(scene.id, %{
          "flow_id" => second_flow.id,
          "trigger_type" => "one_shot"
        })

      duplicate_snapshot =
        scene
        |> SceneBuilder.build_snapshot()
        |> Map.update!("ambient_flows", fn ambient_flows ->
          Enum.map(ambient_flows, fn
            %{"original_id" => id} = ambient_flow
            when id == second_ambient.id ->
              Map.put(ambient_flow, "flow_id", first_flow.id)

            ambient_flow ->
              ambient_flow
          end)
        end)

      {:ok, modified_scene} =
        Storyarn.Scenes.update_scene(scene, %{
          "name" => "Must survive duplicate ambience"
        })

      before_restore = persisted_scene_state(scene.id)

      assert {:error, {:duplicate_scene_snapshot_value, :scene_ambient_flow_flow_id}} =
               SceneBuilder.restore_snapshot(modified_scene, duplicate_snapshot,
                 restore_action: {:entity_version_restore, "scene"}
               )

      assert persisted_scene_state(scene.id) == before_restore
      assert Repo.get!(SceneAmbientFlow, first_ambient.id).flow_id == first_flow.id
      assert Repo.get!(SceneAmbientFlow, second_ambient.id).flow_id == second_flow.id
    end

    test "restores valid zero and false values and preserves walkable action data exactly", %{
      scene: scene
    } do
      {:ok, scene} = Storyarn.Scenes.update_scene(scene, %{"fog_opacity" => 0.0})

      layer =
        layer_fixture(scene, %{
          "name" => "Zero-value layer",
          "visible" => false,
          "fog_enabled" => false
        })

      walkable_action_data = %{
        "metadata" => %{
          "cost" => 0,
          "enabled" => false
        }
      }

      zone =
        zone_fixture(scene, %{
          "name" => "Zero-value zone",
          "layer_id" => layer.id,
          "border_width" => 0,
          "opacity" => 0.0,
          "hidden" => false,
          "locked" => false,
          "action_type" => "walkable",
          "action_data" => walkable_action_data,
          "is_walkable" => true
        })

      pin_a =
        pin_fixture(scene, %{
          "label" => "Zero-value A",
          "layer_id" => layer.id,
          "opacity" => 0.0,
          "hidden" => false,
          "locked" => false,
          "is_playable" => false,
          "is_leader" => false
        })

      pin_b = pin_fixture(scene, %{"label" => "Zero-value B", "layer_id" => layer.id})

      connection =
        connection_fixture(scene, pin_a, pin_b, %{
          "line_width" => 0,
          "bidirectional" => false,
          "show_label" => false,
          "from_stop" => false,
          "to_stop" => false
        })

      snapshot = SceneBuilder.build_snapshot(scene)

      {:ok, modified_scene} = Storyarn.Scenes.update_scene(scene, %{"fog_opacity" => 0.8})
      {:ok, _layer} = Storyarn.Scenes.update_layer(layer, %{"visible" => true, "fog_enabled" => true})

      {:ok, _zone} =
        Storyarn.Scenes.update_zone(zone, %{
          "border_width" => 5,
          "opacity" => 0.75,
          "hidden" => true,
          "locked" => true,
          "action_data" => %{}
        })

      {:ok, _pin} =
        Storyarn.Scenes.update_pin(pin_a, %{
          "opacity" => 0.75,
          "hidden" => true,
          "locked" => true,
          "is_playable" => true
        })

      {:ok, _connection} =
        Storyarn.Scenes.update_connection(connection, %{
          "line_width" => 5,
          "bidirectional" => true,
          "show_label" => true,
          "from_stop" => true,
          "to_stop" => true
        })

      assert {:ok, restored} =
               SceneBuilder.restore_snapshot(modified_scene, snapshot, restore_action: {:entity_version_restore, "scene"})

      assert restored.fog_opacity == 0.0
      assert %{visible: false, fog_enabled: false} = Repo.get!(SceneLayer, layer.id)

      restored_zone = Repo.get!(SceneZone, zone.id)

      assert %{
               border_width: 0,
               hidden: false,
               locked: false,
               action_type: "walkable",
               action_data: ^walkable_action_data,
               is_walkable: true
             } = restored_zone

      assert restored_zone.opacity == 0.0

      restored_pin = Repo.get!(ScenePin, pin_a.id)

      assert %{
               hidden: false,
               locked: false,
               is_playable: false,
               is_leader: false
             } = restored_pin

      assert restored_pin.opacity == 0.0

      assert %{
               line_width: 0,
               bidirectional: false,
               show_label: false,
               from_stop: false,
               to_stop: false
             } = Repo.get!(SceneConnection, connection.id)
    end

    test "recreates a hard-deleted historical pin and cascaded connection with their original ids", %{
      scene: scene
    } do
      layer = layer_fixture(scene, %{"name" => "Historical layer"})
      pin_a = pin_fixture(scene, %{"label" => "Historical A", "layer_id" => layer.id})
      pin_b = pin_fixture(scene, %{"label" => "Historical B", "layer_id" => layer.id})
      connection = connection_fixture(scene, pin_a, pin_b)
      snapshot = SceneBuilder.build_snapshot(scene)

      Repo.delete!(pin_a)

      assert is_nil(Repo.get(ScenePin, pin_a.id))
      assert is_nil(Repo.get(SceneConnection, connection.id))

      {:ok, modified_scene} =
        Storyarn.Scenes.update_scene(scene, %{"name" => "Modified after hard delete"})

      assert {:ok, restored} =
               SceneBuilder.restore_snapshot(modified_scene, snapshot, restore_action: {:entity_version_restore, "scene"})

      assert %ScenePin{id: restored_pin_id, layer_id: restored_layer_id} =
               Repo.get(ScenePin, pin_a.id)

      assert restored_pin_id == pin_a.id
      assert restored_layer_id == layer.id

      assert %SceneConnection{
               id: restored_connection_id,
               from_pin_id: restored_from_pin_id,
               to_pin_id: restored_to_pin_id
             } = Repo.get(SceneConnection, connection.id)

      assert restored_connection_id == connection.id
      assert restored_from_pin_id == pin_a.id
      assert restored_to_pin_id == pin_b.id

      assert {:ok, _restored_again} =
               SceneBuilder.restore_snapshot(restored, snapshot, restore_action: {:entity_version_restore, "scene"})

      assert Repo.get!(ScenePin, pin_a.id).id == pin_a.id
      assert Repo.get!(SceneConnection, connection.id).from_pin_id == pin_a.id
    end

    test "restores swapped pin and zone shortcuts and the leader without unique conflicts", %{
      scene: scene
    } do
      pin_a =
        pin_fixture(scene, %{
          "label" => "Alpha pin",
          "shortcut" => "alpha-pin",
          "is_playable" => true,
          "is_leader" => true
        })

      pin_b =
        pin_fixture(scene, %{
          "label" => "Beta pin",
          "shortcut" => "beta-pin",
          "is_playable" => true
        })

      zone_a = zone_fixture(scene, %{"name" => "Alpha zone", "shortcut" => "alpha-zone"})
      zone_b = zone_fixture(scene, %{"name" => "Beta zone", "shortcut" => "beta-zone"})
      snapshot = SceneBuilder.build_snapshot(scene)

      Repo.update_all(
        from(pin in ScenePin, where: pin.id in ^[pin_a.id, pin_b.id]),
        set: [shortcut: nil, is_leader: false]
      )

      Repo.update_all(
        from(pin in ScenePin, where: pin.id == ^pin_a.id),
        set: [shortcut: "beta-pin"]
      )

      Repo.update_all(
        from(pin in ScenePin, where: pin.id == ^pin_b.id),
        set: [shortcut: "alpha-pin", is_leader: true]
      )

      Repo.update_all(
        from(zone in SceneZone, where: zone.id in ^[zone_a.id, zone_b.id]),
        set: [shortcut: nil]
      )

      Repo.update_all(
        from(zone in SceneZone, where: zone.id == ^zone_a.id),
        set: [shortcut: "beta-zone"]
      )

      Repo.update_all(
        from(zone in SceneZone, where: zone.id == ^zone_b.id),
        set: [shortcut: "alpha-zone"]
      )

      assert {:ok, restored} =
               SceneBuilder.restore_snapshot(scene, snapshot, restore_action: {:entity_version_restore, "scene"})

      assert %{shortcut: "alpha-pin", is_leader: true} = Repo.get!(ScenePin, pin_a.id)
      assert %{shortcut: "beta-pin", is_leader: false} = Repo.get!(ScenePin, pin_b.id)
      assert Repo.get!(SceneZone, zone_a.id).shortcut == "alpha-zone"
      assert Repo.get!(SceneZone, zone_b.id).shortcut == "beta-zone"

      assert {:ok, _restored_again} =
               SceneBuilder.restore_snapshot(restored, snapshot, restore_action: {:entity_version_restore, "scene"})

      assert %{shortcut: "alpha-pin", is_leader: true} = Repo.get!(ScenePin, pin_a.id)
      assert %{shortcut: "beta-pin", is_leader: false} = Repo.get!(ScenePin, pin_b.id)
    end

    test "rejects child ids owned by another scene before mutation", %{
      project: project,
      scene: scene
    } do
      pin = pin_fixture(scene, %{"label" => "Owned pin"})
      other_scene = scene_fixture(project)
      foreign_pin = pin_fixture(other_scene, %{"label" => "Foreign pin"})

      snapshot =
        scene
        |> SceneBuilder.build_snapshot()
        |> Map.update!("orphan_pins", fn pins ->
          Enum.map(pins, fn
            %{"original_id" => id} = pin_snapshot when id == pin.id ->
              Map.put(pin_snapshot, "original_id", foreign_pin.id)

            pin_snapshot ->
              pin_snapshot
          end)
        end)

      {:ok, modified_scene} =
        Storyarn.Scenes.update_scene(scene, %{"name" => "Must survive"})

      assert {:error, {:snapshot_original_id_ownership_mismatch, :scene_pin, foreign_pin_id, scene_id}} =
               SceneBuilder.restore_snapshot(modified_scene, snapshot, restore_action: {:entity_version_restore, "scene"})

      assert foreign_pin_id == foreign_pin.id
      assert scene_id == scene.id
      assert Repo.get!(Scene, scene.id).name == "Must survive"
      assert Repo.get!(ScenePin, pin.id).id == pin.id
    end

    test "rejects dangling connection endpoints before mutation", %{scene: scene} do
      pin_a = pin_fixture(scene, %{"label" => "A"})
      pin_b = pin_fixture(scene, %{"label" => "B"})
      connection = connection_fixture(scene, pin_a, pin_b)

      snapshot =
        scene
        |> SceneBuilder.build_snapshot()
        |> Map.update!("connections", fn connections ->
          Enum.map(connections, fn
            %{"original_id" => id} = connection_snapshot
            when id == connection.id ->
              Map.put(connection_snapshot, "to_pin_original_id", 9_999_999)

            connection_snapshot ->
              connection_snapshot
          end)
        end)

      {:ok, modified_scene} =
        Storyarn.Scenes.update_scene(scene, %{"name" => "Still modified"})

      assert {:error, {:scene_connection_pin_not_in_snapshot, 9_999_999}} =
               SceneBuilder.restore_snapshot(modified_scene, snapshot, restore_action: {:entity_version_restore, "scene"})

      assert Repo.get!(Scene, scene.id).name == "Still modified"
      assert Repo.get!(SceneConnection, connection.id).id == connection.id
    end

    test "rejects a valid endpoint id that disagrees with its snapshot indexes", %{
      scene: scene
    } do
      layer = layer_fixture(scene, %{"name" => "Indexed pins"})
      pin_a = pin_fixture(scene, %{"label" => "A", "layer_id" => layer.id, "position" => 0})
      pin_b = pin_fixture(scene, %{"label" => "B", "layer_id" => layer.id, "position" => 1})
      pin_c = pin_fixture(scene, %{"label" => "C", "layer_id" => layer.id, "position" => 2})
      connection = connection_fixture(scene, pin_a, pin_b)
      snapshot = SceneBuilder.build_snapshot(scene)

      original_connection =
        Enum.find(snapshot["connections"], &(&1["original_id"] == connection.id))

      mismatched_snapshot =
        Map.update!(snapshot, "connections", fn connections ->
          Enum.map(connections, fn
            %{"original_id" => id} = connection_snapshot
            when id == connection.id ->
              Map.put(connection_snapshot, "to_pin_original_id", pin_c.id)

            connection_snapshot ->
              connection_snapshot
          end)
        end)

      {:ok, modified_scene} =
        Storyarn.Scenes.update_scene(scene, %{"name" => "Index mismatch must not restore"})

      before_restore = persisted_scene_state(scene.id)

      assert {:error,
              {:scene_connection_endpoint_index_mismatch, connection_id, :to, direct_pin_id, layer_index, pin_index,
               indexed_pin_id}} =
               SceneBuilder.restore_snapshot(modified_scene, mismatched_snapshot,
                 restore_action: {:entity_version_restore, "scene"}
               )

      assert connection_id == connection.id
      assert direct_pin_id == pin_c.id
      assert layer_index == original_connection["to_layer_index"]
      assert pin_index == original_connection["to_pin_index"]
      assert indexed_pin_id == pin_b.id
      assert persisted_scene_state(scene.id) == before_restore
    end

    test "rebuilds scene pin and zone entity references", %{
      project: project,
      scene: scene
    } do
      sheet = sheet_fixture(project)
      target_scene = scene_fixture(project)

      pin =
        pin_fixture(scene, %{
          "label" => "Referenced pin",
          "sheet_id" => sheet.id
        })

      zone =
        zone_fixture(scene, %{
          "name" => "Referenced zone",
          "target_type" => "scene",
          "target_id" => target_scene.id,
          "action_type" => "action"
        })

      snapshot = SceneBuilder.build_snapshot(scene)

      {:ok, _pin} = Storyarn.Scenes.update_pin(pin, %{"sheet_id" => nil})

      {:ok, _zone} =
        Storyarn.Scenes.update_zone(zone, %{
          "target_type" => nil,
          "target_id" => nil
        })

      assert {:ok, _restored} =
               SceneBuilder.restore_snapshot(scene, snapshot, restore_action: {:entity_version_restore, "scene"})

      assert Repo.exists?(
               from(reference in EntityReference,
                 where:
                   reference.source_type == "scene_pin" and
                     reference.source_id == ^pin.id and
                     reference.target_type == "sheet" and
                     reference.target_id == ^sheet.id
               )
             )

      assert Repo.exists?(
               from(reference in EntityReference,
                 where:
                   reference.source_type == "scene_zone" and
                     reference.source_id == ^zone.id and
                     reference.target_type == "scene" and
                     reference.target_id == ^target_scene.id
               )
             )
    end

    test "deleting post-snapshot pins and zones also removes their entity and variable references", %{
      project: project,
      scene: scene
    } do
      snapshot = SceneBuilder.build_snapshot(scene)
      sheet = sheet_fixture(project)
      block = block_fixture(sheet, %{type: "number", is_constant: false})
      extra_pin = pin_fixture(scene, %{"label" => "Post-snapshot pin"})
      extra_zone = zone_fixture(scene, %{"name" => "Post-snapshot zone"})

      Repo.insert!(%EntityReference{
        source_type: "scene_pin",
        source_id: extra_pin.id,
        target_type: "sheet",
        target_id: sheet.id,
        context: "sheet_id"
      })

      Repo.insert!(%EntityReference{
        source_type: "scene_zone",
        source_id: extra_zone.id,
        target_type: "scene",
        target_id: scene.id,
        context: "target"
      })

      Repo.insert!(%VariableReference{
        source_type: "scene_pin",
        source_id: extra_pin.id,
        block_id: block.id,
        kind: "read",
        source_sheet: sheet.shortcut,
        source_variable: block.variable_name
      })

      Repo.insert!(%VariableReference{
        source_type: "scene_zone",
        source_id: extra_zone.id,
        block_id: block.id,
        kind: "write",
        source_sheet: sheet.shortcut,
        source_variable: block.variable_name
      })

      assert scene_source_reference_count(EntityReference, extra_pin.id, extra_zone.id) == 2
      assert scene_source_reference_count(VariableReference, extra_pin.id, extra_zone.id) == 2

      assert {:ok, _restored} =
               SceneBuilder.restore_snapshot(scene, snapshot, restore_action: {:entity_version_restore, "scene"})

      assert is_nil(Repo.get(ScenePin, extra_pin.id))
      assert is_nil(Repo.get(SceneZone, extra_zone.id))
      assert scene_source_reference_count(EntityReference, extra_pin.id, extra_zone.id) == 0
      assert scene_source_reference_count(VariableReference, extra_pin.id, extra_zone.id) == 0
    end

    test "rolls back scene and child mutations when a snapshotted asset blob is unavailable", %{
      user: user,
      project: project,
      scene: scene
    } do
      asset = uploaded_image_asset(project, user, "missing-zone-icon.png", "missing-zone-icon")
      layer = layer_fixture(scene, %{"name" => "Snapshot layer"})

      _zone =
        zone_fixture(scene, %{
          "name" => "Snapshot zone",
          "layer_id" => layer.id,
          "label_mode" => "icon",
          "label_icon_asset_id" => asset.id
        })

      snapshot = SceneBuilder.build_snapshot(scene)

      delete_storage_blob(BlobStore.blob_key(project.id, asset.blob_hash, "png"))

      {:ok, modified_scene} =
        Storyarn.Scenes.update_scene(scene, %{"name" => "Must survive failed asset restore"})

      _extra_pin =
        pin_fixture(scene, %{
          "label" => "Must survive failed asset restore",
          "layer_id" => layer.id
        })

      before_restore = persisted_scene_state(scene.id)

      assert {:error, {:asset_materialization_failed, asset_id, {:asset_blob_unavailable, _reason}}} =
               SceneBuilder.restore_snapshot(modified_scene, snapshot,
                 restore_action: {:entity_version_restore, "scene"},
                 user_id: user.id
               )

      assert asset_id == asset.id
      assert persisted_scene_state(scene.id) == before_restore
    end

    test "discards asset compensation before post-commit preloads", %{
      user: user,
      project: project,
      scene: scene
    } do
      {scene, _asset, _pin, _zone} =
        scene_with_shared_visual_asset(scene, project, user, "scene-post-commit-boundary")

      snapshot = SceneBuilder.build_snapshot(scene)
      handler_id = "scene-restore-post-commit-#{System.unique_integer([:positive])}"
      marker = make_ref()
      test_pid = self()

      :ok =
        :telemetry.attach(
          handler_id,
          [:storyarn, :repo, :query],
          fn _event, _measurements, %{query: query}, {pid, ref} ->
            if self() == pid and
                 not Repo.in_transaction?() and
                 String.contains?(query, ~s(FROM "assets")) do
              tracker_active? =
                Enum.any?(Process.get(), fn
                  {{Storyarn.Assets.StorageCompensation, tracker}, _tracked}
                  when is_reference(tracker) ->
                    true

                  _entry ->
                    false
                end)

              send(pid, {ref, tracker_active?})
            end
          end,
          {test_pid, marker}
        )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      assert {:ok, _restored} =
               SceneBuilder.restore_snapshot(scene, snapshot,
                 restore_action: {:entity_version_restore, "scene"},
                 user_id: user.id
               )

      assert_receive {^marker, false}
      refute_receive {^marker, true}
    end
  end

  describe "instantiate_snapshot/3" do
    test "rejects raw type corruption and invalid layer invariants before writing", %{
      project: project,
      scene: scene
    } do
      snapshot = SceneBuilder.build_snapshot(scene)
      scene_count = Repo.aggregate(Scene, :count)

      invalid_snapshots = [
        Map.put(snapshot, "default_zoom", "1.0"),
        Map.put(snapshot, "layers", []),
        Map.update!(snapshot, "layers", fn layers ->
          Enum.map(layers, &Map.put(&1, "is_default", false))
        end)
      ]

      Enum.each(invalid_snapshots, fn invalid_snapshot ->
        assert {:error, _reason} =
                 SceneBuilder.instantiate_snapshot(project.id, invalid_snapshot, reset_shortcut: true)

        assert Repo.aggregate(Scene, :count) == scene_count
      end)
    end

    test "maps same-position layers and pins by original id, not RETURNING order", %{
      project: project,
      scene: scene
    } do
      layer_a = layer_fixture(scene, %{"name" => "Layer A"})
      layer_b = layer_fixture(scene, %{"name" => "Layer B"})

      Repo.update_all(
        from(layer in SceneLayer, where: layer.id in ^[layer_a.id, layer_b.id]),
        set: [position: 7]
      )

      pin_a = pin_fixture(scene, %{"label" => "Pin A", "layer_id" => layer_a.id, "position" => 3})
      pin_b = pin_fixture(scene, %{"label" => "Pin B", "layer_id" => layer_b.id, "position" => 3})

      Repo.update_all(
        from(pin in ScenePin, where: pin.id in ^[pin_a.id, pin_b.id]),
        set: [position: 3]
      )

      connection = connection_fixture(scene, pin_a, pin_b)

      snapshot = SceneBuilder.build_snapshot(scene)

      assert {:ok, materialized, id_maps} =
               SceneBuilder.instantiate_snapshot(project.id, snapshot, reset_shortcut: true)

      cloned_a = Repo.get!(ScenePin, id_maps.pin[pin_a.id])
      cloned_b = Repo.get!(ScenePin, id_maps.pin[pin_b.id])
      cloned_connection = Repo.get!(SceneConnection, id_maps.connection[connection.id])

      assert cloned_a.label == "Pin A"
      assert cloned_a.layer_id == id_maps.layer[layer_a.id]
      assert cloned_b.label == "Pin B"
      assert cloned_b.layer_id == id_maps.layer[layer_b.id]
      assert cloned_connection.from_pin_id == cloned_a.id
      assert cloned_connection.to_pin_id == cloned_b.id
      assert materialized.id != scene.id
    end

    test "remaps a scene self-reference to the materialized root and rebuilds its backlink", %{
      project: project,
      scene: scene
    } do
      zone =
        zone_fixture(scene, %{
          "name" => "Self portal",
          "target_type" => "scene",
          "target_id" => scene.id,
          "action_type" => "action",
          "action_data" => %{"assignments" => []}
        })

      snapshot = SceneBuilder.build_snapshot(scene)

      assert {:ok, materialized, id_maps} =
               SceneBuilder.instantiate_snapshot(project.id, snapshot,
                 preserve_external_refs: false,
                 reset_shortcut: true
               )

      cloned_zone = Repo.get!(SceneZone, id_maps.zone[zone.id])
      assert cloned_zone.target_type == "scene"
      assert cloned_zone.target_id == materialized.id

      assert Repo.exists?(
               from(reference in EntityReference,
                 where:
                   reference.source_type == "scene_zone" and
                     reference.source_id == ^cloned_zone.id and
                     reference.target_type == "scene" and
                     reference.target_id == ^materialized.id
               )
             )
    end

    test "materializes ambient flows with explicit cross-project flow remapping", %{
      user: user,
      project: project,
      scene: scene
    } do
      source_flow = FlowsFixtures.flow_fixture(project, %{name: "Source ambience"})

      {:ok, source_ambient} =
        Storyarn.Scenes.create_ambient_flow(scene.id, %{
          "flow_id" => source_flow.id,
          "trigger_type" => "timed",
          "trigger_config" => %{"interval_ms" => 4_000},
          "priority" => 6,
          "enabled" => false,
          "position" => 2
        })

      snapshot = SceneBuilder.build_snapshot(scene)
      target_project = project_fixture(user)
      target_flow = FlowsFixtures.flow_fixture(target_project, %{name: "Target ambience"})

      assert {:ok, materialized, id_maps} =
               SceneBuilder.instantiate_snapshot(target_project.id, snapshot,
                 external_id_maps: %{flow: %{source_flow.id => target_flow.id}},
                 reset_shortcut: true
               )

      assert [ambient] = Storyarn.Scenes.list_ambient_flows(materialized.id)
      assert ambient.id == id_maps.ambient_flow[source_ambient.id]
      refute ambient.id == source_ambient.id
      assert ambient.flow_id == target_flow.id
      assert ambient.trigger_type == "timed"
      assert ambient.trigger_config == %{"interval_ms" => 4_000}
      assert ambient.priority == 6
      refute ambient.enabled
      assert ambient.position == 2
    end

    test "materializes a new scene and remaps connection pin ids", %{
      project: project,
      scene: scene
    } do
      layer = layer_fixture(scene, %{"name" => "Gameplay"})

      pin1 =
        pin_fixture(scene, %{
          "position_x" => 20.0,
          "position_y" => 20.0,
          "label" => "A",
          "layer_id" => layer.id
        })

      pin2 =
        pin_fixture(scene, %{
          "position_x" => 80.0,
          "position_y" => 80.0,
          "label" => "B",
          "layer_id" => layer.id
        })

      connection = connection_fixture(scene, pin1, pin2)

      snapshot = SceneBuilder.build_snapshot(scene)

      assert {:ok, materialized, id_maps} =
               SceneBuilder.instantiate_snapshot(project.id, snapshot,
                 reset_shortcut: true,
                 position: 5
               )

      assert materialized.id != scene.id
      assert materialized.position == 5
      assert materialized.shortcut == nil
      assert id_maps.scene == %{scene.id => materialized.id}
      assert id_maps.pin[pin1.id]
      assert id_maps.pin[pin2.id]
      assert id_maps.connection[connection.id]

      pin_ids = materialized.layers |> Enum.flat_map(& &1.pins) |> Enum.map(& &1.id)
      cloned_connection = hd(materialized.connections)

      assert cloned_connection.from_pin_id in pin_ids
      assert cloned_connection.to_pin_id in pin_ids
      assert cloned_connection.from_pin_id != pin1.id
      assert cloned_connection.to_pin_id != pin2.id
    end

    test "rejects legacy or truncated zone payloads before materialization", %{
      project: project,
      scene: scene
    } do
      snapshot =
        scene
        |> SceneBuilder.build_snapshot()
        |> Map.put("orphan_zones", [
          %{
            "name" => "Materialized Display",
            "vertices" => triangle_vertices(),
            "target_type" => "scene",
            "target_id" => scene.id,
            "action_type" => "display",
            "action_data" => %{"variable_ref" => "hero.hp"},
            "is_walkable" => true
          },
          %{
            "name" => "Materialized Unknown",
            "vertices" => triangle_vertices(),
            "action_type" => "event",
            "action_data" => %{}
          },
          %{
            "name" => "Materialized Invalid Target",
            "vertices" => triangle_vertices(),
            "target_type" => "sheet",
            "target_id" => 123,
            "action_type" => "action",
            "action_data" => %{"assignments" => []}
          }
        ])

      scene_count = Repo.aggregate(Scene, :count)

      assert {:error, {:missing_scene_snapshot_field, :scene_zone, nil, "original_id"}} =
               SceneBuilder.instantiate_snapshot(project.id, snapshot, reset_shortcut: true)

      assert Repo.aggregate(Scene, :count) == scene_count
    end

    test "rejects incoherent zone target contracts before materialization", %{
      project: project,
      scene: scene
    } do
      layer = layer_fixture(scene, %{"name" => "Portal layer"})

      zone =
        zone_fixture(scene, %{
          "name" => "Portal",
          "layer_id" => layer.id,
          "target_type" => "scene",
          "target_id" => scene.id,
          "action_type" => "action",
          "action_data" => %{"assignments" => []}
        })

      snapshot = SceneBuilder.build_snapshot(scene)
      scene_count = Repo.aggregate(Scene, :count)
      zone_count = Repo.aggregate(SceneZone, :count)

      invalid_contracts = [
        {"display", "scene", scene.id,
         %{
           "action_type" => "display",
           "action_data" => %{"variable_ref" => "hero.health"}
         }},
        {"action", "scene", nil, %{"target_id" => nil}},
        {"action", nil, scene.id, %{"target_type" => nil}},
        {"action", "sheet", scene.id, %{"target_type" => "sheet"}}
      ]

      for {normalized_action_type, target_type, target_id, changes} <- invalid_contracts do
        invalid_snapshot =
          update_snapshot_layer_child(snapshot, "zones", zone.id, &Map.merge(&1, changes))

        expected_error =
          {:invalid_scene_zone_target_contract, zone.id, normalized_action_type, target_type, target_id}

        assert {:error, ^expected_error} =
                 SceneBuilder.instantiate_snapshot(project.id, invalid_snapshot, reset_shortcut: true)

        assert Repo.aggregate(Scene, :count) == scene_count
        assert Repo.aggregate(SceneZone, :count) == zone_count
      end
    end

    test "rejects malformed collection items before materialization without mutation", %{
      project: project,
      scene: scene
    } do
      layer = layer_fixture(scene, %{"name" => "Collections"})
      item_id = Ecto.UUID.generate()

      zone =
        zone_fixture(scene, %{
          "name" => "Roster",
          "layer_id" => layer.id,
          "action_type" => "collection",
          "action_data" => %{
            "items" => [
              %{"id" => item_id, "label" => "Unassigned", "sheet_id" => nil}
            ]
          }
        })

      snapshot = SceneBuilder.build_snapshot(scene)
      scene_count = Repo.aggregate(Scene, :count)
      zone_count = Repo.aggregate(SceneZone, :count)

      invalid_action_data = [
        {%{}, {:invalid_scene_zone_collection, zone.id, %{}}},
        {%{"items" => ["not-a-map"]}, {:invalid_scene_zone_collection_item, zone.id, 0, :not_a_map, "not-a-map"}},
        {%{"items" => [%{"id" => "not-a-uuid", "sheet_id" => nil}]},
         {:invalid_scene_zone_collection_item, zone.id, 0, :invalid_id, "not-a-uuid"}},
        {%{
           "items" => [
             %{"id" => item_id, "sheet_id" => nil},
             %{"id" => item_id, "sheet_id" => nil}
           ]
         }, {:invalid_scene_zone_collection_item, zone.id, 1, :duplicate_id, item_id}},
        {%{"items" => [%{"id" => item_id, "sheet_id" => 0}]},
         {:invalid_scene_zone_collection_item, zone.id, 0, :invalid_sheet_id, 0}}
      ]

      for {action_data, expected_error} <- invalid_action_data do
        invalid_snapshot =
          update_snapshot_layer_child(
            snapshot,
            "zones",
            zone.id,
            &Map.put(&1, "action_data", action_data)
          )

        assert {:error, ^expected_error} =
                 SceneBuilder.instantiate_snapshot(
                   project.id,
                   invalid_snapshot,
                   reset_shortcut: true
                 )

        assert Repo.aggregate(Scene, :count) == scene_count
        assert Repo.aggregate(SceneZone, :count) == zone_count
      end
    end

    test "preserves collection item ids and remaps their sheets across projects", %{
      user: user,
      project: project,
      scene: scene
    } do
      layer = layer_fixture(scene, %{"name" => "Collections"})
      source_sheet = sheet_fixture(project)
      linked_item_id = Ecto.UUID.generate()
      unlinked_item_id = Ecto.UUID.generate()

      zone =
        zone_fixture(scene, %{
          "name" => "Roster",
          "layer_id" => layer.id,
          "action_type" => "collection",
          "action_data" => %{
            "items" => [
              %{
                "id" => linked_item_id,
                "label" => "Linked",
                "sheet_id" => source_sheet.id
              },
              %{
                "id" => unlinked_item_id,
                "label" => "Unlinked",
                "sheet_id" => nil
              }
            ]
          }
        })

      snapshot = SceneBuilder.build_snapshot(scene)

      assert %{"action_data" => %{"items" => snapshot_items}} =
               snapshot
               |> Map.fetch!("layers")
               |> Enum.find(&(&1["original_id"] == layer.id))
               |> Map.fetch!("zones")
               |> Enum.find(&(&1["original_id"] == zone.id))

      assert Enum.map(snapshot_items, & &1["id"]) ==
               [linked_item_id, unlinked_item_id]

      target_project = project_fixture(user)
      target_sheet = sheet_fixture(target_project)

      assert {:ok, _materialized, id_maps} =
               SceneBuilder.instantiate_snapshot(
                 target_project.id,
                 snapshot,
                 external_id_maps: %{
                   sheet: %{source_sheet.id => target_sheet.id}
                 },
                 reset_shortcut: true
               )

      cloned_zone = Repo.get!(SceneZone, id_maps.zone[zone.id])
      cloned_items = cloned_zone.action_data["items"]

      assert Enum.map(cloned_items, & &1["id"]) ==
               [linked_item_id, unlinked_item_id]

      assert Enum.map(cloned_items, & &1["sheet_id"]) ==
               [target_sheet.id, nil]

      assert Repo.exists?(
               from(reference in EntityReference,
                 where:
                   reference.source_type == "scene_zone" and
                     reference.source_id == ^cloned_zone.id and
                     reference.target_type == "sheet" and
                     reference.target_id == ^target_sheet.id
               )
             )
    end

    test "rolls back scene materialization when a collection sheet cannot be remapped", %{
      user: user,
      project: project,
      scene: scene
    } do
      source_sheet = sheet_fixture(project)
      item_id = Ecto.UUID.generate()

      zone =
        zone_fixture(scene, %{
          "name" => "Roster",
          "action_type" => "collection",
          "action_data" => %{
            "items" => [
              %{"id" => item_id, "label" => "Linked", "sheet_id" => source_sheet.id}
            ]
          }
        })

      snapshot = SceneBuilder.build_snapshot(scene)
      target_project = project_fixture(user)
      scene_count = Repo.aggregate(Scene, :count)
      zone_count = Repo.aggregate(SceneZone, :count)

      expected_error =
        {:unresolved_scene_zone_collection_sheet, zone.id, 0, item_id, source_sheet.id}

      assert {:error, ^expected_error} =
               SceneBuilder.instantiate_snapshot(
                 target_project.id,
                 snapshot,
                 reset_shortcut: true
               )

      assert Repo.aggregate(Scene, :count) == scene_count
      assert Repo.aggregate(SceneZone, :count) == zone_count
    end

    test "materializes orphan pins and remaps explicit sheet refs across projects", %{
      user: user,
      project: project,
      scene: scene
    } do
      source_sheet = sheet_fixture(project)
      pin1 = pin_fixture(scene, %{"label" => "Loose A", "sheet_id" => source_sheet.id})
      pin2 = pin_fixture(scene, %{"label" => "Loose B"})
      connection = connection_fixture(scene, pin1, pin2)
      snapshot = SceneBuilder.build_snapshot(scene)

      target_project = project_fixture(user)
      target_sheet = sheet_fixture(target_project)

      assert {:ok, materialized, id_maps} =
               SceneBuilder.instantiate_snapshot(target_project.id, snapshot,
                 external_id_maps: %{sheet: %{source_sheet.id => target_sheet.id}}
               )

      assert id_maps.pin[pin1.id]
      assert id_maps.pin[pin2.id]
      assert id_maps.connection[connection.id]

      orphan_pin_ids = Enum.map(materialized.pins, & &1.id)
      remapped_pin = Enum.find(materialized.pins, &(&1.label == "Loose A"))
      cloned_connection = hd(materialized.connections)

      assert remapped_pin.sheet_id == target_sheet.id
      assert cloned_connection.from_pin_id in orphan_pin_ids
      assert cloned_connection.to_pin_id in orphan_pin_ids
    end

    test "clears cross-project sheet refs when no external map is provided", %{
      user: user,
      project: project,
      scene: scene
    } do
      source_sheet = sheet_fixture(project)
      _pin = pin_fixture(scene, %{"label" => "Loose A", "sheet_id" => source_sheet.id})
      snapshot = SceneBuilder.build_snapshot(scene)
      target_project = project_fixture(user)

      assert {:ok, materialized, _id_maps} =
               SceneBuilder.instantiate_snapshot(target_project.id, snapshot)

      assert Enum.all?(materialized.pins, &is_nil(&1.sheet_id))
    end

    test "drops scene pin external refs when preserve_external_refs is false", %{
      project: project,
      scene: scene
    } do
      linked_sheet = sheet_fixture(project)
      target_scene = scene_fixture(project)

      _pin =
        pin_fixture(scene, %{
          "label" => "Loose A",
          "sheet_id" => linked_sheet.id,
          "target_type" => "scene",
          "target_id" => target_scene.id
        })

      snapshot = SceneBuilder.build_snapshot(scene)

      assert {:ok, materialized, _id_maps} =
               SceneBuilder.instantiate_snapshot(project.id, snapshot,
                 preserve_external_refs: false,
                 reset_shortcut: true
               )

      assert Enum.all?(materialized.pins, fn pin ->
               is_nil(pin.sheet_id) and is_nil(pin.flow_id)
             end)
    end

    test "preserve_external_refs false does not drop scene assets", %{
      user: user,
      project: project,
      scene: scene
    } do
      {scene, asset, pin, zone} =
        scene_with_shared_visual_asset(scene, project, user, "preserved-scene-asset")

      snapshot = SceneBuilder.build_snapshot(scene)

      assert {:ok, materialized, id_maps} =
               SceneBuilder.instantiate_snapshot(project.id, snapshot,
                 preserve_external_refs: false,
                 reset_shortcut: true,
                 user_id: user.id
               )

      assert materialized.background_asset_id == asset.id
      assert Repo.get!(ScenePin, id_maps.pin[pin.id]).icon_asset_id == asset.id
      assert Repo.get!(SceneZone, id_maps.zone[zone.id]).label_icon_asset_id == asset.id
    end

    test "asset_mode drop explicitly removes background, pin, and zone assets", %{
      user: user,
      project: project,
      scene: scene
    } do
      {scene, _asset, pin, zone} =
        scene_with_shared_visual_asset(scene, project, user, "dropped-scene-asset")

      snapshot = SceneBuilder.build_snapshot(scene)

      assert {:ok, materialized, id_maps} =
               SceneBuilder.instantiate_snapshot(project.id, snapshot,
                 asset_mode: :drop,
                 reset_shortcut: true,
                 user_id: user.id
               )

      assert is_nil(materialized.background_asset_id)
      assert is_nil(Repo.get!(ScenePin, id_maps.pin[pin.id]).icon_asset_id)
      assert is_nil(Repo.get!(SceneZone, id_maps.zone[zone.id]).label_icon_asset_id)
    end

    test "materializes one destination asset shared by background, pin, and zone", %{
      user: user,
      project: project,
      scene: scene
    } do
      {scene, source_asset, pin, zone} =
        scene_with_shared_visual_asset(scene, project, user, "shared-scene-asset")

      snapshot = SceneBuilder.build_snapshot(scene)
      target_project = project_fixture(user)

      assert {:ok, materialized, id_maps} =
               SceneBuilder.instantiate_snapshot(target_project.id, snapshot,
                 asset_mode: :copy,
                 reset_shortcut: true,
                 user_id: user.id
               )

      destination_asset_id = materialized.background_asset_id
      assert is_integer(destination_asset_id)
      refute destination_asset_id == source_asset.id
      assert Repo.get!(ScenePin, id_maps.pin[pin.id]).icon_asset_id == destination_asset_id
      assert Repo.get!(SceneZone, id_maps.zone[zone.id]).label_icon_asset_id == destination_asset_id

      assert 1 ==
               Repo.aggregate(
                 from(asset in Asset,
                   where:
                     asset.project_id == ^target_project.id and
                       asset.blob_hash == ^source_asset.blob_hash
                 ),
                 :count
               )

      destination_asset = Repo.get!(Asset, destination_asset_id)
      on_exit(fn -> Assets.storage_delete(destination_asset.key) end)
    end

    test "copies background, pin icon, and zone label icon assets into destination project", %{
      user: user,
      project: project,
      scene: scene
    } do
      background_asset = uploaded_image_asset(project, user, "map.png", "map-background")
      pin_icon_asset = uploaded_image_asset(project, user, "pin.png", "pin-icon")
      zone_icon_asset = uploaded_image_asset(project, user, "zone.png", "zone-icon")

      {:ok, scene} = Storyarn.Scenes.update_scene(scene, %{"background_asset_id" => background_asset.id})
      layer = layer_fixture(scene)

      _pin =
        pin_fixture(scene, %{
          "label" => "Icon Pin",
          "layer_id" => layer.id,
          "icon_asset_id" => pin_icon_asset.id
        })

      _zone =
        zone_fixture(scene, %{
          "name" => "Icon Zone",
          "layer_id" => layer.id,
          "label_mode" => "icon",
          "label_icon_asset_id" => zone_icon_asset.id
        })

      snapshot = SceneBuilder.build_snapshot(scene)
      target_project = project_fixture(user)

      assert {:ok, materialized, _id_maps} =
               SceneBuilder.instantiate_snapshot(target_project.id, snapshot,
                 asset_mode: :copy,
                 user_id: user.id,
                 reset_shortcut: true
               )

      materialized = Repo.preload(materialized, :background_asset, force: true)
      assert materialized.background_asset.project_id == target_project.id
      refute materialized.background_asset_id == background_asset.id
      assert {:ok, _binary} = Assets.storage_download(materialized.background_asset.key)
      on_exit(fn -> Assets.storage_delete(materialized.background_asset.key) end)

      cloned_pin =
        materialized.id
        |> Storyarn.Scenes.list_pins()
        |> Enum.find(&(&1.label == "Icon Pin"))
        |> Repo.preload(:icon_asset)

      assert cloned_pin.icon_asset.project_id == target_project.id
      refute cloned_pin.icon_asset_id == pin_icon_asset.id
      assert {:ok, _binary} = Assets.storage_download(cloned_pin.icon_asset.key)
      on_exit(fn -> Assets.storage_delete(cloned_pin.icon_asset.key) end)

      cloned_zone =
        materialized.id
        |> Storyarn.Scenes.list_zones()
        |> Enum.find(&(&1.name == "Icon Zone"))

      assert cloned_zone.label_icon_asset.project_id == target_project.id
      refute cloned_zone.label_icon_asset_id == zone_icon_asset.id
      assert {:ok, _binary} = Assets.storage_download(cloned_zone.label_icon_asset.key)
      on_exit(fn -> Assets.storage_delete(cloned_zone.label_icon_asset.key) end)
    end

    test "reuse mode never preserves a source-project asset id in the destination scene", %{
      user: user,
      project: source_project,
      scene: scene
    } do
      source_asset =
        uploaded_image_asset(
          source_project,
          user,
          "foreign-map.png",
          "cross-project-scene-background"
        )

      {:ok, scene} =
        Storyarn.Scenes.update_scene(scene, %{
          "background_asset_id" => source_asset.id
        })

      snapshot = SceneBuilder.build_snapshot(scene)
      destination_project = project_fixture(user)

      assert {:ok, materialized, _id_maps} =
               SceneBuilder.instantiate_snapshot(destination_project.id, snapshot,
                 preserve_external_refs: true,
                 user_id: user.id,
                 reset_shortcut: true
               )

      materialized = Repo.preload(materialized, :background_asset, force: true)

      refute materialized.background_asset_id == source_asset.id
      assert materialized.background_asset.project_id == destination_project.id
      assert materialized.background_asset.blob_hash == source_asset.blob_hash

      assert {:ok, "cross-project-scene-background"} =
               Assets.storage_download(materialized.background_asset.key)

      on_exit(fn -> Assets.storage_delete(materialized.background_asset.key) end)
    end
  end

  describe "scan_references/1" do
    test "extracts background asset, pin, and zone target refs" do
      snapshot = %{
        "background_asset_id" => 100,
        "layers" => [
          %{
            "pins" => [
              %{
                "sheet_id" => 10,
                "icon_asset_id" => 20,
                "flow_id" => 30
              },
              %{
                "sheet_id" => nil,
                "icon_asset_id" => nil,
                "flow_id" => nil
              }
            ],
            "zones" => [
              %{
                "target_type" => "scene",
                "target_id" => 40
              }
            ]
          }
        ],
        "ambient_flows" => [%{"flow_id" => 50}]
      }

      refs = SceneBuilder.scan_references(snapshot)

      types_and_ids = refs |> Enum.map(&{&1.type, &1.id}) |> Enum.sort()

      assert {:asset, 20} in types_and_ids
      assert {:asset, 100} in types_and_ids
      assert {:flow, 30} in types_and_ids
      assert {:flow, 50} in types_and_ids
      assert {:scene, 40} in types_and_ids
      assert {:sheet, 10} in types_and_ids
      assert length(refs) == 6
    end

    test "skips nil references and url targets" do
      snapshot = %{
        "background_asset_id" => nil,
        "layers" => [
          %{
            "pins" => [
              %{
                "sheet_id" => nil,
                "icon_asset_id" => nil,
                "flow_id" => nil
              }
            ],
            "zones" => [
              %{"target_type" => nil, "target_id" => nil}
            ]
          }
        ]
      }

      refs = SceneBuilder.scan_references(snapshot)
      assert refs == []
    end

    test "extracts orphan pin and zone refs" do
      snapshot = %{
        "background_asset_id" => nil,
        "layers" => [],
        "orphan_pins" => [
          %{
            "sheet_id" => 10,
            "icon_asset_id" => 20,
            "flow_id" => 30
          }
        ],
        "orphan_zones" => [
          %{"target_type" => "flow", "target_id" => 40}
        ]
      }

      refs = SceneBuilder.scan_references(snapshot)

      types_and_ids = refs |> Enum.map(&{&1.type, &1.id}) |> Enum.sort()

      assert {:asset, 20} in types_and_ids
      assert {:flow, 30} in types_and_ids
      assert {:flow, 40} in types_and_ids
      assert {:sheet, 10} in types_and_ids
      assert length(refs) == 4
    end

    test "extracts sheet refs from layered and orphan collection items" do
      snapshot = %{
        "background_asset_id" => nil,
        "layers" => [
          %{
            "pins" => [],
            "zones" => [
              %{
                "action_type" => "collection",
                "action_data" => %{
                  "items" => [
                    %{"id" => Ecto.UUID.generate(), "sheet_id" => 10},
                    %{"id" => Ecto.UUID.generate(), "sheet_id" => nil}
                  ]
                },
                "target_type" => nil,
                "target_id" => nil,
                "label_icon_asset_id" => nil
              }
            ]
          }
        ],
        "orphan_zones" => [
          %{
            "action_type" => "collection",
            "action_data" => %{
              "items" => [
                %{"id" => Ecto.UUID.generate(), "sheet_id" => 20}
              ]
            },
            "target_type" => nil,
            "target_id" => nil,
            "label_icon_asset_id" => nil
          }
        ]
      }

      refs = SceneBuilder.scan_references(snapshot)

      assert refs |> Enum.map(&{&1.type, &1.id}) |> Enum.sort() ==
               [{:sheet, 10}, {:sheet, 20}]

      assert Enum.all?(refs, &String.contains?(&1.context, "collection item"))
    end
  end

  describe "diff_snapshots/2" do
    test "detects ambient flow changes by stable identity" do
      old = %{
        "name" => "S",
        "layers" => [],
        "connections" => [],
        "ambient_flows" => [
          %{
            "original_id" => 10,
            "flow_id" => 20,
            "trigger_type" => "on_enter",
            "trigger_config" => %{},
            "priority" => 0,
            "enabled" => true,
            "position" => 0
          }
        ]
      }

      new =
        put_in(
          old,
          ["ambient_flows", Access.at(0), "priority"],
          8
        )

      assert [
               %{
                 category: :ambient_flow,
                 action: :modified
               }
             ] = SceneBuilder.diff_snapshots(old, new)
    end

    test "detects name change" do
      old = %{"name" => "Old", "shortcut" => "old", "layers" => [], "connections" => []}
      new = %{"name" => "New", "shortcut" => "old", "layers" => [], "connections" => []}

      changes = SceneBuilder.diff_snapshots(old, new)
      assert [%{category: :property, action: :modified, detail: detail}] = changes
      assert detail =~ "Renamed"
    end

    test "detects added pins within matched layers" do
      old_layer = %{
        "position" => 0,
        "name" => "Layer 1",
        "pins" => [],
        "zones" => [],
        "annotations" => []
      }

      new_layer = %{
        "position" => 0,
        "name" => "Layer 1",
        "pins" => [%{"position" => 0, "label" => "A"}],
        "zones" => [],
        "annotations" => []
      }

      old = %{"name" => "S", "layers" => [old_layer], "connections" => []}
      new = %{"name" => "S", "layers" => [new_layer], "connections" => []}

      changes = SceneBuilder.diff_snapshots(old, new)
      assert Enum.any?(changes, &(&1.category == :pin && &1.action == :added))
    end

    test "detects added layers" do
      layer = %{
        "position" => 0,
        "name" => "New Layer",
        "pins" => [],
        "zones" => [],
        "annotations" => []
      }

      old = %{"name" => "S", "layers" => [], "connections" => []}
      new = %{"name" => "S", "layers" => [layer], "connections" => []}

      changes = SceneBuilder.diff_snapshots(old, new)
      assert Enum.any?(changes, &(&1.category == :layer && &1.action == :added))
    end

    test "detects connection changes" do
      conn = %{
        "from_layer_index" => 0,
        "from_pin_index" => 0,
        "to_layer_index" => 0,
        "to_pin_index" => 1
      }

      old = %{"name" => "S", "layers" => [], "connections" => []}
      new = %{"name" => "S", "layers" => [], "connections" => [conn]}

      changes = SceneBuilder.diff_snapshots(old, new)
      assert Enum.any?(changes, &(&1.category == :connection && &1.action == :added))
    end

    test "detects orphan pin changes" do
      old = %{
        "name" => "S",
        "layers" => [],
        "orphan_pins" => [],
        "connections" => []
      }

      new = %{
        "name" => "S",
        "layers" => [],
        "orphan_pins" => [%{"position" => 0, "label" => "Loose A"}],
        "connections" => []
      }

      changes = SceneBuilder.diff_snapshots(old, new)
      assert Enum.any?(changes, &(&1.category == :pin && &1.action == :added))
    end

    test "matches orphan-pin connection changes semantically" do
      orphan_pin = %{"position" => 0, "label" => "Loose A"}

      old = %{
        "name" => "S",
        "layers" => [],
        "orphan_pins" => [orphan_pin],
        "connections" => [
          %{
            "from_layer_index" => -1,
            "from_pin_index" => 0,
            "to_layer_index" => -1,
            "to_pin_index" => 0,
            "label" => "Old"
          }
        ]
      }

      new = %{
        "name" => "S",
        "layers" => [],
        "orphan_pins" => [orphan_pin],
        "connections" => [
          %{
            "from_layer_index" => -1,
            "from_pin_index" => 0,
            "to_layer_index" => -1,
            "to_pin_index" => 0,
            "label" => "New"
          }
        ]
      }

      changes = SceneBuilder.diff_snapshots(old, new)
      assert Enum.any?(changes, &(&1.category == :connection && &1.action == :modified))
    end

    test "does not report identical free routes as added and removed" do
      snapshot = %{
        "name" => "S",
        "layers" => [],
        "connections" => [
          %{
            "from_layer_index" => nil,
            "from_pin_index" => nil,
            "to_layer_index" => nil,
            "to_pin_index" => nil,
            "waypoints" => [
              %{"x" => 10.0, "y" => 10.0},
              %{"x" => 90.0, "y" => 90.0}
            ]
          }
        ]
      }

      assert SceneBuilder.diff_snapshots(snapshot, snapshot) == []
    end

    test "detects route waypoint and stop changes as modified connection" do
      old = %{
        "name" => "S",
        "layers" => [],
        "connections" => [
          %{
            "from_layer_index" => nil,
            "from_pin_index" => nil,
            "to_layer_index" => nil,
            "to_pin_index" => nil,
            "waypoints" => [
              %{"x" => 10.0, "y" => 10.0, "stop" => true, "pauseMs" => 500},
              %{"x" => 90.0, "y" => 90.0}
            ],
            "from_stop" => true,
            "to_stop" => true
          }
        ]
      }

      new = put_in(old, ["connections", Access.at(0), "waypoints", Access.at(0), "pauseMs"], 750)

      changes = SceneBuilder.diff_snapshots(old, new)

      assert Enum.any?(changes, &(&1.category == :connection && &1.action == :modified))
      refute Enum.any?(changes, &(&1.category == :connection && &1.action == :added))
      refute Enum.any?(changes, &(&1.category == :connection && &1.action == :removed))
    end

    test "returns empty list for identical snapshots" do
      snapshot = %{
        "name" => "S",
        "shortcut" => "s",
        "layers" => [],
        "orphan_pins" => [],
        "orphan_zones" => [],
        "orphan_annotations" => [],
        "connections" => []
      }

      assert SceneBuilder.diff_snapshots(snapshot, snapshot) == []
    end
  end

  defp persisted_scene_state(scene_id) do
    %{
      scene: Repo.get!(Scene, scene_id),
      layers:
        Repo.all(
          from(layer in SceneLayer,
            where: layer.scene_id == ^scene_id,
            order_by: layer.id
          )
        ),
      zones:
        Repo.all(
          from(zone in SceneZone,
            where: zone.scene_id == ^scene_id,
            order_by: zone.id
          )
        ),
      pins:
        Repo.all(
          from(pin in ScenePin,
            where: pin.scene_id == ^scene_id,
            order_by: pin.id
          )
        ),
      annotations:
        Repo.all(
          from(annotation in SceneAnnotation,
            where: annotation.scene_id == ^scene_id,
            order_by: annotation.id
          )
        ),
      connections:
        Repo.all(
          from(connection in SceneConnection,
            where: connection.scene_id == ^scene_id,
            order_by: connection.id
          )
        ),
      ambient_flows:
        Repo.all(
          from(ambient_flow in SceneAmbientFlow,
            where: ambient_flow.scene_id == ^scene_id,
            order_by: ambient_flow.id
          )
        )
    }
  end

  defp update_snapshot_layer(snapshot, layer_id, update_fun) do
    Map.update!(snapshot, "layers", fn layers ->
      Enum.map(layers, &maybe_update_snapshot_layer(&1, layer_id, update_fun))
    end)
  end

  defp maybe_update_snapshot_layer(layer, layer_id, update_fun) do
    if layer["original_id"] == layer_id, do: update_fun.(layer), else: layer
  end

  defp update_snapshot_layer_child(snapshot, collection, child_id, update_fun) do
    Map.update!(snapshot, "layers", fn layers ->
      Enum.map(layers, &update_snapshot_layer_children(&1, collection, child_id, update_fun))
    end)
  end

  defp update_snapshot_layer_children(layer, collection, child_id, update_fun) do
    Map.update!(layer, collection, fn children ->
      Enum.map(children, &maybe_update_snapshot_child(&1, child_id, update_fun))
    end)
  end

  defp maybe_update_snapshot_child(child, child_id, update_fun) do
    if child["original_id"] == child_id, do: update_fun.(child), else: child
  end

  defp scene_source_reference_count(schema, pin_id, zone_id) do
    Repo.one(
      from(reference in schema,
        where:
          (reference.source_type == "scene_pin" and reference.source_id == ^pin_id) or
            (reference.source_type == "scene_zone" and reference.source_id == ^zone_id),
        select: count(reference.id)
      )
    )
  end

  defp triangle_vertices do
    [
      %{"x" => 10.0, "y" => 10.0},
      %{"x" => 20.0, "y" => 10.0},
      %{"x" => 15.0, "y" => 20.0}
    ]
  end

  defp scene_with_shared_visual_asset(scene, project, user, content) do
    asset = uploaded_image_asset(project, user, "#{content}.png", content)
    {:ok, scene} = Storyarn.Scenes.update_scene(scene, %{"background_asset_id" => asset.id})
    layer = layer_fixture(scene, %{"name" => "Shared asset layer"})

    pin =
      pin_fixture(scene, %{
        "label" => "Shared asset pin",
        "layer_id" => layer.id,
        "icon_asset_id" => asset.id
      })

    zone =
      zone_fixture(scene, %{
        "name" => "Shared asset zone",
        "layer_id" => layer.id,
        "label_mode" => "icon",
        "label_icon_asset_id" => asset.id
      })

    {scene, asset, pin, zone}
  end

  defp uploaded_image_asset(project, user, filename, content) do
    {:ok, asset} =
      Assets.upload_binary_and_create_asset(
        content,
        %{filename: filename, content_type: "image/png"},
        project,
        user
      )

    on_exit(fn ->
      Assets.storage_delete(asset.key)
      delete_storage_blob(BlobStore.blob_key(project.id, asset.blob_hash, "png"))
    end)

    asset
  end
end
