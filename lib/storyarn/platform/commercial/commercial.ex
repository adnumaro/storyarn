defmodule Storyarn.Platform.Commercial do
  @moduledoc """
  Internal facade for Platform-owned commercial policy and storage accounting.

  The capability owns plans, subscriptions, entitlements, usage limits, and
  workspace-scoped storage reservations. Product contexts consume these
  contracts through `Storyarn.Platform`; this facade keeps the root boundary
  declarative without exposing Commercial's commands, queries, entities, data,
  rules, or execution modules.
  """

  alias Storyarn.Platform.Billing
  alias Storyarn.Platform.Entitlements
  alias Storyarn.Platform.ProjectStorageReservations

  @type storage_reservation_receipt :: ProjectStorageReservations.receipt()
  @type storage_reservation_write_error :: ProjectStorageReservations.write_error()

  defdelegate entitlement_limit(workspace_id, resource), to: Entitlements, as: :limit

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

  defdelegate workspace_storage_usage(workspace_id), to: Billing
  defdelegate project_snapshot_slot_usage(project_id), to: Billing

  defdelegate active_project_snapshot_reservations(snapshot_ids),
    to: Billing,
    as: :active_storage_reservations_by_snapshot

  defdelegate reserve_project_storage(attrs),
    to: ProjectStorageReservations,
    as: :reserve

  defdelegate acquire_project_snapshot_export_lease(attrs),
    to: ProjectStorageReservations,
    as: :acquire_snapshot_export_lease

  defdelegate renew_project_storage_reservation(
                reservation_id,
                lease_token,
                expected_generation
              ),
              to: ProjectStorageReservations,
              as: :renew_live

  defdelegate extend_project_storage_reservation(
                reservation_id,
                lease_token,
                expected_generation,
                target_bytes
              ),
              to: ProjectStorageReservations,
              as: :extend

  defdelegate mark_project_storage_reservation_started(
                reservation_id,
                lease_token,
                expected_generation,
                cleanup_plan
              ),
              to: ProjectStorageReservations,
              as: :mark_started

  defdelegate commit_project_storage_reservation(
                reservation_id,
                lease_token,
                expected_generation,
                actual_bytes,
                owner_fun
              ),
              to: ProjectStorageReservations,
              as: :commit

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

  defdelegate release_project_storage_reservation(
                reservation_id,
                lease_token,
                expected_generation,
                attrs
              ),
              to: ProjectStorageReservations,
              as: :release

  defdelegate project_storage_reservation_object_prefixes(receipt),
    to: ProjectStorageReservations,
    as: :object_prefixes
end
