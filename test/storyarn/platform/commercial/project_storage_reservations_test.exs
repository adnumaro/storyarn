defmodule Storyarn.Platform.ProjectStorageReservationsTest do
  use Storyarn.DataCase, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.VersioningFixtures

  alias Storyarn.Platform
  alias Storyarn.Platform.Billing.StorageReservation
  alias Storyarn.Projects.Persistence.StorageReservationRecord
  alias Storyarn.Projects.PlatformStorageReservations
  alias Storyarn.Repo

  test "public writes return neutral receipts and the Projects ACL returns its local read model" do
    user = user_fixture()
    project = user |> project_fixture() |> Repo.preload(:workspace)
    snapshot = pending_project_snapshot_fixture(project)

    attrs = %{
      workspace_id: project.workspace_id,
      project_id: project.id,
      project_snapshot_id: snapshot.id,
      idempotency_key: "neutral-receipt:#{snapshot.id}",
      kind: "snapshot_build",
      reserved_bytes: 100
    }

    assert {:ok, receipt} = Platform.reserve_project_storage(attrs)
    assert is_map(receipt)
    refute Map.has_key?(receipt, :__struct__)
    refute Map.has_key?(receipt, :__meta__)
    assert receipt.project_snapshot_id_snapshot == snapshot.id

    assert {:ok, %StorageReservationRecord{} = local_record} =
             PlatformStorageReservations.reserve(attrs)

    assert local_record.id == receipt.id
    assert local_record.lease_token == receipt.lease_token
    assert %StorageReservation{} = Repo.get!(StorageReservation, local_record.id)

    assert {:ok, %StorageReservationRecord{status: "released"}} =
             PlatformStorageReservations.release(
               local_record.id,
               local_record.lease_token,
               local_record.generation,
               %{
                 reason: "neutral receipt contract test",
                 cleanup_status: "not_required",
                 cleanup_proof: %{
                   type: "storage_not_started",
                   storage_namespace: local_record.storage_namespace
                 }
               }
             )
  end
end
