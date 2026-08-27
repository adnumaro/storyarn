defmodule Storyarn.Sheets.Versioning do
  @moduledoc """
  Sheet-owned entity version history.

  The module owns the complete Sheet version lifecycle while deliberately
  sharing the existing SQL table and object-storage namespace. Its public
  surface is Sheet-specific; internal discriminator clauses fail closed when a
  record from another entity type reaches the shared table.
  """

  alias Storyarn.Sheets.Sheet
  alias Storyarn.Sheets.Versioning.Commands.NamedVersionCapacity
  alias Storyarn.Sheets.Versioning.Commands.Tracked
  alias Storyarn.Sheets.Versioning.Commands.VersionLifecycle
  alias Storyarn.Sheets.Versioning.EntityVersionRecord
  alias Storyarn.Sheets.Versioning.Execution.Restore
  alias Storyarn.Sheets.Versioning.Execution.SnapshotReader
  alias Storyarn.Sheets.Versioning.Queries.History
  alias Storyarn.Sheets.Versioning.Queries.SnapshotViewer

  @type version :: EntityVersionRecord.t()

  defdelegate can_create_named_version?(project_id, workspace_id),
    to: NamedVersionCapacity,
    as: :can_create?

  defdelegate record_version_panel_opened(scope, sheet), to: Tracked
  defdelegate record_version_compared(scope, sheet), to: Tracked
  defdelegate create_named_version(scope, sheet, opts), to: Tracked

  defdelegate restore_tracked_version(scope, sheet, version, opts),
    to: Tracked,
    as: :restore_version

  defdelegate serialize_version_snapshot(snapshot), to: SnapshotViewer, as: :serialize_sheet

  defdelegate prepare_version_restore(sheet, target_version),
    to: Restore,
    as: :prepare_restore

  defdelegate prepare_version_restore_conflicts(sheet, target_version),
    to: Restore,
    as: :prepare_restore_conflicts

  defdelegate detect_version_restore_conflicts(snapshot, sheet),
    to: Restore,
    as: :detect_restore_conflicts

  defdelegate ensure_version_restore_enabled(), to: Restore, as: :ensure_restore_enabled

  @doc false
  defdelegate set_current_version(sheet, version_or_nil), to: VersionLifecycle

  @doc "Creates a durable Sheet version."
  @spec create_version(Sheet.t(), integer() | nil, keyword()) ::
          {:ok, version()} | {:error, term()}
  defdelegate create_version(sheet, user_id, opts \\ []), to: VersionLifecycle

  @doc false
  defdelegate create_version(arg1, entity, project_id, user_id, opts \\ []),
    to: VersionLifecycle

  @doc "Creates an automatic version when the configured interval has elapsed."
  @spec maybe_create_version(Sheet.t(), integer() | nil, keyword()) ::
          {:ok, version()}
          | {:skipped, :too_recent | :auto_versioning_disabled}
          | {:error, term()}
  defdelegate maybe_create_version(sheet, user_id, opts \\ []), to: VersionLifecycle

  @doc false
  defdelegate maybe_create_version(arg1, entity, project_id, user_id, opts \\ []),
    to: VersionLifecycle

  @doc "Lists Sheet versions newest first."
  @spec list_versions(integer(), keyword()) :: [version()]
  defdelegate list_versions(sheet_id, opts \\ []), to: History

  @doc false
  defdelegate list_versions(arg1, sheet_id, opts), to: History

  @doc "Gets one Sheet version by its monotonic version number."
  @spec get_version(integer(), integer()) :: version() | nil
  defdelegate get_version(sheet_id, version_number), to: History

  @doc false
  defdelegate get_version(arg1, sheet_id, version_number), to: History

  @doc "Gets the most recent Sheet version."
  @spec get_latest_version(integer()) :: version() | nil
  defdelegate get_latest_version(sheet_id), to: History

  @doc false
  defdelegate get_latest_version(arg1, sheet_id), to: History

  @doc "Counts persisted versions for a Sheet."
  @spec count_versions(integer()) :: non_neg_integer()
  defdelegate count_versions(sheet_id), to: History

  @doc false
  defdelegate count_versions(arg1, sheet_id), to: History

  @doc "Returns the Sheet version numbers immediately before and after the current number."
  @spec get_adjacent_version_numbers(integer(), integer()) ::
          {integer() | nil, integer() | nil}
  defdelegate get_adjacent_version_numbers(sheet_id, current_number), to: History

  @doc false
  defdelegate get_adjacent_version_numbers(arg1, sheet_id, current_number), to: History

  @doc "Counts Sheet versions created after a timestamp."
  @spec count_versions_since(integer(), DateTime.t()) :: non_neg_integer()
  defdelegate count_versions_since(sheet_id, since), to: History

  @doc false
  defdelegate count_versions_since(arg1, sheet_id, since), to: History

  @doc "Updates the user-facing name and description of a Sheet version."
  @spec update_version(map(), map()) :: {:ok, version()} | {:error, term()}
  defdelegate update_version(arg1, attrs), to: VersionLifecycle

  @doc "Deletes a Sheet version and best-effort removes its snapshot object."
  @spec delete_version(map()) :: {:ok, version()} | {:error, term()}
  defdelegate delete_version(arg1), to: VersionLifecycle

  @doc "Loads and verifies the exact snapshot owned by a persisted Sheet version."
  @spec load_version_snapshot(map()) :: {:ok, map()} | {:error, term()}
  defdelegate load_version_snapshot(arg1), to: SnapshotReader

  @doc """
  Decides the first restore step for a Sheet.

  A missing or unreadable latest version is treated conservatively as unsaved
  work. Only a clean current Sheet proceeds to loading the target and computing
  its conflict report.
  """
  @spec prepare_restore(Sheet.t(), version()) ::
          {:ok, :unsaved_changes}
          | {:ok, {:ready, map()}}
          | {:error, :target_snapshot_unreadable}
  defdelegate prepare_restore(sheet, target_version), to: Restore

  @doc "Loads the target snapshot and computes its Sheet-owned restore conflict report."
  @spec prepare_restore_conflicts(Sheet.t(), version()) ::
          {:ok, map()} | {:error, :target_snapshot_unreadable}
  defdelegate prepare_restore_conflicts(sheet, target_version), to: Restore

  @doc "Detects Sheet-owned restore conflicts without mutating state."
  defdelegate detect_restore_conflicts(snapshot, sheet), to: Restore

  @doc false
  defdelegate detect_restore_conflicts(arg1, snapshot, sheet), to: Restore

  @doc "Restores a Sheet with a mandatory, verified safety version."
  @spec restore_version(Sheet.t(), map(), keyword()) :: {:ok, Sheet.t()} | {:error, term()}
  defdelegate restore_version(sheet, version), to: Restore

  @doc false
  defdelegate restore_version(sheet, version, opts), to: Restore

  @doc false
  defdelegate restore_version(arg1, sheet, arg3, opts), to: Restore

  @doc "Returns whether Sheet version restore is enabled."
  defdelegate restore_enabled?(), to: Restore

  @doc false
  defdelegate restore_enabled?(arg1), to: Restore

  @doc false
  defdelegate ensure_restore_enabled(), to: Restore

  @doc false
  defdelegate ensure_restore_enabled(arg1), to: Restore

  @doc false
  defdelegate build_snapshot(sheet), to: SnapshotReader

  @doc false
  defdelegate snapshot_has_changes?(previous, current), to: SnapshotReader

  @doc false
  defdelegate snapshot_has_changes?(arg1, previous, current), to: SnapshotReader

  @doc false
  defdelegate next_version_number(sheet_id), to: History
end
