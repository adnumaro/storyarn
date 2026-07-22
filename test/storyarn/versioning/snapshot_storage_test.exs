defmodule Storyarn.Versioning.SnapshotStorageTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Assets.Storage
  alias Storyarn.Versioning.SnapshotStorage

  describe "store_snapshot/5" do
    test "stores compressed JSON and returns key and size" do
      snapshot = %{"name" => "Test", "blocks" => [%{"type" => "text"}]}

      assert {:ok, key, size_bytes} =
               SnapshotStorage.store_snapshot(1, "sheet", 42, 1, snapshot)

      assert key == "projects/1/snapshots/sheet/42/1.json.gz"
      assert size_bytes > 0
    end

    test "returns the checksum when requested by entity versioning" do
      snapshot = %{"name" => "Bound entity version"}

      assert {:ok, key, size_bytes, checksum} =
               SnapshotStorage.store_snapshot_with_checksum(
                 1,
                 "sheet",
                 42,
                 1,
                 snapshot
               )

      assert key == "projects/1/snapshots/sheet/42/1.json.gz"
      assert size_bytes > 0
      assert checksum =~ ~r/\A[0-9a-f]{64}\z/

      assert {:ok, ^snapshot, ^checksum} =
               SnapshotStorage.load_verified_snapshot(key, size_bytes, checksum)
    end

    test "stores snapshots with a unique suffix when provided" do
      snapshot = %{"name" => "Test"}

      assert {:ok, key, size_bytes} =
               SnapshotStorage.store_snapshot(1, "sheet", 42, 1, snapshot, "abc123")

      assert key == "projects/1/snapshots/sheet/42/1-abc123.json.gz"
      assert size_bytes > 0
    end
  end

  describe "load_snapshot/1" do
    test "loads and decompresses a stored snapshot" do
      snapshot = %{"name" => "My Sheet", "blocks" => [%{"type" => "number", "position" => 0}]}

      {:ok, key, _size} = SnapshotStorage.store_snapshot(1, "sheet", 42, 1, snapshot)
      assert {:ok, loaded} = SnapshotStorage.load_snapshot(key)
      assert loaded == snapshot
    end

    test "returns error for non-existent key" do
      assert {:error, _} = SnapshotStorage.load_snapshot("nonexistent/key.json.gz")
    end

    test "returns a checksum for the exact compressed bytes stored" do
      key = "projects/1/snapshots/project/checksummed.json.gz"
      snapshot = %{"format_version" => 2, "project" => %{"name" => "Checksum"}}

      assert {:ok, size, checksum} =
               SnapshotStorage.store_raw_with_checksum(key, snapshot)

      assert size > 0
      assert checksum =~ ~r/\A[0-9a-f]{64}\z/

      assert {:ok, ^snapshot, ^checksum} =
               SnapshotStorage.load_snapshot_with_checksum(key)

      assert :ok = SnapshotStorage.delete_snapshot(key)
    end

    test "streams snapshots spanning multiple storage chunks" do
      key =
        "projects/1/snapshots/project/multi-chunk-#{SnapshotStorage.unique_key_suffix()}.json.gz"

      snapshot = %{
        "format_version" => 2,
        "payload" => Base.encode64(:crypto.strong_rand_bytes(1_100_000))
      }

      assert {:ok, size_bytes, checksum} =
               SnapshotStorage.store_raw_with_checksum(key, snapshot)

      assert size_bytes > 1_048_576

      assert {:ok, ^snapshot, ^checksum} =
               SnapshotStorage.load_snapshot_with_checksum(key)

      assert :ok = SnapshotStorage.delete_snapshot(key)
    end
  end

  describe "load_verified_snapshot/4" do
    test "loads only after verifying compressed metadata" do
      key = "projects/1/snapshots/project/verified.json.gz"
      snapshot = %{"format_version" => 2, "project" => %{"name" => "Verified"}}

      assert {:ok, size_bytes, checksum} =
               SnapshotStorage.store_raw_with_checksum(key, snapshot)

      assert {:ok, ^snapshot, ^checksum} =
               SnapshotStorage.load_verified_snapshot(key, size_bytes, checksum)
    end

    test "rejects a compressed-size mismatch before decompression" do
      key = "projects/1/snapshots/project/size-mismatch.json.gz"
      snapshot = %{"payload" => String.duplicate("compressible", 100)}

      assert {:ok, size_bytes, checksum} =
               SnapshotStorage.store_raw_with_checksum(key, snapshot)

      assert {:error, {:compressed_size_mismatch, expected_size, ^size_bytes}} =
               SnapshotStorage.load_verified_snapshot(key, size_bytes + 1, checksum)

      assert expected_size == size_bytes + 1
    end

    test "rejects a checksum mismatch before decompression" do
      key = "projects/1/snapshots/project/checksum-mismatch.json.gz"
      snapshot = %{"payload" => String.duplicate("compressible", 100)}

      assert {:ok, size_bytes, checksum} =
               SnapshotStorage.store_raw_with_checksum(key, snapshot)

      wrong_checksum = String.duplicate("0", 64)
      refute wrong_checksum == checksum

      assert {:error, {:checksum_mismatch, ^wrong_checksum, ^checksum}} =
               SnapshotStorage.load_verified_snapshot(key, size_bytes, wrong_checksum)
    end

    test "rejects same-size invalid gzip bytes by checksum before inflation" do
      key = "projects/1/snapshots/project/invalid-gzip-checksum.json.gz"
      snapshot = %{"payload" => String.duplicate("compressible", 100)}

      assert {:ok, size_bytes, expected_checksum} =
               SnapshotStorage.store_raw_with_checksum(key, snapshot)

      assert {:ok, compressed} = Storage.download(key)
      <<first_byte, rest::binary>> = compressed
      tampered = <<Bitwise.bxor(first_byte, 0xFF), rest::binary>>
      assert byte_size(tampered) == size_bytes
      assert {:ok, _url} = Storage.upload(key, tampered, "application/gzip")

      actual_checksum =
        :sha256
        |> :crypto.hash(tampered)
        |> Base.encode16(case: :lower)

      assert {:error, {:checksum_mismatch, ^expected_checksum, ^actual_checksum}} =
               SnapshotStorage.load_verified_snapshot(
                 key,
                 size_bytes,
                 expected_checksum
               )
    end

    test "stops incremental inflation above the uncompressed limit" do
      key = "projects/1/snapshots/project/inflate-limit.json.gz"
      snapshot = %{"payload" => String.duplicate("a", 1_000_000)}

      assert {:ok, size_bytes, checksum} =
               SnapshotStorage.store_raw_with_checksum(key, snapshot)

      assert {:error, {:uncompressed_size_limit_exceeded, 1024}} =
               SnapshotStorage.load_verified_snapshot(
                 key,
                 size_bytes,
                 checksum,
                 max_uncompressed_bytes: 1024
               )
    end

    test "rejects an expected compressed size above the configured limit" do
      key = "projects/1/snapshots/project/expected-compressed-limit.json.gz"
      snapshot = %{"payload" => String.duplicate("compressible", 100)}

      assert {:ok, size_bytes, checksum} =
               SnapshotStorage.store_raw_with_checksum(key, snapshot)

      assert {:error, {:compressed_size_limit_exceeded, max_compressed_bytes}} =
               SnapshotStorage.load_verified_snapshot(
                 key,
                 size_bytes,
                 checksum,
                 max_compressed_bytes: size_bytes - 1
               )

      assert max_compressed_bytes == size_bytes - 1
    end

    test "rejects an oversized storage stat before accepting mismatched metadata" do
      key = "projects/1/snapshots/project/stat-compressed-limit.json.gz"
      snapshot = %{"payload" => String.duplicate("compressible", 100)}

      assert {:ok, size_bytes, checksum} =
               SnapshotStorage.store_raw_with_checksum(key, snapshot)

      assert size_bytes > 1

      assert {:error, {:compressed_size_limit_exceeded, max_compressed_bytes}} =
               SnapshotStorage.load_verified_snapshot(
                 key,
                 1,
                 checksum,
                 max_compressed_bytes: size_bytes - 1
               )

      assert max_compressed_bytes == size_bytes - 1
    end

    test "applies compressed and uncompressed bounds to legacy snapshot loads" do
      key = "projects/1/snapshots/project/legacy-load-limits.json.gz"
      snapshot = %{"payload" => String.duplicate("a", 10_000)}

      assert {:ok, size_bytes, _checksum} =
               SnapshotStorage.store_raw_with_checksum(key, snapshot)

      assert {:error, {:compressed_size_limit_exceeded, compressed_limit}} =
               SnapshotStorage.load_snapshot_with_checksum(
                 key,
                 max_compressed_bytes: size_bytes - 1
               )

      assert compressed_limit == size_bytes - 1

      assert {:error, {:uncompressed_size_limit_exceeded, 128}} =
               SnapshotStorage.load_snapshot_with_checksum(
                 key,
                 max_uncompressed_bytes: 128
               )
    end
  end

  describe "write size limits" do
    test "store_snapshot rejects oversized JSON before upload" do
      suffix = SnapshotStorage.unique_key_suffix()
      key = SnapshotStorage.build_key(1, "sheet", 42, 1, suffix)
      snapshot = %{"payload" => String.duplicate("a", 1_000)}

      assert {:error, {:uncompressed_size_limit_exceeded, 64}} =
               SnapshotStorage.store_snapshot(
                 1,
                 "sheet",
                 42,
                 1,
                 snapshot,
                 suffix,
                 max_uncompressed_bytes: 64,
                 max_compressed_bytes: 1_024
               )

      assert {:error, _reason} = Storage.stat(key)
    end

    test "store_raw_with_checksum rejects oversized compressed bytes before upload" do
      key =
        "projects/1/snapshots/project/raw-compressed-limit-#{SnapshotStorage.unique_key_suffix()}.json.gz"

      snapshot = %{"payload" => Base.encode64(:crypto.strong_rand_bytes(2_048))}

      assert {:error, {:compressed_size_limit_exceeded, 64}} =
               SnapshotStorage.store_raw_with_checksum(
                 key,
                 snapshot,
                 max_uncompressed_bytes: 10_000,
                 max_compressed_bytes: 64
               )

      assert {:error, _reason} = Storage.stat(key)
    end

    test "store_raw uses the same write bounds" do
      key =
        "projects/1/snapshots/project/raw-limit-#{SnapshotStorage.unique_key_suffix()}.json.gz"

      snapshot = %{"payload" => String.duplicate("a", 1_000)}

      assert {:error, {:uncompressed_size_limit_exceeded, 64}} =
               SnapshotStorage.store_raw(
                 key,
                 snapshot,
                 max_uncompressed_bytes: 64,
                 max_compressed_bytes: 1_024
               )

      assert {:error, _reason} = Storage.stat(key)
    end

    test "a stored snapshot is loadable under the same limits" do
      key =
        "projects/1/snapshots/project/write-read-limits-#{SnapshotStorage.unique_key_suffix()}.json.gz"

      snapshot = %{
        "format_version" => 2,
        "payload" => Base.encode64(:crypto.strong_rand_bytes(1_024))
      }

      opts = [max_uncompressed_bytes: 10_000, max_compressed_bytes: 10_000]

      assert {:ok, size_bytes, checksum} =
               SnapshotStorage.store_raw_with_checksum(key, snapshot, opts)

      assert {:ok, ^snapshot, ^checksum} =
               SnapshotStorage.load_verified_snapshot(
                 key,
                 size_bytes,
                 checksum,
                 opts
               )
    end
  end

  describe "delete_snapshot/1" do
    test "deletes a stored snapshot" do
      snapshot = %{"name" => "Delete Me"}
      {:ok, key, _size} = SnapshotStorage.store_snapshot(1, "sheet", 99, 1, snapshot)

      assert :ok = SnapshotStorage.delete_snapshot(key)
      assert {:error, _} = SnapshotStorage.load_snapshot(key)
    end
  end

  describe "build_key/4" do
    test "builds the correct key format" do
      assert SnapshotStorage.build_key(5, "flow", 10, 3) ==
               "projects/5/snapshots/flow/10/3.json.gz"
    end

    test "builds an attempt-owned key when a suffix is provided" do
      assert SnapshotStorage.build_key(5, "flow", 10, 3, "deadbeef") ==
               "projects/5/snapshots/flow/10/3-deadbeef.json.gz"
    end

    test "recognizes only keys for the exact entity-version identity" do
      assert SnapshotStorage.entity_key?(
               "projects/5/snapshots/sheet/10/3.json.gz",
               5,
               "sheet",
               10,
               3
             )

      assert SnapshotStorage.entity_key?(
               "projects/5/snapshots/sheet/10/3-0123456789abcdef.json.gz",
               5,
               "sheet",
               10,
               3
             )

      refute SnapshotStorage.entity_key?(
               "projects/6/snapshots/sheet/10/3-0123456789abcdef.json.gz",
               5,
               "sheet",
               10,
               3
             )

      refute SnapshotStorage.entity_key?(
               "projects/5/snapshots/flow/10/3-0123456789abcdef.json.gz",
               5,
               "sheet",
               10,
               3
             )

      refute SnapshotStorage.entity_key?(
               "projects/5/snapshots/sheet/10/3-not-owned.json.gz",
               5,
               "sheet",
               10,
               3
             )
    end
  end

  describe "build_project_key/3" do
    test "builds deterministic and attempt-owned project snapshot keys" do
      assert SnapshotStorage.build_project_key(5, 3) ==
               "projects/5/snapshots/project/3.json.gz"

      assert SnapshotStorage.build_project_key(5, 3, "deadbeef") ==
               "projects/5/snapshots/project/3-deadbeef.json.gz"
    end

    test "recognizes only canonical keys for the exact project snapshot identity" do
      assert SnapshotStorage.project_key?(
               "projects/5/snapshots/project/3.json.gz",
               5,
               3
             )

      assert SnapshotStorage.project_key?(
               "projects/5/snapshots/project/3-0123456789abcdef.json.gz",
               5,
               3
             )

      refute SnapshotStorage.project_key?(
               "projects/6/snapshots/project/3-0123456789abcdef.json.gz",
               5,
               3
             )

      refute SnapshotStorage.project_key?(
               "projects/5/snapshots/project/4-0123456789abcdef.json.gz",
               5,
               3
             )

      refute SnapshotStorage.project_key?(
               "projects/5/snapshots/project/3-not-owned.json.gz",
               5,
               3
             )
    end
  end
end
