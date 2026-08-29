defmodule Storyarn.Projects.Versioning.ProjectSnapshotLeasePolicy do
  @moduledoc """
  Compatibility boundary for the Commercial-owned storage lease policy.

  Snapshot workflows keep their existing vocabulary while reservation and
  capacity policy has one owner in Commercial.
  """

  alias Storyarn.Commercial

  defdelegate download_signed_url_ttl_seconds(), to: Commercial, as: :snapshot_download_signed_url_ttl_seconds
  defdelegate download_max_transfer_seconds(), to: Commercial, as: :snapshot_download_max_transfer_seconds
  defdelegate download_export_lease_ttl_seconds(), to: Commercial, as: :snapshot_download_export_lease_ttl_seconds
  defdelegate build_heartbeat_interval_ms(), to: Commercial, as: :snapshot_build_heartbeat_interval_ms
  defdelegate build_lease_ttl_seconds(), to: Commercial, as: :snapshot_build_lease_ttl_seconds
  defdelegate export_lease_retention_seconds(), to: Commercial, as: :snapshot_export_lease_retention_seconds
end
