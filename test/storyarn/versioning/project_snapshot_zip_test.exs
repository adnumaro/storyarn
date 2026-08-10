defmodule Storyarn.Versioning.ProjectSnapshotZipTest do
  use ExUnit.Case, async: false

  alias Storyarn.Assets.Storage
  alias Storyarn.Assets.Storage.Local
  alias Storyarn.SnapshotReadSwitchStorage
  alias Storyarn.Versioning.ProjectSnapshot
  alias Storyarn.Versioning.ProjectSnapshotZip
  alias Storyarn.Versioning.SnapshotObjectFormat
  alias Storyarn.Versioning.SnapshotObjectStorage
  alias Storyarn.Versioning.SnapshotStorage

  defmodule ThrottledStorage do
    @moduledoc false

    def stat(_key), do: {:error, {:http_error, 429, %{body: "provider-secret"}}}
  end

  test "streams a deterministic STORE plus ZIP64 archive in canonical order" do
    fixture = snapshot_fixture(blobs: [png_blob("later"), png_blob("earlier")])

    assert {:ok, plan} = ProjectSnapshotZip.prepare(fixture.snapshot)
    archive = archive_bytes(plan)

    assert archive == archive_bytes(plan)
    assert :binary.match(archive, <<0x50, 0x4B, 0x06, 0x06>>) != :nomatch
    assert :binary.match(archive, <<0x50, 0x4B, 0x06, 0x07>>) != :nomatch

    entries = zip_entries(archive)

    assert Enum.map(entries, &zip_entry_name/1) ==
             ["manifest.json", "project.json" | Enum.sort(fixture.blob_paths)]

    assert Enum.all?(entries, &(zip_entry_compression_method(archive, &1) == 0))
    assert Enum.all?(entries, &(zip_entry_version_needed(archive, &1) == 45))
    assert Enum.all?(entries, &(zip_entry_mtime(&1) == {{1980, 1, 1}, {0, 0, 0}}))

    assert {:ok, extracted} = :zip.extract(archive, [:memory])

    extracted = Map.new(extracted, fn {name, bytes} -> {List.to_string(name), bytes} end)

    assert extracted == fixture.payloads
  end

  test "keeps duplicate logical filenames and bytes in the manifest while emitting one blob entry" do
    fixture =
      snapshot_fixture(
        blobs: [png_blob("shared bytes")],
        assets: fn [blob] ->
          [
            asset_entry("asset-000001", "hero.png", blob),
            asset_entry("asset-000002", "hero.png", blob)
          ]
        end
      )

    assert {:ok, plan} = ProjectSnapshotZip.prepare(fixture.snapshot)
    archive = archive_bytes(plan)

    assert Enum.map(zip_entries(archive), &zip_entry_name/1) ==
             ["manifest.json", "project.json", hd(fixture.blob_paths)]

    assert {:ok, extracted} = :zip.extract(archive, [:memory])

    manifest =
      extracted
      |> Map.new(fn {name, bytes} -> {List.to_string(name), bytes} end)
      |> Map.fetch!("manifest.json")
      |> Jason.decode!()

    assert Enum.map(manifest["assets"], & &1["logical_id"]) ==
             ["asset-000001", "asset-000002"]

    assert Enum.map(manifest["assets"], & &1["filename"]) == ["hero.png", "hero.png"]
    assert Enum.uniq(Enum.map(manifest["assets"], & &1["blob_path"])) == fixture.blob_paths
    assert manifest["counts"] == %{"assets" => 2, "blobs" => 1, "payload_objects" => 2}
  end

  test "rejects a corrupt physical object during preflight" do
    fixture = snapshot_fixture(blobs: [png_blob("verified content")])
    [blob_path] = fixture.blob_paths
    blob_key = fixture.snapshot.object_prefix <> "/" <> blob_path
    corrupt = corrupt_same_size(Map.fetch!(fixture.payloads, blob_path))

    assert {:ok, _url} = Storage.upload(blob_key, corrupt, "image/png")

    assert {:error, {:snapshot_export_corrupt, {:snapshot_object_checksum_mismatch, ^blob_path}}} =
             ProjectSnapshotZip.prepare(fixture.snapshot)
  end

  test "classifies a known missing object as corrupt" do
    fixture = snapshot_fixture(blobs: [png_blob("missing content")])
    [blob_path] = fixture.blob_paths
    blob_key = fixture.snapshot.object_prefix <> "/" <> blob_path

    assert :ok = Local.delete(blob_key)

    assert {:error, {:snapshot_export_corrupt, {:snapshot_storage_stat_failed, :enoent}}} =
             ProjectSnapshotZip.prepare(fixture.snapshot)
  end

  test "classifies provider throttling as unavailable without retaining provider details" do
    fixture = snapshot_fixture()
    install_storage_adapter(ThrottledStorage)

    assert {:error, :snapshot_export_unavailable} = ProjectSnapshotZip.prepare(fixture.snapshot)
  end

  test "aborts the stream when an object changes after preflight" do
    fixture = snapshot_fixture(blobs: [png_blob("read twice")])
    [blob_path] = fixture.blob_paths
    blob_key = fixture.snapshot.object_prefix <> "/" <> blob_path
    replacement = fixture.payloads |> Map.fetch!(blob_path) |> corrupt_same_size()

    install_read_switch(%{blob_key => replacement})

    assert {:ok, plan} = ProjectSnapshotZip.prepare(fixture.snapshot)
    assert SnapshotReadSwitchStorage.stream_count(blob_key) == 1

    assert_raise RuntimeError, ~r/snapshot ZIP stream verification failed/, fn ->
      plan |> ProjectSnapshotZip.stream() |> Enum.to_list()
    end

    assert SnapshotReadSwitchStorage.stream_count(blob_key) == 2
  end

  test "enforces the total export limit including manifest bytes" do
    fixture = snapshot_fixture(blobs: [png_blob("bounded")])
    original_limits = Application.get_env(:storyarn, SnapshotObjectFormat, [])

    Application.put_env(
      :storyarn,
      SnapshotObjectFormat,
      Keyword.put(original_limits, :max_total_bytes, fixture.snapshot.total_size_bytes - 1)
    )

    on_exit(fn -> Application.put_env(:storyarn, SnapshotObjectFormat, original_limits) end)

    assert {:error, :snapshot_export_limit_exceeded} =
             ProjectSnapshotZip.prepare(fixture.snapshot)
  end

  test "rejects unsafe and duplicate archive paths through manifest validation" do
    unsafe =
      snapshot_fixture(
        blobs: [png_blob("unsafe")],
        mutate_manifest: fn manifest ->
          objects =
            Enum.map(manifest["objects"], fn
              %{"kind" => "asset_blob"} = object -> %{object | "path" => "../escape.png"}
              object -> object
            end)

          %{manifest | "objects" => objects}
        end
      )

    assert {:error, {:snapshot_export_corrupt, {:snapshot_manifest_validation_failed, unsafe_reason}}} =
             ProjectSnapshotZip.prepare(unsafe.snapshot)

    assert match?({:unsafe_snapshot_object_path, _path}, unsafe_reason)

    duplicate =
      snapshot_fixture(
        mutate_manifest: fn manifest ->
          project = manifest["project"]

          manifest
          |> Map.put("objects", [project, project])
          |> Map.put("payload_size_bytes", project["size_bytes"] * 2)
          |> Map.put("counts", %{"assets" => 0, "blobs" => 0, "payload_objects" => 2})
        end
      )

    assert {:error, {:snapshot_export_corrupt, {:snapshot_manifest_validation_failed, duplicate_reason}}} =
             ProjectSnapshotZip.prepare(duplicate.snapshot)

    assert duplicate_reason == {:duplicate_object_path, "project.json"}
  end

  test "requires an exact snapshot row to manifest binding" do
    fixture = snapshot_fixture(blobs: [png_blob("binding")])
    snapshot = %{fixture.snapshot | blob_count: fixture.snapshot.blob_count + 1}

    assert {:error, {:snapshot_export_corrupt, {:snapshot_manifest_field_mismatch, :blob_count, expected, actual}}} =
             ProjectSnapshotZip.prepare(snapshot)

    assert expected == fixture.snapshot.blob_count
    assert actual == fixture.snapshot.blob_count + 1
  end

  test "keeps the plan bounded and defers all second reads until stream consumption" do
    fixture = snapshot_fixture(blobs: [png_blob(:binary.copy("x", 1_100_000))])
    assert {:ok, plan} = ProjectSnapshotZip.prepare(fixture.snapshot)

    assert Enum.all?(plan.entries, fn entry ->
             entry |> Map.keys() |> Enum.sort() ==
               [:content_type, :etag, :key, :path, :sha256, :size_bytes]
           end)

    install_read_switch(%{})
    stream = ProjectSnapshotZip.stream(plan)

    Enum.each(plan.entries, fn entry ->
      assert SnapshotReadSwitchStorage.stream_count(entry.key) == 0
    end)

    assert [_zip_header] = Enum.take(stream, 1)

    Enum.each(plan.entries, fn entry ->
      assert SnapshotReadSwitchStorage.stream_count(entry.key) == 0
    end)

    _archive = stream |> Enum.to_list() |> IO.iodata_to_binary()

    Enum.each(plan.entries, fn entry ->
      assert SnapshotReadSwitchStorage.stream_count(entry.key) == 1
    end)
  end

  test "propagates a failed prepare heartbeat and raises on a failed stream heartbeat" do
    fixture = snapshot_fixture()

    assert {:error, :snapshot_export_lease_lost} =
             ProjectSnapshotZip.prepare(fixture.snapshot,
               heartbeat: fn -> {:error, :snapshot_export_lease_lost} end
             )

    assert {:ok, plan} = ProjectSnapshotZip.prepare(fixture.snapshot)

    assert_raise RuntimeError, ~r/heartbeat_failed/, fn ->
      plan
      |> ProjectSnapshotZip.stream(heartbeat: fn -> {:error, :snapshot_export_lease_lost} end)
      |> Enum.to_list()
    end
  end

  test "checks the lease heartbeat for every provider chunk during preflight and streaming" do
    fixture = snapshot_fixture(blobs: [png_blob(:binary.copy("x", 1_100_000))])
    {prepare_heartbeat, prepare_count} = heartbeat_failing_on_call(8)

    assert {:error, :snapshot_export_unavailable} =
             ProjectSnapshotZip.prepare(fixture.snapshot, heartbeat: prepare_heartbeat)

    assert prepare_count.() == 8

    assert {:ok, plan} = ProjectSnapshotZip.prepare(fixture.snapshot)
    {stream_heartbeat, stream_count} = heartbeat_failing_on_call(7)

    assert_raise RuntimeError, ~r/heartbeat_failed/, fn ->
      plan
      |> ProjectSnapshotZip.stream(heartbeat: stream_heartbeat)
      |> Enum.to_list()
    end

    assert stream_count.() == 7
  end

  defp snapshot_fixture(opts \\ []) do
    project_id = System.unique_integer([:positive])
    token = SnapshotStorage.unique_key_suffix()
    prefix = SnapshotObjectStorage.ready_prefix(project_id, token)
    project = %{"format_version" => 2, "name" => "ZIP fixture"}
    project_bytes = Jason.encode!(project)
    project_descriptor = descriptor("project", "project.json", "application/json", project_bytes)

    blob_specs = Keyword.get(opts, :blobs, [])

    blobs =
      Enum.map(blob_specs, fn blob ->
        descriptor("asset_blob", nil, blob.content_type, blob.bytes)
      end)

    blob_payloads =
      blobs
      |> Enum.zip(blob_specs)
      |> Map.new(fn {descriptor, blob} -> {descriptor["path"], blob.bytes} end)

    assets =
      case Keyword.get(opts, :assets) do
        build when is_function(build, 1) -> build.(blobs)
        nil -> blobs |> Enum.with_index(1) |> Enum.map(&default_asset_entry/1)
      end

    assert {:ok, manifest} =
             SnapshotObjectFormat.build_manifest(project, assets, blobs, project_descriptor: project_descriptor)

    manifest =
      case Keyword.get(opts, :mutate_manifest) do
        mutate when is_function(mutate, 1) -> mutate.(manifest)
        nil -> manifest
      end

    manifest_bytes = Jason.encode!(manifest)
    manifest_key = prefix <> "/manifest.json"
    project_key = prefix <> "/project.json"

    assert {:ok, _url} = Storage.upload(project_key, project_bytes, "application/json")

    Enum.each(blobs, fn blob ->
      assert {:ok, _url} =
               Storage.upload(
                 prefix <> "/" <> blob["path"],
                 Map.fetch!(blob_payloads, blob["path"]),
                 blob["content_type"]
               )
    end)

    assert {:ok, _url} = Storage.upload(manifest_key, manifest_bytes, "application/json")

    cleanup_keys =
      [manifest_key, project_key | Enum.map(blobs, &(prefix <> "/" <> &1["path"]))]

    on_exit(fn -> Enum.each(cleanup_keys, &Local.delete/1) end)

    project_from_manifest = manifest["project"]
    counts = manifest["counts"]
    manifest_size = byte_size(manifest_bytes)
    total_size = manifest["payload_size_bytes"] + manifest_size

    snapshot = %ProjectSnapshot{
      id: System.unique_integer([:positive]),
      project_id: project_id,
      version_number: 7,
      format_version: SnapshotObjectFormat.format_version(),
      object_prefix: prefix,
      manifest_storage_key: manifest_key,
      manifest_size_bytes: manifest_size,
      manifest_checksum: sha256(manifest_bytes),
      project_storage_key: project_key,
      project_size_bytes: project_from_manifest["size_bytes"],
      project_checksum: project_from_manifest["sha256"],
      total_size_bytes: total_size,
      accounted_size_bytes: total_size,
      asset_blob_size_bytes: manifest["payload_size_bytes"] - project_from_manifest["size_bytes"],
      object_count: counts["payload_objects"] + 1,
      asset_count: counts["assets"],
      blob_count: counts["blobs"],
      mode: "full",
      lifecycle_state: "ready",
      integrity_state: "verified",
      accounting_version: 1,
      accounting_generation: 1
    }

    payloads =
      blob_payloads
      |> Map.put("project.json", project_bytes)
      |> Map.put("manifest.json", manifest_bytes)

    %{
      blob_paths: blobs |> Enum.map(& &1["path"]) |> Enum.sort(),
      manifest: manifest,
      payloads: payloads,
      snapshot: snapshot
    }
  end

  defp descriptor(kind, path, content_type, bytes) do
    sha256 = sha256(bytes)

    %{
      "kind" => kind,
      "path" => path || SnapshotObjectFormat.blob_path(sha256, content_type),
      "sha256" => sha256,
      "size_bytes" => byte_size(bytes),
      "content_type" => content_type
    }
  end

  defp default_asset_entry({blob, index}) do
    extension = Path.extname(blob["path"])
    asset_entry("asset-#{index |> Integer.to_string() |> String.pad_leading(6, "0")}", "asset-#{index}#{extension}", blob)
  end

  defp asset_entry(logical_id, filename, blob) do
    %{
      "logical_id" => logical_id,
      "filename" => filename,
      "content_type" => blob["content_type"],
      "size_bytes" => blob["size_bytes"],
      "sha256" => blob["sha256"],
      "blob_path" => blob["path"],
      "metadata" => %{},
      "relationships" => %{"original" => nil, "web" => nil, "variants" => %{}}
    }
  end

  defp png_blob(bytes), do: %{bytes: bytes, content_type: "image/png"}

  defp archive_bytes(plan) do
    plan
    |> ProjectSnapshotZip.stream()
    |> Enum.to_list()
    |> IO.iodata_to_binary()
  end

  defp zip_entries(archive) do
    assert {:ok, entries} = :zip.list_dir(archive)
    Enum.filter(entries, &match?({:zip_file, _name, _info, _comment, _offset, _compressed_size}, &1))
  end

  defp zip_entry_name({:zip_file, name, _info, _comment, _offset, _compressed_size}), do: List.to_string(name)

  defp zip_entry_mtime({:zip_file, _name, info, _comment, _offset, _compressed_size}), do: elem(info, 5)

  defp zip_entry_compression_method(archive, entry) do
    <<0x04034B50::little-size(32), _version::little-size(16), _flags::little-size(16),
      compression_method::little-size(16), _rest::binary>> =
      binary_part(archive, zip_entry_offset(entry), byte_size(archive) - zip_entry_offset(entry))

    compression_method
  end

  defp zip_entry_version_needed(archive, entry) do
    <<0x04034B50::little-size(32), version::little-size(16), _rest::binary>> =
      binary_part(archive, zip_entry_offset(entry), byte_size(archive) - zip_entry_offset(entry))

    version
  end

  defp zip_entry_offset({:zip_file, _name, _info, _comment, offset, _compressed_size}), do: offset

  defp corrupt_same_size(<<first, rest::binary>>), do: <<Bitwise.bxor(first, 1), rest::binary>>

  defp sha256(bytes), do: :sha256 |> :crypto.hash(bytes) |> Base.encode16(case: :lower)

  defp install_read_switch(replacements) do
    original_storage = Application.fetch_env!(:storyarn, :storage)
    {:ok, _pid} = SnapshotReadSwitchStorage.start_link(replacements)

    Application.put_env(
      :storyarn,
      :storage,
      Keyword.put(original_storage, :adapter, SnapshotReadSwitchStorage)
    )

    on_exit(fn ->
      Application.put_env(:storyarn, :storage, original_storage)

      if Process.whereis(SnapshotReadSwitchStorage) do
        Agent.stop(SnapshotReadSwitchStorage)
      end
    end)
  end

  defp install_storage_adapter(adapter) do
    original_storage = Application.fetch_env!(:storyarn, :storage)

    Application.put_env(
      :storyarn,
      :storage,
      Keyword.put(original_storage, :adapter, adapter)
    )

    on_exit(fn -> Application.put_env(:storyarn, :storage, original_storage) end)
  end

  defp heartbeat_failing_on_call(failing_call) do
    counter_key = {__MODULE__, make_ref()}

    heartbeat = fn ->
      count = Process.get(counter_key, 0) + 1
      Process.put(counter_key, count)

      if count == failing_call,
        do: {:error, :snapshot_export_lease_lost},
        else: :ok
    end

    {heartbeat, fn -> Process.get(counter_key, 0) end}
  end
end
