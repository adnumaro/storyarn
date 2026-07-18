defmodule Storyarn.Versioning.Builders.AssetHashResolverTest do
  use Storyarn.DataCase, async: false

  import Ecto.Query
  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Assets
  alias Storyarn.Assets.Asset
  alias Storyarn.Assets.BlobStore
  alias Storyarn.Assets.Storage
  alias Storyarn.Assets.StorageCompensation
  alias Storyarn.Repo
  alias Storyarn.Versioning.AssetMaterializationCache
  alias Storyarn.Versioning.Builders.AssetCopyError
  alias Storyarn.Versioning.Builders.AssetHashResolver

  setup do
    user = user_fixture()
    project = project_fixture(user)
    %{user: user, project: project}
  end

  describe "resolve_hashes/1" do
    test "returns empty maps for empty input" do
      assert {%{}, %{}} = AssetHashResolver.resolve_hashes([])
    end

    test "returns empty maps for nil-only input" do
      assert {%{}, %{}} = AssetHashResolver.resolve_hashes([nil, nil])
    end

    test "returns hash and metadata for assets", %{project: project, user: user} do
      asset =
        asset_fixture(project, user, %{
          filename: "test.jpg",
          blob_hash: "abc123",
          metadata: %{"sanitized_svg" => true, "web_url" => "/uploads/stale.webp"}
        })

      {hash_map, metadata_map} = AssetHashResolver.resolve_hashes([asset.id])

      id_str = to_string(asset.id)
      assert hash_map[id_str] == "abc123"
      assert metadata_map[id_str]["filename"] == "test.jpg"
      assert metadata_map[id_str]["content_type"] == "image/jpeg"
      assert metadata_map[id_str]["size"] == 12_345
      assert metadata_map[id_str]["sanitized_svg"] == true
      refute Map.has_key?(metadata_map[id_str], "web_url")
    end
  end

  describe "resolve_hashes_for_project!/2" do
    test "returns metadata only when every asset belongs to the project", %{
      project: project,
      user: user
    } do
      {asset, hash} =
        materializable_asset(
          project,
          user,
          "owned versioning asset",
          filename: "owned.jpg",
          content_type: "image/jpeg"
        )

      assert {hashes, metadata} =
               AssetHashResolver.resolve_hashes_for_project!([nil, asset.id, asset.id], project.id)

      assert hashes[to_string(asset.id)] == hash
      assert metadata[to_string(asset.id)]["project_id"] == project.id
    end

    test "rejects missing and cross-project assets", %{project: project, user: user} do
      foreign_project = project_fixture(user)
      foreign_asset = asset_fixture(foreign_project, user)
      missing_asset_id = foreign_asset.id + 10_000_000

      assert_raise ArgumentError, ~r/cannot snapshot missing assets/, fn ->
        AssetHashResolver.resolve_hashes_for_project!([missing_asset_id], project.id)
      end

      assert_raise ArgumentError, ~r/owned by another project/, fn ->
        AssetHashResolver.resolve_hashes_for_project!([foreign_asset.id], project.id)
      end
    end

    test "rejects an invalid SHA256 hash", %{project: project, user: user} do
      asset = asset_fixture(project, user, %{blob_hash: "not-a-sha256"})

      assert_raise ArgumentError, ~r/invalid_blob_hash/, fn ->
        AssetHashResolver.resolve_hashes_for_project!([asset.id], project.id)
      end
    end

    test "rejects a missing canonical blob", %{project: project, user: user} do
      hash = String.duplicate("a", 64)

      asset =
        asset_fixture(project, user, %{
          blob_hash: hash,
          size: 12_345
        })

      assert_raise ArgumentError, ~r/asset_blob_unavailable/, fn ->
        AssetHashResolver.resolve_hashes_for_project!([asset.id], project.id)
      end
    end

    test "rejects a canonical blob whose size differs from the asset row", %{
      project: project,
      user: user
    } do
      content = "blob with authoritative size"
      hash = BlobStore.compute_hash(content)
      {:ok, _key} = BlobStore.ensure_blob(project.id, hash, "jpg", content)

      asset =
        asset_fixture(project, user, %{
          blob_hash: hash,
          size: byte_size(content) + 1
        })

      assert_raise ArgumentError, ~r/asset_blob_size_mismatch/, fn ->
        AssetHashResolver.resolve_hashes_for_project!([asset.id], project.id)
      end
    end
  end

  describe "resolve_asset_fk/4" do
    test "returns nil for nil input" do
      assert nil == AssetHashResolver.resolve_asset_fk(nil, %{}, 1)
    end

    test "returns ID when asset still exists", %{project: project, user: user} do
      asset = asset_fixture(project, user)

      result = AssetHashResolver.resolve_asset_fk(asset.id, %{}, project.id)
      assert result == asset.id
    end

    test "never reuses a foreign asset ID and recreates it in the destination project", %{
      project: destination_project,
      user: user
    } do
      source_project = project_fixture(user)
      content = "cross-project versioned audio"
      hash = BlobStore.compute_hash(content)
      {:ok, _key} = BlobStore.ensure_blob(source_project.id, hash, "mp3", content)

      foreign_asset =
        asset_fixture(source_project, user, %{
          content_type: "audio/mpeg",
          filename: "foreign-track.mp3",
          blob_hash: hash,
          size: byte_size(content)
        })

      {hashes, metadata} = AssetHashResolver.resolve_hashes([foreign_asset.id])

      snapshot = %{
        "asset_blob_hashes" => hashes,
        "asset_metadata" => metadata
      }

      new_id =
        AssetHashResolver.resolve_asset_fk(
          foreign_asset.id,
          snapshot,
          destination_project.id,
          user.id
        )

      refute new_id == foreign_asset.id
      new_asset = Repo.get!(Asset, new_id)
      assert new_asset.project_id == destination_project.id
      assert new_asset.blob_hash == hash
    end

    test "drops or raises instead of returning a foreign ID when blob metadata is unavailable", %{
      project: destination_project,
      user: user
    } do
      source_project = project_fixture(user)
      foreign_asset = asset_fixture(source_project, user)

      assert nil ==
               AssetHashResolver.resolve_asset_fk(
                 foreign_asset.id,
                 %{},
                 destination_project.id,
                 user.id
               )

      error =
        assert_raise AssetCopyError, fn ->
          AssetHashResolver.resolve_asset_fk(
            foreign_asset.id,
            %{},
            destination_project.id,
            user.id,
            asset_error_mode: :strict
          )
        end

      assert error.asset_id == foreign_asset.id
      assert error.reason == :missing_blob_hash
    end

    test "recreates asset from blob when deleted", %{project: project, user: user} do
      content = "audio content for versioning"
      hash = BlobStore.compute_hash(content)
      ext = "mp3"
      {:ok, _key} = BlobStore.ensure_blob(project.id, hash, ext, content)

      asset = asset_fixture(project, user, %{content_type: "audio/mpeg", filename: "track.mp3"})
      asset_id_str = to_string(asset.id)

      snapshot = %{
        "asset_blob_hashes" => %{asset_id_str => hash},
        "asset_metadata" => %{
          asset_id_str => %{
            "filename" => "track.mp3",
            "content_type" => "audio/mpeg",
            "size" => byte_size(content)
          }
        }
      }

      Repo.delete!(asset)

      new_id = AssetHashResolver.resolve_asset_fk(asset.id, snapshot, project.id, user.id)
      assert is_integer(new_id)
      refute new_id == asset.id

      new_asset = Repo.get!(Asset, new_id)
      assert new_asset.filename == "track.mp3"
      assert new_asset.content_type == "audio/mpeg"
      assert new_asset.blob_hash == hash
    end

    test "returns nil when asset deleted and no blob info in snapshot", %{
      project: project,
      user: user
    } do
      asset = asset_fixture(project, user)
      Repo.delete!(asset)

      snapshot = %{"asset_blob_hashes" => %{}, "asset_metadata" => %{}}
      result = AssetHashResolver.resolve_asset_fk(asset.id, snapshot, project.id)
      assert is_nil(result)
    end

    test "returns nil for malformed snapshot asset metadata", %{project: project, user: user} do
      asset_id = 999_991

      snapshot = %{
        "asset_blob_hashes" => %{to_string(asset_id) => "abc123"},
        "asset_metadata" => %{
          to_string(asset_id) => %{"filename" => "broken.png", "content_type" => nil}
        }
      }

      assert nil ==
               AssetHashResolver.resolve_asset_fk(asset_id, snapshot, project.id, user.id, asset_mode: :copy)
    end

    test "raises the domain error for malformed metadata in strict mode", %{project: project, user: user} do
      asset_id = 999_992

      snapshot = %{
        "asset_blob_hashes" => %{to_string(asset_id) => "abc123"},
        "asset_metadata" => %{to_string(asset_id) => %{"content_type" => "image/png"}}
      }

      error =
        assert_raise AssetCopyError, fn ->
          AssetHashResolver.resolve_asset_fk(asset_id, snapshot, project.id, user.id,
            asset_mode: :copy,
            asset_error_mode: :strict
          )
        end

      assert error.asset_id == asset_id
      assert error.reason == :missing_asset_metadata
    end

    test "materializes one destination identity for repeated copy resolution", %{
      project: destination_project,
      user: user
    } do
      source_project = project_fixture(user)

      {source_asset, hash} =
        materializable_asset(
          source_project,
          user,
          "shared versioned audio",
          filename: "shared.mp3",
          content_type: "audio/mpeg"
        )

      snapshot = strict_snapshot(source_asset, source_project.id)
      cache = AssetMaterializationCache.new()

      opts = [
        asset_mode: :copy,
        asset_error_mode: :strict,
        asset_materialization_cache: cache
      ]

      first_id =
        AssetHashResolver.resolve_asset_fk(
          source_asset.id,
          snapshot,
          destination_project.id,
          user.id,
          opts
        )

      second_id =
        AssetHashResolver.resolve_asset_fk(
          source_asset.id,
          snapshot,
          destination_project.id,
          user.id,
          opts
        )

      assert second_id == first_id

      assert 1 ==
               Repo.aggregate(
                 from(asset in Asset,
                   where:
                     asset.project_id == ^destination_project.id and
                       asset.blob_hash == ^hash
                 ),
                 :count
               )
    end

    test "rejects a fingerprint conflict for the same materialization identity", %{
      project: destination_project,
      user: user
    } do
      source_project = project_fixture(user)

      {source_asset, _hash} =
        materializable_asset(
          source_project,
          user,
          "fingerprinted versioned audio",
          filename: "fingerprint.mp3",
          content_type: "audio/mpeg"
        )

      snapshot = strict_snapshot(source_asset, source_project.id)
      cache = AssetMaterializationCache.new()

      opts = [
        asset_mode: :copy,
        asset_error_mode: :strict,
        asset_materialization_cache: cache
      ]

      _destination_id =
        AssetHashResolver.resolve_asset_fk(
          source_asset.id,
          snapshot,
          destination_project.id,
          user.id,
          opts
        )

      conflicting_snapshot =
        put_in(
          snapshot,
          ["asset_metadata", to_string(source_asset.id), "filename"],
          "different-name.mp3"
        )

      error =
        assert_raise AssetCopyError, fn ->
          AssetHashResolver.resolve_asset_fk(
            source_asset.id,
            conflicting_snapshot,
            destination_project.id,
            user.id,
            opts
          )
        end

      assert {:asset_materialization_conflict,
              %{
                target_project_id: destination_project_id,
                source_asset_id: source_asset_id,
                cached_mode: :copy,
                requested_mode: :copy
              }} = error.reason

      assert destination_project_id == destination_project.id
      assert source_asset_id == source_asset.id
    end

    test "rejects a mode conflict for the same materialization identity", %{
      project: destination_project,
      user: user
    } do
      source_project = project_fixture(user)

      {source_asset, _hash} =
        materializable_asset(
          source_project,
          user,
          "mode versioned audio",
          filename: "mode.mp3",
          content_type: "audio/mpeg"
        )

      snapshot = strict_snapshot(source_asset, source_project.id)
      cache = AssetMaterializationCache.new()

      _destination_id =
        AssetHashResolver.resolve_asset_fk(
          source_asset.id,
          snapshot,
          destination_project.id,
          user.id,
          asset_mode: :copy,
          asset_error_mode: :strict,
          asset_materialization_cache: cache
        )

      error =
        assert_raise AssetCopyError, fn ->
          AssetHashResolver.resolve_asset_fk(
            source_asset.id,
            snapshot,
            destination_project.id,
            user.id,
            asset_mode: :reuse,
            asset_error_mode: :strict,
            asset_materialization_cache: cache
          )
        end

      assert {:asset_materialization_conflict, %{cached_mode: :copy, requested_mode: :reuse}} = error.reason
    end

    test "rejects a cached destination that no longer exists", %{
      project: destination_project,
      user: user
    } do
      source_project = project_fixture(user)

      {source_asset, _hash} =
        materializable_asset(
          source_project,
          user,
          "stale versioned audio",
          filename: "stale.mp3",
          content_type: "audio/mpeg"
        )

      snapshot = strict_snapshot(source_asset, source_project.id)
      cache = AssetMaterializationCache.new()

      opts = [
        asset_mode: :copy,
        asset_error_mode: :strict,
        asset_materialization_cache: cache
      ]

      destination_id =
        AssetHashResolver.resolve_asset_fk(
          source_asset.id,
          snapshot,
          destination_project.id,
          user.id,
          opts
        )

      Asset
      |> Repo.get!(destination_id)
      |> Repo.delete!()

      error =
        assert_raise AssetCopyError, fn ->
          AssetHashResolver.resolve_asset_fk(
            source_asset.id,
            snapshot,
            destination_project.id,
            user.id,
            opts
          )
        end

      assert {:stale_asset_materialization, %{destination_asset_id: ^destination_id}} = error.reason
    end

    test "rejects a cached destination whose persisted identity changed", %{
      project: destination_project,
      user: user
    } do
      source_project = project_fixture(user)

      {source_asset, _hash} =
        materializable_asset(
          source_project,
          user,
          "mutated destination audio",
          filename: "immutable.mp3",
          content_type: "audio/mpeg"
        )

      snapshot = strict_snapshot(source_asset, source_project.id)
      cache = AssetMaterializationCache.new()

      opts = [
        asset_mode: :copy,
        asset_error_mode: :strict,
        asset_materialization_cache: cache
      ]

      destination_id =
        AssetHashResolver.resolve_asset_fk(
          source_asset.id,
          snapshot,
          destination_project.id,
          user.id,
          opts
        )

      Repo.update_all(
        from(asset in Asset, where: asset.id == ^destination_id),
        set: [filename: "mutated.mp3"]
      )

      error =
        assert_raise AssetCopyError, fn ->
          AssetHashResolver.resolve_asset_fk(
            source_asset.id,
            snapshot,
            destination_project.id,
            user.id,
            opts
          )
        end

      assert {:stale_asset_materialization, %{destination_asset_id: ^destination_id}} = error.reason
    end

    test "strict copy derives the canonical blob key instead of trusting snapshot keys", %{
      project: destination_project,
      user: user
    } do
      source_project = project_fixture(user)

      {source_asset, _hash} =
        materializable_asset(
          source_project,
          user,
          "canonical source audio",
          filename: "canonical.mp3",
          content_type: "audio/mpeg"
        )

      id = to_string(source_asset.id)

      snapshot =
        source_asset
        |> strict_snapshot(source_project.id)
        |> put_in(["asset_metadata", id, "blob_key"], "projects/999/blobs/foreign.mp3")
        |> put_in(["asset_metadata", id, "key"], "projects/999/assets/foreign.mp3")

      destination_id =
        AssetHashResolver.resolve_asset_fk(
          source_asset.id,
          snapshot,
          destination_project.id,
          user.id,
          asset_mode: :copy,
          asset_error_mode: :strict
        )

      assert %Asset{project_id: project_id} = Repo.get!(Asset, destination_id)
      assert project_id == destination_project.id
    end

    test "strict copy accepts a caller-verified portable source key", %{
      project: destination_project,
      user: user
    } do
      source_project = project_fixture(user)
      content = "portable source audio"
      blob_hash = BlobStore.compute_hash(content)
      source_key = "project_templates/imported_blobs/test/#{blob_hash}/portable.mp3"
      {:ok, _url} = Storage.upload(source_key, content, "audio/mpeg")
      on_exit(fn -> Storage.delete(source_key) end)

      source_asset =
        asset_fixture(source_project, user, %{
          filename: "portable.mp3",
          content_type: "audio/mpeg",
          size: byte_size(content),
          blob_hash: blob_hash
        })

      snapshot = %{
        "asset_blob_hashes" => %{to_string(source_asset.id) => blob_hash},
        "asset_metadata" => %{
          to_string(source_asset.id) => %{
            "filename" => "portable.mp3",
            "content_type" => "audio/mpeg",
            "size" => byte_size(content),
            "project_id" => source_project.id,
            "blob_key" => "snapshot/keys/are/not/trusted.mp3"
          }
        }
      }

      destination_id =
        AssetHashResolver.resolve_asset_fk(
          source_asset.id,
          snapshot,
          destination_project.id,
          user.id,
          asset_mode: :copy,
          asset_error_mode: :strict,
          asset_source_keys: %{blob_hash => source_key}
        )

      destination_asset = Repo.get!(Asset, destination_id)
      on_exit(fn -> Storage.delete(destination_asset.key) end)
      assert destination_asset.project_id == destination_project.id
      assert {:ok, ^content} = Storage.download(destination_asset.key)
    end

    test "strict copy rejects same-sized portable bytes whose SHA256 differs from the catalogued hash", %{
      project: destination_project,
      user: user
    } do
      source_project = project_fixture(user)
      expected_content = "expected"
      corrupted_content = "tampered"
      blob_hash = BlobStore.compute_hash(expected_content)
      actual_hash = BlobStore.compute_hash(corrupted_content)
      source_key = "project_templates/imported_blobs/test/corrupt/#{blob_hash}/blob"

      assert byte_size(corrupted_content) == byte_size(expected_content)
      assert {:ok, _url} = Storage.upload(source_key, corrupted_content, "audio/mpeg")
      on_exit(fn -> Storage.delete(source_key) end)

      source_asset =
        asset_fixture(source_project, user, %{
          filename: "corrupt.mp3",
          content_type: "audio/mpeg",
          size: byte_size(expected_content),
          blob_hash: blob_hash
        })

      snapshot = %{
        "asset_blob_hashes" => %{to_string(source_asset.id) => blob_hash},
        "asset_metadata" => %{
          to_string(source_asset.id) => %{
            "filename" => "corrupt.mp3",
            "content_type" => "audio/mpeg",
            "size" => byte_size(expected_content),
            "project_id" => source_project.id
          }
        }
      }

      error =
        assert_raise AssetCopyError, fn ->
          AssetHashResolver.resolve_asset_fk(
            source_asset.id,
            snapshot,
            destination_project.id,
            user.id,
            asset_mode: :copy,
            asset_error_mode: :strict,
            asset_source_keys: %{blob_hash => source_key}
          )
        end

      assert error.reason ==
               {:asset_blob_checksum_mismatch, blob_hash, actual_hash}

      assert [] == Assets.list_assets(destination_project.id)
    end

    test "strict copy rejects filenames whose sanitized value is not a safe storage segment", %{
      project: destination_project,
      user: user
    } do
      isolated_upload_dir = isolate_storage!()
      source_project = project_fixture(user)

      {source_asset, _blob_hash} =
        materializable_asset(
          source_project,
          user,
          "invalid filename source",
          filename: "valid.mp3",
          content_type: "audio/mpeg"
        )

      snapshot = strict_snapshot(source_asset, source_project.id)
      storage_before = storage_files(isolated_upload_dir)
      tracker = StorageCompensation.new()

      for invalid_filename <- ["/", ".", ".."] do
        invalid_snapshot =
          put_in(
            snapshot,
            ["asset_metadata", to_string(source_asset.id), "filename"],
            invalid_filename
          )

        error =
          assert_raise AssetCopyError, fn ->
            AssetHashResolver.resolve_asset_fk(
              source_asset.id,
              invalid_snapshot,
              destination_project.id,
              user.id,
              asset_mode: :copy,
              asset_error_mode: :strict,
              asset_copy_tracker: tracker
            )
          end

        assert error.reason == :invalid_asset_filename
      end

      assert [] == Assets.list_assets(destination_project.id)
      assert storage_files(isolated_upload_dir) == storage_before
      assert :ok = StorageCompensation.cleanup(tracker)
      assert storage_files(isolated_upload_dir) == storage_before
    end

    test "portable materialization drops untrusted metadata before persistence", %{
      project: destination_project,
      user: user
    } do
      source_project = project_fixture(user)

      {source_asset, blob_hash} =
        materializable_asset(
          source_project,
          user,
          "metadata whitelist source",
          filename: "whitelist.mp3",
          content_type: "audio/mpeg"
        )

      external_key = "projects/#{source_project.id}/assets/external/thumbnail.png"
      {:ok, _url} = Storage.upload(external_key, "external thumbnail", "image/png")
      on_exit(fn -> Storage.delete(external_key) end)

      snapshot =
        source_asset
        |> strict_snapshot(source_project.id)
        |> put_in(
          ["asset_metadata", to_string(source_asset.id), "thumbnail_key"],
          external_key
        )
        |> put_in(
          ["asset_metadata", to_string(source_asset.id), "web_url"],
          "/media/foreign"
        )

      destination_id =
        AssetHashResolver.resolve_asset_fk(
          source_asset.id,
          snapshot,
          destination_project.id,
          user.id,
          asset_mode: :copy,
          asset_error_mode: :strict,
          asset_source_keys: %{
            blob_hash => BlobStore.blob_key(source_project.id, blob_hash, "mp3")
          }
        )

      destination_asset = Repo.get!(Asset, destination_id)
      assert destination_asset.metadata == %{}

      assert {:ok, _deleted_asset} = Assets.delete_asset(destination_asset)
      assert :ok = Storage.delete(destination_asset.key)
      assert {:ok, "external thumbnail"} = Storage.download(external_key)
    end

    test "portable materialization rejects SVG even when snapshot metadata claims sanitization", %{
      project: destination_project,
      user: user
    } do
      source_project = project_fixture(user)
      content = ~S|<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>|
      blob_hash = BlobStore.compute_hash(content)
      source_key = "project_templates/imported_blobs/svg/test/#{blob_hash}/blob"
      {:ok, _url} = Storage.upload(source_key, content, "image/svg+xml")
      on_exit(fn -> Storage.delete(source_key) end)
      source_asset_id = System.unique_integer([:positive])

      snapshot = %{
        "asset_blob_hashes" => %{to_string(source_asset_id) => blob_hash},
        "asset_metadata" => %{
          to_string(source_asset_id) => %{
            "filename" => "unsafe.svg",
            "content_type" => "image/svg+xml",
            "size" => byte_size(content),
            "project_id" => source_project.id,
            "sanitized_svg" => true
          }
        }
      }

      error =
        assert_raise AssetCopyError, fn ->
          AssetHashResolver.resolve_asset_fk(
            source_asset_id,
            snapshot,
            destination_project.id,
            user.id,
            asset_mode: :copy,
            asset_error_mode: :strict,
            asset_source_keys: %{blob_hash => source_key}
          )
        end

      assert error.reason == :unsupported_portable_svg
      assert [] == Assets.list_assets(destination_project.id)
    end

    test "an explicit source catalog is exhaustive and never falls back to snapshot or canonical keys", %{
      project: destination_project,
      user: user
    } do
      source_project = project_fixture(user)

      {source_asset, _blob_hash} =
        materializable_asset(
          source_project,
          user,
          "catalogued source audio",
          filename: "catalogued.mp3",
          content_type: "audio/mpeg"
        )

      snapshot = strict_snapshot(source_asset, source_project.id)

      error =
        assert_raise AssetCopyError, fn ->
          AssetHashResolver.resolve_asset_fk(
            source_asset.id,
            snapshot,
            destination_project.id,
            user.id,
            asset_mode: :copy,
            asset_error_mode: :strict,
            asset_source_keys: %{}
          )
        end

      assert error.reason == :missing_asset_source_key
    end
  end

  defp materializable_asset(project, user, content, attrs) do
    content_type = Keyword.fetch!(attrs, :content_type)
    filename = Keyword.fetch!(attrs, :filename)
    hash = BlobStore.compute_hash(content)
    ext = BlobStore.ext_from_content_type(content_type)
    {:ok, _key} = BlobStore.ensure_blob(project.id, hash, ext, content)

    asset =
      asset_fixture(project, user, %{
        filename: filename,
        content_type: content_type,
        size: byte_size(content),
        blob_hash: hash
      })

    {asset, hash}
  end

  defp strict_snapshot(asset, project_id) do
    {hashes, metadata} =
      AssetHashResolver.resolve_hashes_for_project!([asset.id], project_id)

    %{
      "asset_blob_hashes" => hashes,
      "asset_metadata" => metadata
    }
  end

  defp isolate_storage! do
    original_storage_config = Application.fetch_env!(:storyarn, :storage)

    isolated_upload_dir =
      Path.join(
        System.tmp_dir!(),
        "storyarn-asset-resolver-#{System.unique_integer([:positive])}"
      )

    Application.put_env(
      :storyarn,
      :storage,
      Keyword.put(original_storage_config, :upload_dir, isolated_upload_dir)
    )

    on_exit(fn ->
      Application.put_env(:storyarn, :storage, original_storage_config)
      File.rm_rf!(isolated_upload_dir)
    end)

    isolated_upload_dir
  end

  defp storage_files(upload_dir) do
    upload_dir
    |> Path.join("**/*")
    |> Path.wildcard()
    |> Enum.reject(&File.dir?/1)
    |> Enum.map(&Path.relative_to(&1, upload_dir))
    |> Enum.sort()
  end
end
