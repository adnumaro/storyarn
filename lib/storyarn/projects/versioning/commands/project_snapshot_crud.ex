defmodule Storyarn.Projects.Versioning.ProjectSnapshotCrud do
  @moduledoc """
  Persistence primitives for canonical project snapshot lifecycle rows.

  ENG-79 exposes query, metadata, finalization, and remeasurement
  primitives. Capture orchestration, restore, deletion, recovery, and retention
  are owned by their later canonical lifecycle tickets.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Commercial
  alias Storyarn.Projects.Project
  alias Storyarn.Projects.Versioning.ProjectSnapshot
  alias Storyarn.Repo

  defguardp valid_accounting_generation(snapshot_id, generation)
            when is_integer(snapshot_id) and snapshot_id > 0 and is_integer(generation) and
                   generation > 0

  @doc "Lists project snapshots, ordered by version number descending."
  @spec list_snapshots(integer(), keyword()) :: [ProjectSnapshot.t()]
  def list_snapshots(project_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)

    Repo.all(
      from(snapshot in ProjectSnapshot,
        where: snapshot.project_id == ^project_id,
        order_by: [desc: snapshot.version_number],
        limit: ^limit,
        offset: ^offset,
        preload: [:created_by]
      )
    )
  end

  @doc "Gets a project snapshot by version number."
  @spec get_snapshot(integer(), integer()) :: ProjectSnapshot.t() | nil
  def get_snapshot(project_id, version_number) do
    Repo.get_by(ProjectSnapshot,
      project_id: project_id,
      version_number: version_number
    )
  end

  @doc "Gets a project snapshot by ID within its owning project."
  @spec get_snapshot_by_id(integer(), integer()) :: ProjectSnapshot.t() | nil
  def get_snapshot_by_id(project_id, id) do
    Repo.one(
      from(snapshot in ProjectSnapshot,
        where: snapshot.project_id == ^project_id and snapshot.id == ^id,
        preload: [:created_by]
      )
    )
  end

  @doc "Counts canonical project snapshot lifecycle rows for a project."
  @spec count_snapshots(integer()) :: non_neg_integer()
  def count_snapshots(project_id) do
    Repo.one(
      from(snapshot in ProjectSnapshot,
        where: snapshot.project_id == ^project_id,
        select: count(snapshot.id)
      )
    )
  end

  @doc "Updates user-editable snapshot metadata only."
  @spec update_snapshot(ProjectSnapshot.t(), map()) ::
          {:ok, ProjectSnapshot.t()} | {:error, Ecto.Changeset.t()}
  def update_snapshot(%ProjectSnapshot{} = snapshot, attrs) do
    snapshot
    |> ProjectSnapshot.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Finalizes a pending canonical object set inside its reservation commit.

  The matching snapshot-build reservation and workspace lock must already be
  owned by `StorageAccounting.commit/5`.
  """
  @spec finalize_object_set(pos_integer(), 0, map()) ::
          {:ok, ProjectSnapshot.t()} | {:error, term()}
  def finalize_object_set(snapshot_id, expected_generation, attrs)
      when is_integer(snapshot_id) and snapshot_id > 0 and expected_generation == 0 and is_map(attrs) do
    if Commercial.snapshot_storage_commit_context?(snapshot_id, "snapshot_build") do
      finalize_object_set_locked(snapshot_id, expected_generation, attrs)
    else
      {:error, :snapshot_storage_commit_context_required}
    end
  end

  def finalize_object_set(_snapshot_id, _expected_generation, _attrs), do: {:error, :invalid_snapshot_accounting_update}

  @doc """
  Reconfirms immutable full-snapshot accounting behind a workspace lock and
  generation fence. Object identity and inventory cannot change.
  """
  @spec remeasure_object_set(pos_integer(), pos_integer(), map()) ::
          {:ok, ProjectSnapshot.t()} | {:error, term()}
  def remeasure_object_set(snapshot_id, expected_generation, attrs)
      when valid_accounting_generation(snapshot_id, expected_generation) and is_map(attrs) do
    case snapshot_workspace_id(snapshot_id) do
      workspace_id when is_integer(workspace_id) ->
        Commercial.transact_with_workspace_lock(workspace_id, fn _workspace ->
          remeasure_object_set_locked(snapshot_id, expected_generation, attrs)
        end)

      nil ->
        {:error, :project_snapshot_not_found}
    end
  end

  def remeasure_object_set(_snapshot_id, _expected_generation, _attrs), do: {:error, :invalid_snapshot_accounting_update}

  @doc "Returns the next project snapshot version number."
  @spec next_version_number(integer()) :: pos_integer()
  def next_version_number(project_id) do
    query =
      from(snapshot in ProjectSnapshot,
        where: snapshot.project_id == ^project_id,
        select: max(snapshot.version_number)
      )

    (Repo.one(query) || 0) + 1
  end

  defp finalize_object_set_locked(snapshot_id, expected_generation, attrs) do
    {expected_lifecycle_generation, attrs} = Map.pop(attrs, :expected_lifecycle_generation)
    snapshot = lock_snapshot(snapshot_id)

    case snapshot do
      nil ->
        {:error, :project_snapshot_not_found}

      %ProjectSnapshot{
        accounting_generation: nil,
        accounted_size_bytes: nil,
        lifecycle_state: lifecycle_state,
        integrity_state: "unknown"
      } = snapshot
      when lifecycle_state in ["pending", "building", "verifying"] ->
        if expected_generation == 0 and
             lifecycle_generation_matches?(snapshot, expected_lifecycle_generation) do
          snapshot
          |> ProjectSnapshot.object_set_changeset(attrs)
          |> Repo.update(stale_error_field: :accounting_generation)
        else
          {:error, :stale_snapshot_accounting_measurement}
        end

      %ProjectSnapshot{} ->
        {:error, :invalid_snapshot_accounting_transition}
    end
  end

  defp lifecycle_generation_matches?(%ProjectSnapshot{lifecycle_generation: generation}, generation)
       when is_integer(generation), do: true

  defp lifecycle_generation_matches?(_snapshot, _expected), do: false

  defp remeasure_object_set_locked(snapshot_id, expected_generation, attrs) do
    case lock_snapshot(snapshot_id) do
      nil ->
        {:error, :project_snapshot_not_found}

      %ProjectSnapshot{accounting_generation: ^expected_generation, mode: "full"} = snapshot ->
        snapshot
        |> ProjectSnapshot.object_set_changeset(attrs)
        |> Repo.update(stale_error_field: :accounting_generation)

      %ProjectSnapshot{} ->
        {:error, :stale_snapshot_accounting_measurement}
    end
  end

  defp lock_snapshot(snapshot_id) do
    Repo.one(
      from(snapshot in ProjectSnapshot,
        where: snapshot.id == ^snapshot_id,
        lock: "FOR UPDATE"
      )
    )
  end

  defp snapshot_workspace_id(snapshot_id) do
    Repo.one(
      from(snapshot in ProjectSnapshot,
        join: project in Project,
        on: project.id == snapshot.project_id,
        where: snapshot.id == ^snapshot_id,
        select: project.workspace_id
      )
    )
  end
end
