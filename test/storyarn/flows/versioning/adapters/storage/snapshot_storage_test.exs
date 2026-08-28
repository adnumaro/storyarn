defmodule Storyarn.Flows.Versioning.SnapshotStorageTest do
  use ExUnit.Case, async: false

  alias Storyarn.Flows.Versioning.SnapshotStorage
  alias Storyarn.Platform.ObjectStorage, as: Storage
  alias Storyarn.SnapshotReadSwitchStorage

  setup do
    original_storage_config = Application.fetch_env!(:storyarn, :storage)
    {:ok, storage_pid} = SnapshotReadSwitchStorage.start_link(%{})
    Process.unlink(storage_pid)

    Application.put_env(
      :storyarn,
      :storage,
      Keyword.put(original_storage_config, :adapter, SnapshotReadSwitchStorage)
    )

    on_exit(fn ->
      Application.put_env(:storyarn, :storage, original_storage_config)

      if Process.alive?(storage_pid) do
        Agent.stop(storage_pid)
      end
    end)

    :ok
  end

  test "never deletes a recoverable Project blob even when its tail is not a canonical hash filename" do
    assert {:error, :recoverable_blob} =
             SnapshotStorage.delete("projects/42/blobs/legacy/nested-object")
  end

  test "round-trips a Flow snapshot after verifying both streaming passes" do
    snapshot = %{
      "flow" => %{"id" => 42, "name" => "Opening"},
      "nodes" => [%{"id" => 1, "type" => "dialogue"}]
    }

    {key, size_bytes, checksum} = store_snapshot(snapshot)

    assert {:ok, ^snapshot, ^checksum} =
             SnapshotStorage.load_verified(key, size_bytes, checksum)

    assert SnapshotReadSwitchStorage.stream_count(key) == 2
  end

  test "rejects persisted size metadata before reading snapshot bytes" do
    snapshot = %{"flow" => %{"name" => "Wrong size"}}
    {key, size_bytes, checksum} = store_snapshot(snapshot)

    assert {:error, {:compressed_size_mismatch, expected_size, ^size_bytes}} =
             SnapshotStorage.load_verified(key, size_bytes + 1, checksum)

    assert expected_size == size_bytes + 1
    assert SnapshotReadSwitchStorage.stream_count(key) == 0
  end

  test "rejects a checksum mismatch before starting inflation" do
    snapshot = %{"flow" => %{"name" => "Wrong checksum"}}
    {key, size_bytes, checksum} = store_snapshot(snapshot)
    wrong_checksum = String.duplicate("0", 64)
    refute wrong_checksum == checksum

    assert {:error, {:checksum_mismatch, ^wrong_checksum, ^checksum}} =
             SnapshotStorage.load_verified(key, size_bytes, wrong_checksum)

    assert SnapshotReadSwitchStorage.stream_count(key) == 1
  end

  test "enforces compressed and incremental uncompressed limits" do
    snapshot = %{"payload" => String.duplicate("a", 1_000_000)}
    {key, size_bytes, checksum} = store_snapshot(snapshot)

    assert {:error, {:compressed_size_limit_exceeded, compressed_limit}} =
             SnapshotStorage.load_verified(
               key,
               size_bytes,
               checksum,
               max_compressed_bytes: size_bytes - 1
             )

    assert compressed_limit == size_bytes - 1
    assert SnapshotReadSwitchStorage.stream_count(key) == 0

    assert {:error, {:uncompressed_size_limit_exceeded, 1_024}} =
             SnapshotStorage.load_verified(
               key,
               size_bytes,
               checksum,
               max_uncompressed_bytes: 1_024
             )

    assert SnapshotReadSwitchStorage.stream_count(key) == 2
  end

  test "streams snapshots spanning multiple adapter chunks on both verification passes" do
    snapshot = %{"payload" => Base.encode64(:crypto.strong_rand_bytes(1_100_000))}
    {key, size_bytes, checksum} = store_snapshot(snapshot)
    assert size_bytes > 1_048_576

    parent = self()

    SnapshotReadSwitchStorage.observe_io(fn operation, storage_key ->
      send(parent, {:snapshot_storage_io, operation, storage_key})
    end)

    assert {:ok, ^snapshot, ^checksum} =
             SnapshotStorage.load_verified(key, size_bytes, checksum)

    assert SnapshotReadSwitchStorage.stream_count(key) == 2

    for _pass_and_chunk <- 1..4 do
      assert_receive {:snapshot_storage_io, :stream_chunk, ^key}
    end
  end

  test "binds both reads to one ETag and detects replacement between checksum and inflation" do
    snapshot = %{"flow" => %{"name" => "Immutable read"}}
    {key, size_bytes, checksum} = store_snapshot(snapshot)
    assert {:ok, compressed} = Storage.download(key)

    replacement = change_gzip_mtime(compressed)
    replacement_checksum = sha256(replacement)

    assert byte_size(replacement) == size_bytes
    assert :zlib.gunzip(replacement) == :zlib.gunzip(compressed)
    refute replacement_checksum == checksum

    parent = self()
    {:ok, read_counter} = Agent.start_link(fn -> 0 end)

    on_exit(fn ->
      if Process.alive?(read_counter) do
        Agent.stop(read_counter)
      end
    end)

    SnapshotReadSwitchStorage.set_stat_result(fn storage_key ->
      case SnapshotReadSwitchStorage.underlying_stat(storage_key) do
        {:ok, stat} -> {:ok, %{stat | etag: "immutable-flow-snapshot"}}
        {:error, _reason} = error -> error
      end
    end)

    SnapshotReadSwitchStorage.set_stream_result(fn storage_key, offset, length, opts ->
      read_number = Agent.get_and_update(read_counter, fn count -> {count + 1, count + 1} end)
      send(parent, {:snapshot_stream_read, read_number, opts})

      if read_number == 1 do
        SnapshotReadSwitchStorage.underlying_stream(storage_key, offset, length, opts)
      else
        {:ok, [{:ok, replacement}]}
      end
    end)

    assert {:error, {:checksum_mismatch, ^checksum, ^replacement_checksum}} =
             SnapshotStorage.load_verified(key, size_bytes, checksum)

    assert_receive {:snapshot_stream_read, 1, [etag: "immutable-flow-snapshot"]}
    assert_receive {:snapshot_stream_read, 2, [etag: "immutable-flow-snapshot"]}
    assert Agent.get(read_counter, & &1) == 2
  end

  test "reads default limits from the Flow-owned configuration namespace" do
    original_config = Application.get_env(:storyarn, SnapshotStorage)

    Application.put_env(
      :storyarn,
      SnapshotStorage,
      max_compressed_bytes: 1_024,
      max_uncompressed_bytes: 64
    )

    on_exit(fn -> restore_snapshot_storage_config(original_config) end)

    assert {:error, {:uncompressed_size_limit_exceeded, 64}} =
             SnapshotStorage.store_snapshot(
               1,
               42,
               1,
               %{"payload" => String.duplicate("a", 1_000)}
             )
  end

  defp store_snapshot(snapshot) do
    assert {:ok, key, size_bytes, checksum} =
             SnapshotStorage.store_snapshot(1, 42, 1, snapshot)

    on_exit(fn -> SnapshotStorage.delete(key) end)

    {key, size_bytes, checksum}
  end

  defp change_gzip_mtime(<<prefix::binary-size(4), byte, rest::binary>>) do
    <<prefix::binary, Bitwise.bxor(byte, 1), rest::binary>>
  end

  defp sha256(bytes) do
    :sha256
    |> :crypto.hash(bytes)
    |> Base.encode16(case: :lower)
  end

  defp restore_snapshot_storage_config(nil) do
    Application.delete_env(:storyarn, SnapshotStorage)
  end

  defp restore_snapshot_storage_config(config) do
    Application.put_env(:storyarn, SnapshotStorage, config)
  end
end
