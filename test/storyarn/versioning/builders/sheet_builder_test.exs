defmodule Storyarn.Versioning.Builders.SheetBuilderTest do
  use Storyarn.DataCase, async: true
  use Oban.Testing, repo: Storyarn.Repo

  import Ecto.Query, warn: false
  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Assets
  alias Storyarn.Assets.Asset
  alias Storyarn.Assets.BlobStore
  alias Storyarn.Assets.StorageCompensation
  alias Storyarn.Flows
  alias Storyarn.Flows.EntityTrashRef
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.VariableReference
  alias Storyarn.Flows.VariableReferenceTracker
  alias Storyarn.Localization
  alias Storyarn.Localization.LocalizedText
  alias Storyarn.Projects.Project
  alias Storyarn.Repo
  alias Storyarn.Sheets
  alias Storyarn.Sheets.Block
  alias Storyarn.Sheets.BlockGalleryImage
  alias Storyarn.Sheets.EntityReference
  alias Storyarn.Sheets.PropertyInheritance
  alias Storyarn.Sheets.Sheet
  alias Storyarn.Sheets.SheetAvatar
  alias Storyarn.Sheets.TableColumn
  alias Storyarn.Sheets.TableRow
  alias Storyarn.Versioning.AssetMaterializationCache
  alias Storyarn.Versioning.Builders.SheetBuilder
  alias Storyarn.Versioning.LocalizationSnapshotCodec
  alias Storyarn.Workers.DeleteStorageObjectsWorker

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

      Repo.update_all(
        from(avatar in SheetAvatar, where: avatar.id in ^[first.id, second.id]),
        set: [is_default: true]
      )

      multiple_default_snapshot = SheetBuilder.build_snapshot(sheet)

      assert [%{"original_id" => ^first_id, "is_default" => true}, %{"is_default" => false}] =
               multiple_default_snapshot["avatars"]

      assert multiple_default_snapshot["avatar_asset_id"] == first.asset_id
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
      {:ok, restored} =
        SheetBuilder.restore_snapshot(modified_sheet, snapshot, restore_action: {:entity_version_restore, "sheet"})

      assert restored.name == sheet.name
      blocks = Sheets.list_blocks(sheet.id)
      assert length(blocks) == 2
      assert Enum.find(blocks, &(&1.type == "text")).word_count == 3
    end

    test "full-project restore skips external inheritance and table row locks", %{
      sheet: sheet
    } do
      snapshot = SheetBuilder.build_snapshot(sheet)
      handler_id = "full-project-sheet-locks-#{System.unique_integer([:positive])}"
      marker = make_ref()
      test_pid = self()

      :ok =
        :telemetry.attach(
          handler_id,
          [:storyarn, :repo, :query],
          fn _event, _measurements, %{query: query}, {pid, ref} ->
            if self() == pid and
                 (String.contains?(query, ~s(FROM "table_columns")) or
                    String.contains?(query, ~s(FROM "table_rows")) or
                    (String.contains?(query, "inherited_from_block_id") and
                       String.contains?(query, ~s(JOIN "sheets")) and
                       String.contains?(query, "FOR UPDATE"))) do
              send(pid, {ref, query})
            end
          end,
          {test_pid, marker}
        )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      assert {:ok, restored} =
               SheetBuilder.restore_snapshot(sheet, snapshot,
                 full_project_restore: true,
                 restore_action: :project_snapshot_restore
               )

      assert restored.id == sheet.id
      refute_receive {^marker, _unnecessary_lock_query}
    end

    test "rejects in-place restore for a sheet in trash without mutating it", %{sheet: sheet} do
      block =
        block_fixture(sheet, %{
          type: "text",
          value: %{"content" => "Versioned value"}
        })

      snapshot = SheetBuilder.build_snapshot(sheet)
      deleted_at = DateTime.truncate(DateTime.utc_now(), :second)

      Repo.update_all(
        from(current in Sheet, where: current.id == ^sheet.id),
        set: [name: "Current trashed sheet", deleted_at: deleted_at]
      )

      Repo.update_all(
        from(current in Block, where: current.id == ^block.id),
        set: [value: %{"content" => "Current value"}]
      )

      trashed_sheet = Repo.get!(Sheet, sheet.id)

      assert {:error, {:sheet_not_active, sheet_id}} =
               SheetBuilder.restore_snapshot(trashed_sheet, snapshot, restore_action: {:entity_version_restore, "sheet"})

      assert sheet_id == sheet.id
      assert Repo.get!(Sheet, sheet.id).name == "Current trashed sheet"
      assert Repo.get!(Sheet, sheet.id).deleted_at == deleted_at
      assert Repo.get!(Block, block.id).value == %{"content" => "Current value"}
    end

    test "restores block and sheet-name translations without replacing block IDs", %{
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

      assert {:ok, restored} =
               SheetBuilder.restore_snapshot(sheet, snapshot, restore_action: {:entity_version_restore, "sheet"})

      [restored_block] = Enum.filter(restored.blocks, &(&1.type == "text"))
      assert restored_block.id == block.id

      assert [restored_block_text] = Localization.get_texts_for_source("block", restored_block.id)
      assert restored_block_text.id == block_text.id
      assert restored_block_text.translated_text == "Un héroe"
      assert restored_block_text.status == "final"
      assert restored_block_text.reviewer_notes == "Versioned block"

      assert [%{id: restored_sheet_text_id, translated_text: "Personaje", status: "final"}] =
               Localization.get_texts_for_source("sheet", restored.id)

      assert restored_sheet_text_id == sheet_text.id
    end

    test "preserves a target locale archived after the snapshot byte-for-byte", %{
      project: project,
      sheet: sheet
    } do
      _en = source_language_fixture(project, %{locale_code: "en", name: "English"})
      _es = language_fixture(project, %{locale_code: "es", name: "Spanish"})
      fr = language_fixture(project, %{locale_code: "fr", name: "French"})

      block =
        block_fixture(sheet, %{
          type: "text",
          variable_name: "bio",
          value: %{"content" => "Historical biography"}
        })

      :ok = Localization.sync_sheet_names(project.id)

      for text <-
            Localization.get_texts_for_source("sheet", sheet.id) ++
              Localization.get_texts_for_source("block", block.id),
          text.locale_code == "fr" do
        assert {:ok, _text} =
                 Localization.update_text(text, %{
                   translated_text: "Traduction française #{text.source_type}",
                   status: "final",
                   reviewer_notes: "Preserve exactly"
                 })
      end

      snapshot = SheetBuilder.build_snapshot(sheet)
      assert length(snapshot["localization"]) == 4
      assert snapshot["localization_manifest"]["target_locales"] == ["es", "fr"]

      assert {:ok, _archived_fr} = Localization.remove_language(fr)

      {:ok, current_sheet} = Sheets.update_sheet(sheet, %{name: "Current sheet"})
      {:ok, _current_block} = Sheets.update_block_value(block, %{"content" => "Current biography"})

      Repo.update_all(
        from(text in LocalizedText,
          where:
            text.project_id == ^project.id and text.locale_code == "fr" and
              ((text.source_type == "sheet" and text.source_id == ^sheet.id) or
                 (text.source_type == "block" and text.source_id == ^block.id))
        ),
        set: [reviewer_notes: "State after language archive"],
        inc: [lock_version: 1]
      )

      archived_locale_state =
        Repo.all(
          from(text in LocalizedText,
            where:
              text.project_id == ^project.id and text.locale_code == "fr" and
                ((text.source_type == "sheet" and text.source_id == ^sheet.id) or
                   (text.source_type == "block" and text.source_id == ^block.id)),
            order_by: [asc: text.id]
          )
        )

      assert length(archived_locale_state) == 2

      assert {:ok, _restored} =
               SheetBuilder.restore_snapshot(current_sheet, snapshot, restore_action: {:entity_version_restore, "sheet"})

      assert Repo.all(
               from(text in LocalizedText,
                 where:
                   text.project_id == ^project.id and text.locale_code == "fr" and
                     ((text.source_type == "sheet" and text.source_id == ^sheet.id) or
                        (text.source_type == "block" and text.source_id == ^block.id)),
                 order_by: [asc: text.id]
               )
             ) == archived_locale_state
    end

    test "restores historical locales and reconciles a target locale added later", %{
      project: project,
      sheet: sheet
    } do
      _en = source_language_fixture(project, %{locale_code: "en", name: "English"})
      _es = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      block =
        block_fixture(sheet, %{
          type: "text",
          variable_name: "bio",
          value: %{"content" => "Historical biography"}
        })

      :ok = Localization.sync_sheet_names(project.id)
      snapshot = SheetBuilder.build_snapshot(sheet)
      assert snapshot["localization_manifest"]["target_locales"] == ["es"]

      _fr = language_fixture(project, %{locale_code: "fr", name: "French"})

      fr_text =
        "block"
        |> Localization.get_texts_for_source(block.id)
        |> Enum.find(&(&1.locale_code == "fr"))

      assert {:ok, translated_fr} =
               Localization.update_text(fr_text, %{
                 translated_text: "Biographie actuelle",
                 status: "final"
               })

      {:ok, current_sheet} = Sheets.update_sheet(sheet, %{name: "Current sheet"})
      assert {:ok, _current_block} = Sheets.update_block_value(block, %{"content" => "Current biography"})

      assert {:ok, _restored} =
               SheetBuilder.restore_snapshot(current_sheet, snapshot, restore_action: {:entity_version_restore, "sheet"})

      restored_fr = Repo.get!(LocalizedText, translated_fr.id)
      assert restored_fr.translated_text == "Biographie actuelle"
      assert restored_fr.source_text == "Historical biography"
      assert restored_fr.status != "final"
    end

    test "rejects an omitted localization row when its manifest is stale without partial writes", %{
      project: project,
      sheet: sheet
    } do
      _en = source_language_fixture(project, %{locale_code: "en", name: "English"})
      _es = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      block =
        block_fixture(sheet, %{
          type: "text",
          variable_name: "bio",
          value: %{"content" => "Historical biography"}
        })

      :ok = Localization.sync_sheet_names(project.id)
      snapshot = SheetBuilder.build_snapshot(sheet)
      assert length(snapshot["localization"]) == 2

      invalid_snapshot =
        Map.put(snapshot, "localization", tl(snapshot["localization"]))

      {:ok, current_sheet} = Sheets.update_sheet(sheet, %{name: "Current sheet"})
      {:ok, current_block} = Sheets.update_block_value(block, %{"content" => "Current biography"})
      current_localization = sheet_localization_state(sheet.id, block.id)

      assert {:error, {:localization_manifest_mismatch, _provided, _expected}} =
               SheetBuilder.restore_snapshot(current_sheet, invalid_snapshot,
                 restore_action: {:entity_version_restore, "sheet"}
               )

      assert Repo.get!(Sheet, sheet.id).name == "Current sheet"
      assert Repo.get!(Block, block.id).value == current_block.value
      assert sheet_localization_state(sheet.id, block.id) == current_localization
    end

    test "rejects a complete target locale omission with a recomputed manifest without partial writes", %{
      project: project,
      sheet: sheet
    } do
      _en = source_language_fixture(project, %{locale_code: "en", name: "English"})
      _es = language_fixture(project, %{locale_code: "es", name: "Spanish"})
      _fr = language_fixture(project, %{locale_code: "fr", name: "French"})

      block =
        block_fixture(sheet, %{
          type: "rich_text",
          variable_name: "bio",
          value: %{"content" => "<p>Historical biography</p>"}
        })

      :ok = Localization.sync_sheet_names(project.id)
      snapshot = SheetBuilder.build_snapshot(sheet)
      assert length(snapshot["localization"]) == 4

      remaining_rows =
        Enum.reject(snapshot["localization"], &(&1["locale_code"] == "fr"))

      invalid_snapshot = put_localization_with_manifest(snapshot, remaining_rows)

      {:ok, current_sheet} = Sheets.update_sheet(sheet, %{name: "Current sheet"})

      {:ok, current_block} =
        Sheets.update_block_value(block, %{"content" => "<p>Current biography</p>"})

      current_localization = sheet_localization_state(sheet.id, block.id)

      assert {:error, {:incomplete_sheet_localization_snapshot, %{missing: missing, unexpected: []}}} =
               SheetBuilder.restore_snapshot(current_sheet, invalid_snapshot,
                 restore_action: {:entity_version_restore, "sheet"}
               )

      assert length(missing) == 2
      assert Enum.all?(missing, fn {_source, locale} -> locale == "fr" end)
      assert Repo.get!(Sheet, sheet.id).name == "Current sheet"
      assert Repo.get!(Block, block.id).value == current_block.value
      assert sheet_localization_state(sheet.id, block.id) == current_localization
    end

    test "rejects corrupt localization schema and semantics with recomputed manifests without partial writes", %{
      project: project,
      sheet: sheet
    } do
      _en = source_language_fixture(project, %{locale_code: "en", name: "English"})
      _es = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      block =
        block_fixture(sheet, %{
          type: "text",
          variable_name: "bio",
          value: %{"content" => "Historical biography {name}"}
        })

      :ok = Localization.sync_sheet_names(project.id)
      snapshot = SheetBuilder.build_snapshot(sheet)
      row = Enum.find(snapshot["localization"], &(&1["source_type"] == "block"))
      remaining_rows = List.delete(snapshot["localization"], row)

      {:ok, current_sheet} = Sheets.update_sheet(sheet, %{name: "Current sheet"})
      {:ok, current_block} = Sheets.update_block_value(block, %{"content" => "Current biography"})
      current_localization = sheet_localization_state(sheet.id, block.id)

      corruptions = [
        &Map.delete(&1, "reviewer_notes"),
        &Map.put(&1, "source_text", "Forged source"),
        &Map.put(&1, "source_text_hash", String.duplicate("0", 64)),
        &Map.update!(&1, "word_count", fn count -> count + 1 end),
        &Map.put(&1, "status", "final"),
        fn entry ->
          entry
          |> Map.put("archived_at", DateTime.truncate(DateTime.utc_now(), :second))
          |> Map.put("archive_reason", "version_replaced")
        end,
        fn entry ->
          entry
          |> Map.put("translated_text", "Biografía histórica")
          |> Map.put("translated_source_hash", entry["source_text_hash"])
          |> Map.put("status", "final")
        end
      ]

      for corrupt <- corruptions do
        rows = [corrupt.(row) | remaining_rows]
        invalid_snapshot = put_localization_with_manifest(snapshot, rows)

        assert {:error, _reason} =
                 SheetBuilder.restore_snapshot(current_sheet, invalid_snapshot,
                   restore_action: {:entity_version_restore, "sheet"}
                 )

        assert Repo.get!(Sheet, sheet.id).name == "Current sheet"
        assert Repo.get!(Block, block.id).value == current_block.value
        assert sheet_localization_state(sheet.id, block.id) == current_localization
      end
    end

    test "keeps historical IDs, re-inserts a hard-deleted block, and returns identity maps", %{
      sheet: sheet
    } do
      column_group_id = Ecto.UUID.generate()

      block =
        block_fixture(sheet, %{
          type: "text",
          position: 4,
          config: %{"label" => "Biography"},
          value: %{"content" => "Historical biography"},
          column_group_id: column_group_id,
          column_index: 2
        })

      {:ok, historical_sheet} =
        Sheets.update_sheet(sheet, %{
          description: "Historical description",
          hidden_inherited_block_ids: [block.id]
        })

      snapshot = SheetBuilder.build_snapshot(historical_sheet)
      assert [block_snapshot] = snapshot["blocks"]
      assert block_snapshot["column_group_id"] == column_group_id
      assert block_snapshot["column_index"] == 2

      Repo.delete!(block)

      {:ok, current_sheet} =
        Sheets.update_sheet(historical_sheet, %{
          description: "Current description",
          hidden_inherited_block_ids: []
        })

      assert {:ok, restored, id_maps} =
               SheetBuilder.restore_snapshot(current_sheet, snapshot,
                 restore_action: {:entity_version_restore, "sheet"},
                 return_id_maps: true
               )

      assert restored.description == "Historical description"
      assert restored.hidden_inherited_block_ids == [block.id]
      assert id_maps.sheet == %{sheet.id => sheet.id}
      assert id_maps.block == %{block.id => block.id}

      restored_block = Repo.get!(Block, block.id)
      assert restored_block.sheet_id == sheet.id
      assert restored_block.column_group_id == column_group_id
      assert restored_block.column_index == 2
      assert restored_block.value == %{"content" => "Historical biography"}
      assert is_nil(restored_block.deleted_at)
    end

    test "fails closed before writes when a hard-deleted children source lost its instance identities", %{
      project: project,
      sheet: sheet
    } do
      child = child_sheet_fixture(project, sheet)
      source = inheritable_block_fixture(sheet, label: "Historical inherited biography")
      instance = inherited_instance!(child.id, source.id)
      snapshot = SheetBuilder.build_snapshot(sheet)

      {:ok, deleted_source} = Sheets.delete_block(source)
      deleted_instance = Repo.get!(Block, instance.id)
      assert deleted_instance.deleted_at

      assert {:ok, _purged_source} = Sheets.permanently_delete_block(deleted_source)
      assert is_nil(Repo.get!(Block, instance.id).inherited_from_block_id)

      {:ok, current_sheet} =
        Sheets.update_sheet(sheet, %{
          name: "Current sheet after purge",
          description: "Must survive failed restore"
        })

      orphaned_instance = Repo.get!(Block, instance.id)

      assert {:error, {:property_inheritance_restore_conflict, source_id, :missing_historical_children_source, []}} =
               SheetBuilder.restore_snapshot(current_sheet, snapshot, restore_action: {:entity_version_restore, "sheet"})

      assert source_id == source.id
      assert is_nil(Repo.get(Block, source.id))

      unchanged_sheet = Repo.get!(Sheet, sheet.id)
      assert unchanged_sheet.name == "Current sheet after purge"
      assert unchanged_sheet.description == "Must survive failed restore"

      unchanged_instance = Repo.get!(Block, instance.id)
      assert unchanged_instance.inherited_from_block_id == orphaned_instance.inherited_from_block_id
      assert unchanged_instance.deleted_at == orphaned_instance.deleted_at
      assert unchanged_instance.detached == orphaned_instance.detached
      assert unchanged_instance.config == orphaned_instance.config
      assert unchanged_instance.value == orphaned_instance.value
    end

    test "rebuilds flow, pin, and zone variable references after re-inserting a hard-deleted block", %{
      project: project,
      sheet: sheet
    } do
      block =
        block_fixture(sheet, %{
          type: "number",
          config: %{"label" => "Health", "placeholder" => "0"}
        })

      snapshot = SheetBuilder.build_snapshot(sheet)
      condition = variable_condition(sheet.shortcut, block.variable_name)
      assignment = variable_assignment(sheet.shortcut, block.variable_name)
      flow = flow_fixture(project)

      node =
        node_fixture(flow, %{
          type: "instruction",
          data: %{"assignments" => [assignment]}
        })

      scene = scene_fixture(project)
      pin = pin_fixture(scene, %{"condition" => condition})

      zone =
        zone_fixture(scene, %{
          "action_type" => "action",
          "action_data" => %{"assignments" => [assignment]}
        })

      assert :ok = VariableReferenceTracker.update_references(node)

      expected_sources =
        MapSet.new([
          {"flow_node", node.id},
          {"scene_pin", pin.id},
          {"scene_zone", zone.id}
        ])

      assert variable_reference_sources(block.id) == expected_sources

      Repo.delete!(block)
      assert variable_reference_sources(block.id) == MapSet.new()

      assert {:ok, _restored} =
               SheetBuilder.restore_snapshot(sheet, snapshot, restore_action: {:entity_version_restore, "sheet"})

      assert Repo.get!(Block, block.id).id == block.id
      assert variable_reference_sources(block.id) == expected_sources
    end

    test "rolls back every sheet write when reference reconciliation fails", %{
      sheet: sheet
    } do
      block = block_fixture(sheet, %{value: %{"content" => "Historical value"}})
      snapshot = SheetBuilder.build_snapshot(sheet)

      {:ok, current_sheet} =
        Sheets.update_sheet(sheet, %{
          name: "Current sheet",
          description: "Must survive a failed reference rebuild"
        })

      Repo.update_all(
        from(current in Block, where: current.id == ^block.id),
        set: [value: %{"content" => "Current value"}]
      )

      update_references = fn restored_block, _opts ->
        {:error, {:reference_index_unavailable, restored_block.id}}
      end

      assert {:error, {:block_reference_reconcile_failed, block_id, {:reference_index_unavailable, block_id}}} =
               SheetBuilder.restore_snapshot(current_sheet, snapshot,
                 restore_action: {:entity_version_restore, "sheet"},
                 __update_block_references_fun: update_references
               )

      assert block_id == block.id
      assert Repo.get!(Sheet, sheet.id).name == "Current sheet"
      assert Repo.get!(Sheet, sheet.id).description == "Must survive a failed reference rebuild"
      assert Repo.get!(Block, block.id).value == %{"content" => "Current value"}
    end

    test "does not mutate blocks already in trash, their nested rows, or localization", %{
      project: project,
      sheet: sheet
    } do
      _en = source_language_fixture(project, %{locale_code: "en", name: "English"})
      _es = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      _baseline = block_fixture(sheet, %{value: %{"content" => "Baseline"}})
      snapshot = SheetBuilder.build_snapshot(sheet)

      trash_text =
        block_fixture(sheet, %{
          type: "text",
          value: %{"content" => "Discarded biography"}
        })

      assert [localized_text] = Localization.get_texts_for_source("block", trash_text.id)

      assert {:ok, _localized_text} =
               Localization.update_text(localized_text, %{
                 translated_text: "Biografía descartada",
                 status: "final"
               })

      {:ok, deleted_text} = Sheets.delete_block(trash_text)

      archived_text =
        Repo.one!(
          from(text in LocalizedText,
            where: text.source_type == "block" and text.source_id == ^trash_text.id
          )
        )

      trash_table = table_block_fixture(sheet)
      trash_column = table_column_fixture(trash_table, %{name: "Trash score", type: "number"})
      trash_row = table_row_fixture(trash_table, %{name: "Trash row"})
      {:ok, deleted_table} = Sheets.delete_block(trash_table)

      assert {:ok, _restored} =
               SheetBuilder.restore_snapshot(sheet, snapshot, restore_action: {:entity_version_restore, "sheet"})

      restored_trash_text = Repo.get!(Block, trash_text.id)
      restored_trash_table = Repo.get!(Block, trash_table.id)
      restored_archived_text = Repo.get!(LocalizedText, archived_text.id)

      assert restored_trash_text.deleted_at == deleted_text.deleted_at
      assert restored_trash_table.deleted_at == deleted_table.deleted_at
      assert Repo.get!(TableColumn, trash_column.id).block_id == trash_table.id
      assert Repo.get!(TableRow, trash_row.id).block_id == trash_table.id
      assert restored_archived_text.archived_at == archived_text.archived_at
      assert restored_archived_text.archive_reason == archived_text.archive_reason
      assert restored_archived_text.translated_text == "Biografía descartada"
      assert restored_archived_text.lock_version == archived_text.lock_version
    end

    test "soft-deletes active blocks created after the snapshot without changing their IDs or children", %{
      sheet: sheet
    } do
      _baseline = block_fixture(sheet)
      snapshot = SheetBuilder.build_snapshot(sheet)

      post_snapshot_table = table_block_fixture(sheet)
      post_snapshot_column = table_column_fixture(post_snapshot_table, %{name: "Later"})
      post_snapshot_row = table_row_fixture(post_snapshot_table, %{name: "Later row"})

      assert {:ok, _restored} =
               SheetBuilder.restore_snapshot(sheet, snapshot, restore_action: {:entity_version_restore, "sheet"})

      trashed_table = Repo.get!(Block, post_snapshot_table.id)
      assert trashed_table.id == post_snapshot_table.id
      assert trashed_table.deleted_at
      assert Repo.get!(TableColumn, post_snapshot_column.id).block_id == post_snapshot_table.id
      assert Repo.get!(TableRow, post_snapshot_row.id).block_id == post_snapshot_table.id
    end

    test "preserves external inherited instances when restoring a definition", %{
      project: project,
      sheet: sheet
    } do
      child_sheet = child_sheet_fixture(project, sheet)

      source_block =
        inheritable_block_fixture(sheet,
          label: "Inherited biography",
          type: "text"
        )

      inherited_instance =
        Repo.one!(
          from(block in Block,
            where:
              block.sheet_id == ^child_sheet.id and
                block.inherited_from_block_id == ^source_block.id
          )
        )

      snapshot = SheetBuilder.build_snapshot(sheet)

      source_block
      |> Ecto.Changeset.change(
        config: %{"label" => "Changed definition"},
        value: %{"content" => "Changed"}
      )
      |> Repo.update!()

      assert {:ok, _restored} =
               SheetBuilder.restore_snapshot(sheet, snapshot, restore_action: {:entity_version_restore, "sheet"})

      assert Repo.get!(Block, source_block.id).id == source_block.id

      restored_instance = Repo.get!(Block, inherited_instance.id)
      assert restored_instance.sheet_id == child_sheet.id
      assert restored_instance.inherited_from_block_id == source_block.id
      assert is_nil(restored_instance.deleted_at)

      child_snapshot = SheetBuilder.build_snapshot(child_sheet)

      restored_instance
      |> Ecto.Changeset.change(config: %{"label" => "Locally changed inheritance"})
      |> Repo.update!()

      assert {:ok, _restored_child} =
               SheetBuilder.restore_snapshot(child_sheet, child_snapshot,
                 restore_action: {:entity_version_restore, "sheet"}
               )

      restored_instance = Repo.get!(Block, inherited_instance.id)
      assert restored_instance.inherited_from_block_id == source_block.id
      assert restored_instance.config == %{"label" => "Inherited biography", "placeholder" => ""}
    end

    test "soft-deletes an extra children definition and only its active instances", %{
      project: project,
      sheet: sheet
    } do
      _baseline = block_fixture(sheet)
      snapshot = SheetBuilder.build_snapshot(sheet)
      active_child = child_sheet_fixture(project, sheet)
      prior_trash_child = child_sheet_fixture(project, sheet)
      detached_child = child_sheet_fixture(project, sheet)

      source =
        inheritable_block_fixture(sheet,
          label: "Post-snapshot table",
          type: "table"
        )

      active_instance = inherited_instance!(active_child.id, source.id)
      prior_trash_instance = inherited_instance!(prior_trash_child.id, source.id)
      detached_instance = inherited_instance!(detached_child.id, source.id)
      {:ok, prior_trash_instance} = Sheets.delete_block(prior_trash_instance)
      {:ok, detached_instance} = PropertyInheritance.detach_block(detached_instance)

      detached_instance =
        detached_instance
        |> Ecto.Changeset.change(config: %{"label" => "Detached local copy"})
        |> Repo.update!()

      nested_ids =
        Enum.flat_map(
          [source.id, active_instance.id, prior_trash_instance.id, detached_instance.id],
          fn block_id ->
            column_ids =
              from(column in TableColumn,
                where: column.block_id == ^block_id,
                select: column.id
              )
              |> Repo.all()
              |> Enum.map(&{TableColumn, &1})

            row_ids =
              from(row in TableRow,
                where: row.block_id == ^block_id,
                select: row.id
              )
              |> Repo.all()
              |> Enum.map(&{TableRow, &1})

            column_ids ++ row_ids
          end
        )

      assert {:ok, _restored} =
               SheetBuilder.restore_snapshot(sheet, snapshot, restore_action: {:entity_version_restore, "sheet"})

      assert Repo.get!(Block, source.id).deleted_at
      assert Repo.get!(Block, active_instance.id).deleted_at

      restored_prior_trash = Repo.get!(Block, prior_trash_instance.id)
      assert restored_prior_trash.deleted_at == prior_trash_instance.deleted_at
      assert restored_prior_trash.inherited_from_block_id == source.id

      restored_detached = Repo.get!(Block, detached_instance.id)
      assert is_nil(restored_detached.deleted_at)
      assert restored_detached.detached
      assert restored_detached.config == %{"label" => "Detached local copy"}

      Enum.each(nested_ids, fn {schema, nested_id} ->
        assert Repo.get(schema, nested_id)
      end)
    end

    test "fails closed when restoring self to children without historical instance identities", %{
      project: project,
      sheet: sheet
    } do
      source = inheritable_block_fixture(sheet, label: "Historical children scope")
      snapshot = SheetBuilder.build_snapshot(sheet)
      assert {:ok, current_source} = Sheets.update_block(source, %{scope: "self"})
      child = child_sheet_fixture(project, sheet)
      {:ok, current_sheet} = Sheets.update_sheet(sheet, %{name: "Must remain"})

      assert {:error, {:property_inheritance_restore_conflict, source_id, {:scope_change, "self", "children"}, []}} =
               SheetBuilder.restore_snapshot(current_sheet, snapshot, restore_action: {:entity_version_restore, "sheet"})

      assert source_id == source.id
      assert Repo.get!(Sheet, sheet.id).name == "Must remain"
      assert Repo.get!(Block, source.id).scope == current_source.scope

      refute Repo.exists?(
               from(block in Block,
                 where:
                   block.sheet_id == ^child.id and
                     block.inherited_from_block_id == ^source.id and
                     is_nil(block.deleted_at)
               )
             )
    end

    test "archives translations for an extra children definition without changing prior trash", %{
      project: project,
      sheet: sheet
    } do
      _en = source_language_fixture(project, %{locale_code: "en", name: "English"})
      _es = language_fixture(project, %{locale_code: "es", name: "Spanish"})
      _baseline = block_fixture(sheet)
      snapshot = SheetBuilder.build_snapshot(sheet)
      active_child = child_sheet_fixture(project, sheet)
      prior_trash_child = child_sheet_fixture(project, sheet)
      source = inheritable_block_fixture(sheet, label: "Post-snapshot biography")
      active_instance = inherited_instance!(active_child.id, source.id)
      prior_trash_instance = inherited_instance!(prior_trash_child.id, source.id)

      {:ok, source} =
        Sheets.update_block_value(source, %{"content" => "Source biography"})

      {:ok, active_instance} =
        Sheets.update_block_value(active_instance, %{"content" => "Active biography"})

      {:ok, prior_trash_instance} =
        Sheets.update_block_value(prior_trash_instance, %{"content" => "Prior biography"})

      source_text = translated_block_text!(source.id, "Biografía fuente")
      active_text = translated_block_text!(active_instance.id, "Biografía activa")
      prior_text = translated_block_text!(prior_trash_instance.id, "Biografía previa")

      {:ok, _prior_trash_instance} = Sheets.delete_block(prior_trash_instance)
      prior_archived = Repo.get!(LocalizedText, prior_text.id)

      assert {:ok, _restored} =
               SheetBuilder.restore_snapshot(sheet, snapshot, restore_action: {:entity_version_restore, "sheet"})

      assert Repo.get!(Block, source.id).deleted_at
      assert Repo.get!(Block, active_instance.id).deleted_at

      restored_source_text = Repo.get!(LocalizedText, source_text.id)
      restored_active_text = Repo.get!(LocalizedText, active_text.id)
      restored_prior_text = Repo.get!(LocalizedText, prior_text.id)

      assert restored_source_text.translated_text == "Biografía fuente"
      assert restored_source_text.archive_reason == "source_deleted"
      assert restored_source_text.archived_at
      assert restored_active_text.translated_text == "Biografía activa"
      assert restored_active_text.archive_reason == "source_deleted"
      assert restored_active_text.archived_at
      assert restored_prior_text.translated_text == "Biografía previa"
      assert restored_prior_text.archived_at == prior_archived.archived_at
      assert restored_prior_text.archive_reason == prior_archived.archive_reason
      assert restored_prior_text.lock_version == prior_archived.lock_version
    end

    test "rejects a scope transition when external instances exist in trash", %{
      project: project,
      sheet: sheet
    } do
      child = child_sheet_fixture(project, sheet)
      source = inheritable_block_fixture(sheet, label: "Scoped definition")
      instance = inherited_instance!(child.id, source.id)
      snapshot = SheetBuilder.build_snapshot(sheet)

      {:ok, current_source} = Sheets.update_block(source, %{scope: "self"})
      trashed_instance = Repo.get!(Block, instance.id)
      {:ok, modified_sheet} = Sheets.update_sheet(sheet, %{name: "Must survive"})

      assert {:error,
              {:property_inheritance_restore_conflict, source_id, {:scope_change, "self", "children"}, instance_ids}} =
               SheetBuilder.restore_snapshot(modified_sheet, snapshot, restore_action: {:entity_version_restore, "sheet"})

      assert source_id == source.id
      assert instance_ids == [instance.id]
      assert Repo.get!(Sheet, sheet.id).name == "Must survive"
      assert Repo.get!(Block, source.id).scope == current_source.scope
      assert Repo.get!(Block, instance.id).deleted_at == trashed_instance.deleted_at
    end

    test "syncs only active non-detached instances for children definitions", %{
      project: project,
      sheet: sheet
    } do
      active_child = child_sheet_fixture(project, sheet)
      detached_child = child_sheet_fixture(project, sheet)
      trash_child = child_sheet_fixture(project, sheet)
      source = inheritable_block_fixture(sheet, label: "Historical label")
      snapshot = SheetBuilder.build_snapshot(sheet)

      active_instance = inherited_instance!(active_child.id, source.id)
      detached_instance = inherited_instance!(detached_child.id, source.id)
      trash_instance = inherited_instance!(trash_child.id, source.id)

      active_instance
      |> Ecto.Changeset.change(config: %{"label" => "Active drift"})
      |> Repo.update!()

      {:ok, detached_instance} =
        PropertyInheritance.detach_block(detached_instance)

      detached_instance
      |> Ecto.Changeset.change(config: %{"label" => "Detached custom"})
      |> Repo.update!()

      trash_instance =
        trash_instance
        |> Ecto.Changeset.change(config: %{"label" => "Trash custom"})
        |> Repo.update!()

      {:ok, trash_instance} = Sheets.delete_block(trash_instance)

      source
      |> Ecto.Changeset.change(config: %{"label" => "Current definition"})
      |> Repo.update!()

      assert {:ok, _restored} =
               SheetBuilder.restore_snapshot(sheet, snapshot, restore_action: {:entity_version_restore, "sheet"})

      assert Repo.get!(Block, source.id).config["label"] == "Historical label"
      assert Repo.get!(Block, active_instance.id).config["label"] == "Historical label"

      restored_detached = Repo.get!(Block, detached_instance.id)
      assert restored_detached.config["label"] == "Detached custom"
      assert restored_detached.detached
      assert is_nil(restored_detached.deleted_at)

      restored_trash = Repo.get!(Block, trash_instance.id)
      assert restored_trash.config["label"] == "Trash custom"
      assert restored_trash.deleted_at == trash_instance.deleted_at
    end

    test "reconciles localization for active inherited instances changed by definition sync", %{
      project: project,
      sheet: sheet
    } do
      _en = source_language_fixture(project, %{locale_code: "en", name: "English"})
      _es = language_fixture(project, %{locale_code: "es", name: "Spanish"})
      child = child_sheet_fixture(project, sheet)
      source = inheritable_block_fixture(sheet, label: "Inherited biography")
      instance = inherited_instance!(child.id, source.id)

      assert {:ok, instance} =
               Sheets.update_block_value(instance, %{"content" => "Child biography"})

      translated = translated_block_text!(instance.id, "Biografía hija")
      snapshot = SheetBuilder.build_snapshot(sheet)

      assert {:ok, _constant_source} = Sheets.update_block(source, %{is_constant: true})
      assert Repo.get!(Block, instance.id).is_constant
      assert Repo.get!(LocalizedText, translated.id).archived_at

      assert {:ok, _restored} =
               SheetBuilder.restore_snapshot(sheet, snapshot, restore_action: {:entity_version_restore, "sheet"})

      refute Repo.get!(Block, instance.id).is_constant
      restored_text = Repo.get!(LocalizedText, translated.id)
      assert is_nil(restored_text.archived_at)
      assert is_nil(restored_text.archive_reason)
      assert restored_text.translated_text == "Biografía hija"
      assert restored_text.source_text == "Child biography"
    end

    test "restores only the historical cascade of a soft-deleted children definition", %{
      project: project,
      sheet: sheet
    } do
      _en = source_language_fixture(project, %{locale_code: "en", name: "English"})
      _es = language_fixture(project, %{locale_code: "es", name: "Spanish"})
      cascade_child = child_sheet_fixture(project, sheet)
      prior_trash_child = child_sheet_fixture(project, sheet)
      later_trash_child = child_sheet_fixture(project, sheet)
      detached_child = child_sheet_fixture(project, sheet)
      target_sheet = sheet_fixture(project)

      source =
        inheritable_block_fixture(sheet,
          label: "Historical cascade",
          type: "rich_text"
        )

      {:ok, source} =
        Sheets.update_block_value(source, %{"content" => "<p>Historical source</p>"})

      snapshot = SheetBuilder.build_snapshot(sheet)

      cascade_instance = inherited_instance!(cascade_child.id, source.id)
      prior_trash_instance = inherited_instance!(prior_trash_child.id, source.id)
      later_trash_instance = inherited_instance!(later_trash_child.id, source.id)
      detached_instance = inherited_instance!(detached_child.id, source.id)

      mention_html =
        ~s(<p>Meet <span class="mention" data-type="sheet" data-id="#{target_sheet.id}">Target</span></p>)

      {:ok, cascade_instance} =
        Sheets.update_block_value(cascade_instance, %{"content" => mention_html})

      cascade_text = translated_block_text!(cascade_instance.id, "Conoce al objetivo")
      assert block_reference_exists?(cascade_instance.id, "sheet", target_sheet.id)

      {:ok, detached_instance} = PropertyInheritance.detach_block(detached_instance)
      {:ok, prior_trash_instance} = Sheets.delete_block(prior_trash_instance)
      {:ok, deleted_source} = Sheets.delete_block(source)

      historical_deleted_at =
        DateTime.add(deleted_source.deleted_at, -3_600, :second)

      prior_deleted_at = DateTime.add(historical_deleted_at, -10, :second)
      later_deleted_at = DateTime.add(historical_deleted_at, 10, :second)

      Repo.update_all(
        from(block in Block,
          where:
            block.id in ^[
              source.id,
              cascade_instance.id,
              detached_instance.id
            ]
        ),
        set: [deleted_at: historical_deleted_at]
      )

      Repo.update_all(
        from(block in Block, where: block.id == ^prior_trash_instance.id),
        set: [deleted_at: prior_deleted_at]
      )

      Repo.update_all(
        from(block in Block, where: block.id == ^later_trash_instance.id),
        set: [deleted_at: later_deleted_at]
      )

      refute block_reference_exists?(cascade_instance.id, "sheet", target_sheet.id)
      assert Repo.get!(LocalizedText, cascade_text.id).archived_at

      assert {:ok, _restored} =
               SheetBuilder.restore_snapshot(sheet, snapshot, restore_action: {:entity_version_restore, "sheet"})

      assert is_nil(Repo.get!(Block, source.id).deleted_at)
      assert is_nil(Repo.get!(Block, cascade_instance.id).deleted_at)
      assert Repo.get!(Block, prior_trash_instance.id).deleted_at == prior_deleted_at
      assert Repo.get!(Block, later_trash_instance.id).deleted_at == later_deleted_at

      restored_detached = Repo.get!(Block, detached_instance.id)
      assert restored_detached.deleted_at == historical_deleted_at
      assert restored_detached.detached

      assert block_reference_exists?(cascade_instance.id, "sheet", target_sheet.id)

      restored_cascade_text = Repo.get!(LocalizedText, cascade_text.id)
      assert is_nil(restored_cascade_text.archived_at)
      assert is_nil(restored_cascade_text.archive_reason)
      assert restored_cascade_text.translated_text == "Conoce al objetivo"
    end

    test "rejects a type change while a children definition has active instances", %{
      project: project,
      sheet: sheet
    } do
      child = child_sheet_fixture(project, sheet)
      source = inheritable_block_fixture(sheet, label: "Typed definition")
      instance = inherited_instance!(child.id, source.id)
      snapshot = SheetBuilder.build_snapshot(sheet)

      source
      |> Ecto.Changeset.change(
        type: "number",
        config: Block.default_config("number"),
        value: Block.default_value("number")
      )
      |> Repo.update!()

      assert {:error, {:property_inheritance_restore_conflict, source_id, {:type_change, "number", "text"}, instance_ids}} =
               SheetBuilder.restore_snapshot(sheet, snapshot, restore_action: {:entity_version_restore, "sheet"})

      assert source_id == source.id
      assert instance_ids == [instance.id]
      assert Repo.get!(Block, source.id).type == "number"
      assert Repo.get!(Block, instance.id).type == "text"
    end

    test "rejects table column or row changes while active instances exist", %{
      project: project,
      sheet: sheet
    } do
      child = child_sheet_fixture(project, sheet)

      {:ok, source} =
        Sheets.create_block(sheet, %{
          type: "table",
          scope: "children",
          config: %{"label" => "Inherited table", "collapsed" => false}
        })

      instance = inherited_instance!(child.id, source.id)
      snapshot = SheetBuilder.build_snapshot(sheet)
      {:ok, extra_column} = Sheets.create_table_column(source, %{name: "Later", type: "text"})

      assert {:error, {:property_inheritance_restore_conflict, source_id, :table_structure_change, instance_ids}} =
               SheetBuilder.restore_snapshot(sheet, snapshot, restore_action: {:entity_version_restore, "sheet"})

      assert source_id == source.id
      assert instance_ids == [instance.id]
      assert Repo.get!(TableColumn, extra_column.id).block_id == source.id

      assert Enum.any?(
               Sheets.list_table_columns(instance.id),
               &(&1.slug == extra_column.slug)
             )
    end

    test "reconciles avatars, table children, and gallery images by ID despite duplicate block positions", %{
      project: project,
      sheet: sheet,
      user: user
    } do
      avatar_asset = uploaded_image_asset(project, user, "restore-avatar.png", "restore-avatar")
      extra_avatar_asset = uploaded_image_asset(project, user, "extra-avatar.png", "extra-avatar")
      gallery_asset = uploaded_image_asset(project, user, "restore-gallery.png", "restore-gallery")
      extra_gallery_asset = uploaded_image_asset(project, user, "extra-gallery.png", "extra-gallery")

      {:ok, avatar} = Sheets.add_avatar(sheet, avatar_asset.id, %{name: "Hero"})

      table_block = table_block_fixture(sheet)
      table_column = table_column_fixture(table_block, %{name: "Score", type: "number"})
      table_row = table_row_fixture(table_block, %{name: "Final score"})
      {:ok, table_row} = Sheets.update_table_cell(table_row, table_column.slug, "99")

      gallery_block =
        block_fixture(sheet, %{
          type: "gallery",
          config: %{"label" => "References"},
          value: %{}
        })

      {:ok, gallery_image} = Sheets.add_gallery_image(gallery_block, gallery_asset.id)
      {:ok, gallery_image} = Sheets.update_gallery_image(gallery_image, %{label: "Historical image"})

      Repo.update!(Ecto.Changeset.change(table_block, position: 7))
      Repo.update!(Ecto.Changeset.change(gallery_block, position: 7))

      expected_column_ids = table_block.id |> Sheets.list_table_columns() |> Enum.map(& &1.id) |> Enum.sort()
      expected_row_ids = table_block.id |> Sheets.list_table_rows() |> Enum.map(& &1.id) |> Enum.sort()
      snapshot = SheetBuilder.build_snapshot(sheet)

      table_snapshot = Enum.find(snapshot["blocks"], &(&1["original_id"] == table_block.id))
      gallery_snapshot = Enum.find(snapshot["blocks"], &(&1["original_id"] == gallery_block.id))

      assert Enum.sort(Enum.map(table_snapshot["table_data"]["columns"], & &1["original_id"])) ==
               expected_column_ids

      assert Enum.sort(Enum.map(table_snapshot["table_data"]["rows"], & &1["original_id"])) ==
               expected_row_ids

      assert [gallery_image_snapshot] = gallery_snapshot["gallery_images"]
      assert gallery_image_snapshot["original_id"] == gallery_image.id

      assert {:ok, _deleted_column} = Sheets.delete_table_column(table_column)
      assert {:ok, _deleted_row} = Sheets.delete_table_row(table_row)
      assert {:ok, _gallery_image} = Sheets.update_gallery_image(gallery_image, %{label: "Changed"})
      assert {:ok, _avatar} = Sheets.update_avatar(avatar, %{notes: "Changed"})

      _extra_column = table_column_fixture(table_block, %{name: "Extra column"})
      _extra_row = table_row_fixture(table_block, %{name: "Extra row"})
      {:ok, extra_gallery} = Sheets.add_gallery_image(gallery_block, extra_gallery_asset.id)
      {:ok, extra_avatar} = Sheets.add_avatar(sheet, extra_avatar_asset.id, %{name: "Extra"})

      assert {:ok, _restored} =
               SheetBuilder.restore_snapshot(sheet, snapshot, restore_action: {:entity_version_restore, "sheet"})

      assert Enum.sort(Enum.map(Sheets.list_table_columns(table_block.id), & &1.id)) ==
               expected_column_ids

      assert Enum.sort(Enum.map(Sheets.list_table_rows(table_block.id), & &1.id)) ==
               expected_row_ids

      restored_column = Repo.get!(TableColumn, table_column.id)
      restored_row = Repo.get!(TableRow, table_row.id)
      assert restored_column.name == "Score"
      assert restored_row.cells[restored_column.slug] == "99"

      assert [%BlockGalleryImage{id: gallery_image_id, label: "Historical image"}] =
               Sheets.list_gallery_images(gallery_block.id)

      assert gallery_image_id == gallery_image.id
      assert Repo.get(BlockGalleryImage, extra_gallery.id) == nil

      assert [%SheetAvatar{id: avatar_id, notes: nil}] = Sheets.list_avatars(sheet.id)
      assert avatar_id == avatar.id
      assert Repo.get(SheetAvatar, extra_avatar.id) == nil
      assert Repo.get!(Block, table_block.id).position == 7
      assert Repo.get!(Block, gallery_block.id).position == 7
    end

    test "rolls back instead of deleting an avatar referenced by a flow node", %{
      project: project,
      sheet: sheet,
      user: user
    } do
      kept_asset = uploaded_image_asset(project, user, "kept-avatar.png", "kept-avatar")
      referenced_asset = uploaded_image_asset(project, user, "referenced-avatar.png", "referenced-avatar")
      {:ok, _kept_avatar} = Sheets.add_avatar(sheet, kept_asset.id, %{name: "Kept"})
      snapshot = SheetBuilder.build_snapshot(sheet)

      {:ok, referenced_avatar} =
        Sheets.add_avatar(sheet, referenced_asset.id, %{name: "Referenced"})

      flow = flow_fixture(project)

      node =
        node_fixture(flow, %{
          data: %{
            "speaker_sheet_id" => sheet.id,
            "avatar_id" => referenced_avatar.id,
            "text" => "Hello"
          }
        })

      {:ok, current_sheet} = Sheets.update_sheet(sheet, %{name: "Current state"})

      assert {:error, {:avatar_restore_conflict, avatar_id, {:referenced_by_flow_nodes, 1}}} =
               SheetBuilder.restore_snapshot(current_sheet, snapshot, restore_action: {:entity_version_restore, "sheet"})

      assert avatar_id == referenced_avatar.id
      assert Repo.get!(SheetAvatar, referenced_avatar.id).sheet_id == sheet.id
      assert Repo.get!(FlowNode, node.id).data["avatar_id"] == referenced_avatar.id
      assert Repo.get!(Sheet, sheet.id).name == "Current state"

      refute Repo.exists?(
               from(ref in EntityTrashRef,
                 where: ref.target_sheet_avatar_id == ^referenced_avatar.id
               )
             )
    end

    test "preserves pending avatar trash references so they remain restorable", %{
      project: project,
      sheet: sheet,
      user: user
    } do
      kept_asset = uploaded_image_asset(project, user, "pending-kept.png", "pending-kept")
      pending_asset = uploaded_image_asset(project, user, "pending-avatar.png", "pending-avatar")
      {:ok, _kept_avatar} = Sheets.add_avatar(sheet, kept_asset.id, %{name: "Kept"})
      snapshot = SheetBuilder.build_snapshot(sheet)
      {:ok, pending_avatar} = Sheets.add_avatar(sheet, pending_asset.id, %{name: "Pending"})
      flow = flow_fixture(project)

      node =
        node_fixture(flow, %{
          data: %{
            "speaker_sheet_id" => sheet.id,
            "avatar_id" => pending_avatar.id,
            "text" => "Hello"
          }
        })

      assert {:ok, 1} =
               Flows.sweep_trash_refs_jsonb(
                 FlowNode,
                 "flow_node",
                 :data,
                 "avatar_id",
                 :sheet_avatar,
                 pending_avatar.id
               )

      assert is_nil(Repo.get!(FlowNode, node.id).data["avatar_id"])

      assert {:error, {:avatar_restore_conflict, avatar_id, {:pending_flow_trash_references, 1}}} =
               SheetBuilder.restore_snapshot(sheet, snapshot, restore_action: {:entity_version_restore, "sheet"})

      assert avatar_id == pending_avatar.id
      assert Repo.get!(SheetAvatar, pending_avatar.id).sheet_id == sheet.id

      assert Repo.exists?(
               from(ref in EntityTrashRef,
                 where: ref.target_sheet_avatar_id == ^pending_avatar.id
               )
             )

      assert {:ok, %{restored: 1, skipped: 0}} =
               Flows.restore_trash_refs(:sheet_avatar, pending_avatar.id)

      assert Repo.get!(FlowNode, node.id).data["avatar_id"] == pending_avatar.id
    end

    test "ignores inherited instances owned by a sheet in trash during restore preflight", %{
      project: project,
      sheet: sheet
    } do
      child = child_sheet_fixture(project, sheet)

      {:ok, source} =
        Sheets.create_block(sheet, %{
          type: "text",
          scope: "children",
          config: %{"label" => "Historical", "placeholder" => ""}
        })

      instance = inherited_instance!(child.id, source.id)
      snapshot = SheetBuilder.build_snapshot(sheet)
      deleted_at = DateTime.truncate(DateTime.utc_now(), :second)

      Repo.update_all(
        from(owner in Sheet, where: owner.id == ^child.id),
        set: [deleted_at: deleted_at]
      )

      Repo.update_all(
        from(block in Block, where: block.id == ^source.id),
        set: [
          type: "number",
          config: %{"label" => "Current number"},
          value: Block.default_value("number")
        ]
      )

      Repo.update_all(
        from(block in Block, where: block.id == ^instance.id),
        set: [config: %{"label" => "Trash sentinel"}]
      )

      assert {:ok, _restored} =
               SheetBuilder.restore_snapshot(sheet, snapshot, restore_action: {:entity_version_restore, "sheet"})

      assert Repo.get!(Block, source.id).type == "text"
      assert Repo.get!(Block, instance.id).config == %{"label" => "Trash sentinel"}
    end

    test "rolls back the sheet and child rows when a gallery asset blob cannot be materialized", %{
      project: project,
      sheet: sheet,
      user: user
    } do
      suffix = System.unique_integer([:positive])

      banner_asset =
        uploaded_image_asset(
          project,
          user,
          "rollback-banner-#{suffix}.png",
          "rollback-banner"
        )

      gallery_asset =
        uploaded_image_asset(
          project,
          user,
          "rollback-gallery-#{suffix}.png",
          "rollback-gallery"
        )

      {:ok, sheet_with_banner} =
        Sheets.update_sheet(sheet, %{banner_asset_id: banner_asset.id})

      gallery_block =
        block_fixture(sheet, %{
          type: "gallery",
          config: %{"label" => "Historical gallery"},
          value: %{}
        })

      {:ok, gallery_image} = Sheets.add_gallery_image(gallery_block, gallery_asset.id)

      {:ok, gallery_image} =
        Sheets.update_gallery_image(gallery_image, %{
          label: "Historical image",
          description: "Historical description"
        })

      snapshot = SheetBuilder.build_snapshot(sheet_with_banner)

      assert snapshot["asset_blob_hashes"][to_string(gallery_asset.id)] ==
               gallery_asset.blob_hash

      gallery_blob_key =
        BlobStore.blob_key(
          project.id,
          gallery_asset.blob_hash,
          BlobStore.ext_from_content_type(gallery_asset.content_type)
        )

      banner_blob_key =
        BlobStore.blob_key(
          project.id,
          banner_asset.blob_hash,
          BlobStore.ext_from_content_type(banner_asset.content_type)
        )

      assert :ok = delete_storage_blob(gallery_blob_key)

      current_sheet =
        sheet_with_banner
        |> Ecto.Changeset.change(
          name: "Current sheet",
          description: "Current description",
          banner_asset_id: nil
        )
        |> Repo.update!()

      current_block =
        gallery_block
        |> Ecto.Changeset.change(
          config: %{"label" => "Current gallery"},
          value: %{"current" => true}
        )
        |> Repo.update!()

      current_image =
        gallery_image
        |> Ecto.Changeset.change(
          label: "Current image",
          description: "Current image description"
        )
        |> Repo.update!()

      asset_count_before = Repo.aggregate(Asset, :count)
      copied_banner_paths_before = stored_asset_paths(banner_asset.filename)

      assert {:error, {:asset_materialization_failed, missing_asset_id, {:asset_blob_unavailable, _reason}}} =
               SheetBuilder.restore_snapshot(current_sheet, snapshot,
                 asset_mode: :copy,
                 user_id: user.id,
                 restore_action: {:entity_version_restore, "sheet"}
               )

      assert missing_asset_id == gallery_asset.id

      restored_sheet = Repo.get!(Sheet, sheet.id)
      assert restored_sheet.name == "Current sheet"
      assert restored_sheet.description == "Current description"
      assert is_nil(restored_sheet.banner_asset_id)

      restored_block = Repo.get!(Block, gallery_block.id)
      assert restored_block.config == current_block.config
      assert restored_block.value == current_block.value

      restored_image = Repo.get!(BlockGalleryImage, gallery_image.id)
      assert restored_image.asset_id == current_image.asset_id
      assert restored_image.label == "Current image"
      assert restored_image.description == "Current image description"

      assert Repo.aggregate(
               from(image in BlockGalleryImage,
                 where: image.block_id == ^gallery_block.id
               ),
               :count
             ) == 1

      assert Repo.aggregate(Asset, :count) == asset_count_before

      assert [] = all_enqueued(worker: DeleteStorageObjectsWorker)
      assert stored_asset_paths(banner_asset.filename) == copied_banner_paths_before
      assert {:ok, "rollback-banner"} = Assets.storage_download(banner_blob_key)
    end

    test "rejects duplicate and foreign IDs before changing any data", %{
      project: project,
      sheet: sheet
    } do
      first_block = block_fixture(sheet, %{position: 0, config: %{"label" => "First"}})
      second_block = block_fixture(sheet, %{position: 1, config: %{"label" => "Second"}})
      snapshot = SheetBuilder.build_snapshot(sheet)
      {:ok, current_sheet} = Sheets.update_sheet(sheet, %{name: "Current state"})

      [first_snapshot, second_snapshot] = snapshot["blocks"]

      duplicate_snapshot =
        snapshot
        |> Map.put("name", "Invalid duplicate")
        |> Map.put(
          "blocks",
          [first_snapshot, Map.put(second_snapshot, "original_id", first_snapshot["original_id"])]
        )

      assert {:error, {:invalid_snapshot, {:duplicate_original_id, :block, duplicate_id}}} =
               SheetBuilder.restore_snapshot(current_sheet, duplicate_snapshot,
                 restore_action: {:entity_version_restore, "sheet"}
               )

      assert duplicate_id == first_block.id
      assert Repo.get!(Sheet, sheet.id).name == "Current state"
      assert is_nil(Repo.get!(Block, first_block.id).deleted_at)
      assert is_nil(Repo.get!(Block, second_block.id).deleted_at)

      truncated_snapshot =
        snapshot
        |> Map.put("name", "Invalid truncated snapshot")
        |> Map.delete("blocks")

      assert {:error, {:invalid_snapshot, {:missing_field, :sheet, root_id, "blocks"}}} =
               SheetBuilder.restore_snapshot(current_sheet, truncated_snapshot,
                 restore_action: {:entity_version_restore, "sheet"}
               )

      assert root_id == sheet.id
      assert Repo.get!(Sheet, sheet.id).name == "Current state"
      assert is_nil(Repo.get!(Block, first_block.id).deleted_at)
      assert is_nil(Repo.get!(Block, second_block.id).deleted_at)

      for {field, invalid_value} <- [
            {"asset_blob_hashes", []},
            {"asset_metadata", []},
            {"avatar_asset_id", "invalid"}
          ] do
        invalid_manifest = Map.put(snapshot, field, invalid_value)

        assert {:error, {:invalid_snapshot, {:invalid_payload, :sheet, invalid_root_id, ^field, ^invalid_value}}} =
                 SheetBuilder.restore_snapshot(current_sheet, invalid_manifest,
                   restore_action: {:entity_version_restore, "sheet"}
                 )

        assert invalid_root_id == sheet.id
        assert Repo.get!(Sheet, sheet.id).name == "Current state"
        assert is_nil(Repo.get!(Block, first_block.id).deleted_at)
        assert is_nil(Repo.get!(Block, second_block.id).deleted_at)
      end

      foreign_sheet = sheet_fixture(project)
      foreign_block = block_fixture(foreign_sheet)

      ownership_snapshot =
        snapshot
        |> Map.put("name", "Invalid ownership")
        |> Map.put("blocks", [
          Map.put(first_snapshot, "original_id", foreign_block.id),
          second_snapshot
        ])

      assert {:error, {:snapshot_id_ownership_mismatch, :block, foreign_id, expected_sheet_id, actual_sheet_id}} =
               SheetBuilder.restore_snapshot(current_sheet, ownership_snapshot,
                 restore_action: {:entity_version_restore, "sheet"}
               )

      assert foreign_id == foreign_block.id
      assert expected_sheet_id == sheet.id
      assert actual_sheet_id == foreign_sheet.id
      assert Repo.get!(Sheet, sheet.id).name == "Current state"
      assert is_nil(Repo.get!(Block, first_block.id).deleted_at)
      assert is_nil(Repo.get!(Block, second_block.id).deleted_at)
    end

    test "restores an acyclic transitive external inheritance chain", %{
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
        from(current in Block, where: current.id == ^block.id),
        set: [inherited_from_block_id: nil]
      )

      assert {:ok, _restored} =
               SheetBuilder.restore_snapshot(sheet, snapshot, restore_action: {:entity_version_restore, "sheet"})

      assert Repo.get!(Block, block.id).inherited_from_block_id == middle.id
      assert Repo.get!(Block, middle.id).inherited_from_block_id == ancestor.id
    end

    test "rejects a restore that would create a transitive external cycle without partial writes", %{
      project: project,
      sheet: sheet
    } do
      external_sheet = sheet_fixture(project)
      block = block_fixture(sheet, %{type: "text"})
      external = block_fixture(external_sheet, %{type: "text"})
      snapshot = SheetBuilder.build_snapshot(sheet)

      Repo.update_all(
        from(current in Block, where: current.id == ^external.id),
        set: [inherited_from_block_id: block.id]
      )

      cyclic_snapshot =
        snapshot
        |> put_snapshot_block_parent(block.id, external.id)
        |> Map.put("name", "Must not be restored")

      {:ok, current_sheet} = Sheets.update_sheet(sheet, %{name: "Current state"})

      assert {:error, {:invalid_snapshot, {:inheritance_cycle, cycle_id}}} =
               SheetBuilder.restore_snapshot(current_sheet, cyclic_snapshot,
                 restore_action: {:entity_version_restore, "sheet"}
               )

      assert cycle_id == block.id
      assert Repo.get!(Sheet, sheet.id).name == "Current state"
      assert is_nil(Repo.get!(Block, block.id).inherited_from_block_id)
      assert Repo.get!(Block, external.id).inherited_from_block_id == block.id
    end

    test "rejects a same-sheet external block that restore would move to trash", %{
      sheet: sheet
    } do
      kept = block_fixture(sheet, %{type: "text", position: 0})
      omitted = block_fixture(sheet, %{type: "text", position: 1})
      snapshot = SheetBuilder.build_snapshot(sheet)

      invalid_snapshot =
        snapshot
        |> Map.update!("blocks", fn blocks ->
          blocks
          |> Enum.reject(&(&1["original_id"] == omitted.id))
          |> Enum.map(fn block ->
            if block["original_id"] == kept.id,
              do: Map.put(block, "inherited_from_block_id", omitted.id),
              else: block
          end)
        end)
        |> Map.put("name", "Must not be restored")

      {:ok, current_sheet} = Sheets.update_sheet(sheet, %{name: "Current state"})

      assert {:error, {:invalid_snapshot, {:same_sheet_external_block_reference, omitted_id}}} =
               SheetBuilder.restore_snapshot(current_sheet, invalid_snapshot,
                 restore_action: {:entity_version_restore, "sheet"}
               )

      assert omitted_id == omitted.id
      assert Repo.get!(Sheet, sheet.id).name == "Current state"
      assert is_nil(Repo.get!(Block, kept.id).inherited_from_block_id)
      assert is_nil(Repo.get!(Block, omitted.id).deleted_at)
    end

    test "rejects foreign nested IDs for every sheet child type without partial writes", %{
      project: project,
      sheet: sheet,
      user: user
    } do
      avatar_asset = uploaded_image_asset(project, user, "ownership-avatar.png", "ownership-avatar")
      gallery_asset = uploaded_image_asset(project, user, "ownership-gallery.png", "ownership-gallery")
      {:ok, _avatar} = Sheets.add_avatar(sheet, avatar_asset.id, %{name: "Owned avatar"})

      table_block = table_block_fixture(sheet)
      _column = table_column_fixture(table_block, %{name: "Owned column"})
      _row = table_row_fixture(table_block, %{name: "Owned row"})

      gallery_block = block_fixture(sheet, %{type: "gallery", value: %{}})
      {:ok, _gallery_image} = Sheets.add_gallery_image(gallery_block, gallery_asset.id)

      snapshot = SheetBuilder.build_snapshot(sheet)
      {:ok, current_sheet} = Sheets.update_sheet(sheet, %{name: "Current state"})

      foreign_sheet = sheet_fixture(project)
      foreign_table = table_block_fixture(foreign_sheet)
      foreign_column = table_column_fixture(foreign_table, %{name: "Foreign column"})
      foreign_row = table_row_fixture(foreign_table, %{name: "Foreign row"})

      foreign_gallery = block_fixture(foreign_sheet, %{type: "gallery", value: %{}})
      {:ok, foreign_gallery_image} = Sheets.add_gallery_image(foreign_gallery, gallery_asset.id)
      {:ok, foreign_avatar} = Sheets.add_avatar(foreign_sheet, avatar_asset.id, %{name: "Foreign avatar"})

      replace_block = fn source_snapshot, block_id, update_fun ->
        Map.update!(source_snapshot, "blocks", fn blocks ->
          Enum.map(blocks, fn block ->
            if block["original_id"] == block_id, do: update_fun.(block), else: block
          end)
        end)
      end

      table_snapshot = Enum.find(snapshot["blocks"], &(&1["original_id"] == table_block.id))
      [column_snapshot | _] = table_snapshot["table_data"]["columns"]
      [row_snapshot | _] = table_snapshot["table_data"]["rows"]
      gallery_snapshot = Enum.find(snapshot["blocks"], &(&1["original_id"] == gallery_block.id))
      [image_snapshot] = gallery_snapshot["gallery_images"]
      [avatar_snapshot] = snapshot["avatars"]

      foreign_column_snapshot =
        replace_block.(snapshot, table_block.id, fn block ->
          put_in(
            block,
            ["table_data", "columns"],
            [Map.put(column_snapshot, "original_id", foreign_column.id)]
          )
        end)

      foreign_row_snapshot =
        replace_block.(snapshot, table_block.id, fn block ->
          put_in(
            block,
            ["table_data", "rows"],
            [Map.put(row_snapshot, "original_id", foreign_row.id)]
          )
        end)

      foreign_gallery_snapshot =
        replace_block.(snapshot, gallery_block.id, fn block ->
          Map.put(
            block,
            "gallery_images",
            [Map.put(image_snapshot, "original_id", foreign_gallery_image.id)]
          )
        end)

      foreign_avatar_snapshot =
        Map.put(
          snapshot,
          "avatars",
          [Map.put(avatar_snapshot, "original_id", foreign_avatar.id)]
        )

      cases = [
        {:table_column, foreign_column_snapshot, foreign_column.id, table_block.id, foreign_table.id},
        {:table_row, foreign_row_snapshot, foreign_row.id, table_block.id, foreign_table.id},
        {:gallery_image, foreign_gallery_snapshot, foreign_gallery_image.id, gallery_block.id, foreign_gallery.id},
        {:avatar, foreign_avatar_snapshot, foreign_avatar.id, sheet.id, foreign_sheet.id}
      ]

      for {kind, invalid_snapshot, id, expected_parent_id, actual_parent_id} <- cases do
        assert {:error, {:snapshot_id_ownership_mismatch, ^kind, ^id, ^expected_parent_id, ^actual_parent_id}} =
                 SheetBuilder.restore_snapshot(current_sheet, invalid_snapshot,
                   restore_action: {:entity_version_restore, "sheet"}
                 )

        assert Repo.get!(Sheet, sheet.id).name == "Current state"
        assert is_nil(Repo.get!(Block, table_block.id).deleted_at)
        assert is_nil(Repo.get!(Block, gallery_block.id).deleted_at)
      end
    end

    test "rejects a truncated root manifest and missing nil-capable child fields", %{
      project: project,
      sheet: sheet,
      user: user
    } do
      avatar_asset = uploaded_image_asset(project, user, "presence-avatar.png", "presence-avatar")
      gallery_asset = uploaded_image_asset(project, user, "presence-gallery.png", "presence-gallery")
      {:ok, _avatar} = Sheets.add_avatar(sheet, avatar_asset.id, %{})

      block = block_fixture(sheet, %{type: "text", config: %{"label" => "Biography"}})
      gallery_block = block_fixture(sheet, %{type: "gallery", value: %{}})
      {:ok, _gallery_image} = Sheets.add_gallery_image(gallery_block, gallery_asset.id)

      snapshot = SheetBuilder.build_snapshot(sheet)
      {:ok, current_sheet} = Sheets.update_sheet(sheet, %{name: "Current state"})

      update_snapshot_block = fn source_snapshot, block_id, update_fun ->
        Map.update!(source_snapshot, "blocks", fn blocks ->
          Enum.map(blocks, fn block_snapshot ->
            if block_snapshot["original_id"] == block_id,
              do: update_fun.(block_snapshot),
              else: block_snapshot
          end)
        end)
      end

      root_cases =
        for field <-
              ~w(
                original_id name shortcut description avatar_asset_id avatars banner_asset_id
                color hidden_inherited_block_ids blocks asset_blob_hashes asset_metadata
                localization localization_manifest
              ) do
          {:sheet, sheet.id, field, Map.delete(snapshot, field)}
        end

      block_cases =
        for field <- ~w(variable_name inherited_from_block_id column_group_id) do
          invalid_snapshot =
            update_snapshot_block.(snapshot, block.id, &Map.delete(&1, field))

          {:block, block.id, field, invalid_snapshot}
        end

      [avatar_snapshot] = snapshot["avatars"]

      avatar_cases =
        for field <- ~w(name notes) do
          invalid_snapshot =
            Map.put(snapshot, "avatars", [Map.delete(avatar_snapshot, field)])

          {:avatar, avatar_snapshot["original_id"], field, invalid_snapshot}
        end

      gallery_snapshot =
        Enum.find(snapshot["blocks"], &(&1["original_id"] == gallery_block.id))

      [gallery_image_snapshot] = gallery_snapshot["gallery_images"]

      gallery_cases =
        for field <- ~w(label description) do
          invalid_snapshot =
            update_snapshot_block.(snapshot, gallery_block.id, fn block_snapshot ->
              Map.put(
                block_snapshot,
                "gallery_images",
                [Map.delete(gallery_image_snapshot, field)]
              )
            end)

          {:gallery_image, gallery_image_snapshot["original_id"], field, invalid_snapshot}
        end

      for {kind, id, field, invalid_snapshot} <-
            root_cases ++ block_cases ++ avatar_cases ++ gallery_cases do
        assert {:error, {:invalid_snapshot, {:missing_field, ^kind, ^id, ^field}}} =
                 SheetBuilder.restore_snapshot(current_sheet, invalid_snapshot,
                   restore_action: {:entity_version_restore, "sheet"}
                 )

        assert Repo.get!(Sheet, sheet.id).name == "Current state"
        assert is_nil(Repo.get!(Block, block.id).deleted_at)
        assert is_nil(Repo.get!(Block, gallery_block.id).deleted_at)
      end
    end
  end

  describe "instantiate_snapshot/3" do
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
      avatar_asset = uploaded_image_asset(project, user, "copied-avatar.png", "copied avatar")
      broken_avatar_asset = uploaded_image_asset(project, user, "broken-avatar.png", "broken avatar")

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
                 asset_error_mode: :strict,
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

    test "drops banner, avatars, and gallery images only when asset_mode is explicitly drop", %{
      project: project,
      sheet: sheet,
      user: user
    } do
      asset = uploaded_image_asset(project, user, "explicit-drop.png", "explicit-drop")

      {:ok, _sheet} = Sheets.update_sheet(sheet, %{banner_asset_id: asset.id})
      {:ok, _avatar} = Sheets.add_avatar(sheet, asset.id, %{name: "Drop me"})
      gallery_block = block_fixture(sheet, %{type: "gallery", value: %{}})
      {:ok, _gallery_image} = Sheets.add_gallery_image(gallery_block, asset.id)

      snapshot = SheetBuilder.build_snapshot(sheet)
      destination_project = project_fixture(user)

      assert {:ok, materialized, _id_maps} =
               SheetBuilder.instantiate_snapshot(destination_project.id, snapshot,
                 asset_mode: :drop,
                 preserve_external_refs: true,
                 reset_shortcut: true,
                 user_id: user.id
               )

      assert is_nil(Repo.get!(Sheet, materialized.id).banner_asset_id)
      assert Sheets.list_avatars(materialized.id) == []

      [materialized_gallery] =
        Enum.filter(Sheets.list_blocks(materialized.id), &(&1.type == "gallery"))

      assert Sheets.list_gallery_images(materialized_gallery.id) == []

      assert {:ok, _restored, _id_maps} =
               SheetBuilder.restore_snapshot(Repo.get!(Sheet, sheet.id), snapshot,
                 asset_mode: :drop,
                 restore_action: {:entity_version_restore, "sheet"},
                 return_id_maps: true
               )

      assert is_nil(Repo.get!(Sheet, sheet.id).banner_asset_id)
      assert Sheets.list_avatars(sheet.id) == []
      assert Sheets.list_gallery_images(gallery_block.id) == []
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

    test "restores table columns and rows", %{sheet: sheet} do
      table_block = table_block_fixture(sheet)
      col = table_column_fixture(table_block, %{name: "Score", type: "number"})

      [default_row] = Sheets.list_table_rows(table_block.id)

      Sheets.update_table_cell(default_row, col.slug, "99")

      snapshot = SheetBuilder.build_snapshot(sheet)

      # Modify table data
      Sheets.delete_table_column(col)

      # Restore
      {:ok, _restored} =
        SheetBuilder.restore_snapshot(sheet, snapshot, restore_action: {:entity_version_restore, "sheet"})

      # Verify table data was restored
      blocks = Sheets.list_blocks(sheet.id)
      table = Enum.find(blocks, &(&1.type == "table"))
      assert table

      columns = Sheets.list_table_columns(table.id)
      assert Enum.any?(columns, &(&1.name == "Score"))
      assert Enum.any?(columns, &(&1.id == col.id))

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
        "hidden_inherited_block_ids" => [40],
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
      assert {:block, 40} in types_and_ids
      assert length(refs) == 4
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

  defp inherited_instance!(sheet_id, source_block_id) do
    Repo.one!(
      from(block in Block,
        where:
          block.sheet_id == ^sheet_id and
            block.inherited_from_block_id == ^source_block_id
      )
    )
  end

  defp put_snapshot_block_parent(snapshot, block_id, inherited_from_block_id) do
    Map.update!(snapshot, "blocks", fn blocks ->
      Enum.map(
        blocks,
        &put_snapshot_block_parent_entry(&1, block_id, inherited_from_block_id)
      )
    end)
  end

  defp put_snapshot_block_parent_entry(block, block_id, inherited_from_block_id) do
    if block["original_id"] == block_id,
      do: Map.put(block, "inherited_from_block_id", inherited_from_block_id),
      else: block
  end

  defp translated_block_text!(block_id, translated_text) do
    [text] = Localization.get_texts_for_source("block", block_id)
    {:ok, translated} = Localization.update_text(text, %{translated_text: translated_text, status: "final"})
    translated
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

  defp variable_assignment(sheet_shortcut, variable_name) do
    %{
      "id" => Ecto.UUID.generate(),
      "sheet" => sheet_shortcut,
      "variable" => variable_name,
      "operator" => "set",
      "value" => "100",
      "value_type" => "literal"
    }
  end

  defp variable_condition(sheet_shortcut, variable_name) do
    %{
      "logic" => "all",
      "blocks" => [
        %{
          "id" => Ecto.UUID.generate(),
          "type" => "block",
          "logic" => "all",
          "rules" => [
            %{
              "id" => Ecto.UUID.generate(),
              "sheet" => sheet_shortcut,
              "variable" => variable_name,
              "operator" => "greater_than",
              "value" => "50"
            }
          ]
        }
      ]
    }
  end

  defp variable_reference_sources(block_id) do
    VariableReference
    |> where([reference], reference.block_id == ^block_id)
    |> Repo.all()
    |> MapSet.new(&{&1.source_type, &1.source_id})
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

  defp sheet_localization_state(sheet_id, block_id) do
    Repo.all(
      from(text in LocalizedText,
        where:
          (text.source_type == "sheet" and text.source_id == ^sheet_id) or
            (text.source_type == "block" and text.source_id == ^block_id),
        order_by: [asc: text.id]
      )
    )
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
