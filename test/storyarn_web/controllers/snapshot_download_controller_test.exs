defmodule StoryarnWeb.SnapshotDownloadControllerTest do
  use StoryarnWeb.ConnCase, async: false

  import ExUnit.CaptureLog
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.VersioningFixtures
  import Storyarn.WorkspacesFixtures
  import StoryarnWeb.PrivateDownloadAssertions

  alias Storyarn.Commercial.Billing.StorageReservation
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Projects.Assets.Storage
  alias Storyarn.Projects.Versioning
  alias Storyarn.Projects.Versioning.ProjectSnapshot
  alias Storyarn.Repo
  alias Storyarn.SnapshotReadSwitchStorage
  alias Storyarn.Workers.BuildProjectSnapshotWorker

  setup :register_and_log_in_user

  setup %{user: user} do
    project = user |> project_fixture() |> Repo.preload(:workspace)
    %{project: project}
  end

  defp download_url(project, snapshot_id) do
    ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/snapshots/#{snapshot_id}/download"
  end

  test "delivers an authorized persisted ZIP through the private local fallback", %{
    conn: conn,
    project: project,
    user: user
  } do
    snapshot = build_ready_snapshot(project, user)
    assert {:ok, archive} = Storage.download(snapshot.archive_storage_key)
    attach_download_telemetry()

    conn = get(conn, download_url(project, snapshot.id))

    assert conn.status == 200
    assert conn.state == :chunked
    assert conn.resp_body == archive
    assert get_resp_header(conn, "content-type") == ["application/zip"]

    assert get_resp_header(conn, "content-disposition") == [
             ~s(attachment; filename="#{project.slug}-snapshot-v#{snapshot.version_number}.zip")
           ]

    assert get_resp_header(conn, "referrer-policy") == ["no-referrer"]
    assert_direct_private_response(conn, archive)

    assert_receive {:snapshot_download_stop,
                    %{count: 1, bytes: bytes, artifact_bytes: artifact_bytes, duration: duration}, metadata}

    assert metadata == %{
             outcome: :delivered,
             phase: :local,
             error_code: :none,
             user_id: user.id,
             project_id: project.id,
             snapshot_id: snapshot.id,
             lease_status_at_emit: "active"
           }

    assert bytes == byte_size(archive)
    assert artifact_bytes == snapshot.archive_size_bytes
    assert duration >= 0

    assert {:ok, entries} = :zip.unzip(archive, [:memory])
    paths = MapSet.new(entries, fn {path, _content} -> List.to_string(path) end)
    assert MapSet.member?(paths, "manifest.json")
    assert MapSet.member?(paths, "project.json")

    assert %StorageReservation{
             kind: "snapshot_export",
             status: "active",
             reserved_bytes: 0,
             storage_started_at: nil,
             cleanup_status: nil
           } = lease_for(snapshot)
  end

  test "supports a private byte range for the local persisted archive", %{
    conn: conn,
    project: project,
    user: user
  } do
    snapshot = build_ready_snapshot(project, user)
    assert {:ok, archive} = Storage.download(snapshot.archive_storage_key)

    conn =
      conn
      |> put_req_header("range", "bytes=2-11")
      |> get(download_url(project, snapshot.id))

    assert conn.status == 206
    assert conn.resp_body == binary_part(archive, 2, 10)
    assert get_resp_header(conn, "content-range") == ["bytes 2-11/#{byte_size(archive)}"]
    assert get_resp_header(conn, "content-length") == ["10"]
    assert %StorageReservation{status: "active"} = lease_for(snapshot)
  end

  test "records an unsatisfiable local range as rejected instead of delivered", %{
    conn: conn,
    project: project,
    user: user
  } do
    snapshot = build_ready_snapshot(project, user)
    attach_download_telemetry()

    conn =
      conn
      |> put_req_header("range", "bytes=#{snapshot.archive_size_bytes}-")
      |> get(download_url(project, snapshot.id))

    assert conn.status == 416
    assert conn.resp_body == ""
    assert get_resp_header(conn, "content-range") == ["bytes */#{snapshot.archive_size_bytes}"]

    assert_receive {:snapshot_download_stop, %{count: 1, bytes: 0, artifact_bytes: artifact_bytes, duration: duration},
                    %{
                      outcome: :rejected,
                      phase: :local,
                      error_code: :range_not_satisfiable,
                      project_id: project_id,
                      snapshot_id: snapshot_id,
                      lease_status_at_emit: "active"
                    }}

    assert artifact_bytes == snapshot.archive_size_bytes
    assert duration >= 0
    assert project_id == project.id
    assert snapshot_id == snapshot.id
    assert %StorageReservation{status: "active"} = lease_for(snapshot)
  end

  test "records only bytes actually sent when the local storage stream fails", %{
    conn: conn,
    project: project,
    user: user
  } do
    snapshot = build_ready_snapshot(project, user)
    original_storage = Application.fetch_env!(:storyarn, :storage)

    Application.put_env(
      :storyarn,
      :storage,
      Keyword.put(original_storage, :adapter, Storyarn.FailingStreamStorage)
    )

    on_exit(fn -> Application.put_env(:storyarn, :storage, original_storage) end)
    attach_download_telemetry()

    conn = get(conn, download_url(project, snapshot.id))

    assert conn.status == 200
    assert conn.state == :chunked
    assert conn.halted
    assert conn.resp_body == "partial"

    assert_receive {:snapshot_download_stop, %{count: 1, bytes: 7, artifact_bytes: artifact_bytes, duration: duration},
                    %{
                      outcome: :failed,
                      phase: :local,
                      error_code: :stream_failed,
                      project_id: project_id,
                      snapshot_id: snapshot_id,
                      lease_status_at_emit: "active"
                    }}

    assert artifact_bytes == snapshot.archive_size_bytes
    assert duration >= 0
    assert project_id == project.id
    assert snapshot_id == snapshot.id
    assert %StorageReservation{status: "active"} = lease_for(snapshot)
  end

  test "records a local stat failure with the known artifact size", %{
    conn: conn,
    project: project,
    user: user
  } do
    snapshot = build_ready_snapshot(project, user)
    install_signing_adapter({:error, :not_supported})
    SnapshotReadSwitchStorage.set_stat_result({:error, :storage_timeout})
    attach_download_telemetry()

    conn = get(conn, download_url(project, snapshot.id))

    assert conn.status == 503
    assert conn.resp_body =~ "temporarily unavailable"

    assert_receive {:snapshot_download_stop, %{count: 1, bytes: 0, artifact_bytes: artifact_bytes, duration: duration},
                    %{
                      outcome: :failed,
                      phase: :local,
                      error_code: :stat_unavailable,
                      user_id: user_id,
                      project_id: project_id,
                      snapshot_id: snapshot_id,
                      lease_status_at_emit: "active"
                    }}

    assert artifact_bytes == snapshot.archive_size_bytes
    assert duration >= 0
    assert user_id == user.id
    assert project_id == project.id
    assert snapshot_id == snapshot.id
    assert %StorageReservation{status: "active"} = lease_for(snapshot)
  end

  test "records a local stream initialization failure with the known artifact size", %{
    conn: conn,
    project: project,
    user: user
  } do
    snapshot = build_ready_snapshot(project, user)
    install_signing_adapter({:error, :not_supported})
    SnapshotReadSwitchStorage.set_stream_result({:error, :storage_timeout})
    attach_download_telemetry()

    conn = get(conn, download_url(project, snapshot.id))

    assert conn.status == 503
    assert conn.resp_body =~ "temporarily unavailable"

    assert_receive {:snapshot_download_stop, %{count: 1, bytes: 0, artifact_bytes: artifact_bytes, duration: duration},
                    %{
                      outcome: :failed,
                      phase: :local,
                      error_code: :stream_unavailable,
                      project_id: project_id,
                      snapshot_id: snapshot_id,
                      lease_status_at_emit: "active"
                    }}

    assert artifact_bytes == snapshot.archive_size_bytes
    assert duration >= 0
    assert project_id == project.id
    assert snapshot_id == snapshot.id
    assert %StorageReservation{status: "active"} = lease_for(snapshot)
  end

  test "reauthorizes then issues a five-minute R2 GET grant without proxying bytes", %{
    conn: conn,
    project: project,
    user: user
  } do
    snapshot = build_ready_snapshot(project, user)
    install_r2_signing_storage()
    attach_download_telemetry()

    {conn, log} = with_log(fn -> get(conn, download_url(project, snapshot.id)) end)

    assert conn.status == 302
    assert conn.state == :sent
    assert conn.resp_body == ""
    assert get_resp_header(conn, "cache-control") == ["private, no-store, no-transform"]
    assert get_resp_header(conn, "referrer-policy") == ["no-referrer"]
    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
    assert get_resp_header(conn, "content-disposition") == []
    assert get_resp_header(conn, "content-security-policy") == []
    assert get_resp_header(conn, "cross-origin-resource-policy") == []

    [location] = get_resp_header(conn, "location")
    refute log =~ location
    refute log =~ "X-Amz-Signature"

    uri = URI.parse(location)
    query = URI.decode_query(uri.query)

    assert uri.scheme == "https"
    assert uri.host == "t3.storage.dev"
    assert uri.path == "/private-bucket/#{snapshot.archive_storage_key}"
    assert query["X-Amz-Expires"] == "300"
    assert is_binary(query["X-Amz-Signature"])
    assert query["response-content-type"] == "application/zip"
    assert query["response-cache-control"] == "private, no-store, no-transform"

    assert query["response-content-disposition"] ==
             ~s(attachment; filename="#{project.slug}-snapshot-v#{snapshot.version_number}.zip")

    assert_receive {:snapshot_download_stop, %{count: 1, bytes: 0, artifact_bytes: artifact_bytes, duration: duration},
                    %{
                      outcome: :grant_issued,
                      phase: :redirect,
                      error_code: :none,
                      user_id: user_id,
                      project_id: project_id,
                      snapshot_id: snapshot_id,
                      lease_status_at_emit: "active"
                    }}

    assert artifact_bytes == snapshot.archive_size_bytes
    assert duration >= 0
    assert user_id == user.id
    assert project_id == project.id
    assert snapshot_id == snapshot.id

    assert %StorageReservation{
             status: "active",
             reserved_bytes: 0,
             storage_started_at: nil,
             cleanup_status: nil
           } = lease_for(snapshot)
  end

  test "retains the coalesced lease when provider signing fails", %{
    conn: conn,
    project: project,
    user: user
  } do
    snapshot = build_ready_snapshot(project, user)
    install_signing_adapter({:error, :provider_unavailable})

    conn = get(conn, download_url(project, snapshot.id))

    assert conn.status == 503
    assert conn.resp_body =~ "temporarily unavailable"
    assert_no_external_storage_response(conn)
    assert %StorageReservation{status: "active", cleanup_status: nil} = lease_for(snapshot)
  end

  test "sanitizes a signing exception without leaking provider details", %{
    conn: conn,
    project: project,
    user: user
  } do
    snapshot = build_ready_snapshot(project, user)
    install_signing_adapter(fn -> raise "provider-secret" end)

    log = capture_log(fn -> assert get(conn, download_url(project, snapshot.id)).status == 503 end)

    assert log =~ "Snapshot download grant failed"
    assert log =~ "project_id=#{project.id}"
    assert log =~ "snapshot_id=#{snapshot.id}"
    assert log =~ "error_code=signing_exception"
    assert log =~ "exception_module=RuntimeError"
    refute log =~ "provider-secret"
    refute log =~ snapshot.archive_storage_key
    assert %StorageReservation{status: "active"} = lease_for(snapshot)
  end

  test "sanitizes unsafe filename characters at the authorized local boundary", %{
    conn: conn,
    project: project,
    user: user
  } do
    snapshot = build_ready_snapshot(project, user)
    unsafe_slug = "unsafe\r\n\"\\slug"

    project =
      project
      |> Ecto.Changeset.change(slug: unsafe_slug)
      |> Repo.update!()

    conn =
      get(
        conn,
        "/workspaces/#{project.workspace.slug}/projects/#{URI.encode(unsafe_slug)}/snapshots/#{snapshot.id}/download"
      )

    assert conn.status == 200

    assert get_resp_header(conn, "content-disposition") == [
             ~s(attachment; filename="unsafe____slug-snapshot-v#{snapshot.version_number}.zip")
           ]

    assert_no_external_storage_response(conn)
  end

  test "returns 404 for unknown, malformed, or out-of-range snapshot identifiers", %{
    conn: conn,
    project: project,
    user: user
  } do
    attach_download_telemetry()

    for snapshot_id <- [123, "not-an-id", 9_223_372_036_854_775_808] do
      response = get(conn, download_url(project, snapshot_id))
      assert response.status == 404
      assert_no_external_storage_response(response)

      assert_receive {:snapshot_download_stop, _measurements, %{user_id: user_id}}
      assert user_id == user.id
    end
  end

  test "forbids project editors from downloading owner-only snapshots", %{conn: conn, user: user} do
    owner = user_fixture()
    project = owner |> project_fixture() |> Repo.preload(:workspace)
    membership_fixture(project, user, "editor")
    attach_download_telemetry()

    conn = get(conn, download_url(project, 1))

    assert conn.status == 403
    assert conn.resp_body =~ "permission"
    assert_no_external_storage_response(conn)
    assert_receive {:snapshot_download_stop, _measurements, %{user_id: user_id}}
    assert user_id == user.id
  end

  test "returns 404 to a user outside the requested project", %{conn: conn} do
    other_user = user_fixture()
    project = other_user |> project_fixture() |> Repo.preload(:workspace)

    conn = get(conn, download_url(project, 1))

    assert conn.status == 404
    assert_no_external_storage_response(conn)
  end

  test "does not accept a snapshot id owned by another project in the same workspace", %{
    conn: conn,
    user: user
  } do
    workspace = workspace_fixture(user)
    requested_project = user |> project_fixture(%{workspace: workspace}) |> Repo.preload(:workspace)
    other_project = user |> project_fixture(%{workspace: workspace}) |> Repo.preload(:workspace)
    other_snapshot = full_project_snapshot_fixture(other_project, %{asset_blob_size_bytes: 0})

    conn = get(conn, download_url(requested_project, other_snapshot.id))

    assert conn.status == 404
    assert_no_external_storage_response(conn)
  end

  test "fails closed for non-ready and unverified snapshots", %{
    conn: conn,
    project: project,
    user: user
  } do
    attach_download_telemetry()
    pending = pending_project_snapshot_fixture(project)

    missing =
      project
      |> full_project_snapshot_fixture(%{asset_blob_size_bytes: 0})
      |> ProjectSnapshot.reconciliation_integrity_changeset("missing")
      |> Repo.update!()

    pending_conn = get(conn, download_url(project, pending.id))
    assert pending_conn.status == 409
    assert pending_conn.resp_body =~ "not ready"
    assert_receive {:snapshot_download_stop, _measurements, %{user_id: pending_user_id}}
    assert pending_user_id == user.id

    missing_conn = get(conn, download_url(project, missing.id))
    assert missing_conn.status == 422
    assert missing_conn.resp_body =~ "integrity"
    assert_receive {:snapshot_download_stop, _measurements, %{user_id: missing_user_id}}
    assert missing_user_id == user.id

    for response <- [pending_conn, missing_conn] do
      assert_no_external_storage_response(response)
    end
  end

  test "unauthenticated requests still redirect to sign in", %{project: project} do
    conn = get(build_conn(), download_url(project, 123))

    assert conn.status == 302
    assert redirected_to(conn) =~ "/users/log-in"
    assert_no_external_storage_response(conn)
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

  defp install_r2_signing_storage do
    original_storage = Application.fetch_env!(:storyarn, :storage)
    original_r2 = Application.get_env(:storyarn, :r2)
    original_s3 = Application.get_env(:ex_aws, :s3)
    original_access_key = Application.get_env(:ex_aws, :access_key_id)
    original_secret_key = Application.get_env(:ex_aws, :secret_access_key)

    Application.put_env(:storyarn, :storage, Keyword.put(original_storage, :adapter, :r2))

    Application.put_env(:storyarn, :r2,
      bucket: "private-bucket",
      endpoint_url: "https://t3.storage.dev",
      public_url: nil
    )

    Application.put_env(:ex_aws, :s3, host: "t3.storage.dev", scheme: "https://", region: "auto")
    Application.put_env(:ex_aws, :access_key_id, "test-access-key")
    Application.put_env(:ex_aws, :secret_access_key, "test-secret-key")

    on_exit(fn ->
      Application.put_env(:storyarn, :storage, original_storage)
      restore_env(:storyarn, :r2, original_r2)
      restore_env(:ex_aws, :s3, original_s3)
      restore_env(:ex_aws, :access_key_id, original_access_key)
      restore_env(:ex_aws, :secret_access_key, original_secret_key)
    end)
  end

  defp install_signing_adapter(result) do
    original_storage = Application.fetch_env!(:storyarn, :storage)
    {:ok, pid} = SnapshotReadSwitchStorage.start_link(%{})
    Process.unlink(pid)
    SnapshotReadSwitchStorage.set_presigned_download_result(result)

    Application.put_env(
      :storyarn,
      :storage,
      Keyword.put(original_storage, :adapter, SnapshotReadSwitchStorage)
    )

    on_exit(fn ->
      Application.put_env(:storyarn, :storage, original_storage)
      stop_test_process(pid)
    end)
  end

  defp stop_test_process(pid) do
    monitor = Process.monitor(pid)
    Process.exit(pid, :shutdown)

    receive do
      {:DOWN, ^monitor, :process, ^pid, _reason} -> :ok
    after
      1_000 -> kill_stuck_test_process(pid, monitor)
    end
  end

  defp kill_stuck_test_process(pid, monitor) do
    Process.exit(pid, :kill)

    receive do
      {:DOWN, ^monitor, :process, ^pid, _reason} ->
        raise "snapshot read switch storage did not stop cleanly"
    after
      1_000 ->
        Process.demonitor(monitor, [:flush])
        raise "snapshot read switch storage could not be terminated"
    end
  end

  defp lease_for(snapshot) do
    Repo.get_by!(StorageReservation,
      project_snapshot_id_snapshot: snapshot.id,
      kind: "snapshot_export"
    )
  end

  defp attach_download_telemetry do
    handler_id = {__MODULE__, self(), make_ref()}

    :ok =
      :telemetry.attach(
        handler_id,
        [:storyarn, :snapshot, :download, :stop],
        fn _event, measurements, metadata, test_pid ->
          send(
            test_pid,
            {:snapshot_download_stop, measurements,
             Map.put(metadata, :lease_status_at_emit, lease_status_at_emit(metadata))}
          )
        end,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end

  defp lease_status_at_emit(%{snapshot_id: snapshot_id}) when is_integer(snapshot_id) do
    case Repo.get_by(StorageReservation,
           project_snapshot_id_snapshot: snapshot_id,
           kind: "snapshot_export"
         ) do
      %StorageReservation{status: status} -> status
      nil -> nil
    end
  end

  defp lease_status_at_emit(_metadata), do: nil

  defp restore_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_env(app, key, value), do: Application.put_env(app, key, value)
end
