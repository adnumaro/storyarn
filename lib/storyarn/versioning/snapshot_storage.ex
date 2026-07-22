defmodule Storyarn.Versioning.SnapshotStorage do
  @moduledoc """
  Handles storing and loading version snapshots as compressed JSON in object storage.

  Snapshots are gzipped JSON stored via the configured storage adapter (R2/Local).
  Key format: `projects/{project_id}/snapshots/{entity_type}/{entity_id}/{version_number}.json.gz`
  or, for uniquely owned write attempts,
  `projects/{project_id}/snapshots/{entity_type}/{entity_id}/{version_number}-{suffix}.json.gz`.
  """

  alias Storyarn.Assets.Storage

  @default_max_compressed_bytes 128 * 1024 * 1024
  @default_max_uncompressed_bytes 128 * 1024 * 1024
  @sha256_regex ~r/\A[0-9a-f]{64}\z/

  @doc """
  Stores a snapshot map as compressed JSON in object storage.

  Returns `{:ok, storage_key, size_bytes}` or `{:error, reason}`.
  """
  @spec store_snapshot(integer(), String.t(), integer(), integer(), map()) ::
          {:ok, String.t(), integer()} | {:error, term()}
  @spec store_snapshot(integer(), String.t(), integer(), integer(), map(), String.t() | nil) ::
          {:ok, String.t(), integer()} | {:error, term()}
  def store_snapshot(project_id, entity_type, entity_id, version_number, snapshot, suffix \\ nil) do
    store_snapshot(project_id, entity_type, entity_id, version_number, snapshot, suffix, [])
  end

  @spec store_snapshot(
          integer(),
          String.t(),
          integer(),
          integer(),
          map(),
          String.t() | nil,
          keyword()
        ) ::
          {:ok, String.t(), integer()} | {:error, term()}
  def store_snapshot(project_id, entity_type, entity_id, version_number, snapshot, suffix, opts) when is_list(opts) do
    key = build_key(project_id, entity_type, entity_id, version_number, suffix)

    with {:ok, compressed, size_bytes, _checksum} <- encode_snapshot(snapshot, opts),
         {:ok, _url} <- Storage.upload(key, compressed, "application/gzip") do
      {:ok, key, size_bytes}
    end
  end

  @doc """
  Loads and decompresses a snapshot from object storage.

  Returns `{:ok, snapshot_map}` or `{:error, reason}`.
  """
  @spec load_snapshot(String.t()) :: {:ok, map()} | {:error, term()}
  def load_snapshot(storage_key) do
    load_snapshot(storage_key, [])
  end

  @spec load_snapshot(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def load_snapshot(storage_key, opts) when is_list(opts) do
    with {:ok, snapshot, _checksum} <- load_snapshot_with_checksum(storage_key, opts) do
      {:ok, snapshot}
    end
  end

  @doc """
  Loads a snapshot and returns the SHA-256 checksum of the exact compressed
  bytes read from object storage.

  Project recovery compares this digest with independently persisted metadata
  before materializing any data.
  """
  @spec load_snapshot_with_checksum(String.t()) ::
          {:ok, map(), String.t()} | {:error, term()}
  def load_snapshot_with_checksum(storage_key) do
    load_snapshot_with_checksum(storage_key, [])
  end

  @spec load_snapshot_with_checksum(String.t(), keyword()) ::
          {:ok, map(), String.t()} | {:error, term()}
  def load_snapshot_with_checksum(storage_key, opts) when is_list(opts) do
    with {:ok, max_compressed_bytes} <- max_compressed_bytes(opts),
         {:ok, max_uncompressed_bytes} <- max_uncompressed_bytes(opts),
         {:ok, object_stat} <- Storage.stat(storage_key),
         {:ok, stat_size_bytes} <-
           validate_storage_stat_compressed_size(object_stat, max_compressed_bytes),
         {:ok, json, actual_checksum} <-
           stream_snapshot(
             storage_key,
             object_stat,
             stat_size_bytes,
             max_compressed_bytes,
             max_uncompressed_bytes
           ),
         {:ok, snapshot} <- Jason.decode(json) do
      {:ok, snapshot, actual_checksum}
    end
  end

  @doc """
  Loads a snapshot only after verifying its compressed size and SHA-256 digest.

  The compressed blob is streamed through object-version conditional reads.
  A first pass verifies its size and digest incrementally; only then may a
  second pass inflate it incrementally. The snapshot is never inflated or
  decoded when either independently persisted value does not match, and
  inflation stops once the configured uncompressed-byte limit is exceeded.

  The default compressed and uncompressed limits are both 128 MiB. Callers may
  override them with `:max_compressed_bytes` and `:max_uncompressed_bytes`, or
  configure them under:

      config :storyarn, Storyarn.Versioning.SnapshotStorage,
        max_compressed_bytes: 134_217_728,
        max_uncompressed_bytes: 134_217_728

  Returns `{:ok, snapshot_map, actual_checksum}` on success.
  """
  @spec load_verified_snapshot(String.t(), non_neg_integer(), String.t(), keyword()) ::
          {:ok, map(), String.t()} | {:error, term()}
  def load_verified_snapshot(storage_key, expected_size_bytes, expected_checksum, opts \\ []) do
    with :ok <- validate_expected_size(expected_size_bytes),
         :ok <- validate_expected_checksum(expected_checksum),
         {:ok, max_compressed_bytes} <- max_compressed_bytes(opts),
         {:ok, max_uncompressed_bytes} <- max_uncompressed_bytes(opts),
         :ok <- validate_compressed_size(expected_size_bytes, max_compressed_bytes),
         {:ok, object_stat} <- Storage.stat(storage_key),
         :ok <-
           verify_storage_stat_size(
             object_stat,
             expected_size_bytes,
             max_compressed_bytes
           ),
         {:ok, actual_checksum} <-
           stream_snapshot_checksum(
             storage_key,
             object_stat,
             expected_size_bytes,
             max_compressed_bytes
           ),
         :ok <- verify_checksum(actual_checksum, expected_checksum),
         {:ok, json, inflated_checksum} <-
           stream_snapshot(
             storage_key,
             object_stat,
             expected_size_bytes,
             max_compressed_bytes,
             max_uncompressed_bytes
           ),
         :ok <- verify_checksum(inflated_checksum, expected_checksum),
         {:ok, snapshot} <- Jason.decode(json) do
      {:ok, snapshot, actual_checksum}
    end
  end

  defp validate_expected_size(size_bytes) when is_integer(size_bytes) and size_bytes >= 0, do: :ok

  defp validate_expected_size(size_bytes), do: {:error, {:invalid_expected_compressed_size, size_bytes}}

  defp validate_expected_checksum(expected_checksum) when is_binary(expected_checksum) do
    if Regex.match?(@sha256_regex, expected_checksum) do
      :ok
    else
      {:error, {:invalid_expected_checksum, expected_checksum}}
    end
  end

  defp validate_expected_checksum(expected_checksum), do: {:error, {:invalid_expected_checksum, expected_checksum}}

  defp max_compressed_bytes(opts) do
    configured_limit =
      :storyarn
      |> Application.get_env(__MODULE__, [])
      |> Keyword.get(:max_compressed_bytes, @default_max_compressed_bytes)

    case Keyword.get(opts, :max_compressed_bytes, configured_limit) do
      limit when is_integer(limit) and limit > 0 -> {:ok, limit}
      limit -> {:error, {:invalid_max_compressed_bytes, limit}}
    end
  end

  defp max_uncompressed_bytes(opts) do
    configured_limit =
      :storyarn
      |> Application.get_env(__MODULE__, [])
      |> Keyword.get(:max_uncompressed_bytes, @default_max_uncompressed_bytes)

    case Keyword.get(opts, :max_uncompressed_bytes, configured_limit) do
      limit when is_integer(limit) and limit > 0 -> {:ok, limit}
      limit -> {:error, {:invalid_max_uncompressed_bytes, limit}}
    end
  end

  defp verify_storage_stat_size(%{size: actual_size_bytes}, expected_size_bytes, max_compressed_bytes)
       when is_integer(actual_size_bytes) and actual_size_bytes >= 0 do
    with :ok <- validate_compressed_size(actual_size_bytes, max_compressed_bytes) do
      compare_compressed_size(expected_size_bytes, actual_size_bytes)
    end
  end

  defp verify_storage_stat_size(object_stat, _expected_size_bytes, _max_compressed_bytes),
    do: {:error, {:invalid_snapshot_storage_stat, object_stat}}

  defp validate_storage_stat_compressed_size(%{size: size_bytes}, max_compressed_bytes)
       when is_integer(size_bytes) and size_bytes >= 0 do
    with :ok <- validate_compressed_size(size_bytes, max_compressed_bytes) do
      {:ok, size_bytes}
    end
  end

  defp validate_storage_stat_compressed_size(object_stat, _max_compressed_bytes),
    do: {:error, {:invalid_snapshot_storage_stat, object_stat}}

  defp validate_compressed_size(size_bytes, max_compressed_bytes) when size_bytes <= max_compressed_bytes, do: :ok

  defp validate_compressed_size(_size_bytes, max_compressed_bytes),
    do: {:error, {:compressed_size_limit_exceeded, max_compressed_bytes}}

  defp validate_uncompressed_size(size_bytes, max_uncompressed_bytes) when size_bytes <= max_uncompressed_bytes, do: :ok

  defp validate_uncompressed_size(_size_bytes, max_uncompressed_bytes),
    do: {:error, {:uncompressed_size_limit_exceeded, max_uncompressed_bytes}}

  defp compare_compressed_size(expected_size_bytes, expected_size_bytes), do: :ok

  defp compare_compressed_size(expected_size_bytes, actual_size_bytes),
    do: {:error, {:compressed_size_mismatch, expected_size_bytes, actual_size_bytes}}

  defp verify_checksum(actual_checksum, expected_checksum) do
    if Plug.Crypto.secure_compare(expected_checksum, actual_checksum) do
      :ok
    else
      {:error, {:checksum_mismatch, expected_checksum, actual_checksum}}
    end
  end

  defp stream_snapshot(storage_key, object_stat, expected_size_bytes, max_compressed_bytes, max_uncompressed_bytes) do
    with {:ok, stream} <-
           Storage.stream(
             storage_key,
             0,
             expected_size_bytes,
             conditional_stream_opts(object_stat)
           ),
         {:ok, json, actual_size_bytes, actual_checksum} <-
           consume_snapshot_stream(
             stream,
             max_compressed_bytes,
             max_uncompressed_bytes
           ),
         :ok <- compare_compressed_size(expected_size_bytes, actual_size_bytes) do
      {:ok, json, actual_checksum}
    end
  end

  defp stream_snapshot_checksum(storage_key, object_stat, expected_size_bytes, max_compressed_bytes) do
    with {:ok, stream} <-
           Storage.stream(
             storage_key,
             0,
             expected_size_bytes,
             conditional_stream_opts(object_stat)
           ),
         {:ok, actual_size_bytes, actual_checksum} <-
           consume_snapshot_checksum_stream(stream, max_compressed_bytes),
         :ok <- compare_compressed_size(expected_size_bytes, actual_size_bytes) do
      {:ok, actual_checksum}
    end
  end

  defp conditional_stream_opts(%{etag: etag}) when is_binary(etag) and etag != "", do: [etag: etag]

  defp conditional_stream_opts(_object_stat), do: []

  defp consume_snapshot_checksum_stream(stream, max_compressed_bytes) do
    stream
    |> Enum.reduce_while({:ok, 0, :crypto.hash_init(:sha256)}, fn
      {:ok, chunk}, {:ok, compressed_size, hash_state} when is_binary(chunk) ->
        new_compressed_size = compressed_size + byte_size(chunk)

        case validate_compressed_size(new_compressed_size, max_compressed_bytes) do
          :ok ->
            {:cont, {:ok, new_compressed_size, :crypto.hash_update(hash_state, chunk)}}

          {:error, _reason} = error ->
            {:halt, error}
        end

      {:error, reason}, _acc ->
        {:halt, {:error, reason}}

      _unexpected, _acc ->
        {:halt, {:error, :unexpected_snapshot_stream_chunk}}
    end)
    |> finalize_snapshot_checksum_stream()
  end

  defp finalize_snapshot_checksum_stream({:ok, compressed_size, hash_state}) do
    actual_checksum =
      hash_state
      |> :crypto.hash_final()
      |> Base.encode16(case: :lower)

    {:ok, compressed_size, actual_checksum}
  end

  defp finalize_snapshot_checksum_stream({:error, _reason} = error), do: error

  defp consume_snapshot_stream(stream, max_compressed_bytes, max_uncompressed_bytes) do
    zstream = :zlib.open()

    try do
      :ok = :zlib.inflateInit(zstream, 31)

      result =
        Enum.reduce_while(
          stream,
          {:ok, [], 0, 0, :crypto.hash_init(:sha256)},
          fn
            {:ok, chunk}, {:ok, output, uncompressed_size, compressed_size, hash_state}
            when is_binary(chunk) ->
              new_compressed_size = compressed_size + byte_size(chunk)

              with :ok <-
                     validate_compressed_size(
                       new_compressed_size,
                       max_compressed_bytes
                     ),
                   {:ok, output, new_uncompressed_size} <-
                     inflate_input(
                       zstream,
                       chunk,
                       output,
                       uncompressed_size,
                       max_uncompressed_bytes
                     ) do
                new_hash_state = :crypto.hash_update(hash_state, chunk)

                {:cont, {:ok, output, new_uncompressed_size, new_compressed_size, new_hash_state}}
              else
                {:error, _reason} = error -> {:halt, error}
              end

            {:error, reason}, _acc ->
              {:halt, {:error, reason}}

            _unexpected, _acc ->
              {:halt, {:error, :unexpected_snapshot_stream_chunk}}
          end
        )

      with {:ok, output, _uncompressed_size, compressed_size, hash_state} <- result,
           :ok <- finish_inflate(zstream) do
        actual_checksum =
          hash_state
          |> :crypto.hash_final()
          |> Base.encode16(case: :lower)

        {:ok, output |> Enum.reverse() |> IO.iodata_to_binary(), compressed_size, actual_checksum}
      end
    rescue
      error in ErlangError -> {:error, {:decompress_failed, error.original}}
    after
      :zlib.close(zstream)
    end
  end

  defp inflate_input(zstream, input, chunks, size_bytes, max_uncompressed_bytes) do
    case :zlib.safeInflate(zstream, input) do
      {:continue, output} ->
        with {:ok, chunks, size_bytes} <-
               append_inflated_output(
                 output,
                 chunks,
                 size_bytes,
                 max_uncompressed_bytes
               ) do
          inflate_input(zstream, [], chunks, size_bytes, max_uncompressed_bytes)
        end

      {:finished, output} ->
        append_inflated_output(output, chunks, size_bytes, max_uncompressed_bytes)

      {:need_dictionary, _adler, _output} ->
        {:error, :snapshot_requires_inflate_dictionary}
    end
  end

  defp append_inflated_output(output, chunks, size_bytes, max_uncompressed_bytes) do
    output_size_bytes = IO.iodata_length(output)
    new_size_bytes = size_bytes + output_size_bytes

    if new_size_bytes > max_uncompressed_bytes do
      {:error, {:uncompressed_size_limit_exceeded, max_uncompressed_bytes}}
    else
      {:ok, [output | chunks], new_size_bytes}
    end
  end

  defp finish_inflate(zstream) do
    :zlib.inflateEnd(zstream)
  rescue
    error in ErlangError -> {:error, {:decompress_failed, error.original}}
  end

  @doc """
  Stores a snapshot map with a pre-built storage key.

  Returns `{:ok, size_bytes}` or `{:error, reason}`.
  """
  @spec store_raw(String.t(), map()) :: {:ok, integer()} | {:error, term()}
  @spec store_raw(String.t(), map(), keyword()) :: {:ok, integer()} | {:error, term()}
  def store_raw(key, snapshot, opts \\ []) when is_list(opts) do
    case store_raw_with_checksum(key, snapshot, opts) do
      {:ok, size_bytes, _checksum} -> {:ok, size_bytes}
      {:error, _reason} = error -> error
    end
  end

  @doc """
  Stores a snapshot map and returns the SHA-256 checksum of the exact compressed
  bytes uploaded to object storage.
  """
  @spec store_raw_with_checksum(String.t(), map()) ::
          {:ok, integer(), String.t()} | {:error, term()}
  @spec store_raw_with_checksum(String.t(), map(), keyword()) ::
          {:ok, integer(), String.t()} | {:error, term()}
  def store_raw_with_checksum(key, snapshot, opts \\ []) when is_list(opts) do
    with {:ok, compressed, size_bytes, checksum} <- encode_snapshot(snapshot, opts),
         {:ok, _url} <- Storage.upload(key, compressed, "application/gzip") do
      {:ok, size_bytes, checksum}
    end
  end

  defp encode_snapshot(snapshot, opts) do
    with {:ok, max_compressed_bytes} <- max_compressed_bytes(opts),
         {:ok, max_uncompressed_bytes} <- max_uncompressed_bytes(opts),
         json = Jason.encode!(snapshot),
         :ok <- validate_uncompressed_size(byte_size(json), max_uncompressed_bytes),
         compressed = :zlib.gzip(json),
         size_bytes = byte_size(compressed),
         :ok <- validate_compressed_size(size_bytes, max_compressed_bytes) do
      {:ok, compressed, size_bytes, checksum(compressed)}
    end
  end

  @doc """
  Deletes a snapshot from object storage.
  """
  @spec delete_snapshot(String.t()) :: :ok | {:error, term()}
  def delete_snapshot(storage_key) do
    Storage.delete(storage_key)
  end

  @doc """
  Returns a random hex suffix suitable for uniquely owned snapshot storage keys.
  """
  @spec unique_key_suffix() :: String.t()
  def unique_key_suffix do
    8
    |> :crypto.strong_rand_bytes()
    |> Base.encode16(case: :lower)
  end

  @doc """
  Builds the storage key for a snapshot.
  """
  @spec build_key(integer(), String.t(), integer(), integer()) :: String.t()
  @spec build_key(integer(), String.t(), integer(), integer(), String.t() | nil) :: String.t()
  def build_key(project_id, entity_type, entity_id, version_number, suffix \\ nil) do
    version_segment = version_segment(version_number, suffix)
    "projects/#{project_id}/snapshots/#{entity_type}/#{entity_id}/#{version_segment}.json.gz"
  end

  @doc """
  Builds the storage key for a project-level snapshot.
  """
  @spec build_project_key(integer(), integer()) :: String.t()
  @spec build_project_key(integer(), integer(), String.t() | nil) :: String.t()
  def build_project_key(project_id, version_number, suffix \\ nil) do
    version_segment = version_segment(version_number, suffix)
    "projects/#{project_id}/snapshots/project/#{version_segment}.json.gz"
  end

  @doc """
  Returns whether a storage key is the canonical key for the given project
  snapshot identity.

  Both the original deterministic key and the current attempt-owned key are
  accepted. This prevents a database row scoped to one project from making a
  recovery path read an object owned by a different project or version.
  """
  @spec project_key?(term(), term(), term()) :: boolean()
  def project_key?(storage_key, project_id, version_number)
      when is_binary(storage_key) and is_integer(project_id) and project_id > 0 and is_integer(version_number) and
             version_number > 0 do
    base = "projects/#{project_id}/snapshots/project/#{version_number}"

    storage_key == "#{base}.json.gz" or
      Regex.match?(~r/\A#{Regex.escape(base)}-[0-9a-f]{16}\.json\.gz\z/, storage_key)
  end

  def project_key?(_storage_key, _project_id, _version_number), do: false

  defp version_segment(version_number, nil), do: to_string(version_number)
  defp version_segment(version_number, ""), do: to_string(version_number)
  defp version_segment(version_number, suffix), do: "#{version_number}-#{suffix}"

  defp checksum(bytes) do
    :sha256
    |> :crypto.hash(bytes)
    |> Base.encode16(case: :lower)
  end
end
