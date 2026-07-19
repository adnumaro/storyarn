defmodule Storyarn.Versioning.ProjectSnapshotRestoreConcurrencyTest do
  use ExUnit.Case, async: false

  import Ecto.Query
  import Storyarn.AccountsFixtures
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures

  alias Ecto.Adapters.SQL.Sandbox
  alias Storyarn.Accounts.User
  alias Storyarn.Projects.Project
  alias Storyarn.Repo
  alias Storyarn.Versioning.Builders.ProjectSnapshotBuilder
  alias Storyarn.Workspaces.Workspace

  @timeout 15_000
  @blocked_timeout 5_000

  test "an empty-root localization restore locks the project before its child tables" do
    %{user: user, project: project, snapshot: snapshot} =
      Sandbox.unboxed_run(Repo, fn ->
        user =
          user_fixture(%{
            email: "project-snapshot-lock-#{Ecto.UUID.generate()}@example.com"
          })

        project = project_fixture(user)
        _source = source_language_fixture(project, %{locale_code: "en", name: "English"})

        %{
          user: user,
          project: project,
          snapshot: ProjectSnapshotBuilder.build_snapshot(project.id)
        }
      end)

    on_exit(fn ->
      Sandbox.unboxed_run(Repo, fn ->
        Repo.delete_all(from(current in Project, where: current.id == ^project.id))
        Repo.delete_all(from(workspace in Workspace, where: workspace.id == ^project.workspace_id))
        Repo.delete_all(from(current in User, where: current.id == ^user.id))
      end)
    end)

    assert snapshot["sheets"] == []
    assert snapshot["flows"] == []
    assert snapshot["scenes"] == []
    assert snapshot["localization"]["languages"] != []

    parent = self()
    barrier = make_ref()

    table_gate =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          Repo.transaction(fn ->
            Repo.query!("LOCK TABLE localized_texts IN ACCESS EXCLUSIVE MODE")
            send(parent, {barrier, :table_locked})

            receive do
              {^barrier, :release_gate} -> :released
            after
              @timeout -> exit(:gate_release_timeout)
            end
          end)
        end)
      end)

    assert_receive {^barrier, :table_locked}, @timeout

    restorer =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          [[backend_pid]] = Repo.query!("SELECT pg_backend_pid()").rows
          send(parent, {barrier, :restorer_ready, backend_pid})
          ProjectSnapshotBuilder.restore_snapshot(project.id, snapshot)
        end)
      end)

    assert_receive {^barrier, :restorer_ready, backend_pid}, @timeout
    assert wait_until_blocked(backend_pid)
    assert project_row_locked?(project.id)

    send(table_gate.pid, {barrier, :release_gate})

    assert {:ok, _result} = Task.await(restorer, @timeout)
    assert {:ok, :released} = Task.await(table_gate, @timeout)
  end

  defp wait_until_blocked(backend_pid) do
    deadline = System.monotonic_time(:millisecond) + @blocked_timeout
    do_wait_until_blocked(backend_pid, deadline)
  end

  defp do_wait_until_blocked(backend_pid, deadline) do
    [[blocking_count]] =
      Sandbox.unboxed_run(Repo, fn ->
        Repo.query!(
          "SELECT cardinality(pg_blocking_pids($1))",
          [backend_pid]
        )
      end).rows

    cond do
      blocking_count > 0 ->
        true

      System.monotonic_time(:millisecond) >= deadline ->
        false

      true ->
        Process.sleep(10)
        do_wait_until_blocked(backend_pid, deadline)
    end
  end

  defp project_row_locked?(project_id) do
    fn ->
      Sandbox.unboxed_run(Repo, fn ->
        try do
          Repo.transaction(fn ->
            Repo.query!(
              "SELECT id FROM projects WHERE id = $1 FOR UPDATE NOWAIT",
              [project_id]
            )
          end)

          false
        rescue
          error in Postgrex.Error ->
            error.postgres.code == :lock_not_available
        end
      end)
    end
    |> Task.async()
    |> Task.await(@timeout)
  end
end
