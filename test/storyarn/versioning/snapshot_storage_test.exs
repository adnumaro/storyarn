defmodule Storyarn.Versioning.SnapshotStorageTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Versioning.SnapshotStorage

  describe "store_snapshot/5" do
    test "stores compressed JSON and returns key and size" do
      snapshot = %{"name" => "Test", "blocks" => [%{"type" => "text"}]}

      assert {:ok, key, size_bytes} =
               SnapshotStorage.store_snapshot(1, "sheet", 42, 1, snapshot)

      assert key == "projects/1/snapshots/sheet/42/1.json.gz"
      assert size_bytes > 0
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
  end

  describe "build_project_key/3" do
    test "builds deterministic and attempt-owned project snapshot keys" do
      assert SnapshotStorage.build_project_key(5, 3) ==
               "projects/5/snapshots/project/3.json.gz"

      assert SnapshotStorage.build_project_key(5, 3, "deadbeef") ==
               "projects/5/snapshots/project/3-deadbeef.json.gz"
    end
  end
end
