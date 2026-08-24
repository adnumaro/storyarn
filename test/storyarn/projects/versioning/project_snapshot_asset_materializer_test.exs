defmodule Storyarn.Projects.Versioning.ProjectSnapshotAssetMaterializerTest do
  use Storyarn.DataCase, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Platform.Billing
  alias Storyarn.Projects.Assets
  alias Storyarn.Projects.Assets.Asset
  alias Storyarn.Projects.Assets.BlobStore
  alias Storyarn.Projects.Assets.Storage
  alias Storyarn.Projects.Assets.StorageCompensation
  alias Storyarn.Projects.Project
  alias Storyarn.Projects.Versioning.Builders.AssetHashResolver
  alias Storyarn.Projects.Versioning.ProjectSnapshotAssetMaterializer
  alias Storyarn.Projects.Versioning.SnapshotObjectFormat
  alias Storyarn.Repo

  setup do
    user = user_fixture()
    project = project_fixture(user)
    %{user: user, project: project}
  end

  test "plans duplicate logical assets from one verified blob without collapsing identity", %{project: project} do
    fixture = catalog_fixture(project.id)

    assert {:ok, plan} =
             ProjectSnapshotAssetMaterializer.prepare(
               project.id,
               "restore-42",
               fixture.manifest,
               fixture.project_object,
               fixture.staging_prefix,
               fixture.staging_keys
             )

    assert plan.logical_bytes == 2 * byte_size(fixture.bytes)
    assert plan.staging_bytes == byte_size(fixture.bytes)
    assert length(plan.assets) == 2
    assert length(plan.blobs) == 1

    assert [first, second] = plan.assets
    assert first.source_key == second.source_key
    refute first.destination_key == second.destination_key
    assert first.destination_blob_key == second.destination_blob_key

    assert {:ok, same_plan} =
             ProjectSnapshotAssetMaterializer.prepare(
               project.id,
               "restore-42",
               fixture.manifest,
               fixture.project_object,
               fixture.staging_prefix,
               fixture.staging_keys
             )

    assert Enum.map(same_plan.assets, & &1.destination_key) ==
             Enum.map(plan.assets, & &1.destination_key)
  end

  test "rejects an asset catalog without the current exact restore contract", %{project: project} do
    fixture = catalog_fixture(project.id)

    assert {:error, :invalid_snapshot_asset_restore_contract} =
             ProjectSnapshotAssetMaterializer.prepare(
               project.id,
               1,
               fixture.manifest,
               Map.delete(fixture.project_object, "asset_restore_contract_version"),
               fixture.staging_prefix,
               fixture.staging_keys
             )
  end

  test "rejects staging inventories that are not exact and restore-owned", %{project: project} do
    fixture = catalog_fixture(project.id)
    [{path, key}] = Map.to_list(fixture.staging_keys)

    assert {:error, :snapshot_staging_inventory_mismatch} =
             ProjectSnapshotAssetMaterializer.prepare(
               project.id,
               1,
               fixture.manifest,
               fixture.project_object,
               fixture.staging_prefix,
               %{path => key, "blobs/extra.png" => fixture.staging_prefix <> "/blobs/extra.png"}
             )

    current_key = BlobStore.blob_key(project.id, fixture.sha256, "png")

    assert {:error, :snapshot_staging_inventory_mismatch} =
             ProjectSnapshotAssetMaterializer.prepare(
               project.id,
               1,
               fixture.manifest,
               fixture.project_object,
               fixture.staging_prefix,
               %{path => current_key}
             )
  end

  test "exact restore preserves a verified asset even when its MIME family mismatches the slot", %{project: project} do
    fixture = catalog_fixture(project.id)

    project_object = Map.put(fixture.project_object, "localization", %{"texts" => [%{"vo_asset_id" => 41}]})

    assert {:ok, plan} =
             ProjectSnapshotAssetMaterializer.prepare(
               project.id,
               1,
               fixture.manifest,
               project_object,
               fixture.staging_prefix,
               fixture.staging_keys
             )

    assert Enum.map(plan.assets, & &1.content_type) == ["image/png", "image/png"]
  end

  test "rejects a graph asset reference absent from source refs before staging", %{project: project} do
    fixture = catalog_fixture(project.id)

    project_object =
      Map.put(fixture.project_object, "localization", %{"texts" => [%{"vo_asset_id" => 999}]})

    assert {:error, {:pre_materialized_asset_reference_missing, {:localization_voice_over, :project, 0}, 999}} =
             ProjectSnapshotAssetMaterializer.prepare(
               project.id,
               1,
               fixture.manifest,
               project_object,
               fixture.staging_prefix,
               fixture.staging_keys
             )
  end

  test "rejects a graph asset without its captured catalog before staging", %{project: project} do
    fixture = catalog_fixture(project.id)

    sheet_snapshot = %{
      "avatar_asset_id" => nil,
      "banner_asset_id" => 41,
      "avatars" => [],
      "blocks" => [],
      "localization" => []
    }

    project_object =
      fixture.project_object
      |> update_in(["asset_blob_hashes"], &Map.delete(&1, "41"))
      |> update_in(["asset_metadata"], &Map.delete(&1, "41"))
      |> Map.put("sheets", [%{"snapshot" => sheet_snapshot}])

    assert {:error, {:pre_materialized_asset_catalog_missing, {:sheet, :banner}, 41}} =
             ProjectSnapshotAssetMaterializer.prepare(
               project.id,
               1,
               fixture.manifest,
               project_object,
               fixture.staging_prefix,
               fixture.staging_keys
             )
  end

  test "accepts an image-backed sheet slot present in the exact catalog", %{project: project} do
    fixture = catalog_fixture(project.id)

    sheet_snapshot = %{
      "avatar_asset_id" => nil,
      "banner_asset_id" => 41,
      "avatars" => [],
      "blocks" => [],
      "localization" => []
    }

    project_object =
      Map.put(fixture.project_object, "sheets", [%{"snapshot" => sheet_snapshot}])

    assert {:ok, _plan} =
             ProjectSnapshotAssetMaterializer.prepare(
               project.id,
               1,
               fixture.manifest,
               project_object,
               fixture.staging_prefix,
               fixture.staging_keys
             )
  end

  test "exact restore uses verified manifest identity and preserves authored relationship drift", %{
    project: project,
    user: user
  } do
    fixture = catalog_fixture(project.id)
    manifest_bytes = byte_size(fixture.bytes)

    first_metadata = %{
      "authored" => %{"kept" => true},
      "original_asset_id" => "42",
      "web_asset_id" => 999_999_999,
      "variant_asset_ids" => %{
        "captured" => 42,
        "dangling" => "888888888",
        "malformed" => [42],
        "nullable" => nil
      }
    }

    second_metadata = %{
      "original_asset_id" => %{"malformed" => 41},
      "web_asset_id" => 41,
      "variant_asset_ids" => "malformed"
    }

    project_object =
      fixture.project_object
      |> Map.put("asset_blob_hashes", %{
        "41" => String.duplicate("0", 64),
        "42" => String.duplicate("1", 64)
      })
      |> Map.put("asset_metadata", %{
        "41" => %{
          "filename" => "../authored-first.png",
          "content_type" => "text/html",
          "size" => 999_999_999,
          "persisted_metadata" => first_metadata
        },
        "42" => %{
          "filename" => "authored-second.bin",
          "content_type" => "application/x-broken",
          "size" => -7,
          "persisted_metadata" => second_metadata
        }
      })

    assert {:ok, plan} =
             ProjectSnapshotAssetMaterializer.prepare(
               project.id,
               "restore-effective-identity",
               fixture.manifest,
               project_object,
               fixture.staging_prefix,
               fixture.staging_keys
             )

    assert Enum.map(plan.assets, &{&1.filename, &1.content_type, &1.size}) == [
             {"../authored-first.png", "image/png", manifest_bytes},
             {"authored-second.bin", "image/png", manifest_bytes}
           ]

    upload_staging_fixture(fixture)
    tracker = StorageCompensation.new()
    assert :ok = ProjectSnapshotAssetMaterializer.stage_destination_objects(plan, tracker)

    assert {:ok, adoption} =
             Billing.transact_with_workspace_lock(project.workspace_id, fn _workspace ->
               locked_project = Repo.get!(Project, project.id)

               with {:ok, adoption} <-
                      ProjectSnapshotAssetMaterializer.adopt_locked(
                        plan,
                        locked_project,
                        user.id,
                        tracker
                      ),
                    :ok <-
                      ProjectSnapshotAssetMaterializer.verify_adopted_locked(
                        plan,
                        adoption.logical_id_map
                      ) do
                 {:ok, adoption}
               end
             end)

    first = Repo.get!(Asset, adoption.logical_id_map["asset-000001"])
    second = Repo.get!(Asset, adoption.logical_id_map["asset-000002"])

    assert {first.filename, first.content_type, first.size, first.blob_hash} ==
             {"../authored-first.png", "image/png", manifest_bytes, fixture.sha256}

    assert {second.filename, second.content_type, second.size, second.blob_hash} ==
             {"authored-second.bin", "image/png", manifest_bytes, fixture.sha256}

    assert first.metadata == %{
             "authored" => %{"kept" => true},
             "original_asset_id" => second.id,
             "web_asset_id" => 999_999_999,
             "variant_asset_ids" => %{
               "captured" => second.id,
               "dangling" => "888888888",
               "malformed" => [42],
               "nullable" => nil
             }
           }

    assert second.metadata == %{
             "original_asset_id" => %{"malformed" => 41},
             "web_asset_id" => first.id,
             "variant_asset_ids" => "malformed"
           }

    assert Billing.project_storage_usage(project.id).current_assets == %{
             bytes: 2 * manifest_bytes,
             count: 2
           }

    assert :ok = StorageCompensation.cleanup_unretained(tracker)
    cleanup_fixture_objects(fixture, plan)
  end

  test "rejects an unmapped family relationship that resolves to another active asset", %{
    project: project,
    user: user
  } do
    fixture = project.id |> catalog_fixture() |> workspace_snapshot_import_fixture(project.workspace_id)
    foreign_user = user_fixture()
    foreign_project = project_fixture(foreign_user)
    foreign_asset = unmapped_asset_fixture(foreign_project, foreign_user, fixture)

    project_object =
      put_in(
        fixture.project_object,
        ["asset_metadata", "41", "persisted_metadata"],
        %{"web_asset_id" => foreign_asset.id}
      )

    assert {:ok, plan} =
             ProjectSnapshotAssetMaterializer.prepare(
               project.id,
               "foreign-relationship-guard",
               fixture.manifest,
               project_object,
               fixture.staging_prefix,
               fixture.staging_keys
             )

    tracker = StorageCompensation.new()

    assert {:error, {:snapshot_asset_unmapped_existing_relationship_ids, [foreign_asset_id]}} =
             Billing.transact_with_workspace_lock(project.workspace_id, fn _workspace ->
               locked_project = Repo.get!(Project, project.id)
               ProjectSnapshotAssetMaterializer.adopt_locked(plan, locked_project, user.id, tracker)
             end)

    assert foreign_asset_id == foreign_asset.id
    assert Assets.list_assets_for_export(project.id) == []
  end

  test "rejects an unmapped family relationship that resolves to another trashed asset", %{
    project: project,
    user: user
  } do
    fixture = project.id |> catalog_fixture() |> workspace_snapshot_import_fixture(project.workspace_id)
    foreign_user = user_fixture()
    foreign_project = project_fixture(foreign_user)
    foreign_asset = unmapped_asset_fixture(foreign_project, foreign_user, fixture)

    foreign_asset
    |> Asset.trash_changeset(foreign_user.id, "user", DateTime.utc_now(:second))
    |> Repo.update!()

    project_object =
      put_in(
        fixture.project_object,
        ["asset_metadata", "41", "persisted_metadata"],
        %{"original_asset_id" => foreign_asset.id}
      )

    assert {:ok, plan} =
             ProjectSnapshotAssetMaterializer.prepare(
               project.id,
               "foreign-trashed-relationship-guard",
               fixture.manifest,
               project_object,
               fixture.staging_prefix,
               fixture.staging_keys
             )

    tracker = StorageCompensation.new()

    assert {:error, {:snapshot_asset_unmapped_existing_relationship_ids, [foreign_asset_id]}} =
             Billing.transact_with_workspace_lock(project.workspace_id, fn _workspace ->
               locked_project = Repo.get!(Project, project.id)
               ProjectSnapshotAssetMaterializer.adopt_locked(plan, locked_project, user.id, tracker)
             end)

    assert foreign_asset_id == foreign_asset.id
    assert Assets.list_assets_for_export(project.id) == []
  end

  test "in-situ snapshot restore preserves its existing unmapped relationship behavior", %{
    project: project,
    user: user
  } do
    fixture = catalog_fixture(project.id)
    foreign_user = user_fixture()
    foreign_project = project_fixture(foreign_user)
    foreign_asset = unmapped_asset_fixture(foreign_project, foreign_user, fixture)

    project_object =
      put_in(
        fixture.project_object,
        ["asset_metadata", "41", "persisted_metadata"],
        %{"web_asset_id" => foreign_asset.id}
      )

    assert {:ok, plan} =
             ProjectSnapshotAssetMaterializer.prepare(
               project.id,
               "in-situ-restore-keeps-established-semantics",
               fixture.manifest,
               project_object,
               fixture.staging_prefix,
               fixture.staging_keys
             )

    tracker = StorageCompensation.new()

    assert {:ok, %{assets: assets}} =
             Billing.transact_with_workspace_lock(project.workspace_id, fn _workspace ->
               locked_project = Repo.get!(Project, project.id)
               ProjectSnapshotAssetMaterializer.adopt_locked(plan, locked_project, user.id, tracker)
             end)

    assert Enum.find(assets, &(&1.filename == "duplicate.png")).metadata["web_asset_id"] ==
             foreign_asset.id
  end

  test "restores a zero-byte row with captured metadata and remapped valid relationships", %{
    project: project,
    user: user
  } do
    fixture = zero_byte_catalog_fixture(project.id)
    upload_staging_fixture(fixture)
    assert {:ok, plan} = prepare_plan(project.id, fixture)
    tracker = StorageCompensation.new()
    assert :ok = ProjectSnapshotAssetMaterializer.stage_destination_objects(plan, tracker)

    assert {:ok, adoption} =
             Billing.transact_with_workspace_lock(project.workspace_id, fn _workspace ->
               locked_project = Repo.get!(Project, project.id)

               with {:ok, adoption} <-
                      ProjectSnapshotAssetMaterializer.adopt_locked(
                        plan,
                        locked_project,
                        user.id,
                        tracker
                      ),
                    :ok <-
                      ProjectSnapshotAssetMaterializer.verify_adopted_locked(
                        plan,
                        adoption.logical_id_map
                      ) do
                 {:ok, adoption}
               end
             end)

    restored = Repo.get!(Asset, adoption.logical_id_map["asset-000001"])
    assert restored.filename == "empty.png"
    assert restored.content_type == "image/png"
    assert restored.size == 0
    assert restored.blob_hash == fixture.sha256

    assert restored.metadata == %{
             "custom_profile" => %{"label" => "kept exactly"},
             "original_asset_id" => restored.id
           }

    assert {:ok, ""} = Storage.download(restored.key)
    cleanup_fixture_objects(fixture, plan)
  end

  test "rejects corrupt zero-byte staging content", %{project: project} do
    fixture = zero_byte_catalog_fixture(project.id)
    assert {:ok, plan} = prepare_plan(project.id, fixture)

    Enum.each(Map.values(fixture.staging_keys), fn key ->
      assert {:ok, _url} = Storage.upload(key, "corrupt", "image/png")
    end)

    tracker = StorageCompensation.new()
    corrupt_size = byte_size("corrupt")

    assert {:error, {:snapshot_blob_staging_failed, _path, {:snapshot_blob_size_mismatch, 0, ^corrupt_size}}} =
             ProjectSnapshotAssetMaterializer.stage_destination_objects(plan, tracker)

    cleanup_fixture_objects(fixture, plan)
  end

  test "database rollback removes rows and compensates every pre-staged logical object", %{
    project: project,
    user: user
  } do
    fixture = catalog_fixture(project.id)
    upload_staging_fixture(fixture)
    assert {:ok, plan} = prepare_plan(project.id, fixture)
    tracker = StorageCompensation.new()
    assert :ok = ProjectSnapshotAssetMaterializer.stage_destination_objects(plan, tracker)

    assert {:error, :forced_rollback} =
             Billing.transact_with_workspace_lock(project.workspace_id, fn _workspace ->
               locked_project = Repo.get!(Project, project.id)

               with {:ok, _adoption} <-
                      ProjectSnapshotAssetMaterializer.adopt_locked(
                        plan,
                        locked_project,
                        user.id,
                        tracker
                      ) do
                 {:error, :forced_rollback}
               end
             end)

    assert [] == Assets.list_assets_for_export(project.id)
    assert :ok = StorageCompensation.cleanup_after_rollback(tracker)

    Enum.each(plan.assets, fn asset ->
      assert {:error, :enoent} = Storage.download(asset.destination_key)
    end)

    cleanup_fixture_objects(fixture, plan)
  end

  test "adopts large catalogs with a bounded number of database round trips", %{
    project: project,
    user: user
  } do
    assert {:ok, small_plan} = prepare_bulk_plan(project.id, 1)
    assert {:ok, large_plan} = prepare_bulk_plan(project.id, 501)

    {small_result, small_queries} =
      capture_repo_queries(fn -> adopt_unstaged_plan(small_plan, project, user.id) end)

    {large_result, large_queries} =
      capture_repo_queries(fn -> adopt_unstaged_plan(large_plan, project, user.id) end)

    assert {:ok, %{assets: [_asset]}} = small_result
    assert {:ok, %{assets: large_assets, logical_id_map: logical_id_map}} = large_result
    assert length(large_assets) == 501
    assert map_size(logical_id_map) == 501

    assert length(large_queries) - length(small_queries) <= 20,
           "expected bounded asset adoption queries, got #{length(small_queries)} for 1 asset and " <>
             "#{length(large_queries)} for 501 assets"
  end

  defp prepare_plan(project_id, fixture) do
    ProjectSnapshotAssetMaterializer.prepare(
      project_id,
      "restore-#{System.unique_integer([:positive])}",
      fixture.manifest,
      fixture.project_object,
      fixture.staging_prefix,
      fixture.staging_keys
    )
  end

  defp prepare_bulk_plan(project_id, asset_count) do
    fixture = bulk_catalog_fixture(project_id, asset_count)
    prepare_plan(project_id, fixture)
  end

  defp workspace_snapshot_import_fixture(fixture, workspace_id) do
    prefix = "workspace-snapshot-imports/v1/#{workspace_id}/#{Ecto.UUID.generate()}"

    staging_keys =
      Map.new(fixture.staging_keys, fn {path, _key} ->
        {path, prefix <> "/blobs/" <> Path.basename(path)}
      end)

    %{fixture | staging_prefix: prefix, staging_keys: staging_keys}
  end

  defp adopt_unstaged_plan(plan, project, actor_id) do
    tracker = StorageCompensation.new()

    Billing.transact_with_workspace_lock(project.workspace_id, fn _workspace ->
      locked_project = Repo.get!(Project, project.id)
      ProjectSnapshotAssetMaterializer.adopt_locked(plan, locked_project, actor_id, tracker)
    end)
  end

  defp catalog_fixture(project_id) do
    bytes = "snapshot-owned duplicate bytes"
    sha256 = sha256(bytes)
    blob_path = SnapshotObjectFormat.blob_path(sha256, "image/png")

    assets = [
      asset_entry("asset-000001", "duplicate.png", bytes, sha256, blob_path, %{
        "original" => nil,
        "web" => nil,
        "variants" => %{}
      }),
      asset_entry("asset-000002", "duplicate.png", bytes, sha256, blob_path, %{
        "original" => "asset-000001",
        "web" => nil,
        "variants" => %{}
      })
    ]

    blob = %{
      "kind" => "asset_blob",
      "path" => blob_path,
      "sha256" => sha256,
      "size_bytes" => byte_size(bytes),
      "content_type" => "image/png"
    }

    project_object =
      exact_project_object(%{"41" => "asset-000001", "42" => "asset-000002"}, assets)

    project_json = Jason.encode!(project_object)

    project_descriptor = %{
      "kind" => "project",
      "path" => "project.json",
      "sha256" => sha256(project_json),
      "size_bytes" => byte_size(project_json),
      "content_type" => "application/json"
    }

    {:ok, manifest} =
      SnapshotObjectFormat.build_manifest(project_object, assets, [blob], project_descriptor: project_descriptor)

    staging_prefix =
      "projects/#{project_id}/storage-reservations/v1/restore-staging/#{Ecto.UUID.generate()}"

    %{
      bytes: bytes,
      sha256: sha256,
      blob_path: blob_path,
      manifest: manifest,
      project_object: project_object,
      staging_prefix: staging_prefix,
      staging_keys: %{blob_path => staging_prefix <> "/" <> blob_path}
    }
  end

  defp bulk_catalog_fixture(project_id, asset_count) do
    bytes = "x"
    digest = sha256(bytes)
    blob_path = SnapshotObjectFormat.blob_path(digest, "image/png")

    assets =
      Enum.map(1..asset_count, fn index ->
        logical_id = "asset-" <> String.pad_leading(to_string(index), 6, "0")

        relationships = %{
          "original" => if(index == 1, do: nil, else: "asset-000001"),
          "web" => nil,
          "variants" => %{}
        }

        asset_entry(logical_id, "bulk-#{index}.png", bytes, digest, blob_path, relationships)
      end)

    blob = %{
      "kind" => "asset_blob",
      "path" => blob_path,
      "sha256" => digest,
      "size_bytes" => byte_size(bytes),
      "content_type" => "image/png"
    }

    source_refs =
      assets
      |> Enum.with_index(1)
      |> Map.new(fn {asset, index} -> {to_string(10_000 + index), asset["logical_id"]} end)

    project_object = exact_project_object(source_refs, assets)
    project_json = Jason.encode!(project_object)

    project_descriptor = %{
      "kind" => "project",
      "path" => "project.json",
      "sha256" => sha256(project_json),
      "size_bytes" => byte_size(project_json),
      "content_type" => "application/json"
    }

    {:ok, manifest} =
      SnapshotObjectFormat.build_manifest(project_object, assets, [blob], project_descriptor: project_descriptor)

    staging_prefix =
      "projects/#{project_id}/storage-reservations/v1/restore-staging/#{Ecto.UUID.generate()}"

    %{
      manifest: manifest,
      project_object: project_object,
      staging_prefix: staging_prefix,
      staging_keys: %{blob_path => staging_prefix <> "/" <> blob_path}
    }
  end

  defp zero_byte_catalog_fixture(project_id) do
    bytes = ""
    digest = sha256(bytes)
    blob_path = SnapshotObjectFormat.blob_path(digest, "image/png")

    assets = [
      asset_entry("asset-000001", "empty.png", bytes, digest, blob_path, %{
        "original" => "asset-000001",
        "web" => nil,
        "variants" => %{}
      })
    ]

    blob = %{
      "kind" => "asset_blob",
      "path" => blob_path,
      "sha256" => digest,
      "size_bytes" => 0,
      "content_type" => "image/png"
    }

    project_object = %{
      "format_version" => 2,
      "asset_restore_contract_version" => AssetHashResolver.exact_restore_contract_version(),
      "asset_catalog_refs" => %{"41" => "asset-000001"},
      "asset_blob_hashes" => %{"41" => digest},
      "asset_metadata" => %{
        "41" => %{
          "filename" => "empty.png",
          "content_type" => "image/png",
          "size" => 0,
          "persisted_metadata" => %{
            "custom_profile" => %{"label" => "kept exactly"},
            "original_asset_id" => 41
          }
        }
      }
    }

    project_json = Jason.encode!(project_object)

    project_descriptor = %{
      "kind" => "project",
      "path" => "project.json",
      "sha256" => sha256(project_json),
      "size_bytes" => byte_size(project_json),
      "content_type" => "application/json"
    }

    {:ok, manifest} =
      SnapshotObjectFormat.build_manifest(project_object, assets, [blob], project_descriptor: project_descriptor)

    staging_prefix =
      "projects/#{project_id}/storage-reservations/v1/restore-staging/#{Ecto.UUID.generate()}"

    %{
      bytes: bytes,
      sha256: digest,
      blob_path: blob_path,
      manifest: manifest,
      project_object: project_object,
      staging_prefix: staging_prefix,
      staging_keys: %{blob_path => staging_prefix <> "/" <> blob_path}
    }
  end

  defp exact_project_object(source_refs, assets) do
    assets_by_logical_id = Map.new(assets, &{&1["logical_id"], &1})
    source_ids_by_logical_id = Map.new(source_refs, fn {source_id, logical_id} -> {logical_id, source_id} end)

    %{
      "format_version" => 2,
      "asset_restore_contract_version" => AssetHashResolver.exact_restore_contract_version(),
      "asset_catalog_refs" => source_refs,
      "asset_blob_hashes" =>
        Map.new(source_refs, fn {source_id, logical_id} ->
          {source_id, assets_by_logical_id[logical_id]["sha256"]}
        end),
      "asset_metadata" =>
        Map.new(source_refs, fn {source_id, logical_id} ->
          asset = assets_by_logical_id[logical_id]

          {source_id,
           %{
             "filename" => asset["filename"],
             "content_type" => asset["content_type"],
             "size" => asset["size_bytes"],
             "persisted_metadata" => fixture_persisted_metadata(asset["relationships"], source_ids_by_logical_id)
           }}
        end)
    }
  end

  defp fixture_persisted_metadata(%{"original" => nil, "web" => nil, "variants" => variants}, _source_ids)
       when map_size(variants) == 0, do: nil

  defp fixture_persisted_metadata(relationships, source_ids) do
    %{
      "original_asset_id" => fixture_relationship_id(relationships["original"], source_ids),
      "web_asset_id" => fixture_relationship_id(relationships["web"], source_ids),
      "variant_asset_ids" =>
        Map.new(relationships["variants"], fn {profile, logical_id} ->
          {profile, fixture_relationship_id(logical_id, source_ids)}
        end)
    }
  end

  defp fixture_relationship_id(nil, _source_ids), do: nil
  defp fixture_relationship_id(logical_id, source_ids), do: String.to_integer(source_ids[logical_id])

  defp asset_entry(logical_id, filename, bytes, sha256, blob_path, relationships) do
    %{
      "logical_id" => logical_id,
      "filename" => filename,
      "content_type" => "image/png",
      "size_bytes" => byte_size(bytes),
      "sha256" => sha256,
      "blob_path" => blob_path,
      "metadata" => %{"width" => 20, "height" => 10},
      "relationships" => relationships
    }
  end

  defp upload_staging_fixture(fixture) do
    Enum.each(Map.values(fixture.staging_keys), fn key ->
      assert {:ok, _url} = Storage.upload(key, fixture.bytes, "image/png")
    end)
  end

  defp cleanup_fixture_objects(fixture, plan) do
    storage = Storage.adapter()

    Enum.each(Map.values(fixture.staging_keys), &storage.delete/1)
    Enum.each(plan.assets, &storage.delete(&1.destination_key))
    Enum.each(plan.blobs, &delete_storage_blob(&1.destination_key))
  end

  defp unmapped_asset_fixture(project, user, fixture) do
    captured_source_ids =
      fixture.project_object
      |> Map.fetch!("asset_metadata")
      |> Map.keys()
      |> MapSet.new(&String.to_integer/1)

    Enum.find_value(1..10, fn _attempt ->
      asset = asset_fixture(project, user)
      if MapSet.member?(captured_source_ids, asset.id), do: nil, else: asset
    end) || flunk("could not allocate an asset id outside the captured source inventory")
  end

  defp capture_repo_queries(fun) when is_function(fun, 0) do
    handler_id = "snapshot-asset-query-budget-#{System.unique_integer([:positive])}"
    marker = make_ref()
    test_pid = self()

    :ok =
      :telemetry.attach(
        handler_id,
        [:storyarn, :repo, :query],
        fn _event, _measurements, _metadata, {pid, ref} ->
          if self() == pid, do: send(pid, ref)
        end,
        {test_pid, marker}
      )

    try do
      {fun.(), drain_repo_queries(marker)}
    after
      :telemetry.detach(handler_id)
    end
  end

  defp drain_repo_queries(marker, count \\ 0) do
    receive do
      ^marker -> drain_repo_queries(marker, count + 1)
    after
      0 -> List.duplicate(:query, count)
    end
  end

  defp sha256(bytes) do
    :sha256
    |> :crypto.hash(bytes)
    |> Base.encode16(case: :lower)
  end
end
