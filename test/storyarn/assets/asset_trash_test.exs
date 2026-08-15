defmodule Storyarn.Assets.AssetTrashTest do
  use Storyarn.DataCase, async: true

  import Ecto.Query
  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Ecto.Adapters.SQL
  alias Storyarn.Accounts.User
  alias Storyarn.Assets
  alias Storyarn.Assets.Asset
  alias Storyarn.Assets.StorageCleanupRequest
  alias Storyarn.Billing
  alias Storyarn.Flows.EntityTrashRef
  alias Storyarn.Localization
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Sheets
  alias Storyarn.Sheets.Sheet

  setup do
    user = user_fixture()
    project = project_fixture(user)
    %{project: project, user: user}
  end

  test "move to trash preserves ownership and bytes while active reads hide the asset", %{
    project: project,
    user: user
  } do
    asset = image_asset_fixture(project, user, %{metadata: %{"width" => 640}})

    assert {:ok, moved} = Assets.move_asset_to_trash(project.id, asset.id, user.id)
    assert moved.id == asset.id
    assert moved.key == asset.key
    assert moved.size == asset.size
    assert moved.metadata == asset.metadata
    assert moved.deleted_by_id == user.id
    assert moved.deletion_reason == "user"
    assert moved.deletion_generation == 1
    assert %DateTime{} = moved.deleted_at

    assert Assets.get_asset(project.id, asset.id) == nil
    assert Assets.get_asset(asset.id) == nil
    assert Assets.get_asset_by_key(project.id, asset.key) == nil
    assert Assets.list_assets(project.id) == []
    assert Assets.list_assets_for_export(project.id) == []
    assert Assets.count_assets(project.id) == 0
    assert Assets.total_storage_size(project.id) == 0
    assert Assets.get_trashed_asset(project.id, asset.id).id == asset.id
    assert Repo.all(StorageCleanupRequest) == []

    usage = Billing.project_storage_usage(project.id)
    assert usage.current_assets == %{bytes: 0, count: 0}
    assert usage.asset_trash == %{bytes: asset.size, count: 1}
    assert usage.accounted_bytes == asset.size
  end

  test "active content references block trash without detaching anything", %{
    project: project,
    user: user
  } do
    asset = audio_asset_fixture(project, user)
    flow = flow_fixture(project)

    node =
      node_fixture(flow, %{
        type: "dialogue",
        data: %{"audio_asset_id" => asset.id, "text" => "Hello"}
      })

    assert {:error, :asset_still_referenced} =
             Assets.move_asset_to_trash(project.id, asset.id, user.id)

    assert Assets.get_asset(project.id, asset.id)
    assert Repo.reload!(node).data["audio_asset_id"] == asset.id
  end

  test "references owned only by project trash remain recoverable and block purge", %{
    project: project,
    user: user
  } do
    asset = image_asset_fixture(project, user)
    sheet = sheet_fixture(project, %{banner_asset_id: asset.id})
    assert {:ok, _sheet} = Sheets.delete_sheet(sheet)

    assert {:ok, trashed} = Assets.move_asset_to_trash(project.id, asset.id, user.id)

    assert {:error, :asset_still_referenced} =
             Assets.purge_trashed_asset(project.id, asset.id, trashed.deletion_generation, user.id)

    assert Repo.get!(Asset, asset.id).deleted_at
    assert Repo.reload!(sheet).banner_asset_id == asset.id
  end

  test "archived localization lets exact restore trash its voice asset but still blocks purge", %{
    project: project,
    user: user
  } do
    asset = audio_asset_fixture(project, user)
    text = localized_text_fixture(project.id)

    assert {:ok, text} =
             Localization.update_text(text, %{
               vo_asset_id: asset.id,
               vo_status: "recorded"
             })

    assert {:error, :asset_still_referenced} =
             Assets.move_asset_to_trash(project.id, asset.id, user.id)

    text
    |> Ecto.Changeset.change(
      archived_at: TimeHelpers.now(),
      archive_reason: "version_replaced"
    )
    |> Repo.update!()

    assert {:ok, trashed} = Assets.move_asset_to_trash(project.id, asset.id, user.id)

    assert {:error, :asset_still_referenced} =
             Assets.purge_trashed_asset(
               project.id,
               asset.id,
               trashed.deletion_generation,
               user.id
             )
  end

  test "legacy entity-trash reference types remain purge authority", %{
    project: project,
    user: user
  } do
    asset = image_asset_fixture(project, user)

    {1, _} =
      Repo.insert_all(EntityTrashRef, [
        %{
          source_type: "flow_sequence",
          source_id: 99_999,
          source_field: "legacy.asset_id",
          target_asset_id: asset.id,
          inserted_at: DateTime.utc_now(:second)
        }
      ])

    assert {:ok, trashed} = Assets.move_asset_to_trash(project.id, asset.id, user.id)

    assert {:error, :asset_still_referenced} =
             Assets.purge_trashed_asset(
               project.id,
               asset.id,
               trashed.deletion_generation,
               user.id
             )

    assert Repo.get!(Asset, asset.id).deleted_at
    assert Repo.aggregate(EntityTrashRef, :count) == 1
  end

  test "original and variants move and restore as one metadata-preserving family", %{
    project: project,
    user: user
  } do
    original = image_asset_fixture(project, user, %{filename: "hero.png"})
    variant = image_asset_fixture(project, user, %{filename: "hero.webp"})

    assert {:ok, original} =
             Assets.update_asset(original, %{
               metadata: %{"web_asset_id" => variant.id, "web_url" => variant.url}
             })

    assert {:ok, variant} =
             Assets.update_asset(variant, %{
               metadata: %{"is_variant" => true, "original_asset_id" => original.id}
             })

    assert {:ok, trashed_original} =
             Assets.move_asset_to_trash(project.id, original.id, user.id)

    trashed_variant = Repo.reload!(variant)
    assert trashed_original.deleted_at
    assert trashed_variant.deleted_at == trashed_original.deleted_at
    assert Repo.reload!(original).metadata["web_asset_id"] == variant.id
    assert trashed_variant.metadata["original_asset_id"] == original.id

    assert {:ok, restored} =
             Assets.restore_trashed_asset(
               project.id,
               original.id,
               trashed_original.deletion_generation,
               user.id
             )

    assert restored.deleted_at == nil
    assert restored.deletion_generation == 2
    assert Repo.reload!(variant).deleted_at == nil
    assert Assets.get_asset(project.id, original.id)
    assert Assets.get_asset(project.id, variant.id)
  end

  test "exact restore seam requires the lock and a complete intrinsic family", %{
    project: project,
    user: user
  } do
    original = image_asset_fixture(project, user, %{filename: "hero.png"})
    variant = image_asset_fixture(project, user, %{filename: "hero.webp"})

    assert {:ok, original} =
             Assets.update_asset(original, %{metadata: %{"web_asset_id" => variant.id}})

    assert {:error, :storage_accounting_lock_required} =
             Assets.move_assets_to_trash_locked(project.id, user.id, [original.id, variant.id])

    assert {:ok, {:error, :asset_family_incomplete}} =
             Billing.with_storage_accounting_lock(project.workspace_id, fn _workspace ->
               Assets.move_assets_to_trash_locked(project.id, user.id, [original.id])
             end)

    assert {:ok, {:ok, moved}} =
             Billing.with_storage_accounting_lock(project.workspace_id, fn _workspace ->
               Assets.move_assets_to_trash_locked(project.id, user.id, [original.id, variant.id])
             end)

    assert moved.deletion_reason == "snapshot_restore"
    assert Repo.reload!(variant).deleted_at
  end

  test "restore and purge reject a stale generation", %{project: project, user: user} do
    asset = asset_fixture(project, user)
    assert {:ok, trashed} = Assets.move_asset_to_trash(project.id, asset.id, user.id)

    assert {:error, :asset_trash_generation_changed} =
             Assets.restore_trashed_asset(project.id, asset.id, trashed.deletion_generation + 1, user.id)

    assert {:error, :asset_trash_generation_changed} =
             Assets.purge_trashed_asset(project.id, asset.id, trashed.deletion_generation + 1, user.id)

    assert Repo.get!(Asset, asset.id).deleted_at
    assert Repo.all(StorageCleanupRequest) == []
  end

  test "purge deletes only the logical row and durably hands off live-key cleanup", %{
    project: project,
    user: user
  } do
    blob_key = "projects/#{project.id}/blobs/#{String.duplicate("a", 64)}"
    thumbnail_key = Assets.thumbnail_key(Assets.generate_key(project, "hero.png"))

    asset =
      image_asset_fixture(project, user, %{
        blob_hash: String.duplicate("a", 64),
        metadata: %{"blob_key" => blob_key, "thumbnail_key" => thumbnail_key}
      })

    assert {:ok, trashed} = Assets.move_asset_to_trash(project.id, asset.id, user.id)

    assert {:ok, purged} =
             Assets.purge_trashed_asset(project.id, asset.id, trashed.deletion_generation, user.id)

    assert purged.id == asset.id
    assert Repo.get(Asset, asset.id) == nil

    assert [request] = Repo.all(StorageCleanupRequest)
    assert asset.key in request.storage_keys
    assert Assets.thumbnail_key(asset.key) in request.storage_keys
    refute blob_key in request.storage_keys
  end

  test "cross-project references block both move and purge without mutating the foreign project", %{
    project: project,
    user: user
  } do
    asset = image_asset_fixture(project, user)
    foreign_project = project_fixture()
    foreign_sheet = sheet_fixture(foreign_project)

    {1, _} =
      Repo.update_all(
        from(sheet in Sheet, where: sheet.id == ^foreign_sheet.id),
        set: [banner_asset_id: asset.id]
      )

    assert {:error, :asset_still_referenced} =
             Assets.move_asset_to_trash(project.id, asset.id, user.id)

    assert is_nil(Repo.reload!(asset).deleted_at)
    assert Repo.reload!(foreign_sheet).banner_asset_id == asset.id

    {1, _} =
      Repo.update_all(
        from(sheet in Sheet, where: sheet.id == ^foreign_sheet.id),
        set: [banner_asset_id: nil]
      )

    assert {:ok, trashed} = Assets.move_asset_to_trash(project.id, asset.id, user.id)

    {1, _} =
      Repo.update_all(
        from(sheet in Sheet, where: sheet.id == ^foreign_sheet.id),
        set: [banner_asset_id: asset.id]
      )

    assert {:error, :asset_still_referenced} =
             Assets.purge_trashed_asset(
               project.id,
               asset.id,
               trashed.deletion_generation,
               user.id
             )

    assert Repo.get!(Asset, asset.id).deleted_at
    assert Repo.reload!(foreign_sheet).banner_asset_id == asset.id
    assert Repo.all(StorageCleanupRequest) == []
  end

  test "metadata writers reject cross-project and trashed family targets", %{
    project: project,
    user: user
  } do
    target = image_asset_fixture(project, user)
    foreign_project = project_fixture()
    foreign_asset = image_asset_fixture(foreign_project, user)

    assert {:error, :asset_family_identity_invalid} =
             Assets.update_asset(foreign_asset, %{
               metadata: %{"web_asset_id" => target.id}
             })

    assert {:error, :asset_family_identity_invalid} =
             Assets.create_asset(
               foreign_project,
               user,
               valid_asset_attributes(%{
                 key: Assets.generate_key(foreign_project, "cross-project.png"),
                 metadata: %{"original_asset_id" => target.id}
               })
             )

    same_project_asset = image_asset_fixture(project, user)
    assert {:ok, _trashed} = Assets.move_asset_to_trash(project.id, target.id, user.id)

    assert {:error, :asset_family_identity_invalid} =
             Assets.update_asset(same_project_asset, %{
               metadata: %{"web_asset_id" => target.id}
             })
  end

  test "metadata writers reject family IDs outside the PostgreSQL bigint range", %{
    project: project,
    user: user
  } do
    asset = image_asset_fixture(project, user)
    oversized_id = 9_223_372_036_854_775_808

    assert {:error, :asset_family_identity_invalid} =
             Assets.update_asset(asset, %{
               metadata: %{"web_asset_id" => oversized_id}
             })

    assert {:error, :asset_family_identity_invalid} =
             Assets.create_asset(
               project,
               user,
               valid_asset_attributes(%{
                 key: Assets.generate_key(project, "oversized-family-id.png"),
                 metadata: %{"original_asset_id" => Integer.to_string(oversized_id)}
               })
             )

    assert Repo.reload!(asset).metadata == asset.metadata
    assert Assets.list_asset_ids(project.id) == [asset.id]
  end

  test "corrupt family metadata fails closed, including incoming links omitted from the graph", %{
    project: project,
    user: user
  } do
    target = image_asset_fixture(project, user)
    corrupt = image_asset_fixture(project, user)

    {1, _} =
      Repo.update_all(
        from(asset in Asset, where: asset.id == ^corrupt.id),
        set: [
          metadata: %{
            "web_asset_id" => target.id,
            "variant_asset_ids" => "not-an-object"
          }
        ]
      )

    assert {:error, :asset_family_identity_invalid} =
             Assets.move_asset_to_trash(project.id, target.id, user.id)

    assert is_nil(Repo.reload!(target).deleted_at)
    assert is_nil(Repo.reload!(corrupt).deleted_at)

    {1, _} =
      Repo.update_all(
        from(asset in Asset, where: asset.id == ^target.id),
        set: [metadata: %{"web_asset_id" => "invalid"}]
      )

    assert {:error, :asset_family_identity_invalid} =
             Assets.move_asset_to_trash(project.id, target.id, user.id)

    assert is_nil(Repo.reload!(target).deleted_at)
  end

  test "exact restore seam rejects malformed IDs and mixed family state", %{
    project: project,
    user: user
  } do
    original = image_asset_fixture(project, user)
    variant = image_asset_fixture(project, user)

    assert {:ok, original} =
             Assets.update_asset(original, %{metadata: %{"web_asset_id" => variant.id}})

    variant
    |> Asset.trash_changeset(user.id, "user", DateTime.utc_now(:second))
    |> Repo.update!()

    assert {:ok, {:error, :asset_family_incomplete}} =
             Billing.with_storage_accounting_lock(project.workspace_id, fn _workspace ->
               Assets.move_assets_to_trash_locked(project.id, user.id, [original.id])
             end)

    assert {:ok, {:error, :asset_not_found}} =
             Billing.with_storage_accounting_lock(project.workspace_id, fn _workspace ->
               Assets.move_assets_to_trash_locked(project.id, user.id, [original.id, "invalid"])
             end)

    assert is_nil(Repo.reload!(original).deleted_at)
  end

  test "purge rolls back when any family member lacks an authorized cleanup key", %{
    project: project,
    user: user
  } do
    original = image_asset_fixture(project, user)
    variant = image_asset_fixture(project, user)

    assert {:ok, original} =
             Assets.update_asset(original, %{metadata: %{"web_asset_id" => variant.id}})

    assert {:ok, _variant} =
             Assets.update_asset(variant, %{metadata: %{"original_asset_id" => original.id}})

    invalid_key = "projects/#{project.id}/assets/not-a-uuid/variant.png"

    {1, _} =
      Repo.update_all(
        from(asset in Asset, where: asset.id == ^variant.id),
        set: [key: invalid_key]
      )

    assert {:ok, trashed} = Assets.move_asset_to_trash(project.id, original.id, user.id)

    assert {:error, :asset_cleanup_not_authorized} =
             Assets.purge_trashed_asset(
               project.id,
               original.id,
               trashed.deletion_generation,
               user.id
             )

    assert Repo.get!(Asset, original.id).deleted_at
    assert Repo.get!(Asset, variant.id).deleted_at
    assert Repo.all(StorageCleanupRequest) == []
  end

  test "invalid actors fail through the changeset and deleting a recorded actor preserves trash history", %{
    project: project,
    user: user
  } do
    invalid_actor_asset = image_asset_fixture(project, user)

    assert {:error, %Ecto.Changeset{} = changeset} =
             Assets.move_asset_to_trash(project.id, invalid_actor_asset.id, 9_999_999_999)

    assert errors_on(changeset).deleted_by_id != []
    assert is_nil(Repo.reload!(invalid_actor_asset).deleted_at)

    actor =
      Repo.insert!(%User{
        email: unique_user_email(),
        confirmed_at: DateTime.utc_now(:second)
      })

    historical_asset = image_asset_fixture(project, user)
    assert {:ok, trashed} = Assets.move_asset_to_trash(project.id, historical_asset.id, actor.id)
    assert trashed.deleted_by_id == actor.id

    Repo.delete!(actor)

    historical_asset = Repo.reload!(historical_asset)
    assert historical_asset.deleted_by_id == nil
    assert historical_asset.deletion_reason == "user"
    assert historical_asset.deleted_at
  end

  test "bulk purge rejects malformed candidates before changing durable state", %{
    project: project,
    user: user
  } do
    asset = image_asset_fixture(project, user)
    assert {:ok, _trashed} = Assets.move_asset_to_trash(project.id, asset.id, user.id)

    assert {:error, :invalid_asset_trash_request} =
             Assets.purge_trashed_assets(project.id, [:malformed], user.id)

    assert Repo.get!(Asset, asset.id).deleted_at
    assert Repo.all(StorageCleanupRequest) == []
  end

  test "database constraints reject incomplete trash state", %{project: project, user: user} do
    asset = image_asset_fixture(project, user)

    assert_raise Postgrex.Error, fn ->
      Repo.transaction(
        fn ->
          SQL.query!(
            Repo,
            """
            UPDATE assets
            SET deleted_at = NOW(), deletion_reason = NULL, deletion_generation = 1
            WHERE id = $1
            """,
            [asset.id]
          )
        end,
        mode: :savepoint
      )
    end

    assert_raise Postgrex.Error, fn ->
      Repo.transaction(
        fn ->
          SQL.query!(
            Repo,
            """
            UPDATE assets
            SET deleted_at = NOW(), deletion_reason = 'system', deletion_generation = 0
            WHERE id = $1
            """,
            [asset.id]
          )
        end,
        mode: :savepoint
      )
    end

    assert is_nil(Repo.reload!(asset).deleted_at)
  end

  test "migration installs retention and reverse-reference indexes" do
    %{rows: rows} =
      SQL.query!(
        Repo,
        """
        SELECT indexname
        FROM pg_indexes
        WHERE schemaname = current_schema()
          AND indexname = ANY($1::text[])
        """,
        [
          [
            "assets_trash_retention_index",
            "localized_texts_vo_asset_id_index",
            "scenes_background_asset_id_index",
            "sheet_avatars_asset_id_index",
            "block_gallery_images_asset_id_index",
            "flow_nodes_audio_asset_id_index"
          ]
        ]
      )

    assert MapSet.new(List.flatten(rows)) ==
             MapSet.new([
               "assets_trash_retention_index",
               "localized_texts_vo_asset_id_index",
               "scenes_background_asset_id_index",
               "sheet_avatars_asset_id_index",
               "block_gallery_images_asset_id_index",
               "flow_nodes_audio_asset_id_index"
             ])
  end
end
