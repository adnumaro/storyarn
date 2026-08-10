defmodule Storyarn.Versioning.ProjectSnapshotZip do
  @moduledoc """
  Builds a bounded, deterministic ZIP stream for a verified full snapshot.

  `prepare/2` performs the complete storage preflight before a caller commits
  response headers. The returned plan contains only object descriptors and
  provider identities, never snapshot payload bytes. `stream/2` reads each
  object again and aborts the archive if its size or SHA-256 digest changed.
  """

  alias Storyarn.Assets.Storage
  alias Storyarn.Versioning.ProjectSnapshot
  alias Storyarn.Versioning.SnapshotObjectFormat
  alias Storyarn.Versioning.SnapshotObjectStorage

  @fixed_mtime ~N[1980-01-01 00:00:00]
  @format_version SnapshotObjectFormat.format_version()
  @max_zip_path_bytes 255
  @sha256_regex ~r/\A[0-9a-f]{64}\z/

  @enforce_keys [:snapshot, :entries, :total_size_bytes, :heartbeat]
  defstruct [:snapshot, :entries, :total_size_bytes, :heartbeat]

  @type entry :: %{
          content_type: String.t(),
          etag: String.t() | nil,
          key: String.t(),
          path: String.t(),
          sha256: String.t(),
          size_bytes: non_neg_integer()
        }

  @opaque t :: %__MODULE__{
            snapshot: ProjectSnapshot.t(),
            entries: [entry()],
            total_size_bytes: non_neg_integer(),
            heartbeat: (-> :ok | {:error, term()})
          }

  @doc """
  Validates a snapshot row against its manifest and preflights every physical
  object before returning a bounded streaming plan.
  """
  @spec prepare(ProjectSnapshot.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def prepare(snapshot, opts \\ [])

  def prepare(%ProjectSnapshot{} = snapshot, opts) when is_list(opts) do
    with {:ok, heartbeat} <- heartbeat_option(opts),
         :ok <- validate_snapshot_eligibility(snapshot),
         :ok <- run_heartbeat(heartbeat),
         {:ok, %{manifest: manifest, ready_prefix: ready_prefix}} <- inspect_manifest(snapshot),
         :ok <- validate_snapshot_manifest_binding(snapshot, manifest, ready_prefix),
         {:ok, entries, total_size_bytes} <- build_entries(snapshot, manifest, ready_prefix),
         {:ok, entries} <- preflight_entries(entries, heartbeat) do
      {:ok,
       %__MODULE__{
         snapshot: snapshot,
         entries: entries,
         total_size_bytes: total_size_bytes,
         heartbeat: heartbeat
       }}
    end
  end

  def prepare(_snapshot, _opts), do: {:error, :snapshot_export_unavailable}

  @doc """
  Returns a lazy stream of deterministic ZIP bytes.

  The archive always uses the STORE method, ZIP64 records, canonical entry
  order, and a fixed timestamp. Any second-read failure raises and leaves the
  response without a valid central directory, so a partial download cannot be
  mistaken for a complete snapshot archive.
  """
  @spec stream(t(), keyword()) :: Enumerable.t()
  def stream(plan, opts \\ [])

  def stream(%__MODULE__{} = plan, opts) when is_list(opts) do
    heartbeat = stream_heartbeat!(plan, opts)

    plan.entries
    |> Stream.map(fn entry ->
      run_stream_heartbeat!(heartbeat)

      Zstream.entry(
        entry.path,
        verified_second_read(entry, heartbeat),
        coder: Zstream.Coder.Stored,
        mtime: @fixed_mtime
      )
    end)
    |> Zstream.zip(zip64: true)
    |> Stream.map(&IO.iodata_to_binary/1)
  end

  def stream(_plan, _opts), do: raise(ArgumentError, "invalid snapshot ZIP plan")

  defp heartbeat_option(opts) do
    if Keyword.keyword?(opts) do
      case Keyword.get(opts, :heartbeat, &default_heartbeat/0) do
        heartbeat when is_function(heartbeat, 0) -> {:ok, heartbeat}
        _invalid -> {:error, :invalid_snapshot_export_heartbeat}
      end
    else
      {:error, :snapshot_export_unavailable}
    end
  end

  defp stream_heartbeat!(plan, opts) do
    if Keyword.keyword?(opts) do
      case Keyword.get(opts, :heartbeat, plan.heartbeat) do
        heartbeat when is_function(heartbeat, 0) -> heartbeat
        _invalid -> raise ArgumentError, "invalid snapshot ZIP heartbeat"
      end
    else
      raise ArgumentError, "invalid snapshot ZIP options"
    end
  end

  defp default_heartbeat, do: :ok

  defp run_heartbeat(heartbeat) do
    case heartbeat.() do
      :ok -> :ok
      {:error, _reason} = error -> error
      _invalid -> {:error, :invalid_snapshot_export_heartbeat_response}
    end
  end

  defp run_stream_heartbeat!(heartbeat) do
    case heartbeat.() do
      :ok -> :ok
      {:error, reason} -> stream_failure!({:heartbeat_failed, reason})
      _invalid -> stream_failure!(:invalid_heartbeat_response)
    end
  end

  defp validate_snapshot_eligibility(%ProjectSnapshot{mode: "linked"}), do: {:error, :snapshot_export_linked}

  defp validate_snapshot_eligibility(%ProjectSnapshot{mode: mode}) when mode != "full",
    do: {:error, {:snapshot_export_corrupt, :invalid_snapshot_mode}}

  defp validate_snapshot_eligibility(%ProjectSnapshot{lifecycle_state: state}) when state != "ready",
    do: {:error, :snapshot_export_not_ready}

  defp validate_snapshot_eligibility(%ProjectSnapshot{integrity_state: state}) when state != "verified",
    do: {:error, :snapshot_export_integrity_unavailable}

  defp validate_snapshot_eligibility(%ProjectSnapshot{format_version: version}) when version != @format_version,
    do: {:error, :snapshot_export_unsupported_format}

  defp validate_snapshot_eligibility(%ProjectSnapshot{accounting_version: 1}), do: :ok

  defp validate_snapshot_eligibility(%ProjectSnapshot{}),
    do: {:error, {:snapshot_export_corrupt, :invalid_snapshot_accounting_version}}

  defp inspect_manifest(snapshot) do
    snapshot.manifest_storage_key
    |> SnapshotObjectStorage.inspect_ready_manifest(
      snapshot.manifest_checksum,
      snapshot.manifest_size_bytes
    )
    |> case do
      {:ok, _inspection} = result -> result
      {:error, reason} -> map_prepare_failure(reason)
    end
  end

  defp validate_snapshot_manifest_binding(snapshot, manifest, ready_prefix) do
    project = manifest["project"]
    counts = manifest["counts"]

    expected = %{
      format_version: manifest["format_version"],
      object_prefix: ready_prefix,
      manifest_storage_key: ready_prefix <> "/" <> SnapshotObjectFormat.manifest_path(),
      project_storage_key: ready_prefix <> "/" <> SnapshotObjectFormat.project_path(),
      project_size_bytes: project["size_bytes"],
      project_checksum: project["sha256"],
      total_size_bytes: manifest["payload_size_bytes"] + snapshot.manifest_size_bytes,
      accounted_size_bytes: manifest["payload_size_bytes"] + snapshot.manifest_size_bytes,
      asset_blob_size_bytes: manifest["payload_size_bytes"] - project["size_bytes"],
      object_count: counts["payload_objects"] + 1,
      asset_count: counts["assets"],
      blob_count: counts["blobs"]
    }

    with true <- SnapshotObjectStorage.ready_prefix_for_project?(snapshot.project_id, ready_prefix),
         :ok <- compare_snapshot_fields(snapshot, expected) do
      :ok
    else
      false -> {:error, {:snapshot_export_corrupt, :snapshot_project_namespace_mismatch}}
      {:error, _reason} = error -> error
    end
  end

  defp compare_snapshot_fields(snapshot, expected) do
    Enum.reduce_while(expected, :ok, fn {field, expected_value}, :ok ->
      actual_value = Map.fetch!(snapshot, field)

      if actual_value == expected_value do
        {:cont, :ok}
      else
        {:halt,
         {:error, {:snapshot_export_corrupt, {:snapshot_manifest_field_mismatch, field, expected_value, actual_value}}}}
      end
    end)
  end

  defp build_entries(snapshot, manifest, ready_prefix) do
    manifest_entry = %{
      path: SnapshotObjectFormat.manifest_path(),
      key: snapshot.manifest_storage_key,
      size_bytes: snapshot.manifest_size_bytes,
      sha256: snapshot.manifest_checksum,
      content_type: "application/json",
      etag: nil
    }

    payload_entries =
      manifest["objects"]
      |> Enum.sort_by(fn descriptor ->
        case descriptor["kind"] do
          "project" -> {0, descriptor["path"]}
          _kind -> {1, descriptor["path"]}
        end
      end)
      |> Enum.map(&descriptor_entry(ready_prefix, &1))

    entries = [manifest_entry | payload_entries]
    total_size_bytes = Enum.reduce(entries, 0, &(&1.size_bytes + &2))

    with :ok <- validate_zip_entries(entries),
         :ok <- validate_export_limits(entries, total_size_bytes) do
      {:ok, entries, total_size_bytes}
    end
  end

  defp descriptor_entry(ready_prefix, descriptor) do
    %{
      path: descriptor["path"],
      key: ready_prefix <> "/" <> descriptor["path"],
      size_bytes: descriptor["size_bytes"],
      sha256: descriptor["sha256"],
      content_type: descriptor["content_type"],
      etag: nil
    }
  end

  defp validate_zip_entries(entries) do
    entries
    |> Enum.reduce_while({:ok, MapSet.new()}, fn entry, {:ok, paths} ->
      cond do
        not safe_zip_path?(entry.path) ->
          {:halt, {:error, {:snapshot_export_corrupt, {:unsafe_zip_entry_path, entry.path}}}}

        MapSet.member?(paths, entry.path) ->
          {:halt, {:error, {:snapshot_export_corrupt, {:duplicate_zip_entry_path, entry.path}}}}

        not Storage.canonical_key?(entry.key) ->
          {:halt, {:error, {:snapshot_export_corrupt, {:invalid_snapshot_object_key, entry.path}}}}

        true ->
          {:cont, {:ok, MapSet.put(paths, entry.path)}}
      end
    end)
    |> case do
      {:ok, _paths} -> :ok
      {:error, _reason} = error -> error
    end
  end

  defp safe_zip_path?(path) when is_binary(path) do
    byte_size(path) <= @max_zip_path_bytes and String.valid?(path) and
      SnapshotObjectFormat.safe_relative_path?(path) and not String.contains?(path, "\\")
  end

  defp safe_zip_path?(_path), do: false

  defp validate_export_limits(entries, total_size_bytes) do
    limits = SnapshotObjectFormat.limits()

    cond do
      length(entries) > limits.max_objects + 1 ->
        {:error, :snapshot_export_limit_exceeded}

      total_size_bytes > limits.max_total_bytes ->
        {:error, :snapshot_export_limit_exceeded}

      true ->
        :ok
    end
  end

  defp preflight_entries(entries, heartbeat) do
    entries
    |> Enum.reduce_while({:ok, []}, fn entry, {:ok, prepared} ->
      with :ok <- run_heartbeat(heartbeat),
           {:ok, prepared_entry} <- preflight_entry(entry, heartbeat) do
        {:cont, {:ok, [prepared_entry | prepared]}}
      else
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, prepared} -> {:ok, Enum.reverse(prepared)}
      {:error, _reason} = error -> error
    end
  end

  defp preflight_entry(entry, heartbeat) do
    with {:ok, stat} <- storage_stat(entry),
         :ok <- verify_stat(entry, stat),
         {:ok, chunks} <- Storage.stream(entry.key, 0, entry.size_bytes, conditional_opts(stat)),
         :ok <- verify_preflight_chunks(entry, chunks, heartbeat) do
      {:ok, %{entry | etag: normalized_etag(stat)}}
    else
      {:error, reason} -> map_prepare_failure(reason)
    end
  end

  defp storage_stat(entry) do
    case Storage.stat(entry.key) do
      {:ok, stat} -> {:ok, stat}
      {:error, reason} -> {:error, {:snapshot_storage_stat_failed, reason}}
    end
  end

  defp verify_stat(entry, %{size: size, content_type: content_type}) do
    cond do
      size != entry.size_bytes ->
        {:error, {:snapshot_object_size_mismatch, entry.path, entry.size_bytes, size}}

      content_type != entry.content_type ->
        {:error, {:snapshot_object_content_type_mismatch, entry.path, entry.content_type, content_type}}

      true ->
        :ok
    end
  end

  defp verify_stat(entry, stat), do: {:error, {:invalid_snapshot_object_stat, entry.path, stat}}

  defp verify_preflight_chunks(entry, chunks, heartbeat) do
    initial = %{hash: :crypto.hash_init(:sha256), size: 0}

    chunks
    |> Enum.reduce_while({:ok, initial}, fn
      {:ok, chunk}, {:ok, state} when is_binary(chunk) ->
        verify_preflight_chunk(entry, chunk, state, heartbeat)

      {:error, reason}, _state ->
        {:halt, {:error, {:snapshot_storage_stream_failed, reason}}}

      _unexpected, _state ->
        {:halt, {:error, :unexpected_snapshot_storage_chunk}}
    end)
    |> case do
      {:ok, state} -> verify_completed_read(entry, state)
      {:error, _reason} = error -> error
    end
  end

  defp verify_preflight_chunk(entry, chunk, state, heartbeat) do
    case run_heartbeat(heartbeat) do
      :ok -> continue_preflight_chunk(entry, chunk, state)
      {:error, _reason} = error -> {:halt, error}
    end
  end

  defp continue_preflight_chunk(entry, chunk, state) do
    size = state.size + byte_size(chunk)

    if size <= entry.size_bytes do
      {:cont, {:ok, %{hash: :crypto.hash_update(state.hash, chunk), size: size}}}
    else
      {:halt, {:error, {:snapshot_object_size_mismatch, entry.path, entry.size_bytes, size}}}
    end
  end

  defp verified_second_read(entry, heartbeat) do
    Stream.flat_map([:read], fn :read ->
      case Storage.stream(entry.key, 0, entry.size_bytes, conditional_opts(entry)) do
        {:ok, chunks} -> verified_stream_chunks(entry, chunks, heartbeat)
        {:error, reason} -> stream_failure!({:storage_stream_failed, reason})
      end
    end)
  end

  defp verified_stream_chunks(entry, chunks, heartbeat) do
    Stream.transform(
      chunks,
      fn -> %{hash: :crypto.hash_init(:sha256), size: 0} end,
      fn
        {:ok, chunk}, state when is_binary(chunk) ->
          run_stream_heartbeat!(heartbeat)
          size = state.size + byte_size(chunk)

          if size <= entry.size_bytes do
            {[chunk], %{hash: :crypto.hash_update(state.hash, chunk), size: size}}
          else
            stream_failure!({:size_mismatch, entry.path})
          end

        {:error, reason}, _state ->
          stream_failure!({:storage_chunk_failed, reason})

        _unexpected, _state ->
          stream_failure!(:unexpected_storage_chunk)
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

  defp verify_completed_read(entry, state) do
    actual_sha256 = state.hash |> :crypto.hash_final() |> Base.encode16(case: :lower)

    cond do
      state.size != entry.size_bytes ->
        {:error, {:snapshot_object_size_mismatch, entry.path, entry.size_bytes, state.size}}

      not secure_digest_equal?(actual_sha256, entry.sha256) ->
        {:error, {:snapshot_object_checksum_mismatch, entry.path}}

      true ->
        :ok
    end
  end

  defp secure_digest_equal?(left, right)
       when is_binary(left) and is_binary(right) and byte_size(left) == byte_size(right) and byte_size(left) == 64 do
    Regex.match?(@sha256_regex, right) and Plug.Crypto.secure_compare(left, right)
  end

  defp secure_digest_equal?(_left, _right), do: false

  defp normalized_etag(%{etag: etag}) when is_binary(etag) and etag != "", do: etag
  defp normalized_etag(_stat), do: nil

  defp conditional_opts(%{etag: etag}) when is_binary(etag) and etag != "", do: [etag: etag]
  defp conditional_opts(_entry_or_stat), do: []

  defp map_prepare_failure(reason) do
    cond do
      limit_failure?(reason) -> {:error, :snapshot_export_limit_exceeded}
      unsupported_format_failure?(reason) -> {:error, :snapshot_export_unsupported_format}
      known_integrity_failure?(reason) -> {:error, {:snapshot_export_corrupt, reason}}
      true -> {:error, :snapshot_export_unavailable}
    end
  end

  defp limit_failure?({tag, _value}) when tag in [:json_object_size_limit_exceeded, :snapshot_size_limit_exceeded],
    do: true

  defp limit_failure?({tag, _label, _limit})
       when tag in [
              :asset_metadata_depth_limit_exceeded,
              :collection_limit_exceeded,
              :size_limit_exceeded,
              :snapshot_object_size_limit_exceeded
            ], do: true

  defp limit_failure?({:snapshot_manifest_validation_failed, reason}), do: limit_failure?(reason)
  defp limit_failure?(_reason), do: false

  defp unsupported_format_failure?({:snapshot_manifest_validation_failed, reason}),
    do: unsupported_format_failure?(reason)

  defp unsupported_format_failure?({:unsupported_snapshot_object_format, _version}), do: true
  defp unsupported_format_failure?({:unsupported_snapshot_object_type, _format}), do: true
  defp unsupported_format_failure?(_reason), do: false

  defp known_integrity_failure?(:enoent), do: true
  defp known_integrity_failure?({:http_error, 404, _response}), do: true

  defp known_integrity_failure?({tag, reason})
       when tag in [:snapshot_storage_stat_failed, :snapshot_storage_stream_failed] do
    known_integrity_failure?(reason)
  end

  defp known_integrity_failure?(reason)
       when reason in [
              :invalid_ready_manifest_key,
              :invalid_snapshot_inspection_request,
              :invalid_snapshot_object_checksum,
              :invalid_snapshot_object_token
            ], do: true

  defp known_integrity_failure?({:invalid_snapshot_object_size, _label}), do: true
  defp known_integrity_failure?({:invalid_snapshot_object_json, _path, _reason}), do: true
  defp known_integrity_failure?({:snapshot_manifest_validation_failed, _reason}), do: true
  defp known_integrity_failure?({:snapshot_object_checksum_mismatch, _path}), do: true
  defp known_integrity_failure?({:snapshot_object_checksum_mismatch, _expected, _actual}), do: true
  defp known_integrity_failure?({:snapshot_object_size_mismatch, _path}), do: true

  defp known_integrity_failure?({:snapshot_object_size_mismatch, _path, _expected, _actual}), do: true

  defp known_integrity_failure?({:snapshot_object_content_type_mismatch, _path, _expected, _actual}), do: true

  defp known_integrity_failure?(_reason), do: false

  defp stream_failure!(reason) do
    raise RuntimeError, "snapshot ZIP stream verification failed: #{inspect(reason)}"
  end
end
