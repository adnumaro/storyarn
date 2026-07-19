defmodule Storyarn.Flows.EntityTrashRefsConcurrencyTest do
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
  alias Storyarn.Flows.EntityTrashRef
  alias Storyarn.Flows.EntityTrashRefs
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Repo
  alias Storyarn.Sheets
  alias Storyarn.Sheets.Sheet
  alias Storyarn.Sheets.SheetAvatar
  alias Storyarn.Workspaces.Workspace

  @barrier_timeout 15_000

  test "a JSONB sweep preserves an edit committed while it waits for the source row" do
    unboxed_scenario(fn %{flow: flow, speaker: speaker} ->
      node =
        node_fixture(flow, %{
          data: %{
            "speaker_sheet_id" => speaker.id,
            "text" => "Before"
          }
        })

      barrier = make_ref()
      editor = hold_node_edit(self(), barrier, node.id, "text", "Concurrent edit")

      assert_receive {^barrier, :node_edit_held, editor_pid, _editor_backend_pid}, @barrier_timeout
      assert editor_pid == editor.pid

      sweeper =
        concurrent_call(self(), barrier, fn ->
          EntityTrashRefs.sweep_jsonb_field(
            FlowNode,
            "flow_node",
            :data,
            "speaker_sheet_id",
            :sheet,
            speaker.id
          )
        end)

      sweeper_backend_pid = start_and_get_backend!(barrier, sweeper)
      assert_connections_waiting_on_lock([sweeper_backend_pid])

      send(editor.pid, {barrier, :release})

      assert {:ok, %FlowNode{}} = Task.await(editor, @barrier_timeout)
      assert {:ok, 1} = Task.await(sweeper, @barrier_timeout)

      persisted = Repo.get!(FlowNode, node.id)
      assert persisted.data["speaker_sheet_id"] == nil
      assert persisted.data["text"] == "Concurrent edit"
    end)
  end

  test "a JSONB restore preserves an edit committed while it waits for the source row" do
    unboxed_scenario(fn %{flow: flow, speaker: speaker} ->
      node =
        node_fixture(flow, %{
          data: %{
            "speaker_sheet_id" => speaker.id,
            "text" => "Before"
          }
        })

      assert {:ok, 1} =
               EntityTrashRefs.sweep_jsonb_field(
                 FlowNode,
                 "flow_node",
                 :data,
                 "speaker_sheet_id",
                 :sheet,
                 speaker.id
               )

      barrier = make_ref()
      editor = hold_node_edit(self(), barrier, node.id, "text", "Concurrent edit")

      assert_receive {^barrier, :node_edit_held, editor_pid, _editor_backend_pid}, @barrier_timeout
      assert editor_pid == editor.pid

      restorer =
        concurrent_call(self(), barrier, fn ->
          EntityTrashRefs.restore(:sheet, speaker.id)
        end)

      restorer_backend_pid = start_and_get_backend!(barrier, restorer)
      assert_connections_waiting_on_lock([restorer_backend_pid])

      send(editor.pid, {barrier, :release})

      assert {:ok, %FlowNode{}} = Task.await(editor, @barrier_timeout)
      assert {:ok, %{restored: 1, skipped: 0}} = Task.await(restorer, @barrier_timeout)

      persisted = Repo.get!(FlowNode, node.id)
      assert persisted.data["speaker_sheet_id"] == speaker.id
      assert persisted.data["text"] == "Concurrent edit"
    end)
  end

  test "two concurrent JSONB sweeps produce one trash reference" do
    unboxed_scenario(fn %{flow: flow, speaker: speaker} ->
      node =
        node_fixture(flow, %{
          data: %{
            "speaker_sheet_id" => speaker.id,
            "text" => "Unchanged"
          }
        })

      barrier = make_ref()
      holder = hold_node(self(), barrier, node.id)

      assert_receive {^barrier, :node_held, holder_pid, _holder_backend_pid}, @barrier_timeout
      assert holder_pid == holder.pid

      sweep = fn ->
        EntityTrashRefs.sweep_jsonb_field(
          FlowNode,
          "flow_node",
          :data,
          "speaker_sheet_id",
          :sheet,
          speaker.id
        )
      end

      first = concurrent_call(self(), barrier, sweep)
      second = concurrent_call(self(), barrier, sweep)

      backend_pids = [
        start_and_get_backend!(barrier, first),
        start_and_get_backend!(barrier, second)
      ]

      assert_connections_waiting_on_lock(backend_pids)
      send(holder.pid, {barrier, :release})

      assert {:ok, %FlowNode{}} = Task.await(holder, @barrier_timeout)

      results =
        Enum.sort([
          Task.await(first, @barrier_timeout),
          Task.await(second, @barrier_timeout)
        ])

      assert results == [{:ok, 0}, {:ok, 1}]

      assert Repo.aggregate(
               from(ref in EntityTrashRef,
                 where:
                   ref.source_type == "flow_node" and
                     ref.source_id == ^node.id and
                     ref.source_field == "data.speaker_sheet_id" and
                     ref.target_sheet_id == ^speaker.id
               ),
               :count
             ) == 1

      persisted = Repo.get!(FlowNode, node.id)
      assert persisted.data["speaker_sheet_id"] == nil
      assert persisted.data["text"] == "Unchanged"
    end)
  end

  test "an avatar writer that wins the lock makes the concurrent delete fail closed" do
    unboxed_avatar_scenario(fn %{
                                 flow: flow,
                                 speaker: speaker,
                                 avatar: avatar
                               } ->
      node =
        node_fixture(flow, %{
          data: %{
            "speaker_sheet_id" => speaker.id,
            "text" => "Before"
          }
        })

      barrier = make_ref()

      writer =
        hold_after_call(self(), barrier, fn ->
          Flows.update_node_data(node, %{
            "speaker_sheet_id" => speaker.id,
            "avatar_id" => avatar.id,
            "text" => "With avatar"
          })
        end)

      assert_receive {
                       ^barrier,
                       :call_held,
                       writer_pid,
                       _writer_backend_pid,
                       {:ok, %FlowNode{}, %{renamed_jumps: 0}}
                     },
                     @barrier_timeout

      assert writer_pid == writer.pid

      deleter =
        concurrent_call(self(), barrier, fn ->
          Sheets.remove_avatar(speaker.id, avatar.id)
        end)

      deleter_backend_pid = start_and_get_backend!(barrier, deleter)
      assert_connections_waiting_on_lock([deleter_backend_pid])
      send(writer.pid, {barrier, :release})

      assert {:ok, {:ok, %FlowNode{}, %{renamed_jumps: 0}}} =
               Task.await(writer, @barrier_timeout)

      assert {:error, {:avatar_in_use, avatar_id, {:referenced_by_flow_nodes, 1}}} =
               Task.await(deleter, @barrier_timeout)

      assert avatar_id == avatar.id
      assert Repo.get!(SheetAvatar, avatar.id)
      assert Repo.get!(FlowNode, node.id).data["avatar_id"] == avatar.id
    end)
  end

  test "an avatar delete that wins the lock makes the concurrent writer fail closed" do
    unboxed_avatar_scenario(fn %{
                                 flow: flow,
                                 speaker: speaker,
                                 avatar: avatar
                               } ->
      node =
        node_fixture(flow, %{
          data: %{
            "speaker_sheet_id" => speaker.id,
            "text" => "Before"
          }
        })

      barrier = make_ref()

      deleter =
        hold_after_call(self(), barrier, fn ->
          Sheets.remove_avatar(speaker.id, avatar.id)
        end)

      assert_receive {
                       ^barrier,
                       :call_held,
                       deleter_pid,
                       _deleter_backend_pid,
                       {:ok, %SheetAvatar{}}
                     },
                     @barrier_timeout

      assert deleter_pid == deleter.pid

      writer =
        concurrent_call(self(), barrier, fn ->
          Flows.update_node_data(node, %{
            "speaker_sheet_id" => speaker.id,
            "avatar_id" => avatar.id,
            "text" => "With avatar"
          })
        end)

      writer_backend_pid = start_and_get_backend!(barrier, writer)
      assert_connections_waiting_on_lock([writer_backend_pid])
      send(deleter.pid, {barrier, :release})

      assert {:ok, {:ok, %SheetAvatar{}}} = Task.await(deleter, @barrier_timeout)

      assert {:error, {:invalid_avatar_reference, avatar_id}} =
               Task.await(writer, @barrier_timeout)

      assert avatar_id == avatar.id
      refute Repo.get(SheetAvatar, avatar.id)
      refute Map.has_key?(Repo.get!(FlowNode, node.id).data, "avatar_id")
    end)
  end

  defp unboxed_scenario(test_fun) do
    Sandbox.unboxed_run(Repo, fn ->
      user =
        user_fixture(%{
          email: "trash-ref-concurrency-#{Ecto.UUID.generate()}@example.com"
        })

      project = project_fixture(user)
      flow = flow_fixture(project)
      speaker = sheet_fixture(project, %{name: "Speaker"})

      try do
        test_fun.(%{
          user: user,
          workspace_id: project.workspace_id,
          project: project,
          flow: flow,
          speaker: speaker
        })
      after
        cleanup_scenario(project.id, project.workspace_id, user.id)
      end
    end)
  end

  defp unboxed_avatar_scenario(test_fun) do
    unboxed_scenario(fn scenario ->
      asset = image_asset_fixture(scenario.project, scenario.user)
      {:ok, avatar} = Sheets.add_avatar(scenario.speaker, asset.id)
      test_fun.(Map.put(scenario, :avatar, avatar))
    end)
  end

  defp cleanup_scenario(project_id, workspace_id, user_id) do
    sheet_ids =
      from(sheet in Sheet,
        where: sheet.project_id == ^project_id,
        select: sheet.id
      )

    Repo.delete_all(from(avatar in SheetAvatar, where: avatar.sheet_id in subquery(sheet_ids)))
    Repo.delete_all(from(workspace in Workspace, where: workspace.id == ^workspace_id))
    Repo.delete_all(from(user in User, where: user.id == ^user_id))
  end

  defp hold_node_edit(parent, barrier, node_id, key, value) do
    async_unboxed_transaction(fn backend_pid ->
      node = lock_node!(node_id)

      updated =
        node
        |> Ecto.Changeset.change(data: Map.put(node.data, key, value))
        |> Repo.update!()

      send(parent, {barrier, :node_edit_held, self(), backend_pid})
      await_release!(barrier)
      updated
    end)
  end

  defp hold_node(parent, barrier, node_id) do
    async_unboxed_transaction(fn backend_pid ->
      node = lock_node!(node_id)
      send(parent, {barrier, :node_held, self(), backend_pid})
      await_release!(barrier)
      node
    end)
  end

  defp hold_after_call(parent, barrier, call) do
    async_unboxed_transaction(fn backend_pid ->
      result = call.()
      send(parent, {barrier, :call_held, self(), backend_pid, result})
      await_release!(barrier)
      result
    end)
  end

  defp async_unboxed_transaction(transaction) do
    Task.async(fn -> run_unboxed_transaction(transaction) end)
  end

  defp run_unboxed_transaction(transaction) do
    Sandbox.unboxed_run(Repo, fn -> run_transaction(transaction) end)
  end

  defp run_transaction(transaction) do
    backend_pid = backend_pid!()
    Repo.transaction(fn -> transaction.(backend_pid) end)
  end

  defp lock_node!(node_id) do
    Repo.one!(
      from(node in FlowNode,
        where: node.id == ^node_id,
        lock: "FOR UPDATE"
      )
    )
  end

  defp concurrent_call(parent, barrier, call) do
    Task.async(fn ->
      Sandbox.unboxed_run(Repo, fn ->
        backend_pid = backend_pid!()
        send(parent, {barrier, :call_ready, self(), backend_pid})

        receive do
          {^barrier, :start} -> :ok
        after
          @barrier_timeout -> exit(:start_barrier_timeout)
        end

        call.()
      end)
    end)
  end

  defp start_and_get_backend!(barrier, task) do
    task_pid = task.pid
    assert_receive {^barrier, :call_ready, ^task_pid, backend_pid}, @barrier_timeout
    send(task.pid, {barrier, :start})
    backend_pid
  end

  defp backend_pid! do
    [[backend_pid]] = Repo.query!("SELECT pg_backend_pid()").rows
    backend_pid
  end

  defp await_release!(barrier) do
    receive do
      {^barrier, :release} -> :ok
    after
      @barrier_timeout -> Repo.rollback(:release_barrier_timeout)
    end
  end

  defp assert_connections_waiting_on_lock(backend_pids, attempts \\ 1_000)

  defp assert_connections_waiting_on_lock(_backend_pids, 0) do
    flunk("database connections did not block on the expected row lock")
  end

  defp assert_connections_waiting_on_lock(backend_pids, attempts) do
    all_waiting? =
      Enum.all?(backend_pids, fn backend_pid ->
        Repo.query!(
          "SELECT wait_event_type FROM pg_stat_activity WHERE pid = $1",
          [backend_pid]
        ).rows == [["Lock"]]
      end)

    if all_waiting? do
      :ok
    else
      Process.sleep(10)
      assert_connections_waiting_on_lock(backend_pids, attempts - 1)
    end
  end
end
