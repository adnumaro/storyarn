defmodule StoryarnWeb.SnapshotDownloadControllerTest do
  use StoryarnWeb.ConnCase, async: true

  import Storyarn.ProjectsFixtures
  import StoryarnWeb.PrivateDownloadAssertions

  alias Storyarn.Repo

  setup :register_and_log_in_user

  setup %{user: user} do
    project = user |> project_fixture() |> Repo.preload(:workspace)
    %{project: project}
  end

  defp download_url(project, snapshot_id) do
    ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/snapshots/#{snapshot_id}/download"
  end

  test "authenticated requests fail closed without exposing snapshot storage", %{
    conn: conn,
    project: project
  } do
    conn = get(conn, download_url(project, 123))

    assert conn.status == 404
    assert_no_external_storage_response(conn)
  end

  test "unauthenticated requests still redirect to sign in", %{project: project} do
    conn = get(build_conn(), download_url(project, 123))

    assert conn.status == 302
    assert redirected_to(conn) =~ "/users/log-in"
    assert_no_external_storage_response(conn)
  end
end
