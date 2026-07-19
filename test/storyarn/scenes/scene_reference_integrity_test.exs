defmodule Storyarn.Scenes.SceneReferenceIntegrityTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.FlowsFixtures, only: [flow_fixture: 1]
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.References.EntityReference
  alias Storyarn.Repo
  alias Storyarn.Scenes
  alias Storyarn.Scenes.Scene
  alias Storyarn.Scenes.SceneConnection
  alias Storyarn.Scenes.ScenePin
  alias Storyarn.Scenes.SceneZone

  @vertices [
    %{"x" => 10.0, "y" => 10.0},
    %{"x" => 50.0, "y" => 10.0},
    %{"x" => 30.0, "y" => 50.0}
  ]

  describe "scene root references" do
    test "rejects cross-project, inactive and malformed parents without inserting" do
      user = user_fixture()
      project = project_fixture(user)
      foreign_project = project_fixture(user)
      foreign_parent = scene_fixture(foreign_project)
      deleted_parent = scene_fixture(project)
      soft_delete!(deleted_parent)

      initial_count = count_project_scenes(project.id)

      for parent_id <- [foreign_parent.id, deleted_parent.id, "not-an-id"] do
        assert_invalid_reference(
          Scenes.create_scene(project, %{
            name: "Invalid child #{inspect(parent_id)}",
            parent_id: parent_id
          }),
          parent_id
        )
      end

      assert count_project_scenes(project.id) == initial_count
    end

    test "rejects foreign and malformed background assets without inserting" do
      user = user_fixture()
      project = project_fixture(user)
      foreign_project = project_fixture(user)
      foreign_asset = asset_fixture(foreign_project, user)

      initial_count = count_project_scenes(project.id)

      for asset_id <- [foreign_asset.id, "not-an-id"] do
        assert_invalid_reference(
          Scenes.create_scene(project, %{
            name: "Invalid background #{inspect(asset_id)}",
            background_asset_id: asset_id
          }),
          asset_id
        )
      end

      assert count_project_scenes(project.id) == initial_count
    end

    test "rejects a same-project non-image background without inserting" do
      user = user_fixture()
      project = project_fixture(user)
      audio = audio_asset_fixture(project, user)
      initial_count = count_project_scenes(project.id)

      assert {:error, {:invalid_asset_content_type, {:scene, :new, :background_asset_id}, asset_id}} =
               Scenes.create_scene(project, %{
                 name: "Invalid audio background",
                 background_asset_id: audio.id
               })

      assert asset_id == audio.id
      assert count_project_scenes(project.id) == initial_count
    end

    test "reloads stale scenes and preserves current valid references on update" do
      user = user_fixture()
      project = project_fixture(user)
      parent = scene_fixture(project)
      first_asset = asset_fixture(project, user)
      second_asset = asset_fixture(project, user)

      scene =
        scene_fixture(project, %{
          parent_id: parent.id,
          background_asset_id: first_asset.id
        })

      stale_scene = scene

      assert {:ok, _scene} =
               Scenes.update_scene(scene, %{
                 background_asset_id: second_asset.id
               })

      assert {:ok, updated} =
               Scenes.update_scene(stale_scene, %{description: "From stale state"})

      assert updated.parent_id == parent.id
      assert updated.background_asset_id == second_asset.id
      assert is_list(updated.layers)
      assert is_list(updated.zones)
      assert is_list(updated.pins)
      assert is_list(updated.connections)

      persisted = Repo.get!(Scene, scene.id)
      assert persisted.parent_id == parent.id
      assert persisted.background_asset_id == second_asset.id
    end

    test "rejects self and descendant parents and preserves the tree" do
      project = project_fixture()
      parent = scene_fixture(project)
      child = scene_fixture(project, %{parent_id: parent.id})

      assert {:error, {:invalid_scene_parent, _, _, :self}} =
               Scenes.update_scene(parent, %{parent_id: parent.id})

      assert {:error, {:invalid_scene_parent, _, _, :cycle}} =
               Scenes.update_scene(parent, %{parent_id: child.id})

      assert Repo.get!(Scene, parent.id).parent_id == nil
      assert Repo.get!(Scene, child.id).parent_id == parent.id
    end

    test "rejects writes through a soft-deleted scene" do
      project = project_fixture()
      scene = scene_fixture(project)
      soft_delete!(scene)

      assert {:error, :scene_not_active} =
               Scenes.update_scene(scene, %{name: "Must not change"})

      assert {:error, :scene_not_active} =
               Scenes.create_pin(scene.id, valid_pin_attrs())

      assert Repo.get!(Scene, scene.id).name == scene.name
      assert count_scene_records(ScenePin, scene.id) == 0
    end
  end

  describe "scene tree moves" do
    test "rejects cross-project and inactive parents and keeps the old parent" do
      user = user_fixture()
      project = project_fixture(user)
      foreign_project = project_fixture(user)
      original_parent = scene_fixture(project)
      scene = scene_fixture(project, %{parent_id: original_parent.id})
      foreign_parent = scene_fixture(foreign_project)
      deleted_parent = scene_fixture(project)
      soft_delete!(deleted_parent)

      for parent_id <- [foreign_parent.id, deleted_parent.id, "not-an-id"] do
        assert_invalid_reference(
          Scenes.move_scene_to_position(scene, parent_id, 0),
          parent_id
        )

        assert Repo.get!(Scene, scene.id).parent_id == original_parent.id
      end
    end

    test "rejects self and descendant moves atomically" do
      project = project_fixture()
      parent = scene_fixture(project)
      child = scene_fixture(project, %{parent_id: parent.id})

      assert {:error, :cyclic_parent} =
               Scenes.move_scene_to_position(parent, parent.id, 0)

      assert {:error, :cyclic_parent} =
               Scenes.move_scene_to_position(parent, child.id, 0)

      assert Repo.get!(Scene, parent.id).parent_id == nil
      assert Repo.get!(Scene, child.id).parent_id == parent.id
    end
  end

  describe "pin references" do
    test "rejects a same-project non-image icon without inserting" do
      user = user_fixture()
      project = project_fixture(user)
      scene = scene_fixture(project)
      audio = audio_asset_fixture(project, user)

      assert {:error, {:invalid_asset_content_type, {:scene_pin, :new, :icon_asset_id}, asset_id}} =
               Scenes.create_pin(
                 scene.id,
                 Map.put(valid_pin_attrs(), "icon_asset_id", audio.id)
               )

      assert asset_id == audio.id
      assert count_scene_records(ScenePin, scene.id) == 0
    end

    test "rejects cross-project references and malformed IDs without inserting" do
      user = user_fixture()
      project = project_fixture(user)
      foreign_project = project_fixture(user)
      scene = scene_fixture(project)
      foreign_sheet = sheet_fixture(foreign_project)
      foreign_flow = flow_fixture(foreign_project)
      foreign_asset = asset_fixture(foreign_project, user)

      invalid_attrs = [
        %{"sheet_id" => foreign_sheet.id},
        %{"flow_id" => foreign_flow.id},
        %{"icon_asset_id" => foreign_asset.id},
        %{"sheet_id" => "not-an-id"},
        %{"flow_id" => "not-an-id"},
        %{"icon_asset_id" => "not-an-id"}
      ]

      for attrs <- invalid_attrs do
        invalid_value = attrs |> Map.values() |> List.first()

        assert_invalid_reference(
          Scenes.create_pin(scene.id, Map.merge(valid_pin_attrs(), attrs)),
          invalid_value
        )
      end

      assert count_scene_records(ScenePin, scene.id) == 0
    end

    test "rejects soft-deleted sheet and flow references without inserting" do
      project = project_fixture()
      scene = scene_fixture(project)
      sheet = sheet_fixture(project)
      flow = flow_fixture(project)

      soft_delete!(sheet)
      soft_delete!(flow)

      for attrs <- [%{"sheet_id" => sheet.id}, %{"flow_id" => flow.id}] do
        invalid_value = attrs |> Map.values() |> List.first()

        assert_invalid_reference(
          Scenes.create_pin(scene.id, Map.merge(valid_pin_attrs(), attrs)),
          invalid_value
        )
      end

      assert count_scene_records(ScenePin, scene.id) == 0
    end

    test "reloads stale pins, preserves references and replaces trackers atomically" do
      user = user_fixture()
      project = project_fixture(user)
      scene = scene_fixture(project)
      sheet = sheet_fixture(project)
      first_flow = flow_fixture(project)
      second_flow = flow_fixture(project)
      icon_asset = asset_fixture(project, user)

      pin =
        pin_fixture(scene, %{
          "sheet_id" => sheet.id,
          "flow_id" => first_flow.id,
          "icon_asset_id" => icon_asset.id
        })

      stale_pin = pin

      assert {:ok, _pin} =
               Scenes.update_pin(pin, %{"flow_id" => second_flow.id})

      assert {:ok, updated} =
               Scenes.update_pin(stale_pin, %{"label" => "Stale-safe rename"})

      assert updated.sheet_id == sheet.id
      assert updated.flow_id == second_flow.id
      assert updated.icon_asset_id == icon_asset.id

      assert pin_entity_targets(pin.id) ==
               MapSet.new([
                 {"flow", second_flow.id, "target"},
                 {"sheet", sheet.id, "display"}
               ])
    end

    test "rolls back an invalid pin update and preserves row and trackers" do
      user = user_fixture()
      project = project_fixture(user)
      foreign_project = project_fixture(user)
      scene = scene_fixture(project)
      sheet = sheet_fixture(project)
      flow = flow_fixture(project)
      foreign_flow = flow_fixture(foreign_project)
      icon_asset = asset_fixture(project, user)

      pin =
        pin_fixture(scene, %{
          "sheet_id" => sheet.id,
          "flow_id" => flow.id,
          "icon_asset_id" => icon_asset.id
        })

      targets_before = pin_entity_targets(pin.id)

      assert_invalid_reference(
        Scenes.update_pin(pin, %{
          "label" => "Must roll back",
          "flow_id" => foreign_flow.id
        }),
        foreign_flow.id
      )

      persisted = Repo.get!(ScenePin, pin.id)
      assert persisted.label == pin.label
      assert persisted.sheet_id == sheet.id
      assert persisted.flow_id == flow.id
      assert persisted.icon_asset_id == icon_asset.id
      assert pin_entity_targets(pin.id) == targets_before
    end
  end

  describe "zone references" do
    test "rejects a same-project non-image label icon without inserting" do
      user = user_fixture()
      project = project_fixture(user)
      scene = scene_fixture(project)
      audio = audio_asset_fixture(project, user)

      assert {:error, {:invalid_asset_content_type, {:scene_zone, :new, :label_icon_asset_id}, asset_id}} =
               Scenes.create_zone(
                 scene.id,
                 Map.put(valid_zone_attrs(), "label_icon_asset_id", audio.id)
               )

      assert asset_id == audio.id
      assert count_scene_records(SceneZone, scene.id) == 0
    end

    test "rejects cross-project and malformed direct targets and icons" do
      user = user_fixture()
      project = project_fixture(user)
      foreign_project = project_fixture(user)
      scene = scene_fixture(project)
      foreign_flow = flow_fixture(foreign_project)
      foreign_scene = scene_fixture(foreign_project)
      foreign_asset = asset_fixture(foreign_project, user)

      invalid_attrs = [
        %{"target_type" => "flow", "target_id" => foreign_flow.id},
        %{"target_type" => "scene", "target_id" => foreign_scene.id},
        %{"label_icon_asset_id" => foreign_asset.id},
        %{"target_type" => "flow", "target_id" => "not-an-id"},
        %{"label_icon_asset_id" => "not-an-id"}
      ]

      for attrs <- invalid_attrs do
        invalid_value =
          Map.get(attrs, "target_id") ||
            Map.fetch!(attrs, "label_icon_asset_id")

        assert_invalid_reference(
          Scenes.create_zone(scene.id, Map.merge(valid_zone_attrs(), attrs)),
          invalid_value
        )
      end

      assert count_scene_records(SceneZone, scene.id) == 0
    end

    test "rejects soft-deleted flow and scene targets without inserting" do
      project = project_fixture()
      source_scene = scene_fixture(project)
      target_scene = scene_fixture(project)
      target_flow = flow_fixture(project)
      soft_delete!(target_scene)
      soft_delete!(target_flow)

      for attrs <- [
            %{"target_type" => "flow", "target_id" => target_flow.id},
            %{"target_type" => "scene", "target_id" => target_scene.id}
          ] do
        invalid_value = attrs["target_id"]

        assert_invalid_reference(
          Scenes.create_zone(
            source_scene.id,
            Map.merge(valid_zone_attrs(), attrs)
          ),
          invalid_value
        )
      end

      assert count_scene_records(SceneZone, source_scene.id) == 0
    end

    test "reloads stale zones and preserves current target and icon references" do
      user = user_fixture()
      project = project_fixture(user)
      source_scene = scene_fixture(project)
      target_scene = scene_fixture(project)
      target_flow = flow_fixture(project)
      icon_asset = asset_fixture(project, user)

      zone =
        zone_fixture(source_scene, %{
          "target_type" => "flow",
          "target_id" => target_flow.id,
          "label_icon_asset_id" => icon_asset.id
        })

      stale_zone = zone

      assert {:ok, _zone} =
               Scenes.update_zone(zone, %{
                 "target_type" => "scene",
                 "target_id" => target_scene.id
               })

      assert {:ok, updated} =
               Scenes.update_zone(stale_zone, %{"name" => "Stale-safe zone"})

      assert updated.target_type == "scene"
      assert updated.target_id == target_scene.id
      assert updated.label_icon_asset_id == icon_asset.id

      assert zone_entity_targets(zone.id) ==
               MapSet.new([{"scene", target_scene.id, "target"}])
    end

    test "rolls back invalid zone updates and preserves references" do
      user = user_fixture()
      project = project_fixture(user)
      foreign_project = project_fixture(user)
      source_scene = scene_fixture(project)
      target_scene = scene_fixture(project)
      icon_asset = asset_fixture(project, user)
      foreign_asset = asset_fixture(foreign_project, user)

      zone =
        zone_fixture(source_scene, %{
          "target_type" => "scene",
          "target_id" => target_scene.id,
          "label_icon_asset_id" => icon_asset.id
        })

      targets_before = zone_entity_targets(zone.id)

      assert_invalid_reference(
        Scenes.update_zone(zone, %{
          "name" => "Must roll back",
          "label_icon_asset_id" => foreign_asset.id
        }),
        foreign_asset.id
      )

      persisted = Repo.get!(SceneZone, zone.id)
      assert persisted.name == zone.name
      assert persisted.target_type == "scene"
      assert persisted.target_id == target_scene.id
      assert persisted.label_icon_asset_id == icon_asset.id
      assert zone_entity_targets(zone.id) == targets_before
    end

    test "validates, normalizes and tracks collection item sheet references" do
      project = project_fixture()
      foreign_project = project_fixture()
      source_scene = scene_fixture(project)
      local_sheet = sheet_fixture(project)
      foreign_sheet = sheet_fixture(foreign_project)

      attrs =
        valid_zone_attrs()
        |> Map.put("action_type", "collection")
        |> Map.put("action_data", %{
          "items" => [
            %{"id" => Ecto.UUID.generate(), "sheet_id" => foreign_sheet.id}
          ]
        })

      assert_invalid_reference(
        Scenes.create_zone(source_scene.id, attrs),
        foreign_sheet.id
      )

      assert count_scene_records(SceneZone, source_scene.id) == 0

      valid_attrs =
        put_in(
          attrs,
          ["action_data", "items", Access.at(0), "sheet_id"],
          Integer.to_string(local_sheet.id)
        )

      assert {:ok, zone} = Scenes.create_zone(source_scene.id, valid_attrs)

      assert get_in(zone.action_data, ["items", Access.at(0), "sheet_id"]) ==
               local_sheet.id

      assert zone_entity_targets(zone.id) ==
               MapSet.new([{"sheet", local_sheet.id, "collection_item"}])
    end

    test "rejects inactive and malformed collection item sheet references" do
      project = project_fixture()
      source_scene = scene_fixture(project)
      deleted_sheet = sheet_fixture(project)
      soft_delete!(deleted_sheet)

      for sheet_id <- [deleted_sheet.id, "not-an-id"] do
        attrs =
          valid_zone_attrs()
          |> Map.put("action_type", "collection")
          |> Map.put("action_data", %{
            "items" => [
              %{"id" => Ecto.UUID.generate(), "sheet_id" => sheet_id}
            ]
          })

        assert_invalid_reference(
          Scenes.create_zone(source_scene.id, attrs),
          sheet_id
        )
      end

      assert count_scene_records(SceneZone, source_scene.id) == 0
    end

    test "preserves valid collection item IDs and rejects missing or duplicate IDs" do
      project = project_fixture()
      source_scene = scene_fixture(project)
      item_id = Ecto.UUID.generate()

      valid_attrs =
        valid_zone_attrs()
        |> Map.put("action_type", "collection")
        |> Map.put("action_data", %{
          "items" => [%{"id" => item_id, "sheet_id" => nil}]
        })

      assert {:ok, zone} = Scenes.create_zone(source_scene.id, valid_attrs)

      assert get_in(zone.action_data, ["items", Access.at(0), "id"]) ==
               item_id

      for invalid_items <- [
            [%{"sheet_id" => nil}],
            [
              %{"id" => item_id, "sheet_id" => nil},
              %{"id" => item_id, "sheet_id" => nil}
            ]
          ] do
        attrs =
          valid_attrs
          |> put_in(["action_data", "items"], invalid_items)
          |> Map.put("name", "Invalid collection")

        assert {:error, {:invalid_scene_collection_item, _, _, _, _}} =
                 Scenes.create_zone(source_scene.id, attrs)
      end
    end
  end

  describe "connection endpoint integrity" do
    test "rejects foreign-scene, missing and malformed endpoints without inserting" do
      project = project_fixture()
      scene = scene_fixture(project)
      other_scene = scene_fixture(project)
      local_pin = pin_fixture(scene)
      foreign_pin = pin_fixture(other_scene)

      invalid_attrs = [
        %{"from_pin_id" => local_pin.id, "to_pin_id" => foreign_pin.id},
        %{"from_pin_id" => local_pin.id, "to_pin_id" => 9_999_999_999},
        %{"from_pin_id" => local_pin.id, "to_pin_id" => "not-an-id"}
      ]

      for attrs <- invalid_attrs do
        assert {:error, {:invalid_scene_connection_endpoint, :to_pin_id, _value}} =
                 Scenes.create_connection(scene.id, attrs)
      end

      assert count_scene_records(SceneConnection, scene.id) == 0
    end

    test "re-reads existing endpoints before update and waypoint writes" do
      project = project_fixture()
      scene = scene_fixture(project)
      other_scene = scene_fixture(project)
      local_pin_a = pin_fixture(scene)
      local_pin_b = pin_fixture(scene)
      foreign_pin = pin_fixture(other_scene)
      connection = connection_fixture(scene, local_pin_a, local_pin_b)

      Repo.update_all(
        from(candidate in SceneConnection,
          where: candidate.id == ^connection.id
        ),
        set: [to_pin_id: foreign_pin.id]
      )

      assert {:error, {:invalid_scene_connection_endpoint, :to_pin_id, foreign_pin_id}} =
               Scenes.update_connection(connection, %{"label" => "Must fail"})

      assert foreign_pin_id == foreign_pin.id

      assert {:error, {:invalid_scene_connection_endpoint, :to_pin_id, ^foreign_pin_id}} =
               Scenes.update_connection_waypoints(connection, %{
                 "waypoints" => [%{"x" => 10.0, "y" => 20.0}]
               })

      persisted = Repo.get!(SceneConnection, connection.id)
      assert persisted.label == connection.label
      assert persisted.waypoints == connection.waypoints
      assert persisted.to_pin_id == foreign_pin.id
    end
  end

  defp valid_pin_attrs do
    %{
      "position_x" => 50.0,
      "position_y" => 50.0,
      "label" => "Integrity pin"
    }
  end

  defp valid_zone_attrs do
    %{
      "name" => "Integrity zone",
      "vertices" => @vertices
    }
  end

  defp assert_invalid_reference(result, expected_value) do
    assert {:error, {:invalid_project_reference, _context, ^expected_value}} =
             result
  end

  defp soft_delete!(record) do
    record
    |> Ecto.Changeset.change(deleted_at: DateTime.truncate(DateTime.utc_now(), :second))
    |> Repo.update!()
  end

  defp count_project_scenes(project_id) do
    Repo.aggregate(
      from(scene in Scene, where: scene.project_id == ^project_id),
      :count,
      :id
    )
  end

  defp count_scene_records(schema, scene_id) do
    Repo.aggregate(
      from(record in schema, where: record.scene_id == ^scene_id),
      :count,
      :id
    )
  end

  defp pin_entity_targets(pin_id) do
    EntityReference
    |> where(
      [reference],
      reference.source_type == "scene_pin" and
        reference.source_id == ^pin_id
    )
    |> select(
      [reference],
      {reference.target_type, reference.target_id, reference.context}
    )
    |> Repo.all()
    |> MapSet.new()
  end

  defp zone_entity_targets(zone_id) do
    EntityReference
    |> where(
      [reference],
      reference.source_type == "scene_zone" and
        reference.source_id == ^zone_id
    )
    |> select(
      [reference],
      {reference.target_type, reference.target_id, reference.context}
    )
    |> Repo.all()
    |> MapSet.new()
  end
end
