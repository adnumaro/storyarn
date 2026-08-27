defmodule Storyarn.Sheets.Versioning.Execution.Restore do
  @moduledoc false

  use Gettext, backend: Storyarn.Gettext

  import Ecto.Query, warn: false

  alias Storyarn.Platform.Collaboration
  alias Storyarn.Repo
  alias Storyarn.Sheets.Sheet
  alias Storyarn.Sheets.Versioning.Commands.VersionLifecycle
  alias Storyarn.Sheets.Versioning.EntityVersionRecord
  alias Storyarn.Sheets.Versioning.Execution.Conflicts, as: ConflictDetector
  alias Storyarn.Sheets.Versioning.Execution.SnapshotReader
  alias Storyarn.Sheets.Versioning.Queries.History
  alias Storyarn.Sheets.Versioning.RestorePolicy
  alias Storyarn.Sheets.Versioning.SheetSnapshot

  require Logger

  @entity_type "sheet"

  @type version :: EntityVersionRecord.t()

  @spec prepare_restore(Sheet.t(), version()) ::
          {:ok, :unsaved_changes}
          | {:ok, {:ready, map()}}
          | {:error, :target_snapshot_unreadable}
  def prepare_restore(%Sheet{} = sheet, target_version) do
    if unsaved_since_latest_version?(sheet) do
      {:ok, :unsaved_changes}
    else
      with {:ok, report} <- prepare_restore_conflicts(sheet, target_version) do
        {:ok, {:ready, report}}
      end
    end
  end

  @spec prepare_restore_conflicts(Sheet.t(), version()) ::
          {:ok, map()} | {:error, :target_snapshot_unreadable}
  def prepare_restore_conflicts(
        %Sheet{id: sheet_id} = sheet,
        %{entity_type: @entity_type, entity_id: sheet_id} = target_version
      ) do
    case SnapshotReader.load_version_snapshot(target_version) do
      {:ok, snapshot} -> {:ok, ConflictDetector.detect(snapshot, sheet)}
      {:error, _reason} -> {:error, :target_snapshot_unreadable}
    end
  end

  def prepare_restore_conflicts(%Sheet{}, _target_version), do: {:error, :target_snapshot_unreadable}

  def detect_restore_conflicts(snapshot, %Sheet{} = sheet), do: ConflictDetector.detect(snapshot, sheet)

  def detect_restore_conflicts(@entity_type, snapshot, %Sheet{} = sheet), do: ConflictDetector.detect(snapshot, sheet)

  def detect_restore_conflicts(_entity_type, _snapshot, _entity),
    do: raise(ArgumentError, "invalid Sheet restore-conflict scope")

  @spec restore_version(Sheet.t(), map(), keyword()) :: {:ok, Sheet.t()} | {:error, term()}
  def restore_version(%Sheet{} = sheet, version), do: restore_version(sheet, version, [])

  def restore_version(%Sheet{} = sheet, version, opts) do
    restore_version(@entity_type, sheet, version, opts)
  end

  def restore_version(entity_type, entity, version), do: restore_version(entity_type, entity, version, [])

  def restore_version(@entity_type, %Sheet{} = sheet, %{id: version_id}, opts)
      when is_integer(version_id) and is_list(opts) do
    user_id = Keyword.get(opts, :user_id)

    with :ok <- RestorePolicy.ensure_enabled({:entity_version_restore, @entity_type}),
         :ok <- validate_sheet_scope(sheet, sheet.project_id),
         :ok <- validate_actor_id(user_id),
         :ok <- require_outer_transaction(),
         {:ok, target} <- fetch_owned_version(sheet, version_id),
         {:ok, snapshot, _checksum} <- SnapshotReader.load_verified_version(target),
         {:ok, safety} <- create_and_verify_safety_version(sheet, target, user_id, opts),
         :ok <- run_safety_hook(opts, safety.record) do
      snapshot = resolve_shortcut_collision(sheet, snapshot)

      builder_opts =
        opts
        |> Keyword.drop([:skip_pre_snapshot, :__pre_restore_version_fun, :__after_pre_restore_version_verified_hook])
        |> Keyword.put(:restore_action, {:entity_version_restore, @entity_type})
        |> Keyword.put(:pre_restore_snapshot, safety.snapshot)
        |> Keyword.put(:pre_restore_version_identity, version_identity(safety.record))

      case SheetSnapshot.restore(sheet, snapshot, builder_opts) do
        {:ok, restored} ->
          maybe_create_post_restore_version(restored, target, user_id)
          Collaboration.broadcast_dashboard_change(restored.project_id, :sheets)
          {:ok, restored}

        {:error, _reason} = error ->
          error
      end
    end
  end

  def restore_version(_entity_type, _entity, _version, _opts), do: {:error, :entity_version_scope_mismatch}

  def restore_enabled?, do: RestorePolicy.enabled?({:entity_version_restore, @entity_type})

  def restore_enabled?({:entity_version_restore, @entity_type}), do: restore_enabled?()
  def restore_enabled?(_action), do: false

  def ensure_restore_enabled, do: RestorePolicy.ensure_enabled({:entity_version_restore, @entity_type})

  def ensure_restore_enabled({:entity_version_restore, @entity_type} = action), do: RestorePolicy.ensure_enabled(action)

  def ensure_restore_enabled(_action), do: {:error, :restore_temporarily_disabled}

  defp validate_sheet_scope(%Sheet{id: id, project_id: project_id}, project_id)
       when is_integer(id) and id > 0 and is_integer(project_id) and project_id > 0 do
    case Repo.get(Sheet, id) do
      %Sheet{project_id: ^project_id, deleted_at: nil} -> :ok
      _sheet -> {:error, :entity_scope_mismatch}
    end
  end

  defp validate_sheet_scope(_sheet, _project_id), do: {:error, :entity_scope_mismatch}

  defp validate_actor_id(nil), do: :ok
  defp validate_actor_id(id) when is_integer(id) and id > 0, do: :ok
  defp validate_actor_id(_id), do: {:error, :invalid_version_actor}

  defp unsaved_since_latest_version?(%Sheet{} = sheet) do
    case History.get_latest_version(sheet.id) do
      nil ->
        true

      latest ->
        case SnapshotReader.load_version_snapshot(latest) do
          {:ok, latest_snapshot} ->
            current_snapshot = SheetSnapshot.build(sheet)
            SheetSnapshot.diff(latest_snapshot, current_snapshot) != []

          {:error, _reason} ->
            true
        end
    end
  end

  defp fetch_owned_version(sheet, version_id) do
    case Repo.get_by(EntityVersionRecord,
           id: version_id,
           entity_type: @entity_type,
           entity_id: sheet.id,
           project_id: sheet.project_id
         ) do
      %EntityVersionRecord{} = version -> {:ok, version}
      nil -> {:error, :entity_version_scope_mismatch}
    end
  end

  defp require_outer_transaction do
    if Repo.in_transaction?(),
      do: {:error, :version_restore_requires_transaction_boundary},
      else: :ok
  end

  defp create_and_verify_safety_version(sheet, target, user_id, opts) do
    create_opts = [
      title: dgettext("versioning", "Before restore to v%{number}", number: target.version_number),
      is_auto: true,
      skip_diff: true
    ]

    create_fun = Keyword.get(opts, :__pre_restore_version_fun, &VersionLifecycle.create_version/3)

    result =
      with {:ok, %{id: safety_id}} <- safely_create_safety(create_fun, sheet, user_id, create_opts),
           %EntityVersionRecord{} = safety <-
             Repo.get_by(EntityVersionRecord,
               id: safety_id,
               entity_type: @entity_type,
               entity_id: sheet.id,
               project_id: sheet.project_id
             ),
           true <- safety.created_by_id == user_id,
           {:ok, snapshot, _checksum} <- SnapshotReader.load_verified_version(safety) do
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

  defp safely_create_safety(create_fun, sheet, user_id, create_opts) do
    create_fun.(sheet, user_id, create_opts)
  rescue
    error ->
      Logger.error("Sheet safety version creation raised: #{Exception.message(error)}")
      {:error, :pre_restore_version_exception}
  catch
    kind, reason ->
      Logger.error("Sheet safety version creation failed: #{inspect({kind, reason})}")
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

  defp resolve_shortcut_collision(sheet, snapshot) do
    shortcut = snapshot["shortcut"]

    collision? =
      is_binary(shortcut) and
        Repo.exists?(
          from(candidate in Sheet,
            where:
              candidate.project_id == ^sheet.project_id and candidate.id != ^sheet.id and
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
    case VersionLifecycle.create_version(restored, user_id,
           title: dgettext("versioning", "Restored from v%{number}", number: target.version_number),
           is_auto: true,
           skip_diff: true
         ) do
      {:ok, _version} -> :ok
      {:error, reason} -> Logger.warning("Failed to create post-restore Sheet version: #{inspect(reason)}")
    end
  end
end
