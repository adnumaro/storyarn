defmodule Storyarn.Versioning.SnapshotObjectStorage do
  @moduledoc """
  Persists and verifies canonical snapshot-owned object sets.

  Payload objects are first written and verified beneath an inert staging
  namespace. Publication is a separate, explicitly authorized step: the
  authorization callback receives the exact verified byte count before any
  ready object is copied. Ready payload objects are then copied and verified
  before `manifest.json` is published last. A missing manifest therefore means
  "not ready", and retrying the same token is idempotent because every existing
  destination is reverified. Every failed write or publication first poisons
  its exclusive claim and then durably records the complete planned cleanup
  inventory. Successful publication removes only staging objects and reports
  any deferred staging-cleanup request. Claim leases are progress metadata
  only: expiry never authorizes a second writer to take over a namespace.

  This module deliberately does not enqueue capture work, retain snapshots, or
  restore a project. Those lifecycle concerns belong to their dedicated flows.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Assets.Asset
  alias Storyarn.Assets.BlobStore
  alias Storyarn.Assets.Storage
  alias Storyarn.Assets.StorageCleanupOwnershipReceipt
  alias Storyarn.Assets.StorageCompensation
  alias Storyarn.Assets.StorageHash
  alias Storyarn.Billing.StorageReservation
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Versioning.SnapshotObjectFormat
  alias Storyarn.Versioning.SnapshotObjectPublicationClaim
  alias Storyarn.Versioning.SnapshotStorage

  @token_regex ~r/\A[A-Za-z0-9_-]{16}\z/
  @sha256_regex ~r/\A[0-9a-f]{64}\z/
  @blob_filename_regex ~r/\A[0-9a-f]{64}\.[a-z0-9][a-z0-9-]{0,31}\z/
  @publication_claim_lease_seconds 21_600

  @type stored_object_set :: %{
          format_version: pos_integer(),
          mode: String.t(),
          lifecycle_state: String.t(),
          integrity_state: String.t(),
          object_prefix: String.t(),
          manifest_storage_key: String.t(),
          manifest_size_bytes: non_neg_integer(),
          manifest_checksum: String.t(),
          project_storage_key: String.t(),
          project_size_bytes: non_neg_integer(),
          project_checksum: String.t(),
          total_size_bytes: non_neg_integer(),
          accounted_size_bytes: non_neg_integer(),
          asset_blob_size_bytes: non_neg_integer(),
          accounting_version: pos_integer(),
          object_count: pos_integer(),
          asset_count: non_neg_integer(),
          blob_count: non_neg_integer(),
          staging_cleanup_request_id: pos_integer() | nil
        }

  @type prepared_capture :: %{
          capture_digest: String.t(),
          project_json: binary(),
          manifest_json: binary(),
          source_keys: %{String.t() => String.t()},
          project_size_bytes: pos_integer(),
          project_checksum: String.t(),
          manifest_size_bytes: pos_integer(),
          manifest_checksum: String.t(),
          total_size_bytes: pos_integer(),
          asset_blob_size_bytes: non_neg_integer(),
          object_count: pos_integer(),
          asset_count: non_neg_integer(),
          blob_count: non_neg_integer()
        }

  @type cleanup_scope :: %{
          project_id: pos_integer(),
          token: String.t(),
          staging_prefix: String.t(),
          ready_prefix: String.t(),
          storage_keys: [String.t()]
        }

  @type persisted_cleanup_scope :: %{
          project_id: pos_integer(),
          token: String.t(),
          staging_prefix: String.t(),
          ready_prefix: String.t(),
          storage_keys: [String.t()],
          cleanup_request_id: pos_integer()
        }

  @type staged_object_set :: %{
          project_id: pos_integer(),
          token: String.t(),
          limits: map(),
          format_version: pos_integer(),
          mode: String.t(),
          lifecycle_state: String.t(),
          integrity_state: String.t(),
          staging_prefix: String.t(),
          object_prefix: String.t(),
          manifest_staging_key: String.t(),
          manifest_storage_key: String.t(),
          manifest_size_bytes: non_neg_integer(),
          manifest_checksum: String.t(),
          project_staging_key: String.t(),
          project_storage_key: String.t(),
          project_size_bytes: non_neg_integer(),
          project_checksum: String.t(),
          total_size_bytes: non_neg_integer(),
          accounted_size_bytes: non_neg_integer(),
          asset_blob_size_bytes: non_neg_integer(),
          accounting_version: pos_integer(),
          object_count: pos_integer(),
          asset_count: non_neg_integer(),
          blob_count: non_neg_integer(),
          publication_claim_token: Ecto.UUID.t(),
          storage_reservation_id: pos_integer(),
          storage_reservation_lease_token: Ecto.UUID.t(),
          staging_cleanup_request_id: nil,
          cleanup: cleanup_scope()
        }

  @doc """
  Materializes the exact immutable JSON objects and protected source map for a
  later asynchronous build.

  No storage object is written. Asset bytes remain outside application memory;
  the returned source keys point at content-addressed project blobs which the
  asset deletion path is forbidden to remove.
  """
  @spec prepare(pos_integer(), map(), [Asset.t()], keyword()) ::
          {:ok, prepared_capture()} | {:error, term()}
  def prepare(project_id, project_snapshot, assets, opts \\ [])

  def prepare(project_id, project_snapshot, assets, opts)
      when is_integer(project_id) and project_id > 0 and is_list(assets) and is_list(opts) do
    opts = Keyword.put_new(opts, :source_key_mode, :protected_blob)

    with {:ok, normalized_project} <- normalize_project_snapshot(project_snapshot),
         {:ok, project} <- SnapshotObjectFormat.portable_project(normalized_project),
         {:ok, catalog} <- SnapshotObjectFormat.build_catalog(assets, Keyword.put(opts, :project_id, project_id)),
         {:ok, project_descriptor, project_json} <- project_descriptor(project, opts),
         {:ok, manifest} <-
           SnapshotObjectFormat.build_manifest(
             project,
             catalog.assets,
             catalog.blobs,
             Keyword.put(opts, :project_descriptor, project_descriptor)
           ),
         {:ok, manifest_json, manifest_descriptor} <- manifest_descriptor(manifest, opts) do
      {:ok, prepared_capture(project_json, manifest_json, manifest, manifest_descriptor, catalog.source_keys)}
    end
  end

  def prepare(_project_id, _project_snapshot, _assets, _opts), do: {:error, :invalid_snapshot_object_source}

  @doc """
  Stages, verifies, authorizes, and publishes a complete snapshot object set.

  `:token` may be supplied by an orchestrator to retry the exact same immutable
  namespace until cleanup ownership has been handed off. A handed-off token is
  permanently poisoned and a retry must allocate a new token. When omitted, a
  cryptographically random token is generated. A
  `:before_publish` callback is required. It receives a `staged_object_set/0`
  with the exact verified byte count and must atomically authorize or extend the
  caller's storage reservation before returning `{:ok, reservation}`. A
  durable, unstarted `:storage_reservation` is required before staging claims
  its namespace. `:before_stage` must mark and return that same reservation
  with the complete cleanup plan before any storage write.

  This convenience function is equivalent to `stage/4` followed by
  `publish/2`. Callers which need to durably retain the staged result between
  those steps should use those functions directly.
  """
  @spec persist(pos_integer(), map(), [Asset.t()], keyword()) ::
          {:ok, stored_object_set()} | {:error, term()}
  def persist(project_id, project_snapshot, assets, opts \\ [])

  def persist(project_id, project_snapshot, assets, opts)
      when is_integer(project_id) and project_id > 0 and is_list(assets) do
    with {:ok, before_publish} <- fetch_before_publish(opts),
         {:ok, staged} <- stage(project_id, project_snapshot, assets, opts) do
      publish(staged, before_publish)
    end
  end

  def persist(_project_id, _project_snapshot, _assets, _opts), do: {:error, :invalid_snapshot_object_source}

  @doc """
  Writes and verifies a complete snapshot beneath an inert staging namespace.

  No object is written beneath the ready prefix. The returned value contains
  the exact verified byte count, the eventual ready keys, and a deterministic
  cleanup scope covering both sibling namespaces. The supplied durable
  `:storage_reservation` is bound to the exclusive namespace claim before a
  mandatory `:before_stage` callback receives the complete plan. The callback
  must durably mark that same reservation before any storage write. Supplying
  the same token and content is idempotent
  until cleanup is handed off. Once writing starts, any failure returns the
  durable cleanup request id for the complete planned staging and ready
  inventory, or an explicit `cleanup_not_persisted` failure.
  """
  @spec stage(pos_integer(), map(), [Asset.t()], keyword()) ::
          {:ok, staged_object_set()} | {:error, term()}
  def stage(project_id, project_snapshot, assets, opts \\ [])

  def stage(project_id, project_snapshot, assets, opts)
      when is_integer(project_id) and project_id > 0 and is_list(assets) do
    opts = Keyword.put_new(opts, :source_key_mode, :asset)

    with {:ok, prepared} <- prepare(project_id, project_snapshot, assets, opts) do
      stage_prepared(project_id, prepared, opts)
    end
  end

  def stage(_project_id, _project_snapshot, _assets, _opts), do: {:error, :invalid_snapshot_object_source}

  @doc """
  Stages an exact capture previously returned by `prepare/4`.

  The JSON digests, manifest inventory, and protected source-key inventory are
  revalidated before any claim or storage write. This is the asynchronous
  boundary used by snapshot workers; it never re-reads current project rows.
  """
  @spec stage_prepared(pos_integer(), prepared_capture(), keyword()) ::
          {:ok, staged_object_set()} | {:error, term()}
  def stage_prepared(project_id, prepared, opts \\ [])

  def stage_prepared(project_id, prepared, opts)
      when is_integer(project_id) and project_id > 0 and is_map(prepared) and is_list(opts) do
    token = Keyword.get(opts, :token, SnapshotStorage.unique_key_suffix())

    with {:ok, before_stage} <- fetch_before_stage(opts),
         {:ok, on_progress} <- fetch_on_progress(opts),
         {:ok, stage_reservation} <- fetch_stage_reservation(opts),
         :ok <- validate_token(token),
         :ok <- validate_canonical_stage_limits(opts),
         :ok <- ensure_namespace_not_handed_off(project_id, token),
         {:ok, source} <- validate_prepared_capture(project_id, prepared, opts) do
      staging_prefix = staging_prefix(project_id, token)
      ready_prefix = ready_prefix(project_id, token)
      limits = SnapshotObjectFormat.limits(opts)

      staged =
        staged_object_set(
          project_id,
          token,
          staging_prefix,
          ready_prefix,
          source.manifest,
          source.manifest_descriptor,
          limits
        )

      with {:ok, claimed_staged, action} <- acquire_stage_claim(staged, stage_reservation) do
        payload = %{
          project_descriptor: source.project_descriptor,
          project_json: prepared.project_json,
          blobs: source.blobs,
          source_keys: prepared.source_keys,
          manifest_descriptor: source.manifest_descriptor,
          manifest_json: prepared.manifest_json
        }

        authorize_and_stage_claimed_object_set(
          before_stage,
          claimed_staged,
          action,
          payload,
          on_progress
        )
      end
    end
  end

  def stage_prepared(_project_id, _prepared, _opts), do: {:error, :invalid_prepared_snapshot_capture}

  defp authorize_and_stage_claimed_object_set(before_stage, claimed_staged, action, payload, on_progress) do
    case authorize_claimed_stage(before_stage, claimed_staged, action) do
      :ok ->
        stage_claimed_object_set(claimed_staged, action, payload, on_progress)

      {:error, reason} ->
        handle_stage_authorization_failure(claimed_staged, reason)
    end
  end

  @doc """
  Authorizes and publishes a previously staged snapshot object set.

  The callback runs only after all staged objects and exact measurements have
  been reverified, and before any object is copied to the ready namespace. It
  must durably extend the bound reservation to the exact measured size and
  return `{:ok, reservation}`. It must be idempotent because publication itself
  is retryable. Returning `{:error, reason}`, an unpersisted value, raising,
  throwing, or exiting fails closed: no ready copy is started by that attempt
  and the error includes a durable cleanup request
  id for the deterministic complete inventory (or explicitly reports that it
  could not be persisted). Once authorized, payload objects are copied first
  and `manifest.json` is copied last. A successful result includes
  `staging_cleanup_request_id` when staging deletion had to be handed off;
  ready keys are never part of that success cleanup.
  """
  @spec publish(
          staged_object_set(),
          (staged_object_set() -> {:ok, StorageReservation.t()} | {:error, term()}),
          keyword()
        ) ::
          {:ok, stored_object_set()} | {:error, term()}
  def publish(staged, before_publish, opts \\ [])

  def publish(staged, before_publish, opts) when is_map(staged) and is_function(before_publish, 1) and is_list(opts) do
    with {:ok, on_progress} <- fetch_on_progress(opts),
         :ok <- ensure_staged_namespace_not_handed_off(staged),
         {:ok, claim_action} <- acquire_publication_claim(staged) do
      publish_claimed_object_set(staged, before_publish, claim_action, on_progress)
    end
  end

  def publish(_staged, _before_publish, _opts), do: {:error, :invalid_snapshot_publish_request}

  @doc """
  Loads a ready manifest and verifies every declared object before returning the
  project payload. Staging keys are rejected even when they contain a manifest.
  """
  @spec load_verified(String.t(), String.t(), non_neg_integer(), keyword()) ::
          {:ok, %{manifest: map(), project: map()}} | {:error, term()}
  def load_verified(manifest_storage_key, manifest_checksum, manifest_size_bytes, opts \\ []) do
    with {:ok, %{manifest: manifest, ready_prefix: ready_prefix}} <-
           load_verified_manifest(manifest_storage_key, manifest_checksum, manifest_size_bytes, opts),
         :ok <- verify_blob_inventory(ready_prefix, manifest["objects"]),
         project_descriptor = manifest["project"],
         {:ok, project_json} <- read_descriptor_bytes(ready_prefix, project_descriptor),
         {:ok, project} <- decode_json(project_json, SnapshotObjectFormat.project_path()),
         :ok <- SnapshotObjectFormat.validate_project(project) do
      {:ok, %{manifest: manifest, project: project}}
    end
  end

  @doc false
  @spec inspect_ready_manifest(String.t(), String.t(), non_neg_integer(), keyword()) ::
          {:ok, %{manifest: map(), ready_prefix: String.t()}} | {:error, term()}
  def inspect_ready_manifest(manifest_storage_key, manifest_checksum, manifest_size_bytes, opts \\ [])

  def inspect_ready_manifest(manifest_storage_key, manifest_checksum, manifest_size_bytes, opts)
      when is_binary(manifest_storage_key) and is_binary(manifest_checksum) and is_integer(manifest_size_bytes) and
             manifest_size_bytes >= 0 and is_list(opts) do
    if Keyword.keyword?(opts),
      do: load_verified_manifest(manifest_storage_key, manifest_checksum, manifest_size_bytes, opts),
      else: {:error, :invalid_snapshot_inspection_request}
  end

  def inspect_ready_manifest(_manifest_storage_key, _manifest_checksum, _manifest_size_bytes, _opts),
    do: {:error, :invalid_snapshot_inspection_request}

  @doc false
  @spec inspect_ready_object_batch(String.t(), String.t(), non_neg_integer(), keyword()) ::
          {:ok,
           %{
             manifest: map(),
             next_index: non_neg_integer() | nil,
             ready_prefix: String.t(),
             verified_bytes: non_neg_integer(),
             verified_objects: non_neg_integer()
           }}
          | {:error, term()}
  def inspect_ready_object_batch(manifest_storage_key, manifest_checksum, manifest_size_bytes, opts \\ [])

  def inspect_ready_object_batch(manifest_storage_key, manifest_checksum, manifest_size_bytes, opts)
      when is_binary(manifest_storage_key) and is_binary(manifest_checksum) and is_integer(manifest_size_bytes) and
             manifest_size_bytes >= 0 and is_list(opts) do
    if Keyword.keyword?(opts) do
      inspect_ready_object_batch_with_opts(
        manifest_storage_key,
        manifest_checksum,
        manifest_size_bytes,
        opts
      )
    else
      {:error, :invalid_snapshot_inspection_request}
    end
  end

  def inspect_ready_object_batch(_manifest_storage_key, _manifest_checksum, _manifest_size_bytes, _opts),
    do: {:error, :invalid_snapshot_inspection_request}

  defp inspect_ready_object_batch_with_opts(manifest_storage_key, manifest_checksum, manifest_size_bytes, opts) do
    start_index = Keyword.get(opts, :start_index, 0)
    max_objects = Keyword.get(opts, :max_inspection_objects, 100)
    max_bytes = Keyword.get(opts, :max_inspection_bytes, 256 * 1024 * 1024)
    format_opts = Keyword.drop(opts, [:start_index, :max_inspection_objects, :max_inspection_bytes])

    with :ok <- validate_inspection_limits(start_index, max_objects, max_bytes),
         {:ok, %{manifest: manifest, ready_prefix: ready_prefix}} <-
           load_verified_manifest(manifest_storage_key, manifest_checksum, manifest_size_bytes, format_opts),
         objects = manifest["objects"],
         true <- start_index <= length(objects),
         {:ok, verified_objects, verified_bytes} <-
           verify_inspection_batch(ready_prefix, objects, start_index, max_objects, max_bytes) do
      next_index = start_index + verified_objects

      {:ok,
       %{
         manifest: manifest,
         next_index: if(next_index < length(objects), do: next_index),
         ready_prefix: ready_prefix,
         verified_bytes: verified_bytes,
         verified_objects: verified_objects
       }}
    else
      false ->
        {:error, :invalid_snapshot_inspection_cursor}

      {:error, {:inspection_object_failed, failure}} ->
        {:error, {:snapshot_inspection_object_failed, failure}}

      {:error, _reason} = error ->
        error
    end
  end

  defp load_verified_manifest(manifest_storage_key, manifest_checksum, manifest_size_bytes, opts) do
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
         :ok <- validate_loaded_manifest(manifest, opts) do
      {:ok, %{manifest: manifest, ready_prefix: ready_prefix}}
    end
  end

  defp validate_loaded_manifest(manifest, opts) do
    case SnapshotObjectFormat.validate_manifest(manifest, opts) do
      :ok -> :ok
      {:error, reason} -> {:error, {:snapshot_manifest_validation_failed, reason}}
    end
  end

  defp validate_inspection_limits(start_index, max_objects, max_bytes)
       when is_integer(start_index) and start_index >= 0 and is_integer(max_objects) and max_objects > 0 and
              max_objects <= 1_000 and is_integer(max_bytes) and max_bytes >= 128 * 1024 * 1024 and
              max_bytes <= 1024 * 1024 * 1024, do: :ok

  defp validate_inspection_limits(_start_index, _max_objects, _max_bytes),
    do: {:error, :invalid_snapshot_inspection_limits}

  defp verify_inspection_batch(ready_prefix, objects, start_index, max_objects, max_bytes) do
    objects
    |> Enum.drop(start_index)
    |> Enum.with_index(start_index)
    |> Enum.reduce_while({:ok, 0, 0}, fn {descriptor, index}, {:ok, count, bytes} ->
      descriptor_bytes = descriptor["size_bytes"]

      cond do
        count >= max_objects ->
          {:halt, {:ok, count, bytes}}

        count > 0 and bytes + descriptor_bytes > max_bytes ->
          {:halt, {:ok, count, bytes}}

        true ->
          verify_inspection_descriptor(ready_prefix, descriptor, index, length(objects), count, bytes)
      end
    end)
  end

  defp verify_inspection_descriptor(ready_prefix, descriptor, index, object_count, count, bytes) do
    case verify_inspection_object(ready_prefix, descriptor) do
      :ok ->
        {:cont, {:ok, count + 1, bytes + descriptor["size_bytes"]}}

      {:error, reason} ->
        failure = %{
          failed_index: index,
          object_count: object_count,
          path: descriptor["path"],
          reason: reason,
          verified_bytes: bytes,
          verified_objects: count
        }

        {:halt, {:error, {:inspection_object_failed, failure}}}
    end
  end

  defp verify_inspection_object(ready_prefix, %{"kind" => "project"} = descriptor) do
    with {:ok, project_json} <- read_descriptor_bytes(ready_prefix, descriptor),
         {:ok, project} <- decode_json(project_json, SnapshotObjectFormat.project_path()) do
      SnapshotObjectFormat.validate_project(project)
    end
  end

  defp verify_inspection_object(ready_prefix, descriptor) do
    verify_object(object_key(ready_prefix, descriptor["path"]), descriptor)
  end

  @doc false
  def staging_prefix(project_id, token) do
    "projects/#{project_id}/snapshots/object-sets/v#{SnapshotObjectFormat.format_version()}/staging/#{token}"
  end

  @doc false
  def ready_prefix(project_id, token) do
    "projects/#{project_id}/snapshots/object-sets/v#{SnapshotObjectFormat.format_version()}/ready/#{token}"
  end

  defp token_from_ready_prefix(project_id, prefix) do
    base = "projects/#{project_id}/snapshots/object-sets/v#{SnapshotObjectFormat.format_version()}/ready/"

    case String.replace_prefix(prefix, base, "") do
      ^prefix -> {:error, :invalid_snapshot_cleanup_scope}
      token -> if(validate_token(token) == :ok, do: {:ok, token}, else: {:error, :invalid_snapshot_cleanup_scope})
    end
  end

  @doc false
  def ready_manifest_key?(key) when is_binary(key) do
    match?({:ok, _prefix}, ready_prefix_from_manifest_key(key))
  end

  def ready_manifest_key?(_key), do: false

  defp ensure_staged_namespace_not_handed_off(%{project_id: project_id, token: token}),
    do: ensure_namespace_not_handed_off(project_id, token)

  defp ensure_staged_namespace_not_handed_off(_staged), do: :ok

  defp ensure_namespace_not_handed_off(project_id, token)
       when is_integer(project_id) and project_id > 0 and is_binary(token) do
    staging_prefix = staging_prefix(project_id, token)
    ready_prefix = ready_prefix(project_id, token)

    cond do
      StorageCleanupOwnershipReceipt.handed_off_for_prefix?(ready_prefix) ->
        {:error, :snapshot_object_namespace_cleanup_handed_off}

      StorageCleanupOwnershipReceipt.handed_off_for_prefix?(staging_prefix) and
          not published_publication_claim?(ready_prefix) ->
        {:error, :snapshot_object_namespace_cleanup_handed_off}

      true ->
        :ok
    end
  end

  defp ensure_namespace_not_handed_off(_project_id, _token), do: :ok

  @doc false
  def ready_prefix_for_project?(project_id, prefix)
      when is_integer(project_id) and project_id > 0 and is_binary(prefix) do
    String.starts_with?(
      prefix,
      "projects/#{project_id}/snapshots/object-sets/v#{SnapshotObjectFormat.format_version()}/ready/"
    ) and ready_manifest_key?(object_key(prefix, SnapshotObjectFormat.manifest_path()))
  end

  def ready_prefix_for_project?(_project_id, _prefix), do: false

  @doc false
  @spec cleanup_scope_from_capture(pos_integer(), String.t(), binary(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def cleanup_scope_from_capture(project_id, ready_prefix, manifest_json, opts \\ [])

  def cleanup_scope_from_capture(project_id, ready_prefix, manifest_json, opts)
      when is_integer(project_id) and project_id > 0 and is_binary(ready_prefix) and is_binary(manifest_json) and
             is_list(opts) do
    with true <- Keyword.keyword?(opts),
         {:ok, token} <- token_from_ready_prefix(project_id, ready_prefix),
         cleanup_opts = cleanup_manifest_options(opts),
         :ok <-
           validate_size_limit(
             byte_size(manifest_json),
             Keyword.fetch!(cleanup_opts, :max_manifest_bytes),
             :manifest
           ),
         {:ok, manifest} <- decode_json(manifest_json, SnapshotObjectFormat.manifest_path()),
         :ok <- SnapshotObjectFormat.validate_manifest(manifest, cleanup_opts),
         relative_paths when is_list(relative_paths) <-
           Enum.map(manifest["objects"], & &1["path"]) ++ [SnapshotObjectFormat.manifest_path()],
         true <- Enum.all?(relative_paths, &valid_cleanup_relative_path?/1) do
      staging_prefix = staging_prefix(project_id, token)

      storage_keys =
        Enum.flat_map([staging_prefix, ready_prefix], fn prefix ->
          Enum.map(relative_paths, &object_key(prefix, &1))
        end)

      cleanup = %{
        project_id: project_id,
        token: token,
        staging_prefix: staging_prefix,
        ready_prefix: ready_prefix,
        storage_keys: storage_keys
      }

      staged = %{
        project_id: project_id,
        token: token,
        staging_prefix: staging_prefix,
        object_prefix: ready_prefix,
        object_count: length(relative_paths),
        cleanup: cleanup
      }

      with {:ok, validated} <- validate_cleanup_scope(staged) do
        {:ok,
         Map.merge(validated, %{
           inventory_digest: cleanup_inventory_digest(storage_keys),
           estimated_cleanup_bytes: 2 * (manifest["payload_size_bytes"] + byte_size(manifest_json))
         })}
      end
    else
      false -> {:error, :invalid_snapshot_cleanup_scope}
      {:error, _reason} = error -> error
      _invalid -> {:error, :invalid_snapshot_cleanup_scope}
    end
  end

  def cleanup_scope_from_capture(_project_id, _ready_prefix, _manifest_json, _opts),
    do: {:error, :invalid_snapshot_cleanup_scope}

  # Cleanup ownership must outlive operator-configurable reader limits. Every
  # capture was accepted beneath these immutable format-v1 bounds when it was
  # created, so reconstructing its exact deletion inventory uses the same hard
  # ceiling instead of today's potentially lower runtime policy.
  defp cleanup_manifest_options(opts) do
    Keyword.merge(opts, Map.to_list(SnapshotObjectFormat.hard_limits()))
  end

  defp fetch_before_stage(opts) when is_list(opts) do
    case Keyword.fetch(opts, :before_stage) do
      {:ok, before_stage} when is_function(before_stage, 1) -> {:ok, before_stage}
      {:ok, _invalid} -> {:error, :invalid_snapshot_stage_authorizer}
      :error -> {:error, :snapshot_stage_authorization_required}
    end
  end

  defp fetch_before_stage(_opts), do: {:error, :invalid_snapshot_stage_authorizer}

  defp fetch_on_progress(opts) when is_list(opts) do
    case Keyword.get(opts, :on_progress, fn _completed_bytes -> :ok end) do
      on_progress when is_function(on_progress, 1) -> {:ok, on_progress}
      _invalid -> {:error, :invalid_snapshot_progress_callback}
    end
  end

  defp fetch_on_progress(_opts), do: {:error, :invalid_snapshot_progress_callback}

  defp fetch_stage_reservation(opts) when is_list(opts) do
    case Keyword.fetch(opts, :storage_reservation) do
      {:ok, %StorageReservation{id: reservation_id} = reservation}
      when is_integer(reservation_id) and reservation_id > 0 ->
        {:ok, reservation}

      {:ok, _invalid} ->
        {:error, :invalid_snapshot_stage_reservation}

      :error ->
        {:error, :snapshot_stage_reservation_required}
    end
  end

  defp fetch_stage_reservation(_opts), do: {:error, :invalid_snapshot_stage_reservation}

  defp fetch_before_publish(opts) when is_list(opts) do
    case Keyword.fetch(opts, :before_publish) do
      {:ok, before_publish} when is_function(before_publish, 1) -> {:ok, before_publish}
      {:ok, _invalid} -> {:error, :invalid_snapshot_publish_authorizer}
      :error -> {:error, :snapshot_publish_authorization_required}
    end
  end

  defp fetch_before_publish(_opts), do: {:error, :invalid_snapshot_publish_authorizer}

  defp validate_canonical_stage_limits(opts) when is_list(opts) do
    limits = SnapshotObjectFormat.limits(opts)

    with :ok <- SnapshotObjectFormat.validate_limits(limits),
         true <- limits == SnapshotObjectFormat.limits() do
      :ok
    else
      false -> {:error, :snapshot_object_limit_overrides_not_supported}
      {:error, _reason} = error -> error
    end
  end

  defp validate_canonical_stage_limits(_opts), do: {:error, :invalid_snapshot_object_limits}

  defp published_publication_claim?(object_prefix) do
    Repo.exists?(
      from(claim in SnapshotObjectPublicationClaim,
        where: claim.object_prefix == ^object_prefix and claim.status == "published"
      )
    )
  end

  defp authorize_stage(before_stage, staged) do
    case invoke_before_stage(before_stage, staged) do
      {:ok, reservation} -> validate_claimed_stage_reservation(staged, reservation, ["staging"])
      {:error, reason} -> {:error, {:snapshot_stage_authorization_failed, reason}}
    end
  end

  defp authorize_claimed_stage(before_stage, staged, :write), do: authorize_stage(before_stage, staged)

  defp authorize_claimed_stage(_before_stage, staged, action) when action in [:staged, :publishing, :published] do
    validate_claimed_stage_reservation(staged, nil, [Atom.to_string(action)])
  end

  defp validate_claimed_stage_reservation(
         %{storage_reservation_id: reservation_id, storage_reservation_lease_token: reservation_lease_token} = staged,
         reported_reservation,
         allowed_claim_statuses
       ) do
    fn ->
      with %StorageReservation{} = reservation <- lock_storage_reservation(reservation_id),
           :ok <- validate_reported_stage_reservation(reported_reservation, reservation),
           :ok <- validate_stage_reservation(reservation, staged, reservation_lease_token),
           {:ok, claim} <- matching_publication_claim(staged),
           true <- claim.status in allowed_claim_statuses,
           :ok <- validate_claim_reservation_binding(claim, reservation) do
        :ok
      else
        nil -> {:error, :snapshot_object_stage_reservation_missing}
        false -> {:error, :snapshot_object_stage_claim_state_conflict}
        {:error, _reason} = error -> error
        _invalid -> {:error, :snapshot_object_stage_reservation_binding_invalid}
      end
    end
    |> Repo.transaction()
    |> unwrap_claim_result(:snapshot_object_stage_reservation_validation_failed)
  end

  defp validate_claimed_stage_reservation(_staged, _reported_reservation, _allowed_claim_statuses),
    do: {:error, :snapshot_object_stage_reservation_binding_invalid}

  defp validate_claimed_publication_reservation(
         %{storage_reservation_id: reservation_id, storage_reservation_lease_token: reservation_lease_token} = staged,
         reported_reservation
       ) do
    fn ->
      with %StorageReservation{status: "active"} = reservation <-
             lock_storage_reservation(reservation_id),
           :ok <- validate_reported_stage_reservation(reported_reservation, reservation),
           :ok <- validate_stage_reservation(reservation, staged, reservation_lease_token),
           {:ok, claim} <- matching_publication_claim(staged),
           true <- claim.status == "publishing",
           :ok <- validate_claim_reservation_binding(claim, reservation) do
        :ok
      else
        nil -> {:error, :snapshot_object_stage_reservation_missing}
        false -> {:error, :snapshot_object_publication_claim_state_conflict}
        %StorageReservation{} -> {:error, :snapshot_object_stage_reservation_binding_invalid}
        {:error, _reason} = error -> error
        _invalid -> {:error, :snapshot_object_stage_reservation_binding_invalid}
      end
    end
    |> Repo.transaction()
    |> unwrap_claim_result(:snapshot_object_publication_reservation_validation_failed)
  end

  defp validate_claimed_publication_reservation(_staged, _reported_reservation),
    do: {:error, :snapshot_object_stage_reservation_binding_invalid}

  defp validate_reported_stage_reservation(nil, %StorageReservation{}), do: :ok

  defp validate_reported_stage_reservation(
         %StorageReservation{id: reservation_id, lease_token: lease_token},
         %StorageReservation{id: reservation_id, lease_token: lease_token}
       ), do: :ok

  defp validate_reported_stage_reservation(_reported, _persisted),
    do: {:error, :snapshot_object_stage_reservation_binding_conflict}

  defp validate_claim_reservation_binding(
         %SnapshotObjectPublicationClaim{
           storage_reservation_id_snapshot: reservation_id,
           storage_reservation_lease_token: lease_token
         },
         %StorageReservation{id: reservation_id, lease_token: lease_token}
       ), do: :ok

  defp validate_claim_reservation_binding(_claim, _reservation),
    do: {:error, :snapshot_object_stage_reservation_binding_conflict}

  defp validate_preflight_stage_reservation(
         %StorageReservation{
           status: "active",
           kind: "snapshot_build",
           project_id_snapshot: project_id,
           cleanup_object_prefix: object_prefix,
           lease_token: lease_token,
           expires_at: expires_at,
           storage_started_at: storage_started_at
         } = reservation,
         %{project_id: project_id, object_prefix: object_prefix} = staged,
         lease_token
       ) do
    cond do
      not lease_active?(expires_at, TimeHelpers.now()) ->
        {:error, :snapshot_object_stage_reservation_expired}

      is_nil(storage_started_at) ->
        :ok

      true ->
        validate_stage_reservation(reservation, staged, lease_token)
    end
  end

  defp validate_preflight_stage_reservation(_reservation, _staged, _lease_token),
    do: {:error, :snapshot_object_stage_reservation_binding_invalid}

  defp validate_stage_reservation(
         %StorageReservation{
           status: status,
           kind: "snapshot_build",
           project_id_snapshot: project_id,
           cleanup_object_prefix: object_prefix,
           lease_token: lease_token,
           reserved_bytes: reserved_bytes,
           expires_at: expires_at,
           storage_started_at: %DateTime{},
           cleanup_inventory_digest: cleanup_inventory_digest,
           cleanup_inventory_count: cleanup_inventory_count
         },
         %{
           project_id: project_id,
           object_prefix: object_prefix,
           accounted_size_bytes: accounted_size_bytes,
           cleanup: %{storage_keys: storage_keys}
         },
         lease_token
       )
       when status in ["active", "committed"] and is_integer(reserved_bytes) and reserved_bytes >= accounted_size_bytes do
    expected_digest = cleanup_inventory_digest(storage_keys)

    cond do
      status == "active" and not lease_active?(expires_at, TimeHelpers.now()) ->
        {:error, :snapshot_object_stage_reservation_expired}

      cleanup_inventory_digest != expected_digest or cleanup_inventory_count != length(storage_keys) ->
        {:error, :snapshot_object_stage_cleanup_commitment_mismatch}

      true ->
        :ok
    end
  end

  defp validate_stage_reservation(_reservation, _staged, _lease_token),
    do: {:error, :snapshot_object_stage_reservation_binding_invalid}

  defp lock_storage_reservation(reservation_id) do
    Repo.one(
      from(reservation in StorageReservation,
        where: reservation.id == ^reservation_id,
        lock: "FOR UPDATE"
      )
    )
  end

  defp handle_stage_authorization_failure(staged, reason) do
    result =
      fn ->
        with reservation_id when is_integer(reservation_id) and reservation_id > 0 <-
               Map.get(staged, :storage_reservation_id),
             %StorageReservation{} = reservation <- lock_storage_reservation(reservation_id),
             {:ok, claim} <- matching_publication_claim(staged),
             :ok <- validate_claim_reservation_binding(claim, reservation) do
          stage_authorization_failure_state(claim, reservation, staged)
        else
          nil -> {:error, :snapshot_object_stage_reservation_missing}
          _invalid -> {:error, :snapshot_object_stage_authorization_state_unknown}
        end
      end
      |> Repo.transaction()
      |> unwrap_claim_result(:snapshot_object_stage_authorization_cleanup_failed)

    case result do
      {:ok, :not_started} ->
        {:error, reason}

      {:ok, :cleanup_required} ->
        return_stage_failure(staged, reason)

      {:error, state_error} ->
        terminal_unowned_cleanup_failure(
          :stage_authorization,
          {:snapshot_object_stage_authorization_state_unknown, reason, state_error}
        )
    end
  end

  defp stage_authorization_failure_state(
         %SnapshotObjectPublicationClaim{status: "staging"} = claim,
         %StorageReservation{storage_started_at: nil},
         _staged
       ) do
    case Repo.delete(claim) do
      {:ok, _claim} -> {:ok, :not_started}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp stage_authorization_failure_state(
         %SnapshotObjectPublicationClaim{status: status} = claim,
         %StorageReservation{storage_started_at: %DateTime{}} = reservation,
         staged
       )
       when status in ["staging", "poisoned"] do
    with :ok <-
           validate_stage_reservation(
             reservation,
             staged,
             claim.storage_reservation_lease_token
           ),
         {:ok, _claim} <-
           claim
           |> SnapshotObjectPublicationClaim.status_changeset("poisoned")
           |> Repo.update() do
      {:ok, :cleanup_required}
    end
  end

  defp stage_authorization_failure_state(_claim, _reservation, _staged),
    do: {:error, :snapshot_object_stage_authorization_state_unknown}

  defp acquire_stage_claim(
         %{object_prefix: object_prefix} = staged,
         %StorageReservation{id: reservation_id, lease_token: reservation_lease_token} = reported_reservation
       )
       when is_integer(reservation_id) and reservation_id > 0 and is_binary(reservation_lease_token) do
    now = TimeHelpers.now()

    claim_attrs = %{
      object_prefix: object_prefix,
      claim_token: Ecto.UUID.generate(),
      inventory_digest: publication_inventory_digest(staged),
      lease_expires_at: claim_lease_expires_at(now),
      now: now
    }

    fn ->
      with %StorageReservation{} = reservation <- lock_storage_reservation(reservation_id),
           :ok <- validate_reported_stage_reservation(reported_reservation, reservation) do
        create_or_classify_stage_claim(
          reservation,
          staged,
          reservation_lease_token,
          claim_attrs
        )
      else
        nil -> {:error, :snapshot_object_stage_reservation_missing}
        {:error, _reason} = error -> error
      end
    end
    |> Repo.transaction()
    |> complete_stage_claim_acquisition(staged)
  end

  defp acquire_stage_claim(_staged, _reservation), do: {:error, :invalid_snapshot_stage_claim}

  defp create_or_classify_stage_claim(
         %StorageReservation{status: "active"} = reservation,
         staged,
         reservation_lease_token,
         claim_attrs
       ) do
    with :ok <- validate_preflight_stage_reservation(reservation, staged, reservation_lease_token) do
      create_or_classify_active_stage_claim(reservation, claim_attrs)
    end
  end

  defp create_or_classify_stage_claim(
         %StorageReservation{status: "committed"} = reservation,
         staged,
         reservation_lease_token,
         claim_attrs
       ) do
    claim = lock_publication_claim(claim_attrs.object_prefix)

    with :ok <- validate_stage_reservation(reservation, staged, reservation_lease_token),
         :ok <- validate_claim_reservation_binding(claim, reservation) do
      case classify_stage_claim(claim, claim_attrs.inventory_digest) do
        {:ok, claim, :published} -> {:ok, claim, :published}
        {:ok, _claim, _state} -> {:error, :snapshot_object_committed_reservation_claim_state_conflict}
        {:error, _reason} = error -> error
      end
    end
  end

  defp create_or_classify_stage_claim(_reservation, _staged, _reservation_lease_token, _claim_attrs),
    do: {:error, :snapshot_object_stage_reservation_binding_invalid}

  defp create_or_classify_active_stage_claim(reservation, claim_attrs) do
    inserted_count = insert_stage_claim(reservation, claim_attrs)
    claim = lock_publication_claim(claim_attrs.object_prefix)

    with :ok <- validate_claim_reservation_binding(claim, reservation) do
      resolve_stage_claim(inserted_count, claim, claim_attrs.inventory_digest)
    end
  end

  defp insert_stage_claim(reservation, claim_attrs) do
    {inserted_count, _rows} =
      Repo.insert_all(
        SnapshotObjectPublicationClaim,
        [
          %{
            object_prefix: claim_attrs.object_prefix,
            claim_token: claim_attrs.claim_token,
            inventory_digest: claim_attrs.inventory_digest,
            storage_reservation_id_snapshot: reservation.id,
            storage_reservation_lease_token: reservation.lease_token,
            status: "staging",
            lease_expires_at: claim_attrs.lease_expires_at,
            inserted_at: claim_attrs.now,
            updated_at: claim_attrs.now
          }
        ],
        on_conflict: :nothing,
        conflict_target: [:object_prefix]
      )

    inserted_count
  end

  defp resolve_stage_claim(1, claim, _inventory_digest), do: {:ok, claim, :write}

  defp resolve_stage_claim(_inserted_count, claim, inventory_digest), do: classify_stage_claim(claim, inventory_digest)

  defp complete_stage_claim_acquisition({:ok, {:ok, claim, action}}, staged) do
    claimed_staged =
      Map.merge(staged, %{
        publication_claim_token: claim.claim_token,
        storage_reservation_id: claim.storage_reservation_id_snapshot,
        storage_reservation_lease_token: claim.storage_reservation_lease_token
      })

    {:ok, claimed_staged, action}
  end

  defp complete_stage_claim_acquisition({:ok, {:error, reason}}, _staged), do: {:error, reason}

  defp complete_stage_claim_acquisition({:error, reason}, _staged), do: {:error, {:snapshot_stage_claim_failed, reason}}

  defp classify_stage_claim(
         %SnapshotObjectPublicationClaim{inventory_digest: inventory_digest, status: "staged"} = claim,
         inventory_digest
       ), do: {:ok, claim, :staged}

  defp classify_stage_claim(
         %SnapshotObjectPublicationClaim{inventory_digest: inventory_digest, status: "published"} = claim,
         inventory_digest
       ), do: {:ok, claim, :published}

  defp classify_stage_claim(
         %SnapshotObjectPublicationClaim{inventory_digest: inventory_digest, status: "publishing"} = claim,
         inventory_digest
       ), do: {:ok, claim, :publishing}

  defp classify_stage_claim(%SnapshotObjectPublicationClaim{status: "poisoned"}, _inventory_digest),
    do: {:error, :snapshot_object_namespace_cleanup_handed_off}

  defp classify_stage_claim(
         %SnapshotObjectPublicationClaim{
           inventory_digest: inventory_digest,
           status: "staging",
           lease_expires_at: lease_expires_at
         },
         inventory_digest
       ) do
    if lease_active?(lease_expires_at, TimeHelpers.now()),
      do: {:error, :snapshot_object_namespace_in_progress},
      else: {:error, :snapshot_object_stage_reconciliation_required}
  end

  defp classify_stage_claim(%SnapshotObjectPublicationClaim{}, _inventory_digest),
    do: {:error, :snapshot_object_namespace_inventory_conflict}

  defp classify_stage_claim(nil, _inventory_digest), do: {:error, :snapshot_object_stage_claim_missing}

  defp stage_claimed_object_set(staged, action, _payload, _on_progress)
       when action in [:staged, :publishing, :published] do
    case verify_publishable_object_set(staged) do
      {:ok, _manifest, _manifest_descriptor, _stored, publication_state}
      when publication_state in [:staged, :published] ->
        {:ok, staged}

      {:error, reason} ->
        poison_then_stage_failure(staged, {:snapshot_object_reused_stage_invalid, reason})
    end
  end

  defp stage_claimed_object_set(staged, :write, payload, on_progress) do
    result = stage_object_set(staged, payload, on_progress)

    case result do
      {:ok, staged} ->
        case transition_publication_claim(staged, "staging", "staged") do
          :ok ->
            {:ok, staged}

          {:error, reason} ->
            poison_then_stage_failure(staged, {:snapshot_stage_claim_finalize_failed, reason})
        end

      {:error, {:snapshot_object_cleanup_not_persisted, _original_reason, _cleanup_reason} = reason} ->
        poison_then_terminal_failure(staged, :stage, reason)

      {:error, reason} ->
        poison_then_stage_failure(staged, reason)
    end
  end

  defp acquire_publication_claim(%{object_prefix: object_prefix, publication_claim_token: claim_token} = staged) do
    inventory_digest = publication_inventory_digest(staged)
    now = TimeHelpers.now()

    fn ->
      object_prefix
      |> lock_publication_claim()
      |> publication_claim_action(claim_token, inventory_digest, now)
    end
    |> Repo.transaction()
    |> unwrap_claim_result(:snapshot_object_publication_claim_failed)
    |> complete_publication_claim_acquisition(staged)
  end

  defp acquire_publication_claim(_staged), do: {:error, :invalid_snapshot_publication_claim}

  defp publication_claim_action(
         %SnapshotObjectPublicationClaim{
           claim_token: claim_token,
           inventory_digest: inventory_digest,
           storage_reservation_id_snapshot: reservation_id,
           storage_reservation_lease_token: reservation_lease_token,
           status: "staged"
         } = claim,
         claim_token,
         inventory_digest,
         now
       )
       when is_integer(reservation_id) and is_binary(reservation_lease_token) do
    claim
    |> SnapshotObjectPublicationClaim.status_changeset(
      "publishing",
      claim_lease_expires_at(now)
    )
    |> Repo.update()
    |> publication_claim_update_result()
  end

  defp publication_claim_action(
         %SnapshotObjectPublicationClaim{
           claim_token: claim_token,
           inventory_digest: inventory_digest,
           status: "published"
         },
         claim_token,
         inventory_digest,
         _now
       ), do: {:ok, :published}

  defp publication_claim_action(
         %SnapshotObjectPublicationClaim{
           claim_token: claim_token,
           inventory_digest: inventory_digest,
           status: "publishing"
         },
         claim_token,
         inventory_digest,
         _now
       ), do: {:ok, :recover}

  defp publication_claim_action(
         %SnapshotObjectPublicationClaim{status: "poisoned"},
         _claim_token,
         _inventory_digest,
         _now
       ), do: {:error, :snapshot_object_namespace_cleanup_handed_off}

  defp publication_claim_action(%SnapshotObjectPublicationClaim{}, _claim_token, _inventory_digest, _now),
    do: {:error, :snapshot_object_publication_claim_conflict}

  defp publication_claim_action(nil, _claim_token, _inventory_digest, _now),
    do: {:error, :snapshot_object_publication_claim_missing}

  defp publication_claim_update_result({:ok, _claim}), do: {:ok, :claimed}
  defp publication_claim_update_result({:error, changeset}), do: {:error, changeset}

  defp complete_publication_claim_acquisition({:ok, :recover}, staged), do: recover_publication_claim(staged)

  defp complete_publication_claim_acquisition(result, _staged), do: result

  defp recover_publication_claim(staged) do
    case verify_publishable_object_set(staged) do
      {:ok, _manifest, _manifest_descriptor, _stored, :published} ->
        case transition_publication_claim(staged, "publishing", "published") do
          :ok -> {:ok, :published}
          {:error, _reason} = error -> error
        end

      {:ok, _manifest, _manifest_descriptor, _stored, :staged} ->
        publication_recovery_wait_state(staged)

      {:error, reason} ->
        {:error, {:snapshot_object_publication_reconciliation_required, reason}}
    end
  end

  defp publication_recovery_wait_state(staged) do
    fn ->
      with {:ok, claim} <- matching_publication_claim(staged) do
        publication_recovery_state(claim)
      end
    end
    |> Repo.transaction()
    |> unwrap_claim_result(:snapshot_object_publication_claim_observation_failed)
  end

  defp publication_recovery_state(%SnapshotObjectPublicationClaim{
         status: "publishing",
         lease_expires_at: lease_expires_at
       }) do
    if lease_active?(lease_expires_at, TimeHelpers.now()),
      do: {:error, :snapshot_object_publication_in_progress},
      else: {:error, :snapshot_object_publication_reconciliation_required}
  end

  defp publication_recovery_state(%SnapshotObjectPublicationClaim{}),
    do: {:error, :snapshot_object_publication_claim_state_conflict}

  defp publish_claimed_object_set(staged, before_publish, :published, on_progress) do
    case publish_object_set(staged, before_publish, on_progress) do
      {:ok, stored} -> cleanup_published_staging(staged, stored)
      {:error, reason} -> {:error, {:published_snapshot_object_set_invalid, reason}}
    end
  end

  defp publish_claimed_object_set(staged, before_publish, :claimed, on_progress) do
    case publish_object_set(staged, before_publish, on_progress) do
      {:ok, stored} ->
        case transition_publication_claim(staged, "publishing", "published") do
          :ok -> cleanup_published_staging(staged, stored)
          {:error, reason} -> {:error, {:snapshot_publication_claim_finalize_failed, reason}}
        end

      {:error, {:snapshot_publish_authorization_failed, reason}} ->
        poison_then_publish_failure(staged, :authorization, reason)

      {:error, {:snapshot_object_cleanup_not_persisted, _original_reason, _cleanup_reason} = reason} ->
        poison_then_terminal_failure(staged, :publish, reason)

      {:error, reason} ->
        poison_then_publish_failure(staged, :publish, reason)
    end
  end

  defp poison_then_stage_failure(staged, reason) do
    case poison_publication_claim(staged) do
      :ok -> return_stage_failure(staged, reason)
      {:error, poison_error} -> terminal_unowned_cleanup_failure(:stage, {reason, poison_error})
    end
  end

  defp poison_then_publish_failure(staged, phase, reason) do
    case poison_publication_claim(staged) do
      :ok -> return_publish_failure(staged, phase, reason)
      {:error, poison_error} -> terminal_unowned_cleanup_failure(phase, {reason, poison_error})
    end
  end

  defp poison_then_terminal_failure(staged, phase, reason) do
    case poison_publication_claim(staged) do
      :ok -> terminal_unowned_cleanup_failure(phase, reason)
      {:error, poison_error} -> terminal_unowned_cleanup_failure(phase, {reason, poison_error})
    end
  end

  defp transition_publication_claim(staged, expected_status, next_status) do
    fn ->
      with {:ok, claim} <- matching_publication_claim(staged),
           true <- claim.status in [expected_status, next_status],
           {:ok, _claim} <-
             claim
             |> SnapshotObjectPublicationClaim.status_changeset(next_status)
             |> Repo.update() do
        :ok
      else
        false -> {:error, :snapshot_object_publication_claim_state_conflict}
        {:error, _reason} = error -> error
      end
    end
    |> Repo.transaction()
    |> unwrap_claim_result(:snapshot_object_publication_claim_transition_failed)
  end

  defp poison_publication_claim(staged) do
    fn ->
      with {:ok, claim} <- matching_publication_claim(staged) do
        poison_matching_publication_claim(claim)
      end
    end
    |> Repo.transaction()
    |> unwrap_claim_result(:snapshot_object_publication_claim_poison_failed)
  end

  defp poison_matching_publication_claim(%SnapshotObjectPublicationClaim{status: "poisoned"}), do: :ok

  defp poison_matching_publication_claim(%SnapshotObjectPublicationClaim{status: "published"}),
    do: {:error, :cannot_poison_published_snapshot_namespace}

  defp poison_matching_publication_claim(%SnapshotObjectPublicationClaim{} = claim) do
    claim
    |> SnapshotObjectPublicationClaim.status_changeset("poisoned")
    |> Repo.update()
    |> poison_publication_claim_update_result()
  end

  defp poison_publication_claim_update_result({:ok, _claim}), do: :ok
  defp poison_publication_claim_update_result({:error, changeset}), do: {:error, changeset}

  defp matching_publication_claim(%{object_prefix: object_prefix, publication_claim_token: claim_token} = staged) do
    inventory_digest = publication_inventory_digest(staged)

    case lock_publication_claim(object_prefix) do
      %SnapshotObjectPublicationClaim{
        claim_token: ^claim_token,
        inventory_digest: ^inventory_digest
      } = claim ->
        {:ok, claim}

      _claim ->
        {:error, :snapshot_object_publication_claim_conflict}
    end
  end

  defp matching_publication_claim(_staged), do: {:error, :invalid_snapshot_publication_claim}

  defp lock_publication_claim(object_prefix) do
    Repo.one(
      from(claim in SnapshotObjectPublicationClaim,
        where: claim.object_prefix == ^object_prefix,
        lock: "FOR UPDATE"
      )
    )
  end

  defp unwrap_claim_result({:ok, {:ok, result}}, _error_tag), do: {:ok, result}
  defp unwrap_claim_result({:ok, :ok}, _error_tag), do: :ok
  defp unwrap_claim_result({:ok, {:error, reason}}, _error_tag), do: {:error, reason}
  defp unwrap_claim_result({:error, reason}, error_tag), do: {:error, {error_tag, reason}}

  defp publication_inventory_digest(staged) when is_map(staged) do
    SnapshotObjectPublicationClaim.inventory_digest(staged)
  end

  defp claim_lease_expires_at(%DateTime{} = now), do: DateTime.add(now, @publication_claim_lease_seconds, :second)

  defp lease_active?(%DateTime{} = lease_expires_at, %DateTime{} = now), do: DateTime.after?(lease_expires_at, now)

  defp lease_active?(_lease_expires_at, _now), do: false

  defp cleanup_inventory_digest(storage_keys) do
    storage_keys
    |> Enum.sort()
    |> Enum.map_join(fn storage_key -> "#{byte_size(storage_key)}:#{storage_key}" end)
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp stage_object_set(staged, payload, on_progress) do
    result =
      write_staged_object_set(
        staged.staging_prefix,
        payload.project_descriptor,
        payload.project_json,
        payload.blobs,
        payload.source_keys,
        payload.manifest_descriptor,
        payload.manifest_json,
        on_progress
      )

    case result do
      :ok ->
        {:ok, staged}

      {:error, _reason} = error ->
        error

      invalid ->
        {:error, {:unexpected_snapshot_stage_result, invalid}}
    end
  end

  defp write_staged_object_set(
         staging_prefix,
         project_descriptor,
         project_json,
         blobs,
         source_keys,
         manifest_descriptor,
         manifest_json,
         on_progress
       ) do
    with :ok <- stage_project(staging_prefix, project_descriptor, project_json),
         :ok <- invoke_progress(on_progress, project_descriptor["size_bytes"]),
         {:ok, completed_bytes} <-
           stage_blobs(staging_prefix, blobs, source_keys, on_progress, project_descriptor["size_bytes"]),
         :ok <- invoke_progress(on_progress, completed_bytes),
         :ok <- stage_manifest(staging_prefix, manifest_descriptor, manifest_json) do
      invoke_progress(on_progress, completed_bytes + manifest_descriptor["size_bytes"])
    end
  rescue
    exception ->
      {:error, {:snapshot_object_stage_raised, exception.__struct__, Exception.message(exception)}}
  catch
    kind, reason ->
      {:error, {:snapshot_object_stage_caught, kind, reason}}
  end

  defp staged_object_set(project_id, token, staging_prefix, ready_prefix, manifest, manifest_descriptor, limits) do
    {:ok, stored} = stored_object_set(ready_prefix, manifest, manifest_descriptor)

    relative_paths =
      Enum.map(manifest["objects"], & &1["path"]) ++
        [SnapshotObjectFormat.manifest_path()]

    cleanup = %{
      project_id: project_id,
      token: token,
      staging_prefix: staging_prefix,
      ready_prefix: ready_prefix,
      storage_keys:
        Enum.flat_map([staging_prefix, ready_prefix], fn prefix ->
          Enum.map(relative_paths, &object_key(prefix, &1))
        end)
    }

    Map.merge(stored, %{
      project_id: project_id,
      token: token,
      limits: limits,
      lifecycle_state: "staged",
      staging_prefix: staging_prefix,
      manifest_staging_key: object_key(staging_prefix, SnapshotObjectFormat.manifest_path()),
      project_staging_key: object_key(staging_prefix, SnapshotObjectFormat.project_path()),
      cleanup: cleanup
    })
  end

  defp publish_object_set(staged, before_publish, on_progress) do
    with {:ok, manifest, manifest_descriptor, stored, publication_state} <-
           verify_publishable_object_set(staged) do
      case publication_state do
        :published -> {:ok, stored}
        :staged -> publish_authorized(staged, manifest, manifest_descriptor, stored, before_publish, on_progress)
      end
    end
  rescue
    exception ->
      {:error, {:snapshot_object_publish_raised, exception.__struct__, Exception.message(exception)}}
  catch
    kind, reason ->
      {:error, {:snapshot_object_publish_caught, kind, reason}}
  end

  defp verify_publishable_object_set(
         %{
           project_id: project_id,
           token: token,
           limits: limits,
           staging_prefix: staging_prefix,
           object_prefix: ready_prefix,
           manifest_staging_key: manifest_staging_key,
           manifest_storage_key: manifest_storage_key,
           manifest_size_bytes: manifest_size_bytes
         } = staged
       ) do
    with :ok <-
           validate_staged_shape(
             project_id,
             token,
             limits,
             staging_prefix,
             ready_prefix,
             manifest_staging_key,
             manifest_storage_key,
             manifest_size_bytes
           ),
         {:ok, manifest_descriptor, max_manifest_bytes} <-
           validate_staged_header(
             staged,
             project_id,
             token,
             limits,
             staging_prefix,
             ready_prefix,
             manifest_staging_key,
             manifest_storage_key
           ),
         {:ok, manifest, publication_state} <- load_publication_manifest(staged, max_manifest_bytes),
         :ok <- verify_publication_inventory(staged, manifest, publication_state),
         {:ok, stored} <- verify_staged_measurements(staged, manifest, manifest_descriptor) do
      {:ok, manifest, manifest_descriptor, stored, publication_state}
    end
  end

  defp verify_publishable_object_set(_staged), do: {:error, :invalid_staged_snapshot_object_set}

  defp validate_staged_shape(
         project_id,
         token,
         limits,
         staging_prefix,
         ready_prefix,
         manifest_staging_key,
         manifest_storage_key,
         manifest_size_bytes
       ) do
    checks = [
      is_integer(project_id),
      project_id > 0,
      is_binary(token),
      is_map(limits),
      is_binary(staging_prefix),
      is_binary(ready_prefix),
      is_binary(manifest_staging_key),
      is_binary(manifest_storage_key),
      is_integer(manifest_size_bytes),
      manifest_size_bytes >= 0
    ]

    if Enum.all?(checks), do: :ok, else: {:error, :invalid_staged_snapshot_object_set}
  end

  defp validate_staged_header(
         staged,
         project_id,
         token,
         limits,
         staging_prefix,
         ready_prefix,
         manifest_staging_key,
         manifest_storage_key
       ) do
    expected_staging_prefix = staging_prefix(project_id, token)
    expected_ready_prefix = ready_prefix(project_id, token)
    expected_staging_manifest = object_key(expected_staging_prefix, SnapshotObjectFormat.manifest_path())
    expected_ready_manifest = object_key(expected_ready_prefix, SnapshotObjectFormat.manifest_path())
    manifest_descriptor = manifest_descriptor_from_staged(staged)

    with :ok <- validate_token(token),
         :ok <- validate_staged_limits(limits),
         {:ok, max_manifest_bytes} <- Map.fetch(limits, :max_manifest_bytes),
         :ok <-
           validate_staged_prefixes(
             {staging_prefix, ready_prefix, manifest_staging_key, manifest_storage_key},
             {expected_staging_prefix, expected_ready_prefix, expected_staging_manifest, expected_ready_manifest}
           ),
         :ok <- validate_sha256(staged.manifest_checksum) do
      {:ok, manifest_descriptor, max_manifest_bytes}
    end
  end

  defp load_publication_manifest(staged, max_manifest_bytes) do
    case Storage.stat(staged.manifest_storage_key) do
      {:ok, _stat} ->
        staged
        |> load_manifest(staged.manifest_storage_key, max_manifest_bytes)
        |> publication_manifest_result(:published)

      {:error, reason} ->
        if missing_storage_object?(reason) do
          staged
          |> load_manifest(staged.manifest_staging_key, max_manifest_bytes)
          |> publication_manifest_result(:staged)
        else
          {:error, reason}
        end
    end
  end

  defp publication_manifest_result({:ok, manifest}, state), do: {:ok, manifest, state}
  defp publication_manifest_result({:error, _reason} = error, _state), do: error

  defp load_manifest(staged, storage_key, max_manifest_bytes) do
    with {:ok, manifest_json} <-
           read_verified_json_bytes(
             storage_key,
             staged.manifest_size_bytes,
             staged.manifest_checksum,
             max_manifest_bytes
           ),
         {:ok, manifest} <- decode_json(manifest_json, SnapshotObjectFormat.manifest_path()),
         :ok <- SnapshotObjectFormat.validate_manifest(manifest, Map.to_list(staged.limits)) do
      {:ok, manifest}
    end
  end

  defp verify_publication_inventory(staged, manifest, :published) do
    verify_object_inventory(staged.object_prefix, manifest["objects"])
  end

  defp verify_publication_inventory(staged, manifest, :staged) do
    verify_object_inventory(staged.staging_prefix, manifest["objects"])
  end

  defp verify_staged_measurements(staged, manifest, manifest_descriptor) do
    expected =
      staged_object_set(
        staged.project_id,
        staged.token,
        staged.staging_prefix,
        staged.object_prefix,
        manifest,
        manifest_descriptor,
        staged.limits
      )

    with :ok <- validate_exact_staged_object_set(staged, expected) do
      stored_object_set(staged.object_prefix, manifest, manifest_descriptor)
    end
  end

  defp validate_staged_limits(limits) do
    with :ok <- SnapshotObjectFormat.validate_limits(limits),
         true <- limits == SnapshotObjectFormat.limits() do
      :ok
    else
      false -> {:error, :staged_snapshot_object_limits_changed}
      {:error, _reason} -> {:error, :invalid_staged_snapshot_object_limits}
    end
  end

  defp validate_staged_prefixes(actual, expected) do
    if actual == expected, do: :ok, else: {:error, :invalid_staged_snapshot_object_set}
  end

  defp validate_exact_staged_object_set(staged, expected) do
    with claim_token when is_binary(claim_token) <- Map.get(staged, :publication_claim_token),
         {:ok, canonical_claim_token} <- Ecto.UUID.cast(claim_token),
         true <- canonical_claim_token == claim_token,
         reservation_id when is_integer(reservation_id) and reservation_id > 0 <-
           Map.get(staged, :storage_reservation_id),
         reservation_lease_token when is_binary(reservation_lease_token) <-
           Map.get(staged, :storage_reservation_lease_token),
         {:ok, canonical_reservation_lease_token} <- Ecto.UUID.cast(reservation_lease_token),
         true <- canonical_reservation_lease_token == reservation_lease_token,
         true <-
           Map.drop(staged, [
             :publication_claim_token,
             :storage_reservation_id,
             :storage_reservation_lease_token
           ]) == expected do
      :ok
    else
      _invalid -> {:error, :invalid_staged_snapshot_object_set}
    end
  end

  defp manifest_descriptor_from_staged(staged) do
    %{
      "kind" => "manifest",
      "path" => SnapshotObjectFormat.manifest_path(),
      "sha256" => staged.manifest_checksum,
      "size_bytes" => staged.manifest_size_bytes,
      "content_type" => "application/json"
    }
  end

  defp publish_authorized(staged, manifest, manifest_descriptor, stored, before_publish, on_progress) do
    case invoke_before_publish(before_publish, staged) do
      {:ok, reservation} ->
        with :ok <- validate_claimed_publication_reservation(staged, reservation),
             {:ok, completed_bytes} <-
               finalize_payload(staged.staging_prefix, staged.object_prefix, manifest["objects"], on_progress),
             :ok <- invoke_progress(on_progress, completed_bytes),
             :ok <- finalize_manifest(staged.staging_prefix, staged.object_prefix, manifest_descriptor),
             :ok <- invoke_progress(on_progress, completed_bytes + manifest_descriptor["size_bytes"]) do
          {:ok, stored}
        end

      {:error, reason} ->
        {:error, {:snapshot_publish_authorization_failed, reason}}
    end
  end

  defp return_stage_failure(staged, reason) do
    case persist_failure_cleanup(staged) do
      {:ok, cleanup} ->
        {:error, {:snapshot_object_stage_failed, reason, cleanup}}

      {:error, persistence_error, cleanup} ->
        cleanup_not_persisted(:stage, reason, persistence_error, cleanup)
    end
  end

  defp return_publish_failure(staged, :authorization, reason) do
    case persist_failure_cleanup(staged) do
      {:ok, cleanup} ->
        {:error, {:snapshot_publish_authorization_failed, reason, cleanup}}

      {:error, persistence_error, cleanup} ->
        cleanup_not_persisted(:authorization, reason, persistence_error, cleanup)
    end
  end

  defp return_publish_failure(staged, :publish, reason) do
    case persist_failure_cleanup(staged) do
      {:ok, cleanup} ->
        {:error, {:snapshot_object_publish_failed, reason, cleanup}}

      {:error, persistence_error, cleanup} ->
        cleanup_not_persisted(:publish, reason, persistence_error, cleanup)
    end
  end

  defp persist_failure_cleanup(staged) do
    with {:ok, cleanup} <- validate_cleanup_scope(staged),
         {:ok, cleanup_request_id} <- persist_cleanup_keys(cleanup.storage_keys) do
      {:ok, Map.put(cleanup, :cleanup_request_id, cleanup_request_id)}
    else
      {:error, reason} ->
        cleanup = if is_map(staged), do: Map.get(staged, :cleanup)
        {:error, reason, cleanup}
    end
  end

  defp cleanup_not_persisted(phase, reason, persistence_error, cleanup) do
    {:error,
     {:snapshot_object_cleanup_not_persisted,
      %{
        phase: phase,
        reason: reason,
        persistence_error: persistence_error,
        cleanup: cleanup
      }}}
  end

  defp terminal_unowned_cleanup_failure(phase, reason) do
    {:error,
     {:snapshot_object_cleanup_not_persisted,
      %{
        phase: phase,
        reason: reason,
        persistence_error: :temporary_object_has_no_durable_cleanup_owner,
        cleanup: nil
      }}}
  end

  defp cleanup_published_staging(staged, stored) do
    case validate_cleanup_scope(staged) do
      {:ok, cleanup} ->
        staging_keys = storage_keys_for_prefix(cleanup.storage_keys, cleanup.staging_prefix)

        case delete_cleanup_keys(staging_keys) do
          :ok ->
            {:ok, Map.put(stored, :staging_cleanup_request_id, nil)}

          {:error, failed_keys, delete_error} ->
            persist_staging_cleanup(stored, cleanup.staging_prefix, failed_keys, delete_error)
        end

      {:error, reason} ->
        staging_cleanup_not_persisted(nil, reason, staging_cleanup_scope(staged, []))
    end
  end

  defp persist_staging_cleanup(stored, staging_prefix, failed_keys, delete_error) do
    case persist_cleanup_keys(failed_keys) do
      {:ok, cleanup_request_id} ->
        {:ok, Map.put(stored, :staging_cleanup_request_id, cleanup_request_id)}

      {:error, persistence_error} ->
        staging_cleanup_not_persisted(
          delete_error,
          persistence_error,
          %{staging_prefix: staging_prefix, storage_keys: failed_keys}
        )
    end
  end

  defp staging_cleanup_not_persisted(delete_error, persistence_error, cleanup) do
    {:error,
     {:snapshot_staging_cleanup_not_persisted,
      %{
        delete_error: delete_error,
        persistence_error: persistence_error,
        cleanup: cleanup,
        staging_cleanup_request_id: nil
      }}}
  end

  defp staging_cleanup_scope(%{staging_prefix: staging_prefix}, storage_keys) when is_binary(staging_prefix) do
    %{staging_prefix: staging_prefix, storage_keys: storage_keys}
  end

  defp staging_cleanup_scope(_staged, storage_keys), do: %{staging_prefix: nil, storage_keys: storage_keys}

  defp validate_cleanup_scope(%{
         project_id: project_id,
         token: token,
         staging_prefix: staging_prefix,
         object_prefix: ready_prefix,
         object_count: object_count,
         cleanup:
           %{
             project_id: cleanup_project_id,
             token: cleanup_token,
             staging_prefix: cleanup_staging_prefix,
             ready_prefix: cleanup_ready_prefix,
             storage_keys: storage_keys
           } = cleanup
       })
       when is_integer(project_id) and project_id > 0 and is_binary(token) and is_binary(staging_prefix) and
              is_binary(ready_prefix) and is_integer(object_count) and object_count > 0 and is_list(storage_keys) do
    expected_staging_prefix = staging_prefix(project_id, token)
    expected_ready_prefix = ready_prefix(project_id, token)
    staging_paths = cleanup_paths_for_prefix(storage_keys, staging_prefix)
    ready_paths = cleanup_paths_for_prefix(storage_keys, ready_prefix)

    identity = {project_id, token, staging_prefix, ready_prefix}
    cleanup_identity = {cleanup_project_id, cleanup_token, cleanup_staging_prefix, cleanup_ready_prefix}
    expected_identity = {project_id, token, expected_staging_prefix, expected_ready_prefix}

    with :ok <- validate_token(token),
         :ok <- validate_cleanup_identity(identity, cleanup_identity, expected_identity),
         :ok <-
           validate_cleanup_inventory(
             storage_keys,
             staging_paths,
             ready_paths,
             object_count,
             staging_prefix,
             ready_prefix
           ) do
      {:ok, cleanup}
    else
      _invalid -> {:error, :invalid_snapshot_cleanup_scope}
    end
  end

  defp validate_cleanup_scope(_staged), do: {:error, :invalid_snapshot_cleanup_scope}

  defp validate_cleanup_identity(identity, identity, identity), do: :ok

  defp validate_cleanup_identity(_identity, _cleanup_identity, _expected_identity),
    do: {:error, :invalid_snapshot_cleanup_scope}

  defp validate_cleanup_inventory(storage_keys, staging_paths, ready_paths, object_count, staging_prefix, ready_prefix) do
    with true <- length(storage_keys) == length(Enum.uniq(storage_keys)),
         true <- length(staging_paths) == object_count,
         true <- length(ready_paths) == object_count,
         true <- MapSet.new(staging_paths) == MapSet.new(ready_paths),
         true <- cleanup_keys_within_prefixes?(storage_keys, staging_prefix, ready_prefix),
         true <- required_cleanup_paths?(staging_paths),
         true <- Enum.all?(staging_paths, &valid_cleanup_relative_path?/1) do
      :ok
    else
      false -> {:error, :invalid_snapshot_cleanup_scope}
    end
  end

  defp cleanup_keys_within_prefixes?(storage_keys, staging_prefix, ready_prefix) do
    Enum.all?(storage_keys, fn key ->
      cleanup_key_in_prefix?(key, staging_prefix) or cleanup_key_in_prefix?(key, ready_prefix)
    end)
  end

  defp required_cleanup_paths?(paths), do: "manifest.json" in paths and "project.json" in paths

  defp storage_keys_for_prefix(storage_keys, prefix) do
    Enum.filter(storage_keys, &cleanup_key_in_prefix?(&1, prefix))
  end

  defp cleanup_paths_for_prefix(storage_keys, prefix) do
    Enum.flat_map(storage_keys, fn storage_key ->
      if cleanup_key_in_prefix?(storage_key, prefix),
        do: [String.replace_prefix(storage_key, prefix <> "/", "")],
        else: []
    end)
  end

  defp cleanup_key_in_prefix?(storage_key, prefix) when is_binary(storage_key) and is_binary(prefix) do
    String.starts_with?(storage_key, prefix <> "/")
  end

  defp cleanup_key_in_prefix?(_storage_key, _prefix), do: false

  defp valid_cleanup_relative_path?(filename) when filename in ["manifest.json", "project.json"], do: true

  defp valid_cleanup_relative_path?("blobs/" <> filename), do: Regex.match?(@blob_filename_regex, filename)

  defp valid_cleanup_relative_path?(_path), do: false

  defp delete_cleanup_keys(storage_keys) do
    delete_fun = cleanup_callback(:delete_fun, &StorageCompensation.delete_storage_keys/1)

    case delete_fun.(storage_keys) do
      :ok ->
        :ok

      {:error, failed_keys} when is_list(failed_keys) ->
        {:error, normalize_failed_cleanup_keys(failed_keys, storage_keys), :storage_delete_failed}

      {:error, reason} ->
        {:error, storage_keys, reason}

      invalid ->
        {:error, storage_keys, {:unexpected_cleanup_delete_result, invalid}}
    end
  rescue
    exception ->
      {:error, storage_keys, {:cleanup_delete_raised, exception.__struct__, Exception.message(exception)}}
  catch
    kind, reason ->
      {:error, storage_keys, {:cleanup_delete_caught, kind, reason}}
  end

  defp normalize_failed_cleanup_keys(failed_keys, storage_keys) do
    failed_keys = Enum.uniq(failed_keys)
    storage_key_set = MapSet.new(storage_keys)

    if failed_keys != [] and Enum.all?(failed_keys, &MapSet.member?(storage_key_set, &1)),
      do: failed_keys,
      else: storage_keys
  end

  defp persist_cleanup_keys(storage_keys) do
    persist_fun = cleanup_callback(:persist_fun, &StorageCompensation.persist_cleanup_request/1)

    case persist_fun.(storage_keys) do
      {:ok, %{id: cleanup_request_id}} when is_integer(cleanup_request_id) and cleanup_request_id > 0 ->
        {:ok, cleanup_request_id}

      {:error, reason} ->
        {:error, reason}

      invalid ->
        {:error, {:unexpected_cleanup_persistence_result, invalid}}
    end
  rescue
    exception ->
      {:error, {:cleanup_persistence_raised, exception.__struct__, Exception.message(exception)}}
  catch
    kind, reason ->
      {:error, {:cleanup_persistence_caught, kind, reason}}
  end

  defp cleanup_callback(key, default) do
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

  defp invoke_before_stage(before_stage, staged) do
    case before_stage.(staged) do
      {:ok, %StorageReservation{} = reservation} -> {:ok, reservation}
      {:error, reason} -> {:error, reason}
      invalid -> {:error, {:invalid_snapshot_stage_authorization_result, invalid}}
    end
  rescue
    exception ->
      {:error, {:snapshot_stage_authorizer_raised, exception.__struct__, Exception.message(exception)}}
  catch
    kind, reason -> {:error, {:snapshot_stage_authorizer_caught, kind, reason}}
  end

  defp invoke_before_publish(before_publish, staged) do
    case before_publish.(staged) do
      {:ok, %StorageReservation{} = reservation} -> {:ok, reservation}
      {:error, reason} -> {:error, reason}
      invalid -> {:error, {:invalid_snapshot_publish_authorization_result, invalid}}
    end
  rescue
    exception ->
      {:error, {:snapshot_publish_authorizer_raised, exception.__struct__, Exception.message(exception)}}
  catch
    kind, reason -> {:error, {:snapshot_publish_authorizer_caught, kind, reason}}
  end

  defp missing_storage_object?(:enoent), do: true
  defp missing_storage_object?({:http_error, 404, _response}), do: true
  defp missing_storage_object?(_reason), do: false

  defp normalize_project_snapshot(project_snapshot) when is_map(project_snapshot) do
    with {:ok, json} <- Jason.encode(project_snapshot),
         {:ok, normalized} <- Jason.decode(json) do
      {:ok, normalized}
    else
      {:error, _reason} -> {:error, :invalid_project_object}
    end
  end

  defp normalize_project_snapshot(_project_snapshot), do: {:error, :invalid_project_object}

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

  defp validate_prepared_capture(
         project_id,
         %{project_json: project_json, manifest_json: manifest_json, source_keys: source_keys} = prepared,
         opts
       )
       when is_binary(project_json) and is_binary(manifest_json) and is_map(source_keys) do
    with {:ok, project} <- decode_json(project_json, SnapshotObjectFormat.project_path()),
         :ok <- SnapshotObjectFormat.validate_project(project),
         {:ok, manifest} <- decode_json(manifest_json, SnapshotObjectFormat.manifest_path()),
         :ok <- SnapshotObjectFormat.validate_manifest(manifest, opts),
         project_descriptor = manifest["project"],
         :ok <- validate_prepared_descriptor(project_descriptor, project_json, "project"),
         manifest_descriptor = prepared_manifest_descriptor(manifest_json),
         :ok <-
           validate_prepared_sources(
             project_id,
             manifest["objects"],
             source_keys,
             Keyword.get(opts, :source_key_mode, :protected_blob)
           ),
         expected = prepared_capture(project_json, manifest_json, manifest, manifest_descriptor, source_keys),
         true <- Map.take(prepared, Map.keys(expected)) == expected do
      {:ok,
       %{
         project: project,
         manifest: manifest,
         project_descriptor: project_descriptor,
         manifest_descriptor: manifest_descriptor,
         blobs: Enum.filter(manifest["objects"], &(&1["kind"] == "asset_blob"))
       }}
    else
      false -> {:error, :prepared_snapshot_capture_mismatch}
      {:error, _reason} = error -> error
      _invalid -> {:error, :invalid_prepared_snapshot_capture}
    end
  end

  defp validate_prepared_capture(_project_id, _prepared, _opts), do: {:error, :invalid_prepared_snapshot_capture}

  defp validate_prepared_descriptor(
         %{
           "kind" => "project",
           "path" => "project.json",
           "sha256" => checksum,
           "size_bytes" => size_bytes,
           "content_type" => "application/json"
         },
         bytes,
         _label
       ) do
    if size_bytes == byte_size(bytes) and checksum == sha256(bytes),
      do: :ok,
      else: {:error, :prepared_snapshot_project_mismatch}
  end

  defp validate_prepared_descriptor(_descriptor, _bytes, _label), do: {:error, :prepared_snapshot_project_mismatch}

  defp prepared_manifest_descriptor(manifest_json) do
    %{
      "kind" => "manifest",
      "path" => SnapshotObjectFormat.manifest_path(),
      "sha256" => sha256(manifest_json),
      "size_bytes" => byte_size(manifest_json),
      "content_type" => "application/json"
    }
  end

  defp validate_prepared_sources(project_id, objects, source_keys, source_key_mode)
       when is_list(objects) and source_key_mode in [:asset, :protected_blob] do
    blobs = Enum.filter(objects, &(&1["kind"] == "asset_blob"))
    hashes = MapSet.new(blobs, & &1["sha256"])

    with true <- MapSet.new(Map.keys(source_keys)) == hashes,
         true <-
           Enum.all?(blobs, &valid_prepared_source?(project_id, &1, source_keys, source_key_mode)) do
      :ok
    else
      false -> {:error, :prepared_snapshot_source_inventory_mismatch}
    end
  end

  defp validate_prepared_sources(_project_id, _objects, _source_keys, _source_key_mode),
    do: {:error, :prepared_snapshot_source_inventory_mismatch}

  defp valid_prepared_source?(project_id, blob, source_keys, :protected_blob) do
    hash = blob["sha256"]
    content_type = blob["content_type"]
    expected = BlobStore.blob_key(project_id, hash, BlobStore.ext_from_content_type(content_type))
    Map.get(source_keys, hash) == expected and Storage.canonical_key?(expected)
  end

  defp valid_prepared_source?(project_id, blob, source_keys, :asset) do
    source_key = Map.get(source_keys, blob["sha256"])
    expected_project_id = Integer.to_string(project_id)

    case is_binary(source_key) && String.split(source_key, "/", trim: false) do
      ["projects", ^expected_project_id, "assets", asset_uuid, filename] ->
        Storage.canonical_key?(source_key) and match?({:ok, _uuid}, Ecto.UUID.cast(asset_uuid)) and
          filename not in ["", ".", "..", ".storyarn-copy"]

      _invalid ->
        false
    end
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

  defp stage_blobs(prefix, blobs, source_keys, on_progress, initial_bytes) do
    Enum.reduce_while(blobs, {:ok, initial_bytes}, fn blob, {:ok, completed_bytes} ->
      source_key = source_keys[blob["sha256"]]
      destination_key = object_key(prefix, blob["path"])

      case copy_and_verify(source_key, destination_key, blob) do
        :ok ->
          completed_bytes = completed_bytes + blob["size_bytes"]
          continue_after_progress(on_progress, completed_bytes)

        {:error, _reason} = error ->
          {:halt, error}
      end
    end)
  end

  defp continue_after_progress(on_progress, completed_bytes) do
    case invoke_progress(on_progress, completed_bytes) do
      :ok -> {:cont, {:ok, completed_bytes}}
      {:error, _reason} = error -> {:halt, error}
    end
  end

  defp invoke_progress(on_progress, completed_bytes) do
    case on_progress.(completed_bytes) do
      :ok -> :ok
      {:error, _reason} = error -> error
      _invalid -> {:error, :invalid_snapshot_progress_result}
    end
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

  defp finalize_payload(staging_prefix, ready_prefix, objects, on_progress) do
    Enum.reduce_while(objects, {:ok, 0}, fn descriptor, {:ok, completed_bytes} ->
      finalize_payload_object(staging_prefix, ready_prefix, descriptor, on_progress, completed_bytes)
    end)
  end

  defp finalize_payload_object(staging_prefix, ready_prefix, descriptor, on_progress, completed_bytes) do
    with :ok <- finalize_object(staging_prefix, ready_prefix, descriptor),
         completed_bytes = completed_bytes + descriptor["size_bytes"],
         :ok <- invoke_progress(on_progress, completed_bytes) do
      {:cont, {:ok, completed_bytes}}
    else
      {:error, _reason} = error -> {:halt, error}
    end
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

    case StorageCompensation.cleanup_after_rollback(tracker, compensation_options()) do
      :ok ->
        {:error, original_reason}

      {:error, cleanup_reason} ->
        {:error, {:snapshot_object_cleanup_not_persisted, original_reason, cleanup_reason}}
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

  defp verify_blob_inventory(prefix, objects) do
    verify_object_inventory(prefix, Enum.reject(objects, &(&1["kind"] == "project")))
  end

  defp verify_object_inventory(prefix, objects) when is_binary(prefix) and is_list(objects) do
    Enum.reduce_while(objects, :ok, fn descriptor, :ok ->
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
    manifest_size = manifest_descriptor["size_bytes"]
    total_size = manifest["payload_size_bytes"] + manifest_size
    asset_blob_size = total_size - project["size_bytes"] - manifest_size

    {:ok,
     %{
       format_version: SnapshotObjectFormat.format_version(),
       mode: "full",
       lifecycle_state: "ready",
       integrity_state: "verified",
       object_prefix: ready_prefix,
       manifest_storage_key: object_key(ready_prefix, SnapshotObjectFormat.manifest_path()),
       manifest_size_bytes: manifest_size,
       manifest_checksum: manifest_descriptor["sha256"],
       project_storage_key: object_key(ready_prefix, SnapshotObjectFormat.project_path()),
       project_size_bytes: project["size_bytes"],
       project_checksum: project["sha256"],
       total_size_bytes: total_size,
       accounted_size_bytes: total_size,
       asset_blob_size_bytes: asset_blob_size,
       accounting_version: 1,
       object_count: counts["payload_objects"] + 1,
       asset_count: counts["assets"],
       blob_count: counts["blobs"],
       staging_cleanup_request_id: nil
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
