defmodule Storyarn.Versioning.SnapshotArchiveStorage do
  @moduledoc """
  Publishes canonical full-snapshot ZIP archives to private object storage.

  Every build owns exactly four possible keys: `snapshot.zip` and
  `manifest.json` beneath paired staging and ready prefixes. A durable database
  claim and storage reservation fence all writes. The ZIP is uploaded and
  verified in the worker, the ready archive is copied first, and the byte-exact
  manifest sidecar is published last as the readiness marker.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Assets.BlobStore
  alias Storyarn.Assets.Storage
  alias Storyarn.Assets.StorageCompensation
  alias Storyarn.Billing.StorageCleanupInventory
  alias Storyarn.Billing.StorageReservation
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Repo
  alias Storyarn.Versioning.ProjectSnapshotLeasePolicy
  alias Storyarn.Versioning.ProjectSnapshotZip
  alias Storyarn.Versioning.SnapshotObjectFormat
  alias Storyarn.Versioning.SnapshotObjectPublicationClaim
  alias Storyarn.Versioning.SnapshotStorage

  @format_version 2
  @accounting_version 1
  @archive_filename "snapshot.zip"
  @manifest_filename "manifest.json"
  @archive_content_type "application/zip"
  @manifest_content_type "application/json"
  @upload_chunk_size 1_048_576
  @token_regex ~r/\A[A-Za-z0-9_-]{16}\z/

  @type prepared_capture :: map()
  @type cleanup_scope :: %{
          project_id: pos_integer(),
          token: String.t(),
          staging_prefix: String.t(),
          ready_prefix: String.t(),
          storage_keys: [Storage.key()],
          inventory_digest: String.t()
        }
  @type staged_archive :: map()
  @type stored_archive :: map()

  @doc """
  Materializes the immutable logical capture and calculates its exact archive
  accounting without reading or writing object storage.
  """
  @spec prepare(pos_integer(), map(), list(), keyword()) ::
          {:ok, prepared_capture()} | {:error, term()}
  def prepare(project_id, project_snapshot, assets, opts \\ [])

  def prepare(project_id, project_snapshot, assets, opts)
      when is_integer(project_id) and project_id > 0 and is_list(assets) and is_list(opts) do
    with true <- Keyword.keyword?(opts),
         opts = Keyword.put_new(opts, :source_key_mode, :protected_blob),
         {:ok, prepared} <- prepare_capture(project_id, project_snapshot, assets, opts),
         {:ok, plan} <- ProjectSnapshotZip.prepare_capture(project_id, prepared, opts) do
      {:ok, with_archive_accounting(prepared, plan)}
    else
      false -> {:error, :invalid_snapshot_archive_options}
      {:error, _reason} = error -> error
    end
  end

  def prepare(_project_id, _project_snapshot, _assets, _opts), do: {:error, :invalid_snapshot_archive_source}

  @doc false
  @spec canonical_project_checksum(map(), [Storyarn.Assets.Asset.t()], keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def canonical_project_checksum(project_snapshot, assets, opts \\ [])

  def canonical_project_checksum(project_snapshot, assets, opts)
      when is_map(project_snapshot) and is_list(assets) and is_list(opts) do
    limits = SnapshotObjectFormat.limits(opts)

    with {:ok, normalized_project} <- normalize_project_snapshot(project_snapshot, limits),
         {:ok, project} <- SnapshotObjectFormat.portable_project(normalized_project),
         {:ok, source_refs} <- SnapshotObjectFormat.source_refs_for_assets(assets),
         project = Map.put(project, "asset_catalog_refs", source_refs),
         :ok <- SnapshotObjectFormat.validate_project(project),
         {:ok, descriptor, _json} <- project_descriptor(project, opts) do
      {:ok, descriptor["sha256"]}
    end
  end

  def canonical_project_checksum(_project_snapshot, _assets, _opts), do: {:error, :invalid_snapshot_archive_source}

  @doc """
  Claims, uploads and verifies one archive beneath its inert staging prefix.

  `:storage_reservation` and `:before_stage` are mandatory. The callback must
  durably mark the reservation with the complete four-key cleanup inventory
  before the first provider write. Failures after that point poison the claim
  and return a durable cleanup owner for all four keys.
  """
  @spec stage_prepared(pos_integer(), prepared_capture(), keyword()) ::
          {:ok, staged_archive()} | {:error, term()}
  def stage_prepared(project_id, prepared, opts \\ [])

  def stage_prepared(project_id, prepared, opts)
      when is_integer(project_id) and project_id > 0 and is_map(prepared) and is_list(opts) do
    with true <- Keyword.keyword?(opts),
         token = Keyword.get(opts, :token, SnapshotStorage.unique_key_suffix()),
         {:ok, before_stage} <- required_callback(opts, :before_stage, 1),
         {:ok, on_progress} <- optional_callback(opts, :on_progress, 1, fn _bytes -> :ok end),
         {:ok, reservation} <- stage_reservation(opts),
         :ok <- validate_token(token),
         {:ok, plan} <- ProjectSnapshotZip.prepare_capture(project_id, prepared),
         staged = staged_archive(project_id, token, prepared, plan),
         :ok <- validate_initial_reservation(reservation, staged),
         {:ok, claimed, action} <- acquire_stage_claim(staged, reservation) do
      stage_claimed(claimed, action, before_stage, on_progress)
    else
      false -> {:error, :invalid_snapshot_archive_options}
      {:error, _reason} = error -> error
      _invalid -> {:error, :invalid_prepared_snapshot_capture}
    end
  end

  def stage_prepared(_project_id, _prepared, _opts), do: {:error, :invalid_prepared_snapshot_capture}

  @doc """
  Publishes a staged archive and its sidecar to the ready namespace.

  The archive is copied and fully verified before `manifest.json` is copied.
  Therefore the sidecar is the last provider mutation that can make a v2
  snapshot publishable.
  """
  @spec publish(staged_archive(), (staged_archive() -> {:ok, StorageReservation.t()} | {:error, term()}), keyword()) ::
          {:ok, stored_archive()} | {:error, term()}
  def publish(staged, before_publish, opts \\ [])

  def publish(staged, before_publish, opts) when is_map(staged) and is_function(before_publish, 1) and is_list(opts) do
    with true <- Keyword.keyword?(opts),
         {:ok, on_progress} <- optional_callback(opts, :on_progress, 1, fn _bytes -> :ok end),
         :ok <- validate_staged_archive(staged),
         {:ok, action} <- acquire_publication_claim(staged, on_progress) do
      publish_claimed(staged, before_publish, action, on_progress)
    else
      false -> {:error, :invalid_snapshot_archive_options}
      {:error, _reason} = error -> error
      _invalid -> {:error, :invalid_snapshot_archive_publish_request}
    end
  end

  def publish(_staged, _before_publish, _opts), do: {:error, :invalid_snapshot_archive_publish_request}

  @doc false
  @spec staging_prefix(pos_integer(), String.t()) :: String.t()
  def staging_prefix(project_id, token),
    do: "projects/#{project_id}/snapshots/archives/v#{@format_version}/staging/#{token}"

  @doc false
  @spec ready_prefix(pos_integer(), String.t()) :: String.t()
  def ready_prefix(project_id, token), do: "projects/#{project_id}/snapshots/archives/v#{@format_version}/ready/#{token}"

  @doc false
  @spec archive_key(String.t()) :: String.t()
  def archive_key(prefix) when is_binary(prefix), do: prefix <> "/" <> @archive_filename

  @doc false
  @spec manifest_key(String.t()) :: String.t()
  def manifest_key(prefix) when is_binary(prefix), do: prefix <> "/" <> @manifest_filename

  @doc false
  @spec upload_chunk_size() :: pos_integer()
  def upload_chunk_size, do: @upload_chunk_size

  @doc false
  @spec ready_prefix_for_project?(pos_integer(), term()) :: boolean()
  def ready_prefix_for_project?(project_id, prefix)
      when is_integer(project_id) and project_id > 0 and is_binary(prefix) do
    match?({:ok, _token}, token_from_ready_prefix(project_id, prefix))
  end

  def ready_prefix_for_project?(_project_id, _prefix), do: false

  @doc false
  @spec ready_archive_key?(pos_integer(), term(), term()) :: boolean()
  def ready_archive_key?(project_id, object_prefix, storage_key)
      when is_integer(project_id) and project_id > 0 and is_binary(object_prefix) and is_binary(storage_key) do
    ready_prefix_for_project?(project_id, object_prefix) and
      storage_key == archive_key(object_prefix) and Storage.canonical_key?(storage_key)
  end

  def ready_archive_key?(_project_id, _object_prefix, _storage_key), do: false

  @doc false
  @spec cleanup_scope(pos_integer(), String.t()) :: {:ok, cleanup_scope()} | {:error, term()}
  def cleanup_scope(project_id, object_prefix)
      when is_integer(project_id) and project_id > 0 and is_binary(object_prefix) do
    with {:ok, token} <- token_from_ready_prefix(project_id, object_prefix) do
      staging = staging_prefix(project_id, token)
      keys = cleanup_keys(staging, object_prefix)

      {:ok,
       %{
         project_id: project_id,
         token: token,
         staging_prefix: staging,
         ready_prefix: object_prefix,
         storage_keys: keys,
         inventory_digest: StorageCleanupInventory.digest(keys)
       }}
    end
  end

  def cleanup_scope(_project_id, _object_prefix), do: {:error, :invalid_snapshot_archive_cleanup_scope}

  @doc false
  @spec cleanup_scope_from_snapshot(map()) :: {:ok, map()} | {:error, term()}
  def cleanup_scope_from_snapshot(%{
        format_version: 2,
        capture_digest: nil,
        project_id: project_id,
        object_prefix: object_prefix,
        archive_size_bytes: nil,
        manifest_size_bytes: nil
      }) do
    with {:ok, scope} <- cleanup_scope(project_id, object_prefix) do
      {:ok, Map.put(scope, :estimated_cleanup_bytes, 0)}
    end
  end

  def cleanup_scope_from_snapshot(%{
        project_id: project_id,
        object_prefix: object_prefix,
        archive_size_bytes: archive_size_bytes,
        manifest_size_bytes: manifest_size_bytes
      })
      when is_integer(archive_size_bytes) and archive_size_bytes > 0 and is_integer(manifest_size_bytes) and
             manifest_size_bytes > 0 do
    with {:ok, scope} <- cleanup_scope(project_id, object_prefix) do
      {:ok,
       Map.put(
         scope,
         :estimated_cleanup_bytes,
         2 * (archive_size_bytes + manifest_size_bytes)
       )}
    end
  end

  def cleanup_scope_from_snapshot(_snapshot), do: {:error, :invalid_snapshot_archive_cleanup_scope}

  @doc false
  @spec inspect_ready_archive(map()) ::
          {:ok, %{manifest: map(), verified_objects: 2, verified_bytes: pos_integer()}}
          | {:error, term()}
  def inspect_ready_archive(%{
        project_id: project_id,
        object_prefix: object_prefix,
        archive_storage_key: archive_storage_key,
        archive_size_bytes: archive_size_bytes,
        archive_checksum: archive_checksum,
        manifest_storage_key: manifest_storage_key,
        manifest_size_bytes: manifest_size_bytes,
        manifest_checksum: manifest_checksum
      })
      when is_integer(archive_size_bytes) and archive_size_bytes > 0 and is_binary(archive_checksum) and
             is_integer(manifest_size_bytes) and manifest_size_bytes > 0 and is_binary(manifest_checksum) do
    with true <- ready_archive_key?(project_id, object_prefix, archive_storage_key),
         true <- manifest_storage_key == manifest_key(object_prefix),
         {:ok, _archive_checksum} <-
           inspect_indexed_object(
             0,
             @archive_filename,
             archive_storage_key,
             archive_size_bytes,
             archive_checksum,
             @archive_content_type
           ),
         {:ok, manifest_json} <-
           inspect_indexed_json_object(
             1,
             @manifest_filename,
             archive_size_bytes,
             manifest_storage_key,
             manifest_size_bytes,
             manifest_checksum
           ),
         {:ok, manifest} <- decode_json(manifest_json, @manifest_filename),
         :ok <- validate_inspected_manifest(manifest) do
      {:ok,
       %{
         manifest: manifest,
         verified_objects: 2,
         verified_bytes: archive_size_bytes + manifest_size_bytes
       }}
    else
      false -> {:error, :invalid_snapshot_archive_metadata}
      {:error, _reason} = error -> error
    end
  end

  def inspect_ready_archive(_snapshot), do: {:error, :invalid_snapshot_archive_metadata}

  @doc false
  @spec inspect_ready_manifest(map()) :: {:ok, map()} | {:error, term()}
  def inspect_ready_manifest(%{
        project_id: project_id,
        object_prefix: object_prefix,
        manifest_storage_key: manifest_storage_key,
        manifest_size_bytes: manifest_size_bytes,
        manifest_checksum: manifest_checksum
      })
      when is_integer(manifest_size_bytes) and manifest_size_bytes > 0 and is_binary(manifest_checksum) do
    with true <- ready_prefix_for_project?(project_id, object_prefix),
         true <- manifest_storage_key == manifest_key(object_prefix),
         true <- Storage.canonical_key?(manifest_storage_key),
         {:ok, manifest_json} <- inspect_json_object(manifest_storage_key, manifest_size_bytes, manifest_checksum),
         {:ok, manifest} <- decode_json(manifest_json, @manifest_filename),
         :ok <- validate_inspected_manifest(manifest) do
      {:ok, manifest}
    else
      false ->
        {:error, :invalid_snapshot_archive_metadata}

      {:error, reason} ->
        {:error,
         {:snapshot_inspection_object_failed,
          %{
            failed_index: 1,
            object_count: 2,
            path: @manifest_filename,
            reason: reason,
            verified_objects: 0,
            verified_bytes: 0
          }}}
    end
  end

  def inspect_ready_manifest(_snapshot), do: {:error, :invalid_snapshot_archive_metadata}

  defp validate_inspected_manifest(manifest) do
    case SnapshotObjectFormat.validate_manifest(manifest) do
      :ok -> :ok
      {:error, reason} -> {:error, {:snapshot_manifest_validation_failed, reason}}
    end
  end

  defp prepare_capture(project_id, project_snapshot, assets, opts) do
    limits = SnapshotObjectFormat.limits(opts)

    with {:ok, normalized_project} <- normalize_project_snapshot(project_snapshot, limits),
         {:ok, project} <- SnapshotObjectFormat.portable_project(normalized_project),
         asset_content_mode = Keyword.get(opts, :asset_content_mode, :strict),
         catalog_opts = Keyword.put(opts, :asset_content_mode, asset_content_mode),
         {:ok, catalog} <-
           SnapshotObjectFormat.build_catalog(
             assets,
             Keyword.put(catalog_opts, :project_id, project_id)
           ),
         project = Map.put(project, "asset_catalog_refs", catalog.source_refs),
         :ok <- SnapshotObjectFormat.validate_project(project),
         {:ok, project_descriptor, project_json} <- project_descriptor(project, opts),
         {:ok, manifest} <-
           SnapshotObjectFormat.build_manifest(
             project,
             catalog.assets,
             catalog.blobs,
             Keyword.put(opts, :project_descriptor, project_descriptor)
           ),
         {:ok, manifest_json, manifest_descriptor} <- manifest_descriptor(manifest, opts) do
      {:ok,
       prepared_capture(
         project_json,
         manifest_json,
         manifest,
         manifest_descriptor,
         catalog.source_keys
       )}
    end
  end

  defp normalize_project_snapshot(project_snapshot, limits) when is_map(project_snapshot) do
    with {:ok, json} <- Jason.encode_to_iodata(project_snapshot),
         :ok <- validate_encoded_project_size(json, limits),
         {:ok, normalized} <- Jason.decode(json) do
      {:ok, normalized}
    else
      {:error, {:snapshot_object_size_limit_exceeded, :project, _max_size}} = error -> error
      {:error, _reason} -> {:error, :invalid_project_object}
    end
  end

  defp normalize_project_snapshot(_project_snapshot, _limits), do: {:error, :invalid_project_object}

  defp validate_encoded_project_size(json, limits) do
    case SnapshotObjectFormat.validate_limits(limits) do
      :ok -> validate_capture_size(IO.iodata_length(json), limits.max_project_bytes, :project)
      {:error, _reason} -> :ok
    end
  end

  defp project_descriptor(project, opts) do
    json = project |> Jason.encode_to_iodata!() |> IO.iodata_to_binary()
    limits = SnapshotObjectFormat.limits(opts)

    with :ok <- validate_capture_size(byte_size(json), limits.max_project_bytes, :project) do
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

    with :ok <- validate_capture_size(byte_size(json), limits.max_manifest_bytes, :manifest) do
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

  defp prepared_capture(project_json, manifest_json, manifest, manifest_descriptor, source_keys) do
    project_descriptor = manifest["project"]
    counts = manifest["counts"]
    manifest_size = manifest_descriptor["size_bytes"]
    total_size = manifest["payload_size_bytes"] + manifest_size
    asset_blob_size = total_size - project_descriptor["size_bytes"] - manifest_size

    prepared = %{
      project_json: project_json,
      manifest_json: manifest_json,
      source_keys: source_keys,
      project_size_bytes: project_descriptor["size_bytes"],
      project_checksum: project_descriptor["sha256"],
      manifest_size_bytes: manifest_size,
      manifest_checksum: manifest_descriptor["sha256"],
      total_size_bytes: total_size,
      asset_blob_size_bytes: asset_blob_size,
      object_count: counts["payload_objects"] + 1,
      asset_count: counts["assets"],
      blob_count: counts["blobs"]
    }

    Map.put(prepared, :capture_digest, capture_digest(prepared))
  end

  defp capture_digest(prepared) do
    source_inventory =
      prepared.source_keys
      |> Enum.sort()
      |> Enum.map(fn {hash, key} -> [encode_digest_part(hash), encode_digest_part(key)] end)

    [
      "storyarn.project_snapshot.capture.v1",
      encode_digest_part(prepared.project_json),
      encode_digest_part(prepared.manifest_json),
      source_inventory
    ]
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp encode_digest_part(value) when is_binary(value), do: [Integer.to_string(byte_size(value)), ":", value]

  defp validate_capture_size(size, max_size, label)
       when is_integer(size) and size >= 0 and is_integer(max_size) and max_size > 0 do
    if size <= max_size,
      do: :ok,
      else: {:error, {:snapshot_object_size_limit_exceeded, label, max_size}}
  end

  defp validate_capture_size(_size, _max_size, label), do: {:error, {:invalid_snapshot_object_size, label}}

  defp sha256(data), do: :sha256 |> :crypto.hash(data) |> Base.encode16(case: :lower)

  defp with_archive_accounting(prepared, plan) do
    archive_size = ProjectSnapshotZip.archive_size(plan)
    accounted_size = archive_size + prepared.manifest_size_bytes

    Map.merge(prepared, %{
      archive_size_bytes: archive_size,
      accounted_size_bytes: accounted_size,
      snapshot_total_size_bytes: accounted_size,
      snapshot_object_count: 2
    })
  end

  defp staged_archive(project_id, token, prepared, plan) do
    staging = staging_prefix(project_id, token)
    ready = ready_prefix(project_id, token)
    archive_size = ProjectSnapshotZip.archive_size(plan)
    total_size = archive_size + prepared.manifest_size_bytes
    cleanup = cleanup_scope!(project_id, ready)

    %{
      project_id: project_id,
      token: token,
      zip_plan: plan,
      capture_digest: prepared.capture_digest,
      format_version: @format_version,
      mode: "full",
      lifecycle_state: "ready",
      integrity_state: "verified",
      staging_prefix: staging,
      object_prefix: ready,
      archive_staging_key: archive_key(staging),
      archive_storage_key: archive_key(ready),
      archive_size_bytes: archive_size,
      archive_checksum: nil,
      manifest_staging_key: manifest_key(staging),
      manifest_storage_key: manifest_key(ready),
      manifest_size_bytes: prepared.manifest_size_bytes,
      manifest_checksum: prepared.manifest_checksum,
      manifest_json: prepared.manifest_json,
      project_size_bytes: prepared.project_size_bytes,
      project_checksum: prepared.project_checksum,
      total_size_bytes: total_size,
      accounted_size_bytes: total_size,
      asset_blob_size_bytes: prepared.asset_blob_size_bytes,
      accounting_version: @accounting_version,
      object_count: 2,
      asset_count: prepared.asset_count,
      blob_count: prepared.blob_count,
      publication_claim_token: nil,
      storage_reservation_id: nil,
      storage_reservation_lease_token: nil,
      staging_cleanup_request_id: nil,
      cleanup: cleanup
    }
  end

  defp stage_claimed(staged, :write, before_stage, on_progress) do
    case authorize_stage(staged, before_stage) do
      :ok ->
        case write_staging_pair(staged, on_progress) do
          {:ok, staged} -> finish_staging_claim(staged)
          {:error, reason} -> poison_and_handoff(staged, :stage, reason)
        end

      {:error, reason} ->
        handle_stage_authorization_failure(staged, reason)
    end
  end

  defp stage_claimed(staged, :staged, _before_stage, on_progress) do
    with :ok <- validate_started_reservation(staged, ["staged"]),
         {:ok, checksum} <- verify_exact_staging_pair(staged, on_progress) do
      {:ok, %{staged | archive_checksum: checksum}}
    else
      {:error, reason} -> poison_and_handoff(staged, :stage_reuse, reason)
    end
  end

  defp stage_claimed(staged, :recover_staging, before_stage, on_progress) do
    case reservation_storage_started?(staged.storage_reservation_id) do
      true ->
        recover_started_staging_claim(staged, on_progress)

      false ->
        recover_unstarted_staging_claim(staged, before_stage, on_progress)

      :unknown ->
        poison_expired_and_handoff(
          staged,
          "staging",
          :stage_recovery,
          :snapshot_object_stage_reservation_missing
        )
    end
  end

  defp stage_claimed(staged, :published, _before_stage, on_progress) do
    with :ok <- validate_started_reservation(staged, ["published"]),
         {:ok, checksum} <- verify_exact_ready_pair(staged, on_progress) do
      {:ok, %{staged | archive_checksum: checksum}}
    else
      {:error, reason} -> {:error, {:published_snapshot_archive_invalid, reason}}
    end
  end

  defp stage_claimed(staged, :publishing, _before_stage, on_progress) do
    with :ok <- validate_started_reservation(staged, ["publishing"]) do
      recover_publishing_stage(staged, on_progress)
    end
  end

  defp recover_started_staging_claim(staged, on_progress) do
    with :ok <- validate_started_reservation(staged, ["staging", "staged"]),
         {:ok, checksum} <- verify_exact_staging_pair(staged, on_progress),
         :ok <- recover_expired_staging_claim(staged) do
      {:ok, %{staged | archive_checksum: checksum}}
    else
      {:error, reason} ->
        poison_expired_and_handoff(staged, "staging", :stage_recovery, reason)
    end
  end

  defp recover_unstarted_staging_claim(staged, before_stage, on_progress) do
    with :ok <- verify_archive_namespace_empty(staged),
         :ok <- takeover_expired_unstarted_staging_claim(staged) do
      stage_claimed(staged, :write, before_stage, on_progress)
    else
      {:error, reason} ->
        poison_expired_and_handoff(staged, "staging", :stage_recovery, reason)
    end
  end

  defp recover_publishing_stage(staged, on_progress) do
    if claim_lease_active?(staged, TimeHelpers.now()) do
      {:error, :snapshot_object_publication_in_progress}
    else
      case verify_exact_ready_pair(staged, on_progress) do
        {:ok, checksum} -> {:ok, %{staged | archive_checksum: checksum}}
        {:error, ready_reason} -> recover_publishing_staging_pair(staged, on_progress, ready_reason)
      end
    end
  end

  defp recover_publishing_staging_pair(staged, on_progress, ready_reason) do
    case verify_exact_staging_pair(staged, on_progress) do
      {:ok, checksum} ->
        {:ok, %{staged | archive_checksum: checksum}}

      {:error, staging_reason} ->
        reason = %{ready_reason: ready_reason, staging_reason: staging_reason}

        if claim_lease_active?(staged, TimeHelpers.now()) do
          {:error, :snapshot_object_publication_in_progress}
        else
          poison_expired_and_handoff(staged, "publishing", :publish_recovery, reason)
        end
    end
  end

  defp finish_staging_claim(staged) do
    case transition_claim(staged, "staging", "staged") do
      :ok -> {:ok, staged}
      {:error, reason} -> poison_and_handoff(staged, :stage_finalize, reason)
    end
  end

  defp write_staging_pair(staged, on_progress) do
    with {:ok, outgoing_checksum} <- upload_archive(staged, on_progress),
         {:ok, stored_checksum} <-
           verify_archive(staged.archive_staging_key, staged.archive_size_bytes, on_progress),
         true <- secure_digest_equal?(outgoing_checksum, stored_checksum),
         :ok <- put_manifest(staged.manifest_staging_key, staged.manifest_json),
         :ok <- verify_manifest(staged.manifest_staging_key, staged, on_progress),
         :ok <- invoke_callback(on_progress, [staged.total_size_bytes]) do
      {:ok, %{staged | archive_checksum: stored_checksum}}
    else
      false -> {:error, :snapshot_archive_upload_checksum_mismatch}
      {:error, _reason} = error -> error
    end
  end

  defp upload_archive(staged, on_progress) do
    caller = self()
    digest_ref = make_ref()

    chunks =
      staged.zip_plan
      |> ProjectSnapshotZip.stream(on_progress: on_progress)
      |> bounded_upload_chunks()
      |> digest_upload_stream(caller, digest_ref)

    case safe_upload_stream(staged.archive_staging_key, chunks, @archive_content_type) do
      {:ok, _url} -> receive_upload_digest(digest_ref, staged.archive_size_bytes)
      {:error, _reason} = error -> error
    end
  end

  defp digest_upload_stream(chunks, caller, digest_ref) do
    Stream.transform(
      chunks,
      fn -> %{hash: :crypto.hash_init(:sha256), size: 0} end,
      fn chunk, state when is_binary(chunk) ->
        next = %{
          hash: :crypto.hash_update(state.hash, chunk),
          size: state.size + byte_size(chunk)
        }

        {[{:ok, chunk}], next}
      end,
      fn state ->
        checksum = state.hash |> :crypto.hash_final() |> Base.encode16(case: :lower)
        send(caller, {digest_ref, state.size, checksum})
        {[], state}
      end,
      fn _state -> :ok end
    )
  end

  defp bounded_upload_chunks(chunks) do
    Stream.flat_map(chunks, fn chunk when is_binary(chunk) ->
      binary_chunk_stream(chunk, @upload_chunk_size)
    end)
  end

  defp receive_upload_digest(digest_ref, expected_size) do
    receive do
      {^digest_ref, ^expected_size, checksum} -> {:ok, checksum}
      {^digest_ref, actual_size, _checksum} -> {:error, {:snapshot_archive_size_mismatch, expected_size, actual_size}}
    after
      0 -> {:error, :snapshot_archive_upload_not_fully_consumed}
    end
  end

  defp safe_upload_stream(key, chunks, content_type) do
    Storage.upload_stream(key, chunks, content_type)
  rescue
    exception -> {:error, {:snapshot_archive_upload_raised, exception.__struct__, Exception.message(exception)}}
  catch
    {:snapshot_stream_error, reason} -> {:error, reason}
    kind, reason -> {:error, {:snapshot_archive_upload_caught, kind, reason}}
  end

  defp publish_claimed(staged, before_publish, :claimed, on_progress) do
    case publish_pair(staged, before_publish, on_progress) do
      {:ok, stored} ->
        case transition_claim(staged, "publishing", "published") do
          :ok -> cleanup_published_staging(staged, stored)
          {:error, reason} -> poison_and_handoff(staged, :publish_finalize, reason)
        end

      {:error, reason} ->
        poison_and_handoff(staged, :publish, reason)
    end
  end

  defp publish_claimed(staged, before_publish, :published, on_progress) do
    with {:ok, checksum} <- verify_ready_pair_against_checksum(staged, on_progress),
         :ok <- authorize_publication(staged, before_publish) do
      staged
      |> stored_archive(checksum)
      |> then(&cleanup_published_staging(staged, &1))
    else
      {:error, reason} -> {:error, {:published_snapshot_archive_invalid, reason}}
    end
  end

  defp publish_pair(staged, before_publish, on_progress) do
    with {:ok, staging_checksum} <- verify_staging_pair(staged, on_progress),
         true <- secure_digest_equal?(staged.archive_checksum, staging_checksum),
         staged = %{staged | archive_checksum: staging_checksum},
         :ok <- authorize_publication(staged, before_publish),
         :ok <- copy_archive(staged.archive_staging_key, staged.archive_storage_key, staged.archive_size_bytes),
         {:ok, ready_checksum} <-
           verify_archive(staged.archive_storage_key, staged.archive_size_bytes, on_progress),
         true <- secure_digest_equal?(staging_checksum, ready_checksum),
         :ok <- invoke_callback(on_progress, [staged.archive_size_bytes]),
         :ok <- copy_manifest(staged),
         :ok <- verify_manifest(staged.manifest_storage_key, staged, on_progress),
         :ok <- invoke_callback(on_progress, [staged.total_size_bytes]) do
      {:ok, stored_archive(staged, ready_checksum)}
    else
      false -> {:error, :snapshot_archive_publication_checksum_mismatch}
      {:error, _reason} = error -> error
    end
  end

  defp copy_archive(source, destination, size_bytes) do
    case Storage.copy_if_absent_or_stream(source, destination, size_bytes, @archive_content_type) do
      {:ok, _created?} ->
        :ok

      {:error, {:conditional_copy_cleanup_required, created?, cleanup_key, _cleanup_reason} = reason}
      when is_boolean(created?) and is_binary(cleanup_key) ->
        cleanup_keys = if created?, do: [destination, cleanup_key], else: [cleanup_key]
        return_after_compensation(reason, cleanup_keys)

      {:error, {:storage_write_cleanup_required, cleanup_key, _write_reason, _cleanup_reason} = reason} ->
        return_after_compensation(reason, [cleanup_key])

      {:error, _reason} = error ->
        error
    end
  end

  defp copy_manifest(staged) do
    case Storage.copy_if_absent_or_stream(
           staged.manifest_staging_key,
           staged.manifest_storage_key,
           staged.manifest_size_bytes,
           @manifest_content_type
         ) do
      {:ok, _created?} ->
        :ok

      {:error, {:conditional_copy_cleanup_required, created?, cleanup_key, _cleanup_reason} = reason}
      when is_boolean(created?) and is_binary(cleanup_key) ->
        cleanup_keys = if created?, do: [staged.manifest_storage_key, cleanup_key], else: [cleanup_key]
        return_after_compensation(reason, cleanup_keys)

      {:error, {:storage_write_cleanup_required, cleanup_key, _write_reason, _cleanup_reason} = reason} ->
        return_after_compensation(reason, [cleanup_key])

      {:error, _reason} = error ->
        error
    end
  end

  defp stored_archive(staged, archive_checksum) do
    %{
      format_version: @format_version,
      mode: "full",
      lifecycle_state: "ready",
      integrity_state: "verified",
      object_prefix: staged.object_prefix,
      archive_storage_key: staged.archive_storage_key,
      archive_size_bytes: staged.archive_size_bytes,
      archive_checksum: archive_checksum,
      manifest_storage_key: staged.manifest_storage_key,
      manifest_size_bytes: staged.manifest_size_bytes,
      manifest_checksum: staged.manifest_checksum,
      project_size_bytes: staged.project_size_bytes,
      project_checksum: staged.project_checksum,
      total_size_bytes: staged.total_size_bytes,
      accounted_size_bytes: staged.accounted_size_bytes,
      asset_blob_size_bytes: staged.asset_blob_size_bytes,
      accounting_version: @accounting_version,
      object_count: 2,
      asset_count: staged.asset_count,
      blob_count: staged.blob_count,
      staging_cleanup_request_id: nil
    }
  end

  defp verify_staging_pair(staged, observer) do
    with {:ok, checksum} <- verify_archive(staged.archive_staging_key, staged.archive_size_bytes, observer),
         :ok <- verify_manifest(staged.manifest_staging_key, staged, observer) do
      {:ok, checksum}
    end
  end

  defp verify_ready_pair(staged, observer) do
    with {:ok, checksum} <- verify_archive(staged.archive_storage_key, staged.archive_size_bytes, observer),
         :ok <- verify_manifest(staged.manifest_storage_key, staged, observer) do
      {:ok, checksum}
    end
  end

  defp verify_exact_staging_pair(staged, observer) do
    verify_exact_pair(staged, :staging, observer)
  end

  defp verify_exact_ready_pair(staged, observer) do
    verify_exact_pair(staged, :ready, observer)
  end

  defp verify_exact_pair(staged, namespace, observer) do
    with {:ok, stored_checksum} <- verify_archive_pair(staged, namespace, observer),
         {:ok, expected_checksum} <- planned_archive_checksum(staged, observer),
         true <- secure_digest_equal?(stored_checksum, expected_checksum) do
      {:ok, stored_checksum}
    else
      false -> {:error, {:snapshot_archive_recovery_checksum_mismatch, namespace}}
      {:error, _reason} = error -> error
    end
  end

  defp verify_archive_pair(staged, :staging, observer), do: verify_staging_pair(staged, observer)
  defp verify_archive_pair(staged, :ready, observer), do: verify_ready_pair(staged, observer)

  defp verify_ready_pair_against_checksum(staged, observer) do
    with true <- valid_archive_checksum?(staged.archive_checksum),
         {:ok, stored_checksum} <- verify_ready_pair(staged, observer),
         true <- secure_digest_equal?(stored_checksum, staged.archive_checksum) do
      {:ok, stored_checksum}
    else
      false -> {:error, :snapshot_archive_recovery_checksum_mismatch}
      {:error, _reason} = error -> error
    end
  end

  defp planned_archive_checksum(staged, observer) do
    chunks = ProjectSnapshotZip.stream(staged.zip_plan, on_progress: observer)

    {hash, size} =
      Enum.reduce(chunks, {:crypto.hash_init(:sha256), 0}, fn chunk, {hash, size} ->
        {:crypto.hash_update(hash, chunk), size + byte_size(chunk)}
      end)

    if size == staged.archive_size_bytes do
      checksum = hash |> :crypto.hash_final() |> Base.encode16(case: :lower)
      {:ok, checksum}
    else
      {:error, {:snapshot_archive_size_mismatch, staged.archive_size_bytes, size}}
    end
  rescue
    exception -> {:error, {:snapshot_archive_recovery_hash_raised, exception.__struct__, Exception.message(exception)}}
  catch
    {:snapshot_stream_error, reason} -> {:error, reason}
    kind, reason -> {:error, {:snapshot_archive_recovery_hash_caught, kind, reason}}
  end

  defp verify_archive_namespace_empty(staged) do
    Enum.reduce_while(staged.cleanup.storage_keys, :ok, &verify_archive_namespace_key_empty/2)
  end

  defp verify_archive_namespace_key_empty(key, :ok) do
    case Storage.stat(key) do
      {:ok, _stat} ->
        {:halt, {:error, {:snapshot_object_namespace_not_empty, key}}}

      {:error, reason} ->
        if missing_storage_object?(reason),
          do: {:cont, :ok},
          else: {:halt, {:error, {:snapshot_object_namespace_inspection_failed, key, reason}}}
    end
  end

  defp verify_archive(key, size_bytes, observer), do: verify_object(key, size_bytes, nil, @archive_content_type, observer)

  defp verify_manifest(key, staged, observer) do
    case verify_object(
           key,
           staged.manifest_size_bytes,
           staged.manifest_checksum,
           @manifest_content_type,
           observer
         ) do
      {:ok, _checksum} -> :ok
      {:error, _reason} = error -> error
    end
  end

  defp verify_object(key, expected_size, expected_checksum, expected_content_type, observer) do
    with {:ok, stat} <- Storage.stat(key),
         :ok <- verify_object_stat(key, stat, expected_size, expected_content_type),
         {:ok, chunks} <- Storage.stream(key, 0, expected_size, conditional_opts(stat)),
         {:ok, checksum} <- hash_verified_chunks(chunks, key, expected_size, observer),
         true <- is_nil(expected_checksum) or secure_digest_equal?(checksum, expected_checksum) do
      {:ok, checksum}
    else
      false -> {:error, {:snapshot_object_checksum_mismatch, key}}
      {:error, reason} -> {:error, normalize_storage_failure(key, reason)}
    end
  end

  defp inspect_object(key, expected_size, expected_checksum, expected_content_type) do
    with {:ok, stat} <- Storage.stat(key),
         :ok <- verify_object_stat(key, stat, expected_size, expected_content_type),
         {:ok, chunks} <- Storage.stream(key, 0, expected_size, conditional_opts(stat)),
         {:ok, checksum} <- hash_verified_chunks(chunks, key, expected_size, fn _bytes -> :ok end),
         true <- secure_digest_equal?(checksum, expected_checksum) do
      {:ok, checksum}
    else
      false -> {:error, {:snapshot_object_checksum_mismatch, key}}
      {:error, _reason} = error -> error
    end
  end

  defp hash_verified_chunks(chunks, key, expected_size, observer) do
    chunks
    |> Enum.reduce_while(
      {:ok, :crypto.hash_init(:sha256), 0},
      &hash_verified_chunk(&1, &2, key, expected_size, observer)
    )
    |> case do
      {:ok, hash, ^expected_size} ->
        checksum = hash |> :crypto.hash_final() |> Base.encode16(case: :lower)
        {:ok, checksum}

      {:ok, _hash, actual_size} ->
        {:error, {:snapshot_object_size_mismatch, key, expected_size, actual_size}}

      {:error, _reason} = error ->
        error
    end
  end

  defp hash_verified_chunk({:ok, chunk}, {:ok, hash, size}, key, expected_size, observer) when is_binary(chunk) do
    next_size = size + byte_size(chunk)

    if next_size > expected_size,
      do: {:halt, {:error, {:snapshot_object_size_mismatch, key, expected_size, next_size}}},
      else: advance_verified_hash(observer, hash, chunk, next_size)
  end

  defp hash_verified_chunk({:error, reason}, _state, _key, _expected_size, _observer), do: {:halt, {:error, reason}}

  defp hash_verified_chunk(_unexpected, _state, _key, _expected_size, _observer),
    do: {:halt, {:error, :unexpected_snapshot_storage_chunk}}

  defp advance_verified_hash(observer, hash, chunk, next_size) do
    case invoke_callback(observer, [next_size]) do
      :ok -> {:cont, {:ok, :crypto.hash_update(hash, chunk), next_size}}
      {:error, reason} -> {:halt, {:error, reason}}
      invalid -> {:halt, {:error, {:invalid_snapshot_progress_result, invalid}}}
    end
  end

  defp inspect_indexed_object(index, path, key, expected_size, expected_checksum, expected_content_type) do
    case inspect_object(key, expected_size, expected_checksum, expected_content_type) do
      {:ok, _checksum} = success -> success
      {:error, reason} -> {:error, inspection_failure(index, path, 0, reason)}
    end
  end

  defp inspect_json_object(key, expected_size, expected_checksum) do
    with {:ok, stat} <- Storage.stat(key),
         :ok <- verify_object_stat(key, stat, expected_size, @manifest_content_type),
         {:ok, chunks} <- Storage.stream(key, 0, expected_size, conditional_opts(stat)),
         {:ok, bytes, checksum} <- consume_verified_bytes(chunks, expected_size),
         true <- secure_digest_equal?(checksum, expected_checksum) do
      {:ok, bytes}
    else
      false -> {:error, {:snapshot_object_checksum_mismatch, key}}
      {:error, _reason} = error -> error
    end
  end

  defp inspect_indexed_json_object(index, path, verified_bytes, key, expected_size, expected_checksum) do
    case inspect_json_object(key, expected_size, expected_checksum) do
      {:ok, _bytes} = success -> success
      {:error, reason} -> {:error, inspection_failure(index, path, verified_bytes, reason)}
    end
  end

  defp inspection_failure(index, path, verified_bytes, reason) do
    {:snapshot_inspection_object_failed,
     %{
       failed_index: index,
       object_count: 2,
       path: path,
       reason: reason,
       verified_objects: index,
       verified_bytes: verified_bytes
     }}
  end

  defp consume_verified_bytes(chunks, expected_size) do
    chunks
    |> Enum.reduce_while({:ok, [], 0, :crypto.hash_init(:sha256)}, fn
      {:ok, chunk}, {:ok, acc, size, hash} when is_binary(chunk) ->
        next_size = size + byte_size(chunk)

        if next_size <= expected_size,
          do: {:cont, {:ok, [chunk | acc], next_size, :crypto.hash_update(hash, chunk)}},
          else: {:halt, {:error, {:snapshot_object_size_mismatch, expected_size, next_size}}}

      {:error, reason}, _state ->
        {:halt, {:error, reason}}

      _unexpected, _state ->
        {:halt, {:error, :unexpected_snapshot_storage_chunk}}
    end)
    |> case do
      {:ok, chunks, ^expected_size, hash} ->
        checksum = hash |> :crypto.hash_final() |> Base.encode16(case: :lower)
        {:ok, chunks |> Enum.reverse() |> IO.iodata_to_binary(), checksum}

      {:ok, _chunks, actual_size, _hash} ->
        {:error, {:snapshot_object_size_mismatch, expected_size, actual_size}}

      {:error, _reason} = error ->
        error
    end
  end

  defp verify_object_stat(key, %{size: size, content_type: content_type}, expected_size, expected_content_type) do
    cond do
      size != expected_size ->
        {:error, {:snapshot_object_size_mismatch, key, expected_size, size}}

      not BlobStore.compatible_content_type?(content_type, expected_content_type) ->
        {:error, {:snapshot_object_content_type_mismatch, key, expected_content_type, content_type}}

      true ->
        :ok
    end
  end

  defp verify_object_stat(key, stat, _expected_size, _expected_content_type),
    do: {:error, {:invalid_snapshot_object_stat, key, stat}}

  defp put_manifest(key, bytes) do
    case Storage.put_if_absent(key, bytes, @manifest_content_type) do
      {:ok, _url, _created?} ->
        :ok

      {:error, {:storage_write_cleanup_required, cleanup_key, _write_reason, _cleanup_reason} = reason} ->
        return_after_compensation(reason, [cleanup_key])

      {:error, _reason} = error ->
        error
    end
  end

  defp return_after_compensation(original_reason, cleanup_keys) do
    tracker = StorageCompensation.new()
    Enum.each(cleanup_keys, &StorageCompensation.track_force_delete(tracker, &1))

    case StorageCompensation.cleanup_after_rollback(tracker, compensation_options()) do
      :ok -> {:error, original_reason}
      {:error, cleanup_reason} -> {:error, {:snapshot_object_cleanup_not_persisted, original_reason, cleanup_reason}}
    end
  end

  defp compensation_options do
    configured = Application.get_env(:storyarn, __MODULE__, [])

    if is_list(configured) do
      configured
      |> Keyword.take([:compensation_delete_fun, :compensation_enqueue_fun, :compensation_persist_fun])
      |> Enum.map(fn
        {:compensation_delete_fun, callback} -> {:delete_fun, callback}
        {:compensation_enqueue_fun, callback} -> {:enqueue_fun, callback}
        {:compensation_persist_fun, callback} -> {:persist_fun, callback}
      end)
      |> Enum.filter(fn {_key, callback} -> is_function(callback, 1) end)
    else
      []
    end
  end

  defp authorize_stage(staged, before_stage) do
    case invoke_callback(before_stage, [staged]) do
      {:ok, %StorageReservation{} = reservation} -> validate_authorized_reservation(staged, reservation, ["staging"])
      {:ok, _invalid} -> {:error, :invalid_snapshot_stage_authorization_result}
      {:error, _reason} = error -> error
      _invalid -> {:error, :invalid_snapshot_stage_authorization_result}
    end
  end

  defp authorize_publication(staged, before_publish) do
    case invoke_callback(before_publish, [staged]) do
      {:ok, %StorageReservation{} = reservation} ->
        validate_authorized_reservation(staged, reservation, ["publishing", "published"])

      {:ok, _invalid} ->
        {:error, :invalid_snapshot_publish_authorization_result}

      {:error, _reason} = error ->
        error

      _invalid ->
        {:error, :invalid_snapshot_publish_authorization_result}
    end
  end

  defp invoke_callback(callback, args) do
    apply(callback, args)
  rescue
    exception -> {:error, {:snapshot_archive_callback_raised, exception.__struct__, Exception.message(exception)}}
  catch
    kind, reason -> {:error, {:snapshot_archive_callback_caught, kind, reason}}
  end

  defp handle_stage_authorization_failure(staged, reason) do
    case reservation_storage_started?(staged.storage_reservation_id) do
      false ->
        case delete_unstarted_claim(staged) do
          :ok -> {:error, reason}
          {:error, claim_reason} -> {:error, {:snapshot_stage_claim_release_failed, reason, claim_reason}}
        end

      true ->
        poison_and_handoff(staged, :stage_authorization, reason)

      :unknown ->
        {:error, {:snapshot_stage_authorization_state_unknown, reason}}
    end
  end

  defp validate_initial_reservation(
         %StorageReservation{
           id: id,
           status: "active",
           kind: "snapshot_build",
           project_id_snapshot: project_id,
           cleanup_object_prefix: object_prefix,
           lease_token: lease_token,
           reserved_bytes: reserved_bytes,
           expires_at: expires_at,
           storage_started_at: started_at
         },
         %{project_id: project_id, object_prefix: object_prefix, total_size_bytes: total_size_bytes}
       )
       when is_integer(id) and id > 0 and is_binary(lease_token) and is_integer(reserved_bytes) and
              reserved_bytes >= total_size_bytes do
    cond do
      not lease_active?(expires_at, TimeHelpers.now()) -> {:error, :snapshot_object_stage_reservation_expired}
      is_nil(started_at) -> :ok
      match?(%DateTime{}, started_at) -> :ok
      true -> {:error, :snapshot_object_stage_reservation_binding_invalid}
    end
  end

  defp validate_initial_reservation(_reservation, _staged),
    do: {:error, :snapshot_object_stage_reservation_binding_invalid}

  defp validate_started_reservation(staged, allowed_claim_statuses) do
    transact(fn ->
      with %StorageReservation{} = reservation <- lock_reservation(staged.storage_reservation_id),
           :ok <- validate_persisted_reservation(reservation, staged),
           {:ok, claim} <- matching_claim(staged),
           true <- claim.status in allowed_claim_statuses do
        :ok
      else
        nil -> {:error, :snapshot_object_stage_reservation_missing}
        false -> {:error, :snapshot_object_stage_claim_state_conflict}
        {:error, _reason} = error -> error
      end
    end)
  end

  defp validate_authorized_reservation(staged, reported, allowed_claim_statuses) do
    transact(fn ->
      with %StorageReservation{} = reservation <- lock_reservation(staged.storage_reservation_id),
           true <- reported.id == reservation.id and reported.lease_token == reservation.lease_token,
           :ok <- validate_persisted_reservation(reservation, staged),
           {:ok, claim} <- matching_claim(staged),
           true <- claim.status in allowed_claim_statuses do
        :ok
      else
        nil -> {:error, :snapshot_object_stage_reservation_missing}
        false -> {:error, :snapshot_object_stage_reservation_binding_conflict}
        {:error, _reason} = error -> error
      end
    end)
  end

  defp validate_persisted_reservation(
         %StorageReservation{
           status: status,
           kind: "snapshot_build",
           project_id_snapshot: project_id,
           cleanup_object_prefix: object_prefix,
           lease_token: lease_token,
           reserved_bytes: reserved_bytes,
           storage_started_at: %DateTime{},
           cleanup_inventory_digest: inventory_digest,
           cleanup_inventory_count: inventory_count
         },
         %{
           project_id: project_id,
           object_prefix: object_prefix,
           storage_reservation_lease_token: lease_token,
           total_size_bytes: total_size_bytes,
           cleanup: %{storage_keys: storage_keys}
         }
       )
       when status in ["active", "committed"] and is_integer(reserved_bytes) and reserved_bytes >= total_size_bytes do
    if inventory_count == length(storage_keys) and
         inventory_digest == StorageCleanupInventory.digest(storage_keys),
       do: :ok,
       else: {:error, :snapshot_object_stage_cleanup_commitment_mismatch}
  end

  defp validate_persisted_reservation(_reservation, _staged),
    do: {:error, :snapshot_object_stage_reservation_binding_invalid}

  defp acquire_stage_claim(staged, reservation) do
    now = TimeHelpers.now()
    digest = SnapshotObjectPublicationClaim.inventory_digest(staged)
    claim_token = Ecto.UUID.generate()

    fn ->
      with %StorageReservation{} = locked <- lock_reservation(reservation.id),
           true <- locked.lease_token == reservation.lease_token,
           :ok <- validate_initial_reservation(locked, staged),
           {:ok, claimed} <- bind_stage_claim(staged, locked, digest, claim_token, now) do
        {:ok, claimed}
      else
        false -> {:error, :snapshot_object_stage_reservation_binding_conflict}
        {:error, _reason} = error -> error
      end
    end
    |> transact()
    |> case do
      {:ok, {claimed, action}} -> {:ok, claimed, action}
      {:error, _reason} = error -> error
    end
  end

  defp bind_stage_claim(staged, reservation, digest, claim_token, now) do
    inserted = insert_claim(staged, reservation, digest, claim_token, now)
    claim = lock_claim(staged.object_prefix)

    with :ok <- validate_claim_reservation(claim, reservation),
         {:ok, claim, action} <- classify_stage_claim(inserted, claim, digest, now) do
      {:ok,
       {%{
          staged
          | publication_claim_token: claim.claim_token,
            storage_reservation_id: claim.storage_reservation_id_snapshot,
            storage_reservation_lease_token: claim.storage_reservation_lease_token
        }, action}}
    end
  end

  defp insert_claim(staged, reservation, digest, claim_token, now) do
    {count, _rows} =
      Repo.insert_all(
        SnapshotObjectPublicationClaim,
        [
          %{
            object_prefix: staged.object_prefix,
            claim_token: claim_token,
            inventory_digest: digest,
            storage_reservation_id_snapshot: reservation.id,
            storage_reservation_lease_token: reservation.lease_token,
            status: "staging",
            lease_expires_at: claim_lease_expires_at(now),
            inserted_at: now,
            updated_at: now
          }
        ],
        on_conflict: :nothing,
        conflict_target: [:object_prefix]
      )

    count
  end

  defp classify_stage_claim(1, %SnapshotObjectPublicationClaim{} = claim, _digest, _now), do: {:ok, claim, :write}

  defp classify_stage_claim(
         _inserted,
         %SnapshotObjectPublicationClaim{inventory_digest: digest, status: status} = claim,
         digest,
         _now
       )
       when status in ["staged", "publishing", "published"], do: {:ok, claim, String.to_existing_atom(status)}

  defp classify_stage_claim(
         _inserted,
         %SnapshotObjectPublicationClaim{inventory_digest: digest, status: "staging", lease_expires_at: expires_at} =
           claim,
         digest,
         now
       ) do
    if lease_active?(expires_at, now),
      do: {:error, :snapshot_object_namespace_in_progress},
      else: {:ok, claim, :recover_staging}
  end

  defp classify_stage_claim(_inserted, %SnapshotObjectPublicationClaim{status: "poisoned"}, _digest, _now),
    do: {:error, :snapshot_object_namespace_cleanup_handed_off}

  defp classify_stage_claim(_inserted, %SnapshotObjectPublicationClaim{}, _digest, _now),
    do: {:error, :snapshot_object_namespace_inventory_conflict}

  defp classify_stage_claim(_inserted, nil, _digest, _now), do: {:error, :snapshot_object_stage_claim_missing}

  defp acquire_publication_claim(staged, on_progress) do
    now = TimeHelpers.now()

    case transact(fn -> publication_claim_action(lock_claim(staged.object_prefix), staged, now) end) do
      {:ok, :recover} -> recover_publication_claim(staged, on_progress)
      other -> other
    end
  end

  defp publication_claim_action(%SnapshotObjectPublicationClaim{status: "staged"} = claim, staged, now) do
    with :ok <- validate_matching_claim(claim, staged),
         {:ok, _claim} <-
           claim
           |> SnapshotObjectPublicationClaim.status_changeset("publishing", claim_lease_expires_at(now))
           |> Repo.update() do
      {:ok, :claimed}
    end
  end

  defp publication_claim_action(%SnapshotObjectPublicationClaim{status: "published"} = claim, staged, _now) do
    with :ok <- validate_matching_claim(claim, staged), do: {:ok, :published}
  end

  defp publication_claim_action(%SnapshotObjectPublicationClaim{status: "publishing"} = claim, staged, _now) do
    with :ok <- validate_matching_claim(claim, staged), do: {:ok, :recover}
  end

  defp publication_claim_action(%SnapshotObjectPublicationClaim{status: "poisoned"}, _staged, _now),
    do: {:error, :snapshot_object_namespace_cleanup_handed_off}

  defp publication_claim_action(%SnapshotObjectPublicationClaim{}, _staged, _now),
    do: {:error, :snapshot_object_publication_claim_conflict}

  defp publication_claim_action(nil, _staged, _now), do: {:error, :snapshot_object_publication_claim_missing}

  defp recover_publication_claim(staged, on_progress) do
    if claim_lease_active?(staged, TimeHelpers.now()),
      do: {:error, :snapshot_object_publication_in_progress},
      else: recover_expired_publication_claim(staged, on_progress)
  end

  defp recover_expired_publication_claim(staged, on_progress) do
    case verify_exact_ready_pair(staged, on_progress) do
      {:ok, _checksum} ->
        with :ok <- complete_expired_publication_claim(staged), do: {:ok, :published}

      {:error, ready_reason} ->
        recover_expired_publication_claim_from_staging(staged, on_progress, ready_reason)
    end
  end

  defp recover_expired_publication_claim_from_staging(staged, on_progress, ready_reason) do
    case verify_exact_staging_pair(staged, on_progress) do
      {:ok, _checksum} ->
        takeover_expired_publication_claim(staged)

      {:error, staging_reason} ->
        poison_expired_and_handoff(
          staged,
          "publishing",
          :publish_recovery,
          %{ready_reason: ready_reason, staging_reason: staging_reason}
        )
    end
  end

  defp claim_lease_active?(staged, now) do
    case Repo.get(SnapshotObjectPublicationClaim, staged.object_prefix) do
      %SnapshotObjectPublicationClaim{} = claim ->
        claim.status in ["staging", "publishing"] and
          validate_matching_claim(claim, staged) == :ok and lease_active?(claim.lease_expires_at, now)

      nil ->
        false
    end
  end

  defp recover_expired_staging_claim(staged) do
    transact(fn ->
      with {:ok, claim} <- matching_claim(staged) do
        recover_expired_staging_claim(claim, TimeHelpers.now())
      end
    end)
  end

  defp recover_expired_staging_claim(%SnapshotObjectPublicationClaim{status: "staged"}, _now), do: :ok

  defp recover_expired_staging_claim(%SnapshotObjectPublicationClaim{status: "staging"} = claim, now) do
    if lease_active?(claim.lease_expires_at, now) do
      {:error, :snapshot_object_namespace_in_progress}
    else
      claim
      |> SnapshotObjectPublicationClaim.status_changeset("staged")
      |> Repo.update()
      |> update_ok()
    end
  end

  defp recover_expired_staging_claim(%SnapshotObjectPublicationClaim{}, _now),
    do: {:error, :snapshot_object_stage_claim_state_conflict}

  defp takeover_expired_unstarted_staging_claim(staged) do
    now = TimeHelpers.now()

    transact(fn ->
      with %StorageReservation{} = reservation <- lock_reservation(staged.storage_reservation_id),
           :ok <- validate_initial_reservation(reservation, staged),
           {:ok, claim} <- matching_claim(staged) do
        renew_expired_unstarted_staging_claim(reservation, claim, now)
      else
        nil -> {:error, :snapshot_object_stage_reservation_missing}
        {:error, _reason} = error -> error
      end
    end)
  end

  defp renew_expired_unstarted_staging_claim(reservation, claim, now) do
    cond do
      not is_nil(reservation.storage_started_at) ->
        {:error, :snapshot_object_stage_reservation_already_started}

      claim.status != "staging" ->
        {:error, :snapshot_object_stage_claim_state_conflict}

      lease_active?(claim.lease_expires_at, now) ->
        {:error, :snapshot_object_namespace_in_progress}

      true ->
        claim
        |> SnapshotObjectPublicationClaim.status_changeset("staging", claim_lease_expires_at(now))
        |> Repo.update()
        |> update_ok()
    end
  end

  defp complete_expired_publication_claim(staged) do
    transact(fn ->
      with {:ok, claim} <- matching_claim(staged) do
        complete_expired_publication_claim(claim, TimeHelpers.now())
      end
    end)
  end

  defp complete_expired_publication_claim(%SnapshotObjectPublicationClaim{status: "published"}, _now), do: :ok

  defp complete_expired_publication_claim(%SnapshotObjectPublicationClaim{status: "publishing"} = claim, now) do
    if lease_active?(claim.lease_expires_at, now) do
      {:error, :snapshot_object_publication_in_progress}
    else
      claim
      |> SnapshotObjectPublicationClaim.status_changeset("published")
      |> Repo.update()
      |> update_ok()
    end
  end

  defp complete_expired_publication_claim(%SnapshotObjectPublicationClaim{}, _now),
    do: {:error, :snapshot_object_publication_claim_state_conflict}

  defp takeover_expired_publication_claim(staged) do
    now = TimeHelpers.now()

    transact(fn ->
      with {:ok, claim} <- matching_claim(staged) do
        takeover_expired_publication_claim(claim, now)
      end
    end)
  end

  defp takeover_expired_publication_claim(%SnapshotObjectPublicationClaim{status: "published"}, _now),
    do: {:ok, :published}

  defp takeover_expired_publication_claim(%SnapshotObjectPublicationClaim{status: "publishing"} = claim, now) do
    if lease_active?(claim.lease_expires_at, now) do
      {:error, :snapshot_object_publication_in_progress}
    else
      claim
      |> SnapshotObjectPublicationClaim.status_changeset("publishing", claim_lease_expires_at(now))
      |> Repo.update()
      |> publication_takeover_result()
    end
  end

  defp takeover_expired_publication_claim(%SnapshotObjectPublicationClaim{}, _now),
    do: {:error, :snapshot_object_publication_claim_state_conflict}

  defp publication_takeover_result({:ok, _claim}), do: {:ok, :claimed}
  defp publication_takeover_result({:error, _reason} = error), do: error

  defp transition_claim(staged, expected_status, next_status) do
    transact(fn ->
      with {:ok, claim} <- matching_claim(staged),
           true <- claim.status in [expected_status, next_status],
           {:ok, _claim} <- claim |> SnapshotObjectPublicationClaim.status_changeset(next_status) |> Repo.update() do
        :ok
      else
        false -> {:error, :snapshot_object_publication_claim_state_conflict}
        {:error, _reason} = error -> error
      end
    end)
  end

  defp poison_and_handoff(staged, phase, reason) do
    case poison_claim(staged) do
      :ok ->
        handoff_poisoned_claim(staged, phase, reason)

      {:error, persistence_error} ->
        cleanup_not_persisted_error(staged, phase, reason, persistence_error)
    end
  end

  defp poison_expired_and_handoff(staged, expected_status, phase, reason) do
    with :ok <- poison_expired_claim(staged, expected_status) do
      handoff_poisoned_claim(staged, phase, reason)
    end
  end

  defp handoff_poisoned_claim(staged, phase, reason) do
    case persist_cleanup(staged.cleanup.storage_keys) do
      {:ok, cleanup_request_id} ->
        cleanup = Map.put(staged.cleanup, :cleanup_request_id, cleanup_request_id)
        {:error, {:snapshot_archive_failed, %{phase: phase, reason: reason, cleanup: cleanup}}}

      {:error, cleanup_reason} ->
        cleanup_not_persisted_error(staged, phase, reason, cleanup_reason)
    end
  end

  defp cleanup_not_persisted_error(staged, phase, reason, persistence_error) do
    {:error,
     {:snapshot_object_cleanup_not_persisted,
      %{phase: phase, reason: reason, persistence_error: persistence_error, cleanup: staged.cleanup}}}
  end

  defp poison_expired_claim(staged, expected_status) do
    transact(fn ->
      with {:ok, claim} <- matching_claim(staged) do
        poison_expired_claim(claim, expected_status, TimeHelpers.now())
      end
    end)
  end

  defp poison_expired_claim(%SnapshotObjectPublicationClaim{status: "poisoned"}, _expected_status, _now),
    do: {:error, :snapshot_object_namespace_cleanup_handed_off}

  defp poison_expired_claim(%SnapshotObjectPublicationClaim{status: status} = claim, status, now) do
    if lease_active?(claim.lease_expires_at, now),
      do: in_progress_error(status),
      else: poison_existing_claim(claim)
  end

  defp poison_expired_claim(%SnapshotObjectPublicationClaim{}, _expected_status, _now),
    do: {:error, :snapshot_object_publication_claim_state_conflict}

  defp in_progress_error("staging"), do: {:error, :snapshot_object_namespace_in_progress}
  defp in_progress_error("publishing"), do: {:error, :snapshot_object_publication_in_progress}

  defp poison_claim(staged) do
    transact(fn ->
      with {:ok, claim} <- matching_claim(staged) do
        poison_existing_claim(claim)
      end
    end)
  end

  defp poison_existing_claim(%SnapshotObjectPublicationClaim{status: "poisoned"}), do: :ok

  defp poison_existing_claim(%SnapshotObjectPublicationClaim{status: "published"}),
    do: {:error, :cannot_poison_published_snapshot_namespace}

  defp poison_existing_claim(claim) do
    claim
    |> SnapshotObjectPublicationClaim.status_changeset("poisoned")
    |> Repo.update()
    |> update_ok()
  end

  defp delete_unstarted_claim(staged) do
    transact(fn ->
      with {:ok, %SnapshotObjectPublicationClaim{status: "staging"} = claim} <- matching_claim(staged),
           {:ok, _claim} <- Repo.delete(claim) do
        :ok
      else
        {:ok, _claim} -> {:error, :snapshot_object_stage_claim_state_conflict}
        {:error, _reason} = error -> error
      end
    end)
  end

  defp cleanup_published_staging(staged, stored) do
    staging_keys = [staged.archive_staging_key, staged.manifest_staging_key]

    case delete_cleanup_keys(staging_keys) do
      :ok ->
        {:ok, stored}

      {:error, failed_keys} ->
        case persist_cleanup(failed_keys) do
          {:ok, cleanup_request_id} ->
            {:ok, %{stored | staging_cleanup_request_id: cleanup_request_id}}

          {:error, reason} ->
            {:error, {:snapshot_staging_cleanup_not_persisted, %{persistence_error: reason, storage_keys: failed_keys}}}
        end
    end
  end

  defp delete_cleanup_keys(storage_keys) do
    delete_fun = configured_callback(:cleanup_delete_fun, &StorageCompensation.delete_storage_keys/1)

    case invoke_callback(delete_fun, [storage_keys]) do
      :ok -> :ok
      {:error, failed_keys} when is_list(failed_keys) -> {:error, failed_keys}
      {:error, _reason} -> {:error, storage_keys}
      _invalid -> {:error, storage_keys}
    end
  end

  defp persist_cleanup(storage_keys) do
    persist_fun = configured_callback(:cleanup_persist_fun, &StorageCompensation.persist_planned_cleanup_request/1)

    case invoke_callback(persist_fun, [Enum.sort(storage_keys)]) do
      {:ok, %{id: id}} when is_integer(id) and id > 0 -> {:ok, id}
      {:error, _reason} = error -> error
      invalid -> {:error, {:invalid_snapshot_cleanup_persistence_result, invalid}}
    end
  end

  defp configured_callback(key, default) do
    case Application.get_env(:storyarn, __MODULE__, []) do
      opts when is_list(opts) ->
        case Keyword.get(opts, key, default) do
          callback when is_function(callback, 1) -> callback
          _invalid -> default
        end

      _invalid ->
        default
    end
  end

  defp reservation_storage_started?(reservation_id) do
    case Repo.get(StorageReservation, reservation_id) do
      %StorageReservation{storage_started_at: nil} -> false
      %StorageReservation{storage_started_at: %DateTime{}} -> true
      _invalid -> :unknown
    end
  end

  defp validate_staged_archive(staged) do
    expected_cleanup = cleanup_scope!(staged.project_id, staged.object_prefix)

    with :ok <- validate_staged_ready_key(staged),
         :ok <- validate_staged_prefix(staged),
         :ok <- validate_staged_archive_key(staged),
         :ok <- validate_staged_manifest_keys(staged),
         :ok <- validate_staged_cleanup(staged, expected_cleanup) do
      validate_staged_accounting(staged)
    end
  rescue
    _error -> {:error, :invalid_snapshot_archive_publish_request}
  end

  defp validate_staged_ready_key(staged) do
    if ready_archive_key?(staged.project_id, staged.object_prefix, staged.archive_storage_key),
      do: :ok,
      else: {:error, :invalid_snapshot_archive_ready_key}
  end

  defp validate_staged_prefix(staged) do
    if staged.staging_prefix == staging_prefix(staged.project_id, staged.token),
      do: :ok,
      else: {:error, :invalid_snapshot_archive_staging_prefix}
  end

  defp validate_staged_archive_key(staged) do
    if staged.archive_staging_key == archive_key(staged.staging_prefix),
      do: :ok,
      else: {:error, :invalid_snapshot_archive_staging_key}
  end

  defp validate_staged_manifest_keys(staged) do
    valid? =
      staged.manifest_staging_key == manifest_key(staged.staging_prefix) and
        staged.manifest_storage_key == manifest_key(staged.object_prefix)

    if valid?, do: :ok, else: {:error, :invalid_snapshot_archive_manifest_key}
  end

  defp validate_staged_cleanup(staged, expected_cleanup) do
    if staged.cleanup == expected_cleanup,
      do: :ok,
      else: {:error, :invalid_snapshot_archive_cleanup_scope}
  end

  defp validate_staged_accounting(staged) do
    valid? =
      staged.total_size_bytes == staged.archive_size_bytes + staged.manifest_size_bytes and
        staged.accounted_size_bytes == staged.total_size_bytes and staged.object_count == 2 and
        valid_archive_checksum?(staged.archive_checksum)

    if valid?, do: :ok, else: {:error, :invalid_snapshot_archive_accounting}
  end

  defp matching_claim(staged) do
    case lock_claim(staged.object_prefix) do
      %SnapshotObjectPublicationClaim{} = claim ->
        case validate_matching_claim(claim, staged) do
          :ok -> {:ok, claim}
          {:error, _reason} = error -> error
        end

      nil ->
        {:error, :snapshot_object_publication_claim_missing}
    end
  end

  defp validate_matching_claim(claim, staged) do
    digest = SnapshotObjectPublicationClaim.inventory_digest(staged)

    if claim.claim_token == staged.publication_claim_token and claim.inventory_digest == digest and
         claim.storage_reservation_id_snapshot == staged.storage_reservation_id and
         claim.storage_reservation_lease_token == staged.storage_reservation_lease_token,
       do: :ok,
       else: {:error, :snapshot_object_publication_claim_conflict}
  end

  defp validate_claim_reservation(
         %SnapshotObjectPublicationClaim{
           storage_reservation_id_snapshot: reservation_id,
           storage_reservation_lease_token: lease_token
         },
         %StorageReservation{id: reservation_id, lease_token: lease_token}
       ), do: :ok

  defp validate_claim_reservation(_claim, _reservation), do: {:error, :snapshot_object_stage_reservation_binding_conflict}

  defp lock_claim(object_prefix) do
    Repo.one(
      from(claim in SnapshotObjectPublicationClaim,
        where: claim.object_prefix == ^object_prefix,
        lock: "FOR UPDATE"
      )
    )
  end

  defp lock_reservation(reservation_id) do
    Repo.one(
      from(reservation in StorageReservation,
        where: reservation.id == ^reservation_id,
        lock: "FOR UPDATE"
      )
    )
  end

  defp transact(fun) do
    case Repo.transaction(fun) do
      {:ok, {:ok, result}} -> {:ok, result}
      {:ok, :ok} -> :ok
      {:ok, {:error, reason}} -> {:error, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  defp update_ok({:ok, _value}), do: :ok
  defp update_ok({:error, _reason} = error), do: error

  defp stage_reservation(opts) do
    case Keyword.fetch(opts, :storage_reservation) do
      {:ok, %StorageReservation{id: id} = reservation} when is_integer(id) and id > 0 -> {:ok, reservation}
      {:ok, _invalid} -> {:error, :invalid_snapshot_stage_reservation}
      :error -> {:error, :snapshot_stage_reservation_required}
    end
  end

  defp required_callback(opts, key, arity) do
    case Keyword.fetch(opts, key) do
      {:ok, callback} when is_function(callback, arity) -> {:ok, callback}
      {:ok, _invalid} -> {:error, {:invalid_snapshot_archive_callback, key}}
      :error -> {:error, {:snapshot_archive_callback_required, key}}
    end
  end

  defp optional_callback(opts, key, arity, default) do
    case Keyword.get(opts, key, default) do
      callback when is_function(callback, arity) -> {:ok, callback}
      _invalid -> {:error, {:invalid_snapshot_archive_callback, key}}
    end
  end

  defp cleanup_scope!(project_id, ready) do
    {:ok, scope} = cleanup_scope(project_id, ready)
    scope
  end

  defp cleanup_keys(staging, ready) do
    Enum.sort([archive_key(staging), manifest_key(staging), archive_key(ready), manifest_key(ready)])
  end

  defp token_from_ready_prefix(project_id, prefix) do
    base = "projects/#{project_id}/snapshots/archives/v#{@format_version}/ready/"

    case String.starts_with?(prefix, base) && String.replace_prefix(prefix, base, "") do
      token when is_binary(token) ->
        with :ok <- validate_token(token), do: {:ok, token}

      false ->
        {:error, :invalid_snapshot_archive_ready_prefix}
    end
  end

  defp validate_token(token) when is_binary(token) do
    if Regex.match?(@token_regex, token), do: :ok, else: {:error, :invalid_snapshot_object_token}
  end

  defp validate_token(_token), do: {:error, :invalid_snapshot_object_token}

  defp claim_lease_expires_at(now), do: DateTime.add(now, ProjectSnapshotLeasePolicy.build_lease_ttl_seconds(), :second)

  defp lease_active?(%DateTime{} = expires_at, %DateTime{} = now), do: DateTime.after?(expires_at, now)
  defp lease_active?(_expires_at, _now), do: false

  defp binary_chunk_stream(bytes, chunk_size) when is_binary(bytes) and is_integer(chunk_size) and chunk_size > 0 do
    size = byte_size(bytes)

    Stream.unfold(0, fn
      offset when offset < size ->
        next_size = min(chunk_size, size - offset)
        {binary_part(bytes, offset, next_size), offset + next_size}

      _offset ->
        nil
    end)
  end

  defp conditional_opts(%{etag: etag}) when is_binary(etag) and etag != "", do: [etag: etag]
  defp conditional_opts(_stat), do: []

  defp normalize_storage_failure(key, reason) do
    if missing_storage_object?(reason),
      do: {:missing_snapshot_archive_object, key},
      else: reason
  end

  defp missing_storage_object?(:enoent), do: true
  defp missing_storage_object?({:http_error, 404, _response}), do: true
  defp missing_storage_object?(_reason), do: false

  defp decode_json(bytes, path) do
    case Jason.decode(bytes) do
      {:ok, value} -> {:ok, value}
      {:error, reason} -> {:error, {:invalid_snapshot_object_json, path, reason}}
    end
  end

  defp secure_digest_equal?(left, right)
       when is_binary(left) and is_binary(right) and byte_size(left) == 64 and byte_size(right) == 64,
       do: Plug.Crypto.secure_compare(left, right)

  defp secure_digest_equal?(_left, _right), do: false

  defp valid_archive_checksum?(checksum),
    do: is_binary(checksum) and byte_size(checksum) == 64 and checksum =~ ~r/\A[0-9a-f]{64}\z/
end
