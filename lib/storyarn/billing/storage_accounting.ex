defmodule Storyarn.Billing.StorageAccounting do
  @moduledoc """
  Authoritative product storage accounting and workspace-scoped reservations.

  Product usage is rebuilt from database ownership: retained logical assets,
  ready snapshot payloads, and active reservations. Provider object inventory
  is deliberately excluded; temporary, duplicate, orphaned, and
  cleanup-pending provider bytes are operational telemetry, not quota input.

  Synchronous writers may hold `with_workspace_lock/2` for their complete
  transaction. Background or multi-step writers reserve capacity, perform
  external work without holding the row lock, then atomically replace the
  reservation with durable billable ownership through `commit/4`.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Assets.Asset
  alias Storyarn.Assets.StorageCleanupOwnershipReceipt
  alias Storyarn.Billing.Plan
  alias Storyarn.Billing.StorageReservation
  alias Storyarn.Billing.SubscriptionCrud
  alias Storyarn.Projects.Project
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Versioning.ProjectSnapshot
  alias Storyarn.Versioning.ProjectSnapshotLeasePolicy
  alias Storyarn.Versioning.SnapshotArchiveStorage
  alias Storyarn.Versioning.SnapshotObjectFormat
  alias Storyarn.Versioning.SnapshotObjectPublicationClaim
  alias Storyarn.Workspaces.Workspace

  @accounting_version 1
  @default_reservation_ttl_seconds 24 * 60 * 60
  @expired_export_lease_recovery_batch_size 50
  @released_export_lease_purge_batch_size 50
  @reservation_kinds ~w(snapshot_build restore_staging snapshot_export)
  @exclusive_snapshot_operation_kinds ~w(snapshot_build)
  @snapshot_slot_lifecycle_states ~w(pending building verifying ready deleting)
  @workspace_lock_process_key {__MODULE__, :workspace_lock_ids}
  @storage_commit_process_key {__MODULE__, :storage_commit}
  @provider_measurement_keys ~w(
    physical_bytes temporary_bytes orphan_bytes duplicate_bytes cleanup_pending_bytes
  )a
  @snapshot_object_token_regex ~r/\A[A-Za-z0-9_-]{16}\z/
  @temporary_path_segment_regex ~r/\A[A-Za-z0-9][A-Za-z0-9._-]{0,127}\z/
  @max_temporary_relative_key_bytes 512
  @max_temporary_path_segments 16
  @max_cleanup_inventory_bytes 16 * 1024 * 1024

  defguardp is_positive_integer(value) when is_integer(value) and value > 0
  defguardp is_non_negative_integer(value) when is_integer(value) and value >= 0

  defguardp valid_fence(id, lease_token, generation)
            when is_positive_integer(id) and is_binary(lease_token) and
                   is_positive_integer(generation)

  @type usage_bucket :: %{bytes: non_neg_integer(), count: non_neg_integer()}

  @type storage_usage :: %{
          accounting_version: pos_integer(),
          measured_at: DateTime.t(),
          current_assets: usage_bucket(),
          asset_trash: usage_bucket(),
          full_snapshots: usage_bucket(),
          active_reservations: %{
            bytes: non_neg_integer(),
            count: non_neg_integer(),
            by_kind: %{String.t() => non_neg_integer()}
          },
          accounted_bytes: non_neg_integer()
        }

  @doc "Returns the current product-accounted storage categories for a workspace."
  @spec workspace_usage(pos_integer()) :: storage_usage()
  def workspace_usage(workspace_id) when is_integer(workspace_id) and workspace_id > 0 do
    consistent_read(fn ->
      assets = workspace_asset_usage(workspace_id)
      snapshots = workspace_snapshot_usage(workspace_id)
      reservations = workspace_reservation_usage(workspace_id)

      build_usage(assets, snapshots, reservations)
    end)
  end

  @doc "Returns the product-accounted storage categories owned by one project."
  @spec project_usage(pos_integer()) :: storage_usage()
  def project_usage(project_id) when is_integer(project_id) and project_id > 0 do
    consistent_read(fn ->
      assets = project_asset_usage(project_id)
      snapshots = project_snapshot_usage(project_id)
      reservations = project_reservation_usage(project_id)

      build_usage(assets, snapshots, reservations)
    end)
  end

  @doc "Returns the workspace/project usage and snapshot slots from one database view."
  @spec project_storage_context(pos_integer(), pos_integer()) :: %{
          workspace: storage_usage(),
          project: storage_usage(),
          snapshot_slots: non_neg_integer()
        }
  def project_storage_context(project_id, workspace_id)
      when is_integer(project_id) and project_id > 0 and is_integer(workspace_id) and workspace_id > 0 do
    consistent_read(fn ->
      %{
        workspace: workspace_usage(workspace_id),
        project: project_usage(project_id),
        snapshot_slots: snapshot_slots_used(project_id)
      }
    end)
  end

  @doc "Returns stored snapshots plus active build reservations for the count limit."
  @spec project_snapshot_slot_usage(pos_integer()) :: non_neg_integer()
  def project_snapshot_slot_usage(project_id) when is_integer(project_id) and project_id > 0 do
    consistent_read(fn -> snapshot_slots_used(project_id) end)
  end

  @doc "Returns active and export reservation bytes keyed by snapshot id."
  @spec active_reservations_by_snapshot([pos_integer()]) ::
          %{
            optional(pos_integer()) => %{
              active_bytes: non_neg_integer(),
              export_bytes: non_neg_integer(),
              active_count: non_neg_integer()
            }
          }
  def active_reservations_by_snapshot(snapshot_ids) when is_list(snapshot_ids) do
    ids = snapshot_ids |> Enum.filter(&(is_integer(&1) and &1 > 0)) |> Enum.uniq()

    if ids == [] do
      %{}
    else
      StorageReservation
      |> where([reservation], reservation.status == "active")
      |> where([reservation], reservation.project_snapshot_id_snapshot in ^ids)
      |> group_by([reservation], [reservation.project_snapshot_id_snapshot, reservation.kind])
      |> select([reservation], {
        reservation.project_snapshot_id_snapshot,
        reservation.kind,
        type(sum(reservation.reserved_bytes), :integer),
        count(reservation.id)
      })
      |> Repo.all()
      |> Enum.reduce(%{}, fn {snapshot_id, kind, bytes, count}, acc ->
        totals = Map.get(acc, snapshot_id, %{active_bytes: 0, export_bytes: 0, active_count: 0})

        totals = %{
          active_bytes: totals.active_bytes + bytes,
          export_bytes: totals.export_bytes + if(kind == "snapshot_export", do: bytes, else: 0),
          active_count: totals.active_count + count
        }

        Map.put(acc, snapshot_id, totals)
      end)
    end
  end

  @doc "Checks a requested allocation against exact product-accounted workspace bytes."
  @spec check_capacity(Workspace.t(), non_neg_integer()) ::
          :ok | {:error, :limit_reached, map()} | {:error, :invalid_storage_allocation}
  def check_capacity(%Workspace{} = workspace, requested_bytes)
      when is_integer(requested_bytes) and requested_bytes >= 0 do
    plan = SubscriptionCrud.plan_for(workspace)
    limit = Plan.limit(plan, :storage_bytes_per_workspace)
    usage = workspace_usage(workspace.id)

    check_capacity_limit(usage, requested_bytes, limit)
  end

  def check_capacity(%Workspace{}, _requested_bytes), do: {:error, :invalid_storage_allocation}

  @doc """
  Runs a short database transaction while holding the workspace row lock.

  Every storage-accounting writer uses this lock, in the order workspace then
  reservation/snapshot/asset. The callback result is returned inside the usual
  `Repo.transaction/2` tuple.
  """
  @spec with_workspace_lock(pos_integer(), (Workspace.t() -> result), keyword()) ::
          {:ok, result} | {:error, term()}
        when result: term()
  def with_workspace_lock(workspace_id, fun, opts \\ [])
      when is_integer(workspace_id) and workspace_id > 0 and is_function(fun, 1) and is_list(opts) do
    transaction_opts = Keyword.merge([timeout: :infinity], opts)

    Repo.transaction(
      fn ->
        workspace = lock_workspace(workspace_id) || Repo.rollback(:workspace_not_found)
        with_workspace_lock_marker(workspace_id, fn -> fun.(workspace) end)
      end,
      transaction_opts
    )
  end

  @doc "Runs a storage writer transaction under the common workspace-first lock."
  @spec transact_with_workspace_lock(pos_integer(), (Workspace.t() -> {:ok, result} | {:error, term()}), keyword()) ::
          {:ok, result} | {:error, term()}
        when result: term()
  def transact_with_workspace_lock(workspace_id, fun, opts \\ [])
      when is_integer(workspace_id) and workspace_id > 0 and is_function(fun, 1) and is_list(opts) do
    transaction_opts = Keyword.merge([timeout: :infinity], opts)

    Repo.transact(
      fn -> transact_locked(workspace_id, fun) end,
      transaction_opts
    )
  end

  defp transact_locked(workspace_id, fun) do
    case lock_workspace(workspace_id) do
      %Workspace{} = workspace ->
        with_workspace_lock_marker(workspace_id, fn -> fun.(workspace) end)

      nil ->
        {:error, :workspace_not_found}
    end
  end

  @doc "Returns true only inside this process' active common workspace lock."
  @spec workspace_lock_held?(pos_integer()) :: boolean()
  def workspace_lock_held?(workspace_id) when is_integer(workspace_id) and workspace_id > 0 do
    Repo.in_transaction?() and workspace_id in Process.get(@workspace_lock_process_key, [])
  end

  def workspace_lock_held?(_workspace_id), do: false

  @doc false
  @spec snapshot_commit_context?(pos_integer(), String.t()) :: boolean()
  def snapshot_commit_context?(snapshot_id, kind) when is_integer(snapshot_id) and snapshot_id > 0 and is_binary(kind) do
    case Process.get(@storage_commit_process_key) do
      %{
        project_snapshot_id: ^snapshot_id,
        kind: ^kind,
        workspace_id: workspace_id
      } ->
        workspace_lock_held?(workspace_id)

      _context ->
        false
    end
  end

  def snapshot_commit_context?(_snapshot_id, _kind), do: false

  @doc """
  Reserves product-accounted capacity using an idempotency key.

  Snapshot builds reserve their independent project snapshot-count slot under
  the same workspace lock. An exact replay returns the existing reservation;
  a conflicting replay fails without changing capacity.
  """
  @spec reserve(map()) ::
          {:ok, StorageReservation.t()}
          | {:error, :limit_reached, map()}
          | {:error, :reservation_conflict | :snapshot_limit_reached | term()}
  def reserve(attrs) when is_map(attrs) do
    attrs = normalize_reservation_attrs(attrs)

    with workspace_id when is_integer(workspace_id) and workspace_id > 0 <- attrs.workspace_id,
         true <- attrs.kind in @reservation_kinds do
      workspace_id
      |> locked_result(fn workspace -> reserve_locked(workspace, attrs) end)
      |> emit_after_mutation(workspace_id, :reserved)
    else
      _invalid -> {:error, :invalid_storage_reservation}
    end
  end

  def reserve(_attrs), do: {:error, :invalid_storage_reservation}

  @doc """
  Acquires the single application-level read lease for one ready snapshot.

  Repeated and concurrent grants renew the latest active zero-byte lease
  instead of appending one row per request. The common workspace lock and the
  reservation generation fence serialize acquisition with deletion and expiry
  recovery. Pre-existing duplicate leases are left to expire safely; this path
  never creates another one while any reusable lease remains active.
  """
  @spec acquire_snapshot_export_lease(map()) ::
          {:ok, StorageReservation.t()} | {:error, term()}
  def acquire_snapshot_export_lease(attrs) when is_map(attrs) do
    attrs =
      attrs
      |> Map.drop([:expires_at, "expires_at"])
      |> Map.put(:kind, "snapshot_export")
      |> Map.put(:reserved_bytes, 0)
      |> Map.put_new(:idempotency_key, "snapshot-download:#{Ecto.UUID.generate()}")
      |> normalize_reservation_attrs()

    case attrs.workspace_id do
      workspace_id when is_integer(workspace_id) and workspace_id > 0 ->
        workspace_id
        |> locked_result(fn workspace -> acquire_snapshot_export_lease_locked(workspace, attrs) end)
        |> emit_snapshot_export_lease_acquired(workspace_id)

      _invalid ->
        {:error, :invalid_storage_reservation}
    end
  end

  def acquire_snapshot_export_lease(_attrs), do: {:error, :invalid_storage_reservation}

  @doc false
  @spec renew_live_storage_reservation(pos_integer(), Ecto.UUID.t(), pos_integer()) ::
          {:ok, StorageReservation.t()} | {:error, term()}
  def renew_live_storage_reservation(reservation_id, lease_token, expected_generation)
      when valid_fence(reservation_id, lease_token, expected_generation) do
    case lock_reservation_for_live_renewal(reservation_id) do
      {:ok, %StorageReservation{} = reservation} ->
        with :ok <- verify_lease(reservation, lease_token),
             :ok <- active_reservation(reservation),
             :ok <- verify_generation(reservation, expected_generation) do
          renew_live_owner_reservation(reservation)
        end

      {:ok, nil} ->
        {:error, :storage_reservation_not_found}

      {:error, _reason} = error ->
        error
    end
  end

  def renew_live_storage_reservation(_reservation_id, _lease_token, _expected_generation),
    do: {:error, :invalid_storage_reservation_renewal}

  @doc """
  Atomically grows an active reservation to an absolute byte value.

  Reservations never shrink in place. Callers must extend before publishing
  final objects; a capacity failure leaves the existing reservation untouched.
  """
  @spec extend_to(pos_integer(), Ecto.UUID.t(), pos_integer(), non_neg_integer()) ::
          {:ok, StorageReservation.t()} | {:error, atom()} | {:error, :limit_reached, map()}
  def extend_to(reservation_id, lease_token, expected_generation, target_bytes)
      when valid_fence(reservation_id, lease_token, expected_generation) and is_non_negative_integer(target_bytes) do
    case Repo.get(StorageReservation, reservation_id) do
      %StorageReservation{} = reservation ->
        reservation.workspace_id_snapshot
        |> locked_result(fn workspace ->
          extend_locked(workspace, reservation_id, lease_token, expected_generation, target_bytes)
        end)
        |> emit_after_mutation(reservation.workspace_id_snapshot, :extended)

      nil ->
        {:error, :storage_reservation_not_found}
    end
  end

  def extend_to(_reservation_id, _lease_token, _expected_generation, _target_bytes),
    do: {:error, :invalid_storage_reservation_extension}

  @doc """
  Durably marks that an operation may begin writing to its owned namespace.

  Callers must complete this fence before the first external write and provide
  the complete planned cleanup inventory. The immutable inventory commitment
  makes a later cleanup handoff independently verifiable. Replays are
  idempotent only for the same plan. Once marked, the reservation can no longer
  be released with a no-write proof.
  """
  @spec mark_storage_started(pos_integer(), Ecto.UUID.t(), pos_integer(), map()) ::
          {:ok, StorageReservation.t()} | {:error, term()}
  def mark_storage_started(reservation_id, lease_token, expected_generation, cleanup_plan)
      when valid_fence(reservation_id, lease_token, expected_generation) and is_map(cleanup_plan) do
    case Repo.get(StorageReservation, reservation_id) do
      %StorageReservation{} = reservation ->
        locked_result(reservation.workspace_id_snapshot, fn workspace ->
          mark_storage_started_locked(
            workspace,
            reservation_id,
            lease_token,
            expected_generation,
            cleanup_plan
          )
        end)

      nil ->
        {:error, :storage_reservation_not_found}
    end
  end

  def mark_storage_started(_reservation_id, _lease_token, _expected_generation, _cleanup_plan),
    do: {:error, :invalid_storage_reservation_start}

  @doc """
  Atomically replaces an active reservation with durable billable ownership.

  `owner_fun` performs database ownership writes only and must return
  `{:ok, result}` or `{:error, reason}`. Large object transfers and manifest
  publication happen before this short transaction, after `extend_to/4` has
  ensured the final byte count fits. If `actual_bytes` exceeds the reservation,
  finalization fails closed without invoking the callback.
  """
  @spec commit(pos_integer(), Ecto.UUID.t(), pos_integer(), pos_integer(), (StorageReservation.t() -> term())) ::
          {:ok, %{reservation: StorageReservation.t(), result: term()}}
          | {:error, :reservation_underestimated, map()}
          | {:error, term()}
  def commit(reservation_id, lease_token, expected_generation, actual_bytes, owner_fun)
      when valid_fence(reservation_id, lease_token, expected_generation) and is_non_negative_integer(actual_bytes) and
             is_function(owner_fun, 1) do
    case Repo.get(StorageReservation, reservation_id) do
      %StorageReservation{} = reservation ->
        reservation.workspace_id_snapshot
        |> locked_result(fn workspace ->
          commit_locked(workspace, reservation_id, lease_token, expected_generation, actual_bytes, owner_fun)
        end)
        |> emit_after_mutation(reservation.workspace_id_snapshot, :committed)

      nil ->
        {:error, :storage_reservation_not_found}
    end
  end

  def commit(_reservation_id, _lease_token, _expected_generation, _actual_bytes, _owner_fun),
    do: {:error, :invalid_storage_reservation_commit}

  @doc """
  Releases an active reservation after durable cleanup ownership is established.

  `cleanup_status` must be `"not_required"` when no temporary object ever
  existed, or `"owned"` with a durable `cleanup_reference`. Expiry by itself is
  never authority to release capacity; expired snapshot builds are reclaimed
  only after their owning job is terminal or absent and that fact is rechecked
  under the workspace and snapshot locks.
  """
  @spec release(pos_integer(), Ecto.UUID.t(), pos_integer(), map()) ::
          {:ok, StorageReservation.t()} | {:error, term()}
  def release(reservation_id, lease_token, expected_generation, attrs)
      when valid_fence(reservation_id, lease_token, expected_generation) and is_map(attrs) do
    case Repo.get(StorageReservation, reservation_id) do
      %StorageReservation{} = reservation ->
        reservation.workspace_id_snapshot
        |> settlement_locked_result(fn _workspace ->
          release_locked(reservation_id, lease_token, expected_generation, attrs)
        end)
        |> emit_after_mutation(reservation.workspace_id_snapshot, :released)

      nil ->
        {:error, :storage_reservation_not_found}
    end
  end

  def release(_reservation_id, _lease_token, _expected_generation, _attrs),
    do: {:error, :invalid_storage_reservation_release}

  @doc """
  Releases expired zero-byte snapshot export read leases in one bounded batch.

  Candidate selection is advisory. Every release rechecks the immutable lease
  token and generation plus the exact zero-byte, never-started export shape
  under the workspace and reservation locks. Positive export reservations are
  deliberately outside this recovery path because they require durable cleanup
  ownership before release.
  """
  @spec recover_expired_snapshot_export_leases(DateTime.t(), keyword()) :: %{
          candidate_count: non_neg_integer(),
          released_count: non_neg_integer(),
          changed_count: non_neg_integer(),
          failure_count: non_neg_integer(),
          last_candidate_id: pos_integer() | nil
        }
  def recover_expired_snapshot_export_leases(now, opts \\ [])

  def recover_expired_snapshot_export_leases(%DateTime{} = now, opts) when is_list(opts) do
    if Keyword.keyword?(opts),
      do: recover_expired_snapshot_export_lease_candidates(now, opts),
      else: invalid_expired_snapshot_export_lease_recovery()
  end

  def recover_expired_snapshot_export_leases(_now, _opts), do: invalid_expired_snapshot_export_lease_recovery()

  @doc false
  @spec settle_expired_snapshot_export_leases_locked(ProjectSnapshot.t(), pos_integer()) ::
          :ok | {:error, term()}
  def settle_expired_snapshot_export_leases_locked(
        %ProjectSnapshot{id: snapshot_id, project_id: project_id},
        workspace_id
      )
      when is_positive_integer(snapshot_id) and is_positive_integer(project_id) and is_positive_integer(workspace_id) do
    if workspace_lock_held?(workspace_id) do
      with true <- snapshot_in_workspace?(snapshot_id, project_id, workspace_id),
           reservations = lock_active_snapshot_export_leases(snapshot_id, workspace_id),
           :ok <- settle_expired_snapshot_export_leases(reservations, database_clock_now()) do
        :ok
      else
        false -> {:error, :storage_reservation_target_mismatch}
        {:error, _reason} = error -> error
      end
    else
      {:error, :storage_accounting_lock_required}
    end
  end

  def settle_expired_snapshot_export_leases_locked(_snapshot, _workspace_id),
    do: {:error, :invalid_snapshot_export_lease_settlement}

  @doc """
  Purges one bounded batch of terminal, zero-byte export lease history.

  Only released leases with an exact no-write proof and no publication claim
  are eligible. Active leases remain untouched, so an in-flight or issued
  download grant cannot be invalidated by retention.
  """
  @spec purge_released_snapshot_export_leases(DateTime.t(), keyword()) :: %{
          candidate_count: non_neg_integer(),
          purged_count: non_neg_integer(),
          changed_count: non_neg_integer(),
          failure_count: non_neg_integer(),
          last_candidate_id: pos_integer() | nil
        }
  def purge_released_snapshot_export_leases(cutoff, opts \\ [])

  def purge_released_snapshot_export_leases(%DateTime{} = cutoff, opts) when is_list(opts) do
    if Keyword.keyword?(opts),
      do: purge_released_snapshot_export_lease_candidates(cutoff, opts),
      else: invalid_released_snapshot_export_lease_purge()
  end

  def purge_released_snapshot_export_leases(_cutoff, _opts), do: invalid_released_snapshot_export_lease_purge()

  @doc """
  Emits provider-footprint telemetry without mutating or recalculating quota.

  ENG-81 supplies verified provider inventory. Keeping this as an explicit
  input makes it impossible for orphan or implementation-dependent bytes to be
  silently adopted as product-accounted usage.
  """
  @spec emit_provider_footprint(pos_integer(), map()) :: :ok | {:error, :invalid_provider_footprint}
  def emit_provider_footprint(workspace_id, measurements)
      when is_integer(workspace_id) and workspace_id > 0 and is_map(measurements) do
    with {:ok, normalized} <- normalize_provider_measurements(measurements) do
      usage = workspace_usage(workspace_id)

      owned_accounted_bytes = usage.accounted_bytes - usage.active_reservations.bytes

      :telemetry.execute(
        [:storyarn, :storage, :provider_footprint],
        normalized
        |> Map.put(:accounted_bytes, owned_accounted_bytes)
        |> Map.put(:reservation_bytes, usage.active_reservations.bytes)
        |> Map.put(:drift_bytes, normalized.physical_bytes - owned_accounted_bytes),
        %{workspace_id: workspace_id, accounting_version: @accounting_version}
      )

      :ok
    end
  end

  def emit_provider_footprint(_workspace_id, _measurements), do: {:error, :invalid_provider_footprint}

  @doc """
  Returns the exact object namespaces owned by a storage reservation.

  Snapshot builds own paired staging/ready archive prefixes. Restore and export
  operations own one reservation-specific temporary root.
  Every prefix is reconstructed from immutable reservation identity before it
  can authorize cleanup.
  """
  @spec operation_object_prefixes(StorageReservation.t()) ::
          {:ok, %{staging: String.t(), ready: String.t()}}
          | {:ok, %{temporary: String.t()}}
          | {:error, :storage_reservation_has_no_object_namespace}
  def operation_object_prefixes(
        %StorageReservation{
          kind: "snapshot_build",
          project_id_snapshot: project_id,
          cleanup_object_prefix: ready_prefix,
          storage_namespace: storage_namespace,
          lease_token: lease_token
        } = reservation
      ) do
    expected_namespace = reservation_namespace(project_id, reservation.kind, lease_token)

    case {storage_namespace == expected_namespace, snapshot_ready_identity(project_id, ready_prefix)} do
      {true, {:ok, token}} ->
        {:ok,
         %{
           staging: SnapshotArchiveStorage.staging_prefix(project_id, token),
           ready: ready_prefix
         }}

      _invalid ->
        {:error, :storage_reservation_has_no_object_namespace}
    end
  end

  def operation_object_prefixes(%StorageReservation{
        kind: kind,
        project_id_snapshot: project_id,
        storage_namespace: storage_namespace,
        cleanup_object_prefix: cleanup_object_prefix,
        lease_token: lease_token
      })
      when kind in ["restore_staging", "snapshot_export"] do
    case reservation_namespace(project_id, kind, lease_token) do
      ^storage_namespace when cleanup_object_prefix == storage_namespace -> {:ok, %{temporary: storage_namespace}}
      _invalid -> {:error, :storage_reservation_has_no_object_namespace}
    end
  end

  def operation_object_prefixes(%StorageReservation{}), do: {:error, :storage_reservation_has_no_object_namespace}

  defp ensure_operation_namespace_available(reservation) do
    case operation_object_prefixes(reservation) do
      {:ok, prefixes} ->
        prefixes
        |> Map.values()
        |> ensure_prefixes_not_handed_off()

      {:error, _reason} ->
        {:error, :storage_reservation_has_no_object_namespace}
    end
  end

  defp ensure_prefixes_not_handed_off(prefixes) do
    Enum.reduce_while(prefixes, :ok, fn prefix, :ok ->
      prefix
      |> ensure_prefix_not_handed_off()
      |> continue_or_halt_prefix_check()
    end)
  end

  defp continue_or_halt_prefix_check(:ok), do: {:cont, :ok}
  defp continue_or_halt_prefix_check({:error, _reason} = error), do: {:halt, error}

  defp ensure_prefix_not_handed_off(prefix) do
    if StorageCleanupOwnershipReceipt.handed_off_for_prefix?(prefix),
      do: {:error, :storage_reservation_namespace_cleanup_handed_off},
      else: :ok
  end

  defp reserve_locked(workspace, attrs) do
    case reservation_by_key(attrs.workspace_id, attrs.idempotency_key) do
      %StorageReservation{status: "active"} = reservation_hint ->
        with {:ok, target} <- lock_active_reservation_target(workspace, reservation_hint),
             attrs = reuse_operation_identity(attrs, reservation_hint),
             {:ok, attrs} <- put_target_facts(attrs, target),
             %StorageReservation{} = reservation <- lock_reservation(reservation_hint.id) do
          reserve_for_key(workspace, attrs, reservation)
        else
          nil -> {:error, :storage_reservation_not_found}
          {:error, _reason} = error -> error
        end

      %StorageReservation{} = reservation_hint ->
        case lock_reservation(reservation_hint.id) do
          %StorageReservation{} = reservation -> reserve_for_key(workspace, attrs, reservation)
          nil -> {:error, :storage_reservation_not_found}
        end

      nil ->
        with :ok <- validate_reservation_scope(workspace, attrs),
             {:ok, target} <- validate_reservation_target(attrs),
             {:ok, attrs} <- put_target_facts(attrs, target),
             :ok <- ensure_exclusive_snapshot_target_available(attrs) do
          reserve_for_key(workspace, attrs, nil)
        end
    end
  end

  defp acquire_snapshot_export_lease_locked(workspace, attrs) do
    with :ok <- validate_reservation_scope(workspace, attrs),
         {:ok, target} <- validate_reservation_target(attrs),
         {:ok, attrs} <- put_target_facts(attrs, target) do
      attrs = stamp_snapshot_export_lease(attrs)

      case lock_latest_snapshot_export_lease(attrs) do
        %StorageReservation{} = reservation ->
          reservation
          |> renew_snapshot_export_lease()
          |> tag_snapshot_export_lease(:coalesced)

        nil ->
          workspace
          |> reserve_for_key(attrs, nil)
          |> tag_snapshot_export_lease(:created)
      end
    end
  end

  defp lock_latest_snapshot_export_lease(attrs) do
    Repo.one(
      from(reservation in StorageReservation,
        where:
          reservation.workspace_id_snapshot == ^attrs.workspace_id and
            reservation.project_id_snapshot == ^attrs.project_id and
            reservation.project_snapshot_id_snapshot == ^attrs.project_snapshot_id and
            reservation.kind == "snapshot_export" and reservation.status == "active" and
            reservation.reserved_bytes == 0 and is_nil(reservation.storage_started_at),
        order_by: [desc: reservation.expires_at, desc: reservation.id],
        limit: 1,
        lock: "FOR UPDATE"
      )
    )
  end

  defp tag_snapshot_export_lease({:ok, %StorageReservation{} = reservation}, outcome), do: {:ok, {reservation, outcome}}

  defp tag_snapshot_export_lease({:error, _reason} = error, _outcome), do: error

  defp reserve_for_key(_workspace, attrs, %StorageReservation{status: "active"} = reservation) do
    with true <- same_reservation?(reservation, attrs),
         :ok <- verify_unexpired(reservation) do
      {:ok, reservation}
    else
      false -> {:error, :reservation_conflict}
      {:error, _reason} = error -> error
    end
  end

  defp reserve_for_key(_workspace, _attrs, %StorageReservation{}), do: {:error, :storage_reservation_terminal}

  defp reserve_for_key(workspace, attrs, nil) do
    with :ok <- check_snapshot_slot(workspace, attrs),
         :ok <- check_capacity(workspace, attrs.reserved_bytes) do
      %StorageReservation{}
      |> StorageReservation.create_changeset(attrs)
      |> Repo.insert()
    end
  end

  defp extend_locked(workspace, reservation_id, lease_token, expected_generation, target_bytes) do
    case Repo.get(StorageReservation, reservation_id) do
      %StorageReservation{status: "active"} = reservation_hint ->
        with {:ok, _target} <- lock_active_reservation_target(workspace, reservation_hint),
             %StorageReservation{} = reservation <- lock_reservation(reservation_id),
             :ok <- verify_lease(reservation, lease_token),
             :ok <- active_reservation(reservation),
             :ok <- validate_operation_bytes(reservation, target_bytes) do
          extend_for_target(workspace, reservation, expected_generation, target_bytes)
        else
          nil -> {:error, :storage_reservation_not_found}
          {:error, _reason} = error -> error
        end

      %StorageReservation{} ->
        with %StorageReservation{} = reservation <- lock_reservation(reservation_id),
             :ok <- verify_lease(reservation, lease_token),
             :ok <- active_reservation(reservation) do
          extend_for_target(workspace, reservation, expected_generation, target_bytes)
        else
          nil -> {:error, :storage_reservation_not_found}
          {:error, _reason} = error -> error
        end

      nil ->
        {:error, :storage_reservation_not_found}
    end
  end

  defp mark_storage_started_locked(workspace, reservation_id, lease_token, expected_generation, cleanup_plan) do
    case Repo.get(StorageReservation, reservation_id) do
      %StorageReservation{status: "active"} = reservation_hint ->
        with {:ok, _target} <- lock_active_reservation_target(workspace, reservation_hint),
             %StorageReservation{} = reservation <- lock_reservation(reservation_id),
             :ok <- verify_lease(reservation, lease_token),
             :ok <- active_reservation(reservation),
             :ok <- verify_generation(reservation, expected_generation),
             :ok <- verify_unexpired(reservation),
             :ok <- verify_storage_start_allowed(reservation),
             :ok <- ensure_operation_namespace_available(reservation),
             {:ok, storage_keys} <- validate_planned_cleanup_scope(reservation, cleanup_plan) do
          persist_storage_started(reservation, storage_keys)
        else
          nil -> {:error, :storage_reservation_not_found}
          {:error, _reason} = error -> error
        end

      %StorageReservation{} = reservation ->
        with %StorageReservation{} = locked <- lock_reservation(reservation.id),
             :ok <- verify_lease(locked, lease_token),
             :ok <- active_reservation(locked) do
          {:ok, locked}
        else
          nil -> {:error, :storage_reservation_not_found}
          {:error, _reason} = error -> error
        end

      nil ->
        {:error, :storage_reservation_not_found}
    end
  end

  defp persist_storage_started(reservation, storage_keys) do
    inventory_digest = cleanup_inventory_digest(storage_keys)
    inventory_count = length(storage_keys)

    persist_storage_started(reservation, inventory_digest, inventory_count)
  end

  defp persist_storage_started(
         %StorageReservation{
           storage_started_at: %DateTime{},
           cleanup_inventory_digest: inventory_digest,
           cleanup_inventory_count: inventory_count
         } = reservation,
         inventory_digest,
         inventory_count
       ), do: {:ok, reservation}

  defp persist_storage_started(%StorageReservation{storage_started_at: %DateTime{}}, _digest, _count),
    do: {:error, :storage_reservation_cleanup_plan_conflict}

  defp persist_storage_started(reservation, inventory_digest, inventory_count) do
    reservation
    |> StorageReservation.storage_started_changeset(
      TimeHelpers.now(),
      inventory_digest,
      inventory_count
    )
    |> Repo.update()
  end

  defp extend_for_target(workspace, reservation, expected_generation, target_bytes) do
    cond do
      target_bytes == reservation.reserved_bytes and reservation.generation == expected_generation ->
        renew_active_reservation(reservation)

      target_bytes == reservation.reserved_bytes and reservation.generation == expected_generation + 1 ->
        with :ok <- verify_unexpired(reservation), do: {:ok, reservation}

      reservation.generation != expected_generation ->
        {:error, :storage_reservation_generation_mismatch}

      target_bytes < reservation.reserved_bytes ->
        {:error, :storage_reservation_cannot_shrink}

      true ->
        extend_active_reservation(workspace, reservation, target_bytes)
    end
  end

  defp extend_active_reservation(workspace, reservation, target_bytes) do
    delta = target_bytes - reservation.reserved_bytes

    with :ok <- verify_unexpired(reservation),
         :ok <- check_capacity(workspace, delta) do
      measured_at = TimeHelpers.now()

      reservation
      |> StorageReservation.extend_changeset(target_bytes, %{
        generation: reservation.generation + 1,
        expires_at:
          DateTime.add(
            measured_at,
            reservation_ttl_seconds(reservation.kind, target_bytes),
            :second
          ),
        accounting_measured_at: measured_at
      })
      |> Repo.update()
    end
  end

  defp renew_active_reservation(reservation) do
    with :ok <- verify_unexpired(reservation) do
      measured_at = TimeHelpers.now()

      reservation
      |> StorageReservation.renew_changeset(%{
        generation: reservation.generation + 1,
        expires_at: renewed_expiry(reservation, measured_at),
        accounting_measured_at: measured_at
      })
      |> Repo.update()
    end
  end

  defp renew_snapshot_export_lease(reservation) do
    measured_at = database_clock_now()

    reservation
    |> StorageReservation.renew_changeset(%{
      generation: reservation.generation + 1,
      expires_at: renewed_expiry(reservation, measured_at),
      accounting_measured_at: measured_at
    })
    |> Repo.update()
  end

  defp stamp_snapshot_export_lease(attrs) do
    measured_at = database_clock_now()

    %{
      attrs
      | expires_at:
          DateTime.add(
            measured_at,
            ProjectSnapshotLeasePolicy.download_export_lease_ttl_seconds(),
            :second
          ),
        accounting_measured_at: measured_at
    }
  end

  defp renew_live_owner_reservation(reservation) do
    measured_at = database_clock_now()

    reservation
    |> StorageReservation.live_owner_renew_changeset(%{
      generation: reservation.generation + 1,
      expires_at:
        DateTime.add(
          measured_at,
          ProjectSnapshotLeasePolicy.build_lease_ttl_seconds(),
          :second
        ),
      accounting_measured_at: measured_at
    })
    |> Repo.update()
  end

  defp commit_locked(workspace, reservation_id, lease_token, expected_generation, actual_bytes, owner_fun) do
    case Repo.get(StorageReservation, reservation_id) do
      %StorageReservation{status: "active"} = reservation_hint ->
        with {:ok, target} <- lock_active_reservation_target(workspace, reservation_hint),
             %StorageReservation{} = reservation <- lock_reservation(reservation_id),
             :ok <- verify_lease(reservation, lease_token),
             :ok <- validate_operation_bytes(reservation, actual_bytes) do
          commit_for_status(workspace, reservation, target, expected_generation, actual_bytes, owner_fun)
        else
          nil -> {:error, :storage_reservation_not_found}
          {:error, _reason} = error -> error
        end

      %StorageReservation{} ->
        with %StorageReservation{} = reservation <- lock_reservation(reservation_id),
             :ok <- verify_lease(reservation, lease_token) do
          commit_for_status(workspace, reservation, nil, expected_generation, actual_bytes, owner_fun)
        else
          nil -> {:error, :storage_reservation_not_found}
          {:error, _reason} = error -> error
        end

      nil ->
        {:error, :storage_reservation_not_found}
    end
  end

  defp commit_for_status(
         _workspace,
         %{status: "committed"} = reservation,
         _target,
         expected_generation,
         actual_bytes,
         _owner_fun
       ) do
    if reservation.actual_bytes == actual_bytes and reservation.generation == expected_generation + 1,
      do: {:ok, %{reservation: reservation, result: :already_committed}},
      else: {:error, :storage_reservation_commit_conflict}
  end

  defp commit_for_status(_workspace, %{status: "released"}, _target, _expected_generation, _actual_bytes, _owner_fun),
    do: {:error, :storage_reservation_already_released}

  defp commit_for_status(
         workspace,
         %{status: "active"} = reservation,
         target,
         expected_generation,
         actual_bytes,
         owner_fun
       ) do
    with :ok <- verify_generation(reservation, expected_generation),
         :ok <- verify_storage_started(reservation),
         :ok <- verify_unexpired(reservation) do
      commit_active_reservation(workspace, reservation, target, actual_bytes, owner_fun)
    end
  end

  defp commit_active_reservation(workspace, reservation, target, actual_bytes, owner_fun) do
    if actual_bytes > reservation.reserved_bytes do
      reservation_underestimated(workspace, reservation, actual_bytes)
    else
      commit_reserved_capacity(reservation, target, actual_bytes, owner_fun)
    end
  end

  defp reservation_underestimated(workspace, reservation, actual_bytes) do
    usage = workspace_usage(workspace.id)
    limit = workspace |> SubscriptionCrud.plan_for() |> Plan.limit(:storage_bytes_per_workspace)
    details = capacity_details(usage, actual_bytes - reservation.reserved_bytes, limit)

    {:error, :reservation_underestimated,
     Map.merge(details, %{
       reservation_id: reservation.id,
       reserved_bytes: reservation.reserved_bytes,
       actual_bytes: actual_bytes
     })}
  end

  defp commit_reserved_capacity(reservation, target, actual_bytes, owner_fun) do
    with :ok <- validate_snapshot_publication_commitment(reservation),
         {:ok, expectation} <- committed_owner_expectation(reservation, target),
         {:ok, result} <-
           normalize_owner_result(with_storage_commit_context(reservation, fn -> owner_fun.(reservation) end)),
         :ok <- validate_committed_owner(reservation, expectation, result, actual_bytes),
         {:ok, committed} <-
           reservation
           |> StorageReservation.commit_changeset(actual_bytes, %{
             generation: reservation.generation + 1,
             settled_at: TimeHelpers.now(),
             accounting_measured_at: TimeHelpers.now()
           })
           |> Repo.update() do
      {:ok, %{reservation: committed, result: result}}
    end
  end

  defp release_locked(reservation_id, lease_token, expected_generation, attrs) do
    with %StorageReservation{} = reservation <- lock_reservation(reservation_id),
         :ok <- verify_lease(reservation, lease_token),
         {:ok, release_attrs} <- normalize_release_attrs(reservation, attrs) do
      release_for_status(reservation, expected_generation, release_attrs)
    else
      nil -> {:error, :storage_reservation_not_found}
      {:error, _reason} = error -> error
    end
  end

  defp release_for_status(%{status: "released"} = reservation, expected_generation, release_attrs) do
    if same_release?(reservation, release_attrs) and reservation.generation == expected_generation + 1,
      do: {:ok, reservation},
      else: {:error, :storage_reservation_release_conflict}
  end

  defp release_for_status(%{status: "committed"}, _expected_generation, _release_attrs),
    do: {:error, :storage_reservation_already_committed}

  defp release_for_status(%{status: "active"} = reservation, expected_generation, release_attrs) do
    with :ok <- verify_generation(reservation, expected_generation) do
      reservation
      |> StorageReservation.release_changeset(release_attrs.reason, %{
        cleanup_status: release_attrs.cleanup_status,
        cleanup_reference: release_attrs.cleanup_reference,
        generation: reservation.generation + 1,
        settled_at: TimeHelpers.now(),
        accounting_measured_at: TimeHelpers.now()
      })
      |> Repo.update()
    end
  end

  defp locked_result(workspace_id, fun) do
    workspace_id
    |> with_workspace_lock(fn workspace -> run_locked_callback(workspace, fun) end)
    |> unwrap_locked_result()
  end

  defp settlement_locked_result(workspace_id, fun) do
    fn -> run_settlement_locked(workspace_id, fun) end
    |> Repo.transaction(timeout: :infinity)
    |> unwrap_locked_result()
  end

  defp run_settlement_locked(workspace_id, fun) do
    case lock_workspace(workspace_id) do
      %Workspace{} = workspace ->
        with_workspace_lock_marker(workspace_id, fn -> run_locked_callback(workspace, fun) end)

      nil ->
        run_locked_callback(nil, fun)
    end
  end

  defp run_locked_callback(workspace, fun) do
    case fun.(workspace) do
      {:ok, result} -> result
      {:error, reason, details} -> Repo.rollback({:storage_accounting_error, {:error, reason, details}})
      {:error, _reason} = error -> Repo.rollback({:storage_accounting_error, error})
    end
  end

  defp unwrap_locked_result({:ok, result}), do: {:ok, result}
  defp unwrap_locked_result({:error, {:storage_accounting_error, error}}), do: error
  defp unwrap_locked_result({:error, reason}), do: {:error, reason}

  defp emit_after_mutation({:ok, result} = ok, workspace_id, action) do
    maybe_broadcast_snapshot_export_update(result, action)
    usage = workspace_usage(workspace_id)

    :telemetry.execute(
      [:storyarn, :storage, :accounting, :updated],
      %{
        accounted_bytes: usage.accounted_bytes - usage.active_reservations.bytes,
        reservation_bytes: usage.active_reservations.bytes,
        total_bytes: usage.accounted_bytes
      },
      %{workspace_id: workspace_id, action: action, accounting_version: @accounting_version}
    )

    ok
  end

  defp emit_after_mutation(error, _workspace_id, _action), do: error

  defp emit_snapshot_export_lease_acquired({:ok, {reservation, outcome}}, workspace_id)
       when outcome in [:created, :coalesced] do
    action = if outcome == :created, do: :reserved, else: :renewed
    {:ok, reservation} = emit_after_mutation({:ok, reservation}, workspace_id, action)

    :telemetry.execute(
      [:storyarn, :snapshot, :download, :lease],
      %{count: 1},
      %{
        outcome: outcome,
        project_id: reservation.project_id_snapshot,
        snapshot_id: reservation.project_snapshot_id_snapshot
      }
    )

    {:ok, reservation}
  end

  defp emit_snapshot_export_lease_acquired({:error, _reason} = error, _workspace_id), do: error

  # Storage mutations have committed before this hook runs. Snapshot settings
  # subscribe to this topic so destructive controls follow the durable lease
  # fence instead of remaining stale for the reaper interval.
  defp maybe_broadcast_snapshot_export_update(%StorageReservation{} = reservation, action)
       when action in [:reserved, :renewed, :released, :committed] do
    broadcast_snapshot_export_update(reservation)
  end

  defp maybe_broadcast_snapshot_export_update(%{reservation: %StorageReservation{} = reservation}, action)
       when action in [:reserved, :renewed, :released, :committed] do
    broadcast_snapshot_export_update(reservation)
  end

  defp maybe_broadcast_snapshot_export_update(_result, _action), do: :ok

  defp broadcast_snapshot_export_update(%StorageReservation{
         kind: "snapshot_export",
         project_id_snapshot: project_id,
         project_snapshot_id_snapshot: snapshot_id
       })
       when is_integer(project_id) and project_id > 0 and is_integer(snapshot_id) and snapshot_id > 0 do
    Phoenix.PubSub.broadcast(
      Storyarn.PubSub,
      "project_snapshots:#{project_id}",
      {:project_snapshot_updated, snapshot_id}
    )
  end

  defp broadcast_snapshot_export_update(%StorageReservation{}), do: :ok

  defp check_capacity_limit(usage, requested_bytes, limit) when is_integer(limit) and limit >= 0 do
    details = capacity_details(usage, requested_bytes, limit)

    if requested_bytes <= details.available,
      do: :ok,
      else: {:error, :limit_reached, details}
  end

  defp check_capacity_limit(_usage, _requested_bytes, limit) when limit in [:unlimited, :infinity], do: :ok

  defp check_capacity_limit(usage, requested_bytes, _unknown_limit) do
    {:error, :limit_reached, capacity_details(usage, requested_bytes, nil)}
  end

  defp capacity_details(usage, requested_bytes, limit) do
    available = if is_integer(limit), do: max(limit - usage.accounted_bytes, 0), else: 0

    %{
      resource: :storage_bytes_per_workspace,
      used: usage.accounted_bytes,
      reserved: usage.active_reservations.bytes,
      required: requested_bytes,
      available: available,
      limit: limit
    }
  end

  defp check_snapshot_slot(_workspace, %{kind: kind}) when kind != "snapshot_build", do: :ok

  defp check_snapshot_slot(workspace, %{project_id: project_id}) when is_integer(project_id) do
    plan = SubscriptionCrud.plan_for(workspace)
    limit = Plan.limit(plan, :project_snapshots_per_project)

    used = snapshot_slots_used(project_id)

    # The pending snapshot row is created before its build reservation and is
    # already included in `used`. A second pending row pushes it over the limit.
    if is_integer(limit) and limit >= 0 and used <= limit,
      do: :ok,
      else: {:error, :snapshot_limit_reached, %{resource: :project_snapshots_per_project, used: used, limit: limit}}
  end

  defp check_snapshot_slot(_workspace, _attrs), do: {:error, :invalid_snapshot_reservation_project}

  defp snapshot_slots_used(project_id) do
    stored_slots =
      Repo.aggregate(
        from(snapshot in ProjectSnapshot,
          where:
            snapshot.project_id == ^project_id and
              snapshot.lifecycle_state in ^@snapshot_slot_lifecycle_states
        ),
        :count
      )

    unrepresented_build_reservations =
      Repo.aggregate(
        from(reservation in StorageReservation,
          left_join: snapshot in ProjectSnapshot,
          on: snapshot.id == reservation.project_snapshot_id_snapshot,
          where:
            reservation.project_id_snapshot == ^project_id and
              reservation.kind == "snapshot_build" and reservation.status == "active" and
              (is_nil(snapshot.id) or
                 snapshot.lifecycle_state not in ^@snapshot_slot_lifecycle_states)
        ),
        :count
      )

    stored_slots + unrepresented_build_reservations
  end

  defp build_usage(assets, snapshots, reservations) do
    current_assets = assets.current_assets
    asset_trash = assets.asset_trash
    full_snapshots = Map.get(snapshots, "full", empty_bucket())
    accounted_bytes = current_assets.bytes + asset_trash.bytes + full_snapshots.bytes + reservations.bytes

    %{
      accounting_version: @accounting_version,
      measured_at: TimeHelpers.now(),
      current_assets: current_assets,
      asset_trash: asset_trash,
      full_snapshots: full_snapshots,
      active_reservations: reservations,
      accounted_bytes: accounted_bytes
    }
  end

  defp workspace_asset_usage(workspace_id) do
    Asset
    |> join(:inner, [asset], project in Project, on: asset.project_id == project.id)
    |> where([_asset, project], project.workspace_id == ^workspace_id)
    |> aggregate_asset_usage()
  end

  defp project_asset_usage(project_id) do
    Asset
    |> where([asset], asset.project_id == ^project_id)
    |> aggregate_asset_usage()
  end

  defp aggregate_asset_usage(query) do
    {current_bytes, current_count, trash_bytes, trash_count} =
      Repo.one!(
        select(query, [asset, ...], {
          type(coalesce(filter(sum(asset.size), is_nil(asset.deleted_at)), 0), :integer),
          filter(count(asset.id), is_nil(asset.deleted_at)),
          type(coalesce(filter(sum(asset.size), not is_nil(asset.deleted_at)), 0), :integer),
          filter(count(asset.id), not is_nil(asset.deleted_at))
        })
      )

    %{
      current_assets: %{bytes: current_bytes, count: current_count},
      asset_trash: %{bytes: trash_bytes, count: trash_count}
    }
  end

  defp workspace_snapshot_usage(workspace_id) do
    ProjectSnapshot
    |> join(:inner, [snapshot], project in Project, on: snapshot.project_id == project.id)
    |> where([snapshot, project], project.workspace_id == ^workspace_id)
    |> retained_accounted_snapshots()
    |> grouped_snapshot_usage()
  end

  defp project_snapshot_usage(project_id) do
    ProjectSnapshot
    |> where([snapshot], snapshot.project_id == ^project_id)
    |> retained_accounted_snapshots()
    |> grouped_snapshot_usage()
  end

  defp retained_accounted_snapshots(query) do
    where(
      query,
      [snapshot],
      snapshot.lifecycle_state in ["ready", "deleting"] and
        snapshot.mode == "full" and
        snapshot.accounting_version == @accounting_version and
        not is_nil(snapshot.accounted_size_bytes)
    )
  end

  defp grouped_snapshot_usage(query) do
    query
    |> group_by([snapshot], snapshot.mode)
    |> select([snapshot], {
      snapshot.mode,
      type(coalesce(sum(snapshot.accounted_size_bytes), 0), :integer),
      count(snapshot.id)
    })
    |> Repo.all()
    |> Map.new(fn {mode, bytes, count} -> {mode, %{bytes: bytes, count: count}} end)
  end

  defp workspace_reservation_usage(workspace_id) do
    StorageReservation
    |> where([reservation], reservation.workspace_id_snapshot == ^workspace_id)
    |> active_reservation_usage()
  end

  defp project_reservation_usage(project_id) do
    StorageReservation
    |> where([reservation], reservation.project_id_snapshot == ^project_id)
    |> active_reservation_usage()
  end

  defp active_reservation_usage(query) do
    by_kind =
      query
      |> where([reservation], reservation.status == "active")
      |> group_by([reservation], reservation.kind)
      |> select([reservation], {
        reservation.kind,
        type(coalesce(sum(reservation.reserved_bytes), 0), :integer),
        count(reservation.id)
      })
      |> Repo.all()

    Enum.reduce(by_kind, %{bytes: 0, count: 0, by_kind: %{}}, fn {kind, bytes, count}, acc ->
      %{
        bytes: acc.bytes + bytes,
        count: acc.count + count,
        by_kind: Map.put(acc.by_kind, kind, bytes)
      }
    end)
  end

  defp snapshot_in_workspace?(snapshot_id, project_id, workspace_id) do
    Repo.exists?(
      from(snapshot in ProjectSnapshot,
        join: project in Project,
        on: project.id == snapshot.project_id,
        where:
          snapshot.id == ^snapshot_id and snapshot.project_id == ^project_id and
            project.workspace_id == ^workspace_id
      )
    )
  end

  defp lock_active_snapshot_export_leases(snapshot_id, workspace_id) do
    Repo.all(
      from(reservation in StorageReservation,
        where:
          reservation.workspace_id_snapshot == ^workspace_id and
            reservation.project_snapshot_id_snapshot == ^snapshot_id and
            reservation.status == "active" and reservation.kind == "snapshot_export",
        order_by: [asc: reservation.id],
        lock: "FOR UPDATE"
      )
    )
  end

  defp settle_expired_snapshot_export_leases(reservations, now) do
    Enum.reduce_while(reservations, :ok, fn reservation, :ok ->
      case settle_expired_snapshot_export_lease(reservation, now) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp settle_expired_snapshot_export_lease(
         %StorageReservation{reserved_bytes: 0, storage_started_at: nil, expires_at: %DateTime{} = expires_at} =
           reservation,
         now
       ) do
    if DateTime.compare(expires_at, now) in [:lt, :eq] do
      with {:ok, %StorageReservation{status: "released"}} <- release_expired_snapshot_export_lease(reservation) do
        :ok
      end
    else
      :ok
    end
  end

  defp settle_expired_snapshot_export_lease(%StorageReservation{}, _now), do: :ok

  defp expired_snapshot_export_lease_candidates(now, after_id, limit) do
    Repo.all(
      from(reservation in StorageReservation,
        where:
          reservation.status == "active" and reservation.kind == "snapshot_export" and
            reservation.reserved_bytes == 0 and is_nil(reservation.storage_started_at) and
            reservation.expires_at <= ^now and reservation.id > ^after_id,
        order_by: [asc: reservation.id],
        limit: ^limit,
        select: %{
          id: reservation.id,
          workspace_id_snapshot: reservation.workspace_id_snapshot,
          lease_token: reservation.lease_token,
          generation: reservation.generation,
          expires_at: reservation.expires_at
        }
      )
    )
  end

  defp recovery_batch_limit(opts) do
    case Keyword.get(opts, :limit, @expired_export_lease_recovery_batch_size) do
      limit when is_integer(limit) and limit > 0 -> min(limit, @expired_export_lease_recovery_batch_size)
      _invalid -> @expired_export_lease_recovery_batch_size
    end
  end

  defp recovery_after_id(opts) do
    case Keyword.get(opts, :after_id, 0) do
      after_id when is_integer(after_id) and after_id >= 0 -> {:ok, after_id}
      _invalid -> {:error, :invalid_after_id}
    end
  end

  defp invalid_expired_snapshot_export_lease_recovery do
    %{candidate_count: 0, released_count: 0, changed_count: 0, failure_count: 1, last_candidate_id: nil}
  end

  defp recover_expired_snapshot_export_lease_candidates(now, opts) do
    case recovery_after_id(opts) do
      {:ok, after_id} ->
        candidates = expired_snapshot_export_lease_candidates(now, after_id, recovery_batch_limit(opts))

        Enum.reduce(
          candidates,
          %{
            candidate_count: length(candidates),
            released_count: 0,
            changed_count: 0,
            failure_count: 0,
            last_candidate_id: candidates |> List.last() |> then(&(&1 && &1.id))
          },
          &count_expired_snapshot_export_lease_recovery/2
        )

      {:error, :invalid_after_id} ->
        invalid_expired_snapshot_export_lease_recovery()
    end
  end

  defp count_expired_snapshot_export_lease_recovery(candidate, counts) do
    case recover_expired_snapshot_export_lease(candidate) do
      {:ok, %StorageReservation{status: "released"} = reservation} ->
        broadcast_snapshot_export_update(reservation)
        Map.update!(counts, :released_count, &(&1 + 1))

      {:error, :expired_snapshot_export_lease_changed} ->
        Map.update!(counts, :changed_count, &(&1 + 1))

      {:error, _reason} ->
        Map.update!(counts, :failure_count, &(&1 + 1))
    end
  end

  defp recover_expired_snapshot_export_lease(candidate) do
    settlement_locked_result(candidate.workspace_id_snapshot, fn _workspace ->
      with %StorageReservation{} = reservation <- lock_reservation(candidate.id),
           :ok <- verify_lease(reservation, candidate.lease_token),
           :ok <- verify_generation(reservation, candidate.generation),
           :ok <- verify_expired_snapshot_export_lease(reservation, candidate, database_clock_now()),
           {:ok, %StorageReservation{} = released} <- release_expired_snapshot_export_lease(reservation) do
        {:ok, released}
      else
        nil ->
          {:error, :expired_snapshot_export_lease_changed}

        {:error, reason}
        when reason in [
               :storage_reservation_lease_mismatch,
               :storage_reservation_generation_mismatch,
               :expired_snapshot_export_lease_changed
             ] ->
          {:error, :expired_snapshot_export_lease_changed}

        {:error, _reason} = error ->
          error
      end
    end)
  end

  defp verify_expired_snapshot_export_lease(reservation, candidate, now) do
    if reservation.status == "active" and reservation.kind == "snapshot_export" and
         reservation.reserved_bytes == 0 and is_nil(reservation.storage_started_at) and
         reservation.expires_at == candidate.expires_at and
         not DateTime.after?(reservation.expires_at, now),
       do: :ok,
       else: {:error, :expired_snapshot_export_lease_changed}
  end

  defp release_expired_snapshot_export_lease(reservation) do
    with {:ok, release_attrs} <-
           normalize_release_attrs(reservation, %{
             reason: "expired_snapshot_export_lease",
             cleanup_status: "not_required",
             cleanup_proof: %{
               type: "storage_not_started",
               storage_namespace: reservation.storage_namespace
             }
           }) do
      release_for_status(reservation, reservation.generation, release_attrs)
    end
  end

  defp purge_released_snapshot_export_lease_candidates(cutoff, opts) do
    case recovery_after_id(opts) do
      {:ok, after_id} ->
        candidates =
          released_snapshot_export_lease_candidates(
            cutoff,
            after_id,
            released_export_lease_purge_batch_limit(opts)
          )

        candidate_ids = Enum.map(candidates, & &1.id)
        purged_count = purge_released_snapshot_export_lease_ids(candidate_ids, cutoff)

        %{
          candidate_count: length(candidates),
          purged_count: purged_count,
          changed_count: length(candidates) - purged_count,
          failure_count: 0,
          last_candidate_id: candidates |> List.last() |> then(&(&1 && &1.id))
        }

      {:error, :invalid_after_id} ->
        invalid_released_snapshot_export_lease_purge()
    end
  rescue
    _exception -> invalid_released_snapshot_export_lease_purge()
  end

  defp released_snapshot_export_lease_candidates(cutoff, after_id, limit) do
    StorageReservation
    |> released_snapshot_export_lease_query()
    |> where([reservation: reservation], reservation.id > ^after_id and reservation.settled_at <= ^cutoff)
    |> order_by([reservation: reservation], asc: reservation.id)
    |> limit(^limit)
    |> select([reservation: reservation], %{id: reservation.id})
    |> Repo.all()
  end

  defp purge_released_snapshot_export_lease_ids([], _cutoff), do: 0

  defp purge_released_snapshot_export_lease_ids(ids, cutoff) do
    claim_exists =
      from(claim in SnapshotObjectPublicationClaim,
        where: claim.storage_reservation_id_snapshot == parent_as(:reservation).id,
        select: 1
      )

    {purged_count, _rows} =
      StorageReservation
      |> released_snapshot_export_lease_query()
      |> where(
        [reservation: reservation],
        reservation.id in ^ids and reservation.settled_at <= ^cutoff and
          not exists(subquery(claim_exists))
      )
      |> Repo.delete_all()

    purged_count
  end

  defp released_snapshot_export_lease_query(query) do
    query
    |> released_zero_byte_export_lease_query()
    |> never_started_export_lease_query()
    |> preserve_latest_export_lease_evidence_query()
  end

  defp released_zero_byte_export_lease_query(query) do
    from(reservation in query,
      as: :reservation,
      where:
        reservation.status == "released" and reservation.kind == "snapshot_export" and
          reservation.reserved_bytes == 0 and is_nil(reservation.actual_bytes)
    )
  end

  defp never_started_export_lease_query(query) do
    from([reservation: reservation] in query,
      where:
        is_nil(reservation.storage_started_at) and reservation.cleanup_status == "not_required" and
          reservation.cleanup_reference == fragment("'storage_not_started:' || ?", reservation.storage_namespace) and
          not is_nil(reservation.settled_at)
    )
  end

  defp preserve_latest_export_lease_evidence_query(query) do
    latest_evidence_id =
      from(reservation in StorageReservation,
        where: reservation.kind == "snapshot_export" and reservation.reserved_bytes == 0,
        select: max(reservation.id)
      )

    from([reservation: reservation] in query,
      where: reservation.id < subquery(latest_evidence_id)
    )
  end

  defp released_export_lease_purge_batch_limit(opts) do
    case Keyword.get(opts, :limit, @released_export_lease_purge_batch_size) do
      limit when is_integer(limit) and limit > 0 -> min(limit, @released_export_lease_purge_batch_size)
      _invalid -> @released_export_lease_purge_batch_size
    end
  end

  defp invalid_released_snapshot_export_lease_purge do
    %{
      candidate_count: 0,
      purged_count: 0,
      changed_count: 0,
      failure_count: 1,
      last_candidate_id: nil
    }
  end

  defp lock_reservation(id) do
    Repo.one(from(reservation in StorageReservation, where: reservation.id == ^id, lock: "FOR UPDATE"))
  end

  defp lock_reservation_for_live_renewal(reservation_id) do
    case Repo.get(StorageReservation, reservation_id) do
      %StorageReservation{workspace_id_snapshot: workspace_id} ->
        if workspace_lock_held?(workspace_id),
          do: {:ok, lock_reservation(reservation_id)},
          else: {:error, :storage_accounting_lock_required}

      nil ->
        {:error, :storage_reservation_not_found}
    end
  end

  defp reservation_by_key(workspace_id, idempotency_key) do
    Repo.one(
      from(reservation in StorageReservation,
        where:
          reservation.workspace_id_snapshot == ^workspace_id and
            reservation.idempotency_key == ^idempotency_key
      )
    )
  end

  defp lock_active_reservation_target(%Workspace{} = workspace, %StorageReservation{} = reservation) do
    attrs = %{
      project_id: reservation.project_id_snapshot,
      project_snapshot_id: reservation.project_snapshot_id_snapshot,
      kind: reservation.kind,
      reserved_bytes: reservation.reserved_bytes,
      reservation_id: reservation.id
    }

    with :ok <- validate_reservation_scope(workspace, attrs),
         {:ok, target} <- validate_reservation_target(attrs),
         :ok <- validate_active_target_facts(reservation, target) do
      {:ok, target}
    end
  end

  defp lock_active_reservation_target(_workspace, _reservation), do: {:error, :invalid_storage_reservation_project}

  defp validate_reservation_scope(%Workspace{id: workspace_id}, %{project_id: project_id, kind: "restore_staging"})
       when is_integer(project_id) and project_id > 0 do
    project =
      Repo.one(
        from(candidate in Project,
          where: candidate.id == ^project_id and candidate.workspace_id == ^workspace_id,
          lock: "FOR UPDATE"
        )
      )

    if match?(%Project{}, project), do: :ok, else: {:error, :invalid_storage_reservation_project}
  end

  defp validate_reservation_scope(%Workspace{id: workspace_id}, %{project_id: project_id})
       when is_integer(project_id) and project_id > 0 do
    project =
      Repo.one(
        from(candidate in Project,
          where:
            candidate.id == ^project_id and candidate.workspace_id == ^workspace_id and
              is_nil(candidate.deleted_at),
          lock: "FOR UPDATE"
        )
      )

    if match?(%Project{}, project), do: :ok, else: {:error, :invalid_storage_reservation_project}
  end

  defp validate_reservation_scope(%Workspace{}, _attrs), do: {:error, :invalid_storage_reservation_project}

  defp validate_reservation_target(%{
         project_id: project_id,
         project_snapshot_id: snapshot_id,
         kind: kind,
         reserved_bytes: reserved_bytes
       })
       when is_positive_integer(project_id) and is_positive_integer(snapshot_id) and
              is_non_negative_integer(reserved_bytes) do
    snapshot =
      Repo.one(
        from(candidate in ProjectSnapshot,
          where: candidate.id == ^snapshot_id and candidate.project_id == ^project_id,
          lock: "FOR UPDATE"
        )
      )

    with true <- valid_reservation_target?(kind, snapshot),
         :ok <- validate_target_allocation(kind, reserved_bytes, snapshot) do
      {:ok, snapshot}
    else
      _invalid -> {:error, :invalid_storage_reservation_snapshot}
    end
  end

  defp validate_reservation_target(_attrs), do: {:error, :invalid_storage_reservation_snapshot}

  defp valid_reservation_target?("snapshot_build", %ProjectSnapshot{
         project_id: project_id,
         format_version: 2,
         mode: "full",
         lifecycle_state: lifecycle_state,
         integrity_state: "unknown",
         accounted_size_bytes: nil,
         accounting_version: nil,
         object_prefix: object_prefix,
         archive_storage_key: archive_storage_key,
         manifest_storage_key: manifest_storage_key
       })
       when lifecycle_state in ["pending", "building", "verifying"] and is_binary(object_prefix) do
    archive_storage_key == SnapshotArchiveStorage.archive_key(object_prefix) and
      manifest_storage_key == SnapshotArchiveStorage.manifest_key(object_prefix) and
      SnapshotArchiveStorage.ready_prefix_for_project?(project_id, object_prefix)
  end

  defp valid_reservation_target?(kind, %ProjectSnapshot{
         format_version: 2,
         mode: "full",
         lifecycle_state: "ready",
         integrity_state: "verified",
         accounted_size_bytes: accounted_size_bytes,
         accounting_version: @accounting_version
       })
       when kind in ["restore_staging", "snapshot_export"] and is_positive_integer(accounted_size_bytes), do: true

  defp valid_reservation_target?(_kind, _snapshot), do: false

  defp validate_target_allocation("snapshot_export", bytes, %ProjectSnapshot{}) when is_non_negative_integer(bytes),
    do: :ok

  defp validate_target_allocation(kind, bytes, %ProjectSnapshot{})
       when kind in ["snapshot_build", "restore_staging"] and is_positive_integer(bytes), do: :ok

  defp validate_target_allocation(_kind, _bytes, _snapshot), do: {:error, :invalid_storage_reservation_allocation}

  defp validate_active_target_facts(%StorageReservation{}, %ProjectSnapshot{}), do: :ok

  defp normalize_reservation_attrs(attrs) do
    workspace_id = value(attrs, :workspace_id)
    project_id = value(attrs, :project_id)
    project_snapshot_id = value(attrs, :project_snapshot_id)
    kind = value(attrs, :kind)
    lease_token = attrs |> value(:lease_token) |> normalize_lease_token()
    measured_at = TimeHelpers.now()

    %{
      workspace_id: workspace_id,
      workspace_id_snapshot: workspace_id,
      project_id: project_id,
      project_id_snapshot: project_id,
      project_snapshot_id: project_snapshot_id,
      project_snapshot_id_snapshot: project_snapshot_id,
      idempotency_key: value(attrs, :idempotency_key),
      kind: kind,
      status: "active",
      storage_namespace: reservation_namespace(project_id, kind, lease_token),
      cleanup_object_prefix: nil,
      reserved_bytes: value(attrs, :reserved_bytes),
      lease_token: lease_token,
      generation: 1,
      expires_at:
        value(attrs, :expires_at) ||
          DateTime.add(
            measured_at,
            reservation_ttl_seconds(kind, value(attrs, :reserved_bytes)),
            :second
          ),
      accounting_version: @accounting_version,
      accounting_measured_at: measured_at
    }
  end

  defp reservation_namespace(project_id, kind, lease_token)
       when is_positive_integer(project_id) and kind in @reservation_kinds and is_binary(lease_token) do
    normalized_kind = String.replace(kind, "_", "-")
    "projects/#{project_id}/storage-reservations/v1/#{normalized_kind}/#{lease_token}"
  end

  defp reservation_namespace(_project_id, _kind, _lease_token), do: nil

  defp normalize_lease_token(nil), do: Ecto.UUID.generate()

  defp normalize_lease_token(lease_token) do
    case Ecto.UUID.cast(lease_token) do
      {:ok, canonical_lease_token} -> canonical_lease_token
      :error -> nil
    end
  end

  defp put_target_facts(attrs, %ProjectSnapshot{object_prefix: object_prefix}) when attrs.kind == "snapshot_build" do
    {:ok, %{attrs | cleanup_object_prefix: object_prefix}}
  end

  defp put_target_facts(attrs, %ProjectSnapshot{}) when attrs.kind in ["restore_staging", "snapshot_export"] do
    {:ok, %{attrs | cleanup_object_prefix: attrs.storage_namespace}}
  end

  defp put_target_facts(_attrs, _target), do: {:error, :invalid_storage_reservation_snapshot}

  defp reuse_operation_identity(attrs, reservation) do
    %{
      attrs
      | storage_namespace: reservation.storage_namespace,
        lease_token: reservation.lease_token
    }
  end

  defp ensure_exclusive_snapshot_target_available(%{kind: kind, project_snapshot_id: snapshot_id})
       when kind in @exclusive_snapshot_operation_kinds and is_positive_integer(snapshot_id) do
    active? =
      Repo.exists?(
        from(reservation in StorageReservation,
          where:
            reservation.project_snapshot_id_snapshot == ^snapshot_id and
              reservation.status == "active" and
              reservation.kind in ^@exclusive_snapshot_operation_kinds
        )
      )

    if active?, do: {:error, :storage_reservation_active_for_snapshot}, else: :ok
  end

  defp ensure_exclusive_snapshot_target_available(_attrs), do: :ok

  defp normalize_release_attrs(reservation, attrs) do
    reason = value(attrs, :reason)

    with :ok <- validate_release_reason(reason) do
      normalize_cleanup_release(
        reservation,
        reason,
        value(attrs, :cleanup_status),
        value(attrs, :cleanup_reference),
        value(attrs, :cleanup_request_id),
        value(attrs, :cleanup_scope),
        value(attrs, :cleanup_proof)
      )
    end
  end

  defp validate_release_reason(reason) when is_binary(reason) do
    if String.trim(reason) == "",
      do: {:error, :invalid_storage_reservation_release_reason},
      else: :ok
  end

  defp validate_release_reason(_reason), do: {:error, :invalid_storage_reservation_release_reason}

  defp normalize_cleanup_release(reservation, reason, "not_required", nil, nil, nil, cleanup_proof)
       when is_map(cleanup_proof) do
    normalize_no_write_release(reservation, reason, cleanup_proof)
  end

  defp normalize_cleanup_release(reservation, reason, "owned", nil, cleanup_request_id, cleanup_scope, nil)
       when is_positive_integer(cleanup_request_id) and is_map(cleanup_scope) do
    normalize_cleanup_owner(reservation, reason, cleanup_request_id, cleanup_scope)
  end

  defp normalize_cleanup_release(_reservation, _reason, _status, _reference, _request_id, _cleanup_scope, _cleanup_proof),
    do: {:error, :storage_reservation_cleanup_ownership_required}

  defp normalize_no_write_release(%StorageReservation{storage_started_at: nil} = reservation, reason, cleanup_proof) do
    with {:ok, prefixes} <- operation_object_prefixes(reservation),
         :ok <- validate_no_write_proof(reservation, cleanup_proof),
         :ok <- validate_no_write_publication_claim(reservation),
         false <- cleanup_handed_off_for_prefixes?(prefixes) do
      {:ok,
       %{
         reason: reason,
         cleanup_status: "not_required",
         cleanup_reference: no_write_reference(reservation.storage_namespace)
       }}
    else
      _invalid -> {:error, :storage_reservation_cleanup_ownership_required}
    end
  end

  defp normalize_no_write_release(_reservation, _reason, _cleanup_proof),
    do: {:error, :storage_reservation_cleanup_ownership_required}

  defp validate_no_write_proof(reservation, cleanup_proof) do
    if value(cleanup_proof, :type) == "storage_not_started" and
         value(cleanup_proof, :storage_namespace) == reservation.storage_namespace,
       do: :ok,
       else: {:error, :invalid_no_write_proof}
  end

  defp cleanup_handed_off_for_prefixes?(prefixes) do
    prefixes
    |> Map.values()
    |> Enum.any?(&StorageCleanupOwnershipReceipt.handed_off_for_prefix?/1)
  end

  defp normalize_cleanup_owner(reservation, reason, cleanup_request_id, cleanup_scope) do
    with {:ok, request_keys} <- StorageCleanupOwnershipReceipt.storage_keys(cleanup_request_id),
         true <- valid_inventory_bounds?(request_keys),
         {:ok, scope_keys} <- validate_cleanup_scope(reservation, cleanup_request_id, cleanup_scope),
         true <- length(request_keys) == length(scope_keys),
         true <- MapSet.equal?(MapSet.new(request_keys), MapSet.new(scope_keys)),
         :ok <- validate_cleanup_commitment(reservation, scope_keys),
         :ok <- validate_cleanup_publication_claim(reservation) do
      {:ok,
       %{
         reason: reason,
         cleanup_status: "owned",
         cleanup_reference: cleanup_reference(cleanup_request_id)
       }}
    else
      _invalid -> {:error, :storage_reservation_cleanup_ownership_required}
    end
  end

  defp validate_planned_cleanup_scope(reservation, cleanup_plan) do
    with {:ok, prefixes} <- operation_object_prefixes(reservation),
         storage_keys when is_list(storage_keys) <- value(cleanup_plan, :storage_keys),
         true <- valid_unique_inventory?(storage_keys),
         :ok <- validate_cleanup_inventory(prefixes, cleanup_plan, storage_keys) do
      {:ok, storage_keys}
    else
      _invalid -> {:error, :invalid_storage_reservation_cleanup_plan}
    end
  end

  defp validate_cleanup_scope(reservation, cleanup_request_id, cleanup_scope) do
    with :ok <- validate_cleanup_scope_reference(cleanup_request_id, cleanup_scope),
         {:ok, prefixes} <- operation_object_prefixes(reservation),
         storage_keys when is_list(storage_keys) <- value(cleanup_scope, :storage_keys),
         true <- valid_unique_inventory?(storage_keys),
         :ok <- validate_cleanup_inventory(prefixes, cleanup_scope, storage_keys) do
      {:ok, storage_keys}
    else
      _invalid -> {:error, :storage_reservation_cleanup_ownership_required}
    end
  end

  defp validate_cleanup_scope_reference(cleanup_request_id, cleanup_scope) do
    if value(cleanup_scope, :cleanup_request_id) == cleanup_request_id,
      do: :ok,
      else: {:error, :storage_reservation_cleanup_ownership_required}
  end

  defp valid_unique_inventory?(storage_keys) do
    valid_inventory_bounds?(storage_keys) and length(storage_keys) == length(Enum.uniq(storage_keys))
  end

  defp valid_inventory_bounds?(storage_keys) when is_list(storage_keys) do
    # Cleanup ownership must remain provable after operators lower runtime
    # verification limits. The object-format hard bound contains the fixed
    # four-key archive cleanup; digest/count prove the exact inventory.
    max_count = 2 * (SnapshotObjectFormat.hard_limits().max_objects + 1)

    storage_keys != [] and length(storage_keys) <= max_count and
      Enum.all?(storage_keys, &is_binary/1) and
      Enum.reduce_while(storage_keys, 0, fn storage_key, total_bytes ->
        next_total = total_bytes + byte_size(storage_key)

        if next_total <= @max_cleanup_inventory_bytes,
          do: {:cont, next_total},
          else: {:halt, :too_large}
      end) != :too_large
  end

  defp valid_inventory_bounds?(_storage_keys), do: false

  defp validate_cleanup_commitment(
         %StorageReservation{
           storage_started_at: %DateTime{},
           cleanup_inventory_digest: inventory_digest,
           cleanup_inventory_count: inventory_count
         },
         storage_keys
       ) do
    if inventory_count == length(storage_keys) and inventory_digest == cleanup_inventory_digest(storage_keys),
      do: :ok,
      else: {:error, :storage_reservation_cleanup_inventory_mismatch}
  end

  defp validate_cleanup_commitment(_reservation, _storage_keys),
    do: {:error, :storage_reservation_cleanup_inventory_missing}

  defp validate_no_write_publication_claim(%StorageReservation{kind: "snapshot_build", id: reservation_id}) do
    if Repo.exists?(
         from(claim in SnapshotObjectPublicationClaim,
           where: claim.storage_reservation_id_snapshot == ^reservation_id
         )
       ),
       do: {:error, :snapshot_object_publication_claim_still_active},
       else: :ok
  end

  defp validate_no_write_publication_claim(_reservation), do: :ok

  defp validate_cleanup_publication_claim(%StorageReservation{
         kind: "snapshot_build",
         id: reservation_id,
         lease_token: reservation_lease_token,
         cleanup_object_prefix: object_prefix
       }) do
    case Repo.one(
           from(claim in SnapshotObjectPublicationClaim,
             where: claim.storage_reservation_id_snapshot == ^reservation_id,
             lock: "FOR UPDATE"
           )
         ) do
      %SnapshotObjectPublicationClaim{
        object_prefix: ^object_prefix,
        storage_reservation_lease_token: ^reservation_lease_token,
        status: "poisoned"
      } ->
        :ok

      %SnapshotObjectPublicationClaim{
        object_prefix: ^object_prefix,
        storage_reservation_lease_token: ^reservation_lease_token,
        status: "published"
      } ->
        published_claim_deletion_owned?(reservation_id, object_prefix)

      _claim ->
        {:error, :snapshot_object_publication_claim_not_poisoned}
    end
  end

  defp validate_cleanup_publication_claim(_reservation), do: :ok

  defp published_claim_deletion_owned?(reservation_id, object_prefix) do
    deleting_snapshot? =
      Repo.exists?(
        from(snapshot in ProjectSnapshot,
          join: reservation in StorageReservation,
          on: reservation.project_snapshot_id_snapshot == snapshot.id,
          where:
            reservation.id == ^reservation_id and snapshot.lifecycle_state == "deleting" and
              snapshot.object_prefix == ^object_prefix
        )
      )

    if deleting_snapshot? and StorageCleanupOwnershipReceipt.handed_off_for_prefix?(object_prefix),
      do: :ok,
      else: {:error, :snapshot_object_publication_claim_not_poisoned}
  end

  defp cleanup_inventory_digest(storage_keys) do
    storage_keys
    |> Enum.sort()
    |> Enum.map_join(fn storage_key -> "#{byte_size(storage_key)}:#{storage_key}" end)
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp validate_cleanup_inventory(%{staging: staging_prefix, ready: ready_prefix}, cleanup_scope, storage_keys) do
    with ^staging_prefix <- value(cleanup_scope, :staging_prefix),
         ^ready_prefix <- value(cleanup_scope, :ready_prefix),
         true <- Enum.all?(storage_keys, &snapshot_cleanup_key?(&1, staging_prefix, ready_prefix)),
         {:ok, staging_paths} <- relative_cleanup_paths(storage_keys, staging_prefix),
         {:ok, ready_paths} <- relative_cleanup_paths(storage_keys, ready_prefix),
         true <- MapSet.equal?(staging_paths, ready_paths),
         true <- required_cleanup_paths_present?(staging_paths) do
      :ok
    else
      _invalid -> {:error, :invalid_snapshot_cleanup_inventory}
    end
  end

  defp validate_cleanup_inventory(%{temporary: temporary_prefix}, cleanup_scope, storage_keys) do
    with ^temporary_prefix <- value(cleanup_scope, :temporary_prefix),
         true <- Enum.all?(storage_keys, &temporary_object_key?(&1, temporary_prefix)),
         {:ok, _paths} <- relative_cleanup_paths(storage_keys, temporary_prefix) do
      :ok
    else
      _invalid -> {:error, :invalid_temporary_cleanup_inventory}
    end
  end

  defp relative_cleanup_paths(storage_keys, prefix) do
    matching_keys = Enum.filter(storage_keys, &String.starts_with?(&1, prefix <> "/"))

    if matching_keys == [] do
      {:error, :missing_cleanup_namespace}
    else
      {:ok,
       MapSet.new(matching_keys, fn key ->
         String.replace_prefix(key, prefix <> "/", "")
       end)}
    end
  end

  defp required_cleanup_paths_present?(paths) do
    MapSet.subset?(MapSet.new(["snapshot.zip", "manifest.json"]), paths)
  end

  defp snapshot_cleanup_key?(storage_key, staging_prefix, ready_prefix) do
    snapshot_object_key?(storage_key, staging_prefix) or snapshot_object_key?(storage_key, ready_prefix)
  end

  defp temporary_object_key?(storage_key, prefix) when is_binary(storage_key) and is_binary(prefix) do
    if String.starts_with?(storage_key, prefix <> "/") do
      storage_key
      |> String.replace_prefix(prefix <> "/", "")
      |> valid_temporary_relative_key?()
    else
      false
    end
  end

  defp temporary_object_key?(_storage_key, _prefix), do: false

  defp valid_temporary_relative_key?(relative_key) do
    segments = String.split(relative_key, "/", trim: false)

    byte_size(relative_key) <= @max_temporary_relative_key_bytes and
      length(segments) <= @max_temporary_path_segments and
      Enum.all?(segments, &Regex.match?(@temporary_path_segment_regex, &1))
  end

  defp snapshot_object_key?(storage_key, prefix) do
    if String.starts_with?(storage_key, prefix <> "/") do
      relative_key = String.replace_prefix(storage_key, prefix <> "/", "")
      valid_snapshot_object_tail?(prefix, String.split(relative_key, "/", trim: false))
    else
      false
    end
  end

  defp valid_snapshot_object_tail?(prefix, ["manifest.json"]) do
    String.contains?(prefix, "/snapshots/archives/v2/")
  end

  defp valid_snapshot_object_tail?(prefix, ["snapshot.zip"]) do
    String.contains?(prefix, "/snapshots/archives/v2/")
  end

  defp valid_snapshot_object_tail?(_prefix, _parts), do: false

  defp snapshot_ready_identity(project_id, ready_prefix)
       when is_positive_integer(project_id) and is_binary(ready_prefix) do
    case String.split(ready_prefix, "/", trim: false) do
      ["projects", encoded_project_id, "snapshots", "archives", "v2", "ready", token] ->
        if encoded_project_id == Integer.to_string(project_id) and
             Regex.match?(@snapshot_object_token_regex, token),
           do: {:ok, token},
           else: :error

      _parts ->
        :error
    end
  end

  defp snapshot_ready_identity(_project_id, _ready_prefix), do: :error

  defp cleanup_reference(cleanup_request_id), do: "storage_cleanup_request:#{cleanup_request_id}"
  defp no_write_reference(storage_namespace), do: "storage_not_started:#{storage_namespace}"

  defp normalize_provider_measurements(measurements) do
    normalized =
      Map.new(@provider_measurement_keys, fn key ->
        {key, value(measurements, key) || 0}
      end)

    if Enum.all?(normalized, fn {_key, bytes} -> is_integer(bytes) and bytes >= 0 end),
      do: {:ok, normalized},
      else: {:error, :invalid_provider_footprint}
  end

  defp normalize_owner_result({:ok, result}), do: {:ok, result}
  defp normalize_owner_result({:error, _reason} = error), do: error
  defp normalize_owner_result(other), do: {:error, {:invalid_storage_reservation_owner_result, other}}

  defp validate_snapshot_publication_commitment(%StorageReservation{
         kind: "snapshot_build",
         id: reservation_id,
         lease_token: reservation_lease_token,
         cleanup_object_prefix: object_prefix
       }) do
    case Repo.one(
           from(claim in SnapshotObjectPublicationClaim,
             where: claim.storage_reservation_id_snapshot == ^reservation_id,
             lock: "FOR UPDATE"
           )
         ) do
      %SnapshotObjectPublicationClaim{
        object_prefix: ^object_prefix,
        storage_reservation_lease_token: ^reservation_lease_token,
        status: "published"
      } ->
        :ok

      _claim ->
        {:error, :snapshot_object_publication_not_ready}
    end
  end

  defp validate_snapshot_publication_commitment(_reservation), do: :ok

  defp committed_owner_expectation(
         %StorageReservation{kind: kind, project_id_snapshot: project_id, project_snapshot_id_snapshot: snapshot_id} =
           reservation,
         %ProjectSnapshot{id: snapshot_id} = snapshot
       )
       when kind == "snapshot_build" do
    owner_expectation(reservation, project_id, snapshot)
  end

  defp committed_owner_expectation(_reservation, _snapshot), do: {:error, :storage_reservation_not_committable}

  defp owner_expectation(%StorageReservation{kind: "snapshot_build"}, project_id, %ProjectSnapshot{
         id: snapshot_id,
         project_id: project_id,
         format_version: 2,
         mode: "full",
         lifecycle_state: lifecycle_state,
         integrity_state: "unknown",
         accounted_size_bytes: nil,
         accounting_version: nil,
         object_prefix: object_prefix,
         archive_storage_key: archive_storage_key,
         manifest_storage_key: manifest_storage_key
       })
       when lifecycle_state in ["pending", "building", "verifying"] and is_binary(object_prefix) do
    valid_keys? =
      archive_storage_key == SnapshotArchiveStorage.archive_key(object_prefix) and
        manifest_storage_key == SnapshotArchiveStorage.manifest_key(object_prefix)

    if valid_keys? and SnapshotArchiveStorage.ready_prefix_for_project?(project_id, object_prefix) do
      {:ok,
       %{
         snapshot_id: snapshot_id,
         project_id: project_id,
         kind: "snapshot_build",
         object_prefix: object_prefix,
         baseline_accounted_bytes: 0,
         final_modes: ["full"]
       }}
    else
      {:error, :storage_reservation_owner_mismatch}
    end
  end

  defp owner_expectation(_reservation, _project_id, _snapshot), do: {:error, :storage_reservation_owner_mismatch}

  defp validate_committed_owner(reservation, expectation, %ProjectSnapshot{id: snapshot_id}, actual_bytes)
       when snapshot_id == expectation.snapshot_id do
    expected_accounted_bytes = expectation.baseline_accounted_bytes + actual_bytes

    case Repo.get(ProjectSnapshot, snapshot_id) do
      %ProjectSnapshot{
        project_id: project_id,
        object_prefix: object_prefix,
        lifecycle_state: "ready",
        integrity_state: "verified",
        accounted_size_bytes: ^expected_accounted_bytes,
        accounting_version: @accounting_version,
        mode: mode
      } = snapshot ->
        if project_id == expectation.project_id and
             snapshot_id == reservation.project_snapshot_id_snapshot and
             mode in expectation.final_modes and expected_object_prefix?(expectation, object_prefix) and
             valid_committed_accounting?(expectation, snapshot, actual_bytes) and
             publication_inventory_matches?(reservation, snapshot),
           do: :ok,
           else: {:error, :storage_reservation_owner_mismatch}

      _snapshot ->
        {:error, :storage_reservation_owner_mismatch}
    end
  end

  defp validate_committed_owner(_reservation, _expectation, _result, _actual_bytes),
    do: {:error, :storage_reservation_owner_mismatch}

  defp valid_committed_accounting?(%{kind: "snapshot_build"}, %ProjectSnapshot{}, _actual_bytes), do: true

  defp valid_committed_accounting?(_expectation, _snapshot, _actual_bytes), do: false

  defp publication_inventory_matches?(
         %StorageReservation{kind: "snapshot_build", id: reservation_id},
         %ProjectSnapshot{} = snapshot
       ) do
    expected_digest = SnapshotObjectPublicationClaim.inventory_digest(snapshot)

    Repo.exists?(
      from(claim in SnapshotObjectPublicationClaim,
        where:
          claim.storage_reservation_id_snapshot == ^reservation_id and
            claim.status == "published" and claim.inventory_digest == ^expected_digest
      )
    )
  end

  defp publication_inventory_matches?(%StorageReservation{}, %ProjectSnapshot{}), do: true

  defp expected_object_prefix?(%{object_prefix: object_prefix}, object_prefix), do: true
  defp expected_object_prefix?(expectation, _object_prefix), do: not Map.has_key?(expectation, :object_prefix)

  defp same_reservation?(reservation, attrs) do
    reservation.workspace_id_snapshot == attrs.workspace_id and
      reservation.project_id_snapshot == attrs.project_id and
      reservation.project_snapshot_id_snapshot == attrs.project_snapshot_id and
      reservation.idempotency_key == attrs.idempotency_key and
      reservation.kind == attrs.kind and reservation.reserved_bytes == attrs.reserved_bytes and
      reservation.cleanup_object_prefix == attrs.cleanup_object_prefix
  end

  defp same_release?(reservation, attrs) do
    reservation.release_reason == attrs.reason and
      reservation.cleanup_status == attrs.cleanup_status and
      reservation.cleanup_reference == attrs.cleanup_reference
  end

  defp validate_operation_bytes(%StorageReservation{kind: "snapshot_export"}, bytes) when is_non_negative_integer(bytes),
    do: :ok

  defp validate_operation_bytes(%StorageReservation{kind: kind}, bytes)
       when kind in ["snapshot_build", "restore_staging"] and is_positive_integer(bytes), do: :ok

  defp validate_operation_bytes(_reservation, _bytes), do: {:error, :invalid_storage_reservation_allocation}

  defp verify_lease(%StorageReservation{lease_token: lease_token}, lease_token), do: :ok
  defp verify_lease(_reservation, _lease_token), do: {:error, :storage_reservation_lease_mismatch}

  defp verify_generation(%StorageReservation{generation: generation}, generation), do: :ok

  defp verify_generation(_reservation, _expected_generation), do: {:error, :storage_reservation_generation_mismatch}

  defp verify_unexpired(%StorageReservation{expires_at: expires_at}) do
    if DateTime.after?(expires_at, TimeHelpers.now()),
      do: :ok,
      else: {:error, :storage_reservation_lease_expired}
  end

  defp verify_storage_started(%StorageReservation{storage_started_at: %DateTime{}}), do: :ok
  defp verify_storage_started(%StorageReservation{}), do: {:error, :storage_reservation_not_started}

  defp verify_storage_start_allowed(%StorageReservation{kind: "snapshot_export", reserved_bytes: 0}),
    do: {:error, :zero_byte_snapshot_export_lease_cannot_start_storage}

  defp verify_storage_start_allowed(%StorageReservation{}), do: :ok

  defp active_reservation(%StorageReservation{status: "active"}), do: :ok
  defp active_reservation(%StorageReservation{status: "committed"}), do: {:error, :storage_reservation_already_committed}
  defp active_reservation(%StorageReservation{status: "released"}), do: {:error, :storage_reservation_already_released}

  defp renewed_expiry(reservation, measured_at) do
    full_ttl =
      DateTime.add(
        measured_at,
        reservation_ttl_seconds(reservation.kind, reservation.reserved_bytes),
        :second
      )

    after_previous_expiry = DateTime.add(reservation.expires_at, 1, :second)

    if DateTime.after?(full_ttl, after_previous_expiry), do: full_ttl, else: after_previous_expiry
  end

  defp reservation_ttl_seconds("snapshot_build", _reserved_bytes),
    do: ProjectSnapshotLeasePolicy.build_lease_ttl_seconds()

  defp reservation_ttl_seconds("snapshot_export", 0), do: ProjectSnapshotLeasePolicy.download_export_lease_ttl_seconds()

  defp reservation_ttl_seconds(_kind, _reserved_bytes), do: @default_reservation_ttl_seconds

  defp database_clock_now do
    %Postgrex.Result{rows: [[now]]} = Repo.query!("SELECT clock_timestamp()")
    DateTime.truncate(now, :second)
  end

  defp consistent_read(fun) do
    if Repo.in_transaction?() do
      fun.()
    else
      case Repo.repeatable_read(fun, timeout: :infinity) do
        {:ok, result} -> result
        {:error, reason} -> raise "storage accounting read failed: #{inspect(reason)}"
      end
    end
  end

  defp lock_workspace(workspace_id) do
    Repo.one(from(workspace in Workspace, where: workspace.id == ^workspace_id, lock: "FOR UPDATE"))
  end

  defp with_workspace_lock_marker(workspace_id, fun) do
    previous_workspace_ids = Process.get(@workspace_lock_process_key)
    Process.put(@workspace_lock_process_key, [workspace_id | List.wrap(previous_workspace_ids)])

    try do
      fun.()
    after
      restore_workspace_lock_marker(previous_workspace_ids)
    end
  end

  defp restore_workspace_lock_marker(nil), do: Process.delete(@workspace_lock_process_key)

  defp restore_workspace_lock_marker(previous_workspace_ids),
    do: Process.put(@workspace_lock_process_key, previous_workspace_ids)

  defp with_storage_commit_context(reservation, fun) do
    previous_context = Process.get(@storage_commit_process_key)

    Process.put(@storage_commit_process_key, %{
      reservation_id: reservation.id,
      workspace_id: reservation.workspace_id_snapshot,
      project_snapshot_id: reservation.project_snapshot_id_snapshot,
      kind: reservation.kind
    })

    try do
      fun.()
    after
      restore_storage_commit_context(previous_context)
    end
  end

  defp restore_storage_commit_context(nil), do: Process.delete(@storage_commit_process_key)
  defp restore_storage_commit_context(context), do: Process.put(@storage_commit_process_key, context)

  defp empty_bucket, do: %{bytes: 0, count: 0}

  defp value(attrs, key), do: Map.get(attrs, key, Map.get(attrs, to_string(key)))
end
