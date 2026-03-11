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

  alias Storyarn.Versioning.{EntityVersion, VersionCrud}

  @type version :: EntityVersion.t()

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

  # ========== Delete ==========

  @doc """
  Deletes a version and its snapshot from storage.
  """
  defdelegate delete_version(version), to: VersionCrud

  # ========== Restore ==========

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
end
