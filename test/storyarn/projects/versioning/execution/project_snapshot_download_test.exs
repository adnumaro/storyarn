defmodule Storyarn.Projects.Versioning.ProjectSnapshotDownloadTest do
  use Storyarn.DataCase, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Commercial
  alias Storyarn.Commercial.Billing.StorageReservation
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Projects
  alias Storyarn.Projects.Versioning
  alias Storyarn.Workers.BuildProjectSnapshotWorker

  test "coalesces overlapping grants onto one renewed zero-byte lease" do
    user = user_fixture()
    project = project_fixture(user)
    snapshot = build_ready_snapshot(project, user)
    Commercial.subscribe_project_snapshot_export_leases(project.id)
    attach_lease_telemetry()

    assert :grant_issued =
             Versioning.with_project_snapshot_archive(project, snapshot.id, fn delivery ->
               assert delivery.snapshot.id == snapshot.id
               assert delivery.storage_key == snapshot.archive_storage_key
               assert delivery.size_bytes == snapshot.archive_size_bytes
               assert delivery.checksum == snapshot.archive_checksum
               {:keep_lease, :grant_issued}
             end)

    assert %StorageReservation{
             kind: "snapshot_export",
             status: "active",
             reserved_bytes: 0,
             storage_started_at: nil,
             cleanup_status: nil
           } = first_lease = lease_for(snapshot)

    assert DateTime.diff(first_lease.expires_at, first_lease.accounting_measured_at, :second) ==
             Versioning.project_snapshot_download_export_lease_ttl_seconds()

    assert_receive {:commercial_snapshot_export_lease_state_invalidated, snapshot_id}
    assert snapshot_id == snapshot.id

    assert_receive {:snapshot_download_lease, %{count: 1},
                    %{outcome: :created, project_id: project_id, snapshot_id: snapshot_id}}

    assert project_id == project.id
    assert snapshot_id == snapshot.id

    assert :second_grant_issued =
             Versioning.with_project_snapshot_archive(project, snapshot.id, fn _delivery ->
               {:keep_lease, :second_grant_issued}
             end)

    second_lease = lease_for(snapshot)
    assert second_lease.id == first_lease.id
    assert second_lease.generation == first_lease.generation + 1
    assert DateTime.after?(second_lease.expires_at, first_lease.expires_at)

    assert 1 ==
             Repo.aggregate(
               from(reservation in StorageReservation,
                 where:
                   reservation.project_snapshot_id_snapshot == ^snapshot.id and
                     reservation.kind == "snapshot_export" and reservation.status == "active"
               ),
               :count
             )

    assert_receive {:commercial_snapshot_export_lease_state_invalidated, snapshot_id}
    assert snapshot_id == snapshot.id

    assert_receive {:snapshot_download_lease, %{count: 1},
                    %{outcome: :coalesced, project_id: project_id, snapshot_id: snapshot_id}}

    assert project_id == project.id
    assert snapshot_id == snapshot.id
  end

  test "keeps the shared lease after local delivery" do
    user = user_fixture()
    project = project_fixture(user)
    snapshot = build_ready_snapshot(project, user)
    Commercial.subscribe_project_snapshot_export_leases(project.id)

    assert :delivered =
             Versioning.with_project_snapshot_archive(project, snapshot.id, fn _delivery ->
               {:keep_lease, :delivered}
             end)

    assert %StorageReservation{
             status: "active",
             reserved_bytes: 0,
             storage_started_at: nil,
             cleanup_status: nil
           } = lease_for(snapshot)

    assert_receive {:commercial_snapshot_export_lease_state_invalidated, snapshot_id}
    assert snapshot_id == snapshot.id
    refute_receive {:commercial_snapshot_export_lease_state_invalidated, _snapshot_id}
  end

  test "retains the shared lease when delivery raises" do
    user = user_fixture()
    project = project_fixture(user)
    snapshot = build_ready_snapshot(project, user)

    assert_raise RuntimeError, "simulated delivery failure", fn ->
      Versioning.with_project_snapshot_archive(project, snapshot.id, fn _delivery ->
        raise "simulated delivery failure"
      end)
    end

    assert %StorageReservation{status: "active", cleanup_status: nil} =
             lease_for(snapshot)
  end

  test "fails closed and retains when the callback omits its lease decision" do
    user = user_fixture()
    project = project_fixture(user)
    snapshot = build_ready_snapshot(project, user)

    assert {:error, :snapshot_export_unavailable} =
             Versioning.with_project_snapshot_archive(project, snapshot.id, fn _delivery ->
               :ambiguous_result
             end)

    assert %StorageReservation{status: "active"} = lease_for(snapshot)
  end

  test "revalidates an authorized project under the storage lock before granting" do
    user = user_fixture()
    project = project_fixture(user)
    snapshot = build_ready_snapshot(project, user)

    project
    |> Ecto.Changeset.change(deleted_at: TimeHelpers.now())
    |> Repo.update!()

    assert {:error, :snapshot_export_unavailable} =
             Versioning.with_project_snapshot_archive(project, snapshot.id, fn _delivery ->
               flunk("delivery must not start for a concurrently deleted project")
             end)

    refute Repo.get_by(StorageReservation,
             project_snapshot_id_snapshot: snapshot.id,
             kind: "snapshot_export"
           )
  end

  test "the public capability reauthorizes under the storage lock before creating a grant" do
    user = user_fixture()
    project = project_fixture(user)
    snapshot = build_ready_snapshot(project, user)

    project
    |> Ecto.Changeset.change(deleted_at: TimeHelpers.now())
    |> Repo.update!()

    assert {:error, :unauthorized} =
             Projects.with_authorized_project_snapshot_download(
               user_scope_fixture(user),
               project.id,
               snapshot.id,
               fn _delivery -> flunk("delivery must not start for a deleted project") end
             )

    refute Repo.get_by(StorageReservation,
             project_snapshot_id_snapshot: snapshot.id,
             kind: "snapshot_export"
           )
  end

  test "the public capability never invokes the callback for an editor" do
    owner = user_fixture()
    editor = user_fixture()
    project = project_fixture(owner)
    snapshot = build_ready_snapshot(project, owner)
    membership_fixture(project, editor, "editor")

    assert {:error, :unauthorized} =
             Projects.with_authorized_project_snapshot_download(
               user_scope_fixture(editor),
               project.id,
               snapshot.id,
               fn _delivery -> flunk("delivery must remain owner-only") end
             )

    refute Repo.get_by(StorageReservation,
             project_snapshot_id_snapshot: snapshot.id,
             kind: "snapshot_export"
           )
  end

  test "a failed coalesced request cannot release a previous grant" do
    user = user_fixture()
    project = project_fixture(user)
    snapshot = build_ready_snapshot(project, user)

    assert :grant_issued =
             Versioning.with_project_snapshot_archive(project, snapshot.id, fn _delivery ->
               {:keep_lease, :grant_issued}
             end)

    first_lease = lease_for(snapshot)

    assert {:error, :provider_unavailable} =
             Versioning.with_project_snapshot_archive(project, snapshot.id, fn _delivery ->
               {:keep_lease, {:error, :provider_unavailable}}
             end)

    assert %StorageReservation{id: lease_id, status: "active", generation: generation} =
             lease_for(snapshot)

    assert lease_id == first_lease.id
    assert generation == first_lease.generation + 1
  end

  defp lease_for(snapshot) do
    Repo.get_by!(StorageReservation,
      project_snapshot_id_snapshot: snapshot.id,
      kind: "snapshot_export"
    )
  end

  defp attach_lease_telemetry do
    handler_id = "snapshot-download-lease-#{System.unique_integer([:positive])}"
    parent = self()

    :ok =
      :telemetry.attach(
        handler_id,
        [:storyarn, :snapshot, :download, :lease],
        fn _event, measurements, metadata, pid ->
          send(pid, {:snapshot_download_lease, measurements, metadata})
        end,
        parent
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end

  defp build_ready_snapshot(project, user) do
    assert {:ok, requested} =
             Versioning.request_full_project_snapshot(user_scope_fixture(user), project, %{
               idempotency_key: Ecto.UUID.generate()
             })

    job =
      requested.build_job_id
      |> then(&Repo.get!(Oban.Job, &1))
      |> Ecto.Changeset.change(
        state: "executing",
        attempt: 1,
        attempted_at: %{TimeHelpers.now() | microsecond: {0, 6}}
      )
      |> Repo.update!()

    assert :ok = BuildProjectSnapshotWorker.perform(job)
    Versioning.get_project_snapshot(project.id, requested.id)
  end
end
