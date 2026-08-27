defmodule Storyarn.Flows.Versioning.Commands.VersionLifecycle do
  @moduledoc false

  use Gettext, backend: Storyarn.Gettext

  import Ecto.Query, warn: false

  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.Versioning.Commands.NamedVersionCapacity
  alias Storyarn.Flows.Versioning.EntityVersionRecord
  alias Storyarn.Flows.Versioning.Execution.SnapshotReader
  alias Storyarn.Flows.Versioning.FlowSnapshot
  alias Storyarn.Flows.Versioning.Projections.ProjectRecord
  alias Storyarn.Flows.Versioning.Queries.History
  alias Storyarn.Flows.Versioning.SnapshotStorage
  alias Storyarn.Flows.Versioning.VersionNumberLock
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Repo

  require Logger

  @entity_type "flow"
  @default_min_interval_seconds 600
  @max_insert_retries 3

  @type version :: EntityVersionRecord.t()

  def set_current_version(%Flow{} = flow, version_or_nil) do
    version_id = if version_or_nil, do: version_or_nil.id

    flow
    |> Flow.version_changeset(%{current_version_id: version_id})
    |> Repo.update()
  end

  @spec create_version(Flow.t(), integer() | nil, keyword()) ::
          {:ok, version()} | {:error, term()}
  def create_version(%Flow{} = flow, user_id, opts \\ []) do
    create_version(@entity_type, flow, flow.project_id, user_id, opts)
  end

  def create_version(entity_type, entity, project_id, user_id, opts \\ [])

  def create_version(@entity_type, %Flow{} = flow, project_id, user_id, opts) do
    with :ok <- validate_flow_scope(flow, project_id),
         :ok <- validate_actor_id(user_id) do
      snapshot = FlowSnapshot.build(flow)
      create_from_snapshot(flow, project_id, user_id, snapshot, opts)
    end
  end

  def create_version(_entity_type, _entity, _project_id, _user_id, _opts), do: {:error, :entity_scope_mismatch}

  @spec maybe_create_version(Flow.t(), integer() | nil, keyword()) ::
          {:ok, version()}
          | {:skipped, :too_recent | :auto_versioning_disabled}
          | {:error, term()}
  def maybe_create_version(%Flow{} = flow, user_id, opts \\ []) do
    opts = Keyword.put_new(opts, :is_auto, true)

    if Keyword.get(opts, :is_auto) and not auto_versioning_enabled?(flow.project_id) do
      {:skipped, :auto_versioning_disabled}
    else
      maybe_create_version(@entity_type, flow, flow.project_id, user_id, opts)
    end
  end

  def maybe_create_version(entity_type, entity, project_id, user_id, opts \\ [])

  def maybe_create_version(@entity_type, %Flow{} = flow, project_id, user_id, opts) do
    with :ok <- validate_flow_scope(flow, project_id),
         :ok <- validate_actor_id(user_id) do
      min_interval = Keyword.get(opts, :min_interval, @default_min_interval_seconds)
      maybe_create_version_if_due(flow, project_id, user_id, opts, min_interval)
    end
  end

  def maybe_create_version(_entity_type, _entity, _project_id, _user_id, _opts), do: {:error, :entity_scope_mismatch}

  @spec update_version(map(), map()) :: {:ok, version()} | {:error, term()}
  def update_version(%{id: version_id}, attrs) when is_integer(version_id) and is_map(attrs) do
    case version_project_id(version_id) do
      nil ->
        {:error, :entity_version_not_found}

      project_id ->
        fn -> update_locked_version_by_id(project_id, version_id, attrs) end
        |> Repo.transaction()
        |> normalize_limit_error()
    end
  end

  def update_version(_version, _attrs), do: {:error, :entity_version_not_found}

  @spec delete_version(map()) :: {:ok, version()} | {:error, term()}
  def delete_version(%{id: version_id}) when is_integer(version_id) and version_id > 0 do
    case Repo.get_by(EntityVersionRecord, id: version_id, entity_type: @entity_type) do
      %EntityVersionRecord{} = version ->
        delete_persisted_version(version)

      nil ->
        {:error, :entity_version_not_found}
    end
  end

  def delete_version(_version), do: {:error, :entity_version_not_found}

  defp validate_flow_scope(%Flow{id: id, project_id: project_id}, project_id)
       when is_integer(id) and id > 0 and is_integer(project_id) and project_id > 0 do
    case Repo.get(Flow, id) do
      %Flow{project_id: ^project_id, deleted_at: nil} -> :ok
      _flow -> {:error, :entity_scope_mismatch}
    end
  end

  defp validate_flow_scope(_flow, _project_id), do: {:error, :entity_scope_mismatch}

  defp validate_actor_id(nil), do: :ok
  defp validate_actor_id(id) when is_integer(id) and id > 0, do: :ok
  defp validate_actor_id(_id), do: {:error, :invalid_version_actor}

  defp create_from_snapshot(flow, project_id, user_id, snapshot, opts) do
    flow.id
    |> VersionNumberLock.run(fn ->
      create_from_snapshot_locked(flow, project_id, user_id, snapshot, opts)
    end)
    |> normalize_limit_error()
  end

  defp create_from_snapshot_locked(flow, project_id, user_id, snapshot, opts) do
    case ensure_named_version_capacity(project_id, opts) do
      :ok ->
        {change_summary, change_details} = change_data(flow.id, snapshot, opts)

        params = %{
          entity_id: flow.id,
          project_id: project_id,
          created_by_id: user_id,
          title: Keyword.get(opts, :title),
          description: Keyword.get(opts, :description),
          is_auto: Keyword.get(opts, :is_auto, false),
          change_summary: change_summary,
          change_details: change_details,
          snapshot: snapshot
        }

        store_and_insert(params, 1)

      {:error, reason, metadata} ->
        {:error, {reason, metadata}}
    end
  end

  defp store_and_insert(params, attempt) do
    version_number = History.next_version_number(params.entity_id)

    with {:ok, storage_key, size_bytes, checksum} <-
           SnapshotStorage.store_snapshot(
             params.project_id,
             params.entity_id,
             version_number,
             params.snapshot
           ) do
      insert_stored_version(params, version_number, storage_key, size_bytes, checksum, attempt)
    end
  end

  defp insert_stored_version(params, version_number, storage_key, size_bytes, checksum, attempt) do
    attrs = %{
      entity_type: @entity_type,
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
      created_by_id: params.created_by_id
    }

    result = %EntityVersionRecord{} |> EntityVersionRecord.create_changeset(attrs) |> Repo.insert()
    handle_version_insert(result, params, attempt, storage_key)
  end

  defp handle_version_insert({:ok, _version} = result, _params, _attempt, _storage_key), do: result

  defp handle_version_insert({:error, changeset} = error, params, attempt, storage_key) do
    _cleanup_result = SnapshotStorage.delete(storage_key)

    if version_number_conflict?(changeset) and attempt < @max_insert_retries,
      do: store_and_insert(params, attempt + 1),
      else: error
  end

  defp maybe_create_version_if_due(flow, project_id, user_id, opts, min_interval) do
    if version_due?(History.get_latest_version(flow.id), min_interval) do
      snapshot = FlowSnapshot.build(flow)

      flow.id
      |> VersionNumberLock.run(fn ->
        create_version_if_due_locked(
          flow,
          project_id,
          user_id,
          snapshot,
          opts,
          min_interval,
          History.get_latest_version(flow.id)
        )
      end)
      |> normalize_maybe_create_result()
    else
      {:skipped, :too_recent}
    end
  end

  defp create_version_if_due_locked(flow, project_id, user_id, snapshot, opts, min_interval, latest) do
    if version_due?(latest, min_interval),
      do: create_from_snapshot_locked(flow, project_id, user_id, snapshot, opts),
      else: {:ok, {:skipped, :too_recent}}
  end

  defp version_due?(nil, _min_interval), do: true

  defp version_due?(latest, min_interval) do
    abs(DateTime.diff(TimeHelpers.now(), latest.inserted_at, :second)) >= min_interval
  end

  defp normalize_maybe_create_result({:ok, {:skipped, reason}}), do: {:skipped, reason}
  defp normalize_maybe_create_result(result), do: normalize_limit_error(result)

  defp version_project_id(version_id) do
    Repo.one(
      from(version in EntityVersionRecord,
        where: version.id == ^version_id and version.entity_type == @entity_type,
        select: version.project_id
      )
    )
  end

  defp update_locked_version_by_id(project_id, version_id, attrs) do
    with {:ok, project} <- NamedVersionCapacity.lock_project(project_id),
         %EntityVersionRecord{} = version <- lock_version(version_id, project_id) do
      persist_locked_version(version, project, attrs)
    else
      nil -> Repo.rollback(:entity_version_not_found)
      {:error, reason, metadata} -> Repo.rollback({reason, metadata})
    end
  end

  defp lock_version(version_id, project_id) do
    Repo.one(
      from(version in EntityVersionRecord,
        where:
          version.id == ^version_id and version.entity_type == @entity_type and
            version.project_id == ^project_id,
        lock: "FOR UPDATE"
      )
    )
  end

  defp persist_locked_version(version, project, attrs) do
    changeset = EntityVersionRecord.update_changeset(version, attrs)

    with true <- changeset.valid?,
         :ok <- ensure_promotion_capacity(version, project),
         {:ok, updated} <- Repo.update(changeset) do
      updated
    else
      false -> Repo.rollback(changeset)
      {:error, reason, metadata} -> Repo.rollback({reason, metadata})
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp ensure_named_version_capacity(project_id, opts) do
    if named_version?(Keyword.get(opts, :title), Keyword.get(opts, :is_auto, false)),
      do: NamedVersionCapacity.ensure_capacity(project_id),
      else: :ok
  end

  defp ensure_promotion_capacity(%EntityVersionRecord{} = version, project) do
    if named_version?(version.title, version.is_auto),
      do: :ok,
      else: NamedVersionCapacity.ensure_capacity(project)
  end

  defp named_version?(title, false), do: not is_nil(title)
  defp named_version?(_title, _is_auto), do: false

  defp normalize_limit_error({:error, {:limit_reached, metadata}}), do: {:error, :limit_reached, metadata}
  defp normalize_limit_error(result), do: result

  defp delete_persisted_version(version) do
    with :ok <- SnapshotReader.validate_storage_key(version),
         {:ok, deleted} <- Repo.delete(version) do
      cleanup_deleted_snapshot(version.storage_key)
      {:ok, deleted}
    end
  end

  defp cleanup_deleted_snapshot(storage_key) do
    case SnapshotStorage.delete(storage_key) do
      :ok -> :ok
      {:error, reason} -> Logger.warning("Failed to delete Flow version snapshot: #{inspect(reason)}")
    end
  end

  defp auto_versioning_enabled?(project_id) do
    case Repo.get(ProjectRecord, project_id) do
      %ProjectRecord{deleted_at: nil, auto_version_flows: enabled?} -> enabled? == true
      _project -> false
    end
  end

  defp version_number_conflict?(changeset) do
    Enum.any?(changeset.errors, fn
      {:version_number, {_message, opts}} -> Keyword.get(opts, :constraint) == :unique
      _error -> false
    end)
  end

  defp change_data(flow_id, snapshot, opts) do
    if Keyword.get(opts, :skip_diff, false) do
      {nil, nil}
    else
      case History.get_latest_version(flow_id) do
        nil ->
          {gettext("Initial version"), nil}

        previous ->
          previous_change_data(previous, snapshot)
      end
    end
  end

  defp previous_change_data(previous, snapshot) do
    case SnapshotReader.load_version_snapshot(previous) do
      {:ok, previous_snapshot} ->
        changes = FlowSnapshot.diff(previous_snapshot, snapshot)
        {format_summary(changes), serialize_changes(changes)}

      {:error, reason} ->
        Logger.warning("Failed to load previous Flow snapshot: #{inspect(reason)}")
        {gettext("Changes from previous version"), nil}
    end
  end

  defp format_summary([]), do: gettext("No changes detected")

  defp format_summary(changes) do
    frequencies = Enum.frequencies_by(changes, & &1.detail)

    changes
    |> Enum.uniq_by(& &1.detail)
    |> Enum.map_join(", ", fn change ->
      case Map.get(frequencies, change.detail, 1) do
        1 -> change.detail
        count -> "#{change.detail} (×#{count})"
      end
    end)
  end

  defp serialize_changes([]), do: nil

  defp serialize_changes(changes) do
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
        "added" => Enum.count(changes, &(&1.action == :added)),
        "modified" => Enum.count(changes, &(&1.action == :modified)),
        "removed" => Enum.count(changes, &(&1.action == :removed))
      }
    }
  end
end
