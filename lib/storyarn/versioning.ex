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

  alias Storyarn.Versioning.{
    ChangeDetector,
    ConflictDetector,
    EntityVersion,
    ProjectRecovery,
    ProjectSnapshot,
    ProjectSnapshotCrud,
    SnapshotDiff,
    SnapshotViewer,
    VersionCrud
  }

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
  defdelegate create_version(entity_type, entity, project_id, user_id, opts \\ []),
    to: VersionCrud

  @doc """
  Creates a version if enough time has passed since the last version.
  Returns `{:ok, version}`, `{:skipped, :too_recent}`, or `{:error, reason}`.
  """
  defdelegate maybe_create_version(entity_type, entity, project_id, user_id, opts \\ []),
    to: VersionCrud

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
  defdelegate get_adjacent_version_numbers(entity_type, entity_id, current_number),
    to: VersionCrud

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
  defdelegate detect_restore_conflicts(entity_type, snapshot, entity),
    to: ConflictDetector,
    as: :detect_conflicts

  @doc """
  Loads a version's snapshot from storage and restores the entity.
  """
  defdelegate restore_version(entity_type, entity, version, opts \\ []), to: VersionCrud

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

  @doc """
  Creates a project-level snapshot of all entities.
  """
  defdelegate create_project_snapshot(project_id, user_id, opts \\ []),
    to: ProjectSnapshotCrud,
    as: :create_snapshot

  @doc """
  Lists project snapshots, ordered by version number descending.
  """
  defdelegate list_project_snapshots(project_id, opts \\ []),
    to: ProjectSnapshotCrud,
    as: :list_snapshots

  @doc """
  Gets a project snapshot by ID.
  """
  defdelegate get_project_snapshot(project_id, id),
    to: ProjectSnapshotCrud,
    as: :get_snapshot_by_id

  @doc """
  Restores all project entities from a snapshot.
  """
  defdelegate restore_project_snapshot(project_id, snapshot, opts \\ []),
    to: ProjectSnapshotCrud,
    as: :restore_snapshot

  @doc """
  Deletes a project snapshot and its storage.
  """
  defdelegate delete_project_snapshot(snapshot),
    to: ProjectSnapshotCrud,
    as: :delete_snapshot

  @doc """
  Updates a project snapshot's title and description.
  """
  defdelegate update_project_snapshot(snapshot, attrs),
    to: ProjectSnapshotCrud,
    as: :update_snapshot

  @doc """
  Counts project snapshots for billing limit checks.
  """
  defdelegate count_project_snapshots(project_id),
    to: ProjectSnapshotCrud,
    as: :count_snapshots

  @doc """
  Prunes the oldest auto-generated snapshot for a project.
  """
  defdelegate prune_auto_snapshots(project_id),
    to: ProjectSnapshotCrud

  @doc """
  Deletes auto snapshots older than the given retention period.
  """
  defdelegate prune_expired_snapshots(project_id, retention_days),
    to: ProjectSnapshotCrud

  # ========== Project Recovery ==========

  @doc """
  Creates a new project from snapshot data with full ID remapping.
  """
  defdelegate recover_project(workspace_id, snapshot_data, user_id, opts \\ []),
    to: ProjectRecovery

  # ========== Snapshot Diff ==========

  @doc """
  Compares two snapshots and returns a structured diff result with changes and stats.
  """
  defdelegate diff_snapshots(entity_type, old_snapshot, new_snapshot),
    to: SnapshotDiff,
    as: :diff

  @doc """
  Returns true if two snapshots have any differences.
  """
  defdelegate snapshot_has_changes?(entity_type, old_snapshot, new_snapshot),
    to: SnapshotDiff,
    as: :has_changes?

  @doc """
  Converts a diff result into a human-readable summary string.
  """
  defdelegate format_diff_summary(diff_result),
    to: SnapshotDiff,
    as: :format_summary

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
