defmodule Storyarn.Versioning.Builders.SceneBuilderTest do
  use Storyarn.DataCase, async: true
  use Oban.Testing, repo: Storyarn.Repo

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Assets
  alias Storyarn.Assets.Asset
  alias Storyarn.Assets.BlobStore
  alias Storyarn.Repo
  alias Storyarn.Versioning.Builders.AssetCopyError
  alias Storyarn.Versioning.Builders.SceneBuilder
  alias Storyarn.Workers.DeleteStorageObjectsWorker

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

      _conn = connection_fixture(scene, pin1, pin2)

      snapshot = SceneBuilder.build_snapshot(scene)
      assert length(snapshot["connections"]) == 1

      [conn] = snapshot["connections"]
      assert is_integer(conn["from_layer_index"])
      assert is_integer(conn["from_pin_index"])
      assert is_integer(conn["to_layer_index"])
      assert is_integer(conn["to_pin_index"])
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

      _conn = connection_fixture(scene, pin1, pin2)

      snapshot = SceneBuilder.build_snapshot(scene)

      # Modify the scene
      {:ok, modified_scene} = Storyarn.Scenes.update_scene(scene, %{"name" => "Modified"})

      # Restore
      {:ok, restored} = SceneBuilder.restore_snapshot(modified_scene, snapshot)

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
    end

    test "normalizes legacy zone behavior without losing assignments", %{scene: scene} do
      snapshot =
        scene
        |> SceneBuilder.build_snapshot()
        |> Map.put("orphan_zones", [
          %{
            "name" => "Legacy Action",
            "vertices" => triangle_vertices(),
            "action_type" => "instruction",
            "action_data" => %{"assignments" => [%{"variable" => "hero.hp", "operator" => "set", "value" => "1"}]},
            "is_walkable" => true
          },
          %{
            "name" => "Legacy Walkable",
            "vertices" => triangle_vertices(),
            "action_type" => "none",
            "action_data" => %{},
            "is_walkable" => true
          },
          %{
            "name" => "Display With Target",
            "vertices" => triangle_vertices(),
            "target_type" => "scene",
            "target_id" => 999_999,
            "action_type" => "display",
            "action_data" => %{"variable_ref" => "hero.hp"},
            "is_walkable" => true
          },
          %{
            "name" => "Unknown Type",
            "vertices" => triangle_vertices(),
            "action_type" => "event",
            "action_data" => %{},
            "is_walkable" => false
          },
          %{
            "name" => "Action With Invalid Target",
            "vertices" => triangle_vertices(),
            "target_type" => "sheet",
            "target_id" => 123,
            "action_type" => "action",
            "action_data" => %{"assignments" => []}
          }
        ])

      {:ok, modified_scene} = Storyarn.Scenes.update_scene(scene, %{"name" => "Modified"})
      {:ok, restored} = SceneBuilder.restore_snapshot(modified_scene, snapshot)

      zones = restored.id |> Storyarn.Scenes.list_zones() |> Map.new(&{&1.name, &1})

      assert zones["Legacy Action"].action_type == "action"
      assert zones["Legacy Action"].action_data["assignments"] != []
      refute zones["Legacy Action"].is_walkable

      assert zones["Legacy Walkable"].action_type == "walkable"
      assert zones["Legacy Walkable"].is_walkable

      assert zones["Display With Target"].action_type == "display"
      assert zones["Display With Target"].action_data["display_mode"] == "value"
      refute zones["Display With Target"].is_walkable
      assert is_nil(zones["Display With Target"].target_type)
      assert is_nil(zones["Display With Target"].target_id)

      assert zones["Unknown Type"].action_type == "action"
      assert zones["Unknown Type"].action_data == %{"assignments" => []}

      assert zones["Action With Invalid Target"].action_type == "action"
      assert is_nil(zones["Action With Invalid Target"].target_type)
      assert is_nil(zones["Action With Invalid Target"].target_id)
    end
  end

  describe "instantiate_snapshot/3" do
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

    test "materializes normalized zone behavior without preserving invalid display targets", %{
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

      assert {:ok, materialized, _id_maps} =
               SceneBuilder.instantiate_snapshot(project.id, snapshot, reset_shortcut: true)

      zones = materialized.id |> Storyarn.Scenes.list_zones() |> Map.new(&{&1.name, &1})

      assert zones["Materialized Display"].action_type == "display"
      refute zones["Materialized Display"].is_walkable
      assert is_nil(zones["Materialized Display"].target_type)
      assert is_nil(zones["Materialized Display"].target_id)

      assert zones["Materialized Unknown"].action_type == "action"
      assert zones["Materialized Unknown"].action_data == %{"assignments" => []}

      assert zones["Materialized Invalid Target"].action_type == "action"
      assert is_nil(zones["Materialized Invalid Target"].target_type)
      assert is_nil(zones["Materialized Invalid Target"].target_id)
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

    test "durably cleans copied assets when materialization rolls back", %{
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

      assert_raise AssetCopyError, fn ->
        SceneBuilder.instantiate_snapshot(target_project.id, snapshot,
          asset_mode: :copy,
          asset_error_mode: :strict,
          user_id: user.id,
          reset_shortcut: true
        )
      end

      refute Repo.exists?(from asset in Asset, where: asset.project_id == ^target_project.id)
      assert [cleanup_job] = all_enqueued(worker: DeleteStorageObjectsWorker)

      cleanup_keys = cleanup_job.args["storage_keys"]

      copied_blob_key =
        BlobStore.blob_key(
          target_project.id,
          background_asset.blob_hash,
          BlobStore.ext_from_content_type(background_asset.content_type)
        )

      copied_asset_key =
        Enum.find(cleanup_keys, &String.starts_with?(&1, "projects/#{target_project.id}/assets/"))

      assert copied_blob_key in cleanup_keys
      assert is_binary(copied_asset_key)

      on_exit(fn -> Enum.each(cleanup_keys, &Assets.storage_delete/1) end)

      Repo.delete!(target_project)
      assert :ok = perform_job(DeleteStorageObjectsWorker, cleanup_job.args)
      assert {:error, :enoent} = Assets.storage_download(copied_asset_key)
      assert {:error, :enoent} = Assets.storage_download(copied_blob_key)
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
        ]
      }

      refs = SceneBuilder.scan_references(snapshot)

      types_and_ids = refs |> Enum.map(&{&1.type, &1.id}) |> Enum.sort()

      assert {:asset, 20} in types_and_ids
      assert {:asset, 100} in types_and_ids
      assert {:flow, 30} in types_and_ids
      assert {:scene, 40} in types_and_ids
      assert {:sheet, 10} in types_and_ids
      assert length(refs) == 5
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
  end

  describe "diff_snapshots/2" do
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

  defp triangle_vertices do
    [
      %{"x" => 10.0, "y" => 10.0},
      %{"x" => 20.0, "y" => 10.0},
      %{"x" => 15.0, "y" => 20.0}
    ]
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
      Assets.storage_delete(BlobStore.blob_key(project.id, asset.blob_hash, "png"))
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
end
