defmodule Storyarn.Workspaces.Invitations.Commands.AuthorizationConcurrencyTest do
  use ExUnit.Case, async: false

  import Ecto.Query, warn: false
  import Storyarn.AccountsFixtures
  import Storyarn.WorkspacesFixtures

  alias Ecto.Adapters.SQL.Sandbox
  alias Storyarn.Accounts.User
  alias Storyarn.Repo
  alias Storyarn.Workers.DeliverWorkspaceInvitationWorker
  alias Storyarn.Workspaces
  alias Storyarn.Workspaces.Workspace
  alias Storyarn.Workspaces.WorkspaceInvitation
  alias Storyarn.Workspaces.WorkspaceMembership

  @timeout 10_000

  test "create reauthorizes after a concurrent admin removal wins the workspace lock" do
    Sandbox.unboxed_run(Repo, fn ->
      owner = user_fixture()
      workspace = workspace_fixture(owner)
      admin = user_without_workspace()
      admin_membership = workspace_membership_fixture(workspace, admin, "admin")
      email = "removed-admin-create-#{System.unique_integer([:positive])}@example.com"

      try do
        holder = hold_workspace_and_remove_membership(workspace.id, admin_membership.id)
        assert_receive {:workspace_lock_held, holder_pid}, @timeout

        contender =
          start_contender(fn ->
            Workspaces.create_invitation(%{user: admin}, workspace.id, email, "member")
          end)

        assert_receive {:contender_ready, contender_pid, backend_pid}, @timeout
        send(contender_pid, :start)
        assert_connection_waiting_on_lock(backend_pid)

        send(holder_pid, :remove_and_commit)
        assert {:ok, :removed} = Task.await(holder, @timeout)
        assert {:error, :unauthorized} = Task.await(contender, @timeout)

        refute Repo.get_by(WorkspaceInvitation, workspace_id: workspace.id, email: email)

        refute Repo.exists?(
                 from(job in Oban.Job,
                   where: job.worker == ^inspect(DeliverWorkspaceInvitationWorker)
                 )
               )
      after
        cleanup(workspace.id, [owner.id, admin.id])
      end
    end)
  end

  test "revoke reauthorizes after a concurrent admin removal wins the workspace lock" do
    Sandbox.unboxed_run(Repo, fn ->
      owner = user_fixture()
      workspace = workspace_fixture(owner)

      invitation_result =
        Workspaces.create_invitation(
          %{user: owner},
          workspace.id,
          "removed-admin-revoke-#{System.unique_integer([:positive])}@example.com",
          "member"
        )

      admin = user_without_workspace()
      admin_membership = workspace_membership_fixture(workspace, admin, "admin")

      try do
        {:ok, invitation} = invitation_result
        holder = hold_workspace_and_remove_membership(workspace.id, admin_membership.id)

        try do
          assert_receive {:workspace_lock_held, holder_pid}, @timeout

          contender =
            start_contender(fn ->
              Workspaces.revoke_invitation(%{user: admin}, workspace.id, invitation.id)
            end)

          try do
            assert_receive {:contender_ready, contender_pid, backend_pid}, @timeout
            send(contender_pid, :start)
            assert_connection_waiting_on_lock(backend_pid)

            send(holder_pid, :remove_and_commit)
            assert {:ok, :removed} = Task.await(holder, @timeout)
            assert {:error, :unauthorized} = Task.await(contender, @timeout)

            assert Repo.get!(WorkspaceInvitation, invitation.id)
          after
            send(holder.pid, :remove_and_commit)
            send(contender.pid, :start)
            finish_task(holder)
            finish_task(contender)
          end
        after
          send(holder.pid, :remove_and_commit)
          finish_task(holder)
        end
      after
        cleanup(workspace.id, [owner.id, admin.id])
      end
    end)
  end

  defp hold_workspace_and_remove_membership(workspace_id, membership_id) do
    parent = self()

    Task.async(fn ->
      Sandbox.unboxed_run(Repo, fn -> remove_membership_under_workspace_lock(parent, workspace_id, membership_id) end)
    end)
  end

  defp remove_membership_under_workspace_lock(parent, workspace_id, membership_id) do
    Repo.transact(fn ->
      Repo.one!(
        from(workspace in Workspace,
          where: workspace.id == ^workspace_id,
          lock: "FOR UPDATE"
        )
      )

      send(parent, {:workspace_lock_held, self()})

      receive do
        :remove_and_commit ->
          {1, nil} =
            Repo.delete_all(
              from(membership in WorkspaceMembership,
                where: membership.id == ^membership_id
              )
            )

          {:ok, :removed}
      after
        @timeout -> {:error, :holder_timeout}
      end
    end)
  end

  defp start_contender(operation) do
    parent = self()

    Task.async(fn ->
      Sandbox.unboxed_run(Repo, fn ->
        [[backend_pid]] = Repo.query!("SELECT pg_backend_pid()").rows
        send(parent, {:contender_ready, self(), backend_pid})

        receive do
          :start -> operation.()
        after
          @timeout -> {:error, :contender_timeout}
        end
      end)
    end)
  end

  defp assert_connection_waiting_on_lock(backend_pid, attempts \\ 100)

  defp assert_connection_waiting_on_lock(_backend_pid, 0) do
    flunk("invitation command did not wait for the Workspace authorization lock")
  end

  defp assert_connection_waiting_on_lock(backend_pid, attempts) do
    if Repo.query!("SELECT wait_event_type FROM pg_stat_activity WHERE pid = $1", [backend_pid]).rows == [["Lock"]] do
      :ok
    else
      Process.sleep(10)
      assert_connection_waiting_on_lock(backend_pid, attempts - 1)
    end
  end

  defp finish_task(%Task{} = task) do
    if Process.alive?(task.pid) do
      Task.yield(task, @timeout) || Task.shutdown(task, :brutal_kill)
    end

    :ok
  end

  defp user_without_workspace do
    %User{}
    |> User.email_changeset(%{email: unique_user_email()})
    |> User.confirm_changeset()
    |> Repo.insert!()
  end

  defp cleanup(workspace_id, user_ids) do
    Repo.delete_all(Oban.Job)
    {1, nil} = Repo.delete_all(from(workspace in Workspace, where: workspace.id == ^workspace_id))
    Repo.delete_all(from(user in User, where: user.id in ^user_ids))
  end
end
