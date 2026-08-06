defmodule Storyarn.Versioning do
  @moduledoc """
  The Versioning context.

  Manages entity version history for sheets, flows, and scenes. Versions are
  snapshots stored as compressed JSON in object storage (R2/Local), with
  metadata tracked in the database.

  This module serves as a facade, delegating to specialized submodules:
  - `VersionCrud` - CRUD operations for versions
  - `SnapshotStorage` - Compressed JSON storage in R2/Local
  - `Builders.*` - Entity-specific snapshot building and restoration
  """

  alias Storyarn.Versioning.ChangeDetector
  alias Storyarn.Versioning.ConflictDetector
  alias Storyarn.Versioning.EntityVersion
  alias Storyarn.Versioning.ProjectSnapshot
  alias Storyarn.Versioning.ProjectSnapshotBuild
  alias Storyarn.Versioning.ProjectSnapshotCrud
  alias Storyarn.Versioning.ProjectSnapshotLifecycle
  alias Storyarn.Versioning.ProjectSnapshotReset
  alias Storyarn.Versioning.RestorePolicy
  alias Storyarn.Versioning.SnapshotDiff
  alias Storyarn.Versioning.SnapshotObjectStorage
  alias Storyarn.Versioning.SnapshotViewer
  alias Storyarn.Versioning.VersionCrud

  @type version :: EntityVersion.t()
  @type project_snapshot :: ProjectSnapshot.t()

  # ========== Create ==========

  @doc """
  Creates a new version for the given entity.

  ## Options
  - `:title` - Custom title for manual versions
  - `:description` - Optional description
  - `:is_auto` - Whether this is an auto-generated version (default: false)
  """
  defdelegate create_version(entity_type, entity, project_id, user_id, opts \\ []), to: VersionCrud

  @doc """
  Creates a version if enough time has passed since the last version.
  Returns `{:ok, version}`, `{:skipped, :too_recent}`, or `{:error, reason}`.
  """
  defdelegate maybe_create_version(entity_type, entity, project_id, user_id, opts \\ []), to: VersionCrud

  # ========== Queries ==========

  @doc """
  Lists versions for an entity, ordered by version number descending.
  """
  defdelegate list_versions(entity_type, entity_id, opts \\ []), to: VersionCrud

  @doc """
  Gets a specific version by entity type, entity ID, and version number.
  """
  defdelegate get_version(entity_type, entity_id, version_number), to: VersionCrud

  @doc """
  Gets the latest version for an entity.
  """
  defdelegate get_latest_version(entity_type, entity_id), to: VersionCrud

  @doc """
  Returns the total number of versions for an entity.
  """
  defdelegate count_versions(entity_type, entity_id), to: VersionCrud

  @doc """
  Returns `{prev_number, next_number}` adjacent to the given version number.
  Either may be nil if no adjacent version exists.
  """
  defdelegate get_adjacent_version_numbers(entity_type, entity_id, current_number), to: VersionCrud

  @doc """
  Counts versions created after the given timestamp for an entity.
  """
  defdelegate count_versions_since(entity_type, entity_id, since), to: VersionCrud

  # ========== Update ==========

  @doc """
  Updates a version's title and description (promotes auto-snapshots to named versions).
  """
  defdelegate update_version(version, attrs), to: VersionCrud

  @doc """
  Counts named versions (with non-nil title) for a project.
  """
  defdelegate count_named_versions(project_id), to: VersionCrud

  # ========== Delete ==========

  @doc """
  Deletes a version and its snapshot from storage.
  """
  defdelegate delete_version(version), to: VersionCrud

  # ========== Restore ==========

  @doc """
  Detects conflicts that would occur when restoring from a snapshot.
  Returns a report with missing references, shortcut collisions, and auto-resolved items.
  """
  defdelegate detect_restore_conflicts(entity_type, snapshot, entity), to: ConflictDetector, as: :detect_conflicts

  @doc """
  Loads a version's snapshot from storage and restores the entity.
  """
  def restore_version(entity_type, entity, version, opts \\ []) do
    with :ok <- RestorePolicy.ensure_enabled({:entity_version_restore, entity_type}) do
      VersionCrud.restore_version(entity_type, entity, version, opts)
    end
  end

  @doc """
  Returns whether a mutating restore surface is currently enabled.
  """
  defdelegate restore_enabled?(action), to: RestorePolicy, as: :enabled?

  @doc """
  Returns `:ok` when a mutating restore surface is enabled.
  """
  defdelegate ensure_restore_enabled(action), to: RestorePolicy, as: :ensure_enabled

  @doc """
  Loads a version's snapshot from storage.
  """
  defdelegate load_version_snapshot(version), to: VersionCrud

  # ========== Helpers ==========

  @doc """
  Returns the next version number for an entity.
  """
  defdelegate next_version_number(entity_type, entity_id), to: VersionCrud

  @doc """
  Returns the builder module for the given entity type.
  """
  defdelegate get_builder!(entity_type), to: VersionCrud

  # ========== Project Snapshots ==========

  @doc "Persists one immutable full-snapshot request and enqueues its worker atomically."
  defdelegate request_full_project_snapshot(current_scope, project, attrs),
    to: ProjectSnapshotBuild,
    as: :request

  @doc false
  defdelegate perform_project_snapshot_build(snapshot_id, opts),
    to: ProjectSnapshotBuild,
    as: :perform

  @doc false
  defdelegate heartbeat_project_snapshot_build(snapshot_id, job_id),
    to: ProjectSnapshotBuild,
    as: :heartbeat

  @doc false
  defdelegate validate_project_snapshot_build_fence(snapshot_id, expected_generation),
    to: ProjectSnapshotBuild,
    as: :validate_build_fence

  @doc false
  defdelegate reconcile_stale_project_snapshot_builds(),
    to: ProjectSnapshotBuild,
    as: :reconcile_stale_builds

  @doc "Requests cooperative cancellation for an in-progress project snapshot."
  defdelegate cancel_project_snapshot(current_scope, project, snapshot_id),
    to: ProjectSnapshotBuild,
    as: :cancel

  @doc "Authorizes deletion and durably hands every owned object to cleanup."
  defdelegate delete_project_snapshot(current_scope, project, snapshot_id),
    to: ProjectSnapshotLifecycle,
    as: :delete

  @doc false
  defdelegate prepare_project_snapshot_hard_delete(project),
    to: ProjectSnapshotLifecycle,
    as: :prepare_project_hard_delete

  @doc false
  defdelegate prepare_workspace_snapshot_hard_delete(workspace),
    to: ProjectSnapshotLifecycle,
    as: :prepare_workspace_hard_delete

  @doc false
  defdelegate publish_committed_snapshot_cleanup_intents(intents),
    to: ProjectSnapshotLifecycle,
    as: :publish_committed_cleanup_intents

  @doc false
  defdelegate list_project_snapshot_retention_candidates(now, opts \\ []),
    to: ProjectSnapshotLifecycle,
    as: :list_retention_candidates

  @doc false
  defdelegate delete_project_snapshot_retention_candidate(candidate),
    to: ProjectSnapshotLifecycle,
    as: :delete_retention_candidate

  @doc false
  defdelegate list_expired_project_snapshot_build_candidates(now, opts \\ []),
    to: ProjectSnapshotLifecycle,
    as: :list_expired_build_candidates

  @doc false
  defdelegate delete_expired_project_snapshot_build_candidate(candidate),
    to: ProjectSnapshotLifecycle,
    as: :delete_expired_build_candidate

  @doc false
  defdelegate project_snapshot_build_recovery_quarantine_seconds(),
    to: ProjectSnapshotLifecycle,
    as: :build_recovery_quarantine_seconds

  @doc false
  defdelegate project_snapshot_lifecycle_high_watermark(),
    to: ProjectSnapshotLifecycle,
    as: :lifecycle_high_watermark

  @doc false
  @spec process_project_snapshot_cleanup_intent(pos_integer(), keyword()) ::
          ProjectSnapshotLifecycle.cleanup_process_result()
  defdelegate process_project_snapshot_cleanup_intent(intent_id, opts \\ []),
    to: ProjectSnapshotLifecycle,
    as: :process_cleanup_intent

  @doc false
  defdelegate project_snapshot_cleanup_recovery_high_watermark(),
    to: ProjectSnapshotLifecycle,
    as: :cleanup_recovery_high_watermark

  @doc false
  defdelegate discard_stale_project_snapshot_maintenance_jobs(),
    to: ProjectSnapshotLifecycle,
    as: :discard_stale_maintenance_jobs

  @doc false
  defdelegate rescue_stale_project_snapshot_cleanup_jobs(),
    to: ProjectSnapshotLifecycle,
    as: :rescue_stale_cleanup_jobs

  @doc false
  defdelegate list_project_snapshot_cleanup_recovery_candidates(opts \\ []),
    to: ProjectSnapshotLifecycle,
    as: :list_cleanup_recovery_candidates

  @doc false
  defdelegate recover_project_snapshot_cleanup_intent(intent_id),
    to: ProjectSnapshotLifecycle,
    as: :recover_cleanup_intent

  @doc "Replays a terminal snapshot cleanup after its provider failure is remediated."
  defdelegate replay_terminal_project_snapshot_cleanup(intent_id),
    to: ProjectSnapshotLifecycle,
    as: :replay_terminal_cleanup_intent

  @doc false
  defdelegate project_snapshot_cleanup_operator_action(intent_id),
    to: ProjectSnapshotLifecycle,
    as: :cleanup_operator_action

  @doc "Returns observable snapshot cleanup backlog gauges."
  defdelegate project_snapshot_cleanup_backlog(),
    to: ProjectSnapshotLifecycle,
    as: :cleanup_backlog

  @doc false
  defdelegate prepare_project_snapshot_reset(workspace_id, environment, opts \\ []),
    to: ProjectSnapshotReset,
    as: :prepare

  @doc false
  defdelegate execute_project_snapshot_reset(plan, confirmation_digest, opts \\ []),
    to: ProjectSnapshotReset,
    as: :execute

  @doc false
  defdelegate prepare_project_snapshot_provider_reset(environment, opts \\ []),
    to: ProjectSnapshotReset,
    as: :prepare_provider

  @doc false
  defdelegate validate_project_snapshot_reset_plan(plan),
    to: ProjectSnapshotReset,
    as: :validate_plan

  defdelegate verify_project_snapshot_reset_rollout_readiness(environment, opts \\ []),
    to: ProjectSnapshotReset,
    as: :verify_rollout_readiness

  @doc "Subscribes the current process to lifecycle changes for one project's snapshots."
  defdelegate subscribe_project_snapshots(project_id),
    to: ProjectSnapshotBuild,
    as: :subscribe

  @doc """
  Lists project snapshots, ordered by version number descending.
  """
  defdelegate list_project_snapshots(project_id, opts \\ []), to: ProjectSnapshotCrud, as: :list_snapshots

  @doc """
  Gets a project snapshot by ID.
  """
  defdelegate get_project_snapshot(project_id, id), to: ProjectSnapshotCrud, as: :get_snapshot_by_id

  @doc """
  Updates a project snapshot's title and description.
  """
  defdelegate update_project_snapshot(snapshot, attrs), to: ProjectSnapshotCrud, as: :update_snapshot

  @doc """
  Finalizes or remeasures canonical snapshot accounting behind a generation fence.
  """
  defdelegate finalize_project_snapshot_object_set(snapshot_id, expected_generation, attrs),
    to: ProjectSnapshotCrud,
    as: :finalize_object_set

  @doc """
  Converts linked ownership to a self-contained full object set inside its reservation commit.
  """
  defdelegate convert_linked_project_snapshot_object_set(snapshot_id, expected_generation, attrs),
    to: ProjectSnapshotCrud,
    as: :convert_linked_object_set

  @doc """
  Reconfirms immutable snapshot accounting behind a workspace and generation fence.
  """
  defdelegate remeasure_project_snapshot_object_set(snapshot_id, expected_generation, attrs),
    to: ProjectSnapshotCrud,
    as: :remeasure_object_set

  @doc """
  Counts project snapshots for billing limit checks.
  """
  defdelegate count_project_snapshots(project_id), to: ProjectSnapshotCrud, as: :count_snapshots

  @doc """
  Persists a canonical snapshot-owned object set without scheduling capture.
  """
  defdelegate persist_snapshot_object_set(project_id, project_snapshot, assets, opts \\ []),
    to: SnapshotObjectStorage,
    as: :persist

  @doc "Materializes exact project and manifest bytes without writing storage objects."
  defdelegate prepare_snapshot_object_set(project_id, project_snapshot, assets, opts \\ []),
    to: SnapshotObjectStorage,
    as: :prepare

  @doc """
  Stages and verifies a canonical snapshot object set without publishing it.
  """
  defdelegate stage_snapshot_object_set(project_id, project_snapshot, assets, opts \\ []),
    to: SnapshotObjectStorage,
    as: :stage

  @doc "Stages a previously materialized immutable snapshot capture."
  defdelegate stage_prepared_snapshot_object_set(project_id, prepared, opts \\ []),
    to: SnapshotObjectStorage,
    as: :stage_prepared

  @doc """
  Publishes a staged object set after the supplied exact-size authorization.
  """
  defdelegate publish_snapshot_object_set(staged, before_publish),
    to: SnapshotObjectStorage,
    as: :publish

  @doc """
  Loads a ready object set after verifying its manifest and complete inventory.
  """
  defdelegate load_snapshot_object_set(manifest_storage_key, manifest_checksum, manifest_size_bytes, opts \\ []),
    to: SnapshotObjectStorage,
    as: :load_verified

  # ========== Snapshot Diff ==========

  @doc """
  Compares two snapshots and returns a structured diff result with changes and stats.
  """
  defdelegate diff_snapshots(entity_type, old_snapshot, new_snapshot), to: SnapshotDiff, as: :diff

  @doc """
  Returns true if two snapshots have any differences.
  """
  defdelegate snapshot_has_changes?(entity_type, old_snapshot, new_snapshot), to: SnapshotDiff, as: :has_changes?

  @doc """
  Converts a diff result into a human-readable summary string.
  """
  defdelegate format_diff_summary(diff_result), to: SnapshotDiff, as: :format_summary

  # ========== Snapshot Viewer ==========

  @doc """
  Serializes a flow snapshot into the shape expected by the FlowCanvas JS hook.
  """
  defdelegate serialize_flow(snapshot), to: SnapshotViewer

  @doc """
  Serializes a scene snapshot into the shape expected by the SceneCanvas JS hook.
  """
  defdelegate serialize_scene(snapshot), to: SnapshotViewer

  @doc """
  Serializes a sheet snapshot into a list of block maps for BlockComponents.
  """
  defdelegate serialize_sheet(snapshot), to: SnapshotViewer

  # ========== Change Detection ==========

  @doc """
  Returns true if any entity was modified since the last project snapshot.
  """
  defdelegate project_changed_since_last_snapshot?(project_id), to: ChangeDetector

  @doc """
  Returns true if a manual snapshot was created within the given hours.
  """
  defdelegate recent_manual_snapshot?(project_id, hours \\ 6), to: ChangeDetector
end
