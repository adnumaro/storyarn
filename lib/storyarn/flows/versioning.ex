defmodule Storyarn.Flows.Versioning do
  @moduledoc """
  Flow-owned entity version history.

  The module owns the complete Flow version lifecycle while deliberately
  sharing the existing SQL table and object-storage namespace. Its public
  surface is Flow-specific; internal discriminator clauses fail closed when a
  record from another entity type reaches the shared table.
  """

  use Gettext, backend: Storyarn.Gettext

  import Ecto.Query, warn: false

  alias Storyarn.Collaboration
  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.Limits
  alias Storyarn.Flows.Persistence.ProjectRecord
  alias Storyarn.Flows.Versioning.ConflictDetector
  alias Storyarn.Flows.Versioning.EntityVersionRecord
  alias Storyarn.Flows.Versioning.FlowSnapshot
  alias Storyarn.Flows.Versioning.RestorePolicy
  alias Storyarn.Flows.Versioning.SnapshotStorage
  alias Storyarn.Flows.Versioning.VersionNumberLock
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers

  require Logger

  @entity_type "flow"
  @default_min_interval_seconds 600
  @max_insert_retries 3

  @type version :: EntityVersionRecord.t()

  @doc "Creates a durable Flow version."
  @spec create_version(Flow.t(), integer() | nil, keyword()) ::
          {:ok, version()} | {:error, term()}
  def create_version(%Flow{} = flow, user_id, opts \\ []) do
    create_version(@entity_type, flow, flow.project_id, user_id, opts)
  end

  @doc false
  def create_version(entity_type, entity, project_id, user_id, opts \\ [])

  def create_version(@entity_type, %Flow{} = flow, project_id, user_id, opts) do
    with :ok <- validate_flow_scope(flow, project_id),
         :ok <- validate_actor_id(user_id) do
      snapshot = FlowSnapshot.build(flow)
      create_from_snapshot(flow, project_id, user_id, snapshot, opts)
    end
  end

  def create_version(_entity_type, _entity, _project_id, _user_id, _opts), do: {:error, :entity_scope_mismatch}

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
    version_number = next_version_number(params.entity_id)

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

  @doc "Creates an automatic version when the configured interval has elapsed."
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

  @doc false
  def maybe_create_version(entity_type, entity, project_id, user_id, opts \\ [])

  def maybe_create_version(@entity_type, %Flow{} = flow, project_id, user_id, opts) do
    with :ok <- validate_flow_scope(flow, project_id),
         :ok <- validate_actor_id(user_id) do
      min_interval = Keyword.get(opts, :min_interval, @default_min_interval_seconds)
      maybe_create_version_if_due(flow, project_id, user_id, opts, min_interval)
    end
  end

  def maybe_create_version(_entity_type, _entity, _project_id, _user_id, _opts), do: {:error, :entity_scope_mismatch}

  defp maybe_create_version_if_due(flow, project_id, user_id, opts, min_interval) do
    if version_due?(get_latest_version(flow.id), min_interval) do
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
          get_latest_version(flow.id)
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

  @doc "Lists Flow versions newest first."
  @spec list_versions(integer(), keyword()) :: [version()]
  def list_versions(flow_id, opts \\ []) when is_integer(flow_id) do
    list_versions(@entity_type, flow_id, opts)
  end

  @doc false
  def list_versions(@entity_type, flow_id, opts) when is_integer(flow_id) and is_list(opts) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)

    Repo.all(
      from(version in EntityVersionRecord,
        where: version.entity_type == @entity_type and version.entity_id == ^flow_id,
        order_by: [desc: version.version_number],
        limit: ^limit,
        offset: ^offset,
        preload: [:created_by]
      )
    )
  end

  def list_versions(_entity_type, _entity_id, _opts), do: []

  @doc "Gets one Flow version by its monotonic version number."
  @spec get_version(integer(), integer()) :: version() | nil
  def get_version(flow_id, version_number), do: get_version(@entity_type, flow_id, version_number)

  @doc false
  def get_version(@entity_type, flow_id, version_number) when is_integer(flow_id) and is_integer(version_number) do
    Repo.get_by(EntityVersionRecord,
      entity_type: @entity_type,
      entity_id: flow_id,
      version_number: version_number
    )
  end

  def get_version(_entity_type, _entity_id, _version_number), do: nil

  @doc "Gets the most recent Flow version."
  @spec get_latest_version(integer()) :: version() | nil
  def get_latest_version(flow_id), do: get_latest_version(@entity_type, flow_id)

  @doc false
  def get_latest_version(@entity_type, flow_id) when is_integer(flow_id) do
    Repo.one(
      from(version in EntityVersionRecord,
        where: version.entity_type == @entity_type and version.entity_id == ^flow_id,
        order_by: [desc: version.version_number],
        limit: 1
      )
    )
  end

  def get_latest_version(_entity_type, _entity_id), do: nil

  @doc "Counts persisted versions for a Flow."
  @spec count_versions(integer()) :: non_neg_integer()
  def count_versions(flow_id), do: count_versions(@entity_type, flow_id)

  @doc false
  def count_versions(@entity_type, flow_id) when is_integer(flow_id) do
    Repo.one(
      from(version in EntityVersionRecord,
        where: version.entity_type == @entity_type and version.entity_id == ^flow_id,
        select: count(version.id)
      )
    )
  end

  def count_versions(_entity_type, _entity_id), do: 0

  @doc "Returns the Flow version numbers immediately before and after the current number."
  @spec get_adjacent_version_numbers(integer(), integer()) ::
          {integer() | nil, integer() | nil}
  def get_adjacent_version_numbers(flow_id, current_number),
    do: get_adjacent_version_numbers(@entity_type, flow_id, current_number)

  @doc false
  def get_adjacent_version_numbers(@entity_type, flow_id, current_number)
      when is_integer(flow_id) and is_integer(current_number) do
    previous =
      Repo.one(
        from(version in EntityVersionRecord,
          where:
            version.entity_type == @entity_type and version.entity_id == ^flow_id and
              version.version_number < ^current_number,
          order_by: [desc: version.version_number],
          limit: 1,
          select: version.version_number
        )
      )

    following =
      Repo.one(
        from(version in EntityVersionRecord,
          where:
            version.entity_type == @entity_type and version.entity_id == ^flow_id and
              version.version_number > ^current_number,
          order_by: [asc: version.version_number],
          limit: 1,
          select: version.version_number
        )
      )

    {previous, following}
  end

  def get_adjacent_version_numbers(_entity_type, _entity_id, _current_number), do: {nil, nil}

  @doc "Counts Flow versions created after a timestamp."
  @spec count_versions_since(integer(), DateTime.t()) :: non_neg_integer()
  def count_versions_since(flow_id, %DateTime{} = since), do: count_versions_since(@entity_type, flow_id, since)

  @doc false
  def count_versions_since(@entity_type, flow_id, %DateTime{} = since) when is_integer(flow_id) do
    Repo.aggregate(
      from(version in EntityVersionRecord,
        where:
          version.entity_type == @entity_type and version.entity_id == ^flow_id and
            version.inserted_at > ^since
      ),
      :count
    )
  end

  def count_versions_since(_entity_type, _entity_id, _since), do: 0

  @doc "Updates the user-facing name and description of a Flow version."
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

  defp version_project_id(version_id) do
    Repo.one(
      from(version in EntityVersionRecord,
        where: version.id == ^version_id and version.entity_type == @entity_type,
        select: version.project_id
      )
    )
  end

  defp update_locked_version_by_id(project_id, version_id, attrs) do
    with {:ok, project} <- Limits.lock_named_version_project(project_id),
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
      do: Limits.ensure_named_version_capacity(project_id),
      else: :ok
  end

  defp ensure_promotion_capacity(%EntityVersionRecord{} = version, project) do
    if named_version?(version.title, version.is_auto),
      do: :ok,
      else: Limits.ensure_named_version_capacity(project)
  end

  defp named_version?(title, false), do: not is_nil(title)
  defp named_version?(_title, _is_auto), do: false

  defp normalize_limit_error({:error, {:limit_reached, metadata}}), do: {:error, :limit_reached, metadata}

  defp normalize_limit_error(result), do: result

  @doc "Deletes a Flow version and best-effort removes its snapshot object."
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

  defp delete_persisted_version(version) do
    with :ok <- validate_storage_key(version),
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

  @doc "Loads and verifies the exact snapshot owned by a persisted Flow version."
  @spec load_version_snapshot(map()) :: {:ok, map()} | {:error, term()}
  def load_version_snapshot(%{
        id: id,
        entity_type: @entity_type,
        entity_id: entity_id,
        project_id: project_id,
        version_number: version_number
      }) do
    case Repo.get_by(EntityVersionRecord,
           id: id,
           entity_type: @entity_type,
           entity_id: entity_id,
           project_id: project_id,
           version_number: version_number
         ) do
      %EntityVersionRecord{} = persisted ->
        with :ok <- validate_storage_key(persisted),
             {:ok, snapshot, _checksum} <- load_verified(persisted) do
          {:ok, snapshot}
        end

      nil ->
        {:error, :entity_version_not_found}
    end
  end

  def load_version_snapshot(_version), do: {:error, :entity_version_not_found}

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
  def prepare_restore(%Flow{} = flow, target_version) do
    if unsaved_since_latest_version?(flow) do
      {:ok, :unsaved_changes}
    else
      with {:ok, report} <- prepare_restore_conflicts(flow, target_version) do
        {:ok, {:ready, report}}
      end
    end
  end

  @doc "Loads the target snapshot and computes its Flow-owned restore conflict report."
  @spec prepare_restore_conflicts(Flow.t(), version()) ::
          {:ok, map()} | {:error, :target_snapshot_unreadable}
  def prepare_restore_conflicts(
        %Flow{id: flow_id} = flow,
        %{entity_type: @entity_type, entity_id: flow_id} = target_version
      ) do
    case load_version_snapshot(target_version) do
      {:ok, snapshot} -> {:ok, ConflictDetector.detect(snapshot, flow)}
      {:error, _reason} -> {:error, :target_snapshot_unreadable}
    end
  end

  def prepare_restore_conflicts(%Flow{}, _target_version), do: {:error, :target_snapshot_unreadable}

  defp unsaved_since_latest_version?(%Flow{} = flow) do
    case get_latest_version(flow.id) do
      nil ->
        true

      latest ->
        case load_version_snapshot(latest) do
          {:ok, latest_snapshot} ->
            current_snapshot = FlowSnapshot.build(flow)
            FlowSnapshot.diff(latest_snapshot, current_snapshot) != []

          {:error, _reason} ->
            true
        end
    end
  end

  @doc "Detects Flow-owned restore conflicts without mutating state."
  def detect_restore_conflicts(snapshot, %Flow{} = flow), do: ConflictDetector.detect(snapshot, flow)

  @doc false
  def detect_restore_conflicts(@entity_type, snapshot, %Flow{} = flow), do: ConflictDetector.detect(snapshot, flow)

  def detect_restore_conflicts(_entity_type, _snapshot, _entity),
    do: raise(ArgumentError, "invalid Flow restore-conflict scope")

  @doc "Restores a Flow with a mandatory, verified safety version."
  @spec restore_version(Flow.t(), map(), keyword()) :: {:ok, Flow.t()} | {:error, term()}
  def restore_version(%Flow{} = flow, version), do: restore_version(flow, version, [])

  def restore_version(%Flow{} = flow, version, opts) do
    restore_version(@entity_type, flow, version, opts)
  end

  @doc false
  def restore_version(entity_type, entity, version), do: restore_version(entity_type, entity, version, [])

  def restore_version(@entity_type, %Flow{} = flow, %{id: version_id}, opts)
      when is_integer(version_id) and is_list(opts) do
    user_id = Keyword.get(opts, :user_id)

    with :ok <- RestorePolicy.ensure_enabled({:entity_version_restore, @entity_type}),
         :ok <- validate_flow_scope(flow, flow.project_id),
         :ok <- validate_actor_id(user_id),
         :ok <- require_outer_transaction(),
         {:ok, target} <- fetch_owned_version(flow, version_id),
         :ok <- validate_storage_key(target),
         {:ok, snapshot, _checksum} <- load_verified(target),
         {:ok, safety} <- create_and_verify_safety_version(flow, target, user_id, opts),
         :ok <- run_safety_hook(opts, safety.record) do
      snapshot = resolve_shortcut_collision(flow, snapshot)

      builder_opts =
        opts
        |> Keyword.drop([:skip_pre_snapshot, :__pre_restore_version_fun, :__after_pre_restore_version_verified_hook])
        |> Keyword.put(:restore_action, {:entity_version_restore, @entity_type})
        |> Keyword.put(:pre_restore_snapshot, safety.snapshot)
        |> Keyword.put(:pre_restore_version_identity, version_identity(safety.record))

      case FlowSnapshot.restore(flow, snapshot, builder_opts) do
        {:ok, restored} ->
          maybe_create_post_restore_version(restored, target, user_id)
          Collaboration.broadcast_dashboard_change(restored.project_id, :flows)
          {:ok, restored}

        {:error, _reason} = error ->
          error
      end
    end
  end

  def restore_version(_entity_type, _entity, _version, _opts), do: {:error, :entity_version_scope_mismatch}

  @doc "Returns whether Flow version restore is enabled."
  def restore_enabled?, do: RestorePolicy.enabled?({:entity_version_restore, @entity_type})

  @doc false
  def restore_enabled?({:entity_version_restore, @entity_type}), do: restore_enabled?()
  def restore_enabled?(_action), do: false

  @doc false
  def ensure_restore_enabled, do: RestorePolicy.ensure_enabled({:entity_version_restore, @entity_type})

  @doc false
  def ensure_restore_enabled({:entity_version_restore, @entity_type} = action), do: RestorePolicy.ensure_enabled(action)

  def ensure_restore_enabled(_action), do: {:error, :restore_temporarily_disabled}

  @doc false
  def get_builder!(@entity_type), do: FlowSnapshot

  def get_builder!(entity_type), do: raise(ArgumentError, "unknown Flow version entity type: #{inspect(entity_type)}")

  @doc false
  def build_snapshot(%Flow{} = flow), do: FlowSnapshot.build(flow)

  @doc false
  def snapshot_has_changes?(previous, current), do: FlowSnapshot.diff(previous, current) != []

  @doc false
  def snapshot_has_changes?(@entity_type, previous, current), do: FlowSnapshot.diff(previous, current) != []

  def snapshot_has_changes?(_entity_type, _previous, _current), do: false

  @doc false
  def next_version_number(flow_id) do
    (Repo.one(
       from(version in EntityVersionRecord,
         where: version.entity_type == @entity_type and version.entity_id == ^flow_id,
         select: max(version.version_number)
       )
     ) || 0) + 1
  end

  defp auto_versioning_enabled?(project_id) do
    case Repo.get(ProjectRecord, project_id) do
      %ProjectRecord{deleted_at: nil, auto_version_flows: enabled?} -> enabled? == true
      _project -> false
    end
  end

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
      case get_latest_version(flow_id) do
        nil ->
          {gettext("Initial version"), nil}

        previous ->
          previous_change_data(previous, snapshot)
      end
    end
  end

  defp previous_change_data(previous, snapshot) do
    case load_version_snapshot(previous) do
      {:ok, previous_snapshot} ->
        changes = FlowSnapshot.diff(previous_snapshot, snapshot)
        {format_summary(changes), serialize_changes(changes)}

      {:error, reason} ->
        Logger.warning("Failed to load previous Flow snapshot: #{inspect(reason)}")
        {gettext("Changes from previous version"), nil}
    end
  end

  defp format_summary([]), do: gettext("No changes")

  defp format_summary(changes) do
    added = Enum.count(changes, &(&1.action == :added))
    modified = Enum.count(changes, &(&1.action == :modified))
    removed = Enum.count(changes, &(&1.action == :removed))

    gettext("%{added} added, %{modified} modified, %{removed} removed",
      added: added,
      modified: modified,
      removed: removed
    )
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

  defp fetch_owned_version(flow, version_id) do
    case Repo.get_by(EntityVersionRecord,
           id: version_id,
           entity_type: @entity_type,
           entity_id: flow.id,
           project_id: flow.project_id
         ) do
      %EntityVersionRecord{} = version -> {:ok, version}
      nil -> {:error, :entity_version_scope_mismatch}
    end
  end

  defp validate_storage_key(version) do
    if SnapshotStorage.entity_key?(
         version.storage_key,
         version.project_id,
         version.entity_id,
         version.version_number
       ) do
      :ok
    else
      {:error, :entity_version_storage_key_mismatch}
    end
  end

  defp load_verified(version) do
    SnapshotStorage.load_verified(
      version.storage_key,
      version.snapshot_size_bytes,
      version.checksum
    )
  end

  defp require_outer_transaction do
    if Repo.in_transaction?(),
      do: {:error, :version_restore_requires_transaction_boundary},
      else: :ok
  end

  defp create_and_verify_safety_version(flow, target, user_id, opts) do
    create_opts = [
      title: dgettext("versioning", "Before restore to v%{number}", number: target.version_number),
      is_auto: true,
      skip_diff: true
    ]

    create_fun = Keyword.get(opts, :__pre_restore_version_fun, &create_version/3)

    result =
      with {:ok, %{id: safety_id}} <- safely_create_safety(create_fun, flow, user_id, create_opts),
           %EntityVersionRecord{} = safety <-
             Repo.get_by(EntityVersionRecord,
               id: safety_id,
               entity_type: @entity_type,
               entity_id: flow.id,
               project_id: flow.project_id
             ),
           true <- safety.created_by_id == user_id,
           :ok <- validate_storage_key(safety),
           {:ok, snapshot, _checksum} <- load_verified(safety) do
        {:ok, %{record: safety, snapshot: snapshot}}
      else
        nil -> {:error, :pre_restore_version_not_found}
        {:error, _reason} = error -> error
        _invalid -> {:error, :invalid_pre_restore_version_result}
      end

    case result do
      {:ok, _safety} = ok -> ok
      {:error, reason} -> {:error, {:pre_restore_snapshot_failed, reason}}
    end
  end

  defp safely_create_safety(create_fun, flow, user_id, create_opts) do
    create_fun.(flow, user_id, create_opts)
  rescue
    error ->
      Logger.error("Flow safety version creation raised: #{Exception.message(error)}")
      {:error, :pre_restore_version_exception}
  catch
    kind, reason ->
      Logger.error("Flow safety version creation failed: #{inspect({kind, reason})}")
      {:error, :pre_restore_version_failure}
  end

  defp run_safety_hook(opts, version) do
    case Keyword.get(opts, :__after_pre_restore_version_verified_hook) do
      hook when is_function(hook, 1) ->
        hook.(version)
        :ok

      _hook ->
        :ok
    end
  end

  defp version_identity(version) do
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

  defp resolve_shortcut_collision(flow, snapshot) do
    shortcut = snapshot["shortcut"]

    collision? =
      is_binary(shortcut) and
        Repo.exists?(
          from(candidate in Flow,
            where:
              candidate.project_id == ^flow.project_id and candidate.id != ^flow.id and
                candidate.shortcut == ^shortcut and is_nil(candidate.deleted_at)
          )
        )

    if collision? do
      suffix = 4 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)
      Map.put(snapshot, "shortcut", shortcut <> "-" <> suffix)
    else
      snapshot
    end
  end

  defp maybe_create_post_restore_version(_restored, _target, nil), do: :ok

  defp maybe_create_post_restore_version(restored, target, user_id) do
    case create_version(restored, user_id,
           title: dgettext("versioning", "Restored from v%{number}", number: target.version_number),
           is_auto: true,
           skip_diff: true
         ) do
      {:ok, _version} -> :ok
      {:error, reason} -> Logger.warning("Failed to create post-restore Flow version: #{inspect(reason)}")
    end
  end
end
