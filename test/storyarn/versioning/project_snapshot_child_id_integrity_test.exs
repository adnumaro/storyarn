defmodule Storyarn.Versioning.ProjectSnapshotChildIdIntegrityTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Assets
  alias Storyarn.Assets.BlobStore
  alias Storyarn.Scenes
  alias Storyarn.Scenes.Scene
  alias Storyarn.Scenes.SceneAnnotation
  alias Storyarn.Scenes.SceneConnection
  alias Storyarn.Scenes.SceneLayer
  alias Storyarn.Scenes.ScenePin
  alias Storyarn.Scenes.SceneZone
  alias Storyarn.Sheets
  alias Storyarn.Sheets.Block
  alias Storyarn.Sheets.BlockGalleryImage
  alias Storyarn.Sheets.Sheet
  alias Storyarn.Sheets.SheetAvatar
  alias Storyarn.Sheets.TableColumn
  alias Storyarn.Sheets.TableRow
  alias Storyarn.Versioning.Builders.ProjectSnapshotBuilder

  setup do
    user = user_fixture()
    project = project_fixture(user)

    %{project: project, user: user}
  end

  describe "exact project restore preserves child identities" do
    test "recreates a hard-deleted sheet root and every nested child with the snapshot IDs", %{
      project: project,
      user: user
    } do
      sheet = sheet_fixture(project, %{name: "Historical character"})
      plain_block = block_fixture(sheet, %{value: %{"content" => "Historical biography"}})
      table_block = table_block_fixture(sheet)
      table_column = table_column_fixture(table_block, %{name: "Score", type: "number"})
      table_row = table_row_fixture(table_block, %{name: "Final score"})

      gallery_block =
        block_fixture(sheet, %{
          type: "gallery",
          config: %{"label" => "References"},
          value: %{}
        })

      avatar_asset = uploaded_image_asset(project, user, "child-id-avatar.png", "avatar")
      gallery_asset = uploaded_image_asset(project, user, "child-id-gallery.png", "gallery")
      {:ok, avatar} = Sheets.add_avatar(sheet, avatar_asset.id, %{name: "Historical avatar"})
      {:ok, gallery_image} = Sheets.add_gallery_image(gallery_block, gallery_asset.id)

      expected_column_ids =
        table_block.id
        |> Sheets.list_table_columns()
        |> MapSet.new(& &1.id)

      expected_row_ids =
        table_block.id
        |> Sheets.list_table_rows()
        |> MapSet.new(& &1.id)

      snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

      assert {:ok, _deleted} = Sheets.permanently_delete_sheet(sheet)
      assert is_nil(Repo.get(Sheet, sheet.id))
      assert is_nil(Repo.get(Block, plain_block.id))
      assert is_nil(Repo.get(Block, table_block.id))
      assert is_nil(Repo.get(Block, gallery_block.id))
      assert is_nil(Repo.get(TableColumn, table_column.id))
      assert is_nil(Repo.get(TableRow, table_row.id))
      assert is_nil(Repo.get(SheetAvatar, avatar.id))
      assert is_nil(Repo.get(BlockGalleryImage, gallery_image.id))

      assert {:ok, _result} =
               ProjectSnapshotBuilder.restore_snapshot(project.id, snapshot)

      assert %Sheet{id: restored_sheet_id, deleted_at: nil} =
               Repo.get!(Sheet, sheet.id)

      assert restored_sheet_id == sheet.id

      assert %Block{id: restored_plain_id, sheet_id: ^restored_sheet_id, deleted_at: nil} =
               Repo.get!(Block, plain_block.id)

      assert restored_plain_id == plain_block.id

      assert %Block{id: restored_table_id, sheet_id: ^restored_sheet_id, deleted_at: nil} =
               Repo.get!(Block, table_block.id)

      assert restored_table_id == table_block.id

      assert %Block{id: restored_gallery_id, sheet_id: ^restored_sheet_id, deleted_at: nil} =
               Repo.get!(Block, gallery_block.id)

      assert restored_gallery_id == gallery_block.id

      assert MapSet.new(Sheets.list_table_columns(table_block.id), & &1.id) ==
               expected_column_ids

      assert MapSet.new(Sheets.list_table_rows(table_block.id), & &1.id) ==
               expected_row_ids

      assert %TableColumn{id: restored_column_id, block_id: ^restored_table_id} =
               Repo.get!(TableColumn, table_column.id)

      assert restored_column_id == table_column.id

      assert %TableRow{id: restored_row_id, block_id: ^restored_table_id} =
               Repo.get!(TableRow, table_row.id)

      assert restored_row_id == table_row.id

      assert %SheetAvatar{
               id: restored_avatar_id,
               sheet_id: ^restored_sheet_id,
               asset_id: restored_avatar_asset_id
             } = Repo.get!(SheetAvatar, avatar.id)

      assert restored_avatar_id == avatar.id
      assert restored_avatar_asset_id == avatar_asset.id

      assert %BlockGalleryImage{
               id: restored_gallery_image_id,
               block_id: ^restored_gallery_id,
               asset_id: restored_gallery_asset_id
             } = Repo.get!(BlockGalleryImage, gallery_image.id)

      assert restored_gallery_image_id == gallery_image.id
      assert restored_gallery_asset_id == gallery_asset.id

      assert_idempotent_exact_snapshot(project.id, snapshot)
    end

    test "recreates hard-deleted sheet children and removes post-snapshot children without dangling ownership", %{
      project: project,
      user: user
    } do
      sheet = sheet_fixture(project)
      historical_block = block_fixture(sheet, %{value: %{"content" => "Historical"}})
      table_block = table_block_fixture(sheet)
      historical_column = table_column_fixture(table_block, %{name: "Historical column"})
      historical_row = table_row_fixture(table_block, %{name: "Historical row"})

      gallery_block =
        block_fixture(sheet, %{
          type: "gallery",
          config: %{"label" => "References"},
          value: %{}
        })

      historical_avatar_asset =
        uploaded_image_asset(project, user, "historical-avatar.png", "historical-avatar")

      historical_gallery_asset =
        uploaded_image_asset(project, user, "historical-gallery.png", "historical-gallery")

      {:ok, historical_avatar} =
        Sheets.add_avatar(sheet, historical_avatar_asset.id, %{name: "Historical"})

      {:ok, historical_gallery_image} =
        Sheets.add_gallery_image(gallery_block, historical_gallery_asset.id)

      target_snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

      assert {:ok, _deleted_block} =
               Sheets.permanently_delete_block(historical_block)

      assert {:ok, _deleted_column} =
               Sheets.delete_table_column(historical_column)

      assert {:ok, _deleted_row} =
               Sheets.delete_table_row(historical_row)

      assert {:ok, _deleted_gallery_image} =
               Sheets.remove_gallery_image(sheet.id, historical_gallery_image.id)

      assert {:ok, _deleted_avatar} =
               Sheets.remove_avatar(sheet.id, historical_avatar.id)

      post_snapshot_block = block_fixture(sheet, %{value: %{"content" => "Post snapshot"}})
      post_snapshot_column = table_column_fixture(table_block, %{name: "Post snapshot column"})
      post_snapshot_row = table_row_fixture(table_block, %{name: "Post snapshot row"})

      post_avatar_asset =
        uploaded_image_asset(project, user, "post-avatar.png", "post-avatar")

      post_gallery_asset =
        uploaded_image_asset(project, user, "post-gallery.png", "post-gallery")

      {:ok, post_snapshot_avatar} =
        Sheets.add_avatar(sheet, post_avatar_asset.id, %{name: "Post snapshot"})

      {:ok, post_snapshot_gallery_image} =
        Sheets.add_gallery_image(gallery_block, post_gallery_asset.id)

      safety_snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

      assert {:ok, _result} =
               ProjectSnapshotBuilder.restore_snapshot(
                 project.id,
                 target_snapshot,
                 pre_restore_snapshot: safety_snapshot
               )

      assert %Block{id: historical_block_id, sheet_id: sheet_id, deleted_at: nil} =
               Repo.get!(Block, historical_block.id)

      assert historical_block_id == historical_block.id
      assert sheet_id == sheet.id

      assert %TableColumn{id: historical_column_id, block_id: table_block_id} =
               Repo.get!(TableColumn, historical_column.id)

      assert historical_column_id == historical_column.id
      assert table_block_id == table_block.id

      assert %TableRow{id: historical_row_id, block_id: ^table_block_id} =
               Repo.get!(TableRow, historical_row.id)

      assert historical_row_id == historical_row.id

      assert %SheetAvatar{id: historical_avatar_id, sheet_id: ^sheet_id} =
               Repo.get!(SheetAvatar, historical_avatar.id)

      assert historical_avatar_id == historical_avatar.id

      assert %BlockGalleryImage{
               id: historical_gallery_image_id,
               block_id: gallery_block_id
             } = Repo.get!(BlockGalleryImage, historical_gallery_image.id)

      assert historical_gallery_image_id == historical_gallery_image.id
      assert gallery_block_id == gallery_block.id

      assert %Block{deleted_at: %DateTime{}} =
               Repo.get!(Block, post_snapshot_block.id)

      assert is_nil(Repo.get(TableColumn, post_snapshot_column.id))
      assert is_nil(Repo.get(TableRow, post_snapshot_row.id))
      assert is_nil(Repo.get(SheetAvatar, post_snapshot_avatar.id))
      assert is_nil(Repo.get(BlockGalleryImage, post_snapshot_gallery_image.id))

      refute dangling_sheet_child_rows?(sheet.id)
      assert_idempotent_exact_snapshot(project.id, target_snapshot)
    end

    test "recreates a hard-deleted scene root and its complete graph with the snapshot IDs", %{
      project: project
    } do
      scene = scene_fixture(project, %{name: "Historical map"})
      layer = layer_fixture(scene, %{"name" => "Historical layer"})
      zone = zone_fixture(scene, %{"name" => "Historical zone", "layer_id" => layer.id})
      pin_a = pin_fixture(scene, %{"label" => "Historical A", "layer_id" => layer.id})
      pin_b = pin_fixture(scene, %{"label" => "Historical B", "layer_id" => layer.id})

      annotation =
        annotation_fixture(scene, %{
          "text" => "Historical annotation",
          "layer_id" => layer.id
        })

      connection = connection_fixture(scene, pin_a, pin_b, %{"label" => "Historical route"})
      expected_layer_ids = MapSet.new(Scenes.list_layers(scene.id), & &1.id)
      snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

      assert {:ok, _deleted} = Scenes.hard_delete_scene(scene)
      assert is_nil(Repo.get(Scene, scene.id))
      assert is_nil(Repo.get(SceneLayer, layer.id))
      assert is_nil(Repo.get(SceneZone, zone.id))
      assert is_nil(Repo.get(ScenePin, pin_a.id))
      assert is_nil(Repo.get(ScenePin, pin_b.id))
      assert is_nil(Repo.get(SceneAnnotation, annotation.id))
      assert is_nil(Repo.get(SceneConnection, connection.id))

      assert {:ok, _result} =
               ProjectSnapshotBuilder.restore_snapshot(project.id, snapshot)

      assert %Scene{id: restored_scene_id, deleted_at: nil} =
               Repo.get!(Scene, scene.id)

      assert restored_scene_id == scene.id
      assert MapSet.new(Scenes.list_layers(scene.id), & &1.id) == expected_layer_ids

      assert %SceneLayer{id: restored_layer_id, scene_id: ^restored_scene_id} =
               Repo.get!(SceneLayer, layer.id)

      assert restored_layer_id == layer.id

      assert %SceneZone{id: restored_zone_id, scene_id: ^restored_scene_id, layer_id: ^restored_layer_id} =
               Repo.get!(SceneZone, zone.id)

      assert restored_zone_id == zone.id

      assert %ScenePin{id: restored_pin_a_id, scene_id: ^restored_scene_id, layer_id: ^restored_layer_id} =
               Repo.get!(ScenePin, pin_a.id)

      assert restored_pin_a_id == pin_a.id

      assert %ScenePin{id: restored_pin_b_id, scene_id: ^restored_scene_id, layer_id: ^restored_layer_id} =
               Repo.get!(ScenePin, pin_b.id)

      assert restored_pin_b_id == pin_b.id

      assert %SceneAnnotation{
               id: restored_annotation_id,
               scene_id: ^restored_scene_id,
               layer_id: ^restored_layer_id
             } = Repo.get!(SceneAnnotation, annotation.id)

      assert restored_annotation_id == annotation.id

      assert %SceneConnection{
               id: restored_connection_id,
               scene_id: ^restored_scene_id,
               from_pin_id: ^restored_pin_a_id,
               to_pin_id: ^restored_pin_b_id
             } = Repo.get!(SceneConnection, connection.id)

      assert restored_connection_id == connection.id
      refute dangling_scene_rows?(scene.id)
      assert_idempotent_exact_snapshot(project.id, snapshot)
    end

    test "recreates hard-deleted scene children and removes the post-snapshot graph atomically", %{
      project: project
    } do
      scene = scene_fixture(project)
      historical_layer = layer_fixture(scene, %{"name" => "Historical layer"})

      historical_zone =
        zone_fixture(scene, %{"name" => "Historical zone", "layer_id" => historical_layer.id})

      historical_pin_a =
        pin_fixture(scene, %{"label" => "Historical A", "layer_id" => historical_layer.id})

      historical_pin_b =
        pin_fixture(scene, %{"label" => "Historical B", "layer_id" => historical_layer.id})

      historical_annotation =
        annotation_fixture(scene, %{
          "text" => "Historical annotation",
          "layer_id" => historical_layer.id
        })

      historical_connection =
        connection_fixture(scene, historical_pin_a, historical_pin_b)

      target_snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

      assert {:ok, _deleted_zone} = Scenes.delete_zone(historical_zone)
      assert {:ok, _deleted_annotation} = Scenes.delete_annotation(historical_annotation)
      assert {:ok, _deleted_pin_a} = Scenes.delete_pin(historical_pin_a)
      assert {:ok, _deleted_pin_b} = Scenes.delete_pin(historical_pin_b)
      assert is_nil(Repo.get(SceneConnection, historical_connection.id))
      assert {:ok, _deleted_layer} = Scenes.delete_layer(historical_layer)

      post_layer = layer_fixture(scene, %{"name" => "Post snapshot layer"})
      post_zone = zone_fixture(scene, %{"name" => "Post snapshot zone", "layer_id" => post_layer.id})
      post_pin_a = pin_fixture(scene, %{"label" => "Post A", "layer_id" => post_layer.id})
      post_pin_b = pin_fixture(scene, %{"label" => "Post B", "layer_id" => post_layer.id})

      post_annotation =
        annotation_fixture(scene, %{
          "text" => "Post snapshot annotation",
          "layer_id" => post_layer.id
        })

      post_connection = connection_fixture(scene, post_pin_a, post_pin_b)
      safety_snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

      assert {:ok, _result} =
               ProjectSnapshotBuilder.restore_snapshot(
                 project.id,
                 target_snapshot,
                 pre_restore_snapshot: safety_snapshot
               )

      assert %SceneLayer{id: historical_layer_id, scene_id: scene_id} =
               Repo.get!(SceneLayer, historical_layer.id)

      assert historical_layer_id == historical_layer.id
      assert scene_id == scene.id

      assert %SceneZone{id: historical_zone_id, layer_id: ^historical_layer_id} =
               Repo.get!(SceneZone, historical_zone.id)

      assert historical_zone_id == historical_zone.id

      assert %ScenePin{id: historical_pin_a_id, layer_id: ^historical_layer_id} =
               Repo.get!(ScenePin, historical_pin_a.id)

      assert historical_pin_a_id == historical_pin_a.id

      assert %ScenePin{id: historical_pin_b_id, layer_id: ^historical_layer_id} =
               Repo.get!(ScenePin, historical_pin_b.id)

      assert historical_pin_b_id == historical_pin_b.id

      assert %SceneAnnotation{
               id: historical_annotation_id,
               layer_id: ^historical_layer_id
             } = Repo.get!(SceneAnnotation, historical_annotation.id)

      assert historical_annotation_id == historical_annotation.id

      assert %SceneConnection{
               id: historical_connection_id,
               from_pin_id: ^historical_pin_a_id,
               to_pin_id: ^historical_pin_b_id
             } = Repo.get!(SceneConnection, historical_connection.id)

      assert historical_connection_id == historical_connection.id

      assert is_nil(Repo.get(SceneLayer, post_layer.id))
      assert is_nil(Repo.get(SceneZone, post_zone.id))
      assert is_nil(Repo.get(ScenePin, post_pin_a.id))
      assert is_nil(Repo.get(ScenePin, post_pin_b.id))
      assert is_nil(Repo.get(SceneAnnotation, post_annotation.id))
      assert is_nil(Repo.get(SceneConnection, post_connection.id))

      refute dangling_scene_rows?(scene.id)
      assert_idempotent_exact_snapshot(project.id, target_snapshot)
    end
  end

  defp dangling_sheet_child_rows?(sheet_id) do
    dangling_table_columns =
      Repo.exists?(
        from(column in TableColumn,
          left_join: block in Block,
          on: block.id == column.block_id,
          where: is_nil(block.id)
        )
      )

    dangling_table_rows =
      Repo.exists?(
        from(row in TableRow,
          left_join: block in Block,
          on: block.id == row.block_id,
          where: is_nil(block.id)
        )
      )

    dangling_gallery_images =
      Repo.exists?(
        from(image in BlockGalleryImage,
          left_join: block in Block,
          on: block.id == image.block_id,
          where: is_nil(block.id)
        )
      )

    dangling_avatars =
      Repo.exists?(
        from(avatar in SheetAvatar,
          left_join: sheet in Sheet,
          on: sheet.id == avatar.sheet_id,
          where: avatar.sheet_id == ^sheet_id and is_nil(sheet.id)
        )
      )

    dangling_table_columns or dangling_table_rows or dangling_gallery_images or
      dangling_avatars
  end

  defp dangling_scene_rows?(scene_id) do
    dangling_zones =
      Repo.exists?(
        from(zone in SceneZone,
          left_join: layer in SceneLayer,
          on: layer.id == zone.layer_id,
          where:
            zone.scene_id == ^scene_id and not is_nil(zone.layer_id) and
              is_nil(layer.id)
        )
      )

    dangling_pins =
      Repo.exists?(
        from(pin in ScenePin,
          left_join: layer in SceneLayer,
          on: layer.id == pin.layer_id,
          where:
            pin.scene_id == ^scene_id and not is_nil(pin.layer_id) and
              is_nil(layer.id)
        )
      )

    dangling_annotations =
      Repo.exists?(
        from(annotation in SceneAnnotation,
          left_join: layer in SceneLayer,
          on: layer.id == annotation.layer_id,
          where:
            annotation.scene_id == ^scene_id and
              not is_nil(annotation.layer_id) and is_nil(layer.id)
        )
      )

    dangling_connections =
      Repo.exists?(
        from(connection in SceneConnection,
          left_join: from_pin in ScenePin,
          on: from_pin.id == connection.from_pin_id,
          left_join: to_pin in ScenePin,
          on: to_pin.id == connection.to_pin_id,
          where:
            connection.scene_id == ^scene_id and
              (is_nil(from_pin.id) or is_nil(to_pin.id))
        )
      )

    Enum.any?([
      dangling_zones,
      dangling_pins,
      dangling_annotations,
      dangling_connections
    ])
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

  defp assert_idempotent_exact_snapshot(project_id, target_snapshot) do
    assert ProjectSnapshotBuilder.build_snapshot(project_id) == target_snapshot

    assert {:ok, _result} =
             ProjectSnapshotBuilder.restore_snapshot(
               project_id,
               target_snapshot,
               pre_restore_snapshot: target_snapshot
             )

    assert ProjectSnapshotBuilder.build_snapshot(project_id) == target_snapshot
  end
end
