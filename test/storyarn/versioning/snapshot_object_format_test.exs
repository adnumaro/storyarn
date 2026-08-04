defmodule Storyarn.Versioning.SnapshotObjectFormatTest do
  use ExUnit.Case, async: true

  alias Storyarn.Assets.Asset
  alias Storyarn.Versioning.SnapshotObjectFormat

  @hash String.duplicate("a", 64)

  describe "build_catalog/2" do
    test "keeps duplicate filenames distinct while sharing identical verified content" do
      original = asset(41, "portrait.png", @hash, %{"variant_asset_ids" => %{"avatar" => 42}})

      variant =
        asset(42, "portrait.png", @hash, %{
          "is_variant" => true,
          "original_asset_id" => 41,
          "variant_profile" => "avatar",
          "web_url" => "https://storage.invalid/current-object"
        })

      assert {:ok, catalog} = SnapshotObjectFormat.build_catalog([variant, original])

      assert length(catalog.assets) == 2
      assert length(catalog.blobs) == 1
      assert map_size(catalog.source_keys) == 1

      [first, second] = catalog.assets
      assert first["logical_id"] == "asset-000001"
      assert second["logical_id"] == "asset-000002"
      assert first["filename"] == second["filename"]
      assert first["blob_path"] == second["blob_path"]
      assert first["relationships"]["variants"] == %{"avatar" => "asset-000002"}
      assert second["relationships"]["original"] == "asset-000001"
      refute Map.has_key?(second["metadata"], "web_url")
    end

    test "fails closed on dangling asset relationships" do
      dangling = asset(41, "portrait.png", @hash, %{"original_asset_id" => 999})

      assert {:error, {:dangling_asset_relationship, 999}} =
               SnapshotObjectFormat.build_catalog([dangling])
    end

    test "rejects unsafe intrinsic metadata and configured limits" do
      unsafe = asset(41, "portrait.png", @hash, %{"nested" => %{"download_url" => "https://example.test"}})

      assert {:error, {:unsafe_asset_metadata_key, "download_url"}} =
               SnapshotObjectFormat.build_catalog([unsafe])

      assert {:error, {:collection_limit_exceeded, :assets, 0}} =
               SnapshotObjectFormat.build_catalog([asset(41, "portrait.png", @hash)], max_assets: 0)
    end

    test "rejects malformed collections and mixed-project source ownership" do
      assert {:error, :invalid_asset_collection} =
               SnapshotObjectFormat.build_catalog([asset(41, "portrait.png", @hash), :invalid])

      foreign_asset = %{asset(42, "foreign.png", @hash) | project_id: 8}

      assert {:error, {:asset_project_mismatch, 7, [7, 8]}} =
               SnapshotObjectFormat.build_catalog([asset(41, "portrait.png", @hash), foreign_asset])

      wrong_key = %{
        asset(43, "wrong-key.png", @hash)
        | key: "projects/8/assets/00000000-0000-0000-0000-000000000003/wrong-key.png"
      }

      assert {:error, {:asset_source_project_mismatch, 7, _key}} =
               SnapshotObjectFormat.build_catalog([wrong_key])
    end
  end

  describe "manifest validation" do
    test "validates the exact inventory and rejects count or path tampering" do
      asset = asset(41, "portrait.png", @hash)
      assert {:ok, catalog} = SnapshotObjectFormat.build_catalog([asset])

      project = %{"format_version" => 2, "project" => %{"name" => "Portable"}}
      project_json = Jason.encode!(project)

      project_descriptor = %{
        "kind" => "project",
        "path" => "project.json",
        "sha256" => sha256(project_json),
        "size_bytes" => byte_size(project_json),
        "content_type" => "application/json"
      }

      assert {:ok, manifest} =
               SnapshotObjectFormat.build_manifest(
                 project,
                 catalog.assets,
                 catalog.blobs,
                 project_descriptor: project_descriptor
               )

      assert :ok = SnapshotObjectFormat.validate_manifest(manifest)

      assert {:error, {:snapshot_object_count_mismatch, _expected, _actual}} =
               manifest
               |> put_in(["counts", "assets"], 9)
               |> SnapshotObjectFormat.validate_manifest()

      assert {:error, {:unsafe_snapshot_object_path, "../escape.png"}} =
               manifest
               |> put_in(["objects", Access.at(1), "path"], "../escape.png")
               |> SnapshotObjectFormat.validate_manifest()

      extra_hash = String.duplicate("b", 64)

      extra_object = %{
        "kind" => "asset_blob",
        "path" => "blobs/#{extra_hash}.png",
        "sha256" => extra_hash,
        "size_bytes" => 1,
        "content_type" => "image/png"
      }

      manifest_with_extra =
        manifest
        |> update_in(["objects"], &(&1 ++ [extra_object]))
        |> put_in(["counts", "blobs"], 2)
        |> put_in(["counts", "payload_objects"], 3)
        |> update_in(["payload_size_bytes"], &(&1 + 1))

      assert {:error, :asset_blob_inventory_mismatch} =
               SnapshotObjectFormat.validate_manifest(manifest_with_extra)
    end

    test "rejects unsupported versions and storage durability in project.json" do
      assert {:error, {:unsupported_snapshot_object_format, 2}} =
               SnapshotObjectFormat.validate_manifest(%{
                 "format" => SnapshotObjectFormat.format(),
                 "format_version" => 2
               })

      assert {:error, {:unsafe_project_metadata_key, "url"}} =
               SnapshotObjectFormat.validate_project(%{
                 "format_version" => 2,
                 "asset_metadata" => %{"1" => %{"url" => "https://storage.invalid"}}
               })

      assert {:error, {:invalid_snapshot_object_limit, :max_asset_bytes, "large"}} =
               SnapshotObjectFormat.build_catalog(
                 [asset(41, "portrait.png", @hash)],
                 max_asset_bytes: "large"
               )
    end
  end

  defp asset(id, filename, hash, metadata \\ %{}) do
    %Asset{
      id: id,
      project_id: 7,
      filename: filename,
      content_type: "image/png",
      size: 12,
      blob_hash: hash,
      key: "projects/7/assets/00000000-0000-0000-0000-00000000000#{rem(id, 10)}/#{filename}",
      url: "https://storage.invalid/#{id}",
      metadata: metadata,
      inserted_at: DateTime.from_unix!(id)
    }
  end

  defp sha256(data) do
    data
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end
end
