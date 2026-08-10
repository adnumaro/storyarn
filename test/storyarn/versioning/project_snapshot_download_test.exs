defmodule Storyarn.Versioning.ProjectSnapshotDownloadTest do
  use Storyarn.DataCase, async: false

  import ExUnit.CaptureLog
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Billing.StorageReservation
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.SnapshotReadSwitchStorage
  alias Storyarn.Versioning
  alias Storyarn.Workers.BuildProjectSnapshotWorker

  test "normalizes an unexpected preflight exception without invoking the delivery callback" do
    user = user_fixture()
    project = project_fixture(user)
    snapshot = build_ready_snapshot(project, user)
    install_raising_storage()

    log =
      capture_log(fn ->
        assert {:error, :snapshot_export_unavailable} =
                 Versioning.with_project_snapshot_zip(project.id, snapshot.id, fn _plan ->
                   flunk("delivery must not start after a failed preflight")
                 end)
      end)

    assert log =~ "Snapshot ZIP preflight failed unexpectedly"
    refute log =~ "provider-secret"

    assert %StorageReservation{
             status: "released",
             reserved_bytes: 0,
             storage_started_at: nil,
             cleanup_status: "not_required"
           } =
             Repo.get_by!(StorageReservation,
               project_snapshot_id_snapshot: snapshot.id,
               kind: "snapshot_export"
             )
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

  defp install_raising_storage do
    original_storage = Application.fetch_env!(:storyarn, :storage)
    {:ok, _pid} = SnapshotReadSwitchStorage.start_link(%{})

    SnapshotReadSwitchStorage.observe_io(fn
      :stat, _key -> raise "provider-secret"
      _operation, _key -> :ok
    end)

    Application.put_env(
      :storyarn,
      :storage,
      Keyword.put(original_storage, :adapter, SnapshotReadSwitchStorage)
    )

    on_exit(fn ->
      Application.put_env(:storyarn, :storage, original_storage)

      if Process.whereis(SnapshotReadSwitchStorage) do
        Agent.stop(SnapshotReadSwitchStorage)
      end
    end)
  end
end
