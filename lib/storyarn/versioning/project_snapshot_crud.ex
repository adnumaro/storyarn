defmodule Storyarn.Versioning.ProjectSnapshotCrud do
  @moduledoc """
  CRUD operations for project-level snapshots.

  Handles creating, listing, restoring, and deleting project snapshots,
  with compressed JSON stored in object storage.
  """

  import Ecto.Query, warn: false

  require Logger

  use Gettext, backend: Storyarn.Gettext

  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Versioning.Builders.ProjectSnapshotBuilder
  alias Storyarn.Versioning.{ProjectSnapshot, SnapshotStorage}

  # Version number uses optimistic concurrency: compute max+1, insert, retry on
  # unique constraint violation. Matches the pattern in VersionCrud.
  @max_retries 3

  # ========== Create ==========

  @doc """
  Creates a new project snapshot.

  Builds a full snapshot of all project entities, stores it compressed in
  object storage, and creates a record in the database.

  ## Options
  - `:title` - Optional title for the snapshot
  - `:description` - Optional description
  """
  @spec create_snapshot(integer(), integer() | nil, keyword()) ::
          {:ok, ProjectSnapshot.t()} | {:error, term()}
  def create_snapshot(project_id, user_id, opts \\ []) do
    snapshot = ProjectSnapshotBuilder.build_snapshot(project_id)

    params = %{
      project_id: project_id,
      user_id: user_id,
      snapshot: snapshot,
      entity_counts: snapshot["entity_counts"],
      title: Keyword.get(opts, :title),
      description: Keyword.get(opts, :description),
      is_auto: Keyword.get(opts, :is_auto, false)
    }

    store_and_insert_snapshot(params, _attempt = 1)
  end

  defp store_and_insert_snapshot(params, attempt) do
    version_number = next_version_number(params.project_id)

    storage_key =
      "projects/#{params.project_id}/snapshots/project/#{version_number}.json.gz"

    case store_snapshot(storage_key, params.snapshot) do
      {:ok, size_bytes} ->
        case insert_snapshot_record(params, version_number, storage_key, size_bytes) do
          {:ok, snapshot} ->
            {:ok, snapshot}

          {:error, %Ecto.Changeset{errors: errors} = changeset} ->
            handle_insert_conflict(params, errors, changeset, attempt, storage_key)
        end

      {:error, _} = error ->
        error
    end
  end

  defp store_snapshot(key, snapshot) do
    SnapshotStorage.store_raw(key, snapshot)
  end

  defp insert_snapshot_record(params, version_number, storage_key, size_bytes) do
    %ProjectSnapshot{}
    |> ProjectSnapshot.changeset(%{
      project_id: params.project_id,
      version_number: version_number,
      title: params.title,
      description: params.description,
      storage_key: storage_key,
      snapshot_size_bytes: size_bytes,
      entity_counts: params.entity_counts,
      created_by_id: params.user_id,
      is_auto: params.is_auto
    })
    |> Repo.insert()
  end

  defp handle_insert_conflict(params, errors, changeset, attempt, storage_key) do
    SnapshotStorage.delete_snapshot(storage_key)

    if version_number_conflict?(errors) and attempt < @max_retries do
      store_and_insert_snapshot(params, attempt + 1)
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

  # ========== Queries ==========

  @doc """
  Lists project snapshots, ordered by version number descending.

  ## Options
  - `:limit` - Maximum snapshots to return (default: 50)
  - `:offset` - Number of snapshots to skip (default: 0)
  """
  @spec list_snapshots(integer(), keyword()) :: [ProjectSnapshot.t()]
  def list_snapshots(project_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)

    from(s in ProjectSnapshot,
      where: s.project_id == ^project_id,
      order_by: [desc: s.version_number],
      limit: ^limit,
      offset: ^offset,
      preload: [:created_by]
    )
    |> Repo.all()
  end

  @doc """
  Gets a specific project snapshot by version number.
  """
  @spec get_snapshot(integer(), integer()) :: ProjectSnapshot.t() | nil
  def get_snapshot(project_id, version_number) do
    Repo.get_by(ProjectSnapshot,
      project_id: project_id,
      version_number: version_number
    )
  end

  @doc """
  Gets a project snapshot by ID.
  """
  @spec get_snapshot_by_id(integer(), integer()) :: ProjectSnapshot.t() | nil
  def get_snapshot_by_id(project_id, id) do
    from(s in ProjectSnapshot,
      where: s.project_id == ^project_id and s.id == ^id,
      preload: [:created_by]
    )
    |> Repo.one()
  end

  @doc """
  Counts project snapshots for billing limit checks.
  """
  @spec count_snapshots(integer()) :: integer()
  def count_snapshots(project_id) do
    from(s in ProjectSnapshot,
      where: s.project_id == ^project_id,
      select: count(s.id)
    )
    |> Repo.one()
  end

  # ========== Update ==========

  @doc """
  Updates a snapshot's title and description.
  """
  @spec update_snapshot(ProjectSnapshot.t(), map()) ::
          {:ok, ProjectSnapshot.t()} | {:error, Ecto.Changeset.t()}
  def update_snapshot(%ProjectSnapshot{} = snapshot, attrs) do
    snapshot
    |> ProjectSnapshot.update_changeset(attrs)
    |> Repo.update()
  end

  # ========== Delete ==========

  @doc """
  Deletes a snapshot and its storage file (best-effort cleanup).
  """
  @spec delete_snapshot(ProjectSnapshot.t()) ::
          {:ok, ProjectSnapshot.t()} | {:error, term()}
  def delete_snapshot(%ProjectSnapshot{} = snapshot) do
    case Repo.delete(snapshot) do
      {:ok, deleted} ->
        case SnapshotStorage.delete_snapshot(snapshot.storage_key) do
          :ok ->
            :ok

          {:error, reason} ->
            Logger.warning(
              "Failed to delete project snapshot #{snapshot.storage_key}: #{inspect(reason)}"
            )
        end

        {:ok, deleted}

      error ->
        error
    end
  end

  # ========== Restore ==========

  @doc """
  Loads a snapshot from storage and restores all project entities.

  Creates pre/post safety snapshots outside the restore transaction.
  This is intentional: safety snapshots are best-effort and should not
  block the restore if they fail. An orphan pre-restore snapshot may
  exist if the restore transaction itself fails — this is acceptable
  as it still captures the project's state before the attempt.

  Safety snapshots bypass billing limits intentionally — they are
  system-generated recovery aids, not user-initiated snapshots.

  ## Options
  - `:user_id` - User performing the restore
  """
  @spec restore_snapshot(integer(), ProjectSnapshot.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def restore_snapshot(project_id, %ProjectSnapshot{} = snapshot, opts \\ []) do
    user_id = Keyword.get(opts, :user_id)

    with {:ok, snapshot_data} <- SnapshotStorage.load_snapshot(snapshot.storage_key) do
      maybe_create_pre_restore_snapshot(project_id, snapshot, user_id)

      case ProjectSnapshotBuilder.restore_snapshot(project_id, snapshot_data, opts) do
        {:ok, result} ->
          maybe_create_post_restore_snapshot(project_id, snapshot, user_id)
          {:ok, result}

        {:error, _} = error ->
          error
      end
    end
  end

  defp maybe_create_pre_restore_snapshot(_project_id, _snapshot, nil), do: :noop

  defp maybe_create_pre_restore_snapshot(project_id, snapshot, user_id) do
    case create_snapshot(project_id, user_id,
           title:
             dgettext("versioning", "Before restore to project snapshot v%{number}",
               number: snapshot.version_number
             )
         ) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.warning("Failed to create pre-restore safety snapshot: #{inspect(reason)}")
    end
  end

  defp maybe_create_post_restore_snapshot(_project_id, _snapshot, nil), do: :noop

  defp maybe_create_post_restore_snapshot(project_id, snapshot, user_id) do
    case create_snapshot(project_id, user_id,
           title:
             dgettext("versioning", "Restored from project snapshot v%{number}",
               number: snapshot.version_number
             )
         ) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.warning("Failed to create post-restore snapshot: #{inspect(reason)}")
    end
  end

  # ========== Pruning ==========

  @doc """
  Deletes the oldest auto-generated snapshot for a project.
  Only prunes `is_auto: true` snapshots, never manual ones.
  """
  @spec prune_auto_snapshots(integer()) :: :ok
  def prune_auto_snapshots(project_id) do
    oldest_auto =
      from(s in ProjectSnapshot,
        where: s.project_id == ^project_id and s.is_auto == true,
        order_by: [asc: s.version_number],
        limit: 1
      )
      |> Repo.one()

    if oldest_auto do
      case delete_snapshot(oldest_auto) do
        {:ok, _} ->
          Logger.info(
            "Pruned auto snapshot v#{oldest_auto.version_number} for project #{project_id}"
          )

        {:error, reason} ->
          Logger.warning("Failed to prune auto snapshot: #{inspect(reason)}")
      end
    end

    :ok
  end

  @doc """
  Deletes all snapshots for a project that are older than the given number of days.
  Only prunes `is_auto: true` snapshots; manual snapshots are never auto-pruned.
  Returns the number of snapshots deleted.
  """
  @spec prune_expired_snapshots(integer(), integer()) :: integer()
  def prune_expired_snapshots(project_id, retention_days) do
    cutoff =
      TimeHelpers.now()
      |> DateTime.add(-retention_days * 86_400, :second)

    expired =
      from(s in ProjectSnapshot,
        where:
          s.project_id == ^project_id and
            s.is_auto == true and
            s.inserted_at < ^cutoff,
        order_by: [asc: s.version_number]
      )
      |> Repo.all()

    Enum.reduce(expired, 0, fn snapshot, count ->
      case delete_snapshot(snapshot) do
        {:ok, _} ->
          Logger.info(
            "Pruned expired snapshot v#{snapshot.version_number} for project #{project_id}"
          )

          count + 1

        {:error, reason} ->
          Logger.warning("Failed to prune expired snapshot: #{inspect(reason)}")
          count
      end
    end)
  end

  # ========== Helpers ==========

  @doc """
  Returns the next version number for project snapshots.
  """
  @spec next_version_number(integer()) :: integer()
  def next_version_number(project_id) do
    query =
      from(s in ProjectSnapshot,
        where: s.project_id == ^project_id,
        select: max(s.version_number)
      )

    (Repo.one(query) || 0) + 1
  end
end
