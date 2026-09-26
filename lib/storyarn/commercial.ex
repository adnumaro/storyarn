defmodule Storyarn.Commercial do
  @moduledoc """
  Public facade for commercial policy and storage accounting.

  Commercial owns plans, subscriptions, entitlements, usage limits and
  workspace-scoped storage reservations. Other bounded contexts consume these
  contracts through this module without depending on Commercial's commands,
  queries, entities, projections, reference data, rules or execution modules.

  The extraction from Platform deliberately preserves the existing database,
  transaction, workspace-lock and reservation-fencing semantics.
  """

  alias Storyarn.Commercial.Billing
  alias Storyarn.Commercial.Entitlements
  alias Storyarn.Commercial.ProjectStorageReservations

  @typedoc "Transport-neutral result of provisioning an account subscription."
  @type subscription_receipt :: %{
          required(:id) => pos_integer(),
          required(:user_id) => pos_integer(),
          required(:plan) => String.t(),
          required(:status) => String.t()
        }

  @typedoc "Transport-neutral failure returned when provisioning an account subscription."
  @type subscription_creation_error :: %{
          required(:code) =>
            :subscription_already_exists
            | :invalid_subscription
            | :subscription_creation_failed,
          required(:field_errors) => %{
            optional(atom()) => [:already_exists | :required | :invalid]
          }
        }

  @type storage_reservation_receipt :: ProjectStorageReservations.receipt()
  @type storage_reservation_write_error :: ProjectStorageReservations.write_error()

  @doc """
  Returns the current scalar entitlement for one workspace resource.

  The value is a non-negative integer, `:unlimited`, or `nil` when the plan
  does not define the resource. Callers must treat `nil` as blocked and match
  `:unlimited` explicitly rather than comparing it with a number.
  """
  @spec entitlement_limit(pos_integer(), atom()) :: non_neg_integer() | :unlimited | nil
  defdelegate entitlement_limit(workspace_id, resource), to: Entitlements, as: :limit

  # Commercial policy and usage contracts. Billing keeps the implementation
  # and the current shared-database lock semantics until persistence ownership
  # is migrated separately.
  defdelegate can_create_workspace?(user), to: Billing

  defdelegate can_create_project?(workspace), to: Billing
  defdelegate can_publish_reserved_project?(workspace), to: Billing
  defdelegate can_create_project_template?(source_project), to: Billing
  defdelegate can_create_project_template_version?(template), to: Billing

  @doc """
  Checks that giving `role` to `email` in a workspace or project fits the
  seats of the account that owns it, for an invitation, a role change or a
  project transfer.

  Viewers are free, and someone who already holds a seat in any of the
  account's workspaces can take another editing role without a new one. Only
  the account owner (`actor` is their user id) or an operator (`:operator`)
  can raise the count. Call it inside the transaction that writes the
  membership or invitation; it locks the account's seats until that
  transaction ends.
  """
  @spec check_editor_seat(map(), String.t(), String.t(), pos_integer() | :operator) ::
          :ok | {:error, :limit_reached, map()} | {:error, :seat_requires_account_owner}
  defdelegate check_editor_seat(workspace_or_project, email, role, actor), to: Billing

  @doc """
  Checks that accepting an invitation with `role` fits the account's seats,
  counting memberships only: the invitation already holds its seat.
  """
  @spec check_editor_seat_acceptance(map(), String.t(), String.t()) ::
          :ok | {:error, :limit_reached, map()}
  defdelegate check_editor_seat_acceptance(workspace_or_project, email, role), to: Billing

  defdelegate can_upload_asset?(workspace, file_size), to: Billing
  defdelegate can_upload_asset_for_project?(project, file_size), to: Billing
  defdelegate project_usage(project_id, workspace_id), to: Billing
  defdelegate project_limits_usage(project), to: Billing

  @doc """
  Returns how many hours each deleted item stays in the trash, for a list of
  `{workspace_id, deleted_at}` deletions, in the same order.

  An item keeps the retention its workspace owner's plan granted when it was
  deleted: a downgrade never shortens it, an upgrade lengthens it.
  """
  @spec trash_retention_hours([{pos_integer(), DateTime.t()}]) :: [pos_integer()]
  defdelegate trash_retention_hours(deletions), to: Billing

  @doc "Creates an account's default subscription without exposing Commercial persistence structs."
  @spec create_account_subscription(map()) ::
          {:ok, subscription_receipt()} | {:error, subscription_creation_error()}
  defdelegate create_account_subscription(user), to: Billing

  @doc "Subscribes the caller to Commercial-owned snapshot export-lease invalidations for one Project."
  @spec subscribe_project_snapshot_export_leases(pos_integer()) :: :ok | {:error, term()}
  defdelegate subscribe_project_snapshot_export_leases(project_id), to: Billing

  # Storage coordination contracts intentionally preserve Billing's existing
  # transaction and workspace-lock callbacks byte-for-byte.
  defdelegate with_storage_accounting_lock(workspace_id, fun, opts \\ []), to: Billing
  defdelegate transact_with_workspace_lock(workspace_id, fun, opts \\ []), to: Billing
  defdelegate workspace_lock_held?(workspace_id), to: Billing

  defdelegate snapshot_storage_commit_context?(snapshot_id, kind), to: Billing

  defdelegate settle_expired_snapshot_export_leases_locked(snapshot, workspace_id),
    to: Billing

  defdelegate recover_expired_snapshot_export_leases(now, opts \\ []), to: Billing
  defdelegate purge_released_snapshot_export_leases(cutoff, opts \\ []), to: Billing

  defdelegate snapshot_download_signed_url_ttl_seconds(), to: Billing
  defdelegate snapshot_download_max_transfer_seconds(), to: Billing
  defdelegate snapshot_download_export_lease_ttl_seconds(), to: Billing
  defdelegate snapshot_build_heartbeat_interval_ms(), to: Billing
  defdelegate snapshot_build_lease_ttl_seconds(), to: Billing
  defdelegate snapshot_export_lease_retention_seconds(), to: Billing

  @doc "Returns Commercial-accounted storage usage for one workspace identity."
  @spec workspace_storage_usage(pos_integer()) :: map()
  defdelegate workspace_storage_usage(workspace_id), to: Billing

  @doc "Returns the owner's plan and the workspace-wide usage buckets (projects, storage) for one workspace."
  @spec workspace_usage(map()) :: map()
  defdelegate workspace_usage(workspace), to: Billing, as: :usage

  @doc """
  Returns an account's plan, the editor seats it uses and the workspaces it
  owns. These are totals across the whole account: show them to its owner only.
  """
  @spec account_usage(pos_integer()) :: map()
  defdelegate account_usage(user_id), to: Billing

  @doc """
  Returns why a workspace is read-only: the size limits its owner's account
  exceeds, as strings, or an empty list when it is writable. A locked account
  is re-evaluated first, so it unlocks as soon as it is back within limits.
  """
  @spec workspace_read_only_reasons(pos_integer()) :: [String.t()]
  defdelegate workspace_read_only_reasons(workspace_id), to: Billing

  @doc "Returns why an account is read-only, or an empty list. Same rules as `workspace_read_only_reasons/1`."
  @spec account_read_only_reasons(pos_integer()) :: [String.t()]
  defdelegate account_read_only_reasons(user_id), to: Billing

  @doc "Returns stored snapshots plus active build reservations for one Project."
  @spec project_snapshot_slot_usage(pos_integer()) :: non_neg_integer()
  defdelegate project_snapshot_slot_usage(project_id), to: Billing

  @doc "Returns neutral active-reservation totals keyed by Project snapshot id."
  @spec active_project_snapshot_reservations([pos_integer()]) :: map()
  defdelegate active_project_snapshot_reservations(snapshot_ids),
    to: Billing,
    as: :active_storage_reservations_by_snapshot

  @doc "Reserves Commercial-owned storage capacity and returns a transport-neutral receipt."
  @spec reserve_project_storage(map()) ::
          {:ok, storage_reservation_receipt()} | storage_reservation_write_error()
  defdelegate reserve_project_storage(attrs),
    to: ProjectStorageReservations,
    as: :reserve

  @doc "Acquires a snapshot export lease and returns a transport-neutral receipt."
  @spec acquire_project_snapshot_export_lease(map()) ::
          {:ok, storage_reservation_receipt()} | storage_reservation_write_error()
  defdelegate acquire_project_snapshot_export_lease(attrs),
    to: ProjectStorageReservations,
    as: :acquire_snapshot_export_lease

  @doc false
  @spec renew_project_storage_reservation(pos_integer(), Ecto.UUID.t(), pos_integer()) ::
          {:ok, storage_reservation_receipt()} | storage_reservation_write_error()
  defdelegate renew_project_storage_reservation(
                reservation_id,
                lease_token,
                expected_generation
              ),
              to: ProjectStorageReservations,
              as: :renew_live

  @doc "Extends a Project storage reservation and returns a transport-neutral receipt."
  @spec extend_project_storage_reservation(
          pos_integer(),
          Ecto.UUID.t(),
          pos_integer(),
          non_neg_integer()
        ) :: {:ok, storage_reservation_receipt()} | storage_reservation_write_error()
  defdelegate extend_project_storage_reservation(
                reservation_id,
                lease_token,
                expected_generation,
                target_bytes
              ),
              to: ProjectStorageReservations,
              as: :extend

  @doc "Marks the reservation write fence and returns a transport-neutral receipt."
  @spec mark_project_storage_reservation_started(
          pos_integer(),
          Ecto.UUID.t(),
          pos_integer(),
          map()
        ) :: {:ok, storage_reservation_receipt()} | storage_reservation_write_error()
  defdelegate mark_project_storage_reservation_started(
                reservation_id,
                lease_token,
                expected_generation,
                cleanup_plan
              ),
              to: ProjectStorageReservations,
              as: :mark_started

  @doc "Commits Project-owned storage through Commercial's authoritative writer."
  @spec commit_project_storage_reservation(
          pos_integer(),
          Ecto.UUID.t(),
          pos_integer(),
          non_neg_integer(),
          (storage_reservation_receipt() -> term())
        ) ::
          {:ok, %{reservation: storage_reservation_receipt(), result: term()}}
          | storage_reservation_write_error()
  defdelegate commit_project_storage_reservation(
                reservation_id,
                lease_token,
                expected_generation,
                actual_bytes,
                owner_fun
              ),
              to: ProjectStorageReservations,
              as: :commit

  @doc "Commits restore storage without leaking Commercial persistence structs."
  @spec commit_project_snapshot_restore_storage_reservation(
          pos_integer(),
          Ecto.UUID.t(),
          pos_integer(),
          non_neg_integer(),
          (map() -> {:ok, term()} | {:error, term()}),
          (storage_reservation_receipt(), term() -> term())
        ) ::
          {:ok, %{reservation: storage_reservation_receipt(), result: term()}}
          | storage_reservation_write_error()
  defdelegate commit_project_snapshot_restore_storage_reservation(
                reservation_id,
                lease_token,
                expected_generation,
                actual_bytes,
                prelock_fun,
                owner_fun
              ),
              to: ProjectStorageReservations,
              as: :commit_restore

  @doc "Releases Project-owned reserved capacity through Commercial Billing."
  @spec release_project_storage_reservation(
          pos_integer(),
          Ecto.UUID.t(),
          pos_integer(),
          map()
        ) :: {:ok, storage_reservation_receipt()} | storage_reservation_write_error()
  defdelegate release_project_storage_reservation(
                reservation_id,
                lease_token,
                expected_generation,
                attrs
              ),
              to: ProjectStorageReservations,
              as: :release

  @doc "Validates the object namespaces represented by a neutral reservation receipt."
  @spec project_storage_reservation_object_prefixes(storage_reservation_receipt()) ::
          {:ok, map()} | {:error, term()}
  defdelegate project_storage_reservation_object_prefixes(receipt),
    to: ProjectStorageReservations,
    as: :object_prefixes
end
