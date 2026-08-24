defmodule Storyarn.Projects.Versioning.ProjectSnapshotLeasePolicyTest do
  use ExUnit.Case, async: false

  alias Storyarn.Projects.Versioning
  alias Storyarn.Projects.Versioning.ProjectSnapshotLeasePolicy

  setup do
    original = Application.fetch_env!(:storyarn, ProjectSnapshotLeasePolicy)
    on_exit(fn -> Application.put_env(:storyarn, ProjectSnapshotLeasePolicy, original) end)
    %{original: original}
  end

  test "derives the export lease from the signed grant, transfer, and handoff windows", %{
    original: original
  } do
    Application.put_env(
      :storyarn,
      ProjectSnapshotLeasePolicy,
      original
      |> Keyword.put(:download_signed_url_ttl_seconds, 10)
      |> Keyword.put(:download_max_transfer_seconds, 20)
      |> Keyword.put(:download_lease_safety_seconds, 3)
    )

    assert Versioning.project_snapshot_download_signed_url_ttl_seconds() == 10
    assert Versioning.project_snapshot_download_export_lease_ttl_seconds() == 33
  end

  test "rejects a build lease that cannot survive three heartbeat intervals", %{
    original: original
  } do
    Application.put_env(
      :storyarn,
      ProjectSnapshotLeasePolicy,
      original
      |> Keyword.put(:build_heartbeat_interval_seconds, 60)
      |> Keyword.put(:build_lease_ttl_seconds, 120)
    )

    assert_raise ArgumentError, ~r/must cover at least three heartbeat intervals/, fn ->
      ProjectSnapshotLeasePolicy.build_lease_ttl_seconds()
    end
  end

  test "rejects a signed URL TTL outside the private storage grant contract", %{
    original: original
  } do
    Application.put_env(
      :storyarn,
      ProjectSnapshotLeasePolicy,
      Keyword.put(original, :download_signed_url_ttl_seconds, 301)
    )

    assert_raise ArgumentError, ~r/signed URL TTL must be at most 300s/, fn ->
      ProjectSnapshotLeasePolicy.download_signed_url_ttl_seconds()
    end
  end
end
