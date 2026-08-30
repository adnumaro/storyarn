defmodule Storyarn.Flows.DialogueAudioConcurrencyTest do
  @moduledoc """
  Verifies the dialogue-audio command against real PostgreSQL concurrency.

  These tests deliberately use independent unboxed connections. A shared SQL
  sandbox connection would serialize the tasks before PostgreSQL can exercise
  the row-lock protocol that protects Flow edits and asset deletion.
  """
  use ExUnit.Case, async: false

  import Ecto.Query
  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Ecto.Adapters.SQL.Sandbox
  alias Storyarn.Accounts.User
  alias Storyarn.Flows
  alias Storyarn.Projects.Assets
  alias Storyarn.Projects.Assets.Asset
  alias Storyarn.Projects.Project
  alias Storyarn.Repo
  alias Storyarn.Workspaces.Workspace

  @timeout 15_000

  test "an audio assignment and an ordinary Flow edit compose without losing either change" do
    unboxed_scenario(fn state ->
      [audio_result, text_result] =
        run_concurrently([
          fn ->
            Flows.assign_dialogue_audio(
              state.project.id,
              state.sheet.id,
              state.node.id,
              state.audio.id
            )
          end,
          fn ->
            Flows.edit_node(state.flow.id, state.node.id, :put_field, %{
              field: "text",
              value: "Concurrent edit"
            })
          end
        ])

      assert {:ok,
              %{
                node_id: node_id,
                audio_asset_id: audio_id,
                node_snapshot: %{data: snapshot_data}
              }} = audio_result

      assert node_id == state.node.id
      assert audio_id == state.audio.id
      assert snapshot_data["audio_asset_id"] == state.audio.id
      assert {:ok, _updated_node} = text_result

      persisted = Flows.get_node!(state.flow.id, state.node.id)
      assert persisted.data["audio_asset_id"] == state.audio.id
      assert persisted.data["text"] == "Concurrent edit"
      assert persisted.data["stage_directions"] == "Keep this direction"
    end)
  end

  test "audio assignment takes the strong Project lock before waiting on the Flow node" do
    unboxed_scenario(fn state ->
      parent = self()
      release_ref = make_ref()

      blocker =
        Task.async(fn ->
          Sandbox.unboxed_run(Repo, fn ->
            Repo.transaction(fn ->
              Repo.one!(
                from(project in Project,
                  where: project.id == ^state.project.id,
                  lock: "FOR SHARE"
                )
              )

              send(parent, {:dialogue_audio_project_locked, self()})

              receive do
                {^release_ref, :release} -> :released
              after
                @timeout -> exit(:dialogue_audio_project_lock_timeout)
              end
            end)
          end)
        end)

      assert_receive {:dialogue_audio_project_locked, blocker_pid}, @timeout
      assert blocker_pid == blocker.pid

      assignment =
        Task.async(fn ->
          Sandbox.unboxed_run(Repo, fn ->
            %{rows: [[backend_pid]]} = Repo.query!("SELECT pg_backend_pid()")
            send(parent, {:dialogue_audio_backend_ready, self(), backend_pid})

            Flows.assign_dialogue_audio(
              state.project.id,
              state.sheet.id,
              state.node.id,
              state.audio.id
            )
          end)
        end)

      try do
        assert_receive {:dialogue_audio_backend_ready, assignment_pid, backend_pid}, @timeout
        assert assignment_pid == assignment.pid

        assert :waiting_for_lock == wait_for_lock_or_completion(assignment, backend_pid)
      after
        send(blocker.pid, {release_ref, :release})
      end

      assert {:ok,
              %{
                node_id: node_id,
                audio_asset_id: audio_id,
                node_snapshot: %{data: snapshot_data}
              }} =
               Task.await(assignment, @timeout)

      assert node_id == state.node.id
      assert audio_id == state.audio.id
      assert snapshot_data["audio_asset_id"] == state.audio.id
      assert {:ok, :released} = Task.await(blocker, @timeout)
    end)
  end

  test "an audio assignment racing asset deletion never leaves an active dangling reference" do
    unboxed_scenario(fn state ->
      [audio_result, deletion_result] =
        run_concurrently([
          fn ->
            Flows.assign_dialogue_audio(
              state.project.id,
              state.sheet.id,
              state.node.id,
              state.audio.id
            )
          end,
          fn -> Assets.delete_asset(state.audio) end
        ])

      persisted_node = Flows.get_node!(state.flow.id, state.node.id)
      persisted_asset = Repo.get!(Asset, state.audio.id)

      case {audio_result, deletion_result} do
        {{:ok, %{audio_asset_id: audio_id}}, {:error, :asset_still_referenced}} ->
          assert audio_id == state.audio.id
          assert persisted_node.data["audio_asset_id"] == state.audio.id
          assert is_nil(persisted_asset.deleted_at)

        {
          {:error, {:invalid_project_reference, :audio_asset_id, audio_id}},
          {:ok, deleted_asset}
        } ->
          assert audio_id == state.audio.id
          refute Map.has_key?(persisted_node.data, "audio_asset_id")
          assert deleted_asset.id == state.audio.id
          assert persisted_asset.deleted_at

        unexpected ->
          flunk("unexpected concurrent audio/delete outcome: #{inspect(unexpected)}")
      end
    end)
  end

  defp run_concurrently(operations) do
    parent = self()
    barrier = make_ref()

    tasks =
      Enum.map(operations, &start_concurrent_operation(&1, parent, barrier))

    Enum.each(tasks, fn _task ->
      assert_receive {^barrier, :ready, task_pid}, @timeout
      assert task_pid in Enum.map(tasks, & &1.pid)
    end)

    Enum.each(tasks, &send(&1.pid, {barrier, :run}))
    Enum.map(tasks, &Task.await(&1, @timeout))
  end

  defp start_concurrent_operation(operation, parent, barrier) do
    Task.async(fn ->
      Sandbox.unboxed_run(Repo, fn -> await_concurrent_operation(operation, parent, barrier) end)
    end)
  end

  defp await_concurrent_operation(operation, parent, barrier) do
    send(parent, {barrier, :ready, self()})

    receive do
      {^barrier, :run} -> operation.()
    after
      @timeout -> exit(:dialogue_audio_barrier_timeout)
    end
  end

  defp wait_for_lock_or_completion(task, backend_pid) do
    deadline = System.monotonic_time(:millisecond) + @timeout
    wait_for_lock_or_completion(task, backend_pid, deadline)
  end

  defp wait_for_lock_or_completion(task, backend_pid, deadline) do
    case Task.yield(task, 0) do
      {:ok, result} ->
        {:completed_without_waiting, result}

      {:exit, reason} ->
        {:exited_without_waiting, reason}

      nil ->
        %{rows: rows} =
          Repo.query!(
            "SELECT wait_event_type FROM pg_stat_activity WHERE pid = $1",
            [backend_pid]
          )

        waiting? = rows == [["Lock"]]

        cond do
          waiting? ->
            :waiting_for_lock

          System.monotonic_time(:millisecond) >= deadline ->
            :lock_wait_timeout

          true ->
            Process.sleep(10)
            wait_for_lock_or_completion(task, backend_pid, deadline)
        end
    end
  end

  defp unboxed_scenario(test_fun) do
    Sandbox.unboxed_run(Repo, fn ->
      user =
        user_fixture(%{
          email: "dialogue-audio-concurrency-#{Ecto.UUID.generate()}@example.com"
        })

      project = project_fixture(user)
      sheet = sheet_fixture(project, %{name: "Speaker"})
      flow = flow_fixture(project, %{name: "Dialogue"})

      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "speaker_sheet_id" => sheet.id,
            "text" => "Original text",
            "stage_directions" => "Keep this direction"
          }
        })

      audio = audio_asset_fixture(project, user)

      try do
        test_fun.(%{
          user: user,
          project: project,
          sheet: sheet,
          flow: flow,
          node: node,
          audio: audio
        })
      after
        Repo.delete_all(from(current in Project, where: current.id == ^project.id))
        Repo.delete_all(from(workspace in Workspace, where: workspace.id == ^project.workspace_id))
        Repo.delete_all(from(current in User, where: current.id == ^user.id))
      end
    end)
  end
end
