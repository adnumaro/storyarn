defmodule Storyarn.Versioning.VersionCrud do
  @moduledoc """
  CRUD operations for entity versions.

  Handles creating, listing, and deleting versions for any entity type,
  with snapshots stored as compressed JSON in object storage.
  """

  import Ecto.Query, warn: false

  require Logger

  use Gettext, backend: StoryarnWeb.Gettext

  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Versioning.{EntityVersion, SnapshotStorage}

  @builders %{
    "sheet" => Storyarn.Versioning.Builders.SheetBuilder,
    "flow" => Storyarn.Versioning.Builders.FlowBuilder,
    "scene" => Storyarn.Versioning.Builders.SceneBuilder
  }

  # Default rate-limit interval: 10 minutes
  @default_min_interval_seconds 600

  # ========== Create ==========

  @doc """
  Creates a new version for the given entity.

  Builds a snapshot, stores it compressed in object storage, and creates
  a version record in the database.

  ## Options
  - `:title` - Custom title for manual versions
  - `:description` - Optional description
  - `:is_auto` - Whether this is an auto-generated version (default: false)
  """
  @spec create_version(String.t(), struct(), integer(), integer() | nil, keyword()) ::
          {:ok, EntityVersion.t()} | {:error, term()}
  def create_version(entity_type, entity, project_id, user_id, opts \\ []) do
    builder = get_builder!(entity_type)
    snapshot = builder.build_snapshot(entity)

    title = Keyword.get(opts, :title)
    description = Keyword.get(opts, :description)
    is_auto = Keyword.get(opts, :is_auto, false)

    change_summary =
      if title do
        nil
      else
        generate_change_summary(entity_type, entity.id, snapshot, builder)
      end

    params = %{
      entity_type: entity_type,
      entity_id: entity.id,
      project_id: project_id,
      user_id: user_id,
      snapshot: snapshot,
      title: title,
      description: description,
      change_summary: change_summary,
      is_auto: is_auto
    }

    store_and_insert_version(params, _attempt = 1)
  end

  # Handles version numbering + storage + insert with retry on unique constraint race.
  @max_retries 3

  defp store_and_insert_version(params, attempt) do
    version_number = next_version_number(params.entity_type, params.entity_id)

    case SnapshotStorage.store_snapshot(
           params.project_id,
           params.entity_type,
           params.entity_id,
           version_number,
           params.snapshot
         ) do
      {:ok, storage_key, size_bytes} ->
        case insert_version_record(params, version_number, storage_key, size_bytes) do
          {:ok, version} ->
            {:ok, version}

          {:error, %Ecto.Changeset{errors: errors} = changeset} ->
            handle_insert_conflict(params, errors, changeset, attempt, storage_key)
        end

      {:error, _} = error ->
        error
    end
  end

  defp insert_version_record(params, version_number, storage_key, size_bytes) do
    %EntityVersion{}
    |> EntityVersion.changeset(%{
      entity_type: params.entity_type,
      entity_id: params.entity_id,
      project_id: params.project_id,
      version_number: version_number,
      title: params.title,
      description: params.description,
      change_summary: params.change_summary,
      storage_key: storage_key,
      snapshot_size_bytes: size_bytes,
      is_auto: params.is_auto,
      created_by_id: params.user_id
    })
    |> Repo.insert()
  end

  defp handle_insert_conflict(params, errors, changeset, attempt, storage_key) do
    # Clean up orphaned snapshot from the failed attempt
    SnapshotStorage.delete_snapshot(storage_key)

    if version_number_conflict?(errors) and attempt < @max_retries do
      store_and_insert_version(params, attempt + 1)
    else
      {:error, changeset}
    end
  end

  defp version_number_conflict?(errors) do
    Enum.any?(errors, fn
      {:version_number, {_, opts}} -> Keyword.get(opts, :constraint) == :unique
      _ -> false
    end)
  end

  @doc """
  Creates a version if enough time has passed since the last version.

  Returns `{:ok, version}`, `{:skipped, :too_recent}`, or `{:error, reason}`.
  """
  @spec maybe_create_version(String.t(), struct(), integer(), integer() | nil, keyword()) ::
          {:ok, EntityVersion.t()} | {:skipped, :too_recent} | {:error, term()}
  def maybe_create_version(entity_type, entity, project_id, user_id, opts \\ []) do
    min_interval = Keyword.get(opts, :min_interval, @default_min_interval_seconds)

    case get_latest_version(entity_type, entity.id) do
      nil ->
        create_version(entity_type, entity, project_id, user_id, opts)

      latest ->
        seconds_since_last =
          DateTime.diff(TimeHelpers.now(), latest.inserted_at, :second)

        if seconds_since_last >= min_interval do
          create_version(entity_type, entity, project_id, user_id, opts)
        else
          {:skipped, :too_recent}
        end
    end
  end

  # ========== Queries ==========

  @doc """
  Lists versions for an entity, ordered by version number descending.

  ## Options
  - `:limit` - Maximum versions to return (default: 50)
  - `:offset` - Number of versions to skip (default: 0)
  """
  @spec list_versions(String.t(), integer(), keyword()) :: [EntityVersion.t()]
  def list_versions(entity_type, entity_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)

    from(v in EntityVersion,
      where: v.entity_type == ^entity_type and v.entity_id == ^entity_id,
      order_by: [desc: v.version_number],
      limit: ^limit,
      offset: ^offset,
      preload: [:created_by]
    )
    |> Repo.all()
  end

  @doc """
  Gets a specific version by entity type, entity ID, and version number.
  """
  @spec get_version(String.t(), integer(), integer()) :: EntityVersion.t() | nil
  def get_version(entity_type, entity_id, version_number) do
    Repo.get_by(EntityVersion,
      entity_type: entity_type,
      entity_id: entity_id,
      version_number: version_number
    )
  end

  @doc """
  Gets the latest version for an entity.
  """
  @spec get_latest_version(String.t(), integer()) :: EntityVersion.t() | nil
  def get_latest_version(entity_type, entity_id) do
    from(v in EntityVersion,
      where: v.entity_type == ^entity_type and v.entity_id == ^entity_id,
      order_by: [desc: v.version_number],
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
  Returns the total number of versions for an entity.
  """
  @spec count_versions(String.t(), integer()) :: integer()
  def count_versions(entity_type, entity_id) do
    from(v in EntityVersion,
      where: v.entity_type == ^entity_type and v.entity_id == ^entity_id,
      select: count(v.id)
    )
    |> Repo.one()
  end

  # ========== Update ==========

  @doc """
  Updates a version's title and description.
  Used to promote auto-snapshots to named versions.
  """
  @spec update_version(EntityVersion.t(), map()) ::
          {:ok, EntityVersion.t()} | {:error, Ecto.Changeset.t()}
  def update_version(%EntityVersion{} = version, attrs) do
    version
    |> EntityVersion.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Counts versions with a non-nil title for a project.
  Includes both manual versions and promoted auto-snapshots.
  """
  @spec count_named_versions(integer()) :: integer()
  def count_named_versions(project_id) do
    from(v in EntityVersion,
      where: v.project_id == ^project_id and not is_nil(v.title)
    )
    |> Repo.aggregate(:count)
  end

  # ========== Delete ==========

  @doc """
  Deletes a version and its snapshot from storage.
  """
  @spec delete_version(EntityVersion.t()) :: {:ok, EntityVersion.t()} | {:error, term()}
  def delete_version(%EntityVersion{} = version) do
    case Repo.delete(version) do
      {:ok, deleted} ->
        # Best-effort cleanup of storage; don't fail the delete if storage cleanup fails
        case SnapshotStorage.delete_snapshot(version.storage_key) do
          :ok ->
            :ok

          {:error, reason} ->
            Logger.warning(
              "Failed to delete version snapshot #{version.storage_key}: #{inspect(reason)}"
            )
        end

        {:ok, deleted}

      error ->
        error
    end
  end

  # ========== Restore ==========

  @doc """
  Loads a version's snapshot from storage and restores the entity.

  ## Options
  - `:user_id` - If provided, creates a pre-restore safety snapshot and a post-restore version entry
  """
  @spec restore_version(String.t(), struct(), EntityVersion.t(), keyword()) ::
          {:ok, struct()} | {:error, term()}
  def restore_version(entity_type, entity, %EntityVersion{} = version, opts \\ []) do
    builder = get_builder!(entity_type)
    user_id = Keyword.get(opts, :user_id)

    with {:ok, snapshot} <- SnapshotStorage.load_snapshot(version.storage_key) do
      maybe_create_pre_restore_snapshot(entity_type, entity, version, user_id)
      snapshot = maybe_resolve_shortcut_collision(entity_type, entity, snapshot)

      case builder.restore_snapshot(entity, snapshot, opts) do
        {:ok, updated_entity} ->
          maybe_create_post_restore_snapshot(
            entity_type,
            updated_entity,
            entity,
            version,
            user_id
          )

          {:ok, updated_entity}

        error ->
          error
      end
    end
  end

  defp maybe_create_pre_restore_snapshot(_entity_type, _entity, _version, nil), do: :noop

  defp maybe_create_pre_restore_snapshot(entity_type, entity, version, user_id) do
    create_version(entity_type, entity, entity.project_id, user_id,
      title:
        dgettext("versioning", "Before restore to v%{number}", number: version.version_number),
      is_auto: false
    )
  end

  defp maybe_create_post_restore_snapshot(_entity_type, _updated, _entity, _version, nil),
    do: :noop

  defp maybe_create_post_restore_snapshot(entity_type, updated_entity, entity, version, user_id) do
    create_version(entity_type, updated_entity, entity.project_id, user_id,
      title: dgettext("versioning", "Restored from v%{number}", number: version.version_number),
      is_auto: false
    )
  end

  @doc """
  Loads a version's snapshot from storage.
  """
  @spec load_version_snapshot(EntityVersion.t()) :: {:ok, map()} | {:error, term()}
  def load_version_snapshot(%EntityVersion{} = version) do
    SnapshotStorage.load_snapshot(version.storage_key)
  end

  # ========== Helpers ==========

  @doc """
  Returns the next version number for an entity.
  """
  @spec next_version_number(String.t(), integer()) :: integer()
  def next_version_number(entity_type, entity_id) do
    query =
      from(v in EntityVersion,
        where: v.entity_type == ^entity_type and v.entity_id == ^entity_id,
        select: max(v.version_number)
      )

    (Repo.one(query) || 0) + 1
  end

  @doc """
  Returns the builder module for the given entity type.
  """
  @spec get_builder!(String.t()) :: module()
  def get_builder!(entity_type) do
    case Map.fetch(@builders, entity_type) do
      {:ok, builder} -> builder
      :error -> raise ArgumentError, "unknown entity type: #{inspect(entity_type)}"
    end
  end

  @entity_type_to_schema %{
    "sheet" => Storyarn.Sheets.Sheet,
    "flow" => Storyarn.Flows.Flow,
    "scene" => Storyarn.Scenes.Scene
  }

  defp maybe_resolve_shortcut_collision(entity_type, entity, snapshot) do
    shortcut = snapshot["shortcut"]

    if shortcut && shortcut_taken?(entity_type, entity, shortcut) do
      Map.put(snapshot, "shortcut", shortcut <> "-restored")
    else
      snapshot
    end
  end

  defp shortcut_taken?(entity_type, entity, shortcut) do
    schema = Map.fetch!(@entity_type_to_schema, entity_type)

    from(e in schema,
      where:
        e.shortcut == ^shortcut and
          e.project_id == ^entity.project_id and
          e.id != ^entity.id and
          is_nil(e.deleted_at)
    )
    |> Repo.exists?()
  end

  defp generate_change_summary(entity_type, entity_id, current_snapshot, builder) do
    case get_latest_version(entity_type, entity_id) do
      nil ->
        gettext("Initial version")

      previous ->
        case SnapshotStorage.load_snapshot(previous.storage_key) do
          {:ok, previous_snapshot} ->
            builder.diff_snapshots(previous_snapshot, current_snapshot)

          {:error, _} ->
            gettext("Changes from previous version")
        end
    end
  end
end
