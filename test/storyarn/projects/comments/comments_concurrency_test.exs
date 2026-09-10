defmodule Storyarn.Projects.CommentsConcurrencyTest do
  use ExUnit.Case, async: false

  import Ecto.Query
  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Ecto.Adapters.SQL.Sandbox
  alias Storyarn.Accounts.User
  alias Storyarn.Projects
  alias Storyarn.Projects.Comments.Message
  alias Storyarn.Projects.Comments.Thread
  alias Storyarn.Projects.Project
  alias Storyarn.Repo
  alias Storyarn.Sheets
  alias Storyarn.Workspaces.Workspace

  test "simultaneous identical creates persist one thread and one message" do
    with_project(fn ctx ->
      attrs = %{body: "One durable request", client_request_id: Ecto.UUID.generate(), mention_user_ids: []}
      operation = fn -> Projects.create_flow_node_comment(ctx.scope, ctx.project.id, ctx.flow.id, ctx.node.id, attrs) end
      results = concurrently([operation, operation])
      assert [{:ok, first}, {:ok, second}] = results
      assert first.thread.id == second.thread.id
      assert Repo.aggregate(from(t in Thread, where: t.project_id == ^ctx.project.id), :count) == 1
      assert Repo.aggregate(from(m in Message, where: m.project_id == ^ctx.project.id), :count) == 1
    end)
  end

  test "two resolutions from one revision have exactly one winner" do
    with_project(fn ctx ->
      attrs = %{body: "Review before resolving", client_request_id: Ecto.UUID.generate(), mention_user_ids: []}
      {:ok, detail} = Projects.create_flow_node_comment(ctx.scope, ctx.project.id, ctx.flow.id, ctx.node.id, attrs)

      operation = fn ->
        Projects.set_comment_thread_status(
          ctx.scope,
          ctx.project.id,
          detail.thread.id,
          "resolved",
          detail.thread.revision
        )
      end

      results = concurrently([operation, operation])
      assert Enum.count(results, &match?({:ok, %{status: "resolved"}}, &1)) == 1
      assert Enum.count(results, &match?({:error, :stale}, &1)) == 1
      assert Repo.get!(Thread, detail.thread.id).revision == detail.thread.revision + 1
    end)
  end

  test "simultaneous moves from one revision have exactly one winner" do
    with_project(fn ctx ->
      attrs = %{body: "Move this pin", client_request_id: Ecto.UUID.generate(), position: %{x: 0, y: 0}}
      {:ok, detail} = Projects.create_flow_canvas_comment(ctx.scope, ctx.project.id, ctx.flow.id, attrs)

      operations =
        Enum.map([%{x: 10, y: 20}, %{x: 30, y: 40}], &move_operation(ctx, detail, &1))

      results = concurrently(operations)
      assert Enum.count(results, &match?({:ok, _}, &1)) == 1
      assert Enum.count(results, &match?({:error, :stale}, &1)) == 1
      assert Repo.get!(Thread, detail.thread.id).revision == detail.thread.revision + 1
    end)
  end

  test "concurrent last-member deletions invalidate row context after both transactions commit" do
    with_project(fn ctx ->
      sheet = sheet_fixture(ctx.project)
      blocks = for _ <- 1..2, do: block_fixture(sheet)
      {:ok, group_id} = Sheets.create_column_group(sheet.id, Enum.map(blocks, & &1.id))

      {:ok, detail} =
        Projects.create_sheet_canvas_comment(ctx.scope, ctx.project.id, sheet.id, %{
          body: "Keep this row discussion",
          client_request_id: Ecto.UUID.generate(),
          position: %{x: 40, y: 800},
          context: %{type: "sheet_column_group", id: group_id}
        })

      stored = Repo.get!(Thread, detail.thread.id)
      assert [{:ok, :removed}, {:ok, :removed}] = delete_group_members_concurrently(blocks)
      assert Repo.get!(Thread, detail.thread.id) == %{stored | context_sheet_column_group_id: nil}

      assert {:ok, retained} = Projects.get_comment_thread(ctx.scope, ctx.project.id, detail.thread.id)
      assert retained.thread.source.status == "available"
      assert retained.thread.context.status == "unavailable"
      assert retained.thread.context.id == group_id
      assert retained.thread.context.label == detail.thread.context.label
      assert retained.thread.position == detail.thread.position
      assert retained.messages == detail.messages
    end)
  end

  defp delete_group_members_concurrently(blocks) do
    parent = self()
    reference = make_ref()

    tasks = Enum.map(blocks, &start_group_member_deletion(&1, parent, reference))

    try do
      Enum.each(tasks, fn _task -> assert_receive {^reference, :ready, _pid}, 5_000 end)
      Enum.each(tasks, &send(&1.pid, {reference, :start}))
      Task.await_many(tasks, 10_000)
    after
      Enum.each(tasks, &Task.shutdown(&1, :brutal_kill))
    end
  end

  defp start_group_member_deletion(block, parent, reference) do
    Task.async(fn ->
      Sandbox.unboxed_run(Repo, fn -> delete_group_member(block, parent, reference) end)
    end)
  end

  defp delete_group_member(block, parent, reference) do
    Repo.transaction(fn ->
      # Exercise the persistence boundary without the Sheet command's shared
      # owner lock. Each deletion must finish before either transaction commits.
      Repo.query!("DELETE FROM blocks WHERE id = $1", [block.id])
      run_after_start(fn -> :removed end, parent, reference)
    end)
  end

  defp move_operation(ctx, detail, position) do
    fn -> Projects.move_comment_thread(ctx.scope, ctx.project.id, detail.thread.id, position, detail.thread.revision) end
  end

  defp concurrently(operations) do
    parent = self()
    reference = make_ref()

    tasks = Enum.map(operations, &start_operation(&1, parent, reference))

    Enum.each(tasks, fn _task ->
      assert_receive {^reference, :ready, _pid}, 5_000
    end)

    Enum.each(tasks, &send(&1.pid, {reference, :start}))
    Task.await_many(tasks, 10_000)
  end

  defp start_operation(operation, parent, reference) do
    Task.async(fn ->
      Sandbox.unboxed_run(Repo, fn -> run_after_start(operation, parent, reference) end)
    end)
  end

  defp run_after_start(operation, parent, reference) do
    send(parent, {reference, :ready, self()})

    receive do
      {^reference, :start} -> operation.()
    after
      5_000 -> raise "comment concurrency barrier timed out"
    end
  end

  defp with_project(fun) do
    Sandbox.unboxed_run(Repo, fn ->
      owner = user_fixture()
      project = project_fixture(owner)
      flow = flow_fixture(project)
      node = node_fixture(flow)

      try do
        fun.(%{scope: user_scope_fixture(owner), project: project, flow: flow, node: node})
      after
        Repo.delete_all(from(p in Project, where: p.id == ^project.id))
        Repo.delete_all(from(w in Workspace, where: w.id == ^project.workspace_id))
        Repo.delete_all(from(u in User, where: u.id == ^owner.id))
      end
    end)
  end
end
