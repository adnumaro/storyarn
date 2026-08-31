defmodule Storyarn.Projects.Lifecycle.Commands.ProjectCreationAuthorizationConcurrencyTest do
  use ExUnit.Case, async: false

  import Ecto.Query, warn: false
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.WorkspacesFixtures

  alias Ecto.Adapters.SQL.Sandbox
  alias Storyarn.Accounts.Scope
  alias Storyarn.Accounts.User
  alias Storyarn.Projects
  alias Storyarn.Projects.Project
  alias Storyarn.Repo
  alias Storyarn.Workspaces.Workspace
  alias Storyarn.Workspaces.WorkspaceMembership

  @timeout 10_000

  test "project-only Workspace access remains unauthorized rather than hidden" do
    Sandbox.unboxed_run(Repo, fn ->
      owner = user_fixture()
      project_only_member = user_fixture()
      workspace = workspace_fixture(owner)

      try do
        project = project_fixture(owner, %{workspace: workspace})
        _membership = membership_fixture(project, project_only_member, "editor")

        assert {:error, :unauthorized} =
                 Projects.create_project(Scope.for_user(project_only_member), %{
                   name: "Disallowed through virtual membership",
                   workspace_id: workspace.id,
                   project_type: "game",
                   project_subtype: "rpg"
                 })
      after
        cleanup([owner.id, project_only_member.id])
      end
    end)
  end

  test "a committed workspace-role demotion wins before project creation authorization" do
    Sandbox.unboxed_run(Repo, fn ->
      owner = user_fixture()
      member = user_fixture()
      workspace = workspace_fixture(owner)
      membership = workspace_membership_fixture(workspace, member, "member")
      scope = Scope.for_user(member)
      project_name = "Denied after concurrent demotion"
      parent = self()
      barrier = make_ref()

      demotion = hold_committing_demotion(parent, barrier, workspace.id, membership.id)

      try do
        assert_receive {^barrier, :demotion_ready, demotion_pid}, @timeout

        {creation, creation_pid, creation_backend_pid} =
          start_observed_creation(parent, barrier, fn ->
            Projects.create_project(scope, %{
              name: project_name,
              workspace_id: workspace.id,
              project_type: "game",
              project_subtype: "rpg"
            })
          end)

        try do
          send(creation_pid, {barrier, :start_creation})
          assert_connection_waiting_on_lock(creation_backend_pid)

          send(demotion_pid, {barrier, :commit_demotion})

          assert {:ok, :demoted} = Task.await(demotion, @timeout)
          assert {:error, :unauthorized} = Task.await(creation, @timeout)

          refute Repo.exists?(
                   from(project in Project,
                     where: project.workspace_id == ^workspace.id and project.name == ^project_name
                   )
                 )
        after
          send(demotion_pid, {barrier, :commit_demotion})

          if Process.alive?(creation.pid), do: Task.shutdown(creation, :brutal_kill)
        end
      after
        if Process.alive?(demotion.pid), do: Task.shutdown(demotion, :brutal_kill)

        cleanup([owner.id, member.id])
      end
    end)
  end

  defp hold_committing_demotion(parent, barrier, workspace_id, membership_id) do
    Task.async(fn -> run_committing_demotion(parent, barrier, workspace_id, membership_id) end)
  end

  defp run_committing_demotion(parent, barrier, workspace_id, membership_id) do
    Sandbox.unboxed_run(Repo, fn ->
      Repo.transact(fn ->
        Repo.one!(
          from(workspace in Workspace,
            where: workspace.id == ^workspace_id,
            lock: "FOR UPDATE"
          )
        )

        membership =
          Repo.one!(
            from(candidate in WorkspaceMembership,
              where: candidate.id == ^membership_id and candidate.workspace_id == ^workspace_id,
              lock: "FOR UPDATE"
            )
          )

        {:ok, _membership} =
          membership
          |> Ecto.Changeset.change(%{role: "viewer"})
          |> Repo.update()

        send(parent, {barrier, :demotion_ready, self()})

        receive do
          {^barrier, :commit_demotion} -> {:ok, :demoted}
        after
          @timeout -> {:error, :demotion_commit_timeout}
        end
      end)
    end)
  end

  defp start_observed_creation(parent, barrier, operation) do
    task =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          [[backend_pid]] = Repo.query!("SELECT pg_backend_pid()").rows
          send(parent, {barrier, :creation_ready, self(), backend_pid})

          receive do
            {^barrier, :start_creation} -> operation.()
          after
            @timeout -> {:error, :creation_start_timeout}
          end
        end)
      end)

    assert_receive {^barrier, :creation_ready, task_pid, backend_pid}, @timeout
    {task, task_pid, backend_pid}
  end

  defp assert_connection_waiting_on_lock(backend_pid, attempts \\ div(@timeout, 10))

  defp assert_connection_waiting_on_lock(_backend_pid, 0) do
    flunk("project creation did not wait for the Workspace authorization lock")
  end

  defp assert_connection_waiting_on_lock(backend_pid, attempts) do
    if Repo.query!("SELECT wait_event_type FROM pg_stat_activity WHERE pid = $1", [backend_pid]).rows ==
         [["Lock"]] do
      :ok
    else
      Process.sleep(10)
      assert_connection_waiting_on_lock(backend_pid, attempts - 1)
    end
  end

  defp cleanup(user_ids) do
    Repo.delete_all(from(workspace in Workspace, where: workspace.owner_id in ^user_ids))
    Repo.delete_all(from(user in User, where: user.id in ^user_ids))
  end
end
