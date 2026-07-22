defmodule Storyarn.Projects.RestorationLockConcurrencyTest do
  use ExUnit.Case, async: false

  import Ecto.Query
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  alias Ecto.Adapters.SQL.Sandbox
  alias Storyarn.Accounts.User
  alias Storyarn.Projects
  alias Storyarn.Projects.Project
  alias Storyarn.Repo
  alias Storyarn.Versioning
  alias Storyarn.Versioning.SnapshotStorage
  alias Storyarn.Workspaces.Workspace

  @timeout 10_000

  test "two concurrent jobs carrying the same token cannot both claim the restore" do
    %{user: user, project: project, snapshot: snapshot, lock: lock} =
      Sandbox.unboxed_run(Repo, fn ->
        user =
          user_fixture(%{
            email: "restore-fence-#{Ecto.UUID.generate()}@example.com"
          })

        project = project_fixture(user)
        {:ok, snapshot} = Versioning.create_project_snapshot(project.id, user.id)

        {:ok, lock} =
          Projects.acquire_restoration_lock(
            project.id,
            user.id,
            snapshot.id
          )

        %{user: user, project: project, snapshot: snapshot, lock: lock}
      end)

    on_exit(fn ->
      cleanup_restore_fixture(user, project, snapshot, lock.restoration_token)
    end)

    parent = self()
    barrier = make_ref()

    claim = fn job_id ->
      Task.async(fn ->
        :ok = Sandbox.checkout(Repo, sandbox: false)

        try do
          send(parent, {barrier, :ready, self()})

          receive do
            {^barrier, :claim} ->
              Projects.claim_restoration_lock(
                project.id,
                user.id,
                snapshot.id,
                lock.restoration_token,
                job_id
              )
          after
            @timeout -> exit(:claim_barrier_timeout)
          end
        after
          Sandbox.checkin(Repo)
        end
      end)
    end

    first = claim.(101)
    second = claim.(202)

    assert_receive {^barrier, :ready, first_pid}, @timeout
    assert_receive {^barrier, :ready, second_pid}, @timeout

    send(first_pid, {barrier, :claim})
    send(second_pid, {barrier, :claim})

    results = [
      Task.await(first, @timeout),
      Task.await(second, @timeout)
    ]

    assert Enum.count(results, &match?({:ok, %Project{}}, &1)) == 1
    assert Enum.count(results, &match?({:error, :already_claimed}, &1)) == 1

    claimed_job_ids =
      for {:ok, %Project{} = claimed_project} <- results do
        claimed_project.restoration_claimed_by_job_id
      end

    assert claimed_job_ids in [[101], [202]]

    persisted =
      Sandbox.unboxed_run(Repo, fn ->
        Repo.get!(Project, project.id)
      end)

    assert [persisted.restoration_claimed_by_job_id] == claimed_job_ids
  end

  defp cleanup_restore_fixture(user, project, snapshot, token) do
    Sandbox.unboxed_run(Repo, fn ->
      case Repo.get(Project, project.id) do
        %Project{restoration_claimed_by_job_id: nil} ->
          Projects.release_restoration_lock(project.id, token)

        %Project{restoration_claimed_by_job_id: job_id} ->
          Projects.release_restoration_lock(project.id, token, job_id)

        nil ->
          :ok
      end

      SnapshotStorage.delete_snapshot(snapshot.storage_key)
      Repo.delete_all(from(current in Project, where: current.id == ^project.id))
      Repo.delete_all(from(workspace in Workspace, where: workspace.id == ^project.workspace_id))
      Repo.delete_all(from(current in User, where: current.id == ^user.id))
    end)
  end
end
