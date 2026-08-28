defmodule Storyarn.Projects.Versioning.ProjectSnapshotArchiveReaderTest do
  use ExUnit.Case, async: false

  alias Storyarn.Platform.ObjectStorage.Adapters.Local
  alias Storyarn.Projects.Assets.Asset
  alias Storyarn.Projects.Assets.BlobStore
  alias Storyarn.Projects.Assets.Storage
  alias Storyarn.Projects.Versioning.Builders.AssetHashResolver
  alias Storyarn.Projects.Versioning.ProjectSnapshotArchiveReader
  alias Storyarn.Projects.Versioning.ProjectSnapshotArchiveReader.Entry
  alias Storyarn.Projects.Versioning.ProjectSnapshotArchiveReader.Plan
  alias Storyarn.Projects.Versioning.ProjectSnapshotZip
  alias Storyarn.Projects.Versioning.SnapshotArchiveStorage
  alias Storyarn.SnapshotReadSwitchStorage

  test "classifies only explicit transient storage failures as retryable" do
    assert ProjectSnapshotArchiveReader.retryable_error?(:timeout)
    assert ProjectSnapshotArchiveReader.retryable_error?(%Req.TransportError{reason: :closed})
    assert ProjectSnapshotArchiveReader.retryable_error?(%Req.HTTPError{protocol: :http2, reason: :unprocessed})

    assert ProjectSnapshotArchiveReader.retryable_error?({:snapshot_archive_storage_read_failed, "snapshot.zip", :eio})

    assert ProjectSnapshotArchiveReader.retryable_error?(
             {:snapshot_archive_entry_consumer_failed, "assets/blob.png",
              {:staged_object_verification_failed, {:http_error, 503, nil}}}
           )

    assert ProjectSnapshotArchiveReader.retryable_error?(
             {:snapshot_archive_entry_consumer_failed, "assets/blob.png", :multipart_upload_part_timeout}
           )

    assert ProjectSnapshotArchiveReader.retryable_error?(
             {:snapshot_archive_entry_consumer_failed, "assets/blob.png",
              {:multipart_upload_abort_failed, :invalid_upload, {:http_error, 503, nil}}}
           )

    assert ProjectSnapshotArchiveReader.retryable_error?(
             {:snapshot_archive_entry_consumer_failed, "assets/blob.png",
              {:multipart_upload_failed, :error, %Req.TransportError{reason: :timeout}}}
           )

    refute ProjectSnapshotArchiveReader.retryable_error?(:unexpected_eof)
    refute ProjectSnapshotArchiveReader.retryable_error?(%Req.TransportError{reason: :nxdomain})
    refute ProjectSnapshotArchiveReader.retryable_error?(%Req.HTTPError{protocol: :http1, reason: :invalid_status_line})
    refute ProjectSnapshotArchiveReader.retryable_error?({:unsafe_snapshot_zip_path, "../project.json"})
    refute ProjectSnapshotArchiveReader.retryable_error?({:unsupported_snapshot_zip_compression, "blob", 8})
    refute ProjectSnapshotArchiveReader.retryable_error?({:snapshot_zip_entry_crc_mismatch, "blob"})
    refute ProjectSnapshotArchiveReader.retryable_error?({:snapshot_zip_entry_size_mismatch, "blob", 1, 0})

    refute ProjectSnapshotArchiveReader.retryable_error?(
             {:snapshot_archive_entry_consumer_failed, "assets/blob.png",
              {:multipart_upload_abort_failed, {:http_error, 400, nil}, :invalid_abort}}
           )

    refute ProjectSnapshotArchiveReader.retryable_error?(
             {:snapshot_archive_entry_consumer_exception, RuntimeError.exception("bug")}
           )
  end

  test "verifies the exact canonical archive and exposes bounded replay streams" do
    fixture = archive_fixture(:binary.copy("verified archive bytes", 60_000))

    assert {:ok, %Plan{} = plan} = ProjectSnapshotArchiveReader.verify(fixture.snapshot)

    assert plan.manifest == Jason.decode!(fixture.prepared.manifest_json)
    assert plan.project == Jason.decode!(fixture.prepared.project_json)
    assert plan.manifest_json == fixture.prepared.manifest_json
    assert plan.archive_identity == {:sha256, fixture.snapshot.archive_checksum}

    assert plan.entry_order == ["manifest.json", "project.json", fixture.blob_path]

    assert %Entry{
             path: blob_path,
             size_bytes: blob_size,
             sha256: blob_sha,
             content_type: "image/png",
             data_offset: data_offset,
             crc32: crc32
           } = plan.entries_by_path[fixture.blob_path]

    assert blob_path == fixture.blob_path
    assert blob_size == byte_size(fixture.bytes)
    assert blob_sha == fixture.hash
    assert data_offset > 0
    assert crc32 == :erlang.crc32(fixture.bytes)

    assert {:ok, chunks} = ProjectSnapshotArchiveReader.stream_entry(plan, fixture.blob_path)
    assert {:ok, replayed} = collect_entry(chunks)
    assert replayed == fixture.bytes
    assert Enum.all?(entry_chunks(plan, fixture.blob_path), &(byte_size(&1) <= 1_048_576))
  end

  test "preflights embedded metadata without reading asset blob payloads" do
    fixture = archive_fixture("preflight leaves blob payload unread")
    corrupted = flip_entry_byte(fixture.archive, fixture.blob_path)
    path = temporary_archive_path()
    File.write!(path, corrupted)
    on_exit(fn -> File.rm(path) end)

    assert {:ok, preflight} = ProjectSnapshotArchiveReader.preflight_file(path)
    assert preflight.manifest == Jason.decode!(fixture.prepared.manifest_json)
    assert preflight.project == nil
    assert preflight.archive_size_bytes == byte_size(corrupted)
    assert preflight.manifest_checksum == sha256(fixture.prepared.manifest_json)
    assert preflight.project_checksum == sha256(fixture.prepared.project_json)
    assert preflight.logical_asset_bytes == byte_size(fixture.bytes)
    assert preflight.asset_count == 1
    assert preflight.blob_count == 1
    assert preflight.entry_order == ["manifest.json", "project.json", fixture.blob_path]

    assert ProjectSnapshotArchiveReader.max_archive_size_bytes() == 0xFFFFFFFE

    assert {:error, {:snapshot_archive_size_limit_exceeded, maximum}} =
             ProjectSnapshotArchiveReader.preflight_file(path,
               max_archive_size_bytes: byte_size(corrupted) - 1
             )

    assert maximum == byte_size(corrupted) - 1

    assert {:error, :invalid_snapshot_archive_reader_options} =
             ProjectSnapshotArchiveReader.preflight_file(path, [:invalid])
  end

  test "fully verifies an autonomous archive without a snapshot row or manifest sidecar" do
    fixture = archive_fixture(:binary.copy("autonomous archive", 20_000))
    assert :ok = Local.delete(fixture.snapshot.manifest_storage_key)
    install_read_switch()

    archive = %{
      archive_storage_key: fixture.snapshot.archive_storage_key,
      archive_size_bytes: byte_size(fixture.archive)
    }

    assert {:ok, preflight} = ProjectSnapshotArchiveReader.preflight_archive(archive)
    assert preflight.logical_asset_bytes == byte_size(fixture.bytes)
    assert SnapshotReadSwitchStorage.stream_count(fixture.snapshot.archive_storage_key) <= 10
    assert {:ok, %Plan{} = plan} = ProjectSnapshotArchiveReader.verify_archive(archive)
    assert plan.archive_checksum == sha256(fixture.archive)
    assert plan.archive_identity == {:sha256, plan.archive_checksum}
    assert plan.manifest == Jason.decode!(fixture.prepared.manifest_json)
    assert plan.project == Jason.decode!(fixture.prepared.project_json)
    assert plan.logical_asset_bytes == byte_size(fixture.bytes)
    assert plan.entry_order == ["manifest.json", "project.json", fixture.blob_path]

    assert {:ok, chunks} = ProjectSnapshotArchiveReader.stream_entry(plan, fixture.blob_path)
    assert {:ok, fixture.bytes} == collect_entry(chunks)
  end

  test "autonomous verification detects blob corruption deferred by preflight" do
    fixture = archive_fixture("deferred corruption")
    corrupted = flip_entry_byte(fixture.archive, fixture.blob_path)
    snapshot = publish_archive_variant(fixture, corrupted)

    archive = %{
      archive_storage_key: snapshot.archive_storage_key,
      archive_size_bytes: snapshot.archive_size_bytes,
      archive_checksum: snapshot.archive_checksum
    }

    assert {:error, {:snapshot_zip_entry_checksum_mismatch, blob_path}} =
             ProjectSnapshotArchiveReader.verify_archive(archive)

    assert blob_path == fixture.blob_path
  end

  test "streams every verified entry through a synchronous staging consumer" do
    fixture = archive_fixture(:binary.copy("staged", 190_000))
    parent = self()

    consume = fn entry, chunks ->
      case collect_entry(chunks) do
        {:ok, bytes} ->
          send(parent, {:staged, entry.path, bytes})
          :ok

        {:error, reason} ->
          {:error, reason}
      end
    end

    assert {:ok, plan} = ProjectSnapshotArchiveReader.verify(fixture.snapshot, consume_entry: consume)
    assert_receive {:staged, "manifest.json", manifest}
    assert_receive {:staged, "project.json", project}
    assert_receive {:staged, blob_path, blob}
    assert blob_path == fixture.blob_path
    assert manifest == fixture.prepared.manifest_json
    assert project == fixture.prepared.project_json
    assert blob == fixture.bytes
    assert plan.entry_order == ["manifest.json", "project.json", fixture.blob_path]
  end

  test "fails closed when a staging consumer does not drain the entry" do
    fixture = archive_fixture("must be consumed")

    assert {:error, {:snapshot_archive_entry_stream_not_consumed, "manifest.json"}} =
             ProjectSnapshotArchiveReader.verify(fixture.snapshot,
               consume_entry: fn _entry, _chunks -> :ok end
             )
  end

  test "rejects project asset references that do not bind the exact manifest catalog" do
    fixture = archive_fixture("catalog binding")

    project =
      fixture.prepared.project_json
      |> Jason.decode!()
      |> put_in(["asset_catalog_refs", "1"], "asset-999999")

    project_json = Jason.encode!(project)

    manifest =
      fixture.prepared.manifest_json
      |> Jason.decode!()
      |> update_project_descriptor(project_json)

    manifest_json = Jason.encode!(manifest)

    archive =
      zip_from_entries([
        {"manifest.json", manifest_json},
        {"project.json", project_json},
        {fixture.blob_path, fixture.bytes}
      ])

    snapshot = publish_archive_pair_variant(fixture, archive, manifest_json)

    assert {:error, :asset_source_refs_mismatch} =
             ProjectSnapshotArchiveReader.verify(snapshot)
  end

  test "rejects an embedded manifest that is not byte-identical to the sidecar" do
    fixture = archive_fixture("sidecar identity")
    embedded = corrupt_same_size(fixture.prepared.manifest_json)
    archive = replace_entry(fixture, "manifest.json", embedded)
    snapshot = publish_archive_variant(fixture, archive)

    assert {:error, {:snapshot_zip_entry_checksum_mismatch, "manifest.json"}} =
             ProjectSnapshotArchiveReader.verify(snapshot)
  end

  test "rejects extra, duplicate, unsafe, encrypted and compressed entries" do
    fixture = archive_fixture("structural attacks")

    attacks = [
      {
        add_stored_entry(fixture.archive, "extra.txt", "extra"),
        {:snapshot_zip_entry_count_mismatch, 3, 4}
      },
      {
        duplicate_entry_archive(fixture),
        {:duplicate_snapshot_zip_entry, "manifest.json"}
      },
      {
        rename_entry(fixture.archive, "manifest.json", "../unsafe.jsn"),
        {:unsafe_snapshot_zip_path, "../unsafe.jsn"}
      },
      {
        put_central_flags(fixture.archive, fixture.blob_path, 0x0809),
        {:encrypted_snapshot_zip_entry, fixture.blob_path}
      },
      {put_central_method(fixture.archive, fixture.blob_path, 8),
       {:unsupported_snapshot_zip_compression, fixture.blob_path, 8}}
    ]

    Enum.each(attacks, fn {archive, expected_error} ->
      snapshot = publish_archive_variant(fixture, archive)
      assert {:error, ^expected_error} = ProjectSnapshotArchiveReader.verify(snapshot)
    end)
  end

  test "rejects ZIP64, multidisk, local-header mismatch, overlap and out-of-bounds metadata" do
    fixture = archive_fixture("layout attacks")

    attacks = [
      {put_eocd_field(fixture.archive, :entries_on_disk, 0xFFFF), :snapshot_zip64_not_supported},
      {put_eocd_field(fixture.archive, :disk_number, 1), :snapshot_zip_multidisk_not_supported},
      {put_local_flags(fixture.archive, fixture.blob_path, 0x0800),
       {:snapshot_zip_local_header_mismatch, fixture.blob_path}},
      {put_central_local_offset(fixture.archive, fixture.blob_path, 0),
       {:snapshot_zip_local_header_mismatch, "project.json"}},
      {put_eocd_field(fixture.archive, :directory_offset, byte_size(fixture.archive)),
       :invalid_snapshot_zip_central_directory_bounds}
    ]

    Enum.each(attacks, fn {archive, expected_error} ->
      snapshot = publish_archive_variant(fixture, archive)
      assert {:error, ^expected_error} = ProjectSnapshotArchiveReader.verify(snapshot)
    end)
  end

  test "rejects CRC, size and digest corruption before returning a plan" do
    fixture = archive_fixture("payload corruption")

    crc_archive = put_central_crc(fixture.archive, fixture.blob_path, 0)
    snapshot = publish_archive_variant(fixture, crc_archive)

    assert {:error, {:snapshot_zip_data_descriptor_mismatch, blob_path}} =
             ProjectSnapshotArchiveReader.verify(snapshot)

    assert blob_path == fixture.blob_path

    truncated = binary_part(fixture.archive, 0, byte_size(fixture.archive) - 1)
    snapshot = publish_archive_variant(fixture, truncated)
    assert {:error, :invalid_snapshot_zip_end_record} = ProjectSnapshotArchiveReader.verify(snapshot)

    corrupted = flip_entry_byte(fixture.archive, fixture.blob_path)
    snapshot = publish_archive_variant(fixture, corrupted)

    assert {:error, {:snapshot_zip_entry_checksum_mismatch, blob_path}} =
             ProjectSnapshotArchiveReader.verify(snapshot)

    assert blob_path == fixture.blob_path
  end

  test "binds every range read and replay to the captured ETag" do
    fixture = archive_fixture("etag binding")
    parent = self()
    install_read_switch()

    SnapshotReadSwitchStorage.set_stat_result(fn key ->
      case Local.stat(key) do
        {:ok, stat} -> {:ok, %{stat | etag: "immutable-etag"}}
        error -> error
      end
    end)

    SnapshotReadSwitchStorage.set_stream_result(fn key, offset, length, opts ->
      send(parent, {:range, key, offset, length, opts})
      Local.stream(key, offset, length, opts)
    end)

    assert {:ok, plan} = ProjectSnapshotArchiveReader.verify(fixture.snapshot)
    assert plan.archive_identity == {:etag, "immutable-etag"}
    assert_receive {:range, _, _, _, [etag: "immutable-etag"]}

    assert {:ok, replay} = ProjectSnapshotArchiveReader.stream_entry(plan, fixture.blob_path)
    assert {:ok, _bytes} = collect_entry(replay)
    assert_receive {:range, _, _, _, [etag: "immutable-etag"]}
  end

  test "fails when the object identity changes across verification" do
    fixture = archive_fixture("identity race")
    install_read_switch()
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    SnapshotReadSwitchStorage.set_stat_result(fn key ->
      value = Agent.get_and_update(counter, fn count -> {count, count + 1} end)

      case Local.stat(key) do
        {:ok, stat} -> {:ok, %{stat | etag: "etag-#{value}"}}
        error -> error
      end
    end)

    assert {:error, {:snapshot_storage_identity_changed, key}} =
             ProjectSnapshotArchiveReader.verify(fixture.snapshot)

    assert key == fixture.snapshot.manifest_storage_key
  end

  defp archive_fixture(bytes) do
    project_id = System.unique_integer([:positive])
    hash = sha256(bytes)
    source_key = BlobStore.blob_key(project_id, hash, "png")
    asset_key = "projects/#{project_id}/assets/#{Ecto.UUID.generate()}/hero.png"
    token = Ecto.UUID.generate() |> String.replace("-", "") |> binary_part(0, 16)
    prefix = SnapshotArchiveStorage.ready_prefix(project_id, token)
    archive_key = SnapshotArchiveStorage.archive_key(prefix)
    manifest_key = SnapshotArchiveStorage.manifest_key(prefix)
    assert {:ok, _url} = Storage.upload(source_key, bytes, "image/png")

    asset = %Asset{
      id: 1,
      project_id: project_id,
      filename: "hero.png",
      content_type: "image/png",
      size: byte_size(bytes),
      blob_hash: hash,
      key: asset_key,
      url: "/uploads/#{asset_key}",
      metadata: %{},
      inserted_at: DateTime.from_unix!(1)
    }

    project = %{
      "format_version" => 2,
      "asset_restore_contract_version" => AssetHashResolver.exact_restore_contract_version(),
      "project" => %{"name" => "Archive reader fixture"},
      "entity_counts" => %{},
      "asset_metadata" => %{
        "1" => %{
          "filename" => asset.filename,
          "content_type" => asset.content_type,
          "size" => asset.size,
          "key" => asset.key,
          "url" => asset.url,
          "project_id" => project_id,
          "blob_key" => source_key
        }
      },
      "asset_blob_hashes" => %{"1" => hash},
      "sheets" => [],
      "flows" => [],
      "scenes" => [],
      "tree" => %{"sheets" => [], "flows" => [], "scenes" => []},
      "localization" => %{"languages" => [], "texts" => [], "glossary" => []}
    }

    assert {:ok, prepared} =
             SnapshotArchiveStorage.prepare(project_id, project, [asset], source_key_mode: :protected_blob)

    assert {:ok, zip_plan} = ProjectSnapshotZip.prepare_capture(project_id, prepared)
    archive = zip_plan |> ProjectSnapshotZip.stream() |> Enum.to_list() |> IO.iodata_to_binary()
    assert {:ok, _url} = Storage.upload(archive_key, archive, "application/zip")
    assert {:ok, _url} = Storage.upload(manifest_key, prepared.manifest_json, "application/json")

    on_exit(fn ->
      Local.delete(source_key)
      Local.delete(archive_key)
      Local.delete(manifest_key)
    end)

    manifest = Jason.decode!(prepared.manifest_json)
    blob = Enum.find(manifest["objects"], &(&1["kind"] == "asset_blob"))

    snapshot = %{
      project_id: project_id,
      archive_storage_key: archive_key,
      archive_size_bytes: byte_size(archive),
      archive_checksum: sha256(archive),
      manifest_storage_key: manifest_key,
      manifest_size_bytes: byte_size(prepared.manifest_json),
      manifest_checksum: sha256(prepared.manifest_json)
    }

    %{
      project_id: project_id,
      bytes: bytes,
      hash: hash,
      archive: archive,
      snapshot: snapshot,
      prepared: prepared,
      blob_path: blob["path"]
    }
  end

  defp publish_archive_variant(fixture, archive) do
    assert {:ok, _url} = Storage.upload(fixture.snapshot.archive_storage_key, archive, "application/zip")

    %{
      fixture.snapshot
      | archive_size_bytes: byte_size(archive),
        archive_checksum: sha256(archive)
    }
  end

  defp publish_archive_pair_variant(fixture, archive, manifest_json) do
    assert {:ok, _url} = Storage.upload(fixture.snapshot.archive_storage_key, archive, "application/zip")

    assert {:ok, _url} =
             Storage.upload(fixture.snapshot.manifest_storage_key, manifest_json, "application/json")

    %{
      fixture.snapshot
      | archive_size_bytes: byte_size(archive),
        archive_checksum: sha256(archive),
        manifest_size_bytes: byte_size(manifest_json),
        manifest_checksum: sha256(manifest_json)
    }
  end

  defp update_project_descriptor(manifest, project_json) do
    descriptor = %{
      manifest["project"]
      | "sha256" => sha256(project_json),
        "size_bytes" => byte_size(project_json)
    }

    %{
      manifest
      | "project" => descriptor,
        "objects" =>
          Enum.map(manifest["objects"], fn
            %{"kind" => "project"} -> descriptor
            object -> object
          end),
        "payload_size_bytes" =>
          Enum.reduce(manifest["objects"], 0, fn
            %{"kind" => "project"}, total -> total + byte_size(project_json)
            object, total -> total + object["size_bytes"]
          end)
    }
  end

  defp replace_entry(fixture, path, bytes) do
    entries =
      fixture.archive
      |> extract_archive()
      |> Enum.map(fn
        {^path, _old_bytes} -> {path, bytes}
        other -> other
      end)

    zip_from_entries(entries)
  end

  defp duplicate_entry_archive(fixture) do
    zip_from_entries([
      {"manifest.json", fixture.prepared.manifest_json},
      {"manifest.json", fixture.prepared.project_json},
      {fixture.blob_path, fixture.bytes}
    ])
  end

  defp add_stored_entry(archive, path, bytes), do: zip_from_entries(extract_archive(archive) ++ [{path, bytes}])

  defp extract_archive(archive) do
    assert {:ok, entries} = :zip.extract(archive, [:memory])
    Enum.map(entries, fn {path, bytes} -> {List.to_string(path), bytes} end)
  end

  defp zip_from_entries(entries) do
    entries
    |> Enum.map(fn {path, bytes} ->
      Zstream.entry(path, [bytes], coder: Zstream.Coder.Stored, mtime: ~N[1980-01-01 00:00:00])
    end)
    |> Zstream.zip(zip64: false)
    |> Enum.to_list()
    |> IO.iodata_to_binary()
  end

  defp rename_entry(archive, from, to) when byte_size(from) == byte_size(to) do
    entry = central_entry(archive, from)

    archive
    |> replace_bytes(entry.central_offset + 46, byte_size(from), to)
    |> replace_bytes(entry.local_offset + 30, byte_size(from), to)
  end

  defp put_central_flags(archive, path, flags), do: put_central_u16(archive, path, 8, flags)
  defp put_central_method(archive, path, method), do: put_central_u16(archive, path, 10, method)
  defp put_central_crc(archive, path, crc), do: put_central_u32(archive, path, 16, crc)

  defp put_central_local_offset(archive, path, offset), do: put_central_u32(archive, path, 42, offset)

  defp put_local_flags(archive, path, flags) do
    entry = central_entry(archive, path)
    replace_bytes(archive, entry.local_offset + 6, 2, <<flags::little-unsigned-integer-size(16)>>)
  end

  defp put_central_u16(archive, path, field_offset, value) do
    entry = central_entry(archive, path)

    replace_bytes(
      archive,
      entry.central_offset + field_offset,
      2,
      <<value::little-unsigned-integer-size(16)>>
    )
  end

  defp put_central_u32(archive, path, field_offset, value) do
    entry = central_entry(archive, path)

    replace_bytes(
      archive,
      entry.central_offset + field_offset,
      4,
      <<value::little-unsigned-integer-size(32)>>
    )
  end

  defp put_eocd_field(archive, field, value) do
    eocd = eocd_offset(archive)

    {offset, size} =
      case field do
        :disk_number -> {4, 2}
        :entries_on_disk -> {8, 2}
        :directory_offset -> {16, 4}
      end

    encoded =
      case size do
        2 -> <<value::little-unsigned-integer-size(16)>>
        4 -> <<value::little-unsigned-integer-size(32)>>
      end

    replace_bytes(archive, eocd + offset, size, encoded)
  end

  defp flip_entry_byte(archive, path) do
    entry = central_entry(archive, path)
    data_offset = entry.local_offset + 30 + byte_size(path)
    <<byte>> = binary_part(archive, data_offset, 1)
    replace_bytes(archive, data_offset, 1, <<Bitwise.bxor(byte, 1)>>)
  end

  defp central_entry(archive, wanted_path) do
    eocd = eocd_offset(archive)

    <<_signature::little-32, _disk::little-16, _dir_disk::little-16, _entries::little-16, total::little-16,
      directory_size::little-32, directory_offset::little-32, _comment_length::little-16, _comment::binary>> =
      binary_part(archive, eocd, byte_size(archive) - eocd)

    directory = binary_part(archive, directory_offset, directory_size)
    find_central_entry(directory, directory_offset, total, wanted_path)
  end

  defp find_central_entry(directory, absolute_offset, remaining, wanted_path) when remaining > 0 do
    <<0x02014B50::little-32, _fixed::binary-size(24), name_len::little-16, extra_len::little-16, comment_len::little-16,
      _disk_start::little-16, _attrs::binary-size(6), local::little-32, rest::binary>> =
      directory

    <<path::binary-size(name_len), _extra::binary-size(extra_len), _comment::binary-size(comment_len), tail::binary>> =
      rest

    if path == wanted_path do
      %{central_offset: absolute_offset, local_offset: local}
    else
      consumed = 46 + name_len + extra_len + comment_len
      find_central_entry(tail, absolute_offset + consumed, remaining - 1, wanted_path)
    end
  end

  defp eocd_offset(archive) do
    archive
    |> :binary.matches(<<0x50, 0x4B, 0x05, 0x06>>)
    |> List.last()
    |> elem(0)
  end

  defp replace_bytes(binary, offset, length, replacement) when byte_size(replacement) == length do
    prefix = binary_part(binary, 0, offset)
    suffix_offset = offset + length
    suffix = binary_part(binary, suffix_offset, byte_size(binary) - suffix_offset)
    prefix <> replacement <> suffix
  end

  defp collect_entry(chunks) do
    chunks
    |> Enum.reduce_while({:ok, []}, fn
      {:ok, chunk}, {:ok, acc} when is_binary(chunk) -> {:cont, {:ok, [chunk | acc]}}
      {:error, reason}, _state -> {:halt, {:error, reason}}
      _unexpected, _state -> {:halt, {:error, :unexpected_chunk}}
    end)
    |> case do
      {:ok, chunks} -> {:ok, chunks |> Enum.reverse() |> IO.iodata_to_binary()}
      {:error, _reason} = error -> error
    end
  end

  defp entry_chunks(plan, path) do
    assert {:ok, chunks} = ProjectSnapshotArchiveReader.stream_entry(plan, path)
    for {:ok, chunk} <- chunks, do: chunk
  end

  defp install_read_switch do
    original = Application.fetch_env!(:storyarn, :storage)
    {:ok, pid} = SnapshotReadSwitchStorage.start_link(%{})
    Process.unlink(pid)
    Application.put_env(:storyarn, :storage, Keyword.put(original, :adapter, SnapshotReadSwitchStorage))

    on_exit(fn ->
      Application.put_env(:storyarn, :storage, original)
      Agent.stop(pid)
    end)
  end

  defp temporary_archive_path do
    Path.join(System.tmp_dir!(), "storyarn-snapshot-#{Ecto.UUID.generate()}.zip")
  end

  defp sha256(bytes), do: bytes |> then(&:crypto.hash(:sha256, &1)) |> Base.encode16(case: :lower)

  defp corrupt_same_size(<<first, rest::binary>>), do: <<Bitwise.bxor(first, 1), rest::binary>>
end
