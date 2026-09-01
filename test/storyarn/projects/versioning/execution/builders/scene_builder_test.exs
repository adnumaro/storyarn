defmodule Storyarn.Projects.Versioning.Builders.SceneBuilderTest do
  use Storyarn.DataCase, async: true
  use Oban.Testing, repo: Storyarn.Repo

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.FlowsFixtures
  alias Storyarn.Projects.Assets
  alias Storyarn.Projects.Assets.Asset
  alias Storyarn.Projects.Assets.BlobStore
  alias Storyarn.Projects.Project
  alias Storyarn.Projects.References.EntityReference
  alias Storyarn.Projects.Versioning.SnapshotReferences.SceneScanner
  alias Storyarn.Repo
  alias Storyarn.Scenes.Scene
  alias Storyarn.Scenes.SceneConnection
  alias Storyarn.Scenes.SceneLayer
  alias Storyarn.Scenes.ScenePin
  alias Storyarn.Scenes.SceneZone
  alias Storyarn.Workers.DeleteStorageObjectsWorker
  alias StoryarnTest.ProjectsSceneBuilderTestAdapter, as: SceneBuilder

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
      refute Map.has_key?(snapshot, "localization")
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

  describe "entity restore ownership" do
    test "does not expose entity-level Scene restore" do
      refute function_exported?(
               Storyarn.Projects.Versioning.Builders.SceneBuilder,
               :restore_snapshot,
               3
             )
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

    test "exact materialization stages a purged captured endpoint and remaps it through the global pin map", %{
      user: user,
      project: project,
      scene: scene
    } do
      layer = layer_fixture(scene, %{"name" => "Local pins"})
      local_from = pin_fixture(scene, %{"label" => "Local from", "layer_id" => layer.id})
      local_to = pin_fixture(scene, %{"label" => "Local to", "layer_id" => layer.id})
      connection = connection_fixture(scene, local_from, local_to)

      external_scene = scene_fixture(project)
      external_pin = pin_fixture(external_scene, %{"label" => "Captured elsewhere"})

      Repo.update_all(
        from(current in SceneConnection, where: current.id == ^connection.id),
        set: [from_pin_id: external_pin.id]
      )

      external_snapshot = SceneBuilder.build_capture_snapshot(external_scene)
      snapshot = SceneBuilder.build_capture_snapshot(scene)
      captured_connection = hd(snapshot["connections"])
      assert captured_connection["from_pin_original_id"] == external_pin.id
      assert captured_connection["from_layer_index"] == nil
      assert captured_connection["from_pin_index"] == nil

      Repo.delete!(external_pin)

      target_project = project_fixture(user)

      assert {:ok, _temporarily_materialized, temporary_id_maps} =
               SceneBuilder.instantiate_snapshot(target_project.id, snapshot,
                 materialization_mode: :exact,
                 rebuild_references: false,
                 reset_shortcut: true
               )

      temporary_connection = Repo.get!(SceneConnection, temporary_id_maps.connection[connection.id])
      assert temporary_connection.from_pin_id == nil
      assert temporary_connection.to_pin_id == temporary_id_maps.pin[local_to.id]

      assert {:ok, _external_materialized, external_id_maps} =
               SceneBuilder.instantiate_snapshot(target_project.id, external_snapshot,
                 materialization_mode: :exact,
                 rebuild_references: false,
                 reset_shortcut: true
               )

      mapped_pin_id = external_id_maps.pin[external_pin.id]
      assert Repo.get!(ScenePin, mapped_pin_id).scene_id == external_id_maps.scene[external_scene.id]

      assert {:ok, _materialized, id_maps} =
               SceneBuilder.instantiate_snapshot(target_project.id, snapshot,
                 materialization_mode: :exact,
                 external_id_maps: %{pin: %{external_pin.id => mapped_pin_id}},
                 rebuild_references: false,
                 reset_shortcut: true
               )

      cloned_connection = Repo.get!(SceneConnection, id_maps.connection[connection.id])
      assert cloned_connection.from_pin_id == mapped_pin_id
      assert cloned_connection.to_pin_id == id_maps.pin[local_to.id]
    end

    test "exact materialization preserves a raw endpoint owned by a soft-deleted scene in the target project", %{
      project: project,
      scene: scene
    } do
      layer = layer_fixture(scene, %{"name" => "Local pins"})
      local_from = pin_fixture(scene, %{"label" => "Local from", "layer_id" => layer.id})
      local_to = pin_fixture(scene, %{"label" => "Local to", "layer_id" => layer.id})
      connection = connection_fixture(scene, local_from, local_to)

      deleted_scene = scene_fixture(project)
      retained_pin = pin_fixture(deleted_scene, %{"label" => "Retained trash endpoint"})

      Repo.update_all(
        from(current in Scene, where: current.id == ^deleted_scene.id),
        set: [deleted_at: DateTime.utc_now(:second)]
      )

      Repo.update_all(
        from(current in SceneConnection, where: current.id == ^connection.id),
        set: [from_pin_id: retained_pin.id]
      )

      snapshot = SceneBuilder.build_capture_snapshot(scene)

      assert {:ok, _materialized, id_maps} =
               SceneBuilder.instantiate_snapshot(project.id, snapshot,
                 materialization_mode: :exact,
                 rebuild_references: false,
                 reset_shortcut: true
               )

      cloned_connection = Repo.get!(SceneConnection, id_maps.connection[connection.id])
      assert cloned_connection.from_pin_id == retained_pin.id
      assert cloned_connection.to_pin_id == id_maps.pin[local_to.id]
    end

    test "exact materialization rejects a raw connection endpoint owned by another project", %{
      user: user,
      project: project,
      scene: scene
    } do
      layer = layer_fixture(scene, %{"name" => "Local pins"})
      local_from = pin_fixture(scene, %{"label" => "Local from", "layer_id" => layer.id})
      local_to = pin_fixture(scene, %{"label" => "Local to", "layer_id" => layer.id})
      connection = connection_fixture(scene, local_from, local_to)

      foreign_project = project_fixture(user)
      foreign_scene = scene_fixture(foreign_project)
      foreign_pin = pin_fixture(foreign_scene, %{"label" => "Foreign endpoint"})

      Repo.update_all(
        from(current in SceneConnection, where: current.id == ^connection.id),
        set: [from_pin_id: foreign_pin.id]
      )

      snapshot = SceneBuilder.build_capture_snapshot(scene)
      scene_count = Repo.aggregate(Scene, :count)

      assert {:error,
              {:exact_scene_connection_pin_project_mismatch, connection_id, :from, source_pin_id, resolved_pin_id,
               owner_project_id, target_project_id}} =
               SceneBuilder.instantiate_snapshot(project.id, snapshot,
                 materialization_mode: :exact,
                 rebuild_references: false,
                 reset_shortcut: true
               )

      assert connection_id == connection.id
      assert source_pin_id == foreign_pin.id
      assert resolved_pin_id == foreign_pin.id
      assert owner_project_id == foreign_project.id
      assert target_project_id == project.id
      assert Repo.aggregate(Scene, :count) == scene_count
    end

    test "exact materialization remaps captured authored JSON ids and preserves unmapped ids", %{
      user: user,
      project: project,
      scene: scene
    } do
      source_flow = FlowsFixtures.flow_fixture(project, %{name: "Captured target"})
      source_sheet = sheet_fixture(project)
      item_id = Ecto.UUID.generate()

      target_zone =
        zone_fixture(scene, %{
          "name" => "Flow target",
          "target_type" => "flow",
          "target_id" => source_flow.id,
          "action_type" => "action",
          "action_data" => %{"assignments" => []}
        })

      collection_zone =
        zone_fixture(scene, %{
          "name" => "Collection",
          "action_type" => "collection",
          "action_data" => %{
            "items" => [%{"id" => item_id, "label" => "Linked", "sheet_id" => source_sheet.id}]
          }
        })

      snapshot = SceneBuilder.build_capture_snapshot(scene)

      mapped_project = project_fixture(user)
      mapped_flow = FlowsFixtures.flow_fixture(mapped_project, %{name: "Mapped target"})
      mapped_sheet = sheet_fixture(mapped_project)

      assert {:ok, _mapped_scene, mapped_id_maps} =
               SceneBuilder.instantiate_snapshot(mapped_project.id, snapshot,
                 materialization_mode: :exact,
                 external_id_maps: %{
                   flow: %{source_flow.id => mapped_flow.id},
                   sheet: %{source_sheet.id => mapped_sheet.id}
                 },
                 rebuild_references: false,
                 reset_shortcut: true
               )

      mapped_target = Repo.get!(SceneZone, mapped_id_maps.zone[target_zone.id])
      mapped_collection = Repo.get!(SceneZone, mapped_id_maps.zone[collection_zone.id])
      assert {mapped_target.target_type, mapped_target.target_id} == {"flow", mapped_flow.id}
      assert get_in(mapped_collection.action_data, ["items", Access.at(0), "sheet_id"]) == mapped_sheet.id

      raw_project = project_fixture(user)

      assert {:ok, _raw_scene, raw_id_maps} =
               SceneBuilder.instantiate_snapshot(raw_project.id, snapshot,
                 materialization_mode: :exact,
                 rebuild_references: false,
                 reset_shortcut: true
               )

      raw_target = Repo.get!(SceneZone, raw_id_maps.zone[target_zone.id])
      raw_collection = Repo.get!(SceneZone, raw_id_maps.zone[collection_zone.id])
      assert {raw_target.target_type, raw_target.target_id} == {"flow", source_flow.id}
      assert get_in(raw_collection.action_data, ["items", Access.at(0), "sheet_id"]) == source_sheet.id
    end

    test "rejects malformed or truncated zone payloads before materialization", %{
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
      assert_copied_asset_storage(materialized.background_asset, target_project.id, "map-background")

      cloned_pin =
        materialized.id
        |> Storyarn.Scenes.list_pins()
        |> Enum.find(&(&1.label == "Icon Pin"))
        |> Repo.preload(:icon_asset)

      assert cloned_pin.icon_asset.project_id == target_project.id
      refute cloned_pin.icon_asset_id == pin_icon_asset.id
      assert_copied_asset_storage(cloned_pin.icon_asset, target_project.id, "pin-icon")

      cloned_zone =
        materialized.id
        |> Storyarn.Scenes.list_zones()
        |> Enum.find(&(&1.name == "Icon Zone"))

      assert cloned_zone.label_icon_asset.project_id == target_project.id
      refute cloned_zone.label_icon_asset_id == zone_icon_asset.id
      assert_copied_asset_storage(cloned_zone.label_icon_asset, target_project.id, "zone-icon")
    end

    test "immediately cleans unique copied assets and retains the canonical blob after rollback", %{
      user: user,
      project: project,
      scene: scene
    } do
      background_asset = uploaded_image_asset(project, user, "copied-background.png", "copied background")
      broken_pin_asset = uploaded_image_asset(project, user, "broken-pin.png", "broken pin")

      {:ok, scene} = Storyarn.Scenes.update_scene(scene, %{"background_asset_id" => background_asset.id})
      layer = layer_fixture(scene)

      _pin =
        pin_fixture(scene, %{
          "label" => "Broken Pin",
          "layer_id" => layer.id,
          "icon_asset_id" => broken_pin_asset.id
        })

      snapshot =
        scene
        |> SceneBuilder.build_snapshot()
        |> put_in(["asset_metadata", to_string(broken_pin_asset.id)], %{})

      target_project = project_fixture(user)
      copied_asset_paths_before = stored_asset_paths(target_project.id, background_asset.filename)

      copied_blob_key =
        BlobStore.blob_key(
          target_project.id,
          background_asset.blob_hash,
          BlobStore.ext_from_content_type(background_asset.content_type)
        )

      on_exit(fn -> Assets.storage_delete(copied_blob_key) end)

      assert {:error, {:asset_materialization_failed, broken_pin_asset_id, :missing_asset_metadata}} =
               SceneBuilder.instantiate_snapshot(target_project.id, snapshot,
                 asset_mode: :copy,
                 user_id: user.id,
                 reset_shortcut: true
               )

      assert broken_pin_asset_id == broken_pin_asset.id

      refute Repo.exists?(from asset in Asset, where: asset.project_id == ^target_project.id)

      assert stored_asset_paths(target_project.id, background_asset.filename) ==
               copied_asset_paths_before

      assert {:ok, "copied background"} = Assets.storage_download(copied_blob_key)
      assert [] = all_enqueued(worker: DeleteStorageObjectsWorker)
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

  describe "SceneScanner.scan/1" do
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

      refs = SceneScanner.scan(snapshot)

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

      refs = SceneScanner.scan(snapshot)
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

      refs = SceneScanner.scan(snapshot)

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

      refs = SceneScanner.scan(snapshot)

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
    uploaded_asset(project, user, filename, content, "image/png")
  end

  defp uploaded_asset(project, user, filename, content, content_type) do
    {:ok, asset} =
      Assets.upload_binary_and_create_asset(
        content,
        %{filename: filename, content_type: content_type},
        project,
        user
      )

    on_exit(fn ->
      Assets.storage_delete(asset.key)

      delete_storage_blob(
        BlobStore.blob_key(
          project.id,
          asset.blob_hash,
          BlobStore.ext_from_content_type(asset.content_type)
        )
      )
    end)

    asset
  end

  defp assert_copied_asset_storage(asset, project_id, expected_content) do
    blob_key =
      BlobStore.blob_key(
        project_id,
        asset.blob_hash,
        BlobStore.ext_from_content_type(asset.content_type)
      )

    assert {:ok, ^expected_content} = Assets.storage_download(asset.key)
    assert {:ok, ^expected_content} = Assets.storage_download(blob_key)

    on_exit(fn ->
      Assets.storage_delete(asset.key)
      Assets.storage_delete(blob_key)
    end)
  end

  defp stored_asset_paths(project_id, filename) do
    upload_dir =
      :storyarn
      |> Application.fetch_env!(:storage)
      |> Keyword.fetch!(:upload_dir)
      |> Path.expand()

    upload_dir
    |> Path.join("projects/#{project_id}/assets/*/#{filename}")
    |> Path.wildcard()
    |> MapSet.new()
  end
end
