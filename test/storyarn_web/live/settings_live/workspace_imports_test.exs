defmodule StoryarnWeb.SettingsLive.WorkspaceImportsTest do
  use StoryarnWeb.ConnCase, async: false

  import Ecto.Changeset
  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.WorkspacesFixtures

  alias Phoenix.LiveView.Channel
  alias Phoenix.LiveView.Socket
  alias Storyarn.Projects.Assets.Storage
  alias Storyarn.Projects.Versioning.WorkspaceSnapshotImport
  alias Storyarn.Repo
  alias StoryarnWeb.SettingsLive.WorkspaceImports

  require Phoenix.ChannelTest

  defp get_imports_vue(view) do
    LiveVue.Test.get_vue(view, name: "live/workspace/settings/WorkspaceSettingsImports")
  end

  defp workspace_import_fixture(user, workspace, attrs \\ %{}) do
    checksum = String.duplicate("a", 64)
    {:ok, fingerprint} = Storage.namespace_fingerprint()

    defaults = %{
      workspace_id: workspace.id,
      user_id: user.id,
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

    %WorkspaceSnapshotImport{provider_namespace_fingerprint: fingerprint}
    |> WorkspaceSnapshotImport.upload_changeset(Map.merge(defaults, attrs))
    |> WorkspaceSnapshotImport.admit_changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  describe "mount" do
    test "uses server uploads even with external storage without reducing the archive limit", %{conn: conn} do
      original_storage = Application.get_env(:storyarn, :storage)
      Application.put_env(:storyarn, :storage, adapter: :r2)

      on_exit(fn ->
        if is_nil(original_storage),
          do: Application.delete_env(:storyarn, :storage),
          else: Application.put_env(:storyarn, :storage, original_storage)
      end)

      user = user_fixture()
      workspace = workspace_fixture(user)

      {:ok, view, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/users/settings/workspaces/#{workspace.slug}/imports")

      assert {:ok, upload} = Channel.fetch_upload_config(view.pid, :snapshot_zip, nil)
      assert upload.external == false
      assert upload.max_entries == 1
      assert upload.max_file_size == Storyarn.Projects.project_snapshot_archive_max_size_bytes()
      assert get_imports_vue(view).props["request-error-code"] == nil
    end

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

  describe "upload cancellation" do
    setup %{conn: conn} do
      user = user_fixture()
      workspace = workspace_fixture(user)

      {:ok, view, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/users/settings/workspaces/#{workspace.slug}/imports")

      %{view: view, user: user, workspace: workspace}
    end

    test "ignores unknown upload references", %{view: view} do
      render_hook(view, "cancel-upload", %{"ref" => "missing-upload"})
      render_hook(view, "cancel-upload", %{"ref" => "missing-upload"})

      assert Process.alive?(view.pid)
      assert get_imports_vue(view).props["imports"] == []
      assert Repo.aggregate(WorkspaceSnapshotImport, :count) == 0
    end

    test "does not cancel an already cancelled upload channel again", %{user: user, workspace: workspace} do
      entry = %Phoenix.LiveView.UploadEntry{ref: "cancelled-upload", cancelled?: true}

      upload = %Phoenix.LiveView.UploadConfig{
        name: :snapshot_zip,
        entries: [entry],
        entry_refs_to_pids: %{entry.ref => self()}
      }

      socket = %Socket{
        assigns: %{
          __changed__: %{},
          current_scope: user_scope_fixture(user),
          workspace: workspace,
          uploads: %{snapshot_zip: upload}
        }
      }

      assert {:noreply, updated} = WorkspaceImports.handle_event("cancel-upload", %{"ref" => entry.ref}, socket)
      assert updated.assigns.uploads.snapshot_zip == upload
      assert updated.assigns.imports == []
    end

    test "repeated cancellation removes the local temporary upload without creating an import or job", %{view: view} do
      job_count = Repo.aggregate(Oban.Job, :count)
      {entry_ref, channel, path} = start_partial_snapshot_upload(view)
      channel_monitor = Process.monitor(channel.channel_pid)

      assert File.read!(path) == "partial archive"
      render_hook(view, "cancel-upload", %{"ref" => entry_ref})
      render_hook(view, "cancel-upload", %{"ref" => entry_ref})

      assert_receive {:DOWN, ^channel_monitor, :process, _pid, _reason}, 1_000
      assert_file_removed(path)
      assert Process.alive?(view.pid)
      assert get_imports_vue(view).props["imports"] == []
      assert Repo.aggregate(WorkspaceSnapshotImport, :count) == 0
      assert Repo.aggregate(Oban.Job, :count) == job_count
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

  defp start_partial_snapshot_upload(view) do
    {:ok, upload} = Channel.fetch_upload_config(view.pid, :snapshot_zip, nil)
    ref = "partial-upload"
    entry = %{"ref" => ref, "name" => "project.zip", "size" => 1_024, "type" => "application/zip"}
    {_proxy_ref, topic, proxy_pid} = view.proxy

    # LiveVue creates the file input in the browser, so there is no server-rendered
    # input for file_input/4. Use its same preflight protocol and a real upload channel.
    assert {:ok, %{entries: %{^ref => token}}} =
             GenServer.call(proxy_pid, {:render_allow_upload, topic, upload.ref, {[entry], nil}})

    {:ok, socket} = Phoenix.ChannelTest.connect(Socket, %{})
    {:ok, _reply, channel} = Phoenix.ChannelTest.subscribe_and_join(socket, "lvu:partial-upload", %{"token" => token})
    Process.unlink(channel.channel_pid)
    chunk_ref = Phoenix.ChannelTest.push(channel, "chunk", {:binary, "partial archive"})
    assert_receive %Phoenix.Socket.Reply{ref: ^chunk_ref, status: :ok}, 1_000

    {ref, channel, channel.assigns.writer_state.path}
  end

  defp assert_file_removed(path, attempts \\ 100) do
    if File.exists?(path) and attempts > 0 do
      Process.sleep(10)
      assert_file_removed(path, attempts - 1)
    else
      refute File.exists?(path)
    end
  end
end
