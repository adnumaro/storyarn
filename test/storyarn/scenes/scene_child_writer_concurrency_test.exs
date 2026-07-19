defmodule Storyarn.Scenes.SceneChildWriterConcurrencyTest do
  use ExUnit.Case, async: false

  import Ecto.Query
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures

  alias Ecto.Adapters.SQL.Sandbox
  alias Storyarn.Accounts.User
  alias Storyarn.Repo
  alias Storyarn.Scenes.AnnotationCrud
  alias Storyarn.Scenes.LayerCrud
  alias Storyarn.Scenes.Scene
  alias Storyarn.Scenes.SceneAnnotation
  alias Storyarn.Scenes.SceneLayer
  alias Storyarn.Workspaces.Workspace

  @timeout 15_000
  @blocked_timeout 5_000

  test "child updates on one scene serialize before their project activity trigger" do
    unboxed_scenario(fn %{project: project} ->
      scene = scene_fixture(project)
      layer = layer_fixture(scene, %{"name" => "Original layer"})
      annotation = annotation_fixture(scene, %{"text" => "Original annotation"})

      [layer_result, annotation_result] =
        run_after_scene_lock(scene.id, [
          fn -> LayerCrud.update_layer(layer, %{"name" => "Updated layer"}) end,
          fn ->
            AnnotationCrud.update_annotation(annotation, %{
              "text" => "Updated annotation"
            })
          end
        ])

      assert {:ok, %SceneLayer{name: "Updated layer"}} = layer_result

      assert {:ok, %SceneAnnotation{text: "Updated annotation"}} =
               annotation_result

      assert Repo.get!(SceneLayer, layer.id).name == "Updated layer"
      assert Repo.get!(SceneAnnotation, annotation.id).text == "Updated annotation"
    end)
  end

  defp run_after_scene_lock(scene_id, writers) do
    run_behind_lock(
      fn ->
        Repo.one!(
          from(scene in Scene,
            where: scene.id == ^scene_id,
            lock: "FOR UPDATE"
          )
        )
      end,
      writers
    )
  end

  defp run_behind_lock(lock_rows, writers) do
    parent = self()
    barrier = make_ref()

    gate =
      Task.async(fn -> run_lock_gate(lock_rows, parent, barrier) end)

    assert_receive {^barrier, :gate_locked}, @timeout

    tasks =
      Enum.map(writers, fn writer ->
        Task.async(fn -> run_unboxed_writer(writer, parent, barrier) end)
      end)

    backend_pids =
      Enum.map(tasks, fn _task ->
        assert_receive {^barrier, :writer_ready, task_pid, backend_pid}, @timeout
        assert task_pid in Enum.map(tasks, & &1.pid)
        backend_pid
      end)

    assert wait_until_blocked(backend_pids)
    send(gate.pid, {barrier, :release_gate})

    results = Enum.map(tasks, &Task.await(&1, @timeout))
    assert {:ok, :released} = Task.await(gate, @timeout)
    results
  end

  defp run_lock_gate(lock_rows, parent, barrier) do
    Sandbox.unboxed_run(Repo, fn ->
      Repo.transaction(fn -> hold_lock_gate(lock_rows, parent, barrier) end)
    end)
  end

  defp hold_lock_gate(lock_rows, parent, barrier) do
    lock_rows.()
    send(parent, {barrier, :gate_locked})

    receive do
      {^barrier, :release_gate} -> :released
    after
      @timeout -> exit(:gate_release_timeout)
    end
  end

  defp run_unboxed_writer(writer, parent, barrier) do
    Sandbox.unboxed_run(Repo, fn ->
      [[backend_pid]] = Repo.query!("SELECT pg_backend_pid()").rows
      send(parent, {barrier, :writer_ready, self(), backend_pid})
      writer.()
    end)
  end

  defp wait_until_blocked(backend_pids) do
    deadline = System.monotonic_time(:millisecond) + @blocked_timeout
    do_wait_until_blocked(backend_pids, deadline)
  end

  defp do_wait_until_blocked(backend_pids, deadline) do
    cond do
      Enum.all?(backend_pids, &backend_blocked?/1) ->
        true

      System.monotonic_time(:millisecond) >= deadline ->
        false

      true ->
        Process.sleep(10)
        do_wait_until_blocked(backend_pids, deadline)
    end
  end

  defp backend_blocked?(backend_pid) do
    [[blocking_count]] =
      Repo.query!(
        "SELECT cardinality(pg_blocking_pids($1))",
        [backend_pid]
      ).rows

    blocking_count > 0
  end

  defp unboxed_scenario(test_fun) do
    Sandbox.unboxed_run(Repo, fn ->
      user =
        user_fixture(%{
          email: "scene-child-writer-concurrency-#{Ecto.UUID.generate()}@example.com"
        })

      project = project_fixture(user)

      try do
        test_fun.(%{user: user, project: project})
      after
        Repo.delete_all(from(workspace in Workspace, where: workspace.id == ^project.workspace_id))
        Repo.delete_all(from(user_row in User, where: user_row.id == ^user.id))
      end
    end)
  end
end
