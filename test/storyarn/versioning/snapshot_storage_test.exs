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
  end
end
