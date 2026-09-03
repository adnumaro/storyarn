defmodule Storyarn.Projects.Versioning.ProjectSnapshotZipTest do
  use Storyarn.DataCase, async: false

  alias Storyarn.Platform.ObjectStorage.Adapters.Local
  alias Storyarn.Projects.Assets.Asset
  alias Storyarn.Projects.Assets.BlobStore
  alias Storyarn.Projects.Assets.Storage
  alias Storyarn.Projects.Versioning.ProjectSnapshotZip
  alias Storyarn.Projects.Versioning.SnapshotArchiveStorage
  alias Storyarn.Projects.Versioning.SnapshotObjectFormat
  alias Storyarn.SnapshotReadSwitchStorage

  test "prepares without provider I/O and reads every source blob once while streaming" do
    fixture = capture_fixture("one provider read")
    parent = self()
    install_read_switch(%{})
    SnapshotReadSwitchStorage.observe_io(fn operation, key -> send(parent, {:storage_io, operation, key}) end)

    assert {:ok, plan} = ProjectSnapshotZip.prepare_capture(fixture.project_id, fixture.prepared)
    refute_received {:storage_io, _operation, _key}
    assert SnapshotReadSwitchStorage.stream_count(fixture.source_key) == 0

    archive = archive_bytes(plan)

    assert byte_size(archive) == plan.archive_size_bytes
    assert SnapshotReadSwitchStorage.stream_count(fixture.source_key) == 1
  end

  test "emits a deterministic interoperable classic STORE archive in canonical order" do
    fixture = capture_fixture("portable archive")
    assert {:ok, plan} = ProjectSnapshotZip.prepare_capture(fixture.project_id, fixture.prepared)

    archive = archive_bytes(plan)

    assert archive == archive_bytes(plan)
    assert byte_size(archive) == ProjectSnapshotZip.archive_size(plan)
    assert :binary.match(archive, <<0x50, 0x4B, 0x06, 0x06>>) == :nomatch
    assert :binary.match(archive, <<0x50, 0x4B, 0x06, 0x07>>) == :nomatch

    entries = zip_entries(archive)

    assert Enum.map(entries, &zip_entry_name/1) == [
             "manifest.json",
             "project.json",
             fixture.blob_path
           ]

    assert Enum.all?(entries, &(zip_entry_compression_method(archive, &1) == 0))
    assert Enum.all?(entries, &(zip_entry_version_needed(archive, &1) == 20))
    assert Enum.all?(entries, &(zip_entry_mtime(&1) == {{1980, 1, 1}, {0, 0, 0}}))

    assert {:ok, extracted} = :zip.extract(archive, [:memory])
    extracted = extracted_map(extracted)

    assert extracted["manifest.json"] == fixture.prepared.manifest_json
    assert extracted["project.json"] == fixture.prepared.project_json
    assert extracted[fixture.blob_path] == fixture.bytes
  end

  test "plans the classic end record from Zstream's emitted archive contract" do
    fixture = capture_fixture("end record sizing")
    assert {:ok, plan} = ProjectSnapshotZip.prepare_capture(fixture.project_id, fixture.prepared)

    entry_region_bytes =
      Enum.reduce(plan.entries, 0, fn entry, total ->
        path_bytes = byte_size(entry.path)

        total +
          30 + path_bytes + entry.size_bytes + 16 +
          46 + path_bytes
      end)

    zstream_end_record_bytes =
      []
      |> Zstream.zip(zip64: false)
      |> Enum.to_list()
      |> IO.iodata_length()

    assert plan.archive_size_bytes - entry_region_bytes == zstream_end_record_bytes
    assert plan |> archive_bytes() |> byte_size() == plan.archive_size_bytes
  end

  @tag :tmp_dir
  test "extracts with each available independent system ZIP reader", %{tmp_dir: tmp_dir} do
    fixture = capture_fixture("external readers")
    assert {:ok, plan} = ProjectSnapshotZip.prepare_capture(fixture.project_id, fixture.prepared)
    archive_path = Path.join(tmp_dir, "snapshot.zip")
    File.write!(archive_path, archive_bytes(plan))

    expected = %{
      "manifest.json" => fixture.prepared.manifest_json,
      "project.json" => fixture.prepared.project_json,
      fixture.blob_path => fixture.bytes
    }

    assert_external_zip_reader("unzip", archive_path, Path.join(tmp_dir, "unzip"), expected)
    assert_external_zip_reader("ditto", archive_path, Path.join(tmp_dir, "ditto"), expected)
  end

  test "keeps duplicate logical asset names while emitting one content-addressed blob" do
    fixture = capture_fixture("shared", duplicate_asset?: true)
    assert {:ok, plan} = ProjectSnapshotZip.prepare_capture(fixture.project_id, fixture.prepared)
    assert {:ok, extracted} = plan |> archive_bytes() |> :zip.extract([:memory])
    extracted = extracted_map(extracted)

    assert extracted |> Map.keys() |> Enum.sort() ==
             Enum.sort(["manifest.json", "project.json", fixture.blob_path])

    manifest = Jason.decode!(extracted["manifest.json"])
    assert Enum.map(manifest["assets"], & &1["filename"]) == ["hero.png", "hero.png"]
    assert manifest["counts"] == %{"assets" => 2, "blobs" => 1, "payload_objects" => 2}
  end

  test "sidecar bytes are byte-identical to the embedded manifest entry" do
    fixture = capture_fixture("same manifest")
    assert {:ok, plan} = ProjectSnapshotZip.prepare_capture(fixture.project_id, fixture.prepared)
    assert plan.manifest_json == fixture.prepared.manifest_json
    assert {:ok, extracted} = plan |> archive_bytes() |> :zip.extract([:memory])
    assert extracted_map(extracted)["manifest.json"] == plan.manifest_json
  end

  test "aborts before a valid central directory when a source is missing" do
    fixture = capture_fixture("missing source")
    assert :ok = Local.delete(fixture.source_key)
    assert {:ok, plan} = ProjectSnapshotZip.prepare_capture(fixture.project_id, fixture.prepared)

    assert catch_throw(archive_bytes(plan)) ==
             {:snapshot_stream_error, {:missing_snapshot_blob_source, fixture.hash}}
  end

  test "aborts when streamed source bytes differ from the captured checksum" do
    fixture = capture_fixture("expected bytes")
    assert {:ok, _url} = Storage.upload(fixture.source_key, corrupt_same_size(fixture.bytes), "image/png")
    assert {:ok, plan} = ProjectSnapshotZip.prepare_capture(fixture.project_id, fixture.prepared)

    assert catch_throw(archive_bytes(plan)) ==
             {:snapshot_stream_error, {:snapshot_object_checksum_mismatch, fixture.blob_path}}
  end

  test "checks heartbeat and progress callbacks for provider chunks" do
    fixture = capture_fixture(:binary.copy("x", 1_100_000))
    assert {:ok, plan} = ProjectSnapshotZip.prepare_capture(fixture.project_id, fixture.prepared)
    parent = self()

    _archive =
      plan
      |> ProjectSnapshotZip.stream(
        heartbeat: fn ->
          send(parent, :heartbeat)
          :ok
        end,
        on_progress: fn bytes ->
          send(parent, {:progress, bytes})
          :ok
        end
      )
      |> Enum.to_list()

    assert_received :heartbeat
    assert_received {:progress, _bytes}
  end

  test "bounds project, manifest, and ZIP output chunks for JSON payloads above five MiB" do
    fixture = capture_fixture("large JSON", asset_count: 100, metadata_bytes: 56_000)

    assert byte_size(fixture.prepared.project_json) > 5 * 1024 * 1024
    assert byte_size(fixture.prepared.manifest_json) > 5 * 1024 * 1024
    assert {:ok, plan} = ProjectSnapshotZip.prepare_capture(fixture.project_id, fixture.prepared)

    chunks = plan |> ProjectSnapshotZip.stream() |> Enum.to_list()

    assert chunks != []
    assert Enum.all?(chunks, &(byte_size(&1) <= ProjectSnapshotZip.stream_chunk_size()))

    archive = IO.iodata_to_binary(chunks)
    assert byte_size(archive) == ProjectSnapshotZip.archive_size(plan)
    assert {:ok, extracted} = :zip.extract(archive, [:memory])
    extracted = extracted_map(extracted)
    assert extracted["project.json"] == fixture.prepared.project_json
    assert extracted["manifest.json"] == fixture.prepared.manifest_json
  end

  test "rejects captures whose logical inventory was modified" do
    fixture = capture_fixture("immutable")
    modified = %{fixture.prepared | blob_count: fixture.prepared.blob_count + 1}

    assert {:error, :prepared_snapshot_capture_mismatch} =
             ProjectSnapshotZip.prepare_capture(fixture.project_id, modified)
  end

  test "preserves the capture size-limit error at the canonical archive boundary" do
    project_id = System.unique_integer([:positive])

    assert {:error, {:snapshot_object_size_limit_exceeded, :project, 1}} =
             SnapshotArchiveStorage.prepare(
               project_id,
               project_object([]),
               [],
               max_project_bytes: 1,
               source_key_mode: :protected_blob
             )
  end

  test "the canonical archive preparation rejects captures that require ZIP64" do
    project_id = System.unique_integer([:positive])

    assert {:error, :snapshot_zip_limit_exceeded} =
             oversized_prepare_result(project_id)
  end

  defp capture_fixture(bytes, opts \\ []) do
    project_id = System.unique_integer([:positive])
    hash = sha256(bytes)
    source_key = BlobStore.blob_key(project_id, hash, "png")
    asset_key = "projects/#{project_id}/assets/00000000-0000-4000-8000-000000000001/hero.png"
    assert {:ok, _url} = Storage.upload(source_key, bytes, "image/png")

    assets =
      if Keyword.get(opts, :duplicate_asset?, false) do
        [
          asset(1, project_id, "hero.png", asset_key, bytes, hash),
          asset(2, project_id, "hero.png", String.replace(asset_key, "0001/", "0002/"), bytes, hash)
        ]
      else
        metadata_bytes = Keyword.get(opts, :metadata_bytes, 0)
        metadata = if metadata_bytes > 0, do: %{"description" => String.duplicate("x", metadata_bytes)}, else: %{}

        Enum.map(1..Keyword.get(opts, :asset_count, 1), fn id ->
          asset(id, project_id, "hero-#{id}.png", asset_key, bytes, hash, metadata)
        end)
      end

    assert {:ok, prepared} =
             SnapshotArchiveStorage.prepare(
               project_id,
               project_object(assets),
               assets,
               source_key_mode: :protected_blob
             )

    manifest = Jason.decode!(prepared.manifest_json)
    blob = Enum.find(manifest["objects"], &(&1["kind"] == "asset_blob"))

    on_exit(fn -> Local.delete(source_key) end)

    %{
      project_id: project_id,
      prepared: prepared,
      source_key: source_key,
      blob_path: blob["path"],
      bytes: bytes,
      hash: hash
    }
  end

  defp oversized_prepare_result(project_id) do
    asset_size = SnapshotObjectFormat.hard_limits().max_asset_bytes

    assets =
      Enum.map(1..82, fn index ->
        oversized_asset(index, project_id, asset_size)
      end)

    SnapshotArchiveStorage.prepare(
      project_id,
      project_object(assets),
      assets,
      source_key_mode: :protected_blob
    )
  end

  defp project_object(assets) do
    metadata =
      Map.new(assets, fn asset ->
        {to_string(asset.id),
         Map.merge(
           %{
             "filename" => asset.filename,
             "content_type" => asset.content_type,
             "size" => asset.size,
             "key" => asset.key,
             "url" => asset.url,
             "project_id" => asset.project_id,
             "blob_key" => BlobStore.blob_key(asset.project_id, asset.blob_hash, "png")
           },
           asset.metadata
         )}
      end)

    %{
      "format_version" => 2,
      "project" => %{"name" => "ZIP fixture"},
      "entity_counts" => %{},
      "asset_metadata" => metadata,
      "asset_blob_hashes" => Map.new(assets, &{to_string(&1.id), &1.blob_hash}),
      "sheets" => [],
      "flows" => [],
      "scenes" => [],
      "tree" => %{"sheets" => [], "flows" => [], "scenes" => []},
      "localization" => %{"languages" => [], "texts" => [], "glossary" => []}
    }
  end

  defp asset(id, project_id, filename, key, bytes, hash, metadata \\ %{}) do
    %Asset{
      id: id,
      project_id: project_id,
      filename: filename,
      content_type: "image/png",
      size: byte_size(bytes),
      blob_hash: hash,
      key: key,
      url: "/uploads/#{key}",
      metadata: metadata,
      inserted_at: DateTime.from_unix!(id)
    }
  end

  defp oversized_asset(index, project_id, size) do
    hash = index |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(64, "0")
    filename = "asset-#{index}.png"

    %Asset{
      id: index,
      project_id: project_id,
      filename: filename,
      content_type: "image/png",
      size: size,
      blob_hash: hash,
      key: "projects/#{project_id}/assets/#{Ecto.UUID.generate()}/#{filename}",
      url: "",
      metadata: %{},
      inserted_at: DateTime.from_unix!(index)
    }
  end

  defp archive_bytes(plan) do
    plan |> ProjectSnapshotZip.stream() |> Enum.to_list() |> IO.iodata_to_binary()
  end

  defp extracted_map(entries), do: Map.new(entries, fn {name, bytes} -> {List.to_string(name), bytes} end)

  defp zip_entries(archive) do
    assert {:ok, entries} = :zip.list_dir(archive)
    Enum.filter(entries, &match?({:zip_file, _name, _info, _comment, _offset, _compressed_size}, &1))
  end

  defp zip_entry_name({:zip_file, name, _info, _comment, _offset, _compressed_size}), do: List.to_string(name)
  defp zip_entry_mtime({:zip_file, _name, info, _comment, _offset, _compressed_size}), do: elem(info, 5)

  defp zip_entry_compression_method(archive, entry) do
    <<0x04034B50::little-size(32), _version::little-size(16), _flags::little-size(16), method::little-size(16),
      _rest::binary>> =
      binary_part(archive, zip_entry_offset(entry), byte_size(archive) - zip_entry_offset(entry))

    method
  end

  defp zip_entry_version_needed(archive, entry) do
    <<0x04034B50::little-size(32), version::little-size(16), _rest::binary>> =
      binary_part(archive, zip_entry_offset(entry), byte_size(archive) - zip_entry_offset(entry))

    version
  end

  defp zip_entry_offset({:zip_file, _name, _info, _comment, offset, _compressed_size}), do: offset

  defp assert_external_zip_reader(command, archive_path, output_dir, expected_payloads) do
    case System.find_executable(command) do
      nil ->
        :ok

      executable ->
        File.mkdir_p!(output_dir)

        {output, status} =
          System.cmd(executable, extractor_args(command, archive_path, output_dir), stderr_to_stdout: true)

        assert status == 0, "#{command} rejected the generated archive:\n#{output}"

        Enum.each(expected_payloads, fn {path, bytes} ->
          assert File.read!(Path.join(output_dir, path)) == bytes
        end)
    end
  end

  defp extractor_args("unzip", archive_path, output_dir), do: ["-qq", archive_path, "-d", output_dir]
  defp extractor_args("ditto", archive_path, output_dir), do: ["-x", "-k", archive_path, output_dir]

  defp install_read_switch(replacements) do
    original = Application.fetch_env!(:storyarn, :storage)
    {:ok, _pid} = SnapshotReadSwitchStorage.start_link(replacements)
    Application.put_env(:storyarn, :storage, Keyword.put(original, :adapter, SnapshotReadSwitchStorage))

    on_exit(fn ->
      Application.put_env(:storyarn, :storage, original)
      stop_read_switch()
    end)
  end

  defp stop_read_switch do
    if Process.whereis(SnapshotReadSwitchStorage), do: Agent.stop(SnapshotReadSwitchStorage)
  catch
    :exit, _reason -> :ok
  end

  defp corrupt_same_size(<<first, rest::binary>>), do: <<Bitwise.bxor(first, 1), rest::binary>>
  defp sha256(bytes), do: bytes |> then(&:crypto.hash(:sha256, &1)) |> Base.encode16(case: :lower)
end
