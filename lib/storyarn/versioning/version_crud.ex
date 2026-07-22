defmodule Storyarn.Versioning.VersionCrud do
  @moduledoc """
  CRUD operations for entity versions.

  Handles creating, listing, and deleting versions for any entity type,
  with snapshots stored as compressed JSON in object storage.
  """

  use Gettext, backend: Storyarn.Gettext

  import Ecto.Query, warn: false

  alias Storyarn.Collaboration
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Versioning.EntityVersion
  alias Storyarn.Versioning.RestorePolicy
  alias Storyarn.Versioning.SnapshotDiff
  alias Storyarn.Versioning.SnapshotStorage
  alias Storyarn.Versioning.VersionNumberLock

  require Logger

  @builders %{
    "sheet" => Storyarn.Versioning.Builders.SheetBuilder,
    "flow" => Storyarn.Versioning.Builders.FlowBuilder,
    "scene" => Storyarn.Versioning.Builders.SceneBuilder
  }

  @entity_type_to_schema %{
    "sheet" => Storyarn.Sheets.Sheet,
    "flow" => Storyarn.Flows.Flow,
    "scene" => Storyarn.Scenes.Scene
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
    with :ok <- validate_entity_scope(entity_type, entity, project_id) do
      do_create_version(entity_type, entity, project_id, user_id, opts)
    end
  end

  defp do_create_version(entity_type, entity, project_id, user_id, opts) do
    builder = get_builder!(entity_type)
    snapshot = builder.build_snapshot(entity)

    title = Keyword.get(opts, :title)
    description = Keyword.get(opts, :description)
    is_auto = Keyword.get(opts, :is_auto, false)
    skip_diff = Keyword.get(opts, :skip_diff, false)

    params = %{
      entity_type: entity_type,
      entity_id: entity.id,
      project_id: project_id,
      user_id: user_id,
      snapshot: snapshot,
      title: title,
      description: description,
      is_auto: is_auto
    }

    VersionNumberLock.entity_version(entity_type, entity.id, fn ->
      {change_summary, change_details} =
        if skip_diff do
          {nil, nil}
        else
          generate_change_data(entity_type, entity.id, snapshot)
        end

      params =
        Map.merge(params, %{
          change_summary: change_summary,
          change_details: change_details
        })

      store_and_insert_version(params, _attempt = 1)
    end)
  end

  # Handles version numbering + storage + insert with retry on unique constraint race.
  @max_retries 3

  defp store_and_insert_version(params, attempt) do
    version_number = next_version_number(params.entity_type, params.entity_id)

    case SnapshotStorage.store_snapshot_with_checksum(
           params.project_id,
           params.entity_type,
           params.entity_id,
           version_number,
           params.snapshot,
           SnapshotStorage.unique_key_suffix()
         ) do
      {:ok, storage_key, size_bytes, checksum} ->
        case insert_version_record(
               params,
               version_number,
               storage_key,
               size_bytes,
               checksum
             ) do
          {:ok, version} ->
            {:ok, version}

          {:error, %Ecto.Changeset{errors: errors} = changeset} ->
            handle_insert_conflict(params, errors, changeset, attempt, storage_key)
        end

      {:error, _} = error ->
        error
    end
  end

  defp insert_version_record(params, version_number, storage_key, size_bytes, checksum) do
    %EntityVersion{}
    |> EntityVersion.changeset(%{
      entity_type: params.entity_type,
      entity_id: params.entity_id,
      project_id: params.project_id,
      version_number: version_number,
      title: params.title,
      description: params.description,
      change_summary: params.change_summary,
      change_details: params.change_details,
      storage_key: storage_key,
      snapshot_size_bytes: size_bytes,
      checksum: checksum,
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
    with :ok <- validate_entity_scope(entity_type, entity, project_id) do
      do_maybe_create_version(entity_type, entity, project_id, user_id, opts)
    end
  end

  defp do_maybe_create_version(entity_type, entity, project_id, user_id, opts) do
    min_interval = Keyword.get(opts, :min_interval, @default_min_interval_seconds)

    case get_latest_version(entity_type, entity.id) do
      nil ->
        create_version(entity_type, entity, project_id, user_id, opts)

      latest ->
        seconds_since_last =
          abs(DateTime.diff(TimeHelpers.now(), latest.inserted_at, :second))

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

    Repo.all(
      from(v in EntityVersion,
        where: v.entity_type == ^entity_type and v.entity_id == ^entity_id,
        order_by: [desc: v.version_number],
        limit: ^limit,
        offset: ^offset,
        preload: [:created_by]
      )
    )
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
    Repo.one(
      from(v in EntityVersion,
        where: v.entity_type == ^entity_type and v.entity_id == ^entity_id,
        order_by: [desc: v.version_number],
        limit: 1
      )
    )
  end

  @doc """
  Returns the total number of versions for an entity.
  """
  @spec count_versions(String.t(), integer()) :: integer()
  def count_versions(entity_type, entity_id) do
    Repo.one(
      from(v in EntityVersion, where: v.entity_type == ^entity_type and v.entity_id == ^entity_id, select: count(v.id))
    )
  end

  @doc """
  Returns the version numbers immediately adjacent to the given version number.

  Returns `{prev_number | nil, next_number | nil}` where prev is the highest
  version_number below `current`, and next is the lowest above.
  """
  @spec get_adjacent_version_numbers(String.t(), integer(), integer()) ::
          {integer() | nil, integer() | nil}
  def get_adjacent_version_numbers(entity_type, entity_id, current_number) do
    prev =
      Repo.one(
        from(v in EntityVersion,
          where: v.entity_type == ^entity_type and v.entity_id == ^entity_id and v.version_number < ^current_number,
          order_by: [desc: v.version_number],
          limit: 1,
          select: v.version_number
        )
      )

    next =
      Repo.one(
        from(v in EntityVersion,
          where: v.entity_type == ^entity_type and v.entity_id == ^entity_id and v.version_number > ^current_number,
          order_by: [asc: v.version_number],
          limit: 1,
          select: v.version_number
        )
      )

    {prev, next}
  end

  @doc """
  Counts versions created after the given timestamp for an entity.
  """
  @spec count_versions_since(String.t(), integer(), DateTime.t()) :: non_neg_integer()
  def count_versions_since(entity_type, entity_id, since) do
    Repo.aggregate(
      from(v in EntityVersion,
        where: v.entity_type == ^entity_type and v.entity_id == ^entity_id and v.inserted_at > ^since
      ),
      :count
    )
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
  Counts user-created named versions for a project.
  Excludes auto-generated restore safety snapshots (`is_auto: true` with title).
  """
  @spec count_named_versions(integer()) :: integer()
  def count_named_versions(project_id) do
    Repo.aggregate(
      from(v in EntityVersion, where: v.project_id == ^project_id and not is_nil(v.title) and v.is_auto == false),
      :count
    )
  end

  # ========== Delete ==========

  @doc """
  Deletes a version and its snapshot from storage.
  """
  @spec delete_version(EntityVersion.t()) :: {:ok, EntityVersion.t()} | {:error, term()}
  def delete_version(%EntityVersion{id: version_id}) when is_integer(version_id) and version_id > 0 do
    case Repo.get(EntityVersion, version_id) do
      %EntityVersion{} = persisted_version ->
        with :ok <- validate_version_storage_key(persisted_version) do
          delete_persisted_version(persisted_version)
        end

      nil ->
        {:error, :entity_version_not_found}
    end
  end

  def delete_version(%EntityVersion{}), do: {:error, :entity_version_not_found}

  defp delete_persisted_version(%EntityVersion{} = version) do
    case Repo.delete(version) do
      {:ok, deleted} ->
        # Best-effort cleanup of storage; don't fail the delete if storage cleanup fails
        case SnapshotStorage.delete_snapshot(version.storage_key) do
          :ok ->
            :ok

          {:error, reason} ->
            Logger.warning("Failed to delete version snapshot #{version.storage_key}: #{inspect(reason)}")
        end

        {:ok, deleted}

      error ->
        error
    end
  end

  # ========== Restore ==========

  @doc """
  Loads a version's snapshot from storage and restores the entity.

  Restore owns its transaction boundary because safety snapshots and asset
  compensation must be finalized only after the builder transaction commits.
  The target and mandatory pre-restore snapshots are both reloaded from their
  persisted records and verified by size and checksum before mutation.

  ## Options
  - `:user_id` - Actor recorded on the mandatory safety snapshot. When present,
    a best-effort post-restore version is also created.
  """
  @spec restore_version(String.t(), struct(), EntityVersion.t(), keyword()) ::
          {:ok, struct()} | {:error, term()}
  def restore_version(entity_type, entity, %EntityVersion{} = version, opts \\ []) do
    user_id = Keyword.get(opts, :user_id)
    restore_action = {:entity_version_restore, entity_type}

    with :ok <- RestorePolicy.ensure_enabled(restore_action),
         :ok <- validate_entity_scope(entity_type, entity, Map.get(entity, :project_id)),
         :ok <- require_restore_transaction_boundary(),
         builder = get_builder!(entity_type),
         {:ok, owned_version} <- fetch_owned_version(entity_type, entity, version),
         :ok <- validate_version_storage_key(owned_version),
         {:ok, snapshot, _actual_checksum} <- load_verified_version(owned_version),
         {:ok, pre_restore_version} <-
           create_and_verify_pre_restore_version(
             entity_type,
             entity,
             owned_version,
             user_id,
             opts
           ),
         :ok <-
           run_after_pre_restore_version_verified_hook(
             opts,
             pre_restore_version.record
           ) do
      snapshot = maybe_resolve_shortcut_collision(entity_type, entity, snapshot)

      builder_opts =
        opts
        |> Keyword.drop([
          :skip_pre_snapshot,
          :__pre_restore_version_fun,
          :__after_pre_restore_version_verified_hook
        ])
        |> Keyword.put(:restore_action, restore_action)
        |> Keyword.put(:pre_restore_snapshot, pre_restore_version.data)
        |> Keyword.put(
          :pre_restore_version_identity,
          pre_restore_version_identity(pre_restore_version.record)
        )

      case builder.restore_snapshot(entity, snapshot, builder_opts) do
        {:ok, updated_entity} ->
          log_snapshot_error(
            maybe_create_post_restore_snapshot(
              entity_type,
              updated_entity,
              entity,
              owned_version,
              user_id
            ),
            "post-restore",
            entity_type,
            entity.id
          )

          broadcast_dashboard_change(entity_type, updated_entity.project_id)
          {:ok, updated_entity}

        error ->
          error
      end
    end
  end

  defp require_restore_transaction_boundary do
    if Repo.in_transaction?(),
      do: {:error, :version_restore_requires_transaction_boundary},
      else: :ok
  end

  defp fetch_owned_version(entity_type, entity, %EntityVersion{id: version_id})
       when is_integer(version_id) and version_id > 0 do
    case Repo.get_by(EntityVersion,
           id: version_id,
           entity_type: entity_type,
           entity_id: entity.id,
           project_id: entity.project_id
         ) do
      %EntityVersion{} = owned_version -> {:ok, owned_version}
      nil -> {:error, :entity_version_scope_mismatch}
    end
  end

  defp fetch_owned_version(_entity_type, _entity, %EntityVersion{}), do: {:error, :entity_version_scope_mismatch}

  defp create_and_verify_pre_restore_version(entity_type, entity, target_version, user_id, opts) do
    create_opts = [
      title:
        dgettext(
          "versioning",
          "Before restore to v%{number}",
          number: target_version.version_number
        ),
      is_auto: true,
      skip_diff: true
    ]

    create_fun =
      Keyword.get(
        opts,
        :__pre_restore_version_fun,
        &create_version/5
      )

    result =
      with {:ok, %EntityVersion{} = created_version} <-
             safely_create_pre_restore_version(
               create_fun,
               entity_type,
               entity,
               user_id,
               create_opts
             ),
           {:ok, persisted_version} <-
             reload_pre_restore_version(
               entity_type,
               entity,
               created_version.id,
               user_id
             ),
           :ok <- validate_version_storage_key(persisted_version),
           {:ok, snapshot_data, _actual_checksum} <-
             load_verified_version(persisted_version) do
        {:ok, %{data: snapshot_data, record: persisted_version}}
      end

    case result do
      {:ok, %{data: _data, record: %EntityVersion{}}} = ok ->
        ok

      {:error, reason} ->
        Logger.warning("Failed to create or verify pre-restore entity version: #{inspect(reason)}")

        {:error, {:pre_restore_snapshot_failed, reason}}
    end
  end

  defp safely_create_pre_restore_version(create_fun, entity_type, entity, user_id, create_opts) do
    case create_fun.(entity_type, entity, entity.project_id, user_id, create_opts) do
      {:ok, %EntityVersion{}} = ok -> ok
      {:error, reason} -> {:error, reason}
      _other -> {:error, :invalid_pre_restore_version_result}
    end
  rescue
    exception ->
      Logger.error("Pre-restore entity version creation raised: #{Exception.message(exception)}")

      {:error, :pre_restore_version_exception}
  catch
    kind, reason ->
      Logger.error(
        "Pre-restore entity version creation failed " <>
          "kind=#{kind} reason=#{inspect(reason)}"
      )

      {:error, :pre_restore_version_failure}
  end

  defp reload_pre_restore_version(entity_type, entity, version_id, user_id) do
    case Repo.get_by(EntityVersion,
           id: version_id,
           entity_type: entity_type,
           entity_id: entity.id,
           project_id: entity.project_id
         ) do
      %EntityVersion{created_by_id: ^user_id} = version ->
        {:ok, version}

      %EntityVersion{} ->
        {:error, :pre_restore_version_actor_mismatch}

      nil ->
        {:error, :pre_restore_version_not_found}
    end
  end

  defp run_after_pre_restore_version_verified_hook(opts, version) do
    case Keyword.get(opts, :__after_pre_restore_version_verified_hook) do
      hook when is_function(hook, 1) ->
        hook.(version)
        :ok

      _hook ->
        :ok
    end
  end

  defp pre_restore_version_identity(%EntityVersion{} = version) do
    %{
      id: version.id,
      entity_type: version.entity_type,
      entity_id: version.entity_id,
      project_id: version.project_id,
      created_by_id: version.created_by_id,
      version_number: version.version_number,
      storage_key: version.storage_key,
      snapshot_size_bytes: version.snapshot_size_bytes,
      checksum: version.checksum
    }
  end

  defp validate_version_storage_key(%EntityVersion{} = version) do
    if SnapshotStorage.entity_key?(
         version.storage_key,
         version.project_id,
         version.entity_type,
         version.entity_id,
         version.version_number
       ) do
      :ok
    else
      {:error, :entity_version_storage_key_mismatch}
    end
  end

  defp load_verified_version(%EntityVersion{} = version) do
    SnapshotStorage.load_verified_snapshot(
      version.storage_key,
      version.snapshot_size_bytes,
      version.checksum
    )
  end

  defp maybe_create_post_restore_snapshot(_entity_type, _updated, _entity, _version, nil), do: :ok

  defp maybe_create_post_restore_snapshot(entity_type, updated_entity, entity, version, user_id) do
    create_version(entity_type, updated_entity, entity.project_id, user_id,
      title: dgettext("versioning", "Restored from v%{number}", number: version.version_number),
      is_auto: true,
      skip_diff: true
    )
  end

  defp broadcast_dashboard_change("flow", project_id), do: Collaboration.broadcast_dashboard_change(project_id, :flows)

  defp broadcast_dashboard_change("sheet", project_id), do: Collaboration.broadcast_dashboard_change(project_id, :sheets)

  defp broadcast_dashboard_change("scene", project_id), do: Collaboration.broadcast_dashboard_change(project_id, :scenes)

  defp broadcast_dashboard_change(_entity_type, _project_id), do: :ok

  @doc """
  Loads a version's snapshot from storage.
  """
  @spec load_version_snapshot(EntityVersion.t()) :: {:ok, map()} | {:error, term()}
  def load_version_snapshot(%EntityVersion{} = version) do
    with {:ok, persisted_version} <- fetch_persisted_version(version),
         :ok <- validate_version_storage_key(persisted_version),
         {:ok, snapshot, _actual_checksum} <-
           load_verified_version(persisted_version) do
      {:ok, snapshot}
    end
  end

  defp fetch_persisted_version(%EntityVersion{} = version) do
    case Repo.get_by(EntityVersion,
           id: version.id,
           entity_type: version.entity_type,
           entity_id: version.entity_id,
           project_id: version.project_id,
           version_number: version.version_number
         ) do
      %EntityVersion{} = persisted_version -> {:ok, persisted_version}
      nil -> {:error, :entity_version_not_found}
    end
  end

  # ========== Helpers ==========

  defp log_snapshot_error({:error, reason}, phase, entity_type, entity_id) do
    Logger.warning("Failed to create #{phase} snapshot for #{entity_type} #{entity_id}: #{inspect(reason)}")
  end

  defp log_snapshot_error(_result, _phase, _entity_type, _entity_id), do: :ok

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

  defp maybe_resolve_shortcut_collision(entity_type, entity, snapshot) do
    shortcut = snapshot["shortcut"]

    if shortcut && shortcut_taken?(entity_type, entity, shortcut) do
      suffix = 4 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)
      Map.put(snapshot, "shortcut", shortcut <> "-" <> suffix)
    else
      snapshot
    end
  end

  defp shortcut_taken?(entity_type, entity, shortcut) do
    schema = Map.fetch!(@entity_type_to_schema, entity_type)

    Repo.exists?(
      from(e in schema,
        where:
          e.shortcut == ^shortcut and e.project_id == ^entity.project_id and e.id != ^entity.id and is_nil(e.deleted_at)
      )
    )
  end

  defp validate_entity_scope(entity_type, entity, expected_project_id) do
    with {:ok, schema} <- Map.fetch(@entity_type_to_schema, entity_type),
         true <- is_struct(entity, schema),
         {:ok, actual_project_id} <- Map.fetch(entity, :project_id),
         true <-
           is_integer(expected_project_id) and expected_project_id > 0 and
             actual_project_id == expected_project_id do
      :ok
    else
      :error -> {:error, :unknown_entity_type}
      false -> {:error, :entity_scope_mismatch}
    end
  end

  defp generate_change_data(entity_type, entity_id, current_snapshot) do
    case get_latest_version(entity_type, entity_id) do
      nil ->
        {gettext("Initial version"), nil}

      previous ->
        case load_version_snapshot(previous) do
          {:ok, previous_snapshot} ->
            diff_result = SnapshotDiff.diff(entity_type, previous_snapshot, current_snapshot)
            summary = SnapshotDiff.format_summary(diff_result)
            details = serialize_change_details(diff_result)
            {summary, details}

          {:error, reason} ->
            Logger.warning("Failed to load previous snapshot for #{entity_type} #{entity_id}: #{inspect(reason)}")

            {gettext("Changes from previous version"), nil}
        end
    end
  end

  defp serialize_change_details(%{changes: [], stats: _}), do: nil

  defp serialize_change_details(%{changes: changes, stats: stats}) do
    %{
      "changes" =>
        Enum.map(changes, fn change ->
          %{
            "category" => to_string(change.category),
            "action" => to_string(change.action),
            "detail" => change.detail
          }
        end),
      "stats" => %{
        "added" => stats.added,
        "modified" => stats.modified,
        "removed" => stats.removed
      }
    }
  end
end
