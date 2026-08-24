defmodule Storyarn.Projects.Versioning.SnapshotObjectFormatTest do
  use ExUnit.Case, async: true

  alias Storyarn.Projects.Assets.Asset
  alias Storyarn.Projects.Versioning.SnapshotObjectFormat

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

      assert catalog.source_refs == %{
               "41" => "asset-000001",
               "42" => "asset-000002"
             }

      assert map_size(catalog.source_keys) == 1
      assert :ok = SnapshotObjectFormat.validate_source_refs(catalog.source_refs, catalog.assets)

      [first, second] = catalog.assets
      assert first["logical_id"] == "asset-000001"
      assert second["logical_id"] == "asset-000002"
      assert first["filename"] == second["filename"]
      assert first["blob_path"] == second["blob_path"]
      assert first["relationships"]["variants"] == %{"avatar" => "asset-000002"}
      assert second["relationships"]["original"] == "asset-000001"
      refute Map.has_key?(second["metadata"], "web_url")
    end

    test "validates source reference shape, uniqueness, and exact catalog coverage" do
      assert {:ok, catalog} =
               SnapshotObjectFormat.build_catalog([
                 asset(41, "first.png", @hash),
                 asset(42, "second.png", String.duplicate("b", 64))
               ])

      assert {:error, :invalid_asset_source_refs} =
               SnapshotObjectFormat.validate_source_refs(
                 Map.put(catalog.source_refs, "43", "asset-000001"),
                 catalog.assets
               )

      assert {:error, :invalid_asset_source_refs} =
               SnapshotObjectFormat.validate_source_refs(
                 %{"041" => "asset-000001", "42" => "asset-000002"},
                 catalog.assets
               )

      assert {:error, :asset_source_refs_mismatch} =
               SnapshotObjectFormat.validate_source_refs(
                 Map.delete(catalog.source_refs, "42"),
                 catalog.assets
               )

      assert {:error, :invalid_asset_source_refs} =
               SnapshotObjectFormat.validate_source_refs(
                 %{"9223372036854775808" => "asset-000001", "42" => "asset-000002"},
                 catalog.assets
               )
    end

    test "fails closed on dangling asset relationships" do
      dangling = asset(41, "portrait.png", @hash, %{"original_asset_id" => 999})

      assert {:error, {:dangling_asset_relationship, 999}} =
               SnapshotObjectFormat.build_catalog([dangling])
    end

    test "can omit every unmaterializable relationship shape for a restore-blocked archive" do
      assets = [
        asset(41, "dangling-original.png", @hash, %{"original_asset_id" => 999}),
        asset(42, "invalid-web.png", String.duplicate("b", 64), %{"web_asset_id" => [41]}),
        asset(43, "invalid-variants.png", String.duplicate("c", 64), %{
          "variant_asset_ids" => "not-an-object"
        }),
        asset(44, "mixed-variants.png", String.duplicate("d", 64), %{
          "variant_asset_ids" => %{"valid" => 41, "UPPER CASE" => 42, "missing" => 999}
        })
      ]

      assert {:ok, catalog} =
               SnapshotObjectFormat.build_catalog(assets,
                 asset_content_mode: :omit_unmaterializable
               )

      by_id = Map.new(catalog.assets, &{&1["logical_id"], &1})
      assert by_id["asset-000001"]["relationships"]["original"] == nil
      assert by_id["asset-000002"]["relationships"]["web"] == nil
      assert by_id["asset-000003"]["relationships"]["variants"] == %{}

      assert by_id["asset-000004"]["relationships"]["variants"] == %{
               "valid" => "asset-000001"
             }
    end

    test "admits a zero-byte asset through the exact capture catalog" do
      empty = %{asset(41, "empty.png", sha256("")) | size: 0}

      assert {:error, {:invalid_size, :asset, 0}} =
               SnapshotObjectFormat.build_catalog([empty])

      assert {:ok, catalog} =
               SnapshotObjectFormat.build_catalog([empty],
                 asset_content_mode: :omit_unmaterializable
               )

      assert [%{"size_bytes" => 0, "sha256" => hash}] = catalog.assets
      assert hash == sha256("")
      assert [%{"size_bytes" => 0, "sha256" => ^hash}] = catalog.blobs
    end

    test "rejects unsafe intrinsic metadata and configured limits" do
      unsafe = asset(41, "portrait.png", @hash, %{"nested" => %{"download_url" => "https://example.test"}})

      assert {:error, {:unsafe_asset_metadata_key, "download_url"}} =
               SnapshotObjectFormat.build_catalog([unsafe])

      assert {:error, {:collection_limit_exceeded, :assets, 0}} =
               SnapshotObjectFormat.build_catalog([asset(41, "portrait.png", @hash)], max_assets: 0)
    end

    test "rejects plural and camel-case durability metadata without matching ordinary words" do
      for key <- [
            "asset_ids",
            "storage_keys",
            "storageKeys",
            "presignedUrls",
            "thumbnailPaths",
            "currentObjectID"
          ] do
        unsafe = asset(41, "portrait.png", @hash, %{"nested" => %{key => "current-object"}})

        assert {:error, {:unsafe_asset_metadata_key, ^key}} =
                 SnapshotObjectFormat.build_catalog([unsafe])
      end

      safe =
        asset(41, "portrait.png", @hash, %{
          "grid" => "twelve-column",
          "monkey" => "capuchin",
          "pathology" => "none",
          "identity" => "portable"
        })

      assert {:ok, %{assets: [%{"metadata" => metadata}]}} =
               SnapshotObjectFormat.build_catalog([safe])

      assert metadata["grid"] == "twelve-column"
      assert metadata["monkey"] == "capuchin"
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

    test "requires one positive unique database id per logical asset" do
      first = asset(41, "first.png", @hash)
      duplicate_id = asset(41, "second.png", @hash)

      assert {:error, {:duplicate_asset_ids, [41]}} =
               SnapshotObjectFormat.build_catalog([first, duplicate_id])

      assert {:error, {:duplicate_asset_ids, [41]}} =
               SnapshotObjectFormat.build_catalog([first, first])

      for invalid_id <- [nil, 0, -1] do
        invalid = %{first | id: invalid_id}

        assert {:error, {:invalid_asset_ids, [^invalid_id]}} =
                 SnapshotObjectFormat.build_catalog([invalid])
      end
    end
  end

  describe "manifest validation" do
    test "sums logical asset bytes instead of deduplicated blob bytes" do
      first = asset(41, "first.png", @hash)
      second = asset(42, "second.png", @hash)
      assert {:ok, catalog} = SnapshotObjectFormat.build_catalog([first, second])
      assert length(catalog.assets) == 2
      assert length(catalog.blobs) == 1

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

      assert {:ok, 24} = SnapshotObjectFormat.logical_asset_bytes(manifest)

      assert {:error, {:snapshot_object_count_mismatch, _expected, _actual}} =
               manifest
               |> put_in(["counts", "assets"], 1)
               |> SnapshotObjectFormat.logical_asset_bytes()
    end

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

    test "scrubs only structural storage catalogs while retaining user content keys" do
      project = %{
        "format_version" => 2,
        "project" => %{"id" => 41, "project_id" => 7},
        "sheets" => [
          %{
            "id" => 101,
            "parent_id" => 41,
            "grid" => "twelve-column",
            "nested" => %{
              "storageKeys" => ["current/key"],
              "presignedUrls" => ["https://storage.invalid/current"],
              "thumbnailPaths" => ["current/thumb.png"]
            }
          }
        ]
      }

      assert {:ok, portable} = SnapshotObjectFormat.portable_project(project)
      assert portable["project"]["id"] == 41
      refute Map.has_key?(portable["project"], "project_id")
      assert get_in(portable, ["sheets", Access.at(0), "id"]) == 101
      assert get_in(portable, ["sheets", Access.at(0), "parent_id"]) == 41
      assert get_in(portable, ["sheets", Access.at(0), "grid"]) == "twelve-column"

      assert get_in(portable, ["sheets", Access.at(0), "nested"]) == %{
               "storageKeys" => ["current/key"],
               "presignedUrls" => ["https://storage.invalid/current"],
               "thumbnailPaths" => ["current/thumb.png"]
             }

      assert :ok = SnapshotObjectFormat.validate_project(portable)
    end

    test "reader validates portable asset catalog references when present" do
      project = %{
        "format_version" => 2,
        "asset_catalog_refs" => %{"41" => "asset-000001"}
      }

      assert :ok = SnapshotObjectFormat.validate_project(project)

      assert {:error, :invalid_asset_source_refs} =
               project
               |> put_in(["asset_catalog_refs", "41"], "asset-current-storage-key")
               |> SnapshotObjectFormat.validate_project()
    end

    test "reader retains locator-shaped names outside structural storage catalogs" do
      for key <- [
            "storage_keys",
            "storageKeys",
            "presigned_url",
            "presignedUrls",
            "thumbnail_paths",
            "thumbnailPaths",
            "currentObjectUrls",
            "projectId"
          ] do
        project = %{
          "format_version" => 2,
          "sheets" => [%{"id" => 101, "nested" => %{key => "current-object"}}]
        }

        assert :ok = SnapshotObjectFormat.validate_project(project)
      end

      assert :ok =
               SnapshotObjectFormat.validate_project(%{
                 "format_version" => 2,
                 "sheets" => [%{"id" => 101, "parent_id" => 41, "grid" => "safe"}]
               })
    end
  end

  describe "portable_project/1" do
    test "preserves URL-shaped user content while removing generated catalog locators" do
      project = %{
        "format_version" => 2,
        "project" => %{"name" => "Portable"},
        "flows" => [
          %{
            "id" => 9,
            "snapshot" => %{
              "nodes" => [
                %{
                  "data" => %{
                    "options" => [%{"key" => "opt1", "url" => "https://content.invalid"}]
                  }
                }
              ],
              "asset_metadata" => %{
                "41" => %{
                  "filename" => "portrait.png",
                  "key" => "projects/7/assets/current/portrait.png",
                  "url" => "https://storage.invalid/portrait.png",
                  "original_asset_id" => 99,
                  "variant_asset_ids" => %{"url" => 100},
                  "persisted_metadata" => %{
                    "caption" => "Authored asset caption",
                    "custom_url" => "https://content.invalid/asset",
                    "variant_asset_ids" => %{"url" => 100},
                    "nested" => %{
                      "key" => "projects/7/assets/current/nested.png",
                      "url" => "https://storage.invalid/nested.png",
                      "storage_key" => "projects/7/assets/current/storage.png",
                      "project_id" => 7,
                      "label" => "Retained metadata",
                      "items" => [
                        %{
                          "url" => "https://storage.invalid/item.png",
                          "label" => "Retained list metadata"
                        }
                      ]
                    }
                  }
                }
              },
              "referenced_sheets" => %{
                "12" => %{
                  "id" => 12,
                  "name" => "Hero",
                  "avatar_url" => "https://storage.invalid/avatar.png",
                  "banner_url" => "/media/assets/42"
                }
              }
            }
          }
        ]
      }

      assert {:ok, portable} = SnapshotObjectFormat.portable_project(project)
      [flow] = portable["flows"]
      snapshot = flow["snapshot"]

      assert get_in(snapshot, ["nodes", Access.at(0), "data", "options"]) == [
               %{"key" => "opt1", "url" => "https://content.invalid"}
             ]

      assert snapshot["asset_metadata"]["41"] == %{
               "filename" => "portrait.png",
               "original_asset_id" => 99,
               "variant_asset_ids" => %{"url" => 100},
               "persisted_metadata" => %{
                 "caption" => "Authored asset caption",
                 "custom_url" => "https://content.invalid/asset",
                 "variant_asset_ids" => %{"url" => 100},
                 "nested" => %{
                   "label" => "Retained metadata",
                   "items" => [%{"label" => "Retained list metadata"}]
                 }
               }
             }

      assert snapshot["referenced_sheets"]["12"] == %{"id" => 12, "name" => "Hero"}
      assert :ok = SnapshotObjectFormat.validate_project(portable)

      assert {:error, {:unsafe_project_metadata_key, unsafe_key}} =
               SnapshotObjectFormat.validate_project(project)

      assert unsafe_key in ["key", "url", "avatar_url", "banner_url"]
    end

    test "reader rejects storage locators nested in persisted asset metadata" do
      for key <- ~w(key url storage_key project_id) do
        project = %{
          "format_version" => 2,
          "asset_metadata" => %{
            "41" => %{
              "persisted_metadata" => %{
                "safe" => %{
                  "nested" => [%{"label" => "retained", key => "current-storage-locator"}]
                }
              }
            }
          }
        }

        assert {:error, {:unsafe_project_metadata_key, ^key}} =
                 SnapshotObjectFormat.validate_project(project)
      end
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
