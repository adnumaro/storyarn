defmodule Storyarn.Versioning.Builders.SheetBuilderTest do
  use Storyarn.DataCase, async: true
  use Oban.Testing, repo: Storyarn.Repo

  import Ecto.Query, warn: false
  import Storyarn.AccountsFixtures
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Assets
  alias Storyarn.Assets.Asset
  alias Storyarn.Assets.BlobStore
  alias Storyarn.Localization
  alias Storyarn.Repo
  alias Storyarn.Sheets
  alias Storyarn.Versioning.Builders.AssetCopyError
  alias Storyarn.Versioning.Builders.SheetBuilder
  alias Storyarn.Workers.DeleteStorageObjectsWorker

  setup do
    user = user_fixture()
    project = project_fixture(user)
    sheet = sheet_fixture(project)

    %{user: user, project: project, sheet: sheet}
  end

  describe "build_snapshot/1" do
    test "captures sheet metadata", %{sheet: sheet} do
      snapshot = SheetBuilder.build_snapshot(sheet)

      assert snapshot["name"] == sheet.name
      assert snapshot["shortcut"] == sheet.shortcut
      assert is_list(snapshot["blocks"])
    end

    test "captures block data", %{sheet: sheet} do
      _block =
        block_fixture(sheet, %{
          type: "number",
          config: %{"label" => "Health"},
          value: %{"content" => "100"}
        })

      snapshot = SheetBuilder.build_snapshot(sheet)
      assert length(snapshot["blocks"]) == 1

      [block] = snapshot["blocks"]
      assert block["type"] == "number"
      assert block["config"]["label"] == "Health"
      assert block["value"]["content"] == "100"
      refute Map.has_key?(block, "word_count")
    end

    test "excludes block IDs from snapshot", %{sheet: sheet} do
      _block = block_fixture(sheet)
      snapshot = SheetBuilder.build_snapshot(sheet)
      [block] = snapshot["blocks"]
      refute Map.has_key?(block, "id")
    end

    test "captures all avatars and gallery images", %{project: project, sheet: sheet, user: user} do
      avatar_asset = uploaded_image_asset(project, user, "default-avatar.png", "avatar-default")
      expression_asset = uploaded_image_asset(project, user, "expression-avatar.png", "avatar-expression")
      gallery_asset = uploaded_image_asset(project, user, "gallery-image.png", "gallery-image")

      {:ok, _avatar} = Sheets.add_avatar(sheet, avatar_asset.id, %{name: "Default"})
      {:ok, _expression} = Sheets.add_avatar(sheet, expression_asset.id, %{name: "Expression"})

      gallery_block =
        block_fixture(sheet, %{
          type: "gallery",
          position: 0,
          config: %{"label" => "Concept Art"},
          value: %{}
        })

      {:ok, gallery_image} = Sheets.add_gallery_image(gallery_block, gallery_asset.id)
      {:ok, _gallery_image} = Sheets.update_gallery_image(gallery_image, %{label: "Gate", description: "Old gate"})

      snapshot = SheetBuilder.build_snapshot(sheet)

      assert Enum.map(snapshot["avatars"], & &1["asset_id"]) == [avatar_asset.id, expression_asset.id]

      gallery_snapshot = Enum.find(snapshot["blocks"], &(&1["type"] == "gallery"))

      assert [gallery_image_snapshot] = gallery_snapshot["gallery_images"]
      assert gallery_image_snapshot["asset_id"] == gallery_asset.id
      assert gallery_image_snapshot["label"] == "Gate"
      assert gallery_image_snapshot["description"] == "Old gate"

      avatar_id = to_string(avatar_asset.id)
      gallery_id = to_string(gallery_asset.id)
      assert snapshot["asset_blob_hashes"][avatar_id] == avatar_asset.blob_hash
      assert snapshot["asset_metadata"][gallery_id]["blob_key"] =~ "projects/#{project.id}/blobs/"
    end
  end

  describe "restore_snapshot/3" do
    test "restores sheet metadata and blocks", %{sheet: sheet} do
      _b1 =
        block_fixture(sheet, %{
          type: "text",
          config: %{"label" => "Name"},
          value: %{"content" => "Alice brave hero"}
        })

      _b2 =
        block_fixture(sheet, %{
          type: "number",
          config: %{"label" => "Health"},
          value: %{"content" => "100"}
        })

      snapshot = SheetBuilder.build_snapshot(sheet)

      # Modify the sheet
      {:ok, modified_sheet} = Sheets.update_sheet(sheet, %{name: "Modified"})
      Sheets.delete_block(hd(Sheets.list_blocks(sheet.id)))

      # Restore from snapshot
      {:ok, restored} = SheetBuilder.restore_snapshot(modified_sheet, snapshot)

      assert restored.name == sheet.name
      blocks = Sheets.list_blocks(sheet.id)
      assert length(blocks) == 2
      assert Enum.find(blocks, &(&1.type == "text")).word_count == 3
    end

    test "restores block and sheet-name translations after block IDs are replaced", %{
      project: project,
      sheet: sheet
    } do
      _en = source_language_fixture(project, %{locale_code: "en", name: "English"})
      _es = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      block =
        block_fixture(sheet, %{
          type: "text",
          variable_name: "bio",
          value: %{"content" => "A hero"}
        })

      :ok = Localization.sync_sheet_names(project.id)
      [block_text] = Localization.get_texts_for_source("block", block.id)
      [sheet_text] = Localization.get_texts_for_source("sheet", sheet.id)

      assert {:ok, _block_text} =
               Localization.update_text(block_text, %{
                 translated_text: "Un héroe",
                 status: "final",
                 reviewer_notes: "Versioned block"
               })

      assert {:ok, _sheet_text} =
               Localization.update_text(sheet_text, %{translated_text: "Personaje", status: "final"})

      snapshot = SheetBuilder.build_snapshot(sheet)
      assert length(snapshot["localization"]) == 2

      assert {:ok, restored} = SheetBuilder.restore_snapshot(sheet, snapshot)
      [restored_block] = Enum.filter(restored.blocks, &(&1.type == "text"))
      refute restored_block.id == block.id

      assert [restored_block_text] = Localization.get_texts_for_source("block", restored_block.id)
      assert restored_block_text.translated_text == "Un héroe"
      assert restored_block_text.status == "final"
      assert restored_block_text.reviewer_notes == "Versioned block"

      assert [%{translated_text: "Personaje", status: "final"}] =
               Localization.get_texts_for_source("sheet", restored.id)
    end
  end

  describe "instantiate_snapshot/3" do
    test "materializes a new sheet, remaps internal inheritance, and restores table data",
         %{project: project, sheet: sheet} do
      block_a =
        block_fixture(sheet, %{
          type: "text",
          position: 0,
          variable_name: "health",
          config: %{"label" => "Health"},
          value: %{"content" => "One two three"}
        })

      block_b =
        block_fixture(sheet, %{
          type: "number",
          position: 1,
          variable_name: "health_copy",
          config: %{"label" => "Health Copy"}
        })

      Repo.update_all(from(b in Storyarn.Sheets.Block, where: b.id == ^block_b.id),
        set: [inherited_from_block_id: block_a.id]
      )

      table_block = table_block_fixture(sheet, %{position: 2})
      column = table_column_fixture(table_block, %{name: "Score", type: "number"})

      [default_row] = Sheets.list_table_rows(table_block.id)
      Sheets.update_table_cell(default_row, column.slug, "99")

      snapshot = SheetBuilder.build_snapshot(sheet)

      assert {:ok, materialized, id_maps} =
               SheetBuilder.instantiate_snapshot(project.id, snapshot,
                 reset_shortcut: true,
                 position: 7
               )

      assert materialized.id != sheet.id
      assert materialized.position == 7
      assert materialized.shortcut == nil
      assert id_maps.sheet == %{sheet.id => materialized.id}
      assert Map.has_key?(id_maps.block, block_a.id)
      assert Map.has_key?(id_maps.block, block_b.id)

      blocks = Sheets.list_blocks(materialized.id)
      assert Enum.find(blocks, &(&1.variable_name == "health")).word_count == 3
      cloned_b = Enum.find(blocks, &(&1.variable_name == "health_copy"))
      assert cloned_b.inherited_from_block_id == id_maps.block[block_a.id]

      cloned_table = Enum.find(blocks, &(&1.type == "table"))
      assert cloned_table
      assert Enum.any?(Sheets.list_table_columns(cloned_table.id), &(&1.name == "Score"))

      [cloned_row | _] = Sheets.list_table_rows(cloned_table.id)
      assert cloned_row.cells["score"] == "99"
    end

    test "copies avatars and gallery image assets into destination project", %{project: project, sheet: sheet, user: user} do
      avatar_asset = uploaded_image_asset(project, user, "hero-avatar.png", "hero-avatar")
      expression_asset = uploaded_image_asset(project, user, "hero-expression.png", "hero-expression")
      gallery_asset = uploaded_image_asset(project, user, "hero-gallery.png", "hero-gallery")

      {:ok, _avatar} = Sheets.add_avatar(sheet, avatar_asset.id, %{name: "Default"})
      {:ok, _expression} = Sheets.add_avatar(sheet, expression_asset.id, %{name: "Expression"})

      gallery_block =
        block_fixture(sheet, %{
          type: "gallery",
          position: 0,
          config: %{"label" => "References"},
          value: %{}
        })

      {:ok, gallery_image} = Sheets.add_gallery_image(gallery_block, gallery_asset.id)
      {:ok, _gallery_image} = Sheets.update_gallery_image(gallery_image, %{label: "Bridge"})

      destination_project = project_fixture(user)
      snapshot = SheetBuilder.build_snapshot(sheet)

      assert {:ok, materialized, _id_maps} =
               SheetBuilder.instantiate_snapshot(destination_project.id, snapshot,
                 asset_mode: :copy,
                 user_id: user.id,
                 reset_shortcut: true
               )

      avatars = Sheets.list_avatars(materialized.id)
      assert length(avatars) == 2

      source_asset_ids = [avatar_asset.id, expression_asset.id, gallery_asset.id]

      Enum.each(avatars, fn avatar ->
        assert avatar.asset.project_id == destination_project.id
        refute avatar.asset_id in source_asset_ids
        assert_copied_asset_storage(avatar.asset, destination_project.id)
      end)

      [cloned_gallery_block] = Enum.filter(Sheets.list_blocks(materialized.id), &(&1.type == "gallery"))
      [cloned_gallery_image] = Sheets.list_gallery_images(cloned_gallery_block.id)

      assert cloned_gallery_image.asset.project_id == destination_project.id
      refute cloned_gallery_image.asset_id in source_asset_ids
      assert cloned_gallery_image.label == "Bridge"
      assert_copied_asset_storage(cloned_gallery_image.asset, destination_project.id)
    end

    test "durably cleans copied assets when materialization rolls back", %{
      user: user,
      project: project,
      sheet: sheet
    } do
      avatar_asset = uploaded_image_asset(project, user, "copied-avatar.png", "copied avatar")
      broken_avatar_asset = uploaded_image_asset(project, user, "broken-avatar.png", "broken avatar")

      {:ok, _avatar} = Sheets.add_avatar(sheet, avatar_asset.id, %{name: "Default"})
      {:ok, _broken_avatar} = Sheets.add_avatar(sheet, broken_avatar_asset.id, %{name: "Broken"})

      snapshot =
        sheet
        |> SheetBuilder.build_snapshot()
        |> put_in(["asset_metadata", to_string(broken_avatar_asset.id)], %{})

      destination_project = project_fixture(user)
      destination_sheet = sheet_fixture(destination_project)

      assert_raise AssetCopyError, fn ->
        SheetBuilder.restore_snapshot(destination_sheet, snapshot,
          asset_mode: :copy,
          asset_error_mode: :strict,
          user_id: user.id
        )
      end

      refute Repo.exists?(from asset in Asset, where: asset.project_id == ^destination_project.id)
      assert [cleanup_job] = all_enqueued(worker: DeleteStorageObjectsWorker)

      cleanup_keys = cleanup_job.args["storage_keys"]

      copied_blob_key =
        BlobStore.blob_key(
          destination_project.id,
          avatar_asset.blob_hash,
          BlobStore.ext_from_content_type(avatar_asset.content_type)
        )

      copied_asset_key =
        Enum.find(cleanup_keys, &String.starts_with?(&1, "projects/#{destination_project.id}/assets/"))

      assert copied_blob_key in cleanup_keys
      assert is_binary(copied_asset_key)

      on_exit(fn -> Enum.each(cleanup_keys, &Assets.storage_delete/1) end)

      Repo.delete!(destination_project)
      assert :ok = perform_job(DeleteStorageObjectsWorker, cleanup_job.args)
      assert {:error, :enoent} = Assets.storage_download(copied_asset_key)
      assert {:error, :enoent} = Assets.storage_download(copied_blob_key)
    end
  end

  describe "table data in snapshots" do
    test "captures table columns and rows in snapshot", %{sheet: sheet} do
      table_block = table_block_fixture(sheet)
      _col = table_column_fixture(table_block, %{name: "Age", type: "number"})

      [default_row] = Sheets.list_table_rows(table_block.id)

      Sheets.update_table_cell(default_row, "age", "25")

      snapshot = SheetBuilder.build_snapshot(sheet)

      table_snap =
        Enum.find(snapshot["blocks"], &(&1["type"] == "table"))

      assert is_map(table_snap["table_data"])
      assert table_snap["table_data"]["columns"] != []
      assert table_snap["table_data"]["rows"] != []

      age_col = Enum.find(table_snap["table_data"]["columns"], &(&1["name"] == "Age"))
      assert age_col["type"] == "number"
      assert age_col["slug"] == "age"
    end

    test "restores table columns and rows", %{sheet: sheet} do
      table_block = table_block_fixture(sheet)
      col = table_column_fixture(table_block, %{name: "Score", type: "number"})

      [default_row] = Sheets.list_table_rows(table_block.id)

      Sheets.update_table_cell(default_row, col.slug, "99")

      snapshot = SheetBuilder.build_snapshot(sheet)

      # Modify table data
      Sheets.delete_table_column(col)

      # Restore
      {:ok, _restored} = SheetBuilder.restore_snapshot(sheet, snapshot)

      # Verify table data was restored
      blocks = Sheets.list_blocks(sheet.id)
      table = Enum.find(blocks, &(&1.type == "table"))
      assert table

      columns = Sheets.list_table_columns(table.id)
      assert Enum.any?(columns, &(&1.name == "Score"))

      rows = Sheets.list_table_rows(table.id)
      assert rows != []
      row = hd(rows)
      assert row.cells["score"] == "99"
    end

    test "non-table blocks have no table_data key", %{sheet: sheet} do
      _block = block_fixture(sheet, %{type: "text", config: %{"label" => "Name"}})
      snapshot = SheetBuilder.build_snapshot(sheet)

      text_snap = Enum.find(snapshot["blocks"], &(&1["type"] == "text"))
      refute Map.has_key?(text_snap, "table_data")
    end
  end

  describe "scan_references/1" do
    test "extracts asset and block inheritance refs" do
      snapshot = %{
        "avatar_asset_id" => 10,
        "banner_asset_id" => 20,
        "blocks" => [
          %{"inherited_from_block_id" => 30, "type" => "text", "position" => 0},
          %{"inherited_from_block_id" => nil, "type" => "number", "position" => 1}
        ]
      }

      refs = SheetBuilder.scan_references(snapshot)

      types_and_ids = refs |> Enum.map(&{&1.type, &1.id}) |> Enum.sort()

      assert {:asset, 10} in types_and_ids
      assert {:asset, 20} in types_and_ids
      assert {:block, 30} in types_and_ids
      assert length(refs) == 3
    end

    test "skips nil references" do
      snapshot = %{
        "avatar_asset_id" => nil,
        "banner_asset_id" => nil,
        "blocks" => [
          %{"inherited_from_block_id" => nil, "type" => "text", "position" => 0}
        ]
      }

      refs = SheetBuilder.scan_references(snapshot)
      assert refs == []
    end
  end

  describe "diff_snapshots/2" do
    test "detects name change" do
      old = %{"name" => "Old", "shortcut" => "old", "blocks" => []}
      new = %{"name" => "New", "shortcut" => "old", "blocks" => []}

      changes = SheetBuilder.diff_snapshots(old, new)
      assert [%{category: :property, action: :modified, detail: detail}] = changes
      assert detail =~ "Renamed"
    end

    test "detects added blocks" do
      old = %{"name" => "S", "blocks" => []}
      new = %{"name" => "S", "blocks" => [%{"position" => 0, "type" => "text"}]}

      changes = SheetBuilder.diff_snapshots(old, new)
      assert Enum.any?(changes, &(&1.category == :block && &1.action == :added))
    end

    test "detects removed blocks" do
      old = %{
        "name" => "S",
        "blocks" => [%{"position" => 0, "type" => "text", "variable_name" => "name"}]
      }

      new = %{"name" => "S", "blocks" => []}

      changes = SheetBuilder.diff_snapshots(old, new)
      assert Enum.any?(changes, &(&1.category == :block && &1.action == :removed))
    end

    test "detects modified blocks by variable_name" do
      old = %{
        "name" => "S",
        "blocks" => [
          %{
            "position" => 0,
            "type" => "text",
            "variable_name" => "health",
            "value" => %{"content" => "100"}
          }
        ]
      }

      new = %{
        "name" => "S",
        "blocks" => [
          %{
            "position" => 0,
            "type" => "text",
            "variable_name" => "health",
            "value" => %{"content" => "200"}
          }
        ]
      }

      changes = SheetBuilder.diff_snapshots(old, new)
      assert Enum.any?(changes, &(&1.category == :block && &1.action == :modified))
    end

    test "returns empty list for identical snapshots" do
      snapshot = %{"name" => "S", "shortcut" => "s", "blocks" => []}
      assert SheetBuilder.diff_snapshots(snapshot, snapshot) == []
    end
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

  defp assert_copied_asset_storage(asset, project_id) do
    blob_key =
      BlobStore.blob_key(
        project_id,
        asset.blob_hash,
        BlobStore.ext_from_content_type(asset.content_type)
      )

    assert {:ok, _content} = Assets.storage_download(asset.key)
    assert {:ok, _content} = Assets.storage_download(blob_key)

    on_exit(fn ->
      Assets.storage_delete(asset.key)
      Assets.storage_delete(blob_key)
    end)
  end
end
