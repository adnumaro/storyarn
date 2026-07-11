defmodule StoryarnWeb.SnapshotDownloadControllerTest do
  use StoryarnWeb.ConnCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import StoryarnWeb.PrivateDownloadAssertions

  alias Storyarn.Assets.Storage
  alias Storyarn.Repo
  alias Storyarn.Versioning

  setup :register_and_log_in_user

  setup %{user: user} do
    project = user |> project_fixture() |> Repo.preload(:workspace)
    %{project: project}
  end

  defp download_url(project, snapshot_id) do
    ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/snapshots/#{snapshot_id}/download"
  end

  describe "GET download" do
    test "downloads snapshot as gzip attachment", %{conn: conn, user: user, project: project} do
      _flow = flow_fixture(project, %{name: "Test Flow"})
      snapshot = snapshot_fixture(project, user, title: "Backup")

      conn = get(conn, download_url(project, snapshot.id))

      assert conn.status == 200
      assert_direct_private_response(conn, conn.resp_body)
      [content_type] = get_resp_header(conn, "content-type")
      assert content_type =~ "application/gzip"

      [disposition] = get_resp_header(conn, "content-disposition")
      assert disposition =~ "attachment"
      assert disposition =~ "snapshot-v#{snapshot.version_number}"
      assert disposition =~ ".json.gz"
    end

    test "filename includes project name and date", %{conn: conn, user: user, project: project} do
      snapshot = snapshot_fixture(project, user, title: "Backup")

      conn = get(conn, download_url(project, snapshot.id))

      [disposition] = get_resp_header(conn, "content-disposition")
      date = Calendar.strftime(snapshot.inserted_at, "%Y-%m-%d")
      assert disposition =~ date
    end

    test "downloaded content is valid gzipped JSON", %{
      conn: conn,
      user: user,
      project: project
    } do
      _flow = flow_fixture(project, %{name: "Test Flow"})
      snapshot = snapshot_fixture(project, user, title: "Backup")

      conn = get(conn, download_url(project, snapshot.id))

      {:ok, json} = conn.resp_body |> :zlib.gunzip() |> Jason.decode()
      assert json["format_version"] == 2
      assert is_map(json["entity_counts"])
    end

    test "serves a single byte range without exposing a storage URL", %{
      conn: conn,
      user: user,
      project: project
    } do
      snapshot = snapshot_fixture(project, user, title: "Backup")
      {:ok, archive} = Storage.download(snapshot.storage_key)

      conn =
        conn
        |> put_req_header("range", "bytes=3-11")
        |> get(download_url(project, snapshot.id))

      assert conn.status == 206
      assert conn.resp_body == binary_part(archive, 3, 9)
      assert get_resp_header(conn, "content-range") == ["bytes 3-11/#{byte_size(archive)}"]
      assert get_resp_header(conn, "content-length") == ["9"]
      assert_direct_private_response(conn, conn.resp_body)
    end

    test "returns 416 for an unsatisfiable range", %{
      conn: conn,
      user: user,
      project: project
    } do
      snapshot = snapshot_fixture(project, user, title: "Backup")
      {:ok, archive} = Storage.download(snapshot.storage_key)

      conn =
        conn
        |> put_req_header("range", "bytes=#{byte_size(archive)}-")
        |> get(download_url(project, snapshot.id))

      assert conn.status == 416
      assert conn.resp_body == ""
      assert get_resp_header(conn, "content-range") == ["bytes */#{byte_size(archive)}"]
      assert get_resp_header(conn, "accept-ranges") == ["bytes"]
      assert get_resp_header(conn, "cache-control") == ["private, no-store, no-transform"]
      assert_no_external_storage_response(conn)
    end

    test "returns 404 for non-existent snapshot", %{conn: conn, project: project} do
      conn = get(conn, download_url(project, 999_999))
      assert conn.status == 404
    end

    test "rejects a snapshot record that points outside the project snapshot namespace", %{
      conn: conn,
      user: user,
      project: project
    } do
      snapshot = snapshot_fixture(project, user, title: "Forged pointer")
      forbidden_key = "projects/#{project.id}/blobs/forged-snapshot.json.gz"
      forbidden_body = "private blob bytes"
      {:ok, _url} = Storage.upload(forbidden_key, forbidden_body, "application/gzip")
      on_exit(fn -> Storage.delete(forbidden_key) end)

      snapshot
      |> Ecto.Changeset.change(storage_key: forbidden_key)
      |> Repo.update!()

      conn = get(conn, download_url(project, snapshot.id))

      assert conn.status == 404
      refute conn.resp_body == forbidden_body
      assert_no_external_storage_response(conn)
    end

    test "returns 404 for non-member project", %{conn: conn} do
      other_user = user_fixture()
      other_project = other_user |> project_fixture() |> Repo.preload(:workspace)
      snapshot = snapshot_fixture(other_project, other_user, title: "Private backup")

      conn =
        get(
          conn,
          download_url(other_project, snapshot.id)
        )

      assert conn.status == 404
      assert_no_external_storage_response(conn)
    end

    test "denies snapshot archives to editor and viewer roles", %{
      user: owner,
      project: project
    } do
      snapshot = snapshot_fixture(project, owner, title: "Owner-only backup")

      for role <- ~w(editor viewer) do
        member = user_fixture()
        membership_fixture(project, member, role)

        conn =
          build_conn()
          |> log_in_user(member)
          |> get(download_url(project, snapshot.id))

        assert conn.status == 404
        assert_no_external_storage_response(conn)
      end
    end

    test "redirects unauthenticated user", %{user: user, project: project} do
      snapshot = snapshot_fixture(project, user, title: "Private backup")
      conn = build_conn()
      conn = get(conn, download_url(project, snapshot.id))

      assert conn.status == 302
      assert redirected_to(conn) =~ "/users/log-in"
      assert_no_external_storage_response(conn)
    end
  end

  defp snapshot_fixture(project, user, opts) do
    {:ok, snapshot} = Versioning.create_project_snapshot(project.id, user.id, opts)
    on_exit(fn -> Storage.delete(snapshot.storage_key) end)
    snapshot
  end
end
