defmodule Storyarn.Commercial.Billing do
  @moduledoc """
  Internal Billing capability within Commercial.

  Handles plan limits, subscriptions, and usage tracking.
  """

  alias Ecto.Changeset
  alias Storyarn.Commercial.Billing.Limits
  alias Storyarn.Commercial.Billing.Plan
  alias Storyarn.Commercial.Billing.StorageAccounting
  alias Storyarn.Commercial.Billing.StorageLeasePolicy
  alias Storyarn.Commercial.Billing.Subscription
  alias Storyarn.Commercial.Billing.SubscriptionCrud
  alias Storyarn.Commercial.Queries.Subscriptions, as: SubscriptionQueries

  @typedoc "Scalar lock context passed to the Project snapshot restore prelock callback."
  @type snapshot_restore_prelock_context :: StorageAccounting.snapshot_restore_prelock_context()

  # Plan queries
  defdelegate get_plan(plan_key), to: Plan, as: :get
  defdelegate list_plans(), to: Plan, as: :all
  defdelegate default_plan(), to: Plan
  defdelegate plan_limit(plan_key, resource), to: Plan, as: :limit
  defdelegate plan_retention_hours(plan_key), to: Plan, as: :retention_hours

  # Usage counting (internal, exposed for testing)
  defdelegate count_project_items(project_id), to: Limits
  defdelegate count_unique_workspace_users(workspace_id), to: Limits

  # Limit checks
  defdelegate can_create_workspace?(user), to: Limits
  defdelegate can_receive_workspace?(user), to: Limits
  defdelegate can_create_project?(workspace), to: Limits
  defdelegate can_publish_reserved_project?(workspace), to: Limits
  defdelegate can_create_project_template?(source_project), to: Limits
  defdelegate can_create_project_template_version?(template), to: Limits
  defdelegate can_invite_member?(workspace_or_project), to: Limits
  defdelegate can_invite_member?(workspace_or_project, email), to: Limits
  defdelegate can_accept_member?(workspace_or_project, email), to: Limits
  defdelegate can_upload_asset?(workspace, file_size), to: Limits
  defdelegate can_upload_asset_for_project?(project, file_size), to: Limits
  defdelegate can_create_item?(project), to: Limits
  defdelegate can_create_items?(project, count), to: Limits
  defdelegate can_create_named_version?(project_id, workspace_id), to: Limits
  defdelegate project_usage(project_id, workspace_id), to: Limits
  defdelegate project_limits_usage(project), to: Limits
  defdelegate usage(workspace), to: Limits

  # Authoritative storage accounting and reservations
  defdelegate workspace_storage_usage(workspace_id), to: StorageAccounting, as: :workspace_usage
  defdelegate project_storage_usage(project_id), to: StorageAccounting, as: :project_usage
  defdelegate project_snapshot_slot_usage(project_id), to: StorageAccounting

  defdelegate snapshot_download_signed_url_ttl_seconds(),
    to: StorageLeasePolicy,
    as: :download_signed_url_ttl_seconds

  defdelegate snapshot_download_max_transfer_seconds(),
    to: StorageLeasePolicy,
    as: :download_max_transfer_seconds

  defdelegate snapshot_download_export_lease_ttl_seconds(),
    to: StorageLeasePolicy,
    as: :download_export_lease_ttl_seconds

  defdelegate snapshot_build_heartbeat_interval_ms(),
    to: StorageLeasePolicy,
    as: :build_heartbeat_interval_ms

  defdelegate snapshot_build_lease_ttl_seconds(),
    to: StorageLeasePolicy,
    as: :build_lease_ttl_seconds

  defdelegate snapshot_export_lease_retention_seconds(),
    to: StorageLeasePolicy,
    as: :export_lease_retention_seconds

  defdelegate active_storage_reservations_by_snapshot(snapshot_ids),
    to: StorageAccounting,
    as: :active_reservations_by_snapshot

  defdelegate subscribe_project_snapshot_export_leases(project_id), to: StorageAccounting

  defdelegate reserve_storage(attrs), to: StorageAccounting, as: :reserve

  defdelegate acquire_snapshot_export_lease(attrs), to: StorageAccounting

  @doc false
  defdelegate renew_live_storage_reservation(reservation_id, lease_token, expected_generation),
    to: StorageAccounting

  defdelegate extend_storage_reservation(reservation_id, lease_token, expected_generation, target_bytes),
    to: StorageAccounting,
    as: :extend_to

  defdelegate mark_storage_reservation_started(reservation_id, lease_token, expected_generation, cleanup_plan),
    to: StorageAccounting,
    as: :mark_storage_started

  defdelegate commit_storage_reservation(reservation_id, lease_token, expected_generation, actual_bytes, owner_fun),
    to: StorageAccounting,
    as: :commit

  @doc """
  Commits a restore reservation while preserving Billing's workspace-first lock order.

  The prelock callback receives only the stable scalar
  `snapshot_restore_prelock_context/0`; Billing persistence structs never cross
  this public boundary.
  """
  @spec commit_project_snapshot_restore_reservation(
          pos_integer(),
          Ecto.UUID.t(),
          pos_integer(),
          non_neg_integer(),
          (snapshot_restore_prelock_context() -> {:ok, term()} | {:error, term()}),
          (Storyarn.Commercial.Billing.StorageReservation.t(), term() -> term())
        ) :: {:ok, map()} | {:error, term()}
  defdelegate commit_project_snapshot_restore_reservation(
                reservation_id,
                lease_token,
                expected_generation,
                actual_bytes,
                prelock_fun,
                owner_fun
              ),
              to: StorageAccounting

  defdelegate release_storage_reservation(reservation_id, lease_token, expected_generation, attrs),
    to: StorageAccounting,
    as: :release

  defdelegate recover_expired_snapshot_export_leases(now, opts \\ []),
    to: StorageAccounting

  @doc false
  defdelegate settle_expired_snapshot_export_leases_locked(snapshot, workspace_id),
    to: StorageAccounting

  defdelegate purge_released_snapshot_export_leases(cutoff, opts \\ []),
    to: StorageAccounting

  defdelegate storage_reservation_object_prefixes(reservation),
    to: StorageAccounting,
    as: :operation_object_prefixes

  defdelegate with_storage_accounting_lock(workspace_id, fun, opts \\ []),
    to: StorageAccounting,
    as: :with_workspace_lock

  defdelegate transact_with_workspace_lock(workspace_id, fun, opts \\ []),
    to: StorageAccounting

  defdelegate workspace_lock_held?(workspace_id), to: StorageAccounting

  defdelegate snapshot_storage_commit_context?(snapshot_id, kind),
    to: StorageAccounting,
    as: :snapshot_commit_context?

  defdelegate emit_provider_storage_footprint(workspace_id, measurements),
    to: StorageAccounting,
    as: :emit_provider_footprint

  # Subscription operations
  defdelegate plan_for(workspace), to: SubscriptionQueries
  defdelegate plans_for_workspace_ids(workspace_ids), to: SubscriptionQueries

  @doc false
  @spec create_subscription(map()) ::
          {:ok, map()}
          | {:error, %{required(:code) => atom(), required(:field_errors) => map()}}
  def create_subscription(workspace) do
    case SubscriptionCrud.create_subscription(workspace) do
      {:ok, %Subscription{} = subscription} ->
        {:ok,
         %{
           id: subscription.id,
           workspace_id: subscription.workspace_id,
           plan: subscription.plan,
           status: subscription.status
         }}

      {:error, %Changeset{} = changeset} ->
        {:error, subscription_creation_error(changeset)}

      {:error, _reason} ->
        {:error, %{code: :subscription_creation_failed, field_errors: %{}}}
    end
  end

  defp subscription_creation_error(%Changeset{errors: errors}) do
    %{
      code:
        if(Enum.any?(errors, &unique_workspace_constraint?/1),
          do: :subscription_already_exists,
          else: :invalid_subscription
        ),
      field_errors: normalize_subscription_field_errors(errors)
    }
  end

  defp normalize_subscription_field_errors(errors) do
    Enum.reduce(errors, %{}, fn {field, {_message, metadata}}, acc ->
      Map.update(acc, field, [subscription_field_error(metadata)], fn field_errors ->
        Enum.uniq(field_errors ++ [subscription_field_error(metadata)])
      end)
    end)
  end

  defp subscription_field_error(metadata) do
    case {Keyword.get(metadata, :constraint), Keyword.get(metadata, :validation)} do
      {:unique, _validation} -> :already_exists
      {_constraint, :required} -> :required
      {_constraint, _validation} -> :invalid
    end
  end

  defp unique_workspace_constraint?({:workspace_id, {_message, metadata}}),
    do: Keyword.get(metadata, :constraint) == :unique

  defp unique_workspace_constraint?(_error), do: false

  defdelegate create_subscription(workspace, plan), to: SubscriptionCrud
  defdelegate get_subscription(workspace_id), to: SubscriptionQueries
  defdelegate update_plan(subscription, new_plan), to: SubscriptionCrud
end
