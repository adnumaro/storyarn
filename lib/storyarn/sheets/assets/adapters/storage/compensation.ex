defmodule Storyarn.Sheets.Assets.Adapters.Storage.Compensation do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Repo
  alias Storyarn.Sheets.Assets.Adapters.Storage.Locks, as: StorageKeyLock
  alias Storyarn.Sheets.Assets.Adapters.Storage.Objects, as: Storage
  alias Storyarn.Sheets.Assets.Entities.AssetRecord
  alias Storyarn.Sheets.Assets.Entities.StorageCleanupRequestRecord
  alias Storyarn.Sheets.Assets.Projections.StorageReservationRecord
  alias Storyarn.Sheets.Assets.Projections.WorkspaceSnapshotImportRecord

  @tracker_key {__MODULE__, :tracked}
  @retained_key {__MODULE__, :retained}
  @force_delete_prefix "__storyarn_force_delete__:"
  @project_blob_pattern ~r|\Aprojects/([1-9]\d*)/blobs/([0-9a-f]{64})\.[a-z0-9][a-z0-9-]{0,31}\z|
  @conditional_copy_suffix_pattern ~r/\A[A-Za-z0-9_-]{16}\z/
  @asset_uuid_pattern ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/
  @active_import_statuses ~w(uploading queued running retrying)

  @spec new() :: reference()
  def new do
    reference = make_ref()
    Process.put(key(reference), [])
    Process.put(retained_key(reference), [])
    reference
  end

  @spec track(reference(), String.t()) :: :ok
  def track(reference, storage_key) when is_reference(reference) and is_binary(storage_key) do
    cleanup_target =
      Enum.find(tracked(reference), storage_key, fn target ->
        force_delete_target?(target) and cleanup_target_storage_key(target) == storage_key
      end)

    put_tracked(reference, cleanup_target)
    :ok
  end

  @spec track_force_delete(reference(), String.t()) :: :ok
  def track_force_delete(reference, storage_key) when is_reference(reference) and is_binary(storage_key) do
    put_tracked(reference, force_delete_target(storage_key))
    Process.put(retained_key(reference), Enum.reject(retained(reference), &(&1 == storage_key)))
    :ok
  end

  @spec retain_after_commit(reference(), String.t()) :: :ok
  def retain_after_commit(reference, storage_key) when is_reference(reference) and is_binary(storage_key) do
    put_tracked(reference, storage_key)

    Process.put(
      retained_key(reference),
      [storage_key | Enum.reject(retained(reference), &(&1 == storage_key))]
    )

    :ok
  end

  @spec untrack(reference(), String.t()) :: :ok
  def untrack(reference, storage_key) when is_reference(reference) and is_binary(storage_key) do
    Process.put(
      key(reference),
      Enum.reject(tracked(reference), &(cleanup_target_storage_key(&1) == storage_key))
    )

    Process.put(retained_key(reference), Enum.reject(retained(reference), &(&1 == storage_key)))
    :ok
  end

  @spec cleanup_after_rollback(reference(), keyword()) :: :ok | {:error, term()}
  def cleanup_after_rollback(reference, opts \\ []) when is_reference(reference) and is_list(opts) do
    cleanup(reference, tracked(reference), opts)
  end

  @spec cleanup_after_rollback!(reference(), keyword()) :: :ok
  def cleanup_after_rollback!(reference, opts \\ []) when is_reference(reference) and is_list(opts) do
    case cleanup_after_rollback(reference, opts) do
      :ok -> :ok
      {:error, reason} -> raise "Sheet asset rollback cleanup failed: #{inspect(reason)}"
    end
  end

  @spec cleanup_unretained(reference(), keyword()) :: :ok | {:error, term()}
  def cleanup_unretained(reference, opts \\ []) when is_reference(reference) and is_list(opts) do
    retained = reference |> retained() |> MapSet.new()

    cleanup(
      reference,
      Enum.reject(tracked(reference), &MapSet.member?(retained, cleanup_target_storage_key(&1))),
      opts
    )
  end

  @spec discard(reference()) :: :ok
  def discard(reference) when is_reference(reference) do
    Process.delete(key(reference))
    Process.delete(retained_key(reference))
    :ok
  end

  defp cleanup(reference, cleanup_targets, opts) do
    delete_fun = Keyword.get(opts, :delete_fun)
    persist_fun = Keyword.get(opts, :persist_fun, &persist_cleanup_request/1)

    failures =
      cleanup_targets
      |> Enum.filter(&Storage.canonical_key?(cleanup_target_storage_key(&1)))
      |> Enum.uniq()
      |> Enum.filter(&(call_delete(delete_fun, &1) != :ok))

    if failures == [] do
      discard(reference)
    else
      hand_off_failed_cleanup(reference, failures, persist_fun)
    end
  end

  defp hand_off_failed_cleanup(reference, storage_keys, persist_fun) do
    case call_persist(persist_fun, storage_keys) do
      {:ok, _request} ->
        discard(reference)

      {:error, reason} ->
        {:error, {:storage_cleanup_not_persisted, %{failed_keys: storage_keys, persistence_error: safe_error(reason)}}}
    end
  end

  defp persist_cleanup_request(storage_keys) do
    StorageKeyLock.with_cleanup_handoff_locks(storage_keys, fn ->
      %StorageCleanupRequestRecord{}
      |> StorageCleanupRequestRecord.sheet_restore_changeset(storage_keys)
      |> Repo.insert()
    end)
  end

  defp call_delete(nil, cleanup_target) do
    cleanup_target
    |> delete_unowned_cleanup_target()
    |> normalize_delete()
  rescue
    _error -> :error
  catch
    _kind, _reason -> :error
  end

  defp call_delete(delete_fun, cleanup_target) do
    cleanup_target
    |> cleanup_target_storage_key()
    |> delete_fun.()
    |> normalize_delete()
  rescue
    _error -> :error
  catch
    _kind, _reason -> :error
  end

  defp normalize_delete(result) do
    case result do
      :ok -> :ok
      _error -> :error
    end
  end

  defp call_persist(persist_fun, storage_keys) do
    case persist_fun.(storage_keys) do
      {:ok, request} -> {:ok, request}
      {:error, reason} -> {:error, reason}
      _result -> {:error, :unexpected_persistence_result}
    end
  rescue
    error -> {:error, {:exception, error.__struct__}}
  catch
    kind, reason -> {:error, {kind, safe_error(reason)}}
  end

  defp delete_unowned_cleanup_target(cleanup_target) do
    storage_key = cleanup_target_storage_key(cleanup_target)

    if force_delete_target?(cleanup_target) do
      {:error, :force_cleanup_requires_durable_reconciliation}
    else
      StorageKeyLock.with_storage_key_lock(storage_key, fn ->
        delete_unowned_storage_key(storage_key)
      end)
    end
  end

  defp delete_unowned_storage_key(storage_key) do
    cond do
      active_storage_owner?(storage_key) ->
        :ok

      asset_storage_key_owned?(storage_key) ->
        :ok

      conditional_copy_key?(storage_key) ->
        delete_owned_storage_object(storage_key)

      match?({:ok, _project_id}, StorageKeyLock.project_blob_id(storage_key)) ->
        {:error, :project_blob_cleanup_requires_durable_reconciliation}

      true ->
        Storage.delete(storage_key)
    end
  end

  defp active_storage_owner?(storage_key) do
    active_restore_storage_owner?(storage_key) or
      active_workspace_snapshot_import_storage_owner?(storage_key)
  end

  defp active_restore_storage_owner?(storage_key) do
    Repo.exists?(
      from reservation in StorageReservationRecord,
        where:
          reservation.kind == "restore_staging" and reservation.status == "active" and
            not is_nil(reservation.storage_started_at) and
            fragment("? @> ARRAY[?]::text[]", reservation.cleanup_storage_keys, ^storage_key)
    )
  end

  defp active_workspace_snapshot_import_storage_owner?(storage_key) do
    Repo.exists?(
      from import in WorkspaceSnapshotImportRecord,
        where:
          import.status in ^@active_import_statuses and
            fragment("? @> ARRAY[?]::varchar[]", import.materialization_storage_keys, ^storage_key)
    )
  end

  defp asset_storage_key_owned?(storage_key) do
    case Regex.run(@project_blob_pattern, storage_key, capture: :all_but_first) do
      [project_id, blob_hash] ->
        Repo.exists?(
          from(asset in AssetRecord,
            where:
              asset.project_id == ^String.to_integer(project_id) and
                asset.blob_hash == ^blob_hash
          )
        )

      _asset_key ->
        Repo.exists?(from(asset in AssetRecord, where: asset.key == ^storage_key))
    end
  end

  defp conditional_copy_key?(storage_key) do
    case String.split(storage_key, "/") do
      ["projects", project_id, "blobs", ".storyarn-copy", suffix] ->
        valid_project_id?(project_id) and String.match?(suffix, @conditional_copy_suffix_pattern)

      ["projects", project_id, "assets", asset_uuid, ".storyarn-copy", suffix] ->
        valid_project_id?(project_id) and String.match?(asset_uuid, @asset_uuid_pattern) and
          String.match?(suffix, @conditional_copy_suffix_pattern)

      _parts ->
        false
    end
  end

  defp valid_project_id?(project_id) do
    case Integer.parse(project_id) do
      {value, ""} -> value > 0
      _invalid -> false
    end
  end

  defp delete_owned_storage_object(storage_key) do
    Storage.delete_owned_conditional_copy(storage_key)
  end

  defp tracked(reference), do: Process.get(key(reference), [])
  defp retained(reference), do: Process.get(retained_key(reference), [])
  defp key(reference), do: {@tracker_key, reference}
  defp retained_key(reference), do: {@retained_key, reference}

  defp put_tracked(reference, storage_key) do
    raw_storage_key = cleanup_target_storage_key(storage_key)

    Process.put(
      key(reference),
      [
        storage_key
        | Enum.reject(tracked(reference), &(cleanup_target_storage_key(&1) == raw_storage_key))
      ]
    )
  end

  defp force_delete_target(storage_key), do: @force_delete_prefix <> storage_key

  defp force_delete_target?(cleanup_target) when is_binary(cleanup_target),
    do: String.starts_with?(cleanup_target, @force_delete_prefix)

  defp force_delete_target?(_cleanup_target), do: false

  defp cleanup_target_storage_key(cleanup_target) when is_binary(cleanup_target) do
    String.replace_prefix(cleanup_target, @force_delete_prefix, "")
  end

  defp cleanup_target_storage_key(_cleanup_target), do: ""

  defp safe_error(reason) when is_atom(reason), do: reason
  defp safe_error({reason, _details}) when is_atom(reason), do: reason
  defp safe_error(_reason), do: :unexpected_error
end
