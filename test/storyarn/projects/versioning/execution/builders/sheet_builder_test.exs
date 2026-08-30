defmodule Storyarn.Projects.Versioning.Builders.SheetBuilderTest do
  use Storyarn.DataCase, async: true
  use Oban.Testing, repo: Storyarn.Repo

  import Ecto.Query, warn: false
  import Storyarn.AccountsFixtures
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Localization
  alias Storyarn.Localization.LocalizedText
  alias Storyarn.Projects.Assets
  alias Storyarn.Projects.Assets.Asset
  alias Storyarn.Projects.Assets.BlobStore
  alias Storyarn.Projects.Assets.StorageCompensation
  alias Storyarn.Projects.Persistence.EntityReferenceRecord, as: EntityReference
  alias Storyarn.Projects.Project
  alias Storyarn.Projects.Versioning.AssetMaterializationCache
  alias Storyarn.Projects.Versioning.LocalizationSnapshotCodec
  alias Storyarn.Repo
  alias Storyarn.Sheets
  alias Storyarn.Sheets.Block
  alias Storyarn.Sheets.BlockGalleryImage
  alias Storyarn.Sheets.Sheet
  alias Storyarn.Sheets.SheetAvatar
  alias Storyarn.Workers.DeleteStorageObjectsWorker
  alias StoryarnTest.ProjectsSheetBuilderTestAdapter, as: SheetBuilder

  setup do
    user = user_fixture(%{email: "sheet-builder-#{Ecto.UUID.generate()}@example.com"})
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

    test "reloads a stale sheet root before capturing localization", %{
      project: project,
      sheet: stale_sheet
    } do
      _en = source_language_fixture(project, %{locale_code: "en", name: "English"})
      _es = language_fixture(project, %{locale_code: "es", name: "Spanish"})
      {:ok, _current_sheet} = Sheets.update_sheet(stale_sheet, %{name: "Fresh runtime name"})

      snapshot = SheetBuilder.build_snapshot(stale_sheet)

      assert snapshot["name"] == "Fresh runtime name"

      assert [%{"source_text" => "Fresh runtime name"}] =
               Enum.filter(snapshot["localization"], &(&1["source_type"] == "sheet"))

      assert snapshot["localization_manifest"] ==
               LocalizationSnapshotCodec.manifest(snapshot["localization"])
    end

    test "rejects a sheet in trash", %{sheet: sheet} do
      deleted_at = DateTime.truncate(DateTime.utc_now(), :second)
      Repo.update_all(from(current in Sheet, where: current.id == ^sheet.id), set: [deleted_at: deleted_at])

      assert_raise ArgumentError, "cannot snapshot inactive sheet #{sheet.id}", fn ->
        SheetBuilder.build_snapshot(sheet)
      end
    end

    test "rejects a sheet whose project is in trash", %{project: project, sheet: sheet} do
      deleted_at = DateTime.truncate(DateTime.utc_now(), :second)

      Repo.update_all(
        from(current in Project, where: current.id == ^project.id),
        set: [deleted_at: deleted_at]
      )

      assert_raise ArgumentError,
                   "cannot snapshot sheet under inactive project #{project.id}",
                   fn ->
                     SheetBuilder.build_snapshot(sheet)
                   end
    end

    test "fails closed instead of emitting an internally inconsistent localization snapshot", %{
      project: project,
      sheet: sheet
    } do
      _en = source_language_fixture(project, %{locale_code: "en", name: "English"})
      _es = language_fixture(project, %{locale_code: "es", name: "Spanish"})
      :ok = Localization.sync_sheet_names(project.id)
      [text] = Localization.get_texts_for_source("sheet", sheet.id)

      Repo.update_all(
        from(localized_text in LocalizedText, where: localized_text.id == ^text.id),
        set: [source_text: "Corrupt source"]
      )

      assert_raise ArgumentError, ~r/internally inconsistent sheet snapshot/, fn ->
        SheetBuilder.build_snapshot(sheet)
      end
    end

    test "canonical capture preserves inconsistent localization", %{
      project: project,
      sheet: sheet
    } do
      _en = source_language_fixture(project, %{locale_code: "en", name: "English"})
      _es = language_fixture(project, %{locale_code: "es", name: "Spanish"})
      :ok = Localization.sync_sheet_names(project.id)
      [text] = Localization.get_texts_for_source("sheet", sheet.id)

      Repo.update_all(
        from(localized_text in LocalizedText, where: localized_text.id == ^text.id),
        set: [source_text: "Persisted drift"]
      )

      snapshot = SheetBuilder.build_capture_snapshot(sheet)

      assert [%{"source_text" => "Persisted drift"}] = snapshot["localization"]

      assert [%{source_text: "Persisted drift"}] =
               Localization.get_texts_for_source("sheet", sheet.id)
    end

    test "canonical capture preserves missing localization rows instead of synthesizing them", %{
      project: project,
      sheet: sheet
    } do
      _en = source_language_fixture(project, %{locale_code: "en", name: "English"})
      _ca = language_fixture(project, %{locale_code: "ca", name: "Catalan"})
      :ok = Localization.sync_sheet_names(project.id)

      assert {1, _rows} =
               Repo.delete_all(
                 from(text in LocalizedText,
                   where:
                     text.source_type == "sheet" and text.source_id == ^sheet.id and
                       text.source_field == "name" and text.locale_code == "ca"
                 )
               )

      snapshot = SheetBuilder.build_capture_snapshot(sheet)

      assert snapshot["localization"] == []
      assert [] = Localization.get_texts_for_source("sheet", sheet.id)
    end

    test "canonical capture preserves nullable inheritance and residual block children", %{
      project: project,
      sheet: sheet,
      user: user
    } do
      table_block = table_block_fixture(sheet)
      column = table_column_fixture(table_block, %{name: "Residual column"})
      row = table_row_fixture(table_block, %{name: "Residual row"})

      gallery_asset = uploaded_image_asset(project, user, "residual-gallery.png", "residual gallery")
      gallery_block = block_fixture(sheet, %{type: "gallery", value: %{}})
      {:ok, gallery_image} = Sheets.add_gallery_image(gallery_block, gallery_asset.id)

      Repo.update_all(
        from(current in Sheet, where: current.id == ^sheet.id),
        set: [hidden_inherited_block_ids: nil]
      )

      Repo.update_all(
        from(block in Block, where: block.id in ^[table_block.id, gallery_block.id]),
        set: [type: "text"]
      )

      snapshot = SheetBuilder.build_capture_snapshot(sheet)

      assert snapshot["hidden_inherited_block_ids"] == nil

      captured_table = Enum.find(snapshot["blocks"], &(&1["original_id"] == table_block.id))
      assert Enum.any?(captured_table["table_data"]["columns"], &(&1["original_id"] == column.id))
      assert Enum.any?(captured_table["table_data"]["rows"], &(&1["original_id"] == row.id))

      captured_gallery = Enum.find(snapshot["blocks"], &(&1["original_id"] == gallery_block.id))
      assert [%{"original_id" => gallery_image_id}] = captured_gallery["gallery_images"]
      assert gallery_image_id == gallery_image.id

      assert Repo.get!(Sheet, sheet.id).hidden_inherited_block_ids == nil
      assert Repo.get!(Block, table_block.id).type == "text"
      assert Repo.get!(Block, gallery_block.id).type == "text"
    end

    test "still rejects an active localization row for a source outside the snapshot contract", %{
      project: project,
      sheet: sheet
    } do
      _en = source_language_fixture(project, %{locale_code: "en", name: "English"})
      _ca = language_fixture(project, %{locale_code: "ca", name: "Catalan"})

      block =
        block_fixture(sheet, %{
          type: "text",
          variable_name: "biography",
          value: %{"content" => "Biography"}
        })

      assert [_row] = Localization.get_texts_for_source("block", block.id)

      Repo.update_all(
        from(current in Block, where: current.id == ^block.id),
        set: [is_constant: true]
      )

      assert_raise ArgumentError, ~r/internally inconsistent sheet snapshot/, fn ->
        SheetBuilder.build_snapshot(sheet)
      end
    end

    test "fails closed instead of emitting a structurally invalid block snapshot", %{
      sheet: sheet
    } do
      block =
        block_fixture(sheet, %{
          type: "text",
          variable_name: "biography",
          value: %{"content" => "Biography"}
        })

      Repo.update_all(
        from(current in Block, where: current.id == ^block.id),
        set: [scope: "invalid-scope"]
      )

      assert_raise ArgumentError, ~r/internally inconsistent sheet snapshot/, fn ->
        SheetBuilder.build_snapshot(sheet)
      end
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

    test "accepts an acyclic external inheritance chain and rejects a transitive cycle", %{
      project: project,
      sheet: sheet
    } do
      middle_sheet = sheet_fixture(project, %{name: "Middle inheritance"})
      ancestor_sheet = sheet_fixture(project, %{name: "Ancestor inheritance"})
      block = block_fixture(sheet, %{type: "text"})
      middle = block_fixture(middle_sheet, %{type: "text"})
      ancestor = block_fixture(ancestor_sheet, %{type: "text"})

      Repo.update_all(
        from(current in Block, where: current.id == ^block.id),
        set: [inherited_from_block_id: middle.id]
      )

      Repo.update_all(
        from(current in Block, where: current.id == ^middle.id),
        set: [inherited_from_block_id: ancestor.id]
      )

      assert %{"blocks" => [%{"inherited_from_block_id" => middle_id}]} =
               SheetBuilder.build_snapshot(sheet)

      assert middle_id == middle.id

      Repo.update_all(
        from(current in Block, where: current.id == ^ancestor.id),
        set: [inherited_from_block_id: middle.id]
      )

      assert_raise ArgumentError, ~r/inheritance_cycle/, fn ->
        SheetBuilder.build_snapshot(sheet)
      end
    end

    test "rejects a transitive inherited block outside the project", %{
      user: user,
      project: project,
      sheet: sheet
    } do
      external_sheet = sheet_fixture(project)
      block = block_fixture(sheet, %{type: "text"})
      external = block_fixture(external_sheet, %{type: "text"})
      foreign_project = project_fixture(user)
      foreign_sheet = sheet_fixture(foreign_project)
      foreign = block_fixture(foreign_sheet, %{type: "text"})

      Repo.update_all(
        from(current in Block, where: current.id == ^block.id),
        set: [inherited_from_block_id: external.id]
      )

      Repo.update_all(
        from(current in Block, where: current.id == ^external.id),
        set: [inherited_from_block_id: foreign.id]
      )

      assert_raise ArgumentError, ~r/invalid_block_reference/, fn ->
        SheetBuilder.build_snapshot(sheet)
      end
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

    test "normalizes exactly one deterministic default avatar", %{
      project: project,
      sheet: sheet,
      user: user
    } do
      first_asset = uploaded_image_asset(project, user, "first-default.png", "first-default")
      second_asset = uploaded_image_asset(project, user, "second-default.png", "second-default")
      {:ok, first} = Sheets.add_avatar(sheet, first_asset.id, %{name: "First"})
      {:ok, second} = Sheets.add_avatar(sheet, second_asset.id, %{name: "Second"})

      Repo.update_all(
        from(avatar in SheetAvatar, where: avatar.id in ^[first.id, second.id]),
        set: [is_default: false]
      )

      zero_default_snapshot = SheetBuilder.build_snapshot(sheet)

      assert [%{"original_id" => first_id, "is_default" => true}, %{"is_default" => false}] =
               zero_default_snapshot["avatars"]

      assert first_id == first.id
      assert zero_default_snapshot["avatar_asset_id"] == first.asset_id

      exact_zero_default_snapshot = SheetBuilder.build_capture_snapshot(sheet)

      assert Enum.all?(exact_zero_default_snapshot["avatars"], &(&1["is_default"] == false))
      assert exact_zero_default_snapshot["avatar_asset_id"] == nil

      Repo.update_all(
        from(avatar in SheetAvatar, where: avatar.id in ^[first.id, second.id]),
        set: [is_default: true]
      )

      multiple_default_snapshot = SheetBuilder.build_snapshot(sheet)

      assert [%{"original_id" => ^first_id, "is_default" => true}, %{"is_default" => false}] =
               multiple_default_snapshot["avatars"]

      assert multiple_default_snapshot["avatar_asset_id"] == first.asset_id

      exact_multiple_default_snapshot = SheetBuilder.build_capture_snapshot(sheet)

      assert Enum.all?(exact_multiple_default_snapshot["avatars"], &(&1["is_default"] == true))
      assert exact_multiple_default_snapshot["avatar_asset_id"] == first.asset_id
    end

    test "rejects cross-project banner, avatar, and gallery assets", %{
      user: user,
      sheet: sheet
    } do
      foreign_project = project_fixture(user)

      foreign_asset =
        uploaded_image_asset(
          foreign_project,
          user,
          "foreign-sheet-asset.png",
          "foreign sheet asset"
        )

      Repo.update_all(
        from(current in Sheet, where: current.id == ^sheet.id),
        set: [banner_asset_id: foreign_asset.id]
      )

      assert_raise ArgumentError, ~r/owned by another project/, fn ->
        SheetBuilder.build_snapshot(sheet)
      end

      Repo.update_all(
        from(current in Sheet, where: current.id == ^sheet.id),
        set: [banner_asset_id: nil]
      )

      foreign_avatar =
        %SheetAvatar{}
        |> SheetAvatar.create_changeset(%{
          sheet_id: sheet.id,
          asset_id: foreign_asset.id,
          name: "Foreign"
        })
        |> Repo.insert!()

      assert_raise ArgumentError, ~r/owned by another project/, fn ->
        SheetBuilder.build_snapshot(sheet)
      end

      Repo.delete!(foreign_avatar)

      gallery_block = block_fixture(sheet, %{type: "gallery", value: %{}})

      %BlockGalleryImage{}
      |> BlockGalleryImage.create_changeset(%{
        block_id: gallery_block.id,
        asset_id: foreign_asset.id
      })
      |> Repo.insert!()

      assert_raise ArgumentError, ~r/owned by another project/, fn ->
        SheetBuilder.build_snapshot(sheet)
      end
    end
  end

  describe "restore_snapshot/3" do
  end

  describe "instantiate_snapshot/3" do
    test "exact materialization preserves nullable hidden inherited block IDs", %{
      project: project,
      sheet: sheet
    } do
      Repo.update_all(
        from(current in Sheet, where: current.id == ^sheet.id),
        set: [hidden_inherited_block_ids: nil]
      )

      snapshot = SheetBuilder.build_capture_snapshot(sheet)

      assert snapshot["hidden_inherited_block_ids"] == nil

      assert {:error, {:invalid_snapshot, {:expected_id_list, :hidden_inherited_block}}} =
               SheetBuilder.instantiate_snapshot(project.id, snapshot, reset_shortcut: true)

      assert {:ok, materialized, _id_maps} =
               SheetBuilder.instantiate_snapshot(project.id, snapshot,
                 reset_shortcut: true,
                 materialization_mode: :exact
               )

      assert Repo.get!(Sheet, materialized.id).hidden_inherited_block_ids == nil
    end

    test "rejects malformed nested collections before materializing anything", %{
      user: user,
      sheet: sheet
    } do
      _block = block_fixture(sheet, %{type: "text", value: %{"content" => "Biography"}})
      snapshot = SheetBuilder.build_snapshot(sheet)
      malformed_snapshot = Map.put(snapshot, "blocks", [42])
      target_project = project_fixture(user)

      count_before =
        Repo.aggregate(
          from(target_sheet in Sheet, where: target_sheet.project_id == ^target_project.id),
          :count
        )

      assert {:error, {:invalid_snapshot, {:expected_map_entries, :blocks}}} =
               SheetBuilder.instantiate_snapshot(
                 target_project.id,
                 malformed_snapshot,
                 reset_shortcut: true
               )

      assert Repo.aggregate(
               from(target_sheet in Sheet,
                 where: target_sheet.project_id == ^target_project.id
               ),
               :count
             ) == count_before
    end

    test "returns an old-to-new avatar ID map", %{
      project: project,
      sheet: sheet,
      user: user
    } do
      first_asset = uploaded_image_asset(project, user, "mapped-first.png", "mapped-first")
      second_asset = uploaded_image_asset(project, user, "mapped-second.png", "mapped-second")
      {:ok, first} = Sheets.add_avatar(sheet, first_asset.id, %{name: "First"})
      {:ok, second} = Sheets.add_avatar(sheet, second_asset.id, %{name: "Second"})
      snapshot = SheetBuilder.build_snapshot(sheet)

      assert {:ok, materialized, id_maps} =
               SheetBuilder.instantiate_snapshot(project.id, snapshot, reset_shortcut: true)

      assert id_maps.avatar |> Map.keys() |> Enum.sort() == Enum.sort([first.id, second.id])

      new_avatar_ids =
        materialized.id
        |> Sheets.list_avatars()
        |> Enum.map(& &1.id)
        |> Enum.sort()

      assert id_maps.avatar |> Map.values() |> Enum.sort() == new_avatar_ids
      refute Enum.any?(id_maps.avatar, fn {old_id, new_id} -> old_id == new_id end)
    end

    test "rejects zero or multiple default avatars before materializing", %{
      project: project,
      sheet: sheet,
      user: user
    } do
      first_asset = uploaded_image_asset(project, user, "invalid-first.png", "invalid-first")
      second_asset = uploaded_image_asset(project, user, "invalid-second.png", "invalid-second")
      {:ok, _first} = Sheets.add_avatar(sheet, first_asset.id, %{name: "First"})
      {:ok, _second} = Sheets.add_avatar(sheet, second_asset.id, %{name: "Second"})
      snapshot = SheetBuilder.build_snapshot(sheet)

      invalid_snapshots = [
        {0,
         Map.update!(snapshot, "avatars", fn avatars ->
           Enum.map(avatars, &Map.put(&1, "is_default", false))
         end)},
        {2,
         Map.update!(snapshot, "avatars", fn avatars ->
           Enum.map(avatars, &Map.put(&1, "is_default", true))
         end)}
      ]

      sheet_count_before =
        Repo.aggregate(
          from(candidate in Sheet, where: candidate.project_id == ^project.id),
          :count
        )

      for {actual_count, invalid_snapshot} <- invalid_snapshots do
        assert {:error, {:invalid_snapshot, {:avatar_default_cardinality, 1, ^actual_count}}} =
                 SheetBuilder.instantiate_snapshot(project.id, invalid_snapshot, reset_shortcut: true)
      end

      assert Repo.aggregate(
               from(candidate in Sheet, where: candidate.project_id == ^project.id),
               :count
             ) == sheet_count_before
    end

    test "can explicitly defer localization to the project recovery phase", %{
      user: user,
      project: project,
      sheet: sheet
    } do
      _en = source_language_fixture(project, %{locale_code: "en", name: "English"})
      _es = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      _block =
        block_fixture(sheet, %{
          type: "text",
          variable_name: "bio",
          value: %{"content" => "Deferred biography"}
        })

      :ok = Localization.sync_sheet_names(project.id)
      snapshot = SheetBuilder.build_snapshot(sheet)
      assert length(snapshot["localization"]) == 2

      target_project = project_fixture(user)
      _target_en = source_language_fixture(target_project, %{locale_code: "en", name: "English"})
      _target_es = language_fixture(target_project, %{locale_code: "es", name: "Spanish"})

      assert {:ok, materialized, _id_maps} =
               SheetBuilder.instantiate_snapshot(target_project.id, snapshot,
                 reset_shortcut: true,
                 restore_localization: false
               )

      [materialized_block] = Enum.filter(materialized.blocks, &(&1.type == "text"))
      assert Localization.get_texts_for_source("sheet", materialized.id) == []
      assert Localization.get_texts_for_source("block", materialized_block.id) == []
    end

    test "validates localization integrity before materializing even when recovery defers writes", %{
      user: user,
      project: project,
      sheet: sheet
    } do
      _en = source_language_fixture(project, %{locale_code: "en", name: "English"})
      _es = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      _block =
        block_fixture(sheet, %{
          type: "text",
          variable_name: "bio",
          value: %{"content" => "Versioned biography"}
        })

      :ok = Localization.sync_sheet_names(project.id)
      snapshot = SheetBuilder.build_snapshot(sheet)
      target_project = project_fixture(user)

      sheet_count_before =
        Repo.aggregate(
          from(target_sheet in Sheet, where: target_sheet.project_id == ^target_project.id),
          :count
        )

      [row | remaining_rows] = snapshot["localization"]

      stale_manifest_snapshot =
        Map.put(snapshot, "localization", remaining_rows)

      semantic_corruption_snapshot =
        put_localization_with_manifest(
          snapshot,
          [Map.put(row, "source_text", "Forged source") | remaining_rows]
        )

      for invalid_snapshot <- [stale_manifest_snapshot, semantic_corruption_snapshot] do
        assert {:error, _reason} =
                 SheetBuilder.instantiate_snapshot(target_project.id, invalid_snapshot,
                   reset_shortcut: true,
                   restore_localization: false
                 )

        assert Repo.aggregate(
                 from(target_sheet in Sheet, where: target_sheet.project_id == ^target_project.id),
                 :count
               ) == sheet_count_before
      end
    end

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

      Repo.update_all(from(b in Block, where: b.id == ^block_b.id),
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

    test "rejects raw type corruption and inheritance cycles before materializing", %{
      project: project,
      sheet: sheet
    } do
      block_a = block_fixture(sheet, %{type: "text", position: 0})
      block_b = block_fixture(sheet, %{type: "number", position: 1})
      snapshot = SheetBuilder.build_snapshot(sheet)

      cyclic_snapshot =
        Map.update!(snapshot, "blocks", fn blocks ->
          Enum.map(blocks, fn block ->
            case block["original_id"] do
              id when id == block_a.id ->
                Map.put(block, "inherited_from_block_id", block_b.id)

              id when id == block_b.id ->
                Map.put(block, "inherited_from_block_id", block_a.id)
            end
          end)
        end)

      raw_type_corruption =
        Map.update!(snapshot, "blocks", fn [first | rest] ->
          [Map.put(first, "position", "0") | rest]
        end)

      sheet_count = Repo.aggregate(from(current in Sheet, where: current.project_id == ^project.id), :count)

      for invalid_snapshot <- [cyclic_snapshot, raw_type_corruption] do
        assert {:error, _reason} =
                 SheetBuilder.instantiate_snapshot(project.id, invalid_snapshot, reset_shortcut: true)

        assert Repo.aggregate(
                 from(current in Sheet, where: current.project_id == ^project.id),
                 :count
               ) == sheet_count
      end
    end

    test "maps same-position blocks, table data, gallery images, inheritance, and hidden ids by original id", %{
      project: project,
      sheet: sheet,
      user: user
    } do
      source =
        block_fixture(sheet, %{
          type: "text",
          position: 7,
          variable_name: "source",
          value: %{"content" => "Source"}
        })

      inherited =
        block_fixture(sheet, %{
          type: "number",
          position: 7,
          variable_name: "inherited"
        })

      Repo.update_all(
        from(block in Block, where: block.id == ^inherited.id),
        set: [inherited_from_block_id: source.id]
      )

      table = table_block_fixture(sheet, %{position: 7})
      column = table_column_fixture(table, %{name: "Exact score", type: "number"})
      [row] = Sheets.list_table_rows(table.id)
      {:ok, _row} = Sheets.update_table_cell(row, column.slug, "314")

      gallery = block_fixture(sheet, %{type: "gallery", position: 7, value: %{}})
      gallery_asset = uploaded_image_asset(project, user, "stable-gallery.png", "stable-gallery")
      {:ok, image} = Sheets.add_gallery_image(gallery, gallery_asset.id)
      {:ok, _image} = Sheets.update_gallery_image(image, %{label: "Exact gallery"})

      sheet
      |> Ecto.Changeset.change(hidden_inherited_block_ids: [source.id])
      |> Repo.update!()

      snapshot = SheetBuilder.build_snapshot(sheet)

      assert {:ok, materialized, id_maps} =
               SheetBuilder.instantiate_snapshot(project.id, snapshot, reset_shortcut: true)

      assert Repo.get!(Block, id_maps.block[inherited.id]).inherited_from_block_id ==
               id_maps.block[source.id]

      assert Repo.get!(Sheet, materialized.id).hidden_inherited_block_ids == [
               id_maps.block[source.id]
             ]

      cloned_table_id = id_maps.block[table.id]
      assert Enum.any?(Sheets.list_table_columns(cloned_table_id), &(&1.name == "Exact score"))
      assert Enum.any?(Sheets.list_table_rows(cloned_table_id), &(&1.cells[column.slug] == "314"))

      cloned_gallery_id = id_maps.block[gallery.id]
      assert [%{label: "Exact gallery", asset_id: asset_id}] = Sheets.list_gallery_images(cloned_gallery_id)
      assert asset_id == gallery_asset.id

      assert MapSet.new(Map.keys(id_maps.block)) ==
               MapSet.new([source.id, inherited.id, table.id, gallery.id])
    end

    test "preserves, drops, or explicitly remaps active external block inheritance in the destination project", %{
      user: user,
      project: project,
      sheet: sheet
    } do
      external_sheet = sheet_fixture(project, %{name: "Source external"})
      external_block = block_fixture(external_sheet, %{type: "text"})
      inherited = block_fixture(sheet, %{type: "text"})

      Repo.update_all(
        from(block in Block, where: block.id == ^inherited.id),
        set: [inherited_from_block_id: external_block.id]
      )

      sheet
      |> Ecto.Changeset.change(hidden_inherited_block_ids: [external_block.id])
      |> Repo.update!()

      snapshot = SheetBuilder.build_snapshot(sheet)

      assert {:ok, preserved, preserved_maps} =
               SheetBuilder.instantiate_snapshot(project.id, snapshot,
                 reset_shortcut: true,
                 preserve_external_refs: true
               )

      assert Repo.get!(Block, preserved_maps.block[inherited.id]).inherited_from_block_id ==
               external_block.id

      assert Repo.get!(Sheet, preserved.id).hidden_inherited_block_ids == [external_block.id]

      assert {:ok, dropped, dropped_maps} =
               SheetBuilder.instantiate_snapshot(project.id, snapshot,
                 reset_shortcut: true,
                 preserve_external_refs: false
               )

      assert is_nil(Repo.get!(Block, dropped_maps.block[inherited.id]).inherited_from_block_id)
      assert Repo.get!(Sheet, dropped.id).hidden_inherited_block_ids == []

      destination_project = project_fixture(user)
      destination_external_sheet = sheet_fixture(destination_project)
      destination_external_block = block_fixture(destination_external_sheet, %{type: "text"})

      assert {:ok, remapped, remapped_maps} =
               SheetBuilder.instantiate_snapshot(destination_project.id, snapshot,
                 reset_shortcut: true,
                 preserve_external_refs: false,
                 external_id_maps: %{
                   block: %{external_block.id => destination_external_block.id}
                 }
               )

      assert Repo.get!(Block, remapped_maps.block[inherited.id]).inherited_from_block_id ==
               destination_external_block.id

      assert Repo.get!(Sheet, remapped.id).hidden_inherited_block_ids == [
               destination_external_block.id
             ]

      assert {:ok, foreign_dropped, foreign_maps} =
               SheetBuilder.instantiate_snapshot(destination_project.id, snapshot,
                 reset_shortcut: true,
                 preserve_external_refs: false,
                 external_id_maps: %{block: %{external_block.id => external_block.id}}
               )

      assert is_nil(Repo.get!(Block, foreign_maps.block[inherited.id]).inherited_from_block_id)
      assert Repo.get!(Sheet, foreign_dropped.id).hidden_inherited_block_ids == []
    end

    test "rejects a transitive cycle in preserved external inheritance before materializing", %{
      project: project,
      sheet: sheet
    } do
      middle_sheet = sheet_fixture(project)
      ancestor_sheet = sheet_fixture(project)
      block = block_fixture(sheet, %{type: "text"})
      middle = block_fixture(middle_sheet, %{type: "text"})
      ancestor = block_fixture(ancestor_sheet, %{type: "text"})

      Repo.update_all(
        from(current in Block, where: current.id == ^block.id),
        set: [inherited_from_block_id: middle.id]
      )

      Repo.update_all(
        from(current in Block, where: current.id == ^middle.id),
        set: [inherited_from_block_id: ancestor.id]
      )

      snapshot = SheetBuilder.build_snapshot(sheet)

      Repo.update_all(
        from(current in Block, where: current.id == ^ancestor.id),
        set: [inherited_from_block_id: middle.id]
      )

      sheet_count =
        Repo.aggregate(
          from(current in Sheet, where: current.project_id == ^project.id),
          :count
        )

      assert {:error, {:invalid_snapshot, {:inheritance_cycle, cycle_id}}} =
               SheetBuilder.instantiate_snapshot(project.id, snapshot,
                 reset_shortcut: true,
                 preserve_external_refs: true
               )

      assert cycle_id == middle.id

      assert Repo.aggregate(
               from(current in Sheet, where: current.project_id == ^project.id),
               :count
             ) == sheet_count
    end

    test "rebuilds only destination-project backlinks for direct references and rich-text mentions", %{
      user: user,
      project: project,
      sheet: sheet
    } do
      source_target = sheet_fixture(project, %{name: "Source target"})

      direct =
        block_fixture(sheet, %{
          type: "reference",
          value: %{"target_type" => "sheet", "target_id" => source_target.id}
        })

      mention_html =
        ~s(<p><span class="mention" data-type="sheet" data-id="#{source_target.id}">Source</span></p>)

      mention = block_fixture(sheet, %{type: "rich_text", value: %{"content" => mention_html}})
      snapshot = SheetBuilder.build_snapshot(sheet)

      assert {:ok, _same_project_sheet, same_project_maps} =
               SheetBuilder.instantiate_snapshot(project.id, snapshot, reset_shortcut: true)

      assert block_reference_exists?(same_project_maps.block[direct.id], "sheet", source_target.id)
      assert block_reference_exists?(same_project_maps.block[mention.id], "sheet", source_target.id)

      destination_project = project_fixture(user)

      assert {:ok, _cross_project_sheet, cross_project_maps} =
               SheetBuilder.instantiate_snapshot(destination_project.id, snapshot, reset_shortcut: true)

      refute block_reference_exists?(cross_project_maps.block[direct.id], "sheet", source_target.id)
      refute block_reference_exists?(cross_project_maps.block[mention.id], "sheet", source_target.id)
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

    test "immediately cleans copied asset paths and retains the project blob after rollback", %{
      user: user,
      project: project,
      sheet: sheet
    } do
      run_id = Ecto.UUID.generate()
      avatar_asset = uploaded_image_asset(project, user, "copied-avatar-#{run_id}.png", "copied avatar")
      broken_avatar_asset = uploaded_image_asset(project, user, "broken-avatar-#{run_id}.png", "broken avatar")

      {:ok, _avatar} = Sheets.add_avatar(sheet, avatar_asset.id, %{name: "Default"})
      {:ok, _broken_avatar} = Sheets.add_avatar(sheet, broken_avatar_asset.id, %{name: "Broken"})

      snapshot =
        sheet
        |> SheetBuilder.build_snapshot()
        |> put_in(["asset_metadata", to_string(broken_avatar_asset.id)], %{})

      destination_project = project_fixture(user)
      copied_avatar_paths_before = stored_asset_paths(avatar_asset.filename)

      assert {:error, {:asset_materialization_failed, broken_avatar_asset_id, :missing_asset_metadata}} =
               SheetBuilder.instantiate_snapshot(destination_project.id, snapshot,
                 asset_mode: :copy,
                 user_id: user.id,
                 reset_shortcut: true
               )

      assert broken_avatar_asset_id == broken_avatar_asset.id

      refute Repo.exists?(from asset in Asset, where: asset.project_id == ^destination_project.id)

      copied_blob_key =
        BlobStore.blob_key(
          destination_project.id,
          avatar_asset.blob_hash,
          BlobStore.ext_from_content_type(avatar_asset.content_type)
        )

      on_exit(fn -> delete_storage_blob(copied_blob_key) end)

      assert [] = all_enqueued(worker: DeleteStorageObjectsWorker)
      assert stored_asset_paths(avatar_asset.filename) == copied_avatar_paths_before
      assert {:ok, "copied avatar"} = Assets.storage_download(copied_blob_key)
    end

    test "keeps banner, avatar, and gallery assets when external references are not preserved", %{
      project: project,
      sheet: sheet,
      user: user
    } do
      banner_asset = uploaded_image_asset(project, user, "kept-banner.png", "kept-banner")
      avatar_asset = uploaded_image_asset(project, user, "kept-avatar.png", "kept-avatar")
      gallery_asset = uploaded_image_asset(project, user, "kept-gallery.png", "kept-gallery")

      {:ok, _sheet} = Sheets.update_sheet(sheet, %{banner_asset_id: banner_asset.id})
      {:ok, _avatar} = Sheets.add_avatar(sheet, avatar_asset.id, %{name: "Kept avatar"})

      gallery_block = block_fixture(sheet, %{type: "gallery", value: %{}})
      {:ok, _gallery_image} = Sheets.add_gallery_image(gallery_block, gallery_asset.id)

      snapshot = SheetBuilder.build_snapshot(sheet)
      destination_project = project_fixture(user)

      assert {:ok, materialized, _id_maps} =
               SheetBuilder.instantiate_snapshot(destination_project.id, snapshot,
                 preserve_external_refs: false,
                 reset_shortcut: true,
                 user_id: user.id
               )

      restored_sheet = Repo.get!(Sheet, materialized.id)
      [restored_avatar] = Sheets.list_avatars(materialized.id)
      [restored_gallery_block] = Enum.filter(Sheets.list_blocks(materialized.id), &(&1.type == "gallery"))
      [restored_gallery_image] = Sheets.list_gallery_images(restored_gallery_block.id)

      destination_asset_ids = [
        restored_sheet.banner_asset_id,
        restored_avatar.asset_id,
        restored_gallery_image.asset_id
      ]

      refute Enum.any?(destination_asset_ids, &is_nil/1)
      refute Enum.any?(destination_asset_ids, &(&1 in [banner_asset.id, avatar_asset.id, gallery_asset.id]))

      Enum.each(destination_asset_ids, fn asset_id ->
        destination_asset = Repo.get!(Asset, asset_id)
        assert destination_asset.project_id == destination_project.id
        on_exit(fn -> Assets.storage_delete(destination_asset.key) end)
      end)
    end

    test "materializes one destination asset for the same banner, avatar, and gallery source", %{
      project: project,
      sheet: sheet,
      user: user
    } do
      shared_asset = uploaded_image_asset(project, user, "shared-sheet-asset.png", "shared-sheet-asset")

      {:ok, _sheet} = Sheets.update_sheet(sheet, %{banner_asset_id: shared_asset.id})
      {:ok, _avatar} = Sheets.add_avatar(sheet, shared_asset.id, %{name: "Shared avatar"})
      gallery_block = block_fixture(sheet, %{type: "gallery", value: %{}})
      {:ok, _gallery_image} = Sheets.add_gallery_image(gallery_block, shared_asset.id)

      snapshot = SheetBuilder.build_snapshot(sheet)
      destination_project = project_fixture(user)

      assert {:ok, materialized, _id_maps} =
               SheetBuilder.instantiate_snapshot(destination_project.id, snapshot,
                 asset_mode: :copy,
                 reset_shortcut: true,
                 user_id: user.id
               )

      restored_sheet = Repo.get!(Sheet, materialized.id)
      [restored_avatar] = Sheets.list_avatars(materialized.id)
      [restored_gallery_block] = Enum.filter(Sheets.list_blocks(materialized.id), &(&1.type == "gallery"))
      [restored_gallery_image] = Sheets.list_gallery_images(restored_gallery_block.id)

      assert [destination_asset_id] =
               Enum.uniq([restored_sheet.banner_asset_id, restored_avatar.asset_id, restored_gallery_image.asset_id])

      refute destination_asset_id == shared_asset.id

      assert Repo.aggregate(
               from(asset in Asset,
                 where:
                   asset.project_id == ^destination_project.id and
                     asset.blob_hash == ^shared_asset.blob_hash
               ),
               :count
             ) == 1

      destination_asset = Repo.get!(Asset, destination_asset_id)
      on_exit(fn -> Assets.storage_delete(destination_asset.key) end)
    end

    test "preserves caller-owned asset cache and tracker across sheet materializations", %{
      project: project,
      sheet: sheet,
      user: user
    } do
      source_asset = uploaded_image_asset(project, user, "shared-scope.png", "shared-scope")
      {:ok, _sheet} = Sheets.update_sheet(sheet, %{banner_asset_id: source_asset.id})

      snapshot = SheetBuilder.build_snapshot(sheet)
      destination_project = project_fixture(user)
      cache = AssetMaterializationCache.new()
      tracker = StorageCompensation.new()

      on_exit(fn ->
        AssetMaterializationCache.discard(cache)
        StorageCompensation.discard(tracker)
      end)

      opts = [
        asset_mode: :copy,
        asset_materialization_cache: cache,
        asset_copy_tracker: tracker,
        reset_shortcut: true,
        user_id: user.id
      ]

      assert {:ok, first_sheet, _id_maps} =
               SheetBuilder.instantiate_snapshot(destination_project.id, snapshot, opts)

      assert {:ok, second_sheet, _id_maps} =
               SheetBuilder.instantiate_snapshot(destination_project.id, snapshot, opts)

      first_asset_id = Repo.get!(Sheet, first_sheet.id).banner_asset_id
      assert Repo.get!(Sheet, second_sheet.id).banner_asset_id == first_asset_id

      destination_asset = Repo.get!(Asset, first_asset_id)

      assert :ok =
               StorageCompensation.cleanup(tracker,
                 enqueue_fun: fn keys ->
                   send(self(), {:tracked_asset_keys, keys})
                   :ok
                 end,
                 delete_fun: fn _keys -> :ok end
               )

      assert_receive {:tracked_asset_keys, tracked_keys}
      assert destination_asset.key in tracked_keys

      destination_blob_key =
        BlobStore.blob_key(
          destination_project.id,
          destination_asset.blob_hash,
          BlobStore.ext_from_content_type(destination_asset.content_type)
        )

      assert destination_blob_key in tracked_keys

      on_exit(fn ->
        Assets.storage_delete(destination_asset.key)
        Assets.storage_delete(destination_blob_key)
      end)
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
      assert is_integer(age_col["original_id"])
      assert age_col["type"] == "number"
      assert age_col["slug"] == "age"

      assert Enum.all?(table_snap["table_data"]["rows"], &is_integer(&1["original_id"]))
    end

    test "non-table blocks have no table_data key", %{sheet: sheet} do
      _block = block_fixture(sheet, %{type: "text", config: %{"label" => "Name"}})
      snapshot = SheetBuilder.build_snapshot(sheet)

      text_snap = Enum.find(snapshot["blocks"], &(&1["type"] == "text"))
      refute Map.has_key?(text_snap, "table_data")
    end
  end

  describe "scan_references/1" do
    test "extracts assets, inheritance, reference targets, and rich-text mentions" do
      snapshot = %{
        "avatar_asset_id" => 10,
        "banner_asset_id" => 20,
        "hidden_inherited_block_ids" => [40],
        "blocks" => [
          %{"inherited_from_block_id" => 30, "type" => "text", "position" => 0},
          %{
            "inherited_from_block_id" => nil,
            "type" => "reference",
            "position" => 1,
            "value" => %{"target_type" => "flow", "target_id" => "50"}
          },
          %{
            "inherited_from_block_id" => nil,
            "type" => "rich_text",
            "position" => 2,
            "value" => %{
              "content" =>
                ~s(<p><span class="mention" data-type="sheet" data-id="60">Sheet</span><span class="mention" data-type="flow" data-id="70">Flow</span></p>)
            }
          }
        ]
      }

      refs = SheetBuilder.scan_references(snapshot)

      types_and_ids = refs |> Enum.map(&{&1.type, &1.id}) |> Enum.sort()

      assert {:asset, 10} in types_and_ids
      assert {:asset, 20} in types_and_ids
      assert {:block, 30} in types_and_ids
      assert {:block, 40} in types_and_ids
      assert {:flow, "50"} in types_and_ids
      assert {:sheet, "60"} in types_and_ids
      assert {:flow, "70"} in types_and_ids
      assert length(refs) == 7
    end

    test "surfaces malformed reference blocks and mentions" do
      snapshot = %{
        "blocks" => [
          %{
            "type" => "reference",
            "value" => %{"target_type" => "scene", "target_id" => 80}
          },
          %{
            "type" => "rich_text",
            "value" => %{
              "content" => ~s(<p><span class="mention" data-type="sheet">Missing ID</span></p>)
            }
          }
        ]
      }

      refs = SheetBuilder.scan_references(snapshot)

      assert Enum.any?(refs, &(&1.type == :reference and &1.id == 80))
      assert Enum.any?(refs, &(&1.type == :reference and is_binary(&1.id)))
      assert Enum.all?(refs, &(&1.context =~ "malformed embedded reference"))
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

    test "detects modified blocks by snapshot identity" do
      old = %{
        "name" => "S",
        "blocks" => [
          %{
            "original_id" => 41,
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
            "original_id" => 41,
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

    test "matches modified blocks by original ID across variable-name and position changes" do
      old = %{
        "name" => "S",
        "blocks" => [
          %{
            "original_id" => 42,
            "position" => 0,
            "type" => "text",
            "variable_name" => "old_name",
            "value" => %{"content" => "old"}
          }
        ]
      }

      new = %{
        "name" => "S",
        "blocks" => [
          %{
            "original_id" => 42,
            "position" => 7,
            "type" => "text",
            "variable_name" => "new_name",
            "value" => %{"content" => "new"}
          }
        ]
      }

      changes = SheetBuilder.diff_snapshots(old, new)

      assert [%{category: :block, action: :modified}] = changes
    end

    test "returns empty list for identical snapshots" do
      snapshot = %{"name" => "S", "shortcut" => "s", "blocks" => []}
      assert SheetBuilder.diff_snapshots(snapshot, snapshot) == []
    end
  end

  defp block_reference_exists?(source_id, target_type, target_id) do
    Repo.exists?(
      from(reference in EntityReference,
        where:
          reference.source_type == "block" and
            reference.source_id == ^source_id and
            reference.target_type == ^target_type and
            reference.target_id == ^target_id
      )
    )
  end

  defp put_localization_with_manifest(snapshot, rows) do
    snapshot
    |> Map.put("localization", rows)
    |> Map.put(
      "localization_manifest",
      LocalizationSnapshotCodec.manifest(
        rows,
        snapshot["localization_manifest"]["target_locales"]
      )
    )
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

  defp stored_asset_paths(filename) do
    upload_dir =
      :storyarn
      |> Application.fetch_env!(:storage)
      |> Keyword.fetch!(:upload_dir)
      |> Path.expand()

    upload_dir
    |> Path.join("projects/*/assets/*/#{filename}")
    |> Path.wildcard()
    |> MapSet.new()
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
