defmodule Storyarn.Scenes.Versioning.Adapters.Storage.SnapshotStorage do
  @moduledoc """
  Scene-owned storage codec for compressed entity-version snapshots.

  It uses the Platform object-storage contract, but owns the Scene snapshot key
  contract, size limits, checksum verification, and decoding policy.
  """

  alias Storyarn.Scenes.Versioning.Adapters.Storage.Objects, as: Storage

  @default_max_compressed_bytes 128 * 1024 * 1024
  @default_max_uncompressed_bytes 128 * 1024 * 1024
  @sha256_regex ~r/\A[0-9a-f]{64}\z/

  defguardp valid_identity(project_id, scene_id, version_number)
            when is_integer(project_id) and project_id > 0 and is_integer(scene_id) and scene_id > 0 and
                   is_integer(version_number) and version_number > 0

  @spec store_snapshot(integer(), integer(), integer(), map(), keyword()) ::
          {:ok, String.t(), non_neg_integer(), String.t()} | {:error, term()}
  def store_snapshot(project_id, scene_id, version_number, snapshot, opts \\ []) when is_list(opts) do
    key = build_key(project_id, scene_id, version_number, unique_key_suffix())

    with {:ok, compressed, size_bytes, checksum} <- encode(snapshot, opts),
         {:ok, _url} <- Storage.upload(key, compressed, "application/gzip") do
      {:ok, key, size_bytes, checksum}
    end
  end

  @spec load_verified(String.t(), non_neg_integer(), String.t(), keyword()) ::
          {:ok, map(), String.t()} | {:error, term()}
  def load_verified(storage_key, expected_size, expected_checksum, opts \\ []) when is_list(opts) do
    with :ok <- validate_expected_size(expected_size),
         :ok <- validate_checksum_shape(expected_checksum),
         {:ok, max_compressed} <- limit(opts, :max_compressed_bytes, @default_max_compressed_bytes),
         {:ok, max_uncompressed} <- limit(opts, :max_uncompressed_bytes, @default_max_uncompressed_bytes),
         :ok <- within_limit(expected_size, max_compressed, :compressed),
         {:ok, object_stat} <- Storage.stat(storage_key),
         :ok <- verify_stat(object_stat, expected_size, max_compressed),
         {:ok, actual_checksum} <-
           stream_checksum(storage_key, object_stat, expected_size, max_compressed),
         :ok <- verify_checksum(actual_checksum, expected_checksum),
         {:ok, json, inflated_checksum} <-
           stream_and_inflate(
             storage_key,
             object_stat,
             expected_size,
             max_compressed,
             max_uncompressed
           ),
         :ok <- verify_checksum(inflated_checksum, expected_checksum),
         {:ok, snapshot} <- Jason.decode(json) do
      {:ok, snapshot, actual_checksum}
    end
  end

  @spec delete(String.t()) :: :ok | {:error, term()}
  def delete(storage_key), do: Storage.delete(storage_key)

  @spec build_key(integer(), integer(), integer(), String.t()) :: String.t()
  def build_key(project_id, scene_id, version_number, suffix)
      when is_integer(project_id) and project_id > 0 and is_integer(scene_id) and scene_id > 0 and
             is_integer(version_number) and version_number > 0 do
    if Regex.match?(~r/\A[0-9a-f]{16}\z/, suffix) do
      "projects/#{project_id}/snapshots/scene/#{scene_id}/#{version_number}-#{suffix}.json.gz"
    else
      raise ArgumentError, "invalid snapshot attempt suffix"
    end
  end

  @spec entity_key?(term(), term(), term(), term()) :: boolean()
  def entity_key?(storage_key, project_id, scene_id, version_number)
      when is_binary(storage_key) and valid_identity(project_id, scene_id, version_number) do
    base = "projects/#{project_id}/snapshots/scene/#{scene_id}/#{version_number}"
    Regex.match?(~r/\A#{Regex.escape(base)}-[0-9a-f]{16}\.json\.gz\z/, storage_key)
  end

  def entity_key?(_storage_key, _project_id, _scene_id, _version_number), do: false

  @spec unique_key_suffix() :: String.t()
  def unique_key_suffix do
    8
    |> :crypto.strong_rand_bytes()
    |> Base.encode16(case: :lower)
  end

  defp encode(snapshot, opts) do
    with {:ok, max_compressed} <- limit(opts, :max_compressed_bytes, @default_max_compressed_bytes),
         {:ok, max_uncompressed} <- limit(opts, :max_uncompressed_bytes, @default_max_uncompressed_bytes),
         {:ok, json} <- Jason.encode(snapshot),
         :ok <- within_limit(byte_size(json), max_uncompressed, :uncompressed),
         compressed = :zlib.gzip(json),
         :ok <- within_limit(byte_size(compressed), max_compressed, :compressed) do
      {:ok, compressed, byte_size(compressed), sha256(compressed)}
    end
  end

  defp limit(opts, key, default) do
    configured =
      :storyarn
      |> Application.get_env(__MODULE__, [])
      |> Keyword.get(key, default)

    case Keyword.get(opts, key, configured) do
      value when is_integer(value) and value > 0 -> {:ok, value}
      value -> {:error, {invalid_limit_reason(key), value}}
    end
  end

  defp invalid_limit_reason(:max_compressed_bytes), do: :invalid_max_compressed_bytes
  defp invalid_limit_reason(:max_uncompressed_bytes), do: :invalid_max_uncompressed_bytes

  defp validate_expected_size(size) when is_integer(size) and size >= 0, do: :ok
  defp validate_expected_size(size), do: {:error, {:invalid_expected_compressed_size, size}}

  defp validate_checksum_shape(checksum) when is_binary(checksum) do
    if Regex.match?(@sha256_regex, checksum),
      do: :ok,
      else: {:error, {:invalid_expected_checksum, checksum}}
  end

  defp validate_checksum_shape(checksum), do: {:error, {:invalid_expected_checksum, checksum}}

  defp verify_stat(%{size: size}, expected_size, max_compressed) when is_integer(size) and size >= 0 do
    with :ok <- within_limit(size, max_compressed, :compressed) do
      compare_size(expected_size, size)
    end
  end

  defp verify_stat(stat, _expected_size, _max_compressed), do: {:error, {:invalid_snapshot_storage_stat, stat}}

  defp compare_size(expected, expected), do: :ok
  defp compare_size(expected, actual), do: {:error, {:compressed_size_mismatch, expected, actual}}

  defp within_limit(size, limit, _kind) when size <= limit, do: :ok

  defp within_limit(_size, limit, :compressed), do: {:error, {:compressed_size_limit_exceeded, limit}}

  defp within_limit(_size, limit, :uncompressed), do: {:error, {:uncompressed_size_limit_exceeded, limit}}

  defp verify_checksum(actual, expected) do
    if Plug.Crypto.secure_compare(expected, actual),
      do: :ok,
      else: {:error, {:checksum_mismatch, expected, actual}}
  end

  defp stream_checksum(storage_key, object_stat, expected_size, max_compressed) do
    with {:ok, stream} <-
           Storage.stream(
             storage_key,
             0,
             expected_size,
             conditional_stream_opts(object_stat)
           ),
         {:ok, actual_size, actual_checksum} <-
           consume_checksum_stream(stream, max_compressed),
         :ok <- compare_size(expected_size, actual_size) do
      {:ok, actual_checksum}
    end
  end

  defp stream_and_inflate(storage_key, object_stat, expected_size, max_compressed, max_uncompressed) do
    with {:ok, stream} <-
           Storage.stream(
             storage_key,
             0,
             expected_size,
             conditional_stream_opts(object_stat)
           ),
         {:ok, json, actual_size, actual_checksum} <-
           consume_snapshot_stream(stream, max_compressed, max_uncompressed),
         :ok <- compare_size(expected_size, actual_size) do
      {:ok, json, actual_checksum}
    end
  end

  defp conditional_stream_opts(%{etag: etag}) when is_binary(etag) and etag != "", do: [etag: etag]
  defp conditional_stream_opts(_object_stat), do: []

  defp consume_checksum_stream(stream, max_compressed) do
    stream
    |> Enum.reduce_while({:ok, 0, :crypto.hash_init(:sha256)}, fn
      {:ok, chunk}, {:ok, compressed_size, hash_state} when is_binary(chunk) ->
        new_compressed_size = compressed_size + byte_size(chunk)

        case within_limit(new_compressed_size, max_compressed, :compressed) do
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
    |> finalize_checksum_stream()
  end

  defp finalize_checksum_stream({:ok, compressed_size, hash_state}) do
    actual_checksum =
      hash_state
      |> :crypto.hash_final()
      |> Base.encode16(case: :lower)

    {:ok, compressed_size, actual_checksum}
  end

  defp finalize_checksum_stream({:error, _reason} = error), do: error

  defp consume_snapshot_stream(stream, max_compressed, max_uncompressed) do
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

              with :ok <- within_limit(new_compressed_size, max_compressed, :compressed),
                   {:ok, output, new_uncompressed_size} <-
                     inflate_input(
                       zstream,
                       chunk,
                       output,
                       uncompressed_size,
                       max_uncompressed
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

  defp inflate_input(zstream, input, chunks, size, max_uncompressed) do
    case :zlib.safeInflate(zstream, input) do
      {:continue, output} ->
        with {:ok, chunks, size} <-
               append_inflated_output(output, chunks, size, max_uncompressed) do
          inflate_input(zstream, [], chunks, size, max_uncompressed)
        end

      {:finished, output} ->
        append_inflated_output(output, chunks, size, max_uncompressed)

      {:need_dictionary, _adler, _output} ->
        {:error, :snapshot_requires_inflate_dictionary}
    end
  end

  defp append_inflated_output(output, chunks, size, max_uncompressed) do
    new_size = size + IO.iodata_length(output)

    with :ok <- within_limit(new_size, max_uncompressed, :uncompressed) do
      {:ok, [output | chunks], new_size}
    end
  end

  defp finish_inflate(zstream) do
    :zlib.inflateEnd(zstream)
  rescue
    error in ErlangError -> {:error, {:decompress_failed, error.original}}
  end

  defp sha256(bytes) do
    :sha256
    |> :crypto.hash(bytes)
    |> Base.encode16(case: :lower)
  end
end
