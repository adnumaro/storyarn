defmodule Storyarn.Versioning.EntityRestoreLockConcurrencyTest do
  use ExUnit.Case, async: false

  import Ecto.Query
  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.SheetsFixtures

  alias Ecto.Adapters.SQL.Sandbox
  alias Storyarn.Accounts.User
  alias Storyarn.Flows
  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Projects.Project
  alias Storyarn.Repo
  alias Storyarn.Scenes
  alias Storyarn.Scenes.Scene
  alias Storyarn.Sheets
  alias Storyarn.Sheets.Sheet
  alias Storyarn.Workspaces.Workspace

  @timeout 15_000
  @blocked_timeout 5_000

  test "restore_flow locks Project before Flow and serializes with a stale delete" do
    %{user: user, project: project, deleted: deleted} =
      build_deleted_entity("flow", fn project ->
        flow = flow_fixture(project)
        assert {:ok, deleted} = Flows.delete_flow(flow)
        deleted
      end)

    on_exit(fn -> cleanup_project(user, project) end)

    assert_restore_serializes_with_delete(
      Flow,
      deleted.id,
      project.id,
      fn -> Flows.restore_flow(deleted) end,
      fn -> Flows.delete_flow(deleted) end
    )
  end

  test "hard_delete_flow locks Project before Flow and serializes with restore" do
    %{user: user, project: project, deleted: deleted} =
      build_deleted_entity("flow-hard-delete", fn project ->
        flow = flow_fixture(project)
        assert {:ok, deleted} = Flows.delete_flow(flow)
        deleted
      end)

    on_exit(fn -> cleanup_project(user, project) end)

    parent = self()
    barrier = make_ref()

    entity_gate =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          hold_entity_lock(Flow, deleted.id, parent, barrier)
        end)
      end)

    assert_receive {^barrier, :entity_locked, gate_backend_pid}, @timeout

    hard_deleter =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          [[backend_pid]] = Repo.query!("SELECT pg_backend_pid()").rows
          send(parent, {barrier, :hard_deleter_ready, backend_pid})
          Flows.hard_delete_flow(deleted)
        end)
      end)

    assert_receive {^barrier, :hard_deleter_ready, hard_deleter_backend_pid}, @timeout
    assert wait_until_blocked_by(hard_deleter_backend_pid, gate_backend_pid)
    assert project_row_locked?(project.id)

    restorer =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          [[backend_pid]] = Repo.query!("SELECT pg_backend_pid()").rows
          send(parent, {barrier, :restorer_ready, backend_pid})
          Flows.restore_flow(deleted)
        end)
      end)

    assert_receive {^barrier, :restorer_ready, restorer_backend_pid}, @timeout
    assert wait_until_blocked_by(restorer_backend_pid, hard_deleter_backend_pid)

    send(entity_gate.pid, {barrier, :release_gate})

    assert {:ok, hard_deleted} = Task.await(hard_deleter, @timeout)
    assert hard_deleted.id == deleted.id
    assert {:error, :flow_not_deleted} = Task.await(restorer, @timeout)
    assert {:ok, :released} = Task.await(entity_gate, @timeout)

    refute Sandbox.unboxed_run(Repo, fn -> Repo.get(Flow, deleted.id) end)
  end

  test "restore_sequence locks Project before FlowNode and serializes with a stale delete" do
    %{user: user, project: project, deleted: deleted} =
      build_deleted_entity("sequence", fn project ->
        flow = flow_fixture(project)
        assert {:ok, sequence} = Flows.create_sequence(flow.id, %{"name" => "Opening"})
        assert {:ok, deleted} = Flows.delete_sequence(sequence)
        deleted
      end)

    on_exit(fn -> cleanup_project(user, project) end)

    assert_restore_serializes_with_delete(
      FlowNode,
      deleted.id,
      project.id,
      fn -> Flows.restore_sequence(deleted) end,
      fn -> Flows.delete_sequence(deleted) end
    )
  end

  test "restore_scene locks Project before Scene and serializes with a stale delete" do
    %{user: user, project: project, deleted: deleted} =
      build_deleted_entity("scene", fn project ->
        scene = scene_fixture(project)
        assert {:ok, deleted} = Scenes.delete_scene(scene)
        deleted
      end)

    on_exit(fn -> cleanup_project(user, project) end)

    assert_restore_serializes_with_delete(
      Scene,
      deleted.id,
      project.id,
      fn -> Scenes.restore_scene(deleted) end,
      fn -> Scenes.delete_scene(deleted) end
    )
  end

  test "restore_sheet locks Project before Sheet and serializes with a stale delete" do
    %{user: user, project: project, deleted: deleted} =
      build_deleted_entity("sheet", fn project ->
        sheet = sheet_fixture(project)
        assert {:ok, deleted} = Sheets.delete_sheet(sheet)
        deleted
      end)

    on_exit(fn -> cleanup_project(user, project) end)

    assert_restore_serializes_with_delete(
      Sheet,
      deleted.id,
      project.id,
      fn -> Sheets.restore_sheet(deleted) end,
      fn -> Sheets.delete_sheet(deleted) end
    )
  end

  defp build_deleted_entity(label, build_entity) do
    Sandbox.unboxed_run(Repo, fn ->
      user =
        user_fixture(%{
          email: "#{label}-restore-lock-#{Ecto.UUID.generate()}@example.com"
        })

      project = project_fixture(user)
      %{user: user, project: project, deleted: build_entity.(project)}
    end)
  end

  defp assert_restore_serializes_with_delete(schema, entity_id, project_id, restore, delete) do
    parent = self()
    barrier = make_ref()

    entity_gate =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          hold_entity_lock(schema, entity_id, parent, barrier)
        end)
      end)

    assert_receive {^barrier, :entity_locked, gate_backend_pid}, @timeout

    restorer =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          [[backend_pid]] = Repo.query!("SELECT pg_backend_pid()").rows
          send(parent, {barrier, :restorer_ready, backend_pid})
          restore.()
        end)
      end)

    assert_receive {^barrier, :restorer_ready, restorer_backend_pid}, @timeout
    assert wait_until_blocked_by(restorer_backend_pid, gate_backend_pid)
    assert project_row_locked?(project_id)

    deleter =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          [[backend_pid]] = Repo.query!("SELECT pg_backend_pid()").rows
          send(parent, {barrier, :deleter_ready, backend_pid})
          delete.()
        end)
      end)

    assert_receive {^barrier, :deleter_ready, deleter_backend_pid}, @timeout
    assert wait_until_blocked_by(deleter_backend_pid, restorer_backend_pid)

    send(entity_gate.pid, {barrier, :release_gate})

    assert {:ok, restored} = Task.await(restorer, @timeout)
    assert restored.id == entity_id
    refute restored.deleted_at

    assert {:ok, deleted_again} = Task.await(deleter, @timeout)
    assert deleted_again.id == entity_id
    assert deleted_again.deleted_at

    assert {:ok, :released} = Task.await(entity_gate, @timeout)

    persisted =
      Sandbox.unboxed_run(Repo, fn ->
        Repo.get!(schema, entity_id)
      end)

    assert persisted.id == entity_id
    assert persisted.deleted_at
  end

  defp hold_entity_lock(schema, entity_id, parent, barrier) do
    Repo.transaction(fn ->
      [[backend_pid]] = Repo.query!("SELECT pg_backend_pid()").rows

      Repo.one!(
        from(entity in schema,
          where: entity.id == ^entity_id,
          select: entity.id,
          lock: "FOR UPDATE"
        )
      )

      send(parent, {barrier, :entity_locked, backend_pid})

      receive do
        {^barrier, :release_gate} -> :released
      after
        @timeout -> exit(:gate_release_timeout)
      end
    end)
  end

  defp wait_until_blocked_by(backend_pid, blocker_pid) do
    deadline = System.monotonic_time(:millisecond) + @blocked_timeout
    do_wait_until_blocked_by(backend_pid, blocker_pid, deadline)
  end

  defp do_wait_until_blocked_by(backend_pid, blocker_pid, deadline) do
    blockers =
      Sandbox.unboxed_run(Repo, fn ->
        [[blocking_pids]] =
          Repo.query!(
            "SELECT pg_blocking_pids($1)",
            [backend_pid]
          ).rows

        blocking_pids
      end)

    cond do
      blocker_pid in blockers ->
        true

      System.monotonic_time(:millisecond) >= deadline ->
        false

      true ->
        Process.sleep(10)
        do_wait_until_blocked_by(backend_pid, blocker_pid, deadline)
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

  defp cleanup_project(user, project) do
    Sandbox.unboxed_run(Repo, fn ->
      Repo.delete_all(from(current in Project, where: current.id == ^project.id))
      Repo.delete_all(from(workspace in Workspace, where: workspace.id == ^project.workspace_id))
      Repo.delete_all(from(current in User, where: current.id == ^user.id))
    end)
  end
end
