defmodule Storyarn.Platform do
  @moduledoc """
  Public facade for platform-wide capabilities and reaction policy.

  Product contexts own the business facts they emit. Platform decides which
  cross-cutting reactions those facts trigger. The current reaction is
  best-effort product analytics; durable notifications and email delivery must
  enter through persisted, idempotent workflows rather than this synchronous
  path.
  """

  alias Storyarn.Platform.Billing
  alias Storyarn.Platform.Entitlements
  alias Storyarn.Platform.EventTracker
  alias Storyarn.Platform.Notifications
  alias Storyarn.Platform.ProductMetrics.Taxonomy
  alias Storyarn.Platform.ProjectStorageReservations
  alias Storyarn.Workers.DeliverInvitationWorker

  @type notification_delivery_outcome :: Notifications.delivery_outcome()
  @type storage_reservation_receipt :: ProjectStorageReservations.receipt()
  @type storage_reservation_write_error :: ProjectStorageReservations.write_error()

  @doc "Routes a context-owned event through Platform reaction policy."
  @spec react_to_event(term(), atom(), atom(), map()) :: :ok
  defdelegate react_to_event(scope_or_user, source, event_type, payload),
    to: EventTracker,
    as: :react

  @doc "Returns the current scalar entitlement for one workspace resource."
  @spec entitlement_limit(pos_integer(), atom()) :: non_neg_integer() | nil
  defdelegate entitlement_limit(workspace_id, resource), to: Entitlements, as: :limit

  # Commercial policy and usage contracts. Consumers enter through Platform;
  # Billing keeps the implementation and the current shared-database lock
  # semantics until persistence ownership is migrated separately.
  defdelegate can_create_workspace?(user), to: Billing
  defdelegate can_create_project?(workspace), to: Billing
  defdelegate can_publish_reserved_project?(workspace), to: Billing
  defdelegate can_create_project_template?(source_project), to: Billing
  defdelegate can_create_project_template_version?(template), to: Billing
  defdelegate can_invite_member?(workspace_or_project, email), to: Billing
  defdelegate can_accept_member?(workspace_or_project, email), to: Billing
  defdelegate can_upload_asset?(workspace, file_size), to: Billing
  defdelegate can_upload_asset_for_project?(project, file_size), to: Billing
  defdelegate project_usage(project_id, workspace_id), to: Billing
  defdelegate project_limits_usage(project), to: Billing
  defdelegate plans_for_workspace_ids(workspace_ids), to: Billing
  defdelegate plan_retention_hours(plan_key), to: Billing
  defdelegate create_subscription(workspace), to: Billing

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

  @doc "Returns Platform-accounted storage usage for one workspace identity."
  @spec workspace_storage_usage(pos_integer()) :: map()
  defdelegate workspace_storage_usage(workspace_id), to: Billing

  @doc "Returns stored snapshots plus active build reservations for one Project."
  @spec project_snapshot_slot_usage(pos_integer()) :: non_neg_integer()
  defdelegate project_snapshot_slot_usage(project_id), to: Billing

  @doc "Returns neutral active-reservation totals keyed by Project snapshot id."
  @spec active_project_snapshot_reservations([pos_integer()]) :: map()
  defdelegate active_project_snapshot_reservations(snapshot_ids),
    to: Billing,
    as: :active_storage_reservations_by_snapshot

  @doc "Reserves Platform-owned storage and returns a transport-neutral receipt."
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
  defdelegate renew_project_storage_reservation(reservation_id, lease_token, expected_generation),
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

  @doc "Commits Project-owned storage through Platform's authoritative writer."
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

  @doc "Commits restore storage without leaking Platform persistence structs."
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

  @doc "Releases Project-owned reserved capacity through Platform Billing."
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

  @doc "Returns the stable project categories collected for product metrics."
  @spec product_metric_project_types() :: [String.t()]
  defdelegate product_metric_project_types(), to: Taxonomy, as: :project_types

  @doc "Returns the stable project subtype taxonomy collected for product metrics."
  @spec product_metric_project_subtypes() :: %{String.t() => [String.t()]}
  defdelegate product_metric_project_subtypes(), to: Taxonomy, as: :project_subtypes

  @doc "Returns the product metric subtypes available for one project category."
  @spec product_metric_project_subtypes(String.t()) :: [String.t()]
  defdelegate product_metric_project_subtypes(project_type),
    to: Taxonomy,
    as: :project_subtypes

  @doc "Returns the complete project classification options for presentation adapters."
  @spec product_metric_project_options() :: %{
          project_types: [String.t()],
          project_subtypes: %{String.t() => [String.t()]}
        }
  defdelegate product_metric_project_options(), to: Taxonomy, as: :project_options

  @doc "Checks whether a project category belongs to the product metric taxonomy."
  @spec known_product_metric_project_type?(term()) :: boolean()
  defdelegate known_product_metric_project_type?(project_type),
    to: Taxonomy,
    as: :known_project_type?

  @doc "Checks whether a project subtype belongs to its product metric category."
  @spec known_product_metric_project_subtype?(term(), term()) :: boolean()
  defdelegate known_product_metric_project_subtype?(project_type, project_subtype),
    to: Taxonomy,
    as: :known_project_subtype?

  @doc "Persists a context-owned content activity through Platform notification policy."
  @spec deliver_content_activity(term(), pos_integer(), atom(), String.t(), map()) ::
          {:ok, term()} | {:error, term()}
  defdelegate deliver_content_activity(scope, project_id, action, entity_type, entity),
    to: Notifications,
    as: :deliver_content_activity_by_project_id

  @doc "Persists content activity from scalar context-owned identities."
  @spec deliver_content_activity_by_ids(pos_integer(), pos_integer(), atom(), String.t(), map()) ::
          {:ok, term()} | {:error, term()}
  defdelegate deliver_content_activity_by_ids(actor_id, project_id, action, entity_type, entity),
    to: Notifications

  @doc "Persists a requester-only async outcome from scalar context-owned identities."
  @spec deliver_async_result(integer() | nil, pos_integer(), map()) ::
          {:ok, notification_delivery_outcome()} | {:error, term()}
  defdelegate deliver_async_result(requested_by_id, project_id, attrs),
    to: Notifications,
    as: :deliver_async_result_by_ids

  @doc "Persists a requester-only async outcome from an authorized consumer scope."
  @spec deliver_scoped_async_result(term(), term(), map()) ::
          {:ok, notification_delivery_outcome()} | {:error, term()}
  defdelegate deliver_scoped_async_result(recipient_scope, project, attrs),
    to: Notifications,
    as: :deliver_async_result

  @doc "Lists the current recipient's durable notifications."
  @spec list_notifications(term(), keyword()) :: [term()]
  defdelegate list_notifications(scope, opts \\ []), to: Notifications

  @doc "Counts unread durable notifications for the current recipient."
  @spec unread_notification_count(term()) :: non_neg_integer()
  defdelegate unread_notification_count(scope), to: Notifications, as: :unread_count

  @doc "Marks one recipient-owned notification as read."
  @spec mark_notification_read(term(), integer()) :: {:ok, term()} | {:error, :not_found}
  defdelegate mark_notification_read(scope, notification_id), to: Notifications, as: :mark_read

  @doc "Marks all recipient-owned notifications as read."
  @spec mark_all_notifications_read(term()) :: {:ok, non_neg_integer()}
  defdelegate mark_all_notifications_read(scope), to: Notifications, as: :mark_all_read

  @doc "Subscribes a recipient scope to its notification signal topic."
  @spec subscribe_notifications(term()) :: :ok | {:error, :not_found}
  defdelegate subscribe_notifications(scope), to: Notifications, as: :subscribe

  @doc "Publishes the committed notification outcome to connected recipients."
  @spec publish_notification_delivery(notification_delivery_outcome() | [notification_delivery_outcome()]) :: :ok
  defdelegate publish_notification_delivery(outcome), to: Notifications, as: :publish_committed

  @doc "Persists one already-encrypted invitation delivery request."
  @spec enqueue_invitation_delivery(map()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue_invitation_delivery(attrs) when is_map(attrs) do
    attrs
    |> DeliverInvitationWorker.new()
    |> Oban.insert()
  end
end
