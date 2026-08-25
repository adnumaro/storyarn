defmodule Storyarn.Projects.Versioning do
  @moduledoc """
  The Versioning context.

  Manages the legacy entity version history for Sheets. Flow and Scene version
  history belong exclusively to `Storyarn.Flows` and `Storyarn.Scenes`.
  Versions are snapshots stored as compressed JSON in object storage (R2/Local),
  with metadata tracked in the database.

  This module serves as a facade, delegating to specialized submodules:
  - `VersionCrud` - CRUD operations for versions
  - `SnapshotStorage` - Compressed JSON storage in R2/Local
  - `Builders.*` - Entity-specific snapshot building and restoration
  """

  alias Storyarn.Platform
  alias Storyarn.Projects.Versioning.ChangeDetector
  alias Storyarn.Projects.Versioning.ProjectSnapshot
  alias Storyarn.Projects.Versioning.ProjectSnapshotBuild
  alias Storyarn.Projects.Versioning.ProjectSnapshotCrud
  alias Storyarn.Projects.Versioning.ProjectSnapshotDownload
  alias Storyarn.Projects.Versioning.ProjectSnapshotLeasePolicy
  alias Storyarn.Projects.Versioning.ProjectSnapshotLifecycle
  alias Storyarn.Projects.Versioning.ProjectSnapshotReconciliation
  alias Storyarn.Projects.Versioning.ProjectSnapshotReconciliationRepair
  alias Storyarn.Projects.Versioning.ProjectSnapshotRestoreLifecycle
  alias Storyarn.Projects.Versioning.RestorePolicy
  alias Storyarn.Projects.Versioning.WorkspaceSnapshotImports

  @type project_snapshot :: ProjectSnapshot.t()

  # ========== Project Snapshots ==========

  @doc "Requests one durable standalone snapshot import into a workspace."
  defdelegate request_workspace_snapshot_import(current_scope, workspace, uploaded_path, attrs),
    to: WorkspaceSnapshotImports,
    as: :request

  defdelegate prepare_external_workspace_snapshot_import(current_scope, workspace, attrs),
    to: WorkspaceSnapshotImports,
    as: :prepare_external_upload

  defdelegate request_stored_workspace_snapshot_import(current_scope, workspace, import_id),
    to: WorkspaceSnapshotImports,
    as: :request_stored

  defdelegate update_workspace_snapshot_upload_progress(current_scope, workspace, import_id, percent),
    to: WorkspaceSnapshotImports,
    as: :upload_progress

  defdelegate cancel_workspace_snapshot_upload(current_scope, workspace, import_id),
    to: WorkspaceSnapshotImports,
    as: :cancel_upload

  @doc "Lists recent standalone snapshot imports for one workspace."
  defdelegate list_workspace_snapshot_imports(current_scope, workspace),
    to: WorkspaceSnapshotImports,
    as: :list

  @doc "Subscribes to committed standalone snapshot-import lifecycle changes."
  defdelegate subscribe_workspace_snapshot_imports(workspace_id),
    to: WorkspaceSnapshotImports,
    as: :subscribe

  @doc false
  defdelegate prepare_workspace_snapshot_import_hard_delete(workspace),
    to: WorkspaceSnapshotImports,
    as: :prepare_workspace_hard_delete

  @doc false
  defdelegate perform_workspace_snapshot_import(import_id, opts),
    to: WorkspaceSnapshotImports,
    as: :perform

  @doc false
  defdelegate reconcile_abandoned_workspace_snapshot_import_deliveries(opts \\ []),
    to: WorkspaceSnapshotImports,
    as: :reconcile_abandoned_deliveries

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

  @doc "Returns whether this release supports exact full-project snapshot restore."
  def project_snapshot_restore_enabled? do
    RestorePolicy.enabled?({:project_snapshot_restore, "full"})
  end

  @doc false
  defdelegate restorable_project_snapshot_identity(snapshot),
    to: ProjectSnapshotRestoreLifecycle,
    as: :restorable_snapshot_identity

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

  @doc false
  defdelegate project_snapshot_build_statuses(snapshots),
    to: ProjectSnapshotBuild,
    as: :build_statuses

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

  @doc false
  defdelegate request_import_recovery_snapshot_cancellation_in_transaction(snapshot, workspace_id),
    to: ProjectSnapshotBuild

  @doc false
  defdelegate publish_committed_import_recovery_snapshot_cancellation(snapshot),
    to: ProjectSnapshotBuild

  @doc "Authorizes deletion and durably hands every owned object to cleanup."
  defdelegate delete_project_snapshot(current_scope, project, snapshot_id),
    to: ProjectSnapshotLifecycle,
    as: :delete

  @doc false
  defdelegate prepare_abandoned_import_snapshot_cleanup_in_transaction(snapshot, workspace_id),
    to: ProjectSnapshotLifecycle

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
    to: Platform,
    as: :recover_expired_snapshot_export_leases

  @doc false
  defdelegate purge_released_project_snapshot_export_leases(cutoff, opts \\ []),
    to: Platform,
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

  @doc "Authorizes, leases and prepares one bounded Project snapshot download."
  defdelegate with_authorized_project_snapshot_download(scope, project_id, snapshot_id, callback),
    to: ProjectSnapshotDownload,
    as: :with_authorized_download

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

  # ========== Snapshot Viewer ==========

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
