defmodule Storyarn.Billing do
  @moduledoc """
  The Billing context.

  Handles plan limits, subscriptions, and usage tracking.
  """

  alias Storyarn.Billing.Limits
  alias Storyarn.Billing.Plan
  alias Storyarn.Billing.StorageAccounting
  alias Storyarn.Billing.SubscriptionCrud

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
  defdelegate can_create_project?(workspace), to: Limits
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

  defdelegate active_storage_reservations_by_snapshot(snapshot_ids),
    to: StorageAccounting,
    as: :active_reservations_by_snapshot

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

  @doc false
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
  defdelegate plan_for(workspace), to: SubscriptionCrud
  defdelegate plans_for_workspace_ids(workspace_ids), to: SubscriptionCrud
  defdelegate create_subscription(workspace), to: SubscriptionCrud
  defdelegate create_subscription(workspace, plan), to: SubscriptionCrud
  defdelegate get_subscription(workspace_id), to: SubscriptionCrud
  defdelegate update_plan(subscription, new_plan), to: SubscriptionCrud
end
