defmodule Storyarn.Versioning.ProjectSnapshotZip do
  @moduledoc """
  Encodes one immutable full-snapshot capture as its canonical ZIP archive.

  Preparation is pure with respect to object storage: it validates the durable
  capture, fixes the entry order and calculates the exact classic-ZIP size.
  Source blobs are read lazily only when `stream/2` is consumed by the snapshot
  worker. Every provider read is checked against the manifest before the ZIP
  can receive its central directory.
  """

  alias Storyarn.Assets.BlobStore
  alias Storyarn.Assets.Storage
  alias Storyarn.Versioning.SnapshotObjectFormat

  @fixed_mtime ~N[1980-01-01 00:00:00]
  @classic_zip_max_32bit_value 0xFFFF_FFFE
  @classic_zip_max_entries 0xFFFE
  @classic_zip_local_header_bytes 30
  @classic_zip_data_descriptor_bytes 16
  @classic_zip_central_directory_header_bytes 46

  # With no entries and ZIP64 disabled, Zstream emits only its classic ZIP end
  # record, including its implementation-defined archive comment. Derive the
  # size through the public API at compile time instead of copying that private
  # comment's length into the archive-size contract.
  @classic_zip_end_record_bytes []
                                |> Zstream.zip(zip64: false)
                                |> Enum.to_list()
                                |> IO.iodata_length()
  @stream_chunk_size 1_048_576
  @max_zip_path_bytes 255
  @sha256_regex ~r/\A[0-9a-f]{64}\z/

  @capture_fields [
    :capture_digest,
    :project_json,
    :manifest_json,
    :source_keys,
    :project_size_bytes,
    :project_checksum,
    :manifest_size_bytes,
    :manifest_checksum,
    :total_size_bytes,
    :asset_blob_size_bytes,
    :object_count,
    :asset_count,
    :blob_count
  ]

  @enforce_keys [:project_id, :entries, :archive_size_bytes, :manifest_json, :heartbeat]
  defstruct [:project_id, :entries, :archive_size_bytes, :manifest_json, :heartbeat]

  @type memory_entry :: %{
          kind: :memory,
          path: String.t(),
          bytes: binary(),
          size_bytes: non_neg_integer(),
          sha256: String.t(),
          content_type: String.t()
        }
  @type storage_entry :: %{
          kind: :storage,
          path: String.t(),
          key: Storage.key(),
          size_bytes: non_neg_integer(),
          sha256: String.t(),
          content_type: String.t()
        }
  @type entry :: memory_entry() | storage_entry()

  @opaque t :: %__MODULE__{
            project_id: pos_integer(),
            entries: [entry()],
            archive_size_bytes: pos_integer(),
            manifest_json: binary(),
            heartbeat: (-> :ok | {:error, term()})
          }

  @doc """
  Validates and plans the canonical ZIP for a previously materialized capture.

  This function performs no provider I/O. The returned archive size is exact,
  including every local header, data descriptor, central-directory entry and
  the fixed Zstream end record.
  """
  @spec prepare_capture(pos_integer(), map(), keyword()) :: {:ok, t()} | {:error, term()}
  def prepare_capture(project_id, prepared, opts \\ [])

  def prepare_capture(project_id, prepared, opts)
      when is_integer(project_id) and project_id > 0 and is_map(prepared) and is_list(opts) do
    with true <- Keyword.keyword?(opts),
         {:ok, heartbeat} <- heartbeat_option(opts),
         {:ok, source} <- validate_capture(project_id, prepared),
         entries = build_entries(prepared, source),
         :ok <- validate_entries(entries),
         {:ok, archive_size_bytes} <- exact_archive_size(entries) do
      {:ok,
       %__MODULE__{
         project_id: project_id,
         entries: entries,
         archive_size_bytes: archive_size_bytes,
         manifest_json: prepared.manifest_json,
         heartbeat: heartbeat
       }}
    else
      false -> {:error, :invalid_snapshot_zip_options}
      {:error, _reason} = error -> error
      _invalid -> {:error, :invalid_prepared_snapshot_capture}
    end
  end

  def prepare_capture(_project_id, _prepared, _opts), do: {:error, :invalid_prepared_snapshot_capture}

  @doc """
  Returns a lazy stream of deterministic raw ZIP chunks.

  The ZIP always uses STORE, a fixed DOS timestamp and classic ZIP headers.
  Storage source errors abort enumeration before a valid central directory is
  emitted. Callers uploading through `Storage.upload_stream/3` must wrap each
  returned binary as `{:ok, binary}`.
  """
  @spec stream(t(), keyword()) :: Enumerable.t()
  def stream(plan, opts \\ [])

  def stream(%__MODULE__{} = plan, opts) when is_list(opts) do
    heartbeat = stream_callback!(opts, :heartbeat, plan.heartbeat, 0)
    on_progress = stream_callback!(opts, :on_progress, fn _bytes -> :ok end, 1)
    progress = :atomics.new(1, signed: false)

    plan.entries
    |> Stream.map(fn entry ->
      run_stream_callback!(heartbeat, [], :snapshot_zip_heartbeat_failed)

      Zstream.entry(
        entry.path,
        entry_stream(entry, heartbeat, on_progress, progress),
        coder: Zstream.Coder.Stored,
        mtime: @fixed_mtime
      )
    end)
    |> Zstream.zip(zip64: false)
    |> Stream.flat_map(fn iodata ->
      iodata
      |> :erlang.iolist_to_iovec()
      |> Stream.flat_map(&binary_chunk_stream/1)
    end)
  end

  def stream(_plan, _opts), do: raise(ArgumentError, "invalid snapshot ZIP plan")

  @doc false
  @spec archive_size(t()) :: pos_integer()
  def archive_size(%__MODULE__{archive_size_bytes: size}), do: size

  @doc false
  @spec stream_chunk_size() :: pos_integer()
  def stream_chunk_size, do: @stream_chunk_size

  defp validate_capture(
         project_id,
         %{project_json: project_json, manifest_json: manifest_json, source_keys: source_keys} = prepared
       )
       when is_binary(project_json) and is_binary(manifest_json) and is_map(source_keys) do
    with {:ok, project} <- decode_json(project_json, SnapshotObjectFormat.project_path()),
         :ok <- SnapshotObjectFormat.validate_project(project),
         {:ok, manifest} <- decode_json(manifest_json, SnapshotObjectFormat.manifest_path()),
         :ok <- SnapshotObjectFormat.validate_manifest(manifest),
         project_descriptor = manifest["project"],
         :ok <- validate_project_descriptor(project_descriptor, project_json),
         :ok <- validate_sources(project_id, manifest["objects"], source_keys),
         expected = expected_capture(project_json, manifest_json, manifest, source_keys),
         true <- Map.take(prepared, @capture_fields) == expected do
      {:ok,
       %{
         manifest: manifest,
         project_descriptor: project_descriptor,
         blobs: manifest["objects"] |> Enum.filter(&(&1["kind"] == "asset_blob")) |> Enum.sort_by(& &1["path"])
       }}
    else
      false -> {:error, :prepared_snapshot_capture_mismatch}
      {:error, _reason} = error -> error
      _invalid -> {:error, :invalid_prepared_snapshot_capture}
    end
  end

  defp validate_capture(_project_id, _prepared), do: {:error, :invalid_prepared_snapshot_capture}

  defp expected_capture(project_json, manifest_json, manifest, source_keys) do
    project = manifest["project"]
    counts = manifest["counts"]
    manifest_size = byte_size(manifest_json)
    total_size = manifest["payload_size_bytes"] + manifest_size

    capture = %{
      project_json: project_json,
      manifest_json: manifest_json,
      source_keys: source_keys,
      project_size_bytes: project["size_bytes"],
      project_checksum: project["sha256"],
      manifest_size_bytes: manifest_size,
      manifest_checksum: sha256(manifest_json),
      total_size_bytes: total_size,
      asset_blob_size_bytes: total_size - project["size_bytes"] - manifest_size,
      object_count: counts["payload_objects"] + 1,
      asset_count: counts["assets"],
      blob_count: counts["blobs"]
    }

    Map.put(capture, :capture_digest, capture_digest(capture))
  end

  defp validate_project_descriptor(
         %{
           "kind" => "project",
           "path" => "project.json",
           "sha256" => checksum,
           "size_bytes" => size_bytes,
           "content_type" => "application/json"
         },
         project_json
       ) do
    if size_bytes == byte_size(project_json) and secure_digest_equal?(sha256(project_json), checksum),
      do: :ok,
      else: {:error, :prepared_snapshot_project_mismatch}
  end

  defp validate_project_descriptor(_descriptor, _project_json), do: {:error, :prepared_snapshot_project_mismatch}

  defp validate_sources(project_id, objects, source_keys) when is_list(objects) do
    blobs = Enum.filter(objects, &(&1["kind"] == "asset_blob"))
    hashes = MapSet.new(blobs, & &1["sha256"])

    if MapSet.new(Map.keys(source_keys)) == hashes and
         Enum.all?(blobs, &valid_source?(project_id, &1, source_keys)) do
      :ok
    else
      {:error, :prepared_snapshot_source_inventory_mismatch}
    end
  end

  defp validate_sources(_project_id, _objects, _source_keys), do: {:error, :prepared_snapshot_source_inventory_mismatch}

  defp valid_source?(project_id, descriptor, source_keys) do
    hash = descriptor["sha256"]
    content_type = descriptor["content_type"]
    expected = BlobStore.blob_key(project_id, hash, BlobStore.ext_from_content_type(content_type))

    Map.get(source_keys, hash) == expected and Storage.canonical_key?(expected)
  end

  defp build_entries(prepared, source) do
    manifest_entry = memory_entry(SnapshotObjectFormat.manifest_path(), prepared.manifest_json)
    project_entry = memory_entry(SnapshotObjectFormat.project_path(), prepared.project_json)

    blob_entries =
      Enum.map(source.blobs, fn descriptor ->
        %{
          kind: :storage,
          path: descriptor["path"],
          key: Map.fetch!(prepared.source_keys, descriptor["sha256"]),
          size_bytes: descriptor["size_bytes"],
          sha256: descriptor["sha256"],
          content_type: descriptor["content_type"]
        }
      end)

    [manifest_entry, project_entry | blob_entries]
  end

  defp memory_entry(path, bytes) do
    %{
      kind: :memory,
      path: path,
      bytes: bytes,
      size_bytes: byte_size(bytes),
      sha256: sha256(bytes),
      content_type: "application/json"
    }
  end

  defp validate_entries(entries) do
    limits = SnapshotObjectFormat.limits()

    entries
    |> Enum.reduce_while({:ok, MapSet.new()}, fn entry, {:ok, paths} ->
      case validate_entry(entry, paths) do
        {:ok, paths} -> {:cont, {:ok, paths}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, _paths} when length(entries) <= limits.max_objects + 1 -> :ok
      {:ok, _paths} -> {:error, :snapshot_zip_limit_exceeded}
      {:error, _reason} = error -> error
    end
  end

  defp validate_entry(entry, paths) do
    with :ok <- validate_entry_path(entry),
         :ok <- validate_unique_entry_path(entry, paths),
         :ok <- validate_entry_size(entry),
         :ok <- validate_entry_checksum(entry),
         :ok <- validate_entry_source(entry) do
      {:ok, MapSet.put(paths, entry.path)}
    end
  end

  defp validate_entry_path(entry) do
    if safe_zip_path?(entry.path),
      do: :ok,
      else: {:error, {:invalid_snapshot_zip_entry_path, entry.path}}
  end

  defp validate_unique_entry_path(entry, paths) do
    if MapSet.member?(paths, entry.path),
      do: {:error, {:duplicate_snapshot_zip_entry_path, entry.path}},
      else: :ok
  end

  defp validate_entry_size(entry) do
    if is_integer(entry.size_bytes) and entry.size_bytes >= 0,
      do: :ok,
      else: {:error, {:invalid_snapshot_zip_entry_size, entry.path}}
  end

  defp validate_entry_checksum(entry) do
    if valid_sha256?(entry.sha256),
      do: :ok,
      else: {:error, {:invalid_snapshot_zip_entry_checksum, entry.path}}
  end

  defp validate_entry_source(%{kind: :storage} = entry) do
    if Storage.canonical_key?(entry.key),
      do: :ok,
      else: {:error, {:invalid_snapshot_zip_source_key, entry.path}}
  end

  defp validate_entry_source(_entry), do: :ok

  defp exact_archive_size(entries) do
    with true <- length(entries) <= @classic_zip_max_entries,
         {:ok, local_region_size} <- local_region_size(entries),
         central_directory_size =
           Enum.reduce(entries, 0, fn entry, size ->
             size + @classic_zip_central_directory_header_bytes + byte_size(entry.path)
           end),
         true <- central_directory_size <= @classic_zip_max_32bit_value,
         archive_size = local_region_size + central_directory_size + @classic_zip_end_record_bytes,
         true <- archive_size <= @classic_zip_max_32bit_value do
      {:ok, archive_size}
    else
      false -> {:error, :snapshot_zip_limit_exceeded}
      {:error, _reason} = error -> error
    end
  end

  defp local_region_size(entries) do
    Enum.reduce_while(entries, {:ok, 0}, fn entry, {:ok, offset} ->
      next_offset =
        offset + @classic_zip_local_header_bytes + byte_size(entry.path) + entry.size_bytes +
          @classic_zip_data_descriptor_bytes

      if entry.size_bytes <= @classic_zip_max_32bit_value and
           offset <= @classic_zip_max_32bit_value and next_offset <= @classic_zip_max_32bit_value do
        {:cont, {:ok, next_offset}}
      else
        {:halt, {:error, :snapshot_zip_limit_exceeded}}
      end
    end)
  end

  defp entry_stream(%{kind: :memory, bytes: bytes}, heartbeat, on_progress, progress) do
    Stream.map(binary_chunk_stream(bytes), fn chunk ->
      report_progress!(heartbeat, on_progress, progress, byte_size(chunk))
      chunk
    end)
  end

  defp entry_stream(%{kind: :storage} = entry, heartbeat, on_progress, progress) do
    Stream.flat_map([:read], fn :read ->
      with :ok <- run_stream_callback(heartbeat, []),
           {:ok, stat} <- Storage.stat(entry.key),
           :ok <- verify_stat(entry, stat),
           {:ok, chunks} <- Storage.stream(entry.key, 0, entry.size_bytes, conditional_opts(stat)) do
        verified_chunks(entry, chunks, heartbeat, on_progress, progress)
      else
        {:error, reason} -> stream_failure!(normalize_source_failure(entry, reason))
      end
    end)
  end

  defp verified_chunks(entry, chunks, heartbeat, on_progress, progress) do
    Stream.transform(
      chunks,
      fn -> %{hash: :crypto.hash_init(:sha256), size: 0} end,
      fn
        {:ok, chunk}, state when is_binary(chunk) ->
          run_stream_callback!(heartbeat, [], :snapshot_zip_heartbeat_failed)
          size = state.size + byte_size(chunk)

          if size <= entry.size_bytes do
            report_progress!(heartbeat, on_progress, progress, byte_size(chunk), false)

            {bounded_binary_chunks(chunk), %{hash: :crypto.hash_update(state.hash, chunk), size: size}}
          else
            stream_failure!({:snapshot_object_size_mismatch, entry.path, entry.size_bytes, size})
          end

        {:error, reason}, _state ->
          stream_failure!(normalize_source_failure(entry, reason))

        _unexpected, _state ->
          stream_failure!({:unexpected_snapshot_storage_chunk, entry.path})
      end,
      fn state ->
        case verify_completed_read(entry, state) do
          :ok -> {[], state}
          {:error, reason} -> stream_failure!(reason)
        end
      end,
      fn _state -> :ok end
    )
  end

  defp verify_stat(entry, %{size: size, content_type: content_type}) do
    cond do
      size != entry.size_bytes ->
        {:error, {:snapshot_object_size_mismatch, entry.path, entry.size_bytes, size}}

      not BlobStore.compatible_content_type?(content_type, entry.content_type) ->
        {:error, {:snapshot_object_content_type_mismatch, entry.path, entry.content_type, content_type}}

      true ->
        :ok
    end
  end

  defp verify_stat(entry, stat), do: {:error, {:invalid_snapshot_object_stat, entry.path, stat}}

  defp verify_completed_read(entry, state) do
    checksum = state.hash |> :crypto.hash_final() |> Base.encode16(case: :lower)

    cond do
      state.size != entry.size_bytes ->
        {:error, {:snapshot_object_size_mismatch, entry.path, entry.size_bytes, state.size}}

      not secure_digest_equal?(checksum, entry.sha256) ->
        {:error, {:snapshot_object_checksum_mismatch, entry.path}}

      true ->
        :ok
    end
  end

  defp binary_chunk_stream(bytes) when is_binary(bytes) do
    size = byte_size(bytes)

    Stream.unfold(0, fn
      offset when offset < size ->
        chunk_size = min(@stream_chunk_size, size - offset)
        {binary_part(bytes, offset, chunk_size), offset + chunk_size}

      _offset ->
        nil
    end)
  end

  defp bounded_binary_chunks(bytes), do: binary_chunk_stream(bytes)

  defp report_progress!(heartbeat, on_progress, progress, bytes, heartbeat? \\ true) do
    if heartbeat?, do: run_stream_callback!(heartbeat, [], :snapshot_zip_heartbeat_failed)
    completed = :atomics.add_get(progress, 1, bytes)
    run_stream_callback!(on_progress, [completed], :snapshot_zip_progress_failed)
  end

  defp heartbeat_option(opts) do
    case Keyword.get(opts, :heartbeat, fn -> :ok end) do
      callback when is_function(callback, 0) -> {:ok, callback}
      _invalid -> {:error, :invalid_snapshot_zip_heartbeat}
    end
  end

  defp stream_callback!(opts, key, default, arity) do
    if Keyword.keyword?(opts) do
      case Keyword.get(opts, key, default) do
        callback when is_function(callback, arity) -> callback
        _invalid -> raise ArgumentError, "invalid snapshot ZIP #{key} callback"
      end
    else
      raise ArgumentError, "invalid snapshot ZIP options"
    end
  end

  defp run_stream_callback(callback, args) do
    case apply(callback, args) do
      :ok -> :ok
      {:error, _reason} = error -> error
      _invalid -> {:error, :invalid_callback_response}
    end
  end

  defp run_stream_callback!(callback, args, tag) do
    case run_stream_callback(callback, args) do
      :ok -> :ok
      {:error, reason} -> stream_failure!({tag, reason})
    end
  end

  defp conditional_opts(%{etag: etag}) when is_binary(etag) and etag != "", do: [etag: etag]
  defp conditional_opts(_stat), do: []

  defp normalize_source_failure(entry, reason) do
    if missing_storage_object?(reason),
      do: {:missing_snapshot_blob_source, entry.sha256},
      else: {:snapshot_storage_stream_failed, entry.path, reason}
  end

  defp missing_storage_object?(:enoent), do: true
  defp missing_storage_object?({:http_error, 404, _response}), do: true
  defp missing_storage_object?(_reason), do: false

  defp safe_zip_path?(path) when is_binary(path) do
    byte_size(path) <= @max_zip_path_bytes and String.valid?(path) and
      SnapshotObjectFormat.safe_relative_path?(path) and not String.contains?(path, "\\")
  end

  defp safe_zip_path?(_path), do: false

  defp capture_digest(prepared) do
    source_inventory =
      prepared.source_keys
      |> Enum.sort()
      |> Enum.map(fn {hash, key} -> [digest_part(hash), digest_part(key)] end)

    [
      "storyarn.project_snapshot.capture.v1",
      digest_part(prepared.project_json),
      digest_part(prepared.manifest_json),
      source_inventory
    ]
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp digest_part(value) when is_binary(value), do: [Integer.to_string(byte_size(value)), ":", value]

  defp decode_json(bytes, path) do
    case Jason.decode(bytes) do
      {:ok, value} -> {:ok, value}
      {:error, reason} -> {:error, {:invalid_snapshot_object_json, path, reason}}
    end
  end

  defp sha256(bytes), do: bytes |> then(&:crypto.hash(:sha256, &1)) |> Base.encode16(case: :lower)

  defp valid_sha256?(value), do: is_binary(value) and Regex.match?(@sha256_regex, value)

  defp secure_digest_equal?(left, right)
       when is_binary(left) and is_binary(right) and byte_size(left) == 64 and byte_size(right) == 64 do
    valid_sha256?(right) and Plug.Crypto.secure_compare(left, right)
  end

  defp secure_digest_equal?(_left, _right), do: false

  defp stream_failure!(reason), do: throw({:snapshot_stream_error, reason})
end
