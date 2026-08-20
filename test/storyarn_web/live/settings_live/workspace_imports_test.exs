defmodule StoryarnWeb.SettingsLive.WorkspaceImportsTest do
  use StoryarnWeb.ConnCase, async: true

  import Ecto.Changeset
  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.Repo
  alias Storyarn.Versioning.WorkspaceSnapshotImport

  defp get_imports_vue(view) do
    LiveVue.Test.get_vue(view, name: "live/workspace/settings/WorkspaceSettingsImports")
  end

  defp workspace_import_fixture(user, workspace, attrs \\ %{}) do
    checksum = String.duplicate("a", 64)

    defaults = %{
      workspace_id: workspace.id,
      user_id: user.id,
      idempotency_key:
        :sha256
        |> :crypto.hash(inspect(make_ref()))
        |> Base.encode16(case: :lower),
      original_filename: "complete-project.zip",
      project_name: "Recovered story",
      archive_storage_key: "workspace-imports/#{workspace.id}/complete-project.zip",
      archive_size_bytes: 1_024,
      archive_checksum: checksum,
      manifest_checksum: checksum,
      project_checksum: checksum,
      reserved_bytes: 2_048,
      staging_storage_keys: ["workspace-imports/#{workspace.id}/staging/object"],
      progress_total_bytes: 2_048,
      max_attempts: 3
    }

    %WorkspaceSnapshotImport{}
    |> WorkspaceSnapshotImport.request_changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  describe "mount" do
    test "renders the durable import surface for a workspace owner", %{conn: conn} do
      user = user_fixture()
      workspace = workspace_fixture(user)
      import = workspace_import_fixture(user, workspace)

      {:ok, view, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/users/settings/workspaces/#{workspace.slug}/imports")

      vue = get_imports_vue(view)
      assert vue.component == "live/workspace/settings/WorkspaceSettingsImports"
      assert is_map(vue.props["upload-config"])
      assert vue.props["quota-rejection"] == nil
      assert vue.props["request-error-code"] == nil

      assert [serialized] = vue.props["imports"]
      assert serialized["id"] == import.id
      assert serialized["fileName"] == "complete-project.zip"
      assert serialized["projectName"] == "Recovered story"
      assert serialized["status"] == "queued"
      assert serialized["phase"] == "queued"
      assert serialized["progressBytes"] == "0"
      assert serialized["progressTotalBytes"] == "2048"
      assert serialized["projectPath"] == nil
      assert is_binary(serialized["insertedAt"])
    end

    test "renders for a workspace admin", %{conn: conn} do
      owner = user_fixture()
      workspace = workspace_fixture(owner)
      admin = user_fixture()
      workspace_membership_fixture(workspace, admin, "admin")

      {:ok, view, _html} =
        conn
        |> log_in_user(admin)
        |> live(~p"/users/settings/workspaces/#{workspace.slug}/imports")

      assert get_imports_vue(view).props["imports"] == []
    end

    test "redirects a member without administrative settings access", %{conn: conn} do
      owner = user_fixture()
      workspace = workspace_fixture(owner)
      member = user_fixture()
      workspace_membership_fixture(workspace, member, "member")

      assert {:error, {:live_redirect, %{to: "/users/settings", flash: flash}}} =
               conn
               |> log_in_user(member)
               |> live(~p"/users/settings/workspaces/#{workspace.slug}/imports")

      assert flash["error"] =~ "You don't have permission to manage this workspace."
    end

    test "redirects an unauthenticated user to login", %{conn: conn} do
      assert {:error, {:redirect, %{to: path}}} =
               live(conn, ~p"/users/settings/workspaces/some-slug/imports")

      assert path == ~p"/users/log-in"
    end
  end

  test "reloads the durable DB list instead of trusting the PubSub payload", %{conn: conn} do
    user = user_fixture()
    workspace = workspace_fixture(user)
    import = workspace_import_fixture(user, workspace)

    {:ok, view, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/users/settings/workspaces/#{workspace.slug}/imports")

    persisted =
      import
      |> change(project_name: "Persisted DB name")
      |> Repo.update!()

    send(
      view.pid,
      {:workspace_snapshot_import_updated, %{persisted | project_name: "Stale payload name"}}
    )

    assert [serialized] = get_imports_vue(view).props["imports"]
    assert serialized["projectName"] == "Persisted DB name"
  end
end
