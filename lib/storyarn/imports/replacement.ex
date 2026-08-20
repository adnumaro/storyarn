defmodule Storyarn.Imports.Replacement do
  @moduledoc """
  Snapshot gate and transactional cleanup for an explicit project replacement.

  The snapshot is a normal user-visible full project snapshot. Nothing is
  removed until it is ready, verified, still matches its durable import
  binding, and a freshly rebuilt canonical project checksum matches the state
  captured by that snapshot.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Accounts.Scope
  alias Storyarn.Assets
  alias Storyarn.Billing
  alias Storyarn.Flows
  alias Storyarn.Flows.Flow
  alias Storyarn.Imports.ProjectImportAttempt
  alias Storyarn.Imports.Telemetry
  alias Storyarn.Localization.GlossaryEntry
  alias Storyarn.Localization.LocalizedText
  alias Storyarn.Localization.ProjectLanguage
  alias Storyarn.Projects.Project
  alias Storyarn.Repo
  alias Storyarn.Scenes
  alias Storyarn.Scenes.Scene
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Sheets
  alias Storyarn.Sheets.Sheet
  alias Storyarn.Versioning
  alias Storyarn.Versioning.Builders.AssetHashResolver
  alias Storyarn.Versioning.Builders.ProjectSnapshotBuilder
  alias Storyarn.Versioning.ProjectSnapshot
  alias Storyarn.Versioning.SnapshotArchiveStorage

  @snapshot_wait_seconds 5
  @sha256_regex ~r/\A[0-9a-f]{64}\z/

  @type readiness_result ::
          {:ok, ProjectImportAttempt.t()} | {:snooze, pos_integer()} | {:error, term()}

  @doc "Binds the exact ready snapshot identity, or asks Oban to wait without consuming an import retry."
  @spec ensure_snapshot_ready(ProjectImportAttempt.t(), Project.t(), keyword()) :: readiness_result()
  def ensure_snapshot_ready(attempt, project, opts \\ [])

  def ensure_snapshot_ready(%ProjectImportAttempt{import_mode: "additive"} = attempt, %Project{}, _opts),
    do: {:ok, attempt}

  def ensure_snapshot_ready(%ProjectImportAttempt{import_mode: "replace_project"} = attempt, %Project{} = project, opts)
      when is_list(opts) do
    snapshot_previously_bound? = is_integer(attempt.pre_import_snapshot_id)

    with :ok <- ensure_restore_enabled(),
         {:ok, bound_attempt} <- ensure_snapshot_requested(attempt, project, opts) do
      result =
        bound_attempt
        |> inspect_snapshot_state(project)
        |> normalize_readiness_transaction()

      emit_snapshot_transition(bound_attempt, result, snapshot_previously_bound?)
      result
    end
  end

  def ensure_snapshot_ready(%ProjectImportAttempt{}, %Project{}, _opts), do: {:error, :invalid_import_mode}

  @doc "Locks the bound recovery snapshot before the import-attempt row in the final transaction."
  @spec prelock_snapshot_in_transaction(ProjectImportAttempt.t()) :: :ok | {:error, term()}
  def prelock_snapshot_in_transaction(%ProjectImportAttempt{import_mode: "additive"}), do: :ok

  def prelock_snapshot_in_transaction(%ProjectImportAttempt{
        import_mode: "replace_project",
        pre_import_snapshot_id: snapshot_id
      }) do
    cond do
      not Repo.in_transaction?() ->
        {:error, :import_transaction_required}

      match?(%ProjectSnapshot{}, lock_snapshot(snapshot_id)) ->
        :ok

      true ->
        {:error, :pre_import_snapshot_unavailable}
    end
  end

  def prelock_snapshot_in_transaction(%ProjectImportAttempt{}), do: {:error, :invalid_import_mode}

  @doc "Verifies the recovery fence and trashes only replaceable narrative state inside the final import transaction."
  @spec prepare_project_in_transaction(ProjectImportAttempt.t(), Project.t()) ::
          :ok | {:error, term()}
  def prepare_project_in_transaction(%ProjectImportAttempt{import_mode: "additive"}, %Project{}), do: :ok

  def prepare_project_in_transaction(
        %ProjectImportAttempt{import_mode: "replace_project"} = attempt,
        %Project{} = project
      ) do
    cond do
      not Repo.in_transaction?() ->
        {:error, :import_transaction_required}

      not Billing.workspace_lock_held?(project.workspace_id) ->
        {:error, :storage_accounting_lock_required}

      not Versioning.project_snapshot_restore_enabled?() ->
        {:error, :project_snapshot_restore_disabled}

      true ->
        verify_and_prepare_project(attempt, project)
    end
  end

  def prepare_project_in_transaction(%ProjectImportAttempt{}, %Project{}), do: {:error, :invalid_import_mode}

  defp ensure_snapshot_requested(
         %ProjectImportAttempt{pre_import_snapshot_id: snapshot_id, snapshot_reference_bound_at: %DateTime{}} = attempt,
         %Project{},
         _opts
       )
       when is_integer(snapshot_id) and snapshot_id > 0, do: {:ok, attempt}

  defp ensure_snapshot_requested(%ProjectImportAttempt{pre_import_snapshot_id: snapshot_id}, %Project{}, _opts)
       when is_integer(snapshot_id) and snapshot_id > 0, do: {:error, :invalid_import_snapshot_identity}

  defp ensure_snapshot_requested(
         %ProjectImportAttempt{pre_import_snapshot_id: nil, snapshot_reference_bound_at: %DateTime{}},
         %Project{},
         _opts
       ), do: {:error, :pre_import_snapshot_unavailable}

  defp ensure_snapshot_requested(
         %ProjectImportAttempt{pre_import_snapshot_id: nil, snapshot_capture_digest: digest},
         %Project{},
         _opts
       )
       when is_binary(digest), do: {:error, :pre_import_snapshot_unavailable}

  defp ensure_snapshot_requested(%ProjectImportAttempt{} = attempt, %Project{} = project, opts) do
    with {:ok, snapshot} <- request_recovery_snapshot(attempt, project, opts) do
      bind_requested_snapshot(attempt, project, snapshot)
    end
  end

  defp request_recovery_snapshot(attempt, project, opts) do
    request = Keyword.get(opts, :snapshot_request, &Versioning.request_full_project_snapshot/3)

    attrs = %{
      mode: "full",
      idempotency_key: attempt.snapshot_request_key,
      title: "Before Yarn project replacement",
      description: "Recovery point created before replacing narrative project content."
    }

    case request.(Scope.for_user(attempt.user), project, attrs) do
      {:ok, %ProjectSnapshot{} = snapshot} -> {:ok, snapshot}
      {:error, reason} -> {:error, normalize_snapshot_request_error(reason)}
      {:error, reason, _details} -> {:error, normalize_snapshot_request_error(reason)}
      _invalid -> {:error, :pre_import_snapshot_request_failed}
    end
  rescue
    _exception -> {:error, :pre_import_snapshot_request_failed}
  catch
    _kind, _reason -> {:error, :pre_import_snapshot_request_failed}
  end

  defp bind_requested_snapshot(attempt_hint, project_hint, snapshot_hint) do
    Repo.transact(fn ->
      with %Project{} = project <- lock_active_project(project_hint),
           %ProjectSnapshot{} = snapshot <- lock_snapshot(snapshot_hint.id),
           %ProjectImportAttempt{} = attempt <- lock_attempt(attempt_hint, project),
           true <- attempt.status == "queued" and attempt.stage == "awaiting_snapshot",
           :ok <- validate_unbound_snapshot_request_identity(attempt, project, snapshot),
           {:ok, bound_attempt} <- persist_snapshot_reference(attempt, snapshot.id) do
        {:ok, bound_attempt}
      else
        nil -> {:error, :pre_import_snapshot_unavailable}
        false -> {:error, :import_not_queued}
        {:error, reason} -> {:error, reason}
        _invalid -> {:error, :invalid_import_snapshot_identity}
      end
    end)
  end

  defp persist_snapshot_reference(%ProjectImportAttempt{pre_import_snapshot_id: nil} = attempt, snapshot_id) do
    attempt
    |> Ecto.Changeset.change(
      pre_import_snapshot_id: snapshot_id,
      snapshot_reference_bound_at: TimeHelpers.now(),
      error_code: nil,
      error_message: nil,
      error_report: %{}
    )
    |> Repo.update()
  end

  defp persist_snapshot_reference(
         %ProjectImportAttempt{pre_import_snapshot_id: snapshot_id, snapshot_reference_bound_at: %DateTime{}} = attempt,
         snapshot_id
       ), do: {:ok, attempt}

  defp persist_snapshot_reference(%ProjectImportAttempt{}, _snapshot_id), do: {:error, :invalid_import_snapshot_identity}

  defp inspect_snapshot_state(attempt_hint, project_hint) do
    Repo.transact(fn ->
      with %Project{} = project <- lock_active_project(project_hint),
           %ProjectSnapshot{} = snapshot <- lock_snapshot(attempt_hint.pre_import_snapshot_id),
           %ProjectImportAttempt{} = attempt <- lock_attempt(attempt_hint, project),
           true <- attempt.pre_import_snapshot_id == snapshot.id,
           true <- attempt.status in ["queued", "running", "retrying"],
           :ok <- ensure_restore_enabled(),
           :ok <- validate_snapshot_request_identity(attempt, project, snapshot) do
        bind_snapshot_by_state(attempt, snapshot)
      else
        nil -> {:error, :pre_import_snapshot_unavailable}
        false -> {:error, :import_not_queued}
        {:error, reason} -> {:error, reason}
        _invalid -> {:error, :invalid_import_snapshot_identity}
      end
    end)
  end

  defp bind_snapshot_by_state(attempt, %ProjectSnapshot{lifecycle_state: state})
       when state in ["pending", "building", "verifying"] do
    if attempt.status == "queued" and attempt.stage == "awaiting_snapshot" and
         is_nil(attempt.snapshot_capture_digest) do
      case attempt |> ProjectImportAttempt.snapshot_waiting_changeset() |> Repo.update() do
        {:ok, waiting} -> {:ok, {:snooze, @snapshot_wait_seconds, waiting}}
        {:error, _changeset} -> {:error, :invalid_import_snapshot_identity}
      end
    else
      {:error, :invalid_import_snapshot_identity}
    end
  end

  defp bind_snapshot_by_state(attempt, %ProjectSnapshot{lifecycle_state: "ready"} = snapshot) do
    with :ok <- validate_ready_snapshot(snapshot),
         :ok <- validate_or_bind_snapshot_identity(attempt, snapshot) do
      {:ok, {:ready, current_attempt(attempt.id)}}
    end
  end

  defp bind_snapshot_by_state(_attempt, %ProjectSnapshot{}), do: {:error, :pre_import_snapshot_unavailable}

  defp validate_or_bind_snapshot_identity(%ProjectImportAttempt{snapshot_capture_digest: nil} = attempt, snapshot) do
    if attempt.status == "queued" and attempt.stage == "awaiting_snapshot" do
      case attempt
           |> ProjectImportAttempt.snapshot_ready_changeset(snapshot)
           |> Repo.update() do
        {:ok, _updated} -> :ok
        {:error, _changeset} -> {:error, :invalid_import_snapshot_identity}
      end
    else
      {:error, :invalid_import_snapshot_identity}
    end
  end

  defp validate_or_bind_snapshot_identity(%ProjectImportAttempt{} = attempt, snapshot) do
    if bound_snapshot_identity_matches?(attempt, snapshot), do: :ok, else: {:error, :invalid_import_snapshot_identity}
  end

  defp normalize_readiness_transaction({:ok, {:ready, attempt}}), do: {:ok, attempt}
  defp normalize_readiness_transaction({:ok, {:snooze, seconds, _attempt}}), do: {:snooze, seconds}
  defp normalize_readiness_transaction({:error, reason}), do: {:error, reason}

  defp emit_snapshot_transition(attempt, {:snooze, _seconds}, false),
    do: Telemetry.emit_snapshot_transition(attempt, "awaiting_snapshot")

  defp emit_snapshot_transition(
         %ProjectImportAttempt{stage: "awaiting_snapshot"},
         {:ok, %ProjectImportAttempt{stage: "queued"} = ready_attempt},
         _previously_bound
       ), do: Telemetry.emit_snapshot_transition(ready_attempt, "ready")

  defp emit_snapshot_transition(_attempt, _result, _previously_bound), do: :ok

  defp verify_and_prepare_project(attempt, project) do
    with %ProjectSnapshot{} = snapshot <- lock_snapshot(attempt.pre_import_snapshot_id),
         :ok <- validate_snapshot_request_identity(attempt, project, snapshot),
         :ok <- validate_ready_snapshot(snapshot),
         true <- bound_snapshot_identity_matches?(attempt, snapshot),
         {:ok, checksum} <- current_project_checksum(project),
         true <- Plug.Crypto.secure_compare(checksum, snapshot.project_checksum),
         {:ok, roots} <- active_roots(project.id),
         :ok <- trash_active_graph(roots),
         :ok <- archive_active_localization(project.id) do
      :ok
    else
      nil -> {:error, :pre_import_snapshot_unavailable}
      false -> {:error, :project_changed_since_import_snapshot}
      {:error, reason} -> {:error, reason}
      _invalid -> {:error, :invalid_import_snapshot_identity}
    end
  end

  defp current_project_checksum(project) do
    assets = Assets.list_assets_for_export(project.id)

    snapshot =
      project.id
      |> ProjectSnapshotBuilder.build_canonical_snapshot_in_transaction(localization_scope: :active)
      |> put_asset_capture_contract(assets)

    case SnapshotArchiveStorage.canonical_project_checksum(snapshot, assets) do
      {:ok, checksum} when is_binary(checksum) -> {:ok, checksum}
      {:error, _reason} -> {:error, :pre_import_snapshot_verification_failed}
      _invalid -> {:error, :pre_import_snapshot_verification_failed}
    end
  end

  defp put_asset_capture_contract(snapshot, assets) do
    {asset_blob_hashes, asset_metadata} = AssetHashResolver.capture_catalog_maps(assets)

    snapshot
    |> Map.put("asset_restore_contract_version", AssetHashResolver.exact_restore_contract_version())
    |> Map.put("asset_blob_hashes", asset_blob_hashes)
    |> Map.put("asset_metadata", asset_metadata)
  end

  defp active_roots(project_id) do
    {:ok,
     %{
       flows: root_entities(Flow, project_id),
       scenes: root_entities(Scene, project_id),
       sheets: root_entities(Sheet, project_id)
     }}
  end

  defp root_entities(schema, project_id) do
    Repo.all(
      from entity in schema,
        where:
          entity.project_id == ^project_id and is_nil(entity.parent_id) and
            is_nil(entity.deleted_at),
        order_by: [asc: entity.id]
    )
  end

  defp trash_active_graph(roots) do
    with :ok <- trash_roots(roots.flows, &Flows.delete_flow_subtree_for_project_restore_in_transaction/1),
         :ok <- trash_roots(roots.scenes, &Scenes.delete_scene_subtree_in_transaction/1) do
      trash_roots(roots.sheets, &Sheets.delete_sheet_subtree_in_transaction/1)
    end
  end

  defp trash_roots(roots, delete_fun) do
    Enum.reduce_while(roots, :ok, fn root, :ok ->
      case delete_fun.(root) do
        %{entity: _entity} -> {:cont, :ok}
        {:ok, %{entity: _entity}} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
        _invalid -> {:halt, {:error, :import_project_replacement_failed}}
      end
    end)
  end

  defp archive_active_localization(project_id) do
    now = TimeHelpers.now()

    Repo.update_all(
      from(language in ProjectLanguage,
        where: language.project_id == ^project_id and is_nil(language.archived_at)
      ),
      set: [archived_at: now, updated_at: now]
    )

    Repo.update_all(
      from(text in LocalizedText,
        where: text.project_id == ^project_id and is_nil(text.archived_at)
      ),
      set: [archived_at: now, archive_reason: "version_replaced", updated_at: now]
    )

    Repo.delete_all(from entry in GlossaryEntry, where: entry.project_id == ^project_id)
    :ok
  end

  defp validate_unbound_snapshot_request_identity(attempt, project, snapshot) do
    valid_identity? =
      Enum.all?([
        attempt.import_mode == "replace_project",
        attempt.replace_eligible == true,
        snapshot.project_id == project.id,
        snapshot.created_by_id == attempt.user_id,
        snapshot.idempotency_key == attempt.snapshot_request_key,
        snapshot.mode == "full",
        snapshot.origin == "user",
        snapshot.is_auto == false
      ])

    if valid_identity?, do: :ok, else: {:error, :invalid_import_snapshot_identity}
  end

  defp validate_snapshot_request_identity(attempt, project, snapshot) do
    with true <- attempt.pre_import_snapshot_id == snapshot.id,
         :ok <- validate_unbound_snapshot_request_identity(attempt, project, snapshot) do
      :ok
    else
      _mismatch -> {:error, :invalid_import_snapshot_identity}
    end
  end

  defp validate_ready_snapshot(snapshot) do
    with {:ok, _identity} <- Versioning.restorable_project_snapshot_identity(snapshot),
         true <- valid_sha256?(snapshot.capture_digest),
         true <- valid_sha256?(snapshot.project_checksum) do
      :ok
    else
      {:error, :project_snapshot_not_restorable} -> {:error, :pre_import_snapshot_unavailable}
      _invalid -> {:error, :invalid_import_snapshot_identity}
    end
  end

  defp bound_snapshot_identity_matches?(attempt, snapshot) do
    Enum.all?([
      attempt.snapshot_lifecycle_generation == snapshot.lifecycle_generation,
      attempt.snapshot_accounting_generation == snapshot.accounting_generation,
      secure_equal?(attempt.snapshot_capture_digest, snapshot.capture_digest),
      secure_equal?(attempt.snapshot_project_checksum, snapshot.project_checksum),
      attempt.snapshot_archive_storage_key == snapshot.archive_storage_key,
      attempt.snapshot_archive_size_bytes == snapshot.archive_size_bytes,
      secure_equal?(attempt.snapshot_archive_checksum, snapshot.archive_checksum),
      attempt.snapshot_manifest_storage_key == snapshot.manifest_storage_key,
      attempt.snapshot_manifest_size_bytes == snapshot.manifest_size_bytes,
      secure_equal?(attempt.snapshot_manifest_checksum, snapshot.manifest_checksum)
    ])
  end

  defp secure_equal?(left, right) when is_binary(left) and is_binary(right) and byte_size(left) == byte_size(right),
    do: Plug.Crypto.secure_compare(left, right)

  defp secure_equal?(_left, _right), do: false

  defp valid_sha256?(value), do: is_binary(value) and Regex.match?(@sha256_regex, value)

  defp lock_snapshot(snapshot_id) when is_integer(snapshot_id) and snapshot_id > 0 do
    Repo.one(
      from snapshot in ProjectSnapshot,
        where: snapshot.id == ^snapshot_id,
        lock: "FOR SHARE"
    )
  end

  defp lock_snapshot(_snapshot_id), do: nil

  defp lock_active_project(%Project{id: project_id, workspace_id: workspace_id}) do
    Repo.one(
      from project in Project,
        where:
          project.id == ^project_id and project.workspace_id == ^workspace_id and
            is_nil(project.deleted_at),
        lock: "FOR UPDATE"
    )
  end

  defp lock_attempt(attempt, project) do
    Repo.one(
      from candidate in ProjectImportAttempt,
        where:
          candidate.id == ^attempt.id and candidate.project_id == ^project.id and
            candidate.user_id == ^attempt.user_id,
        lock: "FOR UPDATE"
    )
  end

  defp current_attempt(id), do: Repo.get!(ProjectImportAttempt, id)

  defp ensure_restore_enabled do
    case Versioning.ensure_restore_enabled({:project_snapshot_restore, "full"}) do
      :ok -> :ok
      {:error, reason} -> {:error, normalize_restore_policy_error(reason)}
    end
  end

  defp normalize_snapshot_request_error(reason) when reason in [:limit_reached, :snapshot_limit_reached],
    do: :pre_import_snapshot_capacity_unavailable

  defp normalize_snapshot_request_error(:unauthorized), do: :unauthorized
  defp normalize_snapshot_request_error(:invalid_snapshot_request), do: :invalid_import_snapshot_request
  defp normalize_snapshot_request_error(_reason), do: :pre_import_snapshot_request_failed

  defp normalize_restore_policy_error(:restore_temporarily_disabled), do: :project_snapshot_restore_disabled

  defp normalize_restore_policy_error(reason), do: reason
end
