defmodule Storyarn.Flows.Versioning do
  @moduledoc """
  Flow-owned entity version history.

  The module owns the complete Flow version lifecycle while deliberately
  sharing the existing SQL table and object-storage namespace. Its public
  surface is Flow-specific; internal discriminator clauses fail closed when a
  record from another entity type reaches the shared table.
  """

  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.Versioning.Commands.NamedVersionCapacity
  alias Storyarn.Flows.Versioning.Commands.Tracked
  alias Storyarn.Flows.Versioning.Commands.VersionLifecycle
  alias Storyarn.Flows.Versioning.EntityVersionRecord
  alias Storyarn.Flows.Versioning.Execution.Restore
  alias Storyarn.Flows.Versioning.Execution.SnapshotReader
  alias Storyarn.Flows.Versioning.Queries.History
  alias Storyarn.Flows.Versioning.SnapshotViewer

  @type version :: EntityVersionRecord.t()

  defdelegate can_create_named_version?(project_id, workspace_id),
    to: NamedVersionCapacity,
    as: :can_create?

  defdelegate record_version_panel_opened(scope, flow), to: Tracked
  defdelegate record_version_compared(scope, flow), to: Tracked
  defdelegate create_named_version(scope, flow, opts), to: Tracked

  defdelegate restore_tracked_version(scope, flow, version, opts),
    to: Tracked,
    as: :restore_version

  defdelegate serialize_version_snapshot(snapshot), to: SnapshotViewer, as: :serialize

  defdelegate prepare_version_restore(flow, target_version), to: Restore, as: :prepare_restore

  defdelegate prepare_version_restore_conflicts(flow, target_version),
    to: Restore,
    as: :prepare_restore_conflicts

  defdelegate detect_version_restore_conflicts(snapshot, flow),
    to: Restore,
    as: :detect_restore_conflicts

  defdelegate ensure_version_restore_enabled(), to: Restore, as: :ensure_restore_enabled
  defdelegate build_version_snapshot(flow), to: SnapshotReader, as: :build_snapshot

  defdelegate version_snapshot_has_changes?(previous, current),
    to: SnapshotReader,
    as: :snapshot_has_changes?

  @doc false
  defdelegate set_current_version(flow, version_or_nil), to: VersionLifecycle

  @doc "Creates a durable Flow version."
  @spec create_version(Flow.t(), integer() | nil, keyword()) ::
          {:ok, version()} | {:error, term()}
  defdelegate create_version(flow, user_id, opts \\ []), to: VersionLifecycle

  @doc false
  defdelegate create_version(arg1, entity, project_id, user_id, opts \\ []),
    to: VersionLifecycle

  @doc "Creates an automatic version when the configured interval has elapsed."
  @spec maybe_create_version(Flow.t(), integer() | nil, keyword()) ::
          {:ok, version()}
          | {:skipped, :too_recent | :auto_versioning_disabled}
          | {:error, term()}
  defdelegate maybe_create_version(flow, user_id, opts \\ []), to: VersionLifecycle

  @doc false
  defdelegate maybe_create_version(arg1, entity, project_id, user_id, opts \\ []),
    to: VersionLifecycle

  @doc "Lists Flow versions newest first."
  @spec list_versions(integer(), keyword()) :: [version()]
  defdelegate list_versions(flow_id, opts \\ []), to: History

  @doc false
  defdelegate list_versions(arg1, flow_id, opts), to: History

  @doc "Gets one Flow version by its monotonic version number."
  @spec get_version(integer(), integer()) :: version() | nil
  defdelegate get_version(flow_id, version_number), to: History

  @doc false
  defdelegate get_version(arg1, flow_id, version_number), to: History

  @doc "Gets the most recent Flow version."
  @spec get_latest_version(integer()) :: version() | nil
  defdelegate get_latest_version(flow_id), to: History

  @doc false
  defdelegate get_latest_version(arg1, flow_id), to: History

  @doc "Counts persisted versions for a Flow."
  @spec count_versions(integer()) :: non_neg_integer()
  defdelegate count_versions(flow_id), to: History

  @doc false
  defdelegate count_versions(arg1, flow_id), to: History

  @doc "Returns the Flow version numbers immediately before and after the current number."
  @spec get_adjacent_version_numbers(integer(), integer()) ::
          {integer() | nil, integer() | nil}
  defdelegate get_adjacent_version_numbers(flow_id, current_number), to: History

  @doc false
  defdelegate get_adjacent_version_numbers(arg1, flow_id, current_number), to: History

  @doc "Counts Flow versions created after a timestamp."
  @spec count_versions_since(integer(), DateTime.t()) :: non_neg_integer()
  defdelegate count_versions_since(flow_id, since), to: History

  @doc false
  defdelegate count_versions_since(arg1, flow_id, since), to: History

  @doc "Updates the user-facing name and description of a Flow version."
  @spec update_version(map(), map()) :: {:ok, version()} | {:error, term()}
  defdelegate update_version(arg1, attrs), to: VersionLifecycle

  @doc "Deletes a Flow version and best-effort removes its snapshot object."
  @spec delete_version(map()) :: {:ok, version()} | {:error, term()}
  defdelegate delete_version(arg1), to: VersionLifecycle

  @doc "Loads and verifies the exact snapshot owned by a persisted Flow version."
  @spec load_version_snapshot(map()) :: {:ok, map()} | {:error, term()}
  defdelegate load_version_snapshot(arg1), to: SnapshotReader

  @doc """
  Decides the first restore step for a Flow.

  A missing or unreadable latest version is treated conservatively as unsaved
  work. Only a clean current Flow proceeds to loading the target and computing
  its conflict report.
  """
  @spec prepare_restore(Flow.t(), version()) ::
          {:ok, :unsaved_changes}
          | {:ok, {:ready, map()}}
          | {:error, :target_snapshot_unreadable}
  defdelegate prepare_restore(flow, target_version), to: Restore

  @doc "Loads the target snapshot and computes its Flow-owned restore conflict report."
  @spec prepare_restore_conflicts(Flow.t(), version()) ::
          {:ok, map()} | {:error, :target_snapshot_unreadable}
  defdelegate prepare_restore_conflicts(flow, target_version), to: Restore

  @doc "Detects Flow-owned restore conflicts without mutating state."
  defdelegate detect_restore_conflicts(snapshot, flow), to: Restore

  @doc false
  defdelegate detect_restore_conflicts(arg1, snapshot, flow), to: Restore

  @doc "Restores a Flow with a mandatory, verified safety version."
  @spec restore_version(Flow.t(), map(), keyword()) :: {:ok, Flow.t()} | {:error, term()}
  defdelegate restore_version(flow, version), to: Restore

  @doc false
  defdelegate restore_version(flow, version, opts), to: Restore

  defdelegate restore_version(arg1, flow, arg3, opts), to: Restore

  @doc "Returns whether Flow version restore is enabled."
  defdelegate restore_enabled?(), to: Restore

  @doc false
  defdelegate restore_enabled?(arg1), to: Restore

  @doc false
  defdelegate ensure_restore_enabled(), to: Restore

  @doc false
  defdelegate ensure_restore_enabled(arg1), to: Restore

  @doc false
  defdelegate get_builder!(arg1), to: SnapshotReader

  @doc false
  defdelegate build_snapshot(flow), to: SnapshotReader

  @doc false
  defdelegate snapshot_has_changes?(previous, current), to: SnapshotReader

  @doc false
  defdelegate snapshot_has_changes?(arg1, previous, current), to: SnapshotReader

  @doc false
  defdelegate next_version_number(flow_id), to: History
end
