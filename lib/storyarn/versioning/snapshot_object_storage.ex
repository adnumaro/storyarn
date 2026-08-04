defmodule Storyarn.Versioning.SnapshotObjectStorage do
  @moduledoc """
  Persists and verifies canonical snapshot-owned object sets.

  Payload objects are first written beneath an inert staging namespace. Ready
  payload objects are copied and verified before `manifest.json` is published
  last. A missing manifest therefore means "not ready", and retrying the same
  token is idempotent because every existing destination is reverified.

  This module deliberately does not enqueue capture work, retain snapshots, or
  restore a project. Those lifecycle concerns belong to their dedicated flows.
  """

  alias Storyarn.Assets.Storage
  alias Storyarn.Assets.StorageCompensation
  alias Storyarn.Assets.StorageHash
  alias Storyarn.Versioning.SnapshotObjectFormat
  alias Storyarn.Versioning.SnapshotStorage

  @token_regex ~r/\A[A-Za-z0-9_-]{16}\z/
  @sha256_regex ~r/\A[0-9a-f]{64}\z/

  @type stored_object_set :: %{
          format_version: pos_integer(),
          object_prefix: String.t(),
          manifest_storage_key: String.t(),
          manifest_size_bytes: non_neg_integer(),
          manifest_checksum: String.t(),
          project_storage_key: String.t(),
          project_size_bytes: non_neg_integer(),
          project_checksum: String.t(),
          total_size_bytes: non_neg_integer(),
          object_count: pos_integer(),
          asset_count: non_neg_integer(),
          blob_count: non_neg_integer()
        }

  @doc """
  Stages, verifies, and finalizes a complete snapshot object set.

  `:token` may be supplied by an orchestrator to retry the exact same immutable
  namespace. When omitted, a cryptographically random token is generated.
  """
  @spec persist(pos_integer(), map(), [Storyarn.Assets.Asset.t()], keyword()) ::
          {:ok, stored_object_set()} | {:error, term()}
  def persist(project_id, project_snapshot, assets, opts \\ [])

  def persist(project_id, project_snapshot, assets, opts)
      when is_integer(project_id) and project_id > 0 and is_list(assets) do
    token = Keyword.get(opts, :token, SnapshotStorage.unique_key_suffix())

    with :ok <- validate_token(token),
         {:ok, project} <- SnapshotObjectFormat.portable_project(project_snapshot),
         {:ok, catalog} <- SnapshotObjectFormat.build_catalog(assets, Keyword.put(opts, :project_id, project_id)),
         {:ok, project_descriptor, project_json} <- project_descriptor(project, opts),
         {:ok, manifest} <-
           SnapshotObjectFormat.build_manifest(
             project,
             catalog.assets,
             catalog.blobs,
             Keyword.put(opts, :project_descriptor, project_descriptor)
           ),
         {:ok, manifest_json, manifest_descriptor} <- manifest_descriptor(manifest, opts),
         staging_prefix = staging_prefix(project_id, token),
         ready_prefix = ready_prefix(project_id, token),
         :ok <- stage_project(staging_prefix, project_descriptor, project_json),
         :ok <- stage_blobs(staging_prefix, catalog.blobs, catalog.source_keys),
         :ok <- stage_manifest(staging_prefix, manifest_descriptor, manifest_json),
         :ok <- finalize_payload(staging_prefix, ready_prefix, manifest["objects"]),
         :ok <- finalize_manifest(staging_prefix, ready_prefix, manifest_descriptor) do
      stored_object_set(ready_prefix, manifest, manifest_descriptor)
    end
  end

  def persist(_project_id, _project_snapshot, _assets, _opts), do: {:error, :invalid_snapshot_object_source}

  @doc """
  Loads a ready manifest and verifies every declared object before returning the
  project payload. Staging keys are rejected even when they contain a manifest.
  """
  @spec load_verified(String.t(), String.t(), non_neg_integer(), keyword()) ::
          {:ok, %{manifest: map(), project: map()}} | {:error, term()}
  def load_verified(manifest_storage_key, manifest_checksum, manifest_size_bytes, opts \\ []) do
    with {:ok, ready_prefix} <- ready_prefix_from_manifest_key(manifest_storage_key),
         :ok <- validate_sha256(manifest_checksum),
         {:ok, manifest_json} <-
           read_verified_json_bytes(
             manifest_storage_key,
             manifest_size_bytes,
             manifest_checksum,
             SnapshotObjectFormat.limits(opts).max_manifest_bytes
           ),
         {:ok, manifest} <- decode_json(manifest_json, SnapshotObjectFormat.manifest_path()),
         :ok <- SnapshotObjectFormat.validate_manifest(manifest, opts),
         :ok <- verify_blob_inventory(ready_prefix, manifest["objects"]),
         project_descriptor = manifest["project"],
         {:ok, project_json} <- read_descriptor_bytes(ready_prefix, project_descriptor),
         {:ok, project} <- decode_json(project_json, SnapshotObjectFormat.project_path()),
         :ok <- SnapshotObjectFormat.validate_project(project) do
      {:ok, %{manifest: manifest, project: project}}
    end
  end

  @doc false
  def staging_prefix(project_id, token) do
    "projects/#{project_id}/snapshots/object-sets/v#{SnapshotObjectFormat.format_version()}/staging/#{token}"
  end

  @doc false
  def ready_prefix(project_id, token) do
    "projects/#{project_id}/snapshots/object-sets/v#{SnapshotObjectFormat.format_version()}/ready/#{token}"
  end

  @doc false
  def ready_manifest_key?(key) when is_binary(key) do
    match?({:ok, _prefix}, ready_prefix_from_manifest_key(key))
  end

  def ready_manifest_key?(_key), do: false

  defp project_descriptor(project, opts) do
    json = project |> Jason.encode_to_iodata!() |> IO.iodata_to_binary()
    limits = SnapshotObjectFormat.limits(opts)

    with :ok <- validate_size_limit(byte_size(json), limits.max_project_bytes, :project) do
      {:ok,
       %{
         "kind" => "project",
         "path" => SnapshotObjectFormat.project_path(),
         "sha256" => sha256(json),
         "size_bytes" => byte_size(json),
         "content_type" => "application/json"
       }, json}
    end
  end

  defp manifest_descriptor(manifest, opts) do
    json = manifest |> Jason.encode_to_iodata!() |> IO.iodata_to_binary()
    limits = SnapshotObjectFormat.limits(opts)

    with :ok <- validate_size_limit(byte_size(json), limits.max_manifest_bytes, :manifest) do
      {:ok, json,
       %{
         "kind" => "manifest",
         "path" => SnapshotObjectFormat.manifest_path(),
         "sha256" => sha256(json),
         "size_bytes" => byte_size(json),
         "content_type" => "application/json"
       }}
    end
  end

  defp stage_project(prefix, descriptor, json) do
    stage_small_object(prefix, descriptor, json)
  end

  defp stage_manifest(prefix, descriptor, json) do
    stage_small_object(prefix, descriptor, json)
  end

  defp stage_small_object(prefix, descriptor, data) do
    key = object_key(prefix, descriptor["path"])

    with {:ok, _url, _created?} <- put_snapshot_object_if_absent(key, data, descriptor["content_type"]) do
      verify_object(key, descriptor)
    end
  end

  defp stage_blobs(prefix, blobs, source_keys) do
    Enum.reduce_while(blobs, :ok, fn blob, :ok ->
      source_key = source_keys[blob["sha256"]]
      destination_key = object_key(prefix, blob["path"])

      case copy_and_verify(source_key, destination_key, blob) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp copy_and_verify(source_key, destination_key, descriptor) when is_binary(source_key) do
    with :ok <- verify_object(source_key, descriptor),
         {:ok, _created?} <-
           copy_snapshot_object(
             source_key,
             destination_key,
             descriptor["size_bytes"],
             descriptor["content_type"]
           ) do
      verify_object(destination_key, descriptor)
    end
  end

  defp copy_and_verify(_source_key, _destination_key, descriptor),
    do: {:error, {:missing_snapshot_blob_source, descriptor["sha256"]}}

  defp finalize_payload(staging_prefix, ready_prefix, objects) do
    Enum.reduce_while(objects, :ok, fn descriptor, :ok ->
      case finalize_object(staging_prefix, ready_prefix, descriptor) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp finalize_manifest(staging_prefix, ready_prefix, descriptor) do
    finalize_object(staging_prefix, ready_prefix, descriptor)
  end

  defp finalize_object(staging_prefix, ready_prefix, descriptor) do
    source_key = object_key(staging_prefix, descriptor["path"])
    destination_key = object_key(ready_prefix, descriptor["path"])

    with :ok <- verify_object(source_key, descriptor),
         {:ok, _created?} <-
           copy_snapshot_object(
             source_key,
             destination_key,
             descriptor["size_bytes"],
             descriptor["content_type"]
           ) do
      verify_object(destination_key, descriptor)
    end
  end

  defp put_snapshot_object_if_absent(key, data, content_type) do
    case Storage.put_if_absent(key, data, content_type) do
      {:error, {:storage_write_cleanup_required, cleanup_key, _write_reason, _cleanup_reason} = reason} ->
        return_after_compensation(reason, [cleanup_key])

      result ->
        result
    end
  end

  defp copy_snapshot_object(source_key, destination_key, size_bytes, content_type) do
    case Storage.copy_if_absent_or_stream(source_key, destination_key, size_bytes, content_type) do
      {:error, {:conditional_copy_cleanup_required, created?, cleanup_key, _cleanup_reason} = reason}
      when is_boolean(created?) and is_binary(cleanup_key) ->
        cleanup_keys =
          if created?,
            do: [destination_key, cleanup_key],
            else: [cleanup_key]

        return_after_compensation(reason, cleanup_keys)

      {:error, {:storage_write_cleanup_required, cleanup_key, _write_reason, _cleanup_reason} = reason} ->
        return_after_compensation(reason, [cleanup_key])

      result ->
        result
    end
  end

  defp return_after_compensation(original_reason, cleanup_keys) do
    tracker = StorageCompensation.new()
    Enum.each(cleanup_keys, &StorageCompensation.track_force_delete(tracker, &1))

    case StorageCompensation.cleanup_after_rollback(tracker) do
      :ok ->
        {:error, original_reason}

      {:error, cleanup_reason} ->
        {:error, {:snapshot_object_cleanup_not_persisted, original_reason, cleanup_reason}}
    end
  end

  defp verify_blob_inventory(prefix, objects) do
    objects
    |> Enum.reject(&(&1["kind"] == "project"))
    |> Enum.reduce_while(:ok, fn descriptor, :ok ->
      case verify_object(object_key(prefix, descriptor["path"]), descriptor) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp verify_object(key, descriptor) do
    with {:ok, stat} <- Storage.stat(key),
         :ok <- verify_stat(stat, descriptor),
         {:ok, chunks} <- Storage.stream(key, 0, descriptor["size_bytes"], conditional_opts(stat)),
         {:ok, actual_sha256} <- StorageHash.sha256_chunks(chunks) do
      compare_sha256(actual_sha256, descriptor["sha256"])
    end
  end

  defp verify_stat(%{size: size, content_type: content_type}, descriptor) do
    cond do
      size != descriptor["size_bytes"] ->
        {:error, {:snapshot_object_size_mismatch, descriptor["path"], descriptor["size_bytes"], size}}

      not compatible_content_type?(content_type, descriptor["content_type"]) ->
        {:error, {:snapshot_object_content_type_mismatch, descriptor["path"], descriptor["content_type"], content_type}}

      true ->
        :ok
    end
  end

  defp verify_stat(stat, descriptor), do: {:error, {:invalid_snapshot_object_stat, descriptor["path"], stat}}

  defp compatible_content_type?(nil, _expected), do: true
  defp compatible_content_type?("application/octet-stream", _expected), do: true
  defp compatible_content_type?(actual, expected), do: actual == expected

  defp conditional_opts(%{etag: etag}) when is_binary(etag) and etag != "", do: [etag: etag]
  defp conditional_opts(_stat), do: []

  defp compare_sha256(actual, expected) do
    if Plug.Crypto.secure_compare(actual, expected),
      do: :ok,
      else: {:error, {:snapshot_object_checksum_mismatch, expected, actual}}
  end

  defp stored_object_set(ready_prefix, manifest, manifest_descriptor) do
    project = manifest["project"]
    counts = manifest["counts"]

    {:ok,
     %{
       format_version: SnapshotObjectFormat.format_version(),
       object_prefix: ready_prefix,
       manifest_storage_key: object_key(ready_prefix, SnapshotObjectFormat.manifest_path()),
       manifest_size_bytes: manifest_descriptor["size_bytes"],
       manifest_checksum: manifest_descriptor["sha256"],
       project_storage_key: object_key(ready_prefix, SnapshotObjectFormat.project_path()),
       project_size_bytes: project["size_bytes"],
       project_checksum: project["sha256"],
       total_size_bytes: manifest["payload_size_bytes"] + manifest_descriptor["size_bytes"],
       object_count: counts["payload_objects"] + 1,
       asset_count: counts["assets"],
       blob_count: counts["blobs"]
     }}
  end

  defp read_descriptor_bytes(prefix, descriptor) do
    read_verified_json_bytes(
      object_key(prefix, descriptor["path"]),
      descriptor["size_bytes"],
      descriptor["sha256"],
      descriptor["size_bytes"]
    )
  end

  defp read_verified_json_bytes(key, expected_size, expected_sha256, max_size) do
    descriptor = %{
      "path" => Path.basename(key),
      "size_bytes" => expected_size,
      "sha256" => expected_sha256,
      "content_type" => "application/json"
    }

    with :ok <- validate_size_limit(expected_size, max_size, :json_object),
         {:ok, stat} <- Storage.stat(key),
         :ok <- verify_stat(stat, descriptor),
         {:ok, chunks} <- Storage.stream(key, 0, expected_size, conditional_opts(stat)),
         {:ok, bytes} <- consume_binary_chunks(chunks, max_size),
         true <- byte_size(bytes) == expected_size,
         :ok <- compare_sha256(sha256(bytes), expected_sha256) do
      {:ok, bytes}
    else
      false -> {:error, {:snapshot_object_size_mismatch, key}}
      {:error, _reason} = error -> error
    end
  end

  defp consume_binary_chunks(chunks, max_size) do
    chunks
    |> Enum.reduce_while({:ok, [], 0}, fn
      {:ok, chunk}, {:ok, acc, size} when is_binary(chunk) ->
        new_size = size + byte_size(chunk)

        if new_size <= max_size,
          do: {:cont, {:ok, [chunk | acc], new_size}},
          else: {:halt, {:error, {:json_object_size_limit_exceeded, max_size}}}

      {:error, reason}, _acc ->
        {:halt, {:error, reason}}

      _unexpected, _acc ->
        {:halt, {:error, :unexpected_blob_stream_chunk}}
    end)
    |> case do
      {:ok, chunks, _size} -> {:ok, chunks |> Enum.reverse() |> IO.iodata_to_binary()}
      {:error, _reason} = error -> error
    end
  end

  defp decode_json(bytes, path) do
    case Jason.decode(bytes) do
      {:ok, value} -> {:ok, value}
      {:error, reason} -> {:error, {:invalid_snapshot_object_json, path, reason}}
    end
  end

  defp ready_prefix_from_manifest_key(key) do
    parts = String.split(key, "/", trim: false)

    case parts do
      ["projects", project_id, "snapshots", "object-sets", version, "ready", token, "manifest.json"] ->
        with {parsed_project_id, ""} when parsed_project_id > 0 <- Integer.parse(project_id),
             "v1" <- version,
             :ok <- validate_token(token) do
          {:ok, parts |> Enum.drop(-1) |> Enum.join("/")}
        else
          _invalid -> {:error, :invalid_ready_manifest_key}
        end

      _invalid ->
        {:error, :invalid_ready_manifest_key}
    end
  end

  defp object_key(prefix, relative_path), do: prefix <> "/" <> relative_path

  defp validate_token(token) when is_binary(token) do
    if Regex.match?(@token_regex, token), do: :ok, else: {:error, :invalid_snapshot_object_token}
  end

  defp validate_token(_token), do: {:error, :invalid_snapshot_object_token}

  defp validate_sha256(value) when is_binary(value) do
    if Regex.match?(@sha256_regex, value), do: :ok, else: {:error, :invalid_snapshot_object_checksum}
  end

  defp validate_sha256(_value), do: {:error, :invalid_snapshot_object_checksum}

  defp validate_size_limit(size, max_size, label)
       when is_integer(size) and size >= 0 and is_integer(max_size) and max_size > 0 do
    if size <= max_size, do: :ok, else: {:error, {:snapshot_object_size_limit_exceeded, label, max_size}}
  end

  defp validate_size_limit(_size, _max_size, label), do: {:error, {:invalid_snapshot_object_size, label}}

  defp sha256(data) do
    data
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end
end
