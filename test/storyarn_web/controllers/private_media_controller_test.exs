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
      assert get_resp_header(conn, "content-type") == ["image/png; charset=utf-8"]
      assert get_resp_header(conn, "cache-control") == ["private, no-store"]
    end

    test "returns 404 to a user outside the project", %{conn: conn} do
      other_user = user_fixture()
      other_project = project_fixture(other_user)
      {asset, _body} = stored_asset_fixture(other_project, other_user)

      conn = get(conn, PrivateMedia.asset_url(asset))

      assert conn.status == 404
    end

    test "redirects an unauthenticated request", %{user: user, project: project} do
      {asset, _body} = stored_asset_fixture(project, user)

      conn = get(build_conn(), PrivateMedia.asset_url(asset))

      assert conn.status == 302
      assert redirected_to(conn) =~ "/users/log-in"
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
    end

    test "rejects a key belonging to another project", %{conn: conn, project: project} do
      other_user = user_fixture()
      other_project = project_fixture(other_user)
      key = "projects/#{other_project.id}/blobs/private.png"

      conn = get(conn, PrivateMedia.project_file_url(project.id, key))

      assert conn.status == 404
    end
  end

  describe "GET /media/workspaces/:workspace_slug/banner" do
    test "serves the banner to a workspace member", %{conn: conn, workspace: workspace} do
      body = "workspace banner"
      workspace = workspace_with_stored_banner(workspace, body)

      conn = get(conn, PrivateMedia.workspace_banner_url(workspace))

      assert conn.status == 200
      assert conn.resp_body == body
    end

    test "returns 404 to a user outside the workspace", %{conn: conn} do
      other_user = user_fixture()
      other_workspace = workspace_fixture(other_user)
      other_workspace = workspace_with_stored_banner(other_workspace, "private banner")

      conn = get(conn, PrivateMedia.workspace_banner_url(other_workspace))

      assert conn.status == 404
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
end
