defmodule Storyarn.Versioning.ProjectSnapshotAssetMaterializerTest do
  use Storyarn.DataCase, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Assets.Asset
  alias Storyarn.Assets.BlobStore
  alias Storyarn.Assets.Storage
  alias Storyarn.Assets.StorageCompensation
  alias Storyarn.Billing
  alias Storyarn.Projects.Project
  alias Storyarn.Repo
  alias Storyarn.Versioning.ProjectSnapshotAssetMaterializer
  alias Storyarn.Versioning.SnapshotObjectFormat

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

  test "rejects entity asset fingerprints that diverge from the manifest before staging", %{project: project} do
    fixture = catalog_fixture(project.id)

    entity_snapshot = %{
      "asset_blob_hashes" => %{"41" => String.duplicate("f", 64)},
      "asset_metadata" => %{
        "41" => %{
          "filename" => "duplicate.png",
          "content_type" => "image/png",
          "size" => byte_size(fixture.bytes)
        }
      }
    }

    project_object = Map.put(fixture.project_object, "sheets", [%{"snapshot" => entity_snapshot}])

    assert {:error, {:pre_materialized_asset_catalog_mismatch, "41"}} =
             ProjectSnapshotAssetMaterializer.prepare(
               project.id,
               1,
               fixture.manifest,
               project_object,
               fixture.staging_prefix,
               fixture.staging_keys
             )
  end

  test "rejects top-level asset fingerprints that diverge from the manifest before staging", %{project: project} do
    fixture = catalog_fixture(project.id)

    project_object =
      fixture.project_object
      |> Map.put("asset_blob_hashes", %{"41" => String.duplicate("0", 64)})
      |> Map.put("asset_metadata", %{
        "41" => %{
          "filename" => "duplicate.png",
          "content_type" => "image/png",
          "size" => byte_size(fixture.bytes)
        }
      })

    assert {:error, {:pre_materialized_asset_catalog_mismatch, "41"}} =
             ProjectSnapshotAssetMaterializer.prepare(
               project.id,
               1,
               fixture.manifest,
               project_object,
               fixture.staging_prefix,
               fixture.staging_keys
             )
  end

  test "rejects a top-level localization voice-over backed by an image before staging", %{project: project} do
    fixture = catalog_fixture(project.id)
    catalogs = fingerprint_catalogs(fixture, "41")

    project_object =
      fixture.project_object
      |> Map.merge(catalogs)
      |> Map.put("localization", %{"texts" => [%{"vo_asset_id" => 41}]})

    assert {:error,
            {:pre_materialized_asset_content_type_mismatch, {:localization_voice_over, :project, 0}, 41, "audio/",
             "image/png"}} =
             ProjectSnapshotAssetMaterializer.prepare(
               project.id,
               1,
               fixture.manifest,
               project_object,
               fixture.staging_prefix,
               fixture.staging_keys
             )
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

  test "rejects a graph asset without its portable fingerprint before staging", %{project: project} do
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

  test "accepts an image-backed sheet slot with an exact portable fingerprint", %{project: project} do
    fixture = catalog_fixture(project.id)
    catalogs = fingerprint_catalogs(fixture, "41")

    sheet_snapshot =
      Map.merge(catalogs, %{
        "avatar_asset_id" => nil,
        "banner_asset_id" => 41,
        "avatars" => [],
        "blocks" => [],
        "localization" => []
      })

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

  test "stages final objects before the transaction and adopts relationships in two phases", %{
    project: project,
    user: user
  } do
    fixture = catalog_fixture(project.id)
    upload_staging_fixture(fixture)

    assert {:ok, plan} = prepare_plan(project.id, fixture)
    tracker = StorageCompensation.new()
    assert :ok = ProjectSnapshotAssetMaterializer.stage_destination_objects(plan, tracker)

    expected_bytes = fixture.bytes

    assert Enum.all?(plan.assets, fn asset ->
             match?({:ok, ^expected_bytes}, Storage.download(asset.destination_key))
           end)

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

    assert map_size(adoption.logical_id_map) == 2
    assert adoption.source_id_map |> Map.keys() |> Enum.sort() == [41, 42]

    original = Repo.get!(Asset, adoption.logical_id_map["asset-000001"])
    derived = Repo.get!(Asset, adoption.logical_id_map["asset-000002"])

    assert derived.metadata["original_asset_id"] == original.id
    assert original.filename == derived.filename
    refute original.key == derived.key
    assert original.blob_hash == derived.blob_hash

    assert :ok = StorageCompensation.cleanup_unretained(tracker)
    assert {:ok, ^expected_bytes} = Storage.download(original.key)
    assert {:ok, ^expected_bytes} = Storage.download(derived.key)

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

    assert [] == Storyarn.Assets.list_assets_for_export(project.id)
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

    project_object = %{
      "format_version" => 2,
      "asset_catalog_refs" => %{"41" => "asset-000001", "42" => "asset-000002"}
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

    project_object = %{"format_version" => 2, "asset_catalog_refs" => source_refs}
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

  defp fingerprint_catalogs(fixture, source_ref) do
    asset =
      Enum.find(fixture.manifest["assets"], fn asset ->
        fixture.project_object["asset_catalog_refs"][source_ref] == asset["logical_id"]
      end)

    %{
      "asset_blob_hashes" => %{source_ref => asset["sha256"]},
      "asset_metadata" => %{
        source_ref => %{
          "filename" => asset["filename"],
          "content_type" => asset["content_type"],
          "size" => asset["size_bytes"]
        }
      }
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
