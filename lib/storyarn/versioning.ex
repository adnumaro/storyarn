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

  alias Storyarn.Billing
  alias Storyarn.Versioning.ChangeDetector
  alias Storyarn.Versioning.ConflictDetector
  alias Storyarn.Versioning.EntityVersion
  alias Storyarn.Versioning.ProjectSnapshot
  alias Storyarn.Versioning.ProjectSnapshotBuild
  alias Storyarn.Versioning.ProjectSnapshotCrud
  alias Storyarn.Versioning.ProjectSnapshotDownload
  alias Storyarn.Versioning.ProjectSnapshotLeasePolicy
  alias Storyarn.Versioning.ProjectSnapshotLifecycle
  alias Storyarn.Versioning.ProjectSnapshotReconciliation
  alias Storyarn.Versioning.ProjectSnapshotReconciliationRepair
  alias Storyarn.Versioning.ProjectSnapshotRestoreLifecycle
  alias Storyarn.Versioning.RestorePolicy
  alias Storyarn.Versioning.SnapshotDiff
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
  Returns a report with blocking reference conflicts and shortcut collisions.
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

  @doc "Requests one durable exact restore from a canonical full project snapshot."
  defdelegate request_project_snapshot_restore(current_scope, project, snapshot, attrs),
    to: ProjectSnapshotRestoreLifecycle,
    as: :request

  @doc "Returns whether exact full-project snapshot restore is enabled."
  def project_snapshot_restore_enabled? do
    RestorePolicy.enabled?({:project_snapshot_restore, "full"})
  end

  @doc "Returns one durable project-snapshot restore operation."
  defdelegate get_project_snapshot_restore(restore_id),
    to: ProjectSnapshotRestoreLifecycle,
    as: :get

  @doc "Lists recent exact-restore operations for one project."
  defdelegate list_project_snapshot_restores(project_id, opts \\ []),
    to: ProjectSnapshotRestoreLifecycle,
    as: :list_for_project

  @doc "Subscribes the current process to exact-restore lifecycle changes for a project."
  defdelegate subscribe_project_snapshot_restores(project_id),
    to: ProjectSnapshotRestoreLifecycle,
    as: :subscribe

  @doc false
  defdelegate perform_project_snapshot_restore(restore_id, generation, opts),
    to: ProjectSnapshotRestoreLifecycle,
    as: :perform

  @doc false
  defdelegate claim_project_snapshot_restore(restore_id, generation, opts),
    to: ProjectSnapshotRestoreLifecycle,
    as: :claim

  @doc false
  defdelegate complete_project_snapshot_restore(restore_id, generation, result),
    to: ProjectSnapshotRestoreLifecycle,
    as: :complete

  @doc false
  defdelegate fail_project_snapshot_restore(restore_id, generation, reason),
    to: ProjectSnapshotRestoreLifecycle,
    as: :fail

  @doc false
  defdelegate advance_project_snapshot_restore_phase(restore_id, generation, phase),
    to: ProjectSnapshotRestoreLifecycle,
    as: :advance_phase

  @doc false
  defdelegate bind_project_snapshot_restore_reservation(restore_id, generation, reservation),
    to: ProjectSnapshotRestoreLifecycle,
    as: :bind_reservation

  @doc false
  defdelegate reserve_and_bind_project_snapshot_restore(restore_id, generation, reservation_attrs, opts \\ []),
    to: ProjectSnapshotRestoreLifecycle,
    as: :reserve_and_bind

  @doc false
  defdelegate project_snapshot_restore_delivery_recovery_high_watermark(),
    to: ProjectSnapshotRestoreLifecycle,
    as: :delivery_recovery_high_watermark

  @doc false
  defdelegate project_snapshot_restore_delivery_recovery_quarantine_seconds(),
    to: ProjectSnapshotRestoreLifecycle,
    as: :delivery_recovery_quarantine_seconds

  @doc false
  defdelegate list_abandoned_project_snapshot_restore_deliveries(opts \\ []),
    to: ProjectSnapshotRestoreLifecycle,
    as: :list_abandoned_delivery_candidates

  @doc false
  defdelegate recover_abandoned_project_snapshot_restore_delivery(candidate, opts \\ []),
    to: ProjectSnapshotRestoreLifecycle,
    as: :recover_abandoned_delivery

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

  @doc "Starts an observation-only, resumable snapshot reconciliation run."
  defdelegate start_project_snapshot_reconciliation(opts \\ []),
    to: ProjectSnapshotReconciliation,
    as: :start

  @doc false
  defdelegate advance_project_snapshot_reconciliation(run_id, expected_generation),
    to: ProjectSnapshotReconciliation,
    as: :advance

  @doc false
  defdelegate fail_project_snapshot_reconciliation(run_id, expected_generation, reason),
    to: ProjectSnapshotReconciliation,
    as: :fail

  @doc "Returns one persisted snapshot reconciliation run."
  defdelegate get_project_snapshot_reconciliation_run(run_id),
    to: ProjectSnapshotReconciliation,
    as: :get_run

  @doc "Lists immutable findings from one snapshot reconciliation run."
  defdelegate list_project_snapshot_reconciliation_findings(run_id, opts \\ []),
    to: ProjectSnapshotReconciliation,
    as: :list_findings

  @doc "Persists and enqueues one bounded page of explicit, generation-fenced reconciliation repairs."
  defdelegate plan_project_snapshot_reconciliation_repairs(run_id, opts \\ []),
    to: ProjectSnapshotReconciliationRepair,
    as: :plan

  @doc "Lists durable reconciliation repair outcomes for one inspection run."
  defdelegate list_project_snapshot_reconciliation_repairs(run_id, opts \\ []),
    to: ProjectSnapshotReconciliationRepair,
    as: :list_actions

  @doc false
  defdelegate project_snapshot_reconciliation_repair_page_limit(),
    to: ProjectSnapshotReconciliationRepair,
    as: :repair_page_limit

  @doc false
  defdelegate perform_project_snapshot_reconciliation_repair(action_id),
    to: ProjectSnapshotReconciliationRepair,
    as: :perform

  @doc false
  defdelegate fail_project_snapshot_reconciliation_repair(action_id, reason),
    to: ProjectSnapshotReconciliationRepair,
    as: :fail

  @doc false
  defdelegate project_snapshot_reconciliation_repair_recovery_high_watermark(),
    to: ProjectSnapshotReconciliationRepair,
    as: :repair_delivery_recovery_high_watermark

  @doc false
  defdelegate recover_project_snapshot_reconciliation_repair_delivery_page(opts \\ []),
    to: ProjectSnapshotReconciliationRepair,
    as: :recover_repair_delivery_page

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
  defdelegate recover_expired_project_snapshot_export_leases(now, opts \\ []),
    to: Billing,
    as: :recover_expired_snapshot_export_leases

  @doc false
  defdelegate purge_released_project_snapshot_export_leases(cutoff, opts \\ []),
    to: Billing,
    as: :purge_released_snapshot_export_leases

  @doc false
  defdelegate project_snapshot_download_signed_url_ttl_seconds(),
    to: ProjectSnapshotLeasePolicy,
    as: :download_signed_url_ttl_seconds

  @doc false
  defdelegate project_snapshot_download_export_lease_ttl_seconds(),
    to: ProjectSnapshotLeasePolicy,
    as: :download_export_lease_ttl_seconds

  @doc false
  defdelegate project_snapshot_export_lease_retention_seconds(),
    to: ProjectSnapshotLeasePolicy,
    as: :export_lease_retention_seconds

  @doc false
  defdelegate project_snapshot_build_heartbeat_interval_ms(),
    to: ProjectSnapshotLeasePolicy,
    as: :build_heartbeat_interval_ms

  @doc false
  defdelegate project_snapshot_build_lease_ttl_seconds(),
    to: ProjectSnapshotLeasePolicy,
    as: :build_lease_ttl_seconds

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

  @doc "Yields one authorized persisted snapshot archive behind its durable download lease."
  defdelegate with_project_snapshot_archive(project, snapshot_id, callback),
    to: ProjectSnapshotDownload,
    as: :with_archive

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
  Reconfirms immutable snapshot accounting behind a workspace and generation fence.
  """
  defdelegate remeasure_project_snapshot_object_set(snapshot_id, expected_generation, attrs),
    to: ProjectSnapshotCrud,
    as: :remeasure_object_set

  @doc """
  Counts project snapshots for billing limit checks.
  """
  defdelegate count_project_snapshots(project_id), to: ProjectSnapshotCrud, as: :count_snapshots

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
