defmodule Storyarn.Projects.ProjectDeletionStorageLockConcurrencyTest do
  use ExUnit.Case, async: false

  import Ecto.Query
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  alias Ecto.Adapters.SQL.Sandbox
  alias Storyarn.Accounts.User
  alias Storyarn.Platform.Billing
  alias Storyarn.Projects
  alias Storyarn.Projects.Project
  alias Storyarn.Repo
  alias Storyarn.Workspaces.Workspace

  @timeout 10_000

  test "soft deletion waits for the persisted project's workspace accounting lock" do
    %{user: user, project: project, workspace: workspace} = setup_fixture()
    on_exit(fn -> cleanup_fixture(user, project, workspace) end)

    stale_project = %{project | workspace_id: workspace.id + 1_000_000}

    assert {:ok, %Project{deleted_at: %DateTime{}}} =
             delete_while_workspace_locked(workspace.id, fn ->
               Projects.delete_project(stale_project, user.id)
             end)

    assert %Project{deleted_at: %DateTime{}} =
             Sandbox.unboxed_run(Repo, fn -> Repo.get!(Project, project.id) end)
  end

  test "permanent deletion waits for the persisted project's workspace accounting lock" do
    %{user: user, project: project, workspace: workspace} = setup_fixture()
    on_exit(fn -> cleanup_fixture(user, project, workspace) end)

    stale_project = %{project | workspace_id: workspace.id + 1_000_000}

    assert {:ok, %Project{id: project_id}} =
             delete_while_workspace_locked(workspace.id, fn ->
               Projects.permanently_delete_project(stale_project)
             end)

    assert project_id == project.id
    refute Sandbox.unboxed_run(Repo, fn -> Repo.get(Project, project.id) end)
  end

  defp setup_fixture do
    Sandbox.unboxed_run(Repo, fn ->
      user =
        user_fixture(%{
          email: "project-deletion-lock-#{Ecto.UUID.generate()}@example.com"
        })

      project = project_fixture(user)
      workspace = Repo.get!(Workspace, project.workspace_id)

      %{user: user, project: project, workspace: workspace}
    end)
  end

  defp delete_while_workspace_locked(workspace_id, delete_fun) do
    parent = self()
    barrier = make_ref()
    holder = workspace_lock_holder(workspace_id, parent, barrier)

    assert_receive {^barrier, :workspace_locked, holder_pid}, @timeout

    deletion = deletion_task(delete_fun, parent, barrier)
    assert_receive {^barrier, :deletion_ready, deletion_pid}, @timeout
    send(deletion_pid, {barrier, :delete})

    assert Task.yield(deletion, 250) == nil

    send(holder_pid, {barrier, :release_workspace})
    assert {:ok, :workspace_released} = Task.await(holder, @timeout)

    Task.await(deletion, @timeout)
  end

  defp workspace_lock_holder(workspace_id, parent, barrier) do
    Task.async(fn ->
      :ok = Sandbox.checkout(Repo, sandbox: false)

      try do
        Billing.transact_with_workspace_lock(workspace_id, fn _workspace ->
          send(parent, {barrier, :workspace_locked, self()})

          receive do
            {^barrier, :release_workspace} -> {:ok, :workspace_released}
          after
            @timeout -> {:error, :workspace_lock_timeout}
          end
        end)
      after
        Sandbox.checkin(Repo)
      end
    end)
  end

  defp deletion_task(delete_fun, parent, barrier) do
    Task.async(fn ->
      :ok = Sandbox.checkout(Repo, sandbox: false)

      try do
        send(parent, {barrier, :deletion_ready, self()})

        receive do
          {^barrier, :delete} -> delete_fun.()
        after
          @timeout -> {:error, :deletion_start_timeout}
        end
      after
        Sandbox.checkin(Repo)
      end
    end)
  end

  defp cleanup_fixture(user, project, workspace) do
    Sandbox.unboxed_run(Repo, fn ->
      Repo.delete_all(from(current in Project, where: current.id == ^project.id))
      Repo.delete_all(from(current in Workspace, where: current.id == ^workspace.id))
      Repo.delete_all(from(current in User, where: current.id == ^user.id))
    end)
  end
end
