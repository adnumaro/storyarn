defmodule Storyarn.Localization.TextWriterConcurrencyTest do
  use ExUnit.Case, async: false

  import Ecto.Query
  import Storyarn.AccountsFixtures
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures

  alias Ecto.Adapters.SQL.Sandbox
  alias Storyarn.Accounts.User
  alias Storyarn.Localization
  alias Storyarn.Localization.LocalizedText
  alias Storyarn.Repo
  alias Storyarn.Workspaces.Workspace

  @timeout 15_000
  @blocked_timeout 5_000

  test "text updates serialize before their project activity trigger" do
    unboxed_scenario(fn %{project: project} ->
      first = localized_text_fixture(project.id)
      second = localized_text_fixture(project.id)

      [first_result, second_result] =
        run_after_text_locks([first.id, second.id], [
          fn ->
            Localization.update_text(first, %{
              "translator_notes" => "Updated by the first writer"
            })
          end,
          fn ->
            Localization.update_text(second, %{
              "translator_notes" => "Updated by the second writer"
            })
          end
        ])

      assert {:ok, %LocalizedText{translator_notes: "Updated by the first writer"}} =
               first_result

      assert {:ok, %LocalizedText{translator_notes: "Updated by the second writer"}} =
               second_result

      assert Repo.get!(LocalizedText, first.id).translator_notes ==
               "Updated by the first writer"

      assert Repo.get!(LocalizedText, second.id).translator_notes ==
               "Updated by the second writer"
    end)
  end

  test "text updates lock the project before touching localized_texts" do
    unboxed_scenario(fn %{project: project} ->
      text = localized_text_fixture(project.id)
      parent = self()
      barrier = make_ref()

      gate =
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

      writer =
        Task.async(fn ->
          Sandbox.unboxed_run(Repo, fn ->
            [[backend_pid]] = Repo.query!("SELECT pg_backend_pid()").rows
            send(parent, {barrier, :writer_ready, backend_pid})

            Localization.update_text(text, %{
              "translator_notes" => "Project-first writer"
            })
          end)
        end)

      assert_receive {^barrier, :writer_ready, backend_pid}, @timeout
      assert wait_until_blocked([backend_pid])
      assert project_row_locked?(project.id)

      send(gate.pid, {barrier, :release_gate})

      assert {:ok, %LocalizedText{translator_notes: "Project-first writer"}} =
               Task.await(writer, @timeout)

      assert {:ok, :released} = Task.await(gate, @timeout)
    end)
  end

  defp run_after_text_locks(text_ids, writers) do
    run_behind_lock(
      fn ->
        locked_ids =
          Repo.all(
            from(text in LocalizedText,
              where: text.id in ^text_ids,
              order_by: [asc: text.id],
              select: text.id,
              lock: "FOR UPDATE"
            )
          )

        if locked_ids != Enum.sort(text_ids) do
          raise "failed to lock every localized text used by the concurrency test"
        end
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

  defp unboxed_scenario(test_fun) do
    Sandbox.unboxed_run(Repo, fn ->
      user =
        user_fixture(%{
          email: "text-writer-concurrency-#{Ecto.UUID.generate()}@example.com"
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
