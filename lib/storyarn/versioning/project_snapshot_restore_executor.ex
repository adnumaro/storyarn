defmodule Storyarn.Versioning.ProjectSnapshotRestoreExecutor do
  @moduledoc """
  Executes one exact, verified full-project snapshot restore.

  Archive and asset-provider work is completed before the final database
  transaction. The transaction then replaces only the project's active graph
  and active asset catalog, preserving its previous recoverable trash, and
  atomically completes both the storage reservation and restore operation.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Accounts.Scope
  alias Storyarn.Accounts.User
  alias Storyarn.Assets
  alias Storyarn.Assets.Asset
  alias Storyarn.Assets.Storage
  alias Storyarn.Assets.StorageCompensation
  alias Storyarn.Assets.StorageHash
  alias Storyarn.Billing
  alias Storyarn.Billing.StorageCleanupInventory
  alias Storyarn.Billing.StorageReservation
  alias Storyarn.Flows
  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowConnection
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.SequenceConfig
  alias Storyarn.Flows.SequenceTrack
  alias Storyarn.Flows.SequenceVisualLayer
  alias Storyarn.Flows.VariableReferenceTracker
  alias Storyarn.Localization.GlossaryEntry
  alias Storyarn.Localization.LocalizedText
  alias Storyarn.Localization.ProjectLanguage
  alias Storyarn.Projects
  alias Storyarn.Projects.Project
  alias Storyarn.Projects.ProjectMembership
  alias Storyarn.References
  alias Storyarn.References.EntityReference
  alias Storyarn.References.RichTextMentions
  alias Storyarn.References.VariableReference
  alias Storyarn.Repo
  alias Storyarn.Scenes
  alias Storyarn.Scenes.Scene
  alias Storyarn.Scenes.SceneAmbientFlow
  alias Storyarn.Scenes.SceneAnnotation
  alias Storyarn.Scenes.SceneConnection
  alias Storyarn.Scenes.SceneLayer
  alias Storyarn.Scenes.ScenePin
  alias Storyarn.Scenes.SceneZone
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Sheets
  alias Storyarn.Sheets.Block
  alias Storyarn.Sheets.BlockGalleryImage
  alias Storyarn.Sheets.Sheet
  alias Storyarn.Sheets.SheetAvatar
  alias Storyarn.Sheets.TableColumn
  alias Storyarn.Sheets.TableRow
  alias Storyarn.Versioning
  alias Storyarn.Versioning.Builders.ProjectSnapshotBuilder
  alias Storyarn.Versioning.ProjectRecovery
  alias Storyarn.Versioning.ProjectSnapshot
  alias Storyarn.Versioning.ProjectSnapshotArchiveReader
  alias Storyarn.Versioning.ProjectSnapshotAssetMaterializer
  alias Storyarn.Versioning.ProjectSnapshotRestore
  alias Storyarn.Versioning.RestorePolicy

  @phase_rank %{"preflight" => 0, "staging" => 1, "materializing" => 2, "verifying" => 3}
  @compensation_context_key {__MODULE__, :compensation_context}
  @localization_actor_fields ~w(translated_by_id reviewed_by_id)
  @retryable_storage_reasons [
    :eagain,
    :eio,
    :emfile,
    :enfile,
    :enomem,
    :estale,
    :etimedout,
    :timeout,
    :unexpected_eof
  ]
  @type result ::
          {:ok, %{required(:result_digest) => String.t(), optional(atom()) => term()}}
          | {:error, term()}
          | {:retry, term()}
          | {:snooze, pos_integer()}

  @spec execute(ProjectSnapshotRestore.t(), keyword()) :: result()
  def execute(%ProjectSnapshotRestore{status: "completed"} = restore, opts) when is_list(opts),
    do: completed_result(restore)

  def execute(%ProjectSnapshotRestore{status: "running"} = restore, opts) when is_list(opts) do
    reader = Keyword.get(opts, :archive_reader, ProjectSnapshotArchiveReader)
    materializer = Keyword.get(opts, :asset_materializer, ProjectSnapshotAssetMaterializer)
    recovery = Keyword.get(opts, :project_recovery, ProjectRecovery)
    tracker = StorageCompensation.new()
    Process.delete(@compensation_context_key)

    try do
      with {:ok, context} <- preflight(restore, reader, materializer, recovery, opts),
           {:ok, context} <- recover_or_reuse_bound_reservation(context),
           {:ok, context} <- reserve_and_bind(context),
           :ok <- remember_compensation_context(context),
           {:ok, context} <- stage_archive_blobs(context, reader, tracker),
           :ok <- remember_compensation_context(context),
           {:ok, context} <- stage_destination_objects(context, tracker),
           {:ok, result} <- commit_restore(context, tracker) do
        StorageCompensation.discard(tracker)
        Process.delete(@compensation_context_key)
        {:ok, result}
      else
        {:error, {:preflight, reason}} ->
          StorageCompensation.discard(tracker)
          Process.delete(@compensation_context_key)

          if retryable_archive_read_failure?(reason),
            do: {:retry, {:snapshot_archive_storage_unavailable, reason}},
            else: {:error, reason}

        {:error, {:project_snapshot_restore_reservation_recovered, _reservation_id}} ->
          StorageCompensation.discard(tracker)
          Process.delete(@compensation_context_key)
          {:snooze, 1}

        {:error, {:project_snapshot_restore_reservation_recovery_failed, _reason}} ->
          StorageCompensation.discard(tracker)
          Process.delete(@compensation_context_key)
          {:snooze, 30}

        {:error, reason} ->
          compensate_failure(restore, tracker, reason, opts)
      end
    rescue
      error ->
        compensate_failure(
          restore,
          tracker,
          {:project_snapshot_restore_exception, Exception.message(error)},
          opts
        )
    catch
      kind, reason ->
        compensate_failure(restore, tracker, {:project_snapshot_restore_failure, kind, reason}, opts)
    end
  end

  def execute(%ProjectSnapshotRestore{}, _opts), do: {:error, :invalid_project_snapshot_restore_state}
  def execute(_restore, _opts), do: {:error, :invalid_project_snapshot_restore_request}

  @doc false
  @spec settle_bound_reservation(ProjectSnapshotRestore.t(), keyword()) :: :ok | {:error, term()}
  def settle_bound_reservation(restore, opts \\ [])

  def settle_bound_reservation(%ProjectSnapshotRestore{id: restore_id}, opts) when is_list(opts) do
    restore = current_restore(restore_id)

    case bound_reservation(restore) do
      %StorageReservation{status: "active", storage_started_at: nil} = reservation ->
        release_fun =
          Keyword.get(opts, :settlement_release_reservation, &Billing.release_storage_reservation/4)

        release_without_writes(reservation, release_fun)

      %StorageReservation{status: "active"} = reservation ->
        cleanup_keys = Map.get(reservation, :cleanup_storage_keys)

        persist_fun =
          Keyword.get(
            opts,
            :settlement_persist_cleanup,
            &StorageCompensation.persist_planned_cleanup_request/1
          )

        release_fun =
          Keyword.get(opts, :settlement_release_reservation, &Billing.release_storage_reservation/4)

        release_stored_inventory(reservation, cleanup_keys, persist_fun, release_fun)

      %StorageReservation{} ->
        :ok

      nil ->
        :ok
    end
  end

  def settle_bound_reservation(_restore, _opts), do: {:error, :invalid_project_snapshot_restore_request}

  defp preflight(restore, reader, materializer, recovery, opts) do
    with :ok <- RestorePolicy.ensure_enabled({:project_snapshot_restore, "full"}),
         %ProjectSnapshotRestore{} = restore <- current_restore(restore.id),
         :ok <- validate_execution_fence(restore),
         %ProjectSnapshot{} = snapshot <- Repo.get(ProjectSnapshot, restore.project_snapshot_id),
         :ok <- validate_snapshot_identity(restore, snapshot),
         %Project{deleted_at: nil} = project <- Repo.get(Project, restore.project_id),
         true <- project.workspace_id == restore.workspace_id,
         %User{} = actor <- Repo.get(User, restore.requested_by_id),
         {:ok, %Project{id: project_id, deleted_at: nil}, _membership} <-
           Projects.authorize(Scope.for_user(actor), project.id, :manage_project),
         true <- project_id == restore.project_id,
         {:ok, archive_plan} <- reader.verify(snapshot),
         :ok <- validate_canonical_project_fields(project, archive_plan.project),
         bound_reservation = bound_reservation(restore),
         lease_token = reservation_lease_token(bound_reservation),
         staging_prefix = staging_prefix(project.id, lease_token),
         staging_keys = staging_keys(archive_plan.manifest, staging_prefix),
         {:ok, asset_plan} <-
           prepare_asset_plan(
             materializer,
             project.id,
             lease_token,
             archive_plan.manifest,
             archive_plan.project,
             staging_prefix,
             staging_keys
           ) do
      staging_inventory = staging_inventory(archive_plan.manifest, staging_keys)

      reservation_mode =
        reservation_mode(
          restore,
          bound_reservation,
          asset_plan,
          staging_prefix,
          staging_inventory
        )

      reservation_key = reservation_key(restore, bound_reservation, reservation_mode, lease_token)

      {:ok,
       %{
         restore: restore,
         snapshot: snapshot,
         project: project,
         actor: actor,
         archive_plan: archive_plan,
         asset_plan: asset_plan,
         materializer: materializer,
         recovery: recovery,
         trash_active_assets: Keyword.get(opts, :trash_active_assets, &trash_active_assets/2),
         bound_reservation: bound_reservation,
         reservation_mode: reservation_mode,
         reservation_key: reservation_key,
         lease_token: lease_token,
         staging_prefix: staging_prefix,
         staging_keys: staging_keys,
         staging_inventory: staging_inventory,
         after_final_authorization: Keyword.get(opts, :after_final_authorization, fn _membership -> :ok end),
         before_postverify: Keyword.get(opts, :before_postverify, fn -> :ok end)
       }}
    else
      nil -> {:error, {:preflight, :project_snapshot_restore_target_not_found}}
      false -> {:error, {:preflight, :project_snapshot_restore_identity_mismatch}}
      {:error, reason} -> {:error, {:preflight, reason}}
    end
  end

  defp prepare_asset_plan(materializer, project_id, lease_token, manifest, project, prefix, keys) do
    materializer.prepare(project_id, lease_token, manifest, project, prefix, keys, materialization_mode: :exact)
  end

  defp validate_execution_fence(%ProjectSnapshotRestore{} = restore), do: validate_running_restore(restore)

  defp validate_running_restore(%ProjectSnapshotRestore{
         id: id,
         status: "running",
         phase: phase,
         generation: generation,
         attempt: attempt,
         workspace_id: workspace_id,
         project_id: project_id,
         project_snapshot_id: snapshot_id,
         requested_by_id: actor_id
       }) do
    if phase in ["preflight", "staging", "materializing", "verifying"] and
         positive_integers?([id, generation, attempt, workspace_id, project_id, snapshot_id, actor_id]),
       do: :ok,
       else: {:error, :invalid_project_snapshot_restore_state}
  end

  defp validate_running_restore(_restore), do: {:error, :invalid_project_snapshot_restore_state}

  defp validate_snapshot_identity(restore, snapshot) do
    exact? =
      Enum.all?([
        snapshot.project_id == restore.project_id,
        snapshot.lifecycle_state == "ready",
        snapshot.integrity_state == "verified",
        snapshot.format_version == 2,
        snapshot.mode == "full",
        snapshot.restore_contract_version == 1,
        snapshot.lifecycle_generation == restore.snapshot_lifecycle_generation,
        snapshot.accounting_generation == restore.snapshot_accounting_generation,
        snapshot.archive_storage_key == restore.archive_storage_key,
        snapshot.archive_size_bytes == restore.archive_size_bytes,
        snapshot.archive_checksum == restore.archive_checksum,
        snapshot.manifest_storage_key == restore.manifest_storage_key,
        snapshot.manifest_size_bytes == restore.manifest_size_bytes,
        snapshot.manifest_checksum == restore.manifest_checksum
      ])

    if exact?, do: :ok, else: {:error, :project_snapshot_restore_identity_mismatch}
  end

  @project_field_keys MapSet.new(~w(
    name description project_type project_subtype project_type_other settings
    auto_version_flows auto_version_scenes auto_version_sheets
  ))

  defp validate_canonical_project_fields(project, %{"project" => attrs}) when is_map(attrs) do
    exact_keys? = attrs |> Map.keys() |> MapSet.new() |> MapSet.equal?(@project_field_keys)

    if exact_keys? and technically_valid_project_fields?(attrs) and is_integer(project.id) and project.id > 0,
      do: :ok,
      else: {:error, :invalid_project_snapshot_project_fields}
  end

  defp validate_canonical_project_fields(_project, _project_data), do: {:error, :invalid_project_snapshot_project_fields}

  defp technically_valid_project_fields?(attrs) do
    technically_valid_project_text_fields?(attrs) and
      technically_valid_project_settings?(attrs) and
      technically_valid_project_version_flags?(attrs)
  end

  defp technically_valid_project_text_fields?(attrs) do
    is_binary(attrs["name"]) and
      nullable_binary?(attrs["description"]) and
      nullable_binary?(attrs["project_type"]) and
      nullable_binary?(attrs["project_subtype"]) and
      nullable_binary?(attrs["project_type_other"])
  end

  defp technically_valid_project_settings?(attrs) do
    is_map(attrs["settings"]) or is_nil(attrs["settings"])
  end

  defp technically_valid_project_version_flags?(attrs) do
    is_boolean(attrs["auto_version_flows"]) and
      is_boolean(attrs["auto_version_scenes"]) and
      is_boolean(attrs["auto_version_sheets"])
  end

  defp nullable_binary?(value), do: is_nil(value) or is_binary(value)

  defp bound_reservation(%ProjectSnapshotRestore{storage_reservation_id: nil}), do: nil

  defp bound_reservation(%ProjectSnapshotRestore{storage_reservation_id: reservation_id}),
    do: Repo.get(StorageReservation, reservation_id)

  defp reservation_lease_token(%StorageReservation{status: "active", lease_token: lease_token}), do: lease_token
  defp reservation_lease_token(_reservation), do: Ecto.UUID.generate()

  defp reservation_mode(_restore, nil, _asset_plan, _prefix, _inventory), do: :new

  defp reservation_mode(_restore, %StorageReservation{status: status}, _asset_plan, _prefix, _inventory)
       when status in ["released", "committed"], do: :new

  defp reservation_mode(restore, %StorageReservation{status: "active"} = reservation, asset_plan, prefix, inventory) do
    if reusable_bound_reservation?(restore, reservation, asset_plan, prefix, inventory),
      do: :reuse,
      else: :recover
  end

  defp reservation_mode(_restore, _reservation, _asset_plan, _prefix, _inventory), do: :recover

  defp reusable_bound_reservation?(restore, reservation, asset_plan, prefix, inventory) do
    identity_matches? =
      Enum.all?([
        restore.storage_reservation_id == reservation.id,
        restore.storage_reservation_lease_token == reservation.lease_token,
        reservation.kind == "restore_staging",
        reservation.workspace_id_snapshot == restore.workspace_id,
        reservation.project_id_snapshot == restore.project_id,
        reservation.project_snapshot_id_snapshot == restore.project_snapshot_id,
        reservation.reserved_bytes == asset_plan.logical_bytes,
        reservation.storage_namespace == prefix,
        reservation.cleanup_object_prefix == prefix
      ])

    cleanup_matches? = reusable_cleanup_inventory?(reservation, asset_plan, inventory)

    identity_matches? and cleanup_matches? and unexpired_reservation?(reservation)
  end

  defp reusable_cleanup_inventory?(%StorageReservation{storage_started_at: nil} = reservation, _asset_plan, _inventory) do
    is_nil(reservation.cleanup_inventory_digest) and is_nil(reservation.cleanup_inventory_count)
  end

  defp reusable_cleanup_inventory?(reservation, asset_plan, inventory) do
    keys = reservation_cleanup_keys(%{staging_inventory: inventory, asset_plan: asset_plan})

    Enum.all?([
      reservation.cleanup_inventory_count == length(keys),
      reservation.cleanup_inventory_digest == StorageCleanupInventory.digest(keys),
      reservation.cleanup_storage_keys == Enum.sort(keys)
    ])
  end

  defp positive_integers?(values), do: Enum.all?(values, &(is_integer(&1) and &1 > 0))

  defp unexpired_reservation?(%StorageReservation{expires_at: %DateTime{} = expires_at}),
    do: DateTime.after?(expires_at, TimeHelpers.now())

  defp unexpired_reservation?(_reservation), do: false

  defp reservation_key(
         _restore,
         %StorageReservation{status: "active", idempotency_key: idempotency_key},
         :reuse,
         _lease_token
       ), do: idempotency_key

  defp reservation_key(restore, _reservation, _mode, lease_token),
    do: "project-snapshot-restore:#{restore.id}:lease:#{lease_token}"

  defp staging_prefix(project_id, lease_token),
    do: "projects/#{project_id}/storage-reservations/v1/restore-staging/#{lease_token}"

  defp staging_keys(manifest, prefix) do
    manifest["objects"]
    |> Enum.filter(&(&1["kind"] == "asset_blob"))
    |> Map.new(&{&1["path"], prefix <> "/" <> &1["path"]})
  end

  defp staging_inventory(manifest, keys) do
    manifest["objects"]
    |> Enum.filter(&(&1["kind"] == "asset_blob"))
    |> Enum.sort_by(& &1["path"])
    |> Enum.map(fn object ->
      %{
        path: object["path"],
        storage_key: Map.fetch!(keys, object["path"]),
        size: object["size_bytes"],
        sha256: object["sha256"],
        content_type: object["content_type"]
      }
    end)
  end

  defp recover_or_reuse_bound_reservation(%{reservation_mode: mode} = context) when mode in [:new, :reuse],
    do: {:ok, context}

  defp recover_or_reuse_bound_reservation(%{reservation_mode: :recover} = context) do
    reservation = context.bound_reservation

    with :ok <- persist_crash_recovery_ownership(context),
         :ok <- release_bound_reservation(reservation, context) do
      {:error, {:project_snapshot_restore_reservation_recovered, reservation.id}}
    else
      {:error, reason} -> {:error, {:project_snapshot_restore_reservation_recovery_failed, reason}}
    end
  end

  defp reserve_and_bind(context) do
    with {:ok, restore} <- ensure_phase(current_restore(context.restore.id), "staging"),
         attrs = reservation_attrs(context, restore),
         {:ok, {restore, reservation}} <-
           Versioning.reserve_and_bind_project_snapshot_restore(restore.id, restore.generation, attrs) do
      {:ok, context |> Map.put(:restore, restore) |> Map.put(:reservation, reservation)}
    else
      {:error, reason, details} -> {:error, {reason, details}}
      {:error, _reason} = error -> error
    end
  end

  defp reservation_attrs(context, restore) do
    %{
      workspace_id: restore.workspace_id,
      project_id: restore.project_id,
      project_snapshot_id: restore.project_snapshot_id,
      idempotency_key: context.reservation_key,
      kind: "restore_staging",
      reserved_bytes: context.asset_plan.logical_bytes,
      lease_token: context.lease_token
    }
  end

  defp stage_archive_blobs(%{staging_inventory: []} = context, _reader, _tracker), do: {:ok, context}

  defp stage_archive_blobs(context, reader, tracker) do
    reservation = context.reservation
    storage_keys = reservation_cleanup_keys(context)
    cleanup_plan = %{temporary_prefix: reservation.storage_namespace, storage_keys: storage_keys}

    with {:ok, reservation} <-
           Billing.mark_storage_reservation_started(
             reservation.id,
             reservation.lease_token,
             reservation.generation,
             cleanup_plan
           ),
         :ok <- track_staging_inventory(tracker, storage_keys),
         :ok <- upload_staging_inventory(context.archive_plan, context.staging_inventory, reader) do
      {:ok, %{context | reservation: reservation}}
    end
  end

  defp track_staging_inventory(tracker, keys) do
    Enum.each(keys, &StorageCompensation.track_force_delete(tracker, &1))
    :ok
  end

  defp upload_staging_inventory(archive_plan, inventory, reader) do
    Enum.reduce_while(inventory, :ok, fn blob, :ok ->
      case ensure_staged_blob(archive_plan, blob, reader) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp ensure_staged_blob(archive_plan, blob, reader) do
    case verify_staged_blob(blob) do
      :ok ->
        :ok

      {:error, :enoent} ->
        with {:ok, chunks} <- reader.stream_entry(archive_plan, blob.path),
             {:ok, _url} <- Storage.upload_stream(blob.storage_key, chunks, blob.content_type) do
          verify_staged_blob(blob)
        end

      {:error, _reason} = error ->
        error
    end
  end

  defp verify_staged_blob(blob) do
    with {:ok, %{size: size}} <- Storage.stat(blob.storage_key),
         true <- size == blob.size,
         {:ok, chunks} <- Storage.stream(blob.storage_key, 0, blob.size),
         {:ok, checksum} <- StorageHash.sha256_chunks(chunks),
         true <- checksum == blob.sha256 do
      :ok
    else
      false -> {:error, {:snapshot_staging_blob_mismatch, blob.path}}
      {:error, :enoent} -> {:error, :enoent}
      {:error, reason} -> {:error, {:snapshot_staging_blob_verification_failed, blob.path, reason}}
    end
  end

  defp stage_destination_objects(context, tracker) do
    with {:ok, restore} <- ensure_phase(current_restore(context.restore.id), "materializing"),
         :ok <- context.materializer.stage_destination_objects(context.asset_plan, tracker),
         {:ok, restore} <- ensure_phase(restore, "verifying") do
      {:ok, %{context | restore: restore}}
    end
  end

  defp ensure_phase(%ProjectSnapshotRestore{phase: phase} = restore, desired) do
    current_rank = Map.get(@phase_rank, phase)
    desired_rank = Map.fetch!(@phase_rank, desired)

    cond do
      is_nil(current_rank) ->
        {:error, :invalid_project_snapshot_restore_phase}

      current_rank >= desired_rank ->
        {:ok, restore}

      current_rank + 1 == desired_rank ->
        Versioning.advance_project_snapshot_restore_phase(restore.id, restore.generation, desired)

      true ->
        {:error, :invalid_project_snapshot_restore_phase_transition}
    end
  end

  defp current_restore(restore_id), do: Repo.get(ProjectSnapshotRestore, restore_id)

  defp remember_compensation_context(context) do
    Process.put(@compensation_context_key, context)
    :ok
  end

  # Final transaction implementation follows below. Keeping the provider
  # pipeline separate makes it impossible for archive I/O to occur while
  # project rows are locked.
  defp commit_restore(context, tracker) do
    reservation = context.reservation

    case Billing.commit_project_snapshot_restore_reservation(
           reservation.id,
           reservation.lease_token,
           reservation.generation,
           context.asset_plan.logical_bytes,
           &prelock_localization_actors(&1, context),
           &commit_owner(&1, &2, context, tracker)
         ) do
      {:ok, %{result: :already_committed}} -> completed_result(current_restore(context.restore.id))
      {:ok, %{result: %ProjectSnapshotRestore{} = completed}} -> completed_result(completed)
      {:error, _reason} = error -> error
    end
  end

  defp prelock_localization_actors(%{workspace: _workspace, project: project}, context) do
    required_actor_ids = [context.restore.requested_by_id, project.owner_id]

    case context.recovery.lock_materializable_localization_actors(
           context.archive_plan.project,
           required_actor_ids: required_actor_ids,
           additional_actor_ids: Enum.reject([project.deleted_by_id], &is_nil/1)
         ) do
      {:ok, %MapSet{} = actor_ids} ->
        if Enum.all?(required_actor_ids, &MapSet.member?(actor_ids, &1)),
          do: {:ok, actor_ids},
          else: {:error, :project_snapshot_restore_required_actor_unavailable_during_prelock}

      {:error, _reason} = error ->
        error

      _invalid ->
        {:error, :invalid_project_snapshot_restore_localization_actor_prelock}
    end
  end

  defp prelock_localization_actors(_locked_parents, _context),
    do: {:error, :invalid_project_snapshot_restore_lock_context}

  defp commit_owner(_reservation, preserved_localization_actor_ids, context, tracker) do
    with {:ok, locked} <- lock_and_reauthorize(context, preserved_localization_actor_ids),
         :ok <- RestorePolicy.ensure_enabled({:project_snapshot_restore, "full"}),
         {:ok, previous} <- capture_active_state(locked.project.id),
         :ok <- trash_active_graph(previous),
         :ok <- reconcile_localization_before_materialization(locked.project.id, context.archive_plan.project),
         :ok <- context.trash_active_assets.(previous, locked.actor.id),
         {:ok, adoption} <-
           context.materializer.adopt_locked(
             context.asset_plan,
             locked.project,
             locked.actor.id,
             tracker
           ),
         {:ok, project} <- restore_project_fields(locked.project, context.archive_plan.project),
         {:ok,
          %{
            id_maps: id_maps,
            preserved_localization_actor_ids: ^preserved_localization_actor_ids
          }} <-
           context.recovery.materialize_into_project(
             project,
             context.archive_plan.project,
             locked.actor.id,
             adoption.source_id_map,
             localization_scope: :active,
             materialization_mode: :exact,
             preserved_localization_actor_ids: preserved_localization_actor_ids
           ),
         :ok <- context.materializer.verify_adopted_locked(context.asset_plan, adoption.logical_id_map),
         :ok <- context.before_postverify.(),
         {:ok, semantic_digest} <-
           postverify_restore(
             project.id,
             context.archive_plan.project,
             previous,
             id_maps,
             adoption.source_id_map,
             preserved_localization_actor_ids
           ),
         {:ok, cleanup_request_id} <- persist_staging_cleanup(context) do
      result = build_result(context, cleanup_request_id, semantic_digest, previous)

      locked.restore
      |> ProjectSnapshotRestore.complete_changeset(result, TimeHelpers.now())
      |> Repo.update()
    end
  end

  defp lock_and_reauthorize(context, preserved_localization_actor_ids) do
    # StorageAccounting owns the lock order and invokes us only after locking
    # workspace -> project -> available localization actors -> restore ->
    # snapshot -> reservation. The User pass uses SKIP LOCKED: a concurrent
    # delete can therefore never invert a parent/restore FK wait against this
    # transaction.
    with %Project{deleted_at: nil} = project <- Repo.get(Project, context.project.id),
         %ProjectSnapshotRestore{status: "running", phase: "verifying"} = restore <-
           Repo.get(ProjectSnapshotRestore, context.restore.id),
         %ProjectSnapshot{} = snapshot <- Repo.get(ProjectSnapshot, context.snapshot.id),
         :ok <- validate_snapshot_identity(restore, snapshot),
         true <- restore.generation == context.restore.generation,
         true <- restore.storage_reservation_id == context.reservation.id,
         true <- restore.requested_by_id == context.actor.id,
         true <- MapSet.member?(preserved_localization_actor_ids, context.actor.id),
         %User{} = actor <- context.actor,
         %ProjectMembership{} = membership <- lock_project_membership(project.id, actor.id),
         true <- ProjectMembership.can?(membership.role, :manage_project),
         :ok <- context.after_final_authorization.(membership) do
      {:ok, %{project: project, restore: restore, snapshot: snapshot, actor: actor}}
    else
      nil -> {:error, :project_snapshot_restore_target_not_found}
      false -> {:error, :project_snapshot_restore_fence_mismatch}
      {:error, reason} -> {:error, reason}
      _invalid -> {:error, :project_snapshot_restore_fence_mismatch}
    end
  end

  defp lock_project_membership(project_id, user_id) do
    Repo.one(
      from membership in ProjectMembership,
        where: membership.project_id == ^project_id and membership.user_id == ^user_id,
        lock: "FOR SHARE"
    )
  end

  defp capture_active_state(project_id) do
    sheets = Repo.all(from sheet in Sheet, where: sheet.project_id == ^project_id and is_nil(sheet.deleted_at))
    flows = Repo.all(from flow in Flow, where: flow.project_id == ^project_id and is_nil(flow.deleted_at))
    scenes = Repo.all(from scene in Scene, where: scene.project_id == ^project_id and is_nil(scene.deleted_at))

    sheet_ids = Enum.map(sheets, & &1.id)
    flow_ids = Enum.map(flows, & &1.id)
    scene_ids = Enum.map(scenes, & &1.id)

    sources = %{
      "block" => active_child_ids(Block, :sheet_id, sheet_ids),
      "flow_node" => active_child_ids(FlowNode, :flow_id, flow_ids),
      "scene_pin" => child_ids(ScenePin, :scene_id, scene_ids),
      "scene_zone" => child_ids(SceneZone, :scene_id, scene_ids),
      "scene_ambient_flow" => child_ids(SceneAmbientFlow, :scene_id, scene_ids)
    }

    sources =
      Map.merge(sources, %{
        "sheet" => sheet_ids,
        "flow" => flow_ids,
        "scene" => scene_ids
      })

    {:ok,
     %{
       project_id: project_id,
       sheet_roots: Enum.filter(sheets, &is_nil(&1.parent_id)),
       flow_roots: Enum.filter(flows, &is_nil(&1.parent_id)),
       scene_roots: Enum.filter(scenes, &is_nil(&1.parent_id)),
       sources: sources,
       asset_ids: project_id |> Assets.list_assets_for_export() |> Enum.map(& &1.id)
     }}
  end

  defp active_child_ids(_schema, _parent_field, []), do: []

  defp active_child_ids(schema, parent_field, parent_ids) do
    Repo.all(
      from child in schema,
        where: field(child, ^parent_field) in ^parent_ids and is_nil(child.deleted_at),
        select: child.id
    )
  end

  defp child_ids(_schema, _parent_field, []), do: []

  defp child_ids(schema, parent_field, parent_ids) do
    Repo.all(from child in schema, where: field(child, ^parent_field) in ^parent_ids, select: child.id)
  end

  defp trash_active_graph(previous) do
    with :ok <-
           trash_roots(
             previous.flow_roots,
             &Flows.delete_flow_subtree_for_project_restore_in_transaction/1
           ),
         :ok <- trash_roots(previous.scene_roots, &trash_scene/1) do
      trash_roots(previous.sheet_roots, &Sheets.delete_sheet_subtree_in_transaction/1)
    end
  end

  defp trash_roots(roots, delete_fun) do
    Enum.reduce_while(roots, :ok, fn root, :ok ->
      case delete_fun.(root) do
        %{entity: _entity} -> {:cont, :ok}
        {:ok, %{entity: _entity}} -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
        _invalid -> {:halt, {:error, :project_snapshot_restore_trash_failed}}
      end
    end)
  end

  defp trash_scene(scene) do
    Scenes.delete_scene_subtree_in_transaction(scene)
  end

  defp reconcile_localization_before_materialization(project_id, _project_data) do
    now = TimeHelpers.now()

    Repo.update_all(
      from(language in ProjectLanguage,
        where: language.project_id == ^project_id and is_nil(language.archived_at)
      ),
      set: [archived_at: now, updated_at: now]
    )

    # Subtree trashing archives the localization rows it can reach. Any
    # remaining active row is inconsistent current-project state (for example,
    # an orphaned historical source type), but it still belongs in recovery
    # trash rather than being destroyed or left active beside the restored
    # exact graph.
    Repo.update_all(
      from(text in LocalizedText,
        where: text.project_id == ^project_id and is_nil(text.archived_at)
      ),
      set: [archived_at: now, archive_reason: "version_replaced", updated_at: now]
    )

    Repo.delete_all(from entry in GlossaryEntry, where: entry.project_id == ^project_id)
    :ok
  end

  defp trash_active_assets(%{asset_ids: []}, _actor_id), do: :ok

  defp trash_active_assets(previous, actor_id) do
    case Assets.move_assets_to_trash_locked(previous.project_id, actor_id, previous.asset_ids) do
      {:ok, %Asset{}} -> :ok
      {:error, _reason} = error -> error
    end
  end

  defp restore_project_fields(project, project_data) do
    attrs =
      Map.new(@project_field_keys, fn key ->
        {String.to_existing_atom(key), Map.fetch!(project_data["project"], key)}
      end)

    project |> Ecto.Changeset.change(attrs) |> Repo.update()
  end

  defp postverify_restore(project_id, project_data, previous, id_maps, source_id_map, preserved_localization_actor_ids) do
    expected = project_data["entity_counts"]
    expected_graph = expected_graph_inventory(project_data)

    with :ok <- verify_active_count(Sheet, project_id, expected["sheets"]),
         :ok <- verify_active_count(Flow, project_id, expected["flows"]),
         :ok <- verify_active_count(Scene, project_id, expected["scenes"]),
         :ok <- verify_graph_inventory(project_id, expected_graph),
         :ok <- verify_localization_inventory(project_id, project_data),
         :ok <- rebuild_active_reference_sources(project_id),
         :ok <- verify_previous_roots_trashed(previous),
         :ok <- verify_project_fields(project_id, project_data["project"]) do
      verify_semantic_snapshot(
        project_id,
        project_data,
        id_maps,
        source_id_map,
        preserved_localization_actor_ids
      )
    end
  end

  defp verify_semantic_snapshot(project_id, expected, id_maps, source_id_map, preserved_localization_actor_ids) do
    actual =
      project_id
      |> ProjectSnapshotBuilder.build_canonical_snapshot_in_transaction(localization_scope: :active)
      |> normalize_json()

    expected_source =
      expected
      |> normalize_json()
      |> normalize_expected_localization_actors(preserved_localization_actor_ids)

    source_maps = %{mode: :identity, ids: %{}}
    destination_maps = %{mode: :forward, ids: Map.put(id_maps, :asset, source_id_map)}

    with {:ok, variable_plan} <-
           VariableReferenceTracker.prepare_exact_project_snapshot(expected_source),
         {:ok, expected_rewritten} <-
           VariableReferenceTracker.rewrite_portable_project_snapshot(
             expected_source,
             variable_plan,
             Map.fetch!(id_maps, :sheet)
           ) do
      expected_destination = canonical_semantic_snapshot(expected_rewritten, destination_maps)
      actual_destination = canonical_semantic_snapshot(actual, source_maps)

      if actual_destination == expected_destination do
        {:ok,
         expected_source
         |> canonical_semantic_snapshot(source_maps)
         |> semantic_digest()}
      else
        {:error,
         {:project_snapshot_restore_semantic_mismatch,
          first_semantic_difference(expected_destination, actual_destination)}}
      end
    end
  end

  defp normalize_expected_localization_actors(snapshot, preserved_actor_ids) do
    snapshot
    |> update_in(["localization", "texts"], &normalize_expected_localization_rows(&1, preserved_actor_ids))
    |> normalize_expected_entity_localization("sheets", preserved_actor_ids)
    |> normalize_expected_entity_localization("flows", preserved_actor_ids)
  end

  defp normalize_expected_entity_localization(snapshot, collection, preserved_actor_ids) do
    update_in(snapshot, [collection], fn entries ->
      Enum.map(entries, fn entry ->
        update_in(
          entry,
          ["snapshot", "localization"],
          &normalize_expected_localization_rows(&1, preserved_actor_ids)
        )
      end)
    end)
  end

  defp normalize_expected_localization_rows(rows, preserved_actor_ids) do
    Enum.map(rows, fn text ->
      Enum.reduce(
        @localization_actor_fields,
        text,
        &normalize_expected_localization_actor(&1, &2, preserved_actor_ids)
      )
    end)
  end

  defp normalize_expected_localization_actor(field, text, preserved_actor_ids) do
    case Map.fetch(text, field) do
      {:ok, actor_id} -> Map.put(text, field, expected_actor_id(actor_id, preserved_actor_ids))
      :error -> text
    end
  end

  defp expected_actor_id(actor_id, preserved_actor_ids) do
    if MapSet.member?(preserved_actor_ids, actor_id), do: actor_id
  end

  defp first_semantic_difference(expected, actual), do: first_semantic_difference(expected, actual, [])

  defp first_semantic_difference(expected, actual, path) when is_map(expected) and is_map(actual) do
    (Map.keys(expected) ++ Map.keys(actual))
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.find_value(fn key ->
      case {Map.fetch(expected, key), Map.fetch(actual, key)} do
        {{:ok, left}, {:ok, right}} -> first_semantic_difference(left, right, path ++ [key])
        {_left, _right} -> path ++ [key]
      end
    end)
  end

  defp first_semantic_difference([], [], _path), do: nil

  defp first_semantic_difference(expected, actual, path) when is_list(expected) and is_list(actual) do
    max_length = max(length(expected), length(actual))

    Enum.find_value(0..(max_length - 1), fn index ->
      compare_semantic_list_entry(expected, actual, path, index)
    end)
  end

  defp first_semantic_difference(value, value, _path), do: nil

  defp first_semantic_difference(_expected, _actual, path), do: path

  defp compare_semantic_list_entry(expected, actual, path, index) do
    case {Enum.fetch(expected, index), Enum.fetch(actual, index)} do
      {{:ok, left}, {:ok, right}} -> first_semantic_difference(left, right, path ++ [index])
      {_left, _right} -> path ++ [index]
    end
  end

  defp normalize_json(value), do: value |> Jason.encode!() |> Jason.decode!()

  # Only fields whose schema declares an entity identity are rewritten. A
  # value-based walk is unsafe because PostgreSQL sequences from unrelated
  # tables collide and ordinary business integers (positions, dimensions,
  # settings) can equal an entity ID.
  defp canonical_semantic_snapshot(snapshot, maps) do
    maps = Map.put(maps, :mention_block_ids, rich_text_block_ids(snapshot))

    snapshot
    |> Map.take(~w(format_version project entity_counts sheets flows scenes tree localization))
    |> Map.update!("sheets", &Enum.map(&1, fn entry -> canonical_sheet_entry(entry, maps) end))
    |> Map.update!("flows", &Enum.map(&1, fn entry -> canonical_flow_entry(entry, maps) end))
    |> Map.update!("scenes", &Enum.map(&1, fn entry -> canonical_scene_entry(entry, maps) end))
    |> Map.update!("tree", &canonical_tree(&1, maps))
    |> Map.update!("localization", &canonical_project_localization(&1, maps))
  end

  defp canonical_sheet_entry(entry, maps) do
    entry
    |> Map.update!("id", &canonical_id(&1, :sheet, maps))
    |> Map.update!("snapshot", &canonical_sheet_snapshot(&1, maps))
  end

  defp canonical_sheet_snapshot(snapshot, maps) do
    snapshot
    |> Map.drop(~w(asset_blob_hashes asset_metadata localization_manifest))
    |> Map.update!("original_id", &canonical_id(&1, :sheet, maps))
    |> Map.update!("avatar_asset_id", &canonical_id(&1, :asset, maps))
    |> Map.update!("banner_asset_id", &canonical_id(&1, :asset, maps))
    |> Map.update!("avatars", &Enum.map(&1, fn avatar -> canonical_avatar(avatar, maps) end))
    |> Map.update!("hidden_inherited_block_ids", fn
      nil -> nil
      ids -> Enum.map(ids, &canonical_authored_id(&1, :block, maps))
    end)
    |> Map.update!("blocks", &Enum.map(&1, fn block -> canonical_block(block, maps) end))
    |> Map.update!("localization", &canonical_localization_rows(&1, maps))
  end

  defp canonical_avatar(avatar, maps) do
    avatar
    |> Map.update!("original_id", &canonical_id(&1, :avatar, maps))
    |> Map.update!("asset_id", &canonical_id(&1, :asset, maps))
  end

  defp canonical_block(block, maps) do
    block
    |> Map.update!("original_id", &canonical_id(&1, :block, maps))
    |> Map.update!("inherited_from_block_id", &canonical_authored_id(&1, :block, maps))
    |> Map.update!("value", &canonical_block_value(block["type"], &1, maps))
    |> update_if_present("table_data", &canonical_table_data(&1, maps))
    |> update_if_present("gallery_images", fn images ->
      Enum.map(images, &canonical_gallery_image(&1, maps))
    end)
  end

  defp canonical_block_value("reference", value, maps) when is_map(value) do
    canonical_typed_target(value, maps, %{"sheet" => :sheet, "flow" => :flow})
  end

  defp canonical_block_value("rich_text", value, maps), do: canonical_mentions(value, maps)
  defp canonical_block_value(_type, value, _maps), do: value

  defp canonical_table_data(table_data, _maps) do
    table_data
    |> Map.update!("columns", &Enum.map(&1, fn column -> Map.delete(column, "original_id") end))
    |> Map.update!("rows", &Enum.map(&1, fn row -> Map.delete(row, "original_id") end))
  end

  defp canonical_gallery_image(image, maps) do
    image
    |> Map.delete("original_id")
    |> Map.update!("asset_id", &canonical_id(&1, :asset, maps))
  end

  defp canonical_flow_entry(entry, maps) do
    entry
    |> Map.update!("id", &canonical_id(&1, :flow, maps))
    |> Map.update!("snapshot", &canonical_flow_snapshot(&1, maps))
  end

  defp canonical_flow_snapshot(snapshot, maps) do
    nodes = snapshot["nodes"]

    snapshot
    |> Map.drop(~w(asset_blob_hashes asset_metadata localization_manifest referenced_sheets))
    |> Map.update!("original_id", &canonical_id(&1, :flow, maps))
    |> Map.update!("scene_id", &canonical_id(&1, :scene, maps))
    |> Map.update!("nodes", &Enum.map(&1, fn node -> canonical_flow_node(node, maps) end))
    |> Map.update!("connections", fn connections ->
      Enum.map(connections, &canonical_flow_connection(&1, nodes, maps))
    end)
    |> Map.update!("localization", &canonical_localization_rows(&1, maps))
  end

  defp canonical_flow_node(node, maps) do
    node
    |> Map.update!("original_id", &canonical_id(&1, :node, maps))
    |> Map.update!("parent_id", &canonical_authored_id(&1, :node, maps))
    |> Map.update!("data", &canonical_flow_node_data(&1, maps))
    |> update_if_present("sequence_tracks", fn tracks ->
      Enum.map(tracks, &canonical_sequence_resource(&1, maps))
    end)
    |> update_if_present("sequence_visual_layers", fn layers ->
      Enum.map(layers, &canonical_sequence_resource(&1, maps))
    end)
  end

  defp canonical_flow_node_data(data, maps) do
    data
    |> canonical_mentions(maps)
    |> update_if_present("speaker_sheet_id", &canonical_authored_id(&1, :sheet, maps))
    |> update_if_present("location_sheet_id", &canonical_authored_id(&1, :sheet, maps))
    |> update_if_present("referenced_flow_id", &canonical_authored_id(&1, :flow, maps))
    |> update_if_present("avatar_id", &canonical_authored_id(&1, :avatar, maps))
    |> update_if_present("audio_asset_id", &canonical_id(&1, :asset, maps))
    |> canonical_typed_target(maps, %{"flow" => :flow, "scene" => :scene})
  end

  defp canonical_sequence_resource(resource, maps) do
    resource
    |> Map.delete("original_id")
    |> Map.update!("asset_id", &canonical_id(&1, :asset, maps))
  end

  defp canonical_flow_connection(connection, nodes, maps) do
    connection
    |> Map.delete("original_id")
    |> update_if_present("source_node_id", &canonical_id(&1, :node, maps))
    |> update_if_present("target_node_id", &canonical_id(&1, :node, maps))
    |> update_dynamic_subflow_exit_pin(nodes, maps)
  end

  defp update_dynamic_subflow_exit_pin(connection, nodes, maps) do
    case Enum.at(nodes, connection["source_node_index"]) do
      %{"type" => "subflow"} ->
        Map.update!(connection, "source_pin", &canonical_dynamic_exit_pin(&1, maps))

      _ordinary_source ->
        connection
    end
  end

  defp canonical_dynamic_exit_pin("exit_" <> id_text = pin, maps) do
    case Integer.parse(id_text) do
      {id, ""} -> "exit_#{canonical_authored_id_text(id, :node, maps)}"
      _invalid -> pin
    end
  end

  defp canonical_dynamic_exit_pin(pin, _maps), do: pin

  defp canonical_scene_entry(entry, maps) do
    entry
    |> Map.update!("id", &canonical_id(&1, :scene, maps))
    |> Map.update!("snapshot", &canonical_scene_snapshot(&1, maps))
  end

  defp canonical_scene_snapshot(snapshot, maps) do
    snapshot
    |> Map.drop(~w(asset_blob_hashes asset_metadata))
    |> Map.update!("original_id", &canonical_id(&1, :scene, maps))
    |> Map.update!("background_asset_id", &canonical_id(&1, :asset, maps))
    |> Map.update!("layers", &Enum.map(&1, fn layer -> canonical_scene_layer(layer, maps) end))
    |> Map.update!("orphan_zones", &Enum.map(&1, fn zone -> canonical_scene_zone(zone, maps) end))
    |> Map.update!("orphan_pins", &Enum.map(&1, fn pin -> canonical_scene_pin(pin, maps) end))
    |> Map.update!("orphan_annotations", fn annotations ->
      Enum.map(annotations, &Map.delete(&1, "original_id"))
    end)
    |> Map.update!("connections", &Enum.map(&1, fn connection -> canonical_scene_connection(connection, maps) end))
    |> Map.update!("ambient_flows", &Enum.map(&1, fn ambient -> canonical_ambient_flow(ambient, maps) end))
  end

  defp canonical_scene_layer(layer, maps) do
    layer
    |> Map.delete("original_id")
    |> Map.update!("zones", &Enum.map(&1, fn zone -> canonical_scene_zone(zone, maps) end))
    |> Map.update!("pins", &Enum.map(&1, fn pin -> canonical_scene_pin(pin, maps) end))
    |> Map.update!("annotations", &Enum.map(&1, fn annotation -> Map.delete(annotation, "original_id") end))
  end

  defp canonical_scene_zone(zone, maps) do
    zone
    |> Map.delete("original_id")
    |> Map.update!("label_icon_asset_id", &canonical_id(&1, :asset, maps))
    |> canonical_typed_target(maps, %{"sheet" => :sheet, "flow" => :flow, "scene" => :scene})
    |> canonical_collection_action(maps)
  end

  defp canonical_collection_action(%{"action_type" => "collection", "action_data" => action_data} = zone, maps)
       when is_map(action_data) do
    action_data =
      update_if_present(action_data, "items", fn items ->
        Enum.map(items, fn item ->
          update_if_present(item, "sheet_id", &canonical_authored_id(&1, :sheet, maps))
        end)
      end)

    Map.put(zone, "action_data", action_data)
  end

  defp canonical_collection_action(zone, _maps), do: zone

  defp canonical_scene_pin(pin, maps) do
    pin
    |> Map.update!("original_id", &canonical_id(&1, :pin, maps))
    |> Map.update!("sheet_id", &canonical_id(&1, :sheet, maps))
    |> Map.update!("flow_id", &canonical_id(&1, :flow, maps))
    |> Map.update!("icon_asset_id", &canonical_id(&1, :asset, maps))
  end

  defp canonical_scene_connection(connection, maps) do
    connection
    |> Map.delete("original_id")
    |> Map.update!("from_pin_original_id", &canonical_id(&1, :pin, maps))
    |> Map.update!("to_pin_original_id", &canonical_id(&1, :pin, maps))
  end

  defp canonical_ambient_flow(ambient, maps) do
    ambient
    |> Map.delete("original_id")
    |> Map.update!("flow_id", &canonical_id(&1, :flow, maps))
  end

  defp canonical_tree(tree, maps) do
    tree
    |> Map.update!("sheets", &Enum.map(&1, fn item -> canonical_tree_item(item, :sheet, maps) end))
    |> Map.update!("flows", &Enum.map(&1, fn item -> canonical_tree_item(item, :flow, maps) end))
    |> Map.update!("scenes", &Enum.map(&1, fn item -> canonical_tree_item(item, :scene, maps) end))
  end

  defp canonical_tree_item(item, kind, maps) do
    item
    |> Map.update!("id", &canonical_id(&1, kind, maps))
    |> Map.update!("parent_id", &canonical_authored_id(&1, kind, maps))
  end

  defp canonical_project_localization(localization, maps) do
    Map.update!(localization, "texts", &canonical_localization_rows(&1, maps))
  end

  defp canonical_localization_rows(rows, maps) do
    rows
    |> Enum.map(&canonical_localization_row(&1, maps))
    |> Enum.sort_by(fn row ->
      {row["source_type"], row["source_id"], row["source_field"], row["locale_code"]}
    end)
  end

  defp canonical_localization_row(row, maps) do
    old_source_hash = row["source_text_hash"]
    mention_capable? = mention_capable_localization?(row, maps.mention_block_ids)
    source_text = if mention_capable?, do: canonical_mentions(row["source_text"], maps), else: row["source_text"]

    translated_text =
      if mention_capable?, do: canonical_mentions(row["translated_text"], maps), else: row["translated_text"]

    source_hash = hash_semantic_source_text(source_text)

    translated_source_hash =
      if row["translated_source_hash"] == old_source_hash,
        do: source_hash,
        else: row["translated_source_hash"]

    row
    |> Map.put("source_text", source_text)
    |> Map.put("source_text_hash", source_hash)
    |> Map.put("translated_text", translated_text)
    |> Map.put("translated_source_hash", translated_source_hash)
    |> Map.update!("source_id", &canonical_source_id(row["source_type"], &1, maps))
    |> Map.update!("speaker_sheet_id", &canonical_authored_id(&1, :sheet, maps))
    |> Map.update!("vo_asset_id", &canonical_id(&1, :asset, maps))
  end

  defp canonical_source_id("sheet", id, maps), do: canonical_authored_id(id, :sheet, maps)
  defp canonical_source_id("block", id, maps), do: canonical_authored_id(id, :block, maps)
  defp canonical_source_id("flow_node", id, maps), do: canonical_authored_id(id, :node, maps)
  defp canonical_source_id(_source_type, id, _maps), do: id

  defp rich_text_block_ids(snapshot) do
    snapshot["sheets"]
    |> Enum.flat_map(&get_in(&1, ["snapshot", "blocks"]))
    |> Enum.filter(&(&1["type"] == "rich_text"))
    |> MapSet.new(& &1["original_id"])
  end

  defp mention_capable_localization?(%{"source_type" => "flow_node"}, _block_ids), do: true

  defp mention_capable_localization?(
         %{"source_type" => "block", "source_id" => source_id, "source_field" => "value.content"},
         block_ids
       ) do
    MapSet.member?(block_ids, source_id)
  end

  defp mention_capable_localization?(_row, _block_ids), do: false

  defp hash_semantic_source_text(text) when is_binary(text) do
    text |> then(&:crypto.hash(:sha256, &1)) |> Base.encode16(case: :lower)
  end

  defp hash_semantic_source_text(_text), do: nil

  defp canonical_typed_target(%{"target_type" => type, "target_id" => id} = value, maps, kinds) when not is_nil(id) do
    case Map.fetch(kinds, type) do
      {:ok, kind} -> Map.put(value, "target_id", canonical_authored_id(id, kind, maps))
      :error -> value
    end
  end

  defp canonical_typed_target(value, _maps, _kinds), do: value

  defp canonical_id(nil, _kind, _maps), do: nil
  defp canonical_id(value, _kind, %{mode: :identity}), do: value

  defp canonical_id(value, kind, %{mode: :forward, ids: ids}) do
    kind
    |> then(&Map.get(ids, &1, %{}))
    |> fetch_canonical_id(value)
    |> case do
      {:ok, destination_id} -> destination_id
      :error -> %{"missing_restore_id" => Atom.to_string(kind), "source_id" => value}
    end
  end

  defp canonical_authored_id(nil, _kind, _maps), do: nil
  defp canonical_authored_id(value, _kind, %{mode: :identity}), do: value

  defp canonical_authored_id(value, kind, %{mode: :forward, ids: ids}) do
    kind
    |> then(&Map.get(ids, &1, %{}))
    |> fetch_canonical_id(value)
    |> case do
      {:ok, destination_id} -> destination_id
      :error -> value
    end
  end

  defp fetch_canonical_id(mapping, value) do
    case Map.fetch(mapping, value) do
      {:ok, _destination} = found -> found
      :error -> fetch_string_canonical_id(mapping, value)
    end
  end

  defp fetch_string_canonical_id(mapping, value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> Map.fetch(mapping, integer)
      _invalid -> :error
    end
  end

  defp fetch_string_canonical_id(_mapping, _value), do: :error

  defp canonical_authored_id_text(value, kind, maps), do: value |> canonical_authored_id(kind, maps) |> to_string()

  defp update_if_present(map, key, fun) do
    case Map.fetch(map, key) do
      {:ok, value} -> Map.put(map, key, fun.(value))
      :error -> map
    end
  end

  defp canonical_mentions(value, maps) when is_list(value) do
    Enum.map(value, &canonical_mentions(&1, maps))
  end

  defp canonical_mentions(value, maps) when is_map(value) do
    Map.new(value, fn {key, nested} -> {key, canonical_mentions(nested, maps)} end)
  end

  defp canonical_mentions(value, maps) when is_binary(value) do
    if RichTextMentions.html_candidates(value) == [] do
      value
    else
      case Floki.parse_fragment(value) do
        {:ok, nodes} -> nodes |> canonical_mention_nodes(maps) |> Floki.raw_html()
        {:error, _reason} -> value
      end
    end
  end

  defp canonical_mentions(value, _maps), do: value

  defp canonical_mention_nodes(nodes, maps) when is_list(nodes) do
    Enum.map(nodes, &canonical_mention_node(&1, maps))
  end

  defp canonical_mention_node({tag, attributes, children}, maps) do
    attributes = attributes |> canonical_mention_attributes(maps) |> Enum.sort()
    {tag, attributes, canonical_mention_nodes(children, maps)}
  end

  defp canonical_mention_node(node, _maps), do: node

  defp canonical_mention_attributes(attributes, maps) do
    classes = attributes |> mention_attribute("class") |> to_string() |> String.split()

    if "mention" in classes do
      type = mention_attribute(attributes, "data-type")

      with {:ok, kind} <- Map.fetch(%{"sheet" => :sheet, "flow" => :flow}, type),
           id_text when is_binary(id_text) <- mention_attribute(attributes, "data-id"),
           {id, ""} <- Integer.parse(id_text) do
        List.keystore(attributes, "data-id", 0, {"data-id", canonical_authored_id_text(id, kind, maps)})
      else
        _invalid -> attributes
      end
    else
      attributes
    end
  end

  defp mention_attribute(attributes, name) do
    case List.keyfind(attributes, name, 0) do
      {^name, value} -> value
      nil -> nil
    end
  end

  defp semantic_digest(snapshot) do
    snapshot
    |> Jason.encode!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp expected_graph_inventory(project_data) do
    sheet_snapshots = Enum.map(project_data["sheets"], & &1["snapshot"])
    flow_snapshots = Enum.map(project_data["flows"], & &1["snapshot"])
    scene_snapshots = Enum.map(project_data["scenes"], & &1["snapshot"])
    blocks = Enum.flat_map(sheet_snapshots, & &1["blocks"])
    nodes = Enum.flat_map(flow_snapshots, & &1["nodes"])
    scene_layers = Enum.flat_map(scene_snapshots, & &1["layers"])

    %{
      Block => length(blocks),
      SheetAvatar => Enum.reduce(sheet_snapshots, 0, &(length(&1["avatars"]) + &2)),
      TableColumn => nested_table_count(blocks, "columns"),
      TableRow => nested_table_count(blocks, "rows"),
      BlockGalleryImage => Enum.reduce(blocks, 0, &(length(&1["gallery_images"] || []) + &2)),
      FlowNode => length(nodes),
      FlowConnection => Enum.reduce(flow_snapshots, 0, &(length(&1["connections"]) + &2)),
      SequenceConfig => Enum.count(nodes, &is_map(&1["sequence_config"])),
      SequenceTrack => Enum.reduce(nodes, 0, &(length(&1["sequence_tracks"] || []) + &2)),
      SequenceVisualLayer => Enum.reduce(nodes, 0, &(length(&1["sequence_visual_layers"] || []) + &2)),
      SceneLayer => length(scene_layers),
      ScenePin => scene_child_count(scene_snapshots, scene_layers, "pins", "orphan_pins"),
      SceneZone => scene_child_count(scene_snapshots, scene_layers, "zones", "orphan_zones"),
      SceneAnnotation => scene_child_count(scene_snapshots, scene_layers, "annotations", "orphan_annotations"),
      SceneConnection => Enum.reduce(scene_snapshots, 0, &(length(&1["connections"]) + &2)),
      SceneAmbientFlow => Enum.reduce(scene_snapshots, 0, &(length(&1["ambient_flows"]) + &2))
    }
  end

  defp nested_table_count(blocks, collection) do
    Enum.reduce(blocks, 0, fn block, count ->
      count + length(get_in(block, ["table_data", collection]) || [])
    end)
  end

  defp scene_child_count(scene_snapshots, layers, layer_collection, orphan_collection) do
    layer_count = Enum.reduce(layers, 0, &(length(&1[layer_collection]) + &2))
    orphan_count = Enum.reduce(scene_snapshots, 0, &(length(&1[orphan_collection]) + &2))
    layer_count + orphan_count
  end

  defp verify_graph_inventory(project_id, expected_graph) do
    ids = active_graph_ids(project_id)

    Enum.reduce_while(expected_graph, :ok, fn {schema, expected}, :ok ->
      actual = active_graph_count(schema, ids)

      if actual == expected,
        do: {:cont, :ok},
        else: {:halt, {:error, {:project_snapshot_restore_count_mismatch, schema, expected, actual}}}
    end)
  end

  defp active_graph_ids(project_id) do
    sheet_ids =
      Repo.all(from sheet in Sheet, where: sheet.project_id == ^project_id and is_nil(sheet.deleted_at), select: sheet.id)

    flow_ids =
      Repo.all(from flow in Flow, where: flow.project_id == ^project_id and is_nil(flow.deleted_at), select: flow.id)

    scene_ids =
      Repo.all(from scene in Scene, where: scene.project_id == ^project_id and is_nil(scene.deleted_at), select: scene.id)

    block_ids = active_child_ids(Block, :sheet_id, sheet_ids)
    node_ids = active_child_ids(FlowNode, :flow_id, flow_ids)
    layer_ids = child_ids(SceneLayer, :scene_id, scene_ids)

    %{
      sheet_ids: sheet_ids,
      block_ids: block_ids,
      flow_ids: flow_ids,
      node_ids: node_ids,
      scene_ids: scene_ids,
      layer_ids: layer_ids
    }
  end

  defp active_graph_count(Block, ids), do: length(ids.block_ids)
  defp active_graph_count(FlowNode, ids), do: length(ids.node_ids)
  defp active_graph_count(SceneLayer, ids), do: length(ids.layer_ids)
  defp active_graph_count(SheetAvatar, ids), do: count_by_parent(SheetAvatar, :sheet_id, ids.sheet_ids)
  defp active_graph_count(TableColumn, ids), do: count_by_parent(TableColumn, :block_id, ids.block_ids)
  defp active_graph_count(TableRow, ids), do: count_by_parent(TableRow, :block_id, ids.block_ids)
  defp active_graph_count(BlockGalleryImage, ids), do: count_by_parent(BlockGalleryImage, :block_id, ids.block_ids)
  defp active_graph_count(FlowConnection, ids), do: count_by_parent(FlowConnection, :flow_id, ids.flow_ids)
  defp active_graph_count(SequenceConfig, ids), do: count_by_parent(SequenceConfig, :flow_node_id, ids.node_ids)
  defp active_graph_count(SequenceTrack, ids), do: count_by_parent(SequenceTrack, :flow_node_id, ids.node_ids)
  defp active_graph_count(SequenceVisualLayer, ids), do: count_by_parent(SequenceVisualLayer, :flow_node_id, ids.node_ids)
  defp active_graph_count(ScenePin, ids), do: count_by_parent(ScenePin, :scene_id, ids.scene_ids)
  defp active_graph_count(SceneZone, ids), do: count_by_parent(SceneZone, :scene_id, ids.scene_ids)
  defp active_graph_count(SceneAnnotation, ids), do: count_by_parent(SceneAnnotation, :scene_id, ids.scene_ids)
  defp active_graph_count(SceneConnection, ids), do: count_by_parent(SceneConnection, :scene_id, ids.scene_ids)
  defp active_graph_count(SceneAmbientFlow, ids), do: count_by_parent(SceneAmbientFlow, :scene_id, ids.scene_ids)

  defp count_by_parent(_schema, _parent_field, []), do: 0

  defp count_by_parent(schema, parent_field, ids) do
    Repo.aggregate(from(row in schema, where: field(row, ^parent_field) in ^ids), :count)
  end

  defp verify_localization_inventory(project_id, project_data) do
    localization = project_data["localization"]

    with :ok <- verify_unarchived_count(ProjectLanguage, project_id, length(localization["languages"])),
         :ok <- verify_unarchived_count(LocalizedText, project_id, length(localization["texts"])) do
      verify_plain_count(GlossaryEntry, project_id, length(localization["glossary"]))
    end
  end

  defp verify_unarchived_count(schema, project_id, expected) do
    actual =
      Repo.aggregate(
        from(entity in schema, where: entity.project_id == ^project_id and is_nil(entity.archived_at)),
        :count
      )

    if actual == expected,
      do: :ok,
      else: {:error, {:project_snapshot_restore_count_mismatch, schema, expected, actual}}
  end

  defp verify_plain_count(schema, project_id, expected) do
    actual = Repo.aggregate(from(row in schema, where: row.project_id == ^project_id), :count)

    if actual == expected,
      do: :ok,
      else: {:error, {:project_snapshot_restore_count_mismatch, schema, expected, actual}}
  end

  defp rebuild_active_reference_sources(project_id) do
    ids = active_graph_ids(project_id)
    before = active_reference_inventory(ids)

    with :ok <- References.rebuild_project_entity_references(project_id),
         :ok <- delete_active_variable_references(ids),
         :ok <- References.rebuild_project_variable_references(project_id),
         true <- before == active_reference_inventory(ids) do
      :ok
    else
      false -> {:error, :project_snapshot_restore_active_reference_mismatch}
      {:error, _reason} = error -> error
    end
  end

  defp delete_active_variable_references(ids) do
    pins = child_ids(ScenePin, :scene_id, ids.scene_ids)
    zones = child_ids(SceneZone, :scene_id, ids.scene_ids)
    ambient_flows = child_ids(SceneAmbientFlow, :scene_id, ids.scene_ids)

    Enum.each(
      %{
        "flow_node" => ids.node_ids,
        "scene_pin" => pins,
        "scene_zone" => zones,
        "scene_ambient_flow" => ambient_flows
      },
      fn
        {_source_type, []} ->
          :ok

        {source_type, source_ids} ->
          Repo.delete_all(
            from(ref in VariableReference,
              where: ref.source_type == ^source_type and ref.source_id in ^source_ids
            )
          )
      end
    )

    :ok
  end

  defp active_reference_inventory(ids) do
    pins = child_ids(ScenePin, :scene_id, ids.scene_ids)
    zones = child_ids(SceneZone, :scene_id, ids.scene_ids)
    ambient_flows = child_ids(SceneAmbientFlow, :scene_id, ids.scene_ids)

    %{
      entity:
        semantic_entity_references(%{
          "block" => ids.block_ids,
          "flow_node" => ids.node_ids,
          "scene_pin" => pins,
          "scene_zone" => zones
        }),
      variable:
        semantic_variable_references(%{
          "flow_node" => ids.node_ids,
          "scene_pin" => pins,
          "scene_zone" => zones,
          "scene_ambient_flow" => ambient_flows
        })
    }
  end

  defp semantic_entity_references(sources) do
    sources
    |> Enum.flat_map(fn {source_type, source_ids} ->
      if source_ids == [] do
        []
      else
        Repo.all(
          from(ref in EntityReference,
            where: ref.source_type == ^source_type and ref.source_id in ^source_ids,
            select: {ref.source_type, ref.source_id, ref.target_type, ref.target_id, ref.context}
          )
        )
      end
    end)
    |> Enum.sort()
  end

  defp semantic_variable_references(sources) do
    sources
    |> Enum.flat_map(fn {source_type, source_ids} ->
      if source_ids == [] do
        []
      else
        Repo.all(
          from(ref in VariableReference,
            where: ref.source_type == ^source_type and ref.source_id in ^source_ids,
            select:
              {ref.source_type, ref.source_id, ref.flow_node_id, ref.block_id, ref.kind, ref.source_sheet,
               ref.source_variable}
          )
        )
      end
    end)
    |> Enum.sort()
  end

  defp verify_project_fields(project_id, expected) do
    project = Repo.get!(Project, project_id)
    actual = Map.new(@project_field_keys, &{&1, Map.get(project, String.to_existing_atom(&1))})

    if actual == expected,
      do: :ok,
      else: {:error, :project_snapshot_restore_project_fields_mismatch}
  end

  defp verify_active_count(schema, project_id, expected) do
    actual =
      Repo.aggregate(
        from(entity in schema, where: entity.project_id == ^project_id and is_nil(entity.deleted_at)),
        :count
      )

    if actual == expected, do: :ok, else: {:error, {:project_snapshot_restore_count_mismatch, schema, expected, actual}}
  end

  defp verify_previous_roots_trashed(previous) do
    checks = [{Sheet, previous.sheet_roots}, {Flow, previous.flow_roots}, {Scene, previous.scene_roots}]

    if Enum.all?(checks, &roots_trashed?/1) do
      :ok
    else
      {:error, :project_snapshot_restore_previous_graph_not_trashed}
    end
  end

  defp roots_trashed?({_schema, []}), do: true

  defp roots_trashed?({schema, roots}) do
    ids = Enum.map(roots, & &1.id)

    Repo.aggregate(
      from(entity in schema, where: entity.id in ^ids and not is_nil(entity.deleted_at)),
      :count
    ) == length(ids)
  end

  defp persist_staging_cleanup(%{staging_inventory: []}), do: {:ok, nil}

  defp persist_staging_cleanup(context) do
    keys = Enum.map(context.staging_inventory, & &1.storage_key)

    with {:ok, request} <- StorageCompensation.persist_planned_cleanup_request(keys),
         true <- MapSet.new(request.storage_keys) == MapSet.new(keys) do
      {:ok, request.id}
    else
      false -> {:error, :project_snapshot_restore_cleanup_inventory_mismatch}
      {:error, _reason} = error -> error
    end
  end

  defp build_result(context, cleanup_request_id, semantic_digest, previous) do
    base = %{
      reservation_id: context.reservation.id,
      cleanup_request_id: cleanup_request_id,
      snapshot_id: context.snapshot.id,
      semantic_digest: semantic_digest,
      restored_asset_count: length(context.asset_plan.assets),
      restored_logical_bytes: context.asset_plan.logical_bytes,
      content_replaced: true,
      replaced_sheet_ids: replaced_source_ids(previous, "sheet"),
      replaced_flow_ids: replaced_source_ids(previous, "flow"),
      replaced_scene_ids: replaced_source_ids(previous, "scene")
    }

    digest =
      base
      |> :erlang.term_to_binary([:deterministic])
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)

    Map.put(base, :result_digest, digest)
  end

  defp completed_result(%ProjectSnapshotRestore{status: "completed", result_digest: digest} = restore)
       when is_binary(digest) do
    result = atomize_result(restore.result)
    {:ok, Map.put(result, :result_digest, digest)}
  end

  defp completed_result(_restore), do: {:error, :project_snapshot_restore_commit_replay_mismatch}

  defp atomize_result(result) when is_map(result) do
    Map.new(result, fn
      {"reservation_id", value} -> {:reservation_id, value}
      {"cleanup_request_id", value} -> {:cleanup_request_id, value}
      {"snapshot_id", value} -> {:snapshot_id, value}
      {"semantic_digest", value} -> {:semantic_digest, value}
      {"restored_asset_count", value} -> {:restored_asset_count, value}
      {"restored_logical_bytes", value} -> {:restored_logical_bytes, value}
      {"content_replaced", value} -> {:content_replaced, value}
      {"replaced_sheet_ids", value} -> {:replaced_sheet_ids, value}
      {"replaced_flow_ids", value} -> {:replaced_flow_ids, value}
      {"replaced_scene_ids", value} -> {:replaced_scene_ids, value}
      {key, value} -> {key, value}
    end)
  end

  defp replaced_source_ids(previous, source_type) do
    previous.sources
    |> Map.fetch!(source_type)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp retryable_archive_read_failure?(reason), do: retryable_storage_failure?(reason)

  defp retryable_storage_failure?(%Req.TransportError{}), do: true
  defp retryable_storage_failure?(%Req.HTTPError{}), do: true

  defp retryable_storage_failure?({:http_error, status, _response})
       when status in [408, 409, 425, 429] or status in 500..599, do: true

  defp retryable_storage_failure?({kind, _key, reason})
       when kind in [:snapshot_archive_storage_read_failed, :snapshot_archive_storage_stat_failed],
       do: retryable_storage_failure?(reason)

  defp retryable_storage_failure?({:unexpected_length, actual, expected})
       when is_integer(actual) and is_integer(expected), do: true

  defp retryable_storage_failure?(reason) when reason in @retryable_storage_reasons, do: true

  defp retryable_storage_failure?(_reason), do: false

  defp compensate_failure(restore, tracker, reason, opts) do
    context = Process.get(@compensation_context_key)
    cleanup_fun = Keyword.get(opts, :cleanup_after_rollback, &cleanup_after_rollback(&1, context))
    release_fun = Keyword.get(opts, :release_reservation, &release_active_reservation/2)
    cleanup_result = cleanup_fun.(tracker)

    ownership_result =
      case cleanup_result do
        :ok -> :ok
        {:error, _reason} -> persist_failed_cleanup_ownership(tracker, cleanup_result)
      end

    release_result =
      if ownership_result == :ok,
        do: release_fun.(current_restore(restore.id), context),
        else: {:error, :project_snapshot_restore_cleanup_not_owned}

    Process.delete(@compensation_context_key)

    if ownership_result == :ok and release_result == :ok,
      do: {:retry, reason},
      else: {:snooze, 30}
  end

  defp cleanup_after_rollback(tracker, %{reservation: %StorageReservation{} = reservation}) do
    StorageCompensation.cleanup_after_rollback(tracker, restore_cleanup_owner: reservation)
  end

  defp cleanup_after_rollback(tracker, _context), do: StorageCompensation.cleanup_after_rollback(tracker)

  defp persist_failed_cleanup_ownership(tracker, cleanup_result) do
    cleanup_targets = cleanup_failure_targets(cleanup_result)

    cleanup_targets =
      if cleanup_targets == [],
        do: StorageCompensation.pending_cleanup_targets(tracker),
        else: cleanup_targets

    persist_cleanup_targets(cleanup_targets)
  end

  defp cleanup_failure_targets({:error, reason}), do: cleanup_failure_targets(reason)

  defp cleanup_failure_targets(%{failed_keys: keys}) when is_list(keys), do: Enum.uniq(keys)
  defp cleanup_failure_targets(%{"failed_keys" => keys}) when is_list(keys), do: Enum.uniq(keys)
  defp cleanup_failure_targets(%{cleanup_keys: keys}) when is_list(keys), do: Enum.uniq(keys)
  defp cleanup_failure_targets(%{"cleanup_keys" => keys}) when is_list(keys), do: Enum.uniq(keys)

  defp cleanup_failure_targets(reason) when is_tuple(reason) do
    reason
    |> Tuple.to_list()
    |> Enum.find_value([], fn value ->
      case cleanup_failure_targets(value) do
        [] -> nil
        keys -> keys
      end
    end)
  end

  defp cleanup_failure_targets(_reason), do: []

  defp persist_crash_recovery_ownership(%{bound_reservation: %StorageReservation{storage_started_at: nil}}), do: :ok

  defp persist_crash_recovery_ownership(context), do: context |> compensation_keys() |> persist_cleanup_targets()

  defp persist_cleanup_targets([]), do: :ok

  defp persist_cleanup_targets(keys) do
    keys
    |> Enum.uniq()
    |> StorageCompensation.persist_planned_cleanup_request()
    |> normalize_cleanup_ownership()
  end

  defp compensation_keys(context) do
    reservation_cleanup_keys(context)
  end

  defp reservation_cleanup_keys(context) do
    staging = Enum.map(context.staging_inventory, & &1.storage_key)
    blobs = Enum.map(context.asset_plan.blobs, & &1.destination_key)
    assets = Enum.map(context.asset_plan.assets, & &1.destination_key)
    Enum.uniq(staging ++ blobs ++ assets)
  end

  defp normalize_cleanup_ownership({:ok, _request}), do: :ok
  defp normalize_cleanup_ownership({:error, _reason} = error), do: error

  defp release_bound_reservation(%StorageReservation{status: "active", storage_started_at: nil} = reservation, _context),
    do: release_without_writes(reservation)

  defp release_bound_reservation(%StorageReservation{status: "active"} = reservation, context),
    do: release_with_cleanup(reservation, context)

  defp release_bound_reservation(%StorageReservation{}, _context), do: :ok
  defp release_bound_reservation(nil, _context), do: :ok

  defp release_active_reservation(%ProjectSnapshotRestore{storage_reservation_id: nil}, _context), do: :ok

  defp release_active_reservation(%ProjectSnapshotRestore{} = restore, context) do
    case Repo.get(StorageReservation, restore.storage_reservation_id) do
      %StorageReservation{status: "active", storage_started_at: nil} = reservation ->
        release_without_writes(reservation)

      %StorageReservation{status: "active"} = reservation ->
        if is_nil(context) do
          release_stored_inventory(
            reservation,
            reservation.cleanup_storage_keys,
            &StorageCompensation.persist_planned_cleanup_request/1,
            &Billing.release_storage_reservation/4
          )
        else
          release_with_cleanup(reservation, context)
        end

      %StorageReservation{} ->
        :ok

      nil ->
        :ok
    end
  end

  defp release_active_reservation(_restore, _context), do: :ok

  defp release_without_writes(reservation) do
    release_without_writes(reservation, &Billing.release_storage_reservation/4)
  end

  defp release_without_writes(reservation, release_fun) when is_function(release_fun, 4) do
    attrs = %{
      reason: "snapshot_restore_failed",
      cleanup_status: "not_required",
      cleanup_proof: %{
        type: "storage_not_started",
        storage_namespace: reservation.storage_namespace
      }
    }

    normalize_release(release_fun.(reservation.id, reservation.lease_token, reservation.generation, attrs))
  end

  defp release_stored_inventory(reservation, keys, persist_fun, release_fun)
       when is_list(keys) and keys != [] and is_function(persist_fun, 1) and is_function(release_fun, 4) do
    with {:ok, request} <- persist_fun.(keys),
         attrs = %{
           reason: "snapshot_restore_failed",
           cleanup_status: "owned",
           cleanup_request_id: request.id,
           cleanup_scope: %{
             cleanup_request_id: request.id,
             temporary_prefix: reservation.storage_namespace,
             storage_keys: keys
           }
         },
         {:ok, %StorageReservation{}} <-
           release_fun.(reservation.id, reservation.lease_token, reservation.generation, attrs) do
      :ok
    end
  end

  defp release_stored_inventory(_reservation, _keys, _persist_fun, _release_fun),
    do: {:error, :project_snapshot_restore_cleanup_inventory_missing}

  defp release_with_cleanup(_reservation, nil), do: {:error, :project_snapshot_restore_cleanup_context_missing}

  defp release_with_cleanup(reservation, context) do
    keys = reservation_cleanup_keys(context)

    with {:ok, request} <- StorageCompensation.persist_planned_cleanup_request(keys),
         attrs = %{
           reason: "snapshot_restore_failed",
           cleanup_status: "owned",
           cleanup_request_id: request.id,
           cleanup_scope: %{
             cleanup_request_id: request.id,
             temporary_prefix: reservation.storage_namespace,
             storage_keys: keys
           }
         },
         {:ok, _reservation} <-
           Billing.release_storage_reservation(
             reservation.id,
             reservation.lease_token,
             reservation.generation,
             attrs
           ) do
      :ok
    end
  end

  defp normalize_release({:ok, %StorageReservation{}}), do: :ok
  defp normalize_release({:error, _reason} = error), do: error
end
