defmodule StoryarnWeb.SnapshotDownloadControllerTest do
  use StoryarnWeb.ConnCase, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.VersioningFixtures
  import Storyarn.WorkspacesFixtures
  import StoryarnWeb.PrivateDownloadAssertions

  alias Storyarn.Billing.StorageReservation
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Versioning
  alias Storyarn.Versioning.ProjectSnapshot
  alias Storyarn.Workers.BuildProjectSnapshotWorker

  setup :register_and_log_in_user

  setup %{user: user} do
    project = user |> project_fixture() |> Repo.preload(:workspace)
    %{project: project}
  end

  defp download_url(project, snapshot_id) do
    ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/snapshots/#{snapshot_id}/download"
  end

  test "streams an authorized verified full snapshot as a private ZIP", %{
    conn: conn,
    project: project,
    user: user
  } do
    snapshot = build_ready_snapshot(project, user)

    conn = get(conn, download_url(project, snapshot.id))

    assert conn.status == 200
    assert conn.state == :chunked
    assert get_resp_header(conn, "content-type") == ["application/zip"]

    assert get_resp_header(conn, "content-disposition") == [
             ~s(attachment; filename="#{project.slug}-snapshot-v#{snapshot.version_number}.zip")
           ]

    assert get_resp_header(conn, "cache-control") == ["private, no-store, no-transform"]
    assert get_resp_header(conn, "content-security-policy") == ["sandbox; default-src 'none'"]
    assert get_resp_header(conn, "cross-origin-resource-policy") == ["same-origin"]
    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
    assert get_resp_header(conn, "location") == []
    assert_no_external_storage_response(conn)

    assert {:ok, entries} = :zip.unzip(conn.resp_body, [:memory])
    paths = MapSet.new(entries, fn {path, _content} -> List.to_string(path) end)
    assert MapSet.member?(paths, "manifest.json")
    assert MapSet.member?(paths, "project.json")

    assert %StorageReservation{
             kind: "snapshot_export",
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

  test "returns 404 for an unknown snapshot without exposing storage", %{
    conn: conn,
    project: project
  } do
    conn = get(conn, download_url(project, 123))

    assert conn.status == 404
    assert_no_external_storage_response(conn)
  end

  test "returns 404 for malformed snapshot identifiers", %{conn: conn, project: project} do
    conn = get(conn, download_url(project, "not-an-id"))

    assert conn.status == 404
    assert conn.resp_body =~ "not found"
    assert_no_external_storage_response(conn)
  end

  test "returns 404 for snapshot identifiers outside the bigint range", %{
    conn: conn,
    project: project
  } do
    conn = get(conn, download_url(project, 9_223_372_036_854_775_808))

    assert conn.status == 404
    assert conn.resp_body =~ "not found"
    assert_no_external_storage_response(conn)
  end

  test "sanitizes unsafe filename characters at the response boundary", %{
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

    encoded_slug = URI.encode(unsafe_slug)

    conn =
      get(
        conn,
        "/workspaces/#{project.workspace.slug}/projects/#{encoded_slug}/snapshots/#{snapshot.id}/download"
      )

    assert conn.status == 200

    assert get_resp_header(conn, "content-disposition") == [
             ~s(attachment; filename="unsafe____slug-snapshot-v#{snapshot.version_number}.zip")
           ]

    assert_no_external_storage_response(conn)
  end

  test "forbids project editors from downloading owner-only snapshots", %{
    conn: conn,
    user: user
  } do
    owner = user_fixture()
    project = owner |> project_fixture() |> Repo.preload(:workspace)
    membership_fixture(project, user, "editor")

    conn = get(conn, download_url(project, 1))

    assert conn.status == 403
    assert conn.resp_body =~ "permission"
    assert_no_external_storage_response(conn)
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

  test "fails closed with an actionable conflict for a non-ready snapshot", %{
    conn: conn,
    project: project
  } do
    snapshot = pending_project_snapshot_fixture(project)

    conn = get(conn, download_url(project, snapshot.id))

    assert conn.status == 409
    assert conn.resp_body =~ "not ready"
    assert_no_external_storage_response(conn)
  end

  test "fails closed with conversion guidance for a linked snapshot", %{
    conn: conn,
    project: project
  } do
    snapshot =
      project
      |> full_project_snapshot_fixture(%{asset_blob_size_bytes: 0})
      |> Ecto.Changeset.change(mode: "linked")
      |> Repo.update!()

    conn = get(conn, download_url(project, snapshot.id))

    assert conn.status == 409
    assert conn.resp_body =~ "Convert this linked snapshot"
    assert_no_external_storage_response(conn)
  end

  test "rejects a snapshot whose persisted integrity is unavailable", %{
    conn: conn,
    project: project
  } do
    snapshot =
      project
      |> full_project_snapshot_fixture(%{asset_blob_size_bytes: 0})
      |> ProjectSnapshot.reconciliation_integrity_changeset("missing")
      |> Repo.update!()

    conn = get(conn, download_url(project, snapshot.id))

    assert conn.status == 422
    assert conn.resp_body =~ "integrity"
    assert_no_external_storage_response(conn)
  end

  test "rejects corrupt canonical storage before sending ZIP headers", %{
    conn: conn,
    project: project
  } do
    snapshot = full_project_snapshot_fixture(project, %{asset_blob_size_bytes: 0})

    conn = get(conn, download_url(project, snapshot.id))

    assert conn.status == 422
    assert get_resp_header(conn, "content-type") == ["text/plain; charset=utf-8"]
    assert get_resp_header(conn, "content-disposition") == []
    assert conn.resp_body =~ "integrity"
    assert_no_external_storage_response(conn)

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

  test "releases the read lease when delivery exits unexpectedly", %{
    project: project,
    user: user
  } do
    snapshot = build_ready_snapshot(project, user)

    assert_raise RuntimeError, "simulated client disconnect", fn ->
      Versioning.with_project_snapshot_zip(project.id, snapshot.id, fn _plan ->
        raise "simulated client disconnect"
      end)
    end

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
end
