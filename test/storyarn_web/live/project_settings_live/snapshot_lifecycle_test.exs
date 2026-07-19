defmodule StoryarnWeb.ProjectSettingsLive.SnapshotLifecycleTest do
  use Storyarn.DataCase, async: false
  use Oban.Testing, repo: Storyarn.Repo

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  alias Phoenix.LiveView.Socket
  alias Storyarn.Accounts.Scope
  alias Storyarn.Collaboration
  alias Storyarn.Projects
  alias Storyarn.Versioning
  alias Storyarn.Versioning.RestorePolicy
  alias Storyarn.Workers.RestoreProjectWorker
  alias StoryarnWeb.ProjectLive.Components.SettingsComponents

  setup do
    original_policy = Application.get_env(:storyarn, RestorePolicy)

    Application.put_env(
      :storyarn,
      RestorePolicy,
      sheet_version_restore: true,
      flow_version_restore: true,
      scene_version_restore: true,
      project_snapshot_restore: true,
      deleted_project_recovery: false
    )

    on_exit(fn ->
      if is_nil(original_policy) do
        Application.delete_env(:storyarn, RestorePolicy)
      else
        Application.put_env(:storyarn, RestorePolicy, original_policy)
      end
    end)

    user = user_fixture()
    project = project_fixture(user)

    {:ok, snapshot} =
      Versioning.create_project_snapshot(project.id, user.id, title: "Lifecycle failure")

    Collaboration.subscribe_restoration(project.id)

    socket = %Socket{
      assigns: %{
        __changed__: %{},
        flash: %{},
        current_scope: Scope.for_user(user),
        project: project,
        restoration_in_progress: false
      }
    }

    %{project: project, snapshot: snapshot, socket: socket}
  end

  test "returned enqueue errors publish a terminal failure and release the lock", context do
    assert_enqueue_failure(context, fn _project_id, _snapshot_id, _user_id ->
      {:error, :queue_unavailable}
    end)
  end

  test "enqueue exceptions publish a terminal failure and release the lock", context do
    assert_enqueue_failure(context, fn _project_id, _snapshot_id, _user_id ->
      raise "queue unavailable"
    end)
  end

  test "enqueue exits publish a terminal failure and release the lock", context do
    assert_enqueue_failure(context, fn _project_id, _snapshot_id, _user_id ->
      exit(:queue_unavailable)
    end)
  end

  defp assert_enqueue_failure(%{project: project, snapshot: snapshot, socket: socket}, enqueue_fun) do
    assert {:noreply, result_socket} =
             SettingsComponents.do_restore_snapshot(socket, snapshot.id, enqueue_fun: enqueue_fun)

    refute result_socket.assigns.restoration_in_progress
    refute Projects.restoration_in_progress?(project.id)
    refute_enqueued(worker: RestoreProjectWorker)

    assert {:project_restoration_started, _payload} = receive_restoration_event()

    assert {:project_restoration_failed, %{reason: :enqueue_failed}} =
             receive_restoration_event()

    refute_receive {:project_restoration_completed, _payload}
  end

  defp receive_restoration_event do
    receive do
      {:project_restoration_started, _payload} = event -> event
      {:project_restoration_completed, _payload} = event -> event
      {:project_restoration_failed, _payload} = event -> event
    after
      1_000 -> flunk("expected a project restoration lifecycle event")
    end
  end
end
