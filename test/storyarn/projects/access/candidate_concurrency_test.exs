defmodule Storyarn.Projects.CandidateConcurrencyTest do
  use ExUnit.Case, async: false

  import Ecto.Query
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.WorkspacesFixtures

  alias Ecto.Adapters.SQL.Sandbox
  alias Storyarn.Accounts.User
  alias Storyarn.Projects
  alias Storyarn.Projects.Project
  alias Storyarn.Repo
  alias Storyarn.Workspaces
  alias Storyarn.Workspaces.Workspace
  alias Storyarn.Workspaces.WorkspaceMembership

  @timeout 10_000

  setup do
    Sandbox.unboxed_run(Repo, fn ->
      owner = user_fixture()
      workspace = workspace_fixture(owner)
      project = project_fixture(owner, %{workspace: workspace})
      candidate = user_without_workspace()
      actor = user_without_workspace()
      assert candidate.id < actor.id
      candidate_membership = workspace_membership_fixture(workspace, candidate, "member")
      workspace_membership_fixture(workspace, actor, "member")

      on_exit(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          Repo.delete_all(from p in Project, where: p.id == ^project.id)
          Repo.delete_all(from w in Workspace, where: w.id == ^workspace.id)
          Repo.delete_all(from u in User, where: u.id in ^[owner.id, candidate.id, actor.id])
        end)
      end)

      {:ok,
       project: project,
       workspace: workspace,
       owner: user_scope_fixture(owner),
       actor: user_scope_fixture(actor),
       candidate: candidate,
       candidate_membership: candidate_membership}
    end)
  end

  test "a candidate locked by workspace management returns busy without aborting the actor transaction", ctx do
    parent = self()

    actor =
      start_transaction(fn ->
        assert {:ok, _, _} = Projects.authorize_locked(ctx.actor, ctx.project.id, :edit_content)
        send(parent, {:actor_locked, self()})
        await_message(:check_candidate)

        result = Projects.check_editor_candidate_locked(ctx.actor, ctx.project.id, ctx.candidate.id, :nowait)
        assert {:error, :candidate_busy} = result
        assert [[1]] = Repo.query!("SELECT 1").rows
        {:ok, result}
      end)

    try do
      assert_receive {:actor_locked, actor_pid}, @timeout
      removal = start_removal(ctx)

      try do
        assert_receive {:removal_ready, backend_pid}, @timeout
        Sandbox.unboxed_run(Repo, fn -> assert_waiting_on_lock(backend_pid) end)
        send(actor_pid, :check_candidate)

        assert {:ok, {:error, :candidate_busy}} = Task.await(actor, @timeout)
        assert {:ok, _} = Task.await(removal, @timeout)
        assert_ineligible(ctx)
      after
        send(actor.pid, :check_candidate)
        finish_task(actor)
        finish_task(removal)
      end
    after
      send(actor.pid, :check_candidate)
      finish_task(actor)
    end
  end

  test "a successful nonblocking candidate check keeps its membership lock until commit", ctx do
    parent = self()

    actor =
      start_transaction(fn ->
        assert {:ok, true} =
                 Projects.check_editor_candidate_locked(ctx.actor, ctx.project.id, ctx.candidate.id, :nowait)

        send(parent, :candidate_locked)
        await_message(:commit)
        {:ok, :committed}
      end)

    try do
      assert_receive :candidate_locked, @timeout
      removal = start_candidate_downgrade(ctx)

      try do
        assert_receive {:removal_ready, backend_pid}, @timeout
        Sandbox.unboxed_run(Repo, fn -> assert_waiting_on_lock(backend_pid) end)
        send(actor.pid, :commit)

        assert {:ok, :committed} = Task.await(actor, @timeout)
        assert {:ok, _} = Task.await(removal, @timeout)
        assert_ineligible(ctx)
      after
        send(actor.pid, :commit)
        finish_task(actor)
        finish_task(removal)
      end
    after
      send(actor.pid, :commit)
      finish_task(actor)
    end
  end

  defp start_transaction(callback) do
    Task.async(fn -> Sandbox.unboxed_run(Repo, fn -> Repo.transact(callback) end) end)
  end

  defp start_removal(ctx) do
    parent = self()

    Task.async(fn ->
      Sandbox.unboxed_run(Repo, fn ->
        [[backend_pid]] = Repo.query!("SELECT pg_backend_pid()").rows
        send(parent, {:removal_ready, backend_pid})
        Workspaces.remove_member(ctx.owner, ctx.workspace.id, ctx.candidate_membership.id)
      end)
    end)
  end

  defp assert_ineligible(ctx) do
    Sandbox.unboxed_run(Repo, fn ->
      assert {:ok, false} =
               Repo.transact(fn ->
                 Projects.check_editor_candidate_locked(ctx.actor, ctx.project.id, ctx.candidate.id, :nowait)
               end)
    end)
  end

  defp start_candidate_downgrade(ctx) do
    parent = self()
    Task.async(fn -> Sandbox.unboxed_run(Repo, fn -> downgrade_candidate(ctx, parent) end) end)
  end

  defp downgrade_candidate(ctx, parent) do
    [[backend_pid]] = Repo.query!("SELECT pg_backend_pid()").rows
    send(parent, {:removal_ready, backend_pid})

    Repo.transact(fn ->
      {1, nil} =
        Repo.update_all(from(m in WorkspaceMembership, where: m.id == ^ctx.candidate_membership.id),
          set: [role: "viewer"]
        )

      {:ok, :downgraded}
    end)
  end

  defp await_message(message) do
    receive do
      ^message -> :ok
    after
      @timeout -> flunk("candidate transaction was not released")
    end
  end

  defp assert_waiting_on_lock(backend_pid, attempts \\ 100)
  defp assert_waiting_on_lock(_backend_pid, 0), do: flunk("workspace membership removal did not wait on its row lock")

  defp assert_waiting_on_lock(backend_pid, attempts) do
    if Repo.query!("SELECT wait_event_type FROM pg_stat_activity WHERE pid = $1", [backend_pid]).rows == [["Lock"]] do
      :ok
    else
      Process.sleep(10)
      assert_waiting_on_lock(backend_pid, attempts - 1)
    end
  end

  defp finish_task(task) do
    if Process.alive?(task.pid), do: Task.yield(task, @timeout) || Task.shutdown(task, :brutal_kill)
    :ok
  end

  defp user_without_workspace do
    %User{}
    |> User.email_changeset(%{email: unique_user_email()})
    |> User.confirm_changeset()
    |> Repo.insert!()
  end
end
