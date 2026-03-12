defmodule StoryarnWeb.SnapshotDownloadControllerTest do
  use StoryarnWeb.ConnCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Repo
  alias Storyarn.Versioning

  setup :register_and_log_in_user

  setup %{user: user} do
    project = project_fixture(user) |> Repo.preload(:workspace)
    %{project: project}
  end

  defp download_url(project, snapshot_id) do
    ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/snapshots/#{snapshot_id}/download"
  end

  describe "GET download" do
    test "downloads snapshot as gzip attachment", %{conn: conn, user: user, project: project} do
      _flow = flow_fixture(project, %{name: "Test Flow"})
      {:ok, snapshot} = Versioning.create_project_snapshot(project.id, user.id, title: "Backup")

      conn = get(conn, download_url(project, snapshot.id))

      assert conn.status == 200
      [content_type] = get_resp_header(conn, "content-type")
      assert content_type =~ "application/gzip"

      [disposition] = get_resp_header(conn, "content-disposition")
      assert disposition =~ "attachment"
      assert disposition =~ "snapshot-v#{snapshot.version_number}"
      assert disposition =~ ".json.gz"
    end

    test "filename includes project name and date", %{conn: conn, user: user, project: project} do
      {:ok, snapshot} = Versioning.create_project_snapshot(project.id, user.id, title: "Backup")

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
      {:ok, snapshot} = Versioning.create_project_snapshot(project.id, user.id, title: "Backup")

      conn = get(conn, download_url(project, snapshot.id))

      {:ok, json} = conn.resp_body |> :zlib.gunzip() |> Jason.decode()
      assert json["format_version"] == 2
      assert is_map(json["entity_counts"])
    end

    test "returns 404 for non-existent snapshot", %{conn: conn, project: project} do
      conn = get(conn, download_url(project, 999_999))
      assert conn.status == 404
    end

    test "returns 404 for non-member project", %{conn: conn} do
      other_user = user_fixture()
      other_project = project_fixture(other_user) |> Repo.preload(:workspace)

      conn =
        get(
          conn,
          ~p"/workspaces/#{other_project.workspace.slug}/projects/#{other_project.slug}/snapshots/1/download"
        )

      assert conn.status == 404
    end

    test "redirects unauthenticated user", %{project: project} do
      conn = build_conn()
      conn = get(conn, download_url(project, 1))

      assert conn.status == 302
      assert redirected_to(conn) =~ "/users/log-in"
    end
  end
end
