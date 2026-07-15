defmodule Storyarn.Shared.InvitationConcurrencyTest do
  use ExUnit.Case, async: false

  import Ecto.Query
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.WorkspacesFixtures

  alias Ecto.Adapters.SQL.Sandbox
  alias Storyarn.Billing
  alias Storyarn.Projects
  alias Storyarn.Projects.ProjectInvitation
  alias Storyarn.Repo
  alias Storyarn.Workspaces
  alias Storyarn.Workspaces.Workspace
  alias Storyarn.Workspaces.WorkspaceInvitation

  test "project and workspace invitations serialize the final member seat" do
    Sandbox.unboxed_run(Repo, fn ->
      owner = user_fixture()
      workspace = workspace_fixture(owner)
      project = project_fixture(owner, %{workspace: workspace})

      try do
        parent = self()

        holder = hold_workspace_lock(parent, workspace.id)

        assert_receive {:workspace_lock_held, holder_pid}, 1_000

        invitation_tasks = [
          concurrent_invitation(parent, fn ->
            Projects.create_invitation(
              project,
              owner,
              "project-race@example.com",
              "editor"
            )
          end),
          concurrent_invitation(parent, fn ->
            Workspaces.create_invitation(
              workspace,
              owner,
              "workspace-race@example.com",
              "member"
            )
          end)
        ]

        contenders =
          Enum.map(invitation_tasks, fn _task ->
            assert_receive {:invitation_ready, task_pid, backend_pid}, 1_000
            {task_pid, backend_pid}
          end)

        Enum.each(contenders, fn {task_pid, _backend_pid} -> send(task_pid, :start_invitation) end)
        assert_connections_waiting_on_lock(Enum.map(contenders, &elem(&1, 1)))
        refute_receive {:invitation_finished, _pid, _result}, 50
        send(holder_pid, :release_workspace_lock)
        assert {:ok, :ok} = Task.await(holder, 5_000)

        results = Enum.map(invitation_tasks, &Task.await(&1, 5_000))

        assert Enum.count(results, &match?({:ok, _invitation}, &1)) == 1

        assert Enum.count(results, fn
                 {:error, :limit_reached, %{used: 2, limit: 2}} -> true
                 _ -> false
               end) == 1

        pending_count =
          length(Projects.list_pending_invitations(project.id)) +
            length(Workspaces.list_pending_invitations(workspace.id))

        assert pending_count == 1
      after
        Repo.delete_all(Oban.Job)
        Repo.delete!(workspace)
        Repo.delete!(owner)
      end
    end)
  end

  test "legacy project and workspace invitations cannot overfill the plan when accepted concurrently" do
    Sandbox.unboxed_run(Repo, fn ->
      owner = user_fixture()
      first_invitee = user_fixture()
      second_invitee = user_fixture()
      workspace = workspace_fixture(owner)
      project = project_fixture(owner, %{workspace: workspace})

      {_first_token, first_invitation} =
        ProjectInvitation.build_invitation(
          project,
          owner,
          first_invitee.email,
          "editor"
        )

      first_invitation = Repo.insert!(first_invitation)

      {_second_token, second_invitation} =
        WorkspaceInvitation.build_invitation(
          workspace,
          owner,
          second_invitee.email,
          "member"
        )

      second_invitation = Repo.insert!(second_invitation)

      try do
        parent = self()
        holder = hold_workspace_lock(parent, workspace.id)

        assert_receive {:workspace_lock_held, holder_pid}, 1_000

        acceptance_tasks = [
          concurrent_invitation(parent, fn ->
            Projects.accept_invitation(first_invitation, first_invitee)
          end),
          concurrent_invitation(parent, fn ->
            Workspaces.accept_invitation(second_invitation, second_invitee)
          end)
        ]

        contenders =
          Enum.map(acceptance_tasks, fn _task ->
            assert_receive {:invitation_ready, task_pid, backend_pid}, 1_000
            {task_pid, backend_pid}
          end)

        Enum.each(contenders, fn {task_pid, _backend_pid} -> send(task_pid, :start_invitation) end)
        assert_connections_waiting_on_lock(Enum.map(contenders, &elem(&1, 1)))
        send(holder_pid, :release_workspace_lock)
        assert {:ok, :ok} = Task.await(holder, 5_000)

        results = Enum.map(acceptance_tasks, &Task.await(&1, 5_000))

        assert Enum.count(results, &match?({:ok, _membership}, &1)) == 1

        assert Enum.count(results, fn
                 {:error, :limit_reached, %{used: 2, limit: 2}} -> true
                 _ -> false
               end) == 1

        assert Billing.count_unique_workspace_users(workspace.id) == 2

        accepted_count =
          Enum.count(
            [Repo.get!(ProjectInvitation, first_invitation.id), Repo.get!(WorkspaceInvitation, second_invitation.id)],
            & &1.accepted_at
          )

        assert accepted_count == 1
      after
        Repo.delete_all(Oban.Job)

        owner_ids = [owner.id, first_invitee.id, second_invitee.id]
        Repo.delete_all(from(owned_workspace in Workspace, where: owned_workspace.owner_id in ^owner_ids))

        Repo.delete!(first_invitee)
        Repo.delete!(second_invitee)
        Repo.delete!(owner)
      end
    end)
  end

  defp hold_workspace_lock(parent, workspace_id) do
    Task.async(fn ->
      Sandbox.unboxed_run(Repo, fn ->
        hold_workspace_lock_transaction(parent, workspace_id)
      end)
    end)
  end

  defp hold_workspace_lock_transaction(parent, workspace_id) do
    Repo.transaction(fn ->
      Repo.one!(
        from(locked_workspace in Workspace,
          where: locked_workspace.id == ^workspace_id,
          lock: "FOR UPDATE"
        )
      )

      send(parent, {:workspace_lock_held, self()})

      receive do
        :release_workspace_lock -> :ok
      end
    end)
  end

  defp concurrent_invitation(parent, invitation_fun) do
    Task.async(fn ->
      Sandbox.unboxed_run(Repo, fn ->
        [[backend_pid]] = Repo.query!("SELECT pg_backend_pid()").rows
        send(parent, {:invitation_ready, self(), backend_pid})

        receive do
          :start_invitation -> :ok
        end

        result = invitation_fun.()
        send(parent, {:invitation_finished, self(), result})
        result
      end)
    end)
  end

  defp assert_connections_waiting_on_lock(backend_pids, attempts \\ 100)

  defp assert_connections_waiting_on_lock(_backend_pids, 0) do
    flunk("invitation transactions did not block on the workspace lock")
  end

  defp assert_connections_waiting_on_lock(backend_pids, attempts) do
    all_waiting? =
      Enum.all?(backend_pids, fn backend_pid ->
        Repo.query!(
          "SELECT wait_event_type FROM pg_stat_activity WHERE pid = $1",
          [backend_pid]
        ).rows == [["Lock"]]
      end)

    if all_waiting? do
      :ok
    else
      Process.sleep(10)
      assert_connections_waiting_on_lock(backend_pids, attempts - 1)
    end
  end
end
