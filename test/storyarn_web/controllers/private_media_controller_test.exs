defmodule StoryarnWeb.PrivateMediaControllerTest do
  use StoryarnWeb.ConnCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.Assets.Storage
  alias Storyarn.Repo
  alias Storyarn.Workspaces
  alias StoryarnWeb.PrivateMedia

  setup :register_and_log_in_user

  setup %{user: user} do
    project = user |> project_fixture() |> Repo.preload(:workspace)
    %{project: project, workspace: project.workspace}
  end

  describe "GET /media/assets/:id" do
    test "serves an asset to a project member", %{conn: conn, user: user, project: project} do
      {asset, body} = stored_asset_fixture(project, user)

      conn = get(conn, PrivateMedia.asset_url(asset))

      assert conn.status == 200
      assert conn.resp_body == body
      assert get_resp_header(conn, "content-type") == ["image/png"]
      assert_direct_private_response(conn, body)
    end

    test "serves a single byte range without exposing storage", %{
      conn: conn,
      user: user,
      project: project
    } do
      {asset, body} = stored_asset_fixture(project, user)

      conn =
        conn
        |> put_req_header("range", "bytes=2-5")
        |> get(PrivateMedia.asset_url(asset))

      assert conn.status == 206
      assert conn.resp_body == binary_part(body, 2, 4)
      assert get_resp_header(conn, "content-range") == ["bytes 2-5/#{byte_size(body)}"]
      assert get_resp_header(conn, "content-length") == ["4"]
      assert_direct_private_response(conn, conn.resp_body)
    end

    test "returns 416 for an unsatisfiable range", %{
      conn: conn,
      user: user,
      project: project
    } do
      {asset, body} = stored_asset_fixture(project, user)

      conn =
        conn
        |> put_req_header("range", "bytes=#{byte_size(body)}-")
        |> get(PrivateMedia.asset_url(asset))

      assert conn.status == 416
      assert conn.resp_body == ""
      assert get_resp_header(conn, "content-range") == ["bytes */#{byte_size(body)}"]
      assert get_resp_header(conn, "accept-ranges") == ["bytes"]
      assert get_resp_header(conn, "cache-control") == ["private, no-store, no-transform"]
      assert_no_external_storage_response(conn)
    end

    test "returns 404 to a user outside the project", %{conn: conn} do
      other_user = user_fixture()
      other_project = project_fixture(other_user)
      {asset, body} = stored_asset_fixture(other_project, other_user)

      conn = get(conn, PrivateMedia.asset_url(asset))

      assert conn.status == 404
      refute conn.resp_body == body
      assert_no_external_storage_response(conn)
    end

    test "rejects an asset record that points outside its asset namespace", %{
      conn: conn,
      user: user,
      project: project
    } do
      key = "projects/#{project.id}/snapshots/project/forged.json.gz"
      body = "snapshot bytes"
      {:ok, url} = Storage.upload(key, body, "application/gzip")
      on_exit(fn -> Storage.delete(key) end)

      asset =
        asset_fixture(project, user, %{
          filename: "forged.png",
          content_type: "image/png",
          size: byte_size(body),
          key: key,
          url: url
        })

      conn = get(conn, PrivateMedia.asset_url(asset))

      assert conn.status == 404
      refute conn.resp_body == body
      assert_no_external_storage_response(conn)
    end

    test "redirects an unauthenticated request", %{user: user, project: project} do
      {asset, body} = stored_asset_fixture(project, user)

      conn = get(build_conn(), PrivateMedia.asset_url(asset))

      assert conn.status == 302
      assert redirected_to(conn) =~ "/users/log-in"
      refute conn.resp_body == body
      assert_no_external_storage_response(conn)
    end
  end

  describe "GET /media/projects/:project_id/files/:encoded_key" do
    test "serves a project-scoped blob", %{conn: conn, project: project} do
      key = "projects/#{project.id}/blobs/#{Ecto.UUID.generate()}.png"
      body = "project blob"
      {:ok, _url} = Storage.upload(key, body, "image/png")
      on_exit(fn -> Storage.delete(key) end)

      conn = get(conn, PrivateMedia.project_file_url(project.id, key))

      assert conn.status == 200
      assert conn.resp_body == body
      assert_direct_private_response(conn, body)
    end

    test "rejects a key belonging to another project", %{conn: conn, project: project} do
      other_user = user_fixture()
      other_project = project_fixture(other_user)
      key = "projects/#{other_project.id}/blobs/private.png"

      conn = get(conn, PrivateMedia.project_file_url(project.id, key))

      assert conn.status == 404
      assert_no_external_storage_response(conn)
    end

    test "rejects a base64 key that is not valid UTF-8", %{conn: conn, project: project} do
      encoded_key = Base.url_encode64(<<255, 254>>, padding: false)

      conn = get(conn, "/media/projects/#{project.id}/files/#{encoded_key}")

      assert conn.status == 404
      assert_no_external_storage_response(conn)
    end

    test "rejects snapshot keys even when they belong to the requested project", %{
      conn: conn,
      project: project
    } do
      key = "projects/#{project.id}/snapshots/project/1.json.gz"

      conn = get(conn, project_file_path(project.id, key))

      assert conn.status == 404
      assert_no_external_storage_response(conn)
    end

    test "returns 416 when a byte range targets an empty object", %{
      conn: conn,
      project: project
    } do
      key = "projects/#{project.id}/blobs/#{Ecto.UUID.generate()}.bin"
      {:ok, _url} = Storage.upload(key, "", "application/octet-stream")
      on_exit(fn -> Storage.delete(key) end)

      conn =
        conn
        |> put_req_header("range", "bytes=0-")
        |> get(PrivateMedia.project_file_url(project.id, key))

      assert conn.status == 416
      assert get_resp_header(conn, "content-range") == ["bytes */0"]
      assert_no_external_storage_response(conn)
    end

    test "ignores a malformed byte range on an empty object", %{
      conn: conn,
      project: project
    } do
      key = "projects/#{project.id}/blobs/#{Ecto.UUID.generate()}.bin"
      {:ok, _url} = Storage.upload(key, "", "application/octet-stream")
      on_exit(fn -> Storage.delete(key) end)

      conn =
        conn
        |> put_req_header("range", "bytes=not-a-range")
        |> get(PrivateMedia.project_file_url(project.id, key))

      assert conn.status == 200
      assert conn.resp_body == ""
      assert get_resp_header(conn, "content-length") == ["0"]
      assert_no_external_storage_response(conn)
    end
  end

  describe "GET /media/workspaces/:workspace_slug/banner" do
    test "serves the banner to a workspace member", %{conn: conn, workspace: workspace} do
      body = "workspace banner"
      workspace = workspace_with_stored_banner(workspace, body)

      conn = get(conn, PrivateMedia.workspace_banner_url(workspace))

      assert conn.status == 200
      assert conn.resp_body == body
      assert_direct_private_response(conn, body)
    end

    test "returns 404 to a user outside the workspace", %{conn: conn} do
      other_user = user_fixture()
      other_workspace = workspace_fixture(other_user)
      other_workspace = workspace_with_stored_banner(other_workspace, "private banner")

      conn = get(conn, PrivateMedia.workspace_banner_url(other_workspace))

      assert conn.status == 404
      assert_no_external_storage_response(conn)
    end
  end

  describe "legacy /uploads path" do
    test "does not expose local storage through Plug.Static" do
      key = "projects/999/private/#{Ecto.UUID.generate()}.png"
      body = "private static file"
      {:ok, public_path} = Storage.upload(key, body, "image/png")
      on_exit(fn -> Storage.delete(key) end)

      conn = get(build_conn(), public_path)

      assert conn.status == 404
      refute conn.resp_body == body
    end
  end

  defp stored_asset_fixture(project, user) do
    key = "projects/#{project.id}/assets/#{Ecto.UUID.generate()}/private.png"
    body = "private image #{key}"
    {:ok, url} = Storage.upload(key, body, "image/png")
    on_exit(fn -> Storage.delete(key) end)

    asset =
      asset_fixture(project, user, %{
        filename: "private.png",
        content_type: "image/png",
        size: byte_size(body),
        key: key,
        url: url
      })

    {asset, body}
  end

  defp workspace_with_stored_banner(workspace, body) do
    key = "workspaces/#{workspace.slug}/banner/#{Ecto.UUID.generate()}.png"
    {:ok, url} = Storage.upload(key, body, "image/png")
    on_exit(fn -> Storage.delete(key) end)
    {:ok, workspace} = Workspaces.update_workspace(workspace, %{banner_url: url})
    workspace
  end

  defp project_file_path(project_id, key) do
    encoded_key = Base.url_encode64(key, padding: false)
    "/media/projects/#{project_id}/files/#{encoded_key}"
  end

  defp assert_direct_private_response(conn, body) do
    assert get_resp_header(conn, "location") == []
    assert get_resp_header(conn, "accept-ranges") == ["bytes"]
    assert get_resp_header(conn, "cache-control") == ["private, no-store, no-transform"]
    assert get_resp_header(conn, "content-security-policy") == ["sandbox; default-src 'none'"]
    assert get_resp_header(conn, "cross-origin-resource-policy") == ["same-origin"]
    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
    assert get_resp_header(conn, "content-length") == [Integer.to_string(byte_size(body))]
    assert_no_external_storage_response(conn)
  end

  defp assert_no_external_storage_response(conn) do
    response = conn |> then(&inspect({&1.resp_headers, &1.resp_body})) |> String.downcase()

    refute response =~ "storage.dev"
    refute response =~ "x-amz-"
  end
end
