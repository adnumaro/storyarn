defmodule Storyarn.Commercial.Billing.StorageProtocolTest do
  use ExUnit.Case, async: true

  alias Storyarn.Commercial.Billing.Persistence.ProjectRecord
  alias Storyarn.Commercial.Billing.Persistence.ProjectSnapshotRecord
  alias Storyarn.Commercial.Billing.Persistence.SnapshotObjectPublicationClaimRecord
  alias Storyarn.Commercial.Billing.Persistence.WorkspaceSnapshotImportRecord
  alias Storyarn.Commercial.Billing.StorageProtocol
  alias Storyarn.Commercial.Billing.StorageReservation
  alias Storyarn.Projects.Assets.Storage
  alias Storyarn.Projects.Assets.StorageKeyLock
  alias Storyarn.Projects.Versioning.SnapshotArchiveStorage
  alias Storyarn.Projects.Versioning.SnapshotObjectFormat
  alias Storyarn.Projects.Versioning.SnapshotObjectPublicationClaim
  alias Storyarn.Projects.Versioning.WorkspaceSnapshotImport

  test "reservation associations stay inside the Commercial persistence model" do
    assert StorageReservation.__schema__(:association, :project).related == ProjectRecord
    assert StorageReservation.__schema__(:association, :project_snapshot).related == ProjectSnapshotRecord
  end

  test "the duplicated snapshot object contract remains compatible with the Project writer" do
    project_id = 42
    token = "abcdefghijklmnop"
    ready_prefix = "projects/42/snapshots/archives/v2/ready/#{token}"

    assert StorageProtocol.staging_prefix(project_id, token) == SnapshotArchiveStorage.staging_prefix(project_id, token)
    assert StorageProtocol.archive_key(ready_prefix) == SnapshotArchiveStorage.archive_key(ready_prefix)
    assert StorageProtocol.manifest_key(ready_prefix) == SnapshotArchiveStorage.manifest_key(ready_prefix)

    assert StorageProtocol.ready_prefix_for_project?(project_id, ready_prefix) ==
             SnapshotArchiveStorage.ready_prefix_for_project?(project_id, ready_prefix)

    assert StorageProtocol.ready_prefix_token(project_id, ready_prefix) == {:ok, token}
    assert StorageProtocol.ready_prefix_token(project_id + 1, ready_prefix) == :error
    assert StorageProtocol.ready_prefix_token(project_id, ready_prefix <> "/snapshot.zip") == :error
    assert StorageProtocol.ready_prefix_token(project_id, String.replace(ready_prefix, token, "short")) == :error
    assert StorageProtocol.snapshot_object_key?(ready_prefix, StorageProtocol.archive_key(ready_prefix))
    assert StorageProtocol.snapshot_object_key?(ready_prefix, StorageProtocol.manifest_key(ready_prefix))
    refute StorageProtocol.snapshot_object_key?(ready_prefix, ready_prefix <> "/other.json")

    assert StorageProtocol.hard_limits() == SnapshotObjectFormat.hard_limits()
  end

  test "snapshot reservations validate ready prefixes through the persisted protocol" do
    lease_token = Ecto.UUID.generate()

    attrs = %{
      workspace_id: 7,
      project_id: 42,
      project_snapshot_id: 99,
      idempotency_key: "snapshot-protocol",
      kind: "snapshot_build",
      storage_namespace: "projects/42/storage-reservations/v1/snapshot-build/#{lease_token}",
      cleanup_object_prefix: "projects/42/snapshots/archives/v2/ready/abcdefghijklmnop",
      reserved_bytes: 1,
      lease_token: lease_token,
      generation: 1,
      expires_at: ~U[2026-01-01 00:01:00Z],
      accounting_version: 1,
      accounting_measured_at: ~U[2026-01-01 00:00:00Z]
    }

    assert %Ecto.Changeset{valid?: true} = StorageReservation.create_changeset(%StorageReservation{}, attrs)

    mismatched_project =
      StorageReservation.create_changeset(
        %StorageReservation{},
        %{attrs | cleanup_object_prefix: "projects/43/snapshots/archives/v2/ready/abcdefghijklmnop"}
      )

    refute mismatched_project.valid?
    assert {"has invalid format", _metadata} = mismatched_project.errors[:cleanup_object_prefix]
  end

  test "the persisted active import states remain compatible with the Project writer" do
    assert WorkspaceSnapshotImportRecord.active_statuses() == WorkspaceSnapshotImport.active_statuses()
  end

  test "cleanup key validation remains compatible with Project storage" do
    corpus = [
      "projects/42/assets/#{Ecto.UUID.generate()}/portrait.png",
      "projects/42/blobs/#{String.duplicate("a", 64)}.png",
      "projects//invalid",
      "projects/42/../invalid",
      "",
      <<0>>
    ]

    for key <- corpus do
      assert StorageProtocol.canonical_key?(key) == Storage.canonical_key?(key)
      assert StorageProtocol.project_blob_identity(key) == StorageKeyLock.project_blob_identity(key)
    end
  end

  test "publication inventory digest remains compatible with the Project writer" do
    snapshot = %{
      format_version: 2,
      mode: "full",
      object_prefix: "projects/42/snapshots/archives/v2/ready/abcdefghijklmnop",
      archive_storage_key: "projects/42/snapshots/archives/v2/ready/abcdefghijklmnop/snapshot.zip",
      archive_size_bytes: 100,
      manifest_storage_key: "projects/42/snapshots/archives/v2/ready/abcdefghijklmnop/manifest.json",
      manifest_size_bytes: 20,
      manifest_checksum: String.duplicate("a", 64),
      project_size_bytes: 80,
      project_checksum: String.duplicate("b", 64),
      total_size_bytes: 120,
      accounted_size_bytes: 120,
      asset_blob_size_bytes: 40,
      accounting_version: 1,
      object_count: 3,
      asset_count: 2,
      blob_count: 1,
      capture_digest: String.duplicate("c", 64)
    }

    assert SnapshotObjectPublicationClaimRecord.inventory_digest(snapshot) ==
             SnapshotObjectPublicationClaim.inventory_digest(snapshot)

    string_snapshot = Map.new(snapshot, fn {field, value} -> {Atom.to_string(field), value} end)

    assert SnapshotObjectPublicationClaimRecord.inventory_digest(string_snapshot) ==
             SnapshotObjectPublicationClaim.inventory_digest(string_snapshot)

    for module <- [SnapshotObjectPublicationClaimRecord, SnapshotObjectPublicationClaim] do
      assert_raise ArgumentError, "unsupported snapshot claim format: 3", fn ->
        module.inventory_digest(%{format_version: 3})
      end
    end
  end
end
