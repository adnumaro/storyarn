defmodule Storyarn.Scenes.Versioning do
  @moduledoc """
  Scene-owned entity version history.

  The module owns the complete Scene version lifecycle while deliberately
  sharing the existing SQL table and object-storage namespace. Its public
  surface is Scene-specific; internal discriminator clauses fail closed when a
  record from another entity type reaches the shared table.
  """

  alias Storyarn.Scenes.Scene
  alias Storyarn.Scenes.Versioning.Commands.NamedVersionCapacity
  alias Storyarn.Scenes.Versioning.Commands.Tracked
  alias Storyarn.Scenes.Versioning.Commands.VersionLifecycle
  alias Storyarn.Scenes.Versioning.EntityVersionRecord
  alias Storyarn.Scenes.Versioning.Execution.Restore
  alias Storyarn.Scenes.Versioning.Execution.SnapshotReader
  alias Storyarn.Scenes.Versioning.Queries.History

  @type version :: EntityVersionRecord.t()

  defdelegate can_create_named_version?(project_id, workspace_id),
    to: NamedVersionCapacity,
    as: :can_create?

  defdelegate record_version_panel_opened(scope, scene), to: Tracked
  defdelegate record_version_compared(scope, scene), to: Tracked
  defdelegate create_named_version(scope, scene, opts), to: Tracked

  defdelegate restore_tracked_version(scope, scene, version, opts),
    to: Tracked,
    as: :restore_version

  @doc false
  defdelegate set_current_version(scene, version_or_nil), to: VersionLifecycle

  @doc "Creates a durable Scene version."
  @spec create_version(Scene.t(), integer() | nil, keyword()) ::
          {:ok, version()} | {:error, term()}
  defdelegate create_version(scene, user_id, opts \\ []), to: VersionLifecycle

  @doc false
  defdelegate create_version(arg1, entity, project_id, user_id, opts \\ []),
    to: VersionLifecycle

  @doc "Creates an automatic version when the configured interval has elapsed."
  @spec maybe_create_version(Scene.t(), integer() | nil, keyword()) ::
          {:ok, version()}
          | {:skipped, :too_recent | :auto_versioning_disabled}
          | {:error, term()}
  defdelegate maybe_create_version(scene, user_id, opts \\ []), to: VersionLifecycle

  @doc false
  defdelegate maybe_create_version(arg1, entity, project_id, user_id, opts \\ []),
    to: VersionLifecycle

  @doc "Lists Scene versions newest first."
  @spec list_versions(integer(), keyword()) :: [version()]
  defdelegate list_versions(scene_id, opts \\ []), to: History

  @doc false
  defdelegate list_versions(arg1, scene_id, opts), to: History

  @doc "Gets one Scene version by its monotonic version number."
  @spec get_version(integer(), integer()) :: version() | nil
  defdelegate get_version(scene_id, version_number), to: History

  @doc false
  defdelegate get_version(arg1, scene_id, version_number), to: History

  @doc "Gets the most recent Scene version."
  @spec get_latest_version(integer()) :: version() | nil
  defdelegate get_latest_version(scene_id), to: History

  @doc false
  defdelegate get_latest_version(arg1, scene_id), to: History

  @doc "Counts persisted versions for a Scene."
  @spec count_versions(integer()) :: non_neg_integer()
  defdelegate count_versions(scene_id), to: History

  @doc false
  defdelegate count_versions(arg1, scene_id), to: History

  @doc "Returns the Scene version numbers immediately before and after the current number."
  @spec get_adjacent_version_numbers(integer(), integer()) ::
          {integer() | nil, integer() | nil}
  defdelegate get_adjacent_version_numbers(scene_id, current_number), to: History

  @doc false
  defdelegate get_adjacent_version_numbers(arg1, scene_id, current_number), to: History

  @doc "Counts Scene versions created after a timestamp."
  @spec count_versions_since(integer(), DateTime.t()) :: non_neg_integer()
  defdelegate count_versions_since(scene_id, since), to: History

  @doc false
  defdelegate count_versions_since(arg1, scene_id, since), to: History

  @doc "Updates the user-facing name and description of a Scene version."
  @spec update_version(map(), map()) :: {:ok, version()} | {:error, term()}
  defdelegate update_version(arg1, attrs), to: VersionLifecycle

  @doc "Deletes a Scene version and best-effort removes its snapshot object."
  @spec delete_version(map()) :: {:ok, version()} | {:error, term()}
  defdelegate delete_version(arg1), to: VersionLifecycle

  @doc "Loads and verifies the exact snapshot owned by a persisted Scene version."
  @spec load_version_snapshot(map()) :: {:ok, map()} | {:error, term()}
  defdelegate load_version_snapshot(arg1), to: SnapshotReader

  @doc """
  Decides the first restore step for a Scene.

  A missing or unreadable latest version is treated conservatively as unsaved
  work. Only a clean current Scene proceeds to loading the target and computing
  its conflict report.
  """
  @spec prepare_restore(Scene.t(), version()) ::
          {:ok, :unsaved_changes}
          | {:ok, {:ready, map()}}
          | {:error, :target_snapshot_unreadable}
  defdelegate prepare_restore(scene, target_version), to: Restore

  @doc "Loads the target snapshot and computes its Scene-owned restore conflict report."
  @spec prepare_restore_conflicts(Scene.t(), version()) ::
          {:ok, map()} | {:error, :target_snapshot_unreadable}
  defdelegate prepare_restore_conflicts(scene, target_version), to: Restore

  @doc "Detects Scene-owned restore conflicts without mutating state."
  defdelegate detect_restore_conflicts(snapshot, scene), to: Restore

  @doc false
  defdelegate detect_restore_conflicts(arg1, snapshot, scene), to: Restore

  @doc "Restores a Scene with a mandatory, verified safety version."
  @spec restore_version(Scene.t(), map(), keyword()) :: {:ok, Scene.t()} | {:error, term()}
  defdelegate restore_version(scene, version), to: Restore

  @doc false
  defdelegate restore_version(scene, version, opts), to: Restore

  @doc false
  defdelegate restore_version(arg1, scene, arg3, opts), to: Restore

  @doc "Returns whether Scene version restore is enabled."
  defdelegate restore_enabled?(), to: Restore

  @doc false
  defdelegate restore_enabled?(arg1), to: Restore

  @doc false
  defdelegate ensure_restore_enabled(), to: Restore

  @doc false
  defdelegate ensure_restore_enabled(arg1), to: Restore

  @doc false
  defdelegate build_snapshot(scene), to: SnapshotReader

  @doc false
  defdelegate snapshot_has_changes?(previous, current), to: SnapshotReader

  @doc false
  defdelegate snapshot_has_changes?(arg1, previous, current), to: SnapshotReader

  @doc false
  defdelegate next_version_number(scene_id), to: History
end
