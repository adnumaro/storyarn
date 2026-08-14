defmodule Storyarn.Versioning.ProjectSnapshotArchiveReader do
  @moduledoc """
  Reads and verifies the canonical classic-ZIP project snapshot archive.

  The reader trusts neither ZIP paths nor central-directory metadata. It uses
  bounded conditional range reads, checks the exact archive layout emitted by
  `ProjectSnapshotZip`, and verifies every payload byte before returning a
  restore plan. Blob entries are never assembled in memory.
  """

  alias Storyarn.Assets.BlobStore
  alias Storyarn.Assets.Storage
  alias Storyarn.Versioning.ProjectSnapshotArchiveReader.Entry
  alias Storyarn.Versioning.ProjectSnapshotArchiveReader.Plan
  alias Storyarn.Versioning.SnapshotObjectFormat

  @archive_content_type "application/zip"
  @manifest_content_type "application/json"
  @archive_filename "snapshot.zip"
  @manifest_filename "manifest.json"
  @eocd_signature 0x06054B50
  @central_signature 0x02014B50
  @local_signature 0x04034B50
  @descriptor_signature 0x08074B50
  @zip64_locator_signature 0x07064B50
  @classic_sentinel_16 0xFFFF
  @classic_sentinel_32 0xFFFFFFFF
  @eocd_bytes 22
  @max_zip_comment_bytes 65_535
  @local_header_bytes 30
  @central_header_bytes 46
  @data_descriptor_bytes 16
  @max_path_bytes 255
  @version_made_by 52
  @version_needed 20
  @canonical_flags 0x0808
  @stored_method 0
  @fixed_dos_time 0
  @fixed_dos_date 0x21
  @canonical_external_attributes 0x81A40000
  @canonical_empty_archive []
                           |> Zstream.zip(zip64: false)
                           |> Enum.to_list()
                           |> IO.iodata_to_binary()
  @canonical_comment binary_part(
                       @canonical_empty_archive,
                       @eocd_bytes,
                       byte_size(@canonical_empty_archive) - @eocd_bytes
                     )
  @sha256_regex ~r/\A[0-9a-f]{64}\z/
  @ready_key_regex ~r"""
  \Aprojects/[1-9][0-9]*/snapshots/archives/v2/ready/
  [A-Za-z0-9_-]{16}/(?:snapshot\.zip|manifest\.json)\z
  """x

  @type consume_entry :: (Entry.t(), Enumerable.t() -> :ok | {:error, term()})

  @doc """
  Verifies one ready snapshot archive and returns its immutable restore plan.

  `:consume_entry` may be a two-argument callback that synchronously consumes
  the supplied `{:ok, binary} | {:error, term()}` stream. This lets restore
  staging upload each entry during the single full-payload verification pass.
  Returning before the stream reaches its terminal verifier fails closed.
  """
  @spec verify(map(), keyword()) :: {:ok, Plan.t()} | {:error, term()}
  def verify(snapshot, opts \\ [])

  def verify(snapshot, opts) when is_map(snapshot) and is_list(opts) do
    with {:ok, consume_entry} <- consume_entry_option(opts),
         {:ok, metadata} <- snapshot_metadata(snapshot),
         {:ok, manifest_json, manifest} <- read_sidecar(metadata),
         {:ok, archive_stat} <- archive_stat(metadata),
         {:ok, eocd, eocd_bytes} <- read_eocd(metadata, archive_stat),
         {:ok, expected} <- expected_entries(manifest_json, manifest),
         :ok <- validate_eocd(eocd, expected, metadata.archive_size_bytes),
         {:ok, directory_bytes} <-
           read_exact(
             metadata.archive_key,
             eocd.directory_offset,
             eocd.directory_size,
             archive_stat
           ),
         {:ok, central_entries} <- parse_central_directory(directory_bytes, expected),
         {:ok, verified_entries} <-
           verify_local_layout(
             metadata.archive_key,
             archive_stat,
             central_entries,
             eocd.directory_offset
           ),
         {:ok, captures, archive_checksum} <-
           verify_payloads(
             metadata.archive_key,
             archive_stat,
             verified_entries,
             directory_bytes,
             eocd_bytes,
             consume_entry
           ),
         :ok <- verify_checksum(archive_checksum, metadata.archive_checksum, :snapshot_archive_checksum_mismatch),
         :ok <- verify_embedded_manifest(captures.manifest, manifest_json),
         {:ok, project} <- decode_project(captures.project),
         :ok <-
           SnapshotObjectFormat.validate_source_refs(
             project["asset_catalog_refs"],
             manifest["assets"]
           ),
         :ok <- stable_archive_stat(metadata, archive_stat) do
      entries = Enum.map(verified_entries, & &1.entry)

      {:ok,
       %Plan{
         manifest: manifest,
         project: project,
         manifest_json: manifest_json,
         archive_key: metadata.archive_key,
         archive_size_bytes: metadata.archive_size_bytes,
         archive_checksum: metadata.archive_checksum,
         archive_identity: archive_identity(archive_stat, metadata.archive_checksum),
         entries_by_path: Map.new(entries, &{&1.path, &1}),
         entry_order: Enum.map(entries, & &1.path)
       }}
    end
  end

  def verify(_snapshot, _opts), do: {:error, :invalid_snapshot_archive_read_request}

  @doc """
  Reopens one verified entry as a bounded, identity-bound stream.

  The returned stream repeats the entry size, SHA-256 and CRC-32 checks. A
  mismatch is emitted as a terminal `{:error, reason}` item so a staging upload
  cannot publish truncated or corrupt bytes as a successful object.
  """
  @spec stream_entry(Plan.t(), String.t()) :: {:ok, Enumerable.t()} | {:error, term()}
  def stream_entry(%Plan{} = plan, path) when is_binary(path) do
    with {:ok, entry} <- fetch_entry(plan, path),
         {:ok, stat} <- Storage.stat(plan.archive_key),
         :ok <- validate_replay_stat(plan, stat),
         {:ok, chunks} <-
           Storage.stream(
             plan.archive_key,
             entry.data_offset,
             entry.size_bytes,
             conditional_opts(stat)
           ) do
      {:ok, replay_stream(chunks, entry, plan, stat)}
    end
  end

  def stream_entry(_plan, _path), do: {:error, :invalid_snapshot_archive_entry_request}

  defp consume_entry_option(opts) do
    if Keyword.keyword?(opts) do
      case Keyword.get(opts, :consume_entry, &drain_entry/2) do
        callback when is_function(callback, 2) -> {:ok, callback}
        _invalid -> {:error, :invalid_snapshot_archive_entry_consumer}
      end
    else
      {:error, :invalid_snapshot_archive_reader_options}
    end
  end

  defp snapshot_metadata(%{
         project_id: project_id,
         archive_storage_key: archive_key,
         archive_size_bytes: archive_size_bytes,
         archive_checksum: archive_checksum,
         manifest_storage_key: manifest_key,
         manifest_size_bytes: manifest_size_bytes,
         manifest_checksum: manifest_checksum
       }) do
    limits = SnapshotObjectFormat.limits()

    with :ok <- validate_project_id(project_id),
         :ok <- validate_ready_keys(project_id, archive_key, manifest_key),
         :ok <- validate_archive_size(archive_size_bytes),
         :ok <- validate_manifest_size(manifest_size_bytes, limits.max_manifest_bytes),
         :ok <- validate_persisted_checksums(archive_checksum, manifest_checksum) do
      {:ok,
       %{
         project_id: project_id,
         archive_key: archive_key,
         archive_size_bytes: archive_size_bytes,
         archive_checksum: archive_checksum,
         manifest_key: manifest_key,
         manifest_size_bytes: manifest_size_bytes,
         manifest_checksum: manifest_checksum
       }}
    end
  end

  defp snapshot_metadata(_snapshot), do: {:error, :invalid_snapshot_archive_metadata}

  defp validate_project_id(project_id) when is_integer(project_id) and project_id > 0, do: :ok
  defp validate_project_id(_project_id), do: {:error, :invalid_snapshot_archive_metadata}

  defp validate_ready_keys(project_id, archive_key, manifest_key) do
    if valid_ready_key?(project_id, archive_key, @archive_filename) and
         valid_ready_key?(project_id, manifest_key, @manifest_filename) and
         Path.dirname(archive_key) == Path.dirname(manifest_key),
       do: :ok,
       else: {:error, :invalid_snapshot_archive_metadata}
  end

  defp validate_archive_size(size) when is_integer(size) and size >= @eocd_bytes and size < @classic_sentinel_32 do
    :ok
  end

  defp validate_archive_size(_size), do: {:error, :invalid_snapshot_archive_metadata}

  defp validate_manifest_size(size, maximum) when is_integer(size) and size > 0 and size <= maximum, do: :ok

  defp validate_manifest_size(_size, _maximum), do: {:error, :invalid_snapshot_archive_metadata}

  defp validate_persisted_checksums(archive_checksum, manifest_checksum) do
    if valid_sha256?(archive_checksum) and valid_sha256?(manifest_checksum),
      do: :ok,
      else: {:error, :invalid_snapshot_archive_metadata}
  end

  defp valid_ready_key?(project_id, key, filename) when is_binary(key) do
    Regex.match?(@ready_key_regex, key) and
      String.starts_with?(key, "projects/#{project_id}/snapshots/archives/v2/ready/") and
      Path.basename(key) == filename and Storage.canonical_key?(key)
  end

  defp valid_ready_key?(_project_id, _key, _filename), do: false

  defp read_sidecar(metadata) do
    with {:ok, stat} <- Storage.stat(metadata.manifest_key),
         :ok <-
           validate_object_stat(
             metadata.manifest_key,
             stat,
             metadata.manifest_size_bytes,
             @manifest_content_type
           ),
         {:ok, bytes} <-
           read_exact(metadata.manifest_key, 0, metadata.manifest_size_bytes, stat),
         :ok <- verify_checksum(sha256(bytes), metadata.manifest_checksum, :snapshot_manifest_checksum_mismatch),
         :ok <- stable_object_stat(metadata.manifest_key, stat, metadata.manifest_size_bytes, @manifest_content_type),
         {:ok, manifest} <- decode_manifest(bytes) do
      {:ok, bytes, manifest}
    end
  end

  defp decode_manifest(bytes) do
    with {:ok, manifest} <- decode_json(bytes, @manifest_filename),
         :ok <- SnapshotObjectFormat.validate_manifest(manifest) do
      {:ok, manifest}
    end
  end

  defp archive_stat(metadata) do
    with {:ok, stat} <- Storage.stat(metadata.archive_key),
         :ok <-
           validate_object_stat(
             metadata.archive_key,
             stat,
             metadata.archive_size_bytes,
             @archive_content_type
           ) do
      {:ok, stat}
    end
  end

  defp read_eocd(metadata, archive_stat) do
    tail_size = min(metadata.archive_size_bytes, @eocd_bytes + @max_zip_comment_bytes)
    tail_offset = metadata.archive_size_bytes - tail_size

    with {:ok, tail} <- read_exact(metadata.archive_key, tail_offset, tail_size, archive_stat),
         {:ok, relative_offset} <- find_eocd_offset(tail),
         {:ok, eocd, eocd_bytes} <- parse_eocd(tail, relative_offset, tail_offset),
         :ok <- reject_zip64_locator(tail, relative_offset) do
      {:ok, eocd, eocd_bytes}
    end
  end

  defp find_eocd_offset(tail) do
    offsets =
      tail
      |> :binary.matches(<<@eocd_signature::little-unsigned-integer-size(32)>>)
      |> Enum.map(&elem(&1, 0))
      |> Enum.filter(&terminal_eocd?(tail, &1))

    case offsets do
      [offset] -> {:ok, offset}
      _other -> {:error, :invalid_snapshot_zip_end_record}
    end
  end

  defp terminal_eocd?(tail, offset) when offset + @eocd_bytes <= byte_size(tail) do
    <<comment_length::little-unsigned-integer-size(16)>> = binary_part(tail, offset + 20, 2)
    offset + @eocd_bytes + comment_length == byte_size(tail)
  end

  defp terminal_eocd?(_tail, _offset), do: false

  defp parse_eocd(tail, offset, tail_offset) do
    bytes = binary_part(tail, offset, byte_size(tail) - offset)

    case bytes do
      <<@eocd_signature::little-unsigned-integer-size(32), disk_number::little-unsigned-integer-size(16),
        directory_disk::little-unsigned-integer-size(16), entries_on_disk::little-unsigned-integer-size(16),
        total_entries::little-unsigned-integer-size(16), directory_size::little-unsigned-integer-size(32),
        directory_offset::little-unsigned-integer-size(32), comment_length::little-unsigned-integer-size(16),
        comment::binary-size(comment_length)>> ->
        if comment == @canonical_comment do
          {:ok,
           %{
             offset: tail_offset + offset,
             disk_number: disk_number,
             directory_disk: directory_disk,
             entries_on_disk: entries_on_disk,
             total_entries: total_entries,
             directory_size: directory_size,
             directory_offset: directory_offset
           }, bytes}
        else
          {:error, :noncanonical_snapshot_zip_comment}
        end

      _other ->
        {:error, :invalid_snapshot_zip_end_record}
    end
  end

  defp reject_zip64_locator(tail, eocd_offset) when eocd_offset >= 20 do
    case binary_part(tail, eocd_offset - 20, 4) do
      <<@zip64_locator_signature::little-unsigned-integer-size(32)>> ->
        {:error, :snapshot_zip64_not_supported}

      _other ->
        :ok
    end
  end

  defp reject_zip64_locator(_tail, _eocd_offset), do: :ok

  defp expected_entries(manifest_json, manifest) do
    manifest_descriptor = %{
      "path" => @manifest_filename,
      "size_bytes" => byte_size(manifest_json),
      "sha256" => sha256(manifest_json),
      "content_type" => @manifest_content_type
    }

    project = manifest["project"]

    blobs =
      manifest["objects"]
      |> Enum.filter(&(&1["kind"] == "asset_blob"))
      |> Enum.sort_by(& &1["path"])

    expected = [manifest_descriptor, project | blobs]
    limits = SnapshotObjectFormat.limits()

    if length(expected) <= limits.max_objects + 1,
      do: {:ok, expected},
      else: {:error, :snapshot_zip_entry_limit_exceeded}
  end

  defp validate_eocd(eocd, expected, archive_size_bytes) do
    max_directory_bytes = length(expected) * (@central_header_bytes + @max_path_bytes)

    with :ok <- validate_classic_zip_fields(eocd),
         :ok <- validate_single_disk(eocd),
         :ok <- validate_entry_count(eocd, length(expected)),
         :ok <- validate_directory_size(eocd.directory_size, max_directory_bytes),
         :ok <- validate_directory_bounds(eocd) do
      validate_end_record_bounds(eocd, archive_size_bytes)
    end
  end

  defp validate_single_disk(%{disk_number: 0, directory_disk: 0, entries_on_disk: count, total_entries: count}), do: :ok

  defp validate_single_disk(_eocd), do: {:error, :snapshot_zip_multidisk_not_supported}

  defp validate_classic_zip_fields(eocd) do
    values = [eocd.entries_on_disk, eocd.total_entries, eocd.directory_size, eocd.directory_offset]

    if @classic_sentinel_16 in Enum.take(values, 2) or @classic_sentinel_32 in Enum.drop(values, 2),
      do: {:error, :snapshot_zip64_not_supported},
      else: :ok
  end

  defp validate_entry_count(%{total_entries: expected}, expected), do: :ok

  defp validate_entry_count(%{total_entries: actual}, expected),
    do: {:error, {:snapshot_zip_entry_count_mismatch, expected, actual}}

  defp validate_directory_size(size, maximum) when size <= maximum, do: :ok
  defp validate_directory_size(_size, _maximum), do: {:error, :snapshot_zip_central_directory_limit_exceeded}

  defp validate_directory_bounds(%{directory_offset: offset, directory_size: size, offset: end_offset})
       when offset + size == end_offset, do: :ok

  defp validate_directory_bounds(_eocd), do: {:error, :invalid_snapshot_zip_central_directory_bounds}

  defp validate_end_record_bounds(%{offset: offset}, archive_size_bytes)
       when offset + @eocd_bytes + byte_size(@canonical_comment) == archive_size_bytes, do: :ok

  defp validate_end_record_bounds(_eocd, _archive_size_bytes), do: {:error, :invalid_snapshot_zip_end_record_bounds}

  defp parse_central_directory(directory, expected) do
    directory
    |> parse_central_entries(expected, [], MapSet.new())
    |> case do
      {:ok, [], entries, _paths} -> {:ok, Enum.reverse(entries)}
      {:ok, _remaining, _entries, _paths} -> {:error, :invalid_snapshot_zip_central_directory}
      {:error, _reason} = error -> error
    end
  end

  defp parse_central_entries(<<>>, [], entries, paths), do: {:ok, [], entries, paths}

  defp parse_central_entries(directory, [descriptor | expected], entries, paths)
       when byte_size(directory) >= @central_header_bytes do
    <<signature::little-unsigned-integer-size(32), version_made_by::little-unsigned-integer-size(16),
      version_needed::little-unsigned-integer-size(16), flags::little-unsigned-integer-size(16),
      method::little-unsigned-integer-size(16), modified_time::little-unsigned-integer-size(16),
      modified_date::little-unsigned-integer-size(16), crc32::little-unsigned-integer-size(32),
      compressed_size::little-unsigned-integer-size(32), size_bytes::little-unsigned-integer-size(32),
      name_length::little-unsigned-integer-size(16), extra_length::little-unsigned-integer-size(16),
      comment_length::little-unsigned-integer-size(16), disk_start::little-unsigned-integer-size(16),
      internal_attributes::little-unsigned-integer-size(16), external_attributes::little-unsigned-integer-size(32),
      local_header_offset::little-unsigned-integer-size(32), rest::binary>> = directory

    metadata_size = name_length + extra_length + comment_length

    with true <- metadata_size <= byte_size(rest),
         <<path::binary-size(name_length), extra::binary-size(extra_length), comment::binary-size(comment_length),
           remaining::binary>> <- rest,
         :ok <-
           validate_central_entry(
             descriptor,
             path,
             paths,
             %{
               signature: signature,
               version_made_by: version_made_by,
               version_needed: version_needed,
               flags: flags,
               method: method,
               modified_time: modified_time,
               modified_date: modified_date,
               crc32: crc32,
               compressed_size: compressed_size,
               size_bytes: size_bytes,
               name_length: name_length,
               extra: extra,
               comment: comment,
               disk_start: disk_start,
               internal_attributes: internal_attributes,
               external_attributes: external_attributes,
               local_header_offset: local_header_offset
             }
           ) do
      entry = %{
        path: path,
        size_bytes: size_bytes,
        sha256: descriptor["sha256"],
        content_type: descriptor["content_type"],
        crc32: crc32,
        local_header_offset: local_header_offset
      }

      parse_central_entries(remaining, expected, [entry | entries], MapSet.put(paths, path))
    else
      false -> {:error, :invalid_snapshot_zip_central_directory}
      {:error, _reason} = error -> error
      _invalid -> {:error, :invalid_snapshot_zip_central_directory}
    end
  end

  defp parse_central_entries(_directory, _expected, _entries, _paths),
    do: {:error, :invalid_snapshot_zip_central_directory}

  defp validate_central_entry(descriptor, path, paths, metadata) do
    with :ok <- validate_central_signature_and_version(path, metadata),
         :ok <- validate_central_encoding(path, metadata),
         :ok <- validate_central_storage(path, metadata),
         :ok <- validate_central_path(path, paths, metadata),
         :ok <- validate_central_metadata(path, metadata) do
      validate_central_descriptor(descriptor, path, metadata)
    end
  end

  defp validate_central_signature_and_version(path, metadata) do
    cond do
      metadata.signature != @central_signature ->
        {:error, :invalid_snapshot_zip_central_directory}

      metadata.version_made_by != @version_made_by or metadata.version_needed != @version_needed ->
        {:error, {:unsupported_snapshot_zip_version, path}}

      true ->
        :ok
    end
  end

  defp validate_central_encoding(path, metadata) do
    cond do
      Bitwise.band(metadata.flags, 0x0001) != 0 ->
        {:error, {:encrypted_snapshot_zip_entry, path}}

      metadata.flags != @canonical_flags ->
        {:error, {:noncanonical_snapshot_zip_flags, path, metadata.flags}}

      metadata.method != @stored_method ->
        {:error, {:unsupported_snapshot_zip_compression, path, metadata.method}}

      metadata.modified_time != @fixed_dos_time or metadata.modified_date != @fixed_dos_date ->
        {:error, {:noncanonical_snapshot_zip_timestamp, path}}

      true ->
        :ok
    end
  end

  defp validate_central_storage(path, metadata) do
    cond do
      @classic_sentinel_32 in [metadata.compressed_size, metadata.size_bytes, metadata.local_header_offset] ->
        {:error, :snapshot_zip64_not_supported}

      metadata.compressed_size != metadata.size_bytes ->
        {:error, {:invalid_stored_snapshot_zip_size, path}}

      true ->
        :ok
    end
  end

  defp validate_central_path(path, paths, metadata) do
    cond do
      metadata.name_length == 0 or metadata.name_length > @max_path_bytes or not safe_path?(path) ->
        {:error, {:unsafe_snapshot_zip_path, path}}

      MapSet.member?(paths, path) ->
        {:error, {:duplicate_snapshot_zip_entry, path}}

      true ->
        :ok
    end
  end

  defp validate_central_metadata(path, metadata) do
    cond do
      metadata.extra != <<>> or metadata.comment != <<>> ->
        {:error, {:noncanonical_snapshot_zip_entry_metadata, path}}

      metadata.disk_start != 0 ->
        {:error, :snapshot_zip_multidisk_not_supported}

      metadata.internal_attributes != 0 or metadata.external_attributes != @canonical_external_attributes ->
        {:error, {:noncanonical_snapshot_zip_attributes, path}}

      true ->
        :ok
    end
  end

  defp validate_central_descriptor(descriptor, path, metadata) do
    cond do
      path != descriptor["path"] ->
        {:error, {:snapshot_zip_inventory_mismatch, descriptor["path"], path}}

      metadata.size_bytes != descriptor["size_bytes"] ->
        {:error, {:snapshot_zip_entry_size_mismatch, path, descriptor["size_bytes"], metadata.size_bytes}}

      true ->
        :ok
    end
  end

  defp verify_local_layout(archive_key, archive_stat, central_entries, directory_offset) do
    central_entries
    |> verify_local_entries(archive_key, archive_stat, directory_offset, 0, [])
    |> case do
      {:ok, verified, ^directory_offset} -> {:ok, Enum.reverse(verified)}
      {:ok, _verified, _offset} -> {:error, :invalid_snapshot_zip_local_region_bounds}
      {:error, _reason} = error -> error
    end
  end

  defp verify_local_entries([], _archive_key, _archive_stat, _directory_offset, expected_offset, verified),
    do: {:ok, verified, expected_offset}

  defp verify_local_entries([central | remaining], archive_key, archive_stat, directory_offset, expected_offset, verified) do
    next_offset =
      case remaining do
        [next | _rest] -> next.local_header_offset
        [] -> directory_offset
      end

    case verify_local_entry(archive_key, archive_stat, central, expected_offset, next_offset) do
      {:ok, entry} ->
        verify_local_entries(
          remaining,
          archive_key,
          archive_stat,
          directory_offset,
          next_offset,
          [entry | verified]
        )

      {:error, _reason} = error ->
        error
    end
  end

  defp verify_local_entry(archive_key, archive_stat, central, expected_offset, next_offset) do
    with true <- central.local_header_offset == expected_offset,
         true <- central.local_header_offset + @local_header_bytes <= next_offset,
         {:ok, fixed_header} <-
           read_exact(archive_key, central.local_header_offset, @local_header_bytes, archive_stat),
         {:ok, name_length} <- validate_local_fixed_header(fixed_header, central),
         {:ok, name} <-
           read_exact(
             archive_key,
             central.local_header_offset + @local_header_bytes,
             name_length,
             archive_stat
           ),
         true <- name == central.path,
         data_offset = central.local_header_offset + @local_header_bytes + name_length,
         descriptor_offset = data_offset + central.size_bytes,
         true <- descriptor_offset + @data_descriptor_bytes == next_offset,
         {:ok, descriptor} <-
           read_exact(archive_key, descriptor_offset, @data_descriptor_bytes, archive_stat),
         :ok <- validate_data_descriptor(descriptor, central) do
      {:ok,
       %{
         entry: %Entry{
           path: central.path,
           size_bytes: central.size_bytes,
           sha256: central.sha256,
           content_type: central.content_type,
           data_offset: data_offset,
           crc32: central.crc32,
           local_header_offset: central.local_header_offset
         },
         local_header: fixed_header <> name,
         data_descriptor: descriptor
       }}
    else
      false -> {:error, {:snapshot_zip_local_header_mismatch, central.path}}
      {:error, _reason} = error -> error
    end
  end

  defp validate_local_fixed_header(header, central) do
    case header do
      <<@local_signature::little-unsigned-integer-size(32), @version_needed::little-unsigned-integer-size(16),
        @canonical_flags::little-unsigned-integer-size(16), @stored_method::little-unsigned-integer-size(16),
        @fixed_dos_time::little-unsigned-integer-size(16), @fixed_dos_date::little-unsigned-integer-size(16),
        0::little-unsigned-integer-size(32), 0::little-unsigned-integer-size(32), 0::little-unsigned-integer-size(32),
        name_length::little-unsigned-integer-size(16), 0::little-unsigned-integer-size(16)>>
      when name_length == byte_size(central.path) ->
        {:ok, name_length}

      _other ->
        {:error, {:snapshot_zip_local_header_mismatch, central.path}}
    end
  end

  defp validate_data_descriptor(descriptor, central) do
    case descriptor do
      <<@descriptor_signature::little-unsigned-integer-size(32), crc32::little-unsigned-integer-size(32),
        compressed_size::little-unsigned-integer-size(32), size_bytes::little-unsigned-integer-size(32)>>
      when crc32 == central.crc32 and compressed_size == central.size_bytes and size_bytes == central.size_bytes ->
        :ok

      _other ->
        {:error, {:snapshot_zip_data_descriptor_mismatch, central.path}}
    end
  end

  defp verify_payloads(archive_key, archive_stat, entries, directory_bytes, eocd_bytes, consume_entry) do
    initial = {:ok, :crypto.hash_init(:sha256), %{manifest: nil, project: nil}}

    entries
    |> Enum.reduce_while(initial, fn verified, {:ok, outer_hash, captures} ->
      outer_hash = :crypto.hash_update(outer_hash, verified.local_header)

      case consume_verified_entry(archive_key, archive_stat, verified.entry, outer_hash, consume_entry) do
        {:ok, outer_hash, captured} ->
          captures = put_capture(captures, verified.entry.path, captured)
          outer_hash = :crypto.hash_update(outer_hash, verified.data_descriptor)
          {:cont, {:ok, outer_hash, captures}}

        {:error, _reason} = error ->
          {:halt, error}
      end
    end)
    |> case do
      {:ok, outer_hash, captures} ->
        checksum =
          outer_hash
          |> :crypto.hash_update(directory_bytes)
          |> :crypto.hash_update(eocd_bytes)
          |> :crypto.hash_final()
          |> Base.encode16(case: :lower)

        {:ok, captures, checksum}

      {:error, _reason} = error ->
        error
    end
  end

  defp consume_verified_entry(archive_key, archive_stat, entry, outer_hash, consume_entry) do
    with {:ok, chunks} <-
           Storage.stream(
             archive_key,
             entry.data_offset,
             entry.size_bytes,
             conditional_opts(archive_stat)
           ) do
      reference = make_ref()
      recipient = self()
      capture? = entry.path in [@manifest_filename, SnapshotObjectFormat.project_path()]

      stream = verified_stream(chunks, entry, outer_hash, capture?, recipient, reference)
      consume_result = invoke_consumer(consume_entry, entry, stream)

      verification_result =
        receive do
          {:snapshot_archive_entry_verified, ^reference, result} -> result
        after
          0 -> {:error, {:snapshot_archive_entry_stream_not_consumed, entry.path}}
        end

      merge_consumer_result(entry, verification_result, consume_result)
    end
  end

  defp verified_stream(chunks, entry, outer_hash, capture?, recipient, reference) do
    initial = %{
      sha256: :crypto.hash_init(:sha256),
      crc32: 0,
      size: 0,
      outer_hash: outer_hash,
      capture: [],
      capture?: capture?,
      failed?: false
    }

    chunks
    |> Stream.concat([:storyarn_snapshot_entry_end])
    |> Stream.transform(initial, fn
      _item, %{failed?: true} = state ->
        {:halt, state}

      {:ok, chunk}, state when is_binary(chunk) ->
        advance_verified_stream(chunk, state, entry, recipient, reference)

      {:error, reason}, state ->
        fail_verified_stream(
          {:snapshot_archive_storage_read_failed, entry.path, reason},
          state,
          recipient,
          reference
        )

      :storyarn_snapshot_entry_end, state ->
        finish_verified_stream(state, entry, recipient, reference)

      _unexpected, state ->
        fail_verified_stream(
          {:unexpected_snapshot_archive_storage_chunk, entry.path},
          state,
          recipient,
          reference
        )
    end)
  end

  defp advance_verified_stream(chunk, state, entry, recipient, reference) do
    size = state.size + byte_size(chunk)

    if size <= entry.size_bytes do
      capture = if state.capture?, do: [chunk | state.capture], else: state.capture

      state = %{
        state
        | sha256: :crypto.hash_update(state.sha256, chunk),
          crc32: :erlang.crc32(state.crc32, chunk),
          size: size,
          outer_hash: :crypto.hash_update(state.outer_hash, chunk),
          capture: capture
      }

      {[{:ok, chunk}], state}
    else
      fail_verified_stream(
        {:snapshot_zip_entry_size_mismatch, entry.path, entry.size_bytes, size},
        state,
        recipient,
        reference
      )
    end
  end

  defp finish_verified_stream(state, entry, recipient, reference) do
    checksum = state.sha256 |> :crypto.hash_final() |> Base.encode16(case: :lower)

    result =
      cond do
        state.size != entry.size_bytes ->
          {:error, {:snapshot_zip_entry_size_mismatch, entry.path, entry.size_bytes, state.size}}

        not secure_digest_equal?(checksum, entry.sha256) ->
          {:error, {:snapshot_zip_entry_checksum_mismatch, entry.path}}

        state.crc32 != entry.crc32 ->
          {:error, {:snapshot_zip_entry_crc_mismatch, entry.path}}

        true ->
          captured = if state.capture?, do: state.capture |> Enum.reverse() |> IO.iodata_to_binary()
          {:ok, state.outer_hash, captured}
      end

    send(recipient, {:snapshot_archive_entry_verified, reference, result})

    case result do
      {:ok, _outer_hash, _captured} -> {[], state}
      {:error, reason} -> {[{:error, reason}], %{state | failed?: true}}
    end
  end

  defp fail_verified_stream(reason, state, recipient, reference) do
    send(recipient, {:snapshot_archive_entry_verified, reference, {:error, reason}})
    {[{:error, reason}], %{state | failed?: true}}
  end

  defp invoke_consumer(consume_entry, entry, stream) do
    case consume_entry.(entry, stream) do
      :ok -> :ok
      {:error, _reason} = error -> error
      invalid -> {:error, {:invalid_snapshot_archive_entry_consumer_result, invalid}}
    end
  rescue
    exception -> {:error, {:snapshot_archive_entry_consumer_exception, exception}}
  catch
    kind, reason -> {:error, {:snapshot_archive_entry_consumer_throw, kind, reason}}
  end

  defp merge_consumer_result(entry, {:error, {:snapshot_archive_entry_stream_not_consumed, _path}}, {:error, reason}),
    do: {:error, {:snapshot_archive_entry_consumer_failed, entry.path, reason}}

  defp merge_consumer_result(_entry, {:error, _reason} = error, _consume_result), do: error

  defp merge_consumer_result(entry, {:ok, _outer_hash, _captured}, {:error, reason}),
    do: {:error, {:snapshot_archive_entry_consumer_failed, entry.path, reason}}

  defp merge_consumer_result(_entry, {:ok, outer_hash, captured}, :ok), do: {:ok, outer_hash, captured}

  defp put_capture(captures, @manifest_filename, bytes), do: %{captures | manifest: bytes}

  defp put_capture(captures, "project.json", bytes), do: %{captures | project: bytes}

  defp put_capture(captures, _path, _bytes), do: captures

  defp drain_entry(_entry, chunks) do
    Enum.reduce_while(chunks, :ok, fn
      {:ok, chunk}, :ok when is_binary(chunk) -> {:cont, :ok}
      {:error, reason}, :ok -> {:halt, {:error, reason}}
      _unexpected, :ok -> {:halt, {:error, :unexpected_snapshot_archive_entry_chunk}}
    end)
  end

  defp verify_embedded_manifest(embedded, sidecar)
       when is_binary(embedded) and is_binary(sidecar) and byte_size(embedded) == byte_size(sidecar) do
    if Plug.Crypto.secure_compare(embedded, sidecar),
      do: :ok,
      else: {:error, :snapshot_embedded_manifest_mismatch}
  end

  defp verify_embedded_manifest(_embedded, _sidecar), do: {:error, :snapshot_embedded_manifest_mismatch}

  defp decode_project(bytes) when is_binary(bytes) do
    with {:ok, project} <- decode_json(bytes, SnapshotObjectFormat.project_path()),
         :ok <- SnapshotObjectFormat.validate_project(project) do
      {:ok, project}
    end
  end

  defp decode_project(_bytes), do: {:error, :missing_snapshot_project_object}

  defp stable_archive_stat(metadata, archive_stat) do
    stable_object_stat(
      metadata.archive_key,
      archive_stat,
      metadata.archive_size_bytes,
      @archive_content_type
    )
  end

  defp stable_object_stat(key, initial_stat, size_bytes, content_type) do
    with {:ok, final_stat} <- Storage.stat(key),
         :ok <- validate_object_stat(key, final_stat, size_bytes, content_type),
         true <- Map.get(initial_stat, :etag) == Map.get(final_stat, :etag) do
      :ok
    else
      false -> {:error, {:snapshot_storage_identity_changed, key}}
      {:error, _reason} = error -> error
    end
  end

  defp validate_object_stat(key, %{size: size, content_type: content_type}, expected_size, expected_content_type) do
    cond do
      size != expected_size ->
        {:error, {:snapshot_object_size_mismatch, key, expected_size, size}}

      not BlobStore.compatible_content_type?(content_type, expected_content_type) ->
        {:error, {:snapshot_object_content_type_mismatch, key, expected_content_type, content_type}}

      true ->
        :ok
    end
  end

  defp validate_object_stat(key, stat, _expected_size, _expected_content_type),
    do: {:error, {:invalid_snapshot_object_stat, key, stat}}

  defp read_exact(_key, _offset, 0, _stat), do: {:ok, <<>>}

  defp read_exact(key, offset, length, stat)
       when is_integer(offset) and offset >= 0 and is_integer(length) and length > 0 do
    with {:ok, chunks} <- Storage.stream(key, offset, length, conditional_opts(stat)) do
      consume_exact_range(chunks, key, length)
    end
  end

  defp read_exact(key, _offset, _length, _stat), do: {:error, {:invalid_snapshot_storage_range, key}}

  defp consume_exact_range(chunks, key, length) do
    chunks
    |> Enum.reduce_while({:ok, [], 0}, &consume_exact_range_chunk(&1, &2, key, length))
    |> finalize_exact_range(key, length)
  end

  defp consume_exact_range_chunk({:ok, chunk}, {:ok, acc, size}, key, length) when is_binary(chunk) do
    next_size = size + byte_size(chunk)

    if next_size <= length,
      do: {:cont, {:ok, [chunk | acc], next_size}},
      else: {:halt, {:error, {:snapshot_storage_range_size_mismatch, key, length, next_size}}}
  end

  defp consume_exact_range_chunk({:error, reason}, _state, key, _length),
    do: {:halt, {:error, {:snapshot_archive_storage_read_failed, key, reason}}}

  defp consume_exact_range_chunk(_unexpected, _state, key, _length),
    do: {:halt, {:error, {:unexpected_snapshot_archive_storage_chunk, key}}}

  defp finalize_exact_range({:ok, chunks, length}, _key, length),
    do: {:ok, chunks |> Enum.reverse() |> IO.iodata_to_binary()}

  defp finalize_exact_range({:ok, _chunks, actual}, key, length),
    do: {:error, {:snapshot_storage_range_size_mismatch, key, length, actual}}

  defp finalize_exact_range({:error, _reason} = error, _key, _length), do: error

  defp fetch_entry(%Plan{entries_by_path: entries}, path) do
    case Map.fetch(entries, path) do
      {:ok, %Entry{} = entry} -> {:ok, entry}
      :error -> {:error, {:unknown_snapshot_archive_entry, path}}
      _invalid -> {:error, :invalid_snapshot_archive_plan}
    end
  end

  defp validate_replay_stat(plan, stat) do
    with :ok <- validate_object_stat(plan.archive_key, stat, plan.archive_size_bytes, @archive_content_type) do
      validate_replay_identity(plan, stat)
    end
  end

  defp validate_replay_identity(%Plan{archive_identity: {:etag, etag}} = plan, stat)
       when is_binary(etag) and etag != "" do
    if Map.get(stat, :etag) == etag,
      do: :ok,
      else: {:error, {:snapshot_storage_identity_changed, plan.archive_key}}
  end

  defp validate_replay_identity(%Plan{archive_identity: {:sha256, checksum}} = plan, _stat)
       when checksum == plan.archive_checksum, do: :ok

  defp validate_replay_identity(_plan, _stat), do: {:error, :invalid_snapshot_archive_plan}

  defp replay_stream(chunks, entry, plan, initial_stat) do
    initial = %{sha256: :crypto.hash_init(:sha256), crc32: 0, size: 0, failed?: false}

    chunks
    |> Stream.concat([:storyarn_snapshot_entry_end])
    |> Stream.transform(initial, fn
      _item, %{failed?: true} = state ->
        {:halt, state}

      {:ok, chunk}, state when is_binary(chunk) ->
        size = state.size + byte_size(chunk)

        if size <= entry.size_bytes do
          state = %{
            state
            | sha256: :crypto.hash_update(state.sha256, chunk),
              crc32: :erlang.crc32(state.crc32, chunk),
              size: size
          }

          {[{:ok, chunk}], state}
        else
          reason = {:snapshot_zip_entry_size_mismatch, entry.path, entry.size_bytes, size}
          {[{:error, reason}], %{state | failed?: true}}
        end

      {:error, reason}, state ->
        reason = {:snapshot_archive_storage_read_failed, entry.path, reason}
        {[{:error, reason}], %{state | failed?: true}}

      :storyarn_snapshot_entry_end, state ->
        finish_replay_stream(state, entry, plan, initial_stat)

      _unexpected, state ->
        reason = {:unexpected_snapshot_archive_storage_chunk, entry.path}
        {[{:error, reason}], %{state | failed?: true}}
    end)
  end

  defp finish_replay_stream(state, entry, plan, initial_stat) do
    checksum = state.sha256 |> :crypto.hash_final() |> Base.encode16(case: :lower)

    reason =
      cond do
        state.size != entry.size_bytes ->
          {:snapshot_zip_entry_size_mismatch, entry.path, entry.size_bytes, state.size}

        not secure_digest_equal?(checksum, entry.sha256) ->
          {:snapshot_zip_entry_checksum_mismatch, entry.path}

        state.crc32 != entry.crc32 ->
          {:snapshot_zip_entry_crc_mismatch, entry.path}

        true ->
          case Storage.stat(plan.archive_key) do
            {:ok, final_stat} -> replay_identity_result(plan, initial_stat, final_stat)
            {:error, stat_reason} -> {:snapshot_archive_storage_stat_failed, plan.archive_key, stat_reason}
          end
      end

    if is_nil(reason), do: {[], state}, else: {[{:error, reason}], %{state | failed?: true}}
  end

  defp replay_identity_result(plan, initial_stat, final_stat) do
    case {validate_replay_stat(plan, final_stat), Map.get(initial_stat, :etag) == Map.get(final_stat, :etag)} do
      {:ok, true} -> nil
      {{:error, reason}, _same} -> reason
      {:ok, false} -> {:snapshot_storage_identity_changed, plan.archive_key}
    end
  end

  defp archive_identity(%{etag: etag}, _checksum) when is_binary(etag) and etag != "", do: {:etag, etag}
  defp archive_identity(_stat, checksum), do: {:sha256, checksum}

  defp conditional_opts(%{etag: etag}) when is_binary(etag) and etag != "", do: [etag: etag]
  defp conditional_opts(_stat), do: []

  defp verify_checksum(actual, expected, error) do
    if secure_digest_equal?(actual, expected), do: :ok, else: {:error, error}
  end

  defp decode_json(bytes, path) do
    case Jason.decode(bytes) do
      {:ok, value} -> {:ok, value}
      {:error, reason} -> {:error, {:invalid_snapshot_object_json, path, reason}}
    end
  end

  defp safe_path?(path) when is_binary(path) do
    byte_size(path) <= @max_path_bytes and String.valid?(path) and
      SnapshotObjectFormat.safe_relative_path?(path) and not String.contains?(path, "\\")
  end

  defp safe_path?(_path), do: false

  defp sha256(bytes), do: bytes |> then(&:crypto.hash(:sha256, &1)) |> Base.encode16(case: :lower)

  defp valid_sha256?(value), do: is_binary(value) and Regex.match?(@sha256_regex, value)

  defp secure_digest_equal?(left, right)
       when is_binary(left) and is_binary(right) and byte_size(left) == 64 and byte_size(right) == 64 do
    valid_sha256?(left) and valid_sha256?(right) and Plug.Crypto.secure_compare(left, right)
  end

  defp secure_digest_equal?(_left, _right), do: false
end
