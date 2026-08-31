defmodule Storyarn.AI.Governance.AuthorizationLockOrderTest do
  use ExUnit.Case, async: false

  import Ecto.Query, warn: false
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.WorkspacesFixtures

  alias Ecto.Adapters.SQL.Sandbox
  alias Storyarn.Accounts.User
  alias Storyarn.AI.ExecutionIntent
  alias Storyarn.AI.Governance
  alias Storyarn.AI.PolicyDecision
  alias Storyarn.AI.Task, as: AITask
  alias Storyarn.AI.WorkspacePolicy
  alias Storyarn.Projects.ProjectMembership
  alias Storyarn.Repo
  alias Storyarn.Workspaces.Workspace
  alias Storyarn.Workspaces.WorkspaceMembership
  alias StoryarnTest.AI.ContractTask

  @timeout 15_000
  @blocked_timeout 5_000

  test "locked project authorization follows Workspace -> Project -> memberships order" do
    Sandbox.unboxed_run(Repo, fn ->
      owner =
        user_fixture(%{
          email: "ai-authorization-lock-order-#{Ecto.UUID.generate()}@example.com"
        })

      scope = user_scope_fixture(owner)
      workspace = workspace_fixture(owner)
      project = project_fixture(owner, %{workspace: workspace})
      project_membership = Repo.get_by!(ProjectMembership, project_id: project.id, user_id: owner.id)
      workspace_membership = Repo.get_by!(WorkspaceMembership, workspace_id: workspace.id, user_id: owner.id)

      FunWithFlags.enable(:ai_integrations, for_actor: owner)

      %WorkspacePolicy{workspace_id: workspace.id}
      |> WorkspacePolicy.changeset(%{
        allowed_lanes: ["managed"],
        version: 1,
        updated_by_id: owner.id
      })
      |> Repo.insert!()

      assert {:ok, task} = AITask.new(ContractTask, ContractTask.definition())

      assert {:ok, intent} =
               ExecutionIntent.new(scope, %{
                 workspace_id: workspace.id,
                 project_id: project.id,
                 task_id: task.id,
                 input: %{"text" => "lock order"}
               })

      parent = self()
      barrier = make_ref()

      project_gate =
        start_row_gate("projects", project.id, parent, barrier, :project_locked, :release_project)

      project_membership_gate =
        start_row_gate(
          "project_memberships",
          project_membership.id,
          parent,
          barrier,
          :project_membership_locked,
          :release_project_membership
        )

      try do
        assert_receive {^barrier, :project_locked, project_gate_backend_pid}, @timeout

        assert_receive {^barrier, :project_membership_locked, project_membership_gate_backend_pid},
                       @timeout

        authorization = start_authorization(intent, task, parent, barrier)

        try do
          assert_receive {^barrier, :authorization_ready, authorization_backend_pid}, @timeout

          assert wait_until_blocked_by(authorization_backend_pid, project_gate_backend_pid),
                 "AI authorization did not block behind the Project gate"

          assert :lock_unavailable = update_lock_nowait("workspaces", workspace.id)

          send(project_gate.pid, {barrier, :release_project})
          assert {:ok, :released} = Task.await(project_gate, @timeout)

          assert wait_until_blocked_by(authorization_backend_pid, project_membership_gate_backend_pid),
                 "AI authorization did not reach the ProjectMembership gate"

          assert :lock_unavailable =
                   update_lock_nowait("workspace_memberships", workspace_membership.id)

          send(project_membership_gate.pid, {barrier, :release_project_membership})
          assert {:ok, :released} = Task.await(project_membership_gate, @timeout)

          assert {:ok, %PolicyDecision{actor_id: actor_id}} = Task.await(authorization, @timeout)
          assert actor_id == owner.id
        after
          finish_task(authorization)
        end
      after
        send(project_gate.pid, {barrier, :release_project})
        send(project_membership_gate.pid, {barrier, :release_project_membership})
        finish_task(project_gate)
        finish_task(project_membership_gate)
        FunWithFlags.disable(:ai_integrations, for_actor: owner)
        cleanup(workspace.id, owner.id)
      end
    end)
  end

  defp start_authorization(intent, task, parent, barrier) do
    Task.async(fn -> run_authorization(intent, task, parent, barrier) end)
  end

  defp run_authorization(intent, task, parent, barrier) do
    Sandbox.unboxed_run(Repo, fn ->
      authorize_with_backend_pid(intent, task, parent, barrier)
    end)
  end

  defp authorize_with_backend_pid(intent, task, parent, barrier) do
    [[backend_pid]] = Repo.query!("SELECT pg_backend_pid()").rows
    send(parent, {barrier, :authorization_ready, backend_pid})

    Repo.transact(fn ->
      Governance.authorize(intent, task, :execute, lane: :managed, lock_policy: true)
    end)
  end

  defp start_row_gate(table, row_id, parent, barrier, locked_message, release_message) do
    Task.async(fn ->
      run_row_gate(table, row_id, parent, barrier, locked_message, release_message)
    end)
  end

  defp run_row_gate(table, row_id, parent, barrier, locked_message, release_message) do
    Sandbox.unboxed_run(Repo, fn ->
      hold_row_gate(table, row_id, parent, barrier, locked_message, release_message)
    end)
  end

  defp hold_row_gate(table, row_id, parent, barrier, locked_message, release_message) do
    Repo.transaction(fn ->
      [[backend_pid]] = Repo.query!("SELECT pg_backend_pid()").rows
      lock_row!(table, row_id)
      send(parent, {barrier, locked_message, backend_pid})
      await_row_gate_release(barrier, release_message, locked_message)
    end)
  end

  defp await_row_gate_release(barrier, release_message, locked_message) do
    receive do
      {^barrier, ^release_message} ->
        :released
    after
      @timeout ->
        exit({:row_gate_release_timeout, locked_message})
    end
  end

  defp lock_row!("projects", row_id) do
    %{num_rows: 1} = Repo.query!("SELECT id FROM projects WHERE id = $1 FOR UPDATE", [row_id])
  end

  defp lock_row!("project_memberships", row_id) do
    %{num_rows: 1} =
      Repo.query!("SELECT id FROM project_memberships WHERE id = $1 FOR UPDATE", [row_id])
  end

  defp update_lock_nowait(table, row_id) do
    fn -> run_update_lock_nowait(table, row_id) end
    |> Task.async()
    |> Task.await(@timeout)
  end

  defp run_update_lock_nowait(table, row_id) do
    Sandbox.unboxed_run(Repo, fn -> attempt_update_lock_nowait(table, row_id) end)
  end

  defp attempt_update_lock_nowait(table, row_id) do
    acquire_update_lock_nowait(table, row_id)
    :available
  rescue
    error in Postgrex.Error -> handle_update_lock_error(error, __STACKTRACE__)
  end

  defp acquire_update_lock_nowait(table, row_id) do
    Repo.transaction(fn -> lock_row_nowait!(table, row_id) end)
  end

  defp handle_update_lock_error(%Postgrex.Error{postgres: %{code: :lock_not_available}}, _stacktrace),
    do: :lock_unavailable

  defp handle_update_lock_error(error, stacktrace), do: reraise(error, stacktrace)

  defp lock_row_nowait!("workspaces", row_id) do
    %{num_rows: 1} =
      Repo.query!("SELECT id FROM workspaces WHERE id = $1 FOR UPDATE NOWAIT", [row_id])
  end

  defp lock_row_nowait!("workspace_memberships", row_id) do
    %{num_rows: 1} =
      Repo.query!("SELECT id FROM workspace_memberships WHERE id = $1 FOR UPDATE NOWAIT", [row_id])
  end

  defp wait_until_blocked_by(blocked_backend_pid, blocker_backend_pid) do
    deadline = System.monotonic_time(:millisecond) + @blocked_timeout
    do_wait_until_blocked_by(blocked_backend_pid, blocker_backend_pid, deadline)
  end

  defp do_wait_until_blocked_by(blocked_backend_pid, blocker_backend_pid, deadline) do
    if backend_blocked_by?(blocked_backend_pid, blocker_backend_pid) do
      true
    else
      if System.monotonic_time(:millisecond) >= deadline do
        false
      else
        Process.sleep(10)
        do_wait_until_blocked_by(blocked_backend_pid, blocker_backend_pid, deadline)
      end
    end
  end

  defp backend_blocked_by?(blocked_backend_pid, blocker_backend_pid) do
    case Repo.query!(
           """
           SELECT wait_event_type,
                  $2::integer = ANY(pg_blocking_pids(pid)) AS blocked_by_gate
           FROM pg_stat_activity
           WHERE pid = $1::integer
           """,
           [blocked_backend_pid, blocker_backend_pid]
         ).rows do
      [["Lock", true]] -> true
      _other -> false
    end
  end

  defp finish_task(%Task{} = task) do
    if Process.alive?(task.pid) do
      Task.yield(task, @timeout) || Task.shutdown(task, :brutal_kill)
    end

    :ok
  end

  defp cleanup(workspace_id, user_id) do
    Repo.delete_all(from(workspace in Workspace, where: workspace.id == ^workspace_id))
    Repo.delete_all(from(user in User, where: user.id == ^user_id))
  end
end
