defmodule Storyarn.Projects.CommentsTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.Flows
  alias Storyarn.Platform
  alias Storyarn.Projects
  alias Storyarn.Projects.Comments.Mention
  alias Storyarn.Projects.Comments.Message
  alias Storyarn.Projects.Comments.Thread

  setup do
    owner = user_fixture()
    workspace = workspace_fixture(owner)
    project = project_fixture(owner, %{workspace: workspace})
    flow = flow_fixture(project)
    node = node_fixture(flow, %{data: %{"text" => "A source worth reviewing"}})
    %{owner: owner, scope: user_scope_fixture(owner), workspace: workspace, project: project, flow: flow, node: node}
  end

  test "creation persists typed source, author, preview and counts", ctx do
    assert {:ok, detail} = create_comment(ctx)
    assert detail.thread.status == "open"
    assert detail.thread.message_count == 1
    assert detail.thread.author.id == ctx.owner.id
    assert detail.thread.source.id == ctx.node.id
    assert detail.thread.source.label == "A source worth reviewing"
    assert detail.thread.source.status == "available"
    assert detail.thread.preview == "Please review this line"
    assert [%{id: message_id, parent_id: nil, body: "Please review this line"}] = detail.messages
    assert detail.thread.root_message_id == message_id

    assert {:ok, %{flow_id: flow_id, node_id: node_id, thread_id: thread_id}} =
             Projects.comment_destination(ctx.scope, ctx.project.id, message_id)

    assert {flow_id, node_id, thread_id} == {ctx.flow.id, ctx.node.id, detail.thread.id}
    assert {:ok, %{ctx.node.id => 1}} == Projects.flow_comment_counts(ctx.scope, ctx.project.id, ctx.flow.id)
  end

  test "effective workspace members can comment; direct viewer wins over workspace editor", ctx do
    member = user_fixture()
    workspace_membership_fixture(ctx.workspace, member, "member")
    member_scope = user_scope_fixture(member)
    assert {:ok, _} = create_comment(%{ctx | scope: member_scope})
    membership_fixture(ctx.project, member, "viewer")
    assert {:error, :unauthorized} = create_comment(%{ctx | scope: member_scope})
    assert {:ok, %{threads: [_]}} = Projects.list_flow_comment_threads(member_scope, ctx.project.id, ctx.flow.id)
  end

  test "open counts exclude a stored anchor whose source ID disagrees with its node pointer", ctx do
    {:ok, detail} = create_comment(ctx)
    other_node = node_fixture(ctx.flow)

    # Simulate an inconsistent stored anchor; the public comment API never
    # changes either source identity after creation.
    Thread
    |> Repo.get!(detail.thread.id)
    |> change(source_id: other_node.id)
    |> Repo.update!()

    assert {:ok, unavailable} = Projects.get_comment_thread(ctx.scope, ctx.project.id, detail.thread.id)
    assert unavailable.thread.source.status == "unavailable"
    assert {:ok, counts} = Projects.flow_comment_counts(ctx.scope, ctx.project.id, ctx.flow.id)
    assert counts == %{}
  end

  test "viewer reads but cannot create, reply, resolve or reopen", ctx do
    viewer = user_fixture()
    membership_fixture(ctx.project, viewer, "viewer")
    scope = user_scope_fixture(viewer)
    {:ok, detail} = create_comment(ctx)
    assert {:ok, _} = Projects.get_comment_thread(scope, ctx.project.id, detail.thread.id)
    assert {:error, :unauthorized} = create_comment(%{ctx | scope: scope})
    assert {:error, :unauthorized} = reply(%{ctx | scope: scope}, detail)

    assert {:error, :unauthorized} =
             Projects.set_comment_thread_status(
               scope,
               ctx.project.id,
               detail.thread.id,
               "resolved",
               detail.thread.revision
             )

    assert {:error, :unauthorized} =
             Projects.set_comment_thread_status(scope, ctx.project.id, detail.thread.id, "open", detail.thread.revision)
  end

  test "foreign project and anchor identities never authorize an operation", ctx do
    stranger = user_fixture()
    other = project_fixture(stranger)
    other_flow = flow_fixture(other)
    other_node = node_fixture(other_flow)
    {:ok, detail} = create_comment(ctx)

    assert {:error, :not_found} =
             Projects.get_comment_thread(user_scope_fixture(stranger), ctx.project.id, detail.thread.id)

    assert {:error, :not_found} = Projects.get_comment_thread(ctx.scope, other.id, detail.thread.id)

    assert {:error, :source_unavailable} =
             Projects.create_flow_node_comment(ctx.scope, ctx.project.id, other_flow.id, other_node.id, attrs())

    assert {:error, :not_found} =
             Projects.reply_to_comment_thread(
               user_scope_fixture(stranger),
               other.id,
               detail.thread.id,
               reply_attrs(detail)
             )

    assert Repo.aggregate(Message, :count) == 1
  end

  test "revoked membership is checked again on read and mutation", ctx do
    editor = user_fixture()
    membership = membership_fixture(ctx.project, editor)
    scope = user_scope_fixture(editor)
    {:ok, detail} = create_comment(%{ctx | scope: scope})
    Repo.delete!(membership)
    assert {:error, :not_found} = Projects.get_comment_thread(scope, ctx.project.id, detail.thread.id)
    assert {:error, :not_found} = reply(%{ctx | scope: scope}, detail)
  end

  test "same request returns original result and publishes no duplicate signal", ctx do
    request = attrs()
    assert :ok = Projects.subscribe_flow_comments(ctx.scope, ctx.project.id, ctx.flow.id)
    assert {:ok, first} = create_comment(ctx, request)
    flow_id = ctx.flow.id
    assert_receive {:flow_comments_changed, ^flow_id}
    assert {:ok, second} = create_comment(ctx, request)
    assert first.thread.id == second.thread.id
    refute_receive {:flow_comments_changed, _}
    assert Repo.aggregate(Thread, :count) == 1
    assert Repo.aggregate(Message, :count) == 1
    assert {:error, :idempotency_conflict} = create_comment(ctx, %{request | body: "Another body"})
    assert :ok = Projects.unsubscribe_flow_comments(ctx.project.id, ctx.flow.id)
  end

  test "replies require a parent from the same thread and retry without incrementing", ctx do
    {:ok, first} = create_comment(ctx)
    {:ok, other} = create_comment(ctx)
    invalid = %{reply_attrs(first) | parent_id: hd(other.messages).id}

    assert {:error, :invalid_parent} =
             Projects.reply_to_comment_thread(ctx.scope, ctx.project.id, first.thread.id, invalid)

    request = reply_attrs(first)
    assert {:ok, replied} = Projects.reply_to_comment_thread(ctx.scope, ctx.project.id, first.thread.id, request)
    assert replied.thread.message_count == 2
    assert List.last(replied.messages).parent_id == hd(first.messages).id
    assert {:ok, repeated} = Projects.reply_to_comment_thread(ctx.scope, ctx.project.id, first.thread.id, request)
    assert repeated.thread.revision == replied.thread.revision
    assert repeated.thread.message_count == 2
  end

  test "a reply invalidates stale resolution and resolution requires reopening", ctx do
    {:ok, first} = create_comment(ctx)
    {:ok, replied} = reply(ctx, first)

    assert {:error, :stale} =
             Projects.set_comment_thread_status(
               ctx.scope,
               ctx.project.id,
               first.thread.id,
               "resolved",
               first.thread.revision
             )

    assert {:ok, resolved} =
             Projects.set_comment_thread_status(
               ctx.scope,
               ctx.project.id,
               first.thread.id,
               "resolved",
               replied.thread.revision
             )

    assert resolved.resolved_by.id == ctx.owner.id
    assert {:ok, %{}} = Projects.flow_comment_counts(ctx.scope, ctx.project.id, ctx.flow.id)
    assert {:error, :thread_resolved} = reply(ctx, first)

    assert {:error, :stale} =
             Projects.set_comment_thread_status(
               ctx.scope,
               ctx.project.id,
               first.thread.id,
               "open",
               replied.thread.revision
             )

    assert {:ok, reopened} =
             Projects.set_comment_thread_status(ctx.scope, ctx.project.id, first.thread.id, "open", resolved.revision)

    assert reopened.resolved_at == nil
    assert reopened.status == "open"
  end

  test "status changes reject thread IDs beyond PostgreSQL bigint without changing the conversation", ctx do
    {:ok, detail} = create_comment(ctx)

    for status <- ["resolved", "open"], thread_id <- [9_223_372_036_854_775_808, Integer.pow(10, 100)] do
      assert {:error, :invalid_status} =
               Projects.set_comment_thread_status(ctx.scope, ctx.project.id, thread_id, status, detail.thread.revision)
    end

    assert {:error, :not_found} =
             Projects.set_comment_thread_status(
               ctx.scope,
               ctx.project.id,
               9_223_372_036_854_775_807,
               "resolved",
               detail.thread.revision
             )

    assert {:ok, unchanged} = Projects.get_comment_thread(ctx.scope, ctx.project.id, detail.thread.id)
    assert unchanged.thread == detail.thread
    assert unchanged.messages == detail.messages
  end

  test "mentions include effective members, deduplicate IDs and reject outsiders atomically", ctx do
    member = user_fixture()
    workspace_membership_fixture(ctx.workspace, member, "viewer")
    membership_fixture(ctx.project, member, "editor")
    assert {:ok, candidates} = Projects.list_comment_members(ctx.scope, ctx.project.id)
    assert Enum.count(candidates, &(&1.id == member.id)) == 1
    assert {:ok, detail} = create_comment(ctx, %{attrs() | mention_user_ids: [member.id, member.id]})
    assert [%{mentions: [%{id: member_id}]}] = detail.messages
    assert member_id == member.id
    assert Repo.aggregate(Mention, :count) == 1
    outsider = user_fixture()
    assert {:error, :invalid_mention} = create_comment(ctx, %{attrs() | mention_user_ids: [outsider.id]})
    assert Repo.aggregate(Thread, :count) == 1
    assert Repo.aggregate(Message, :count) == 1
  end

  test "reply notifications target the explicit parent and mentions, not every participant", ctx do
    alice = user_fixture()
    bob = user_fixture()
    membership_fixture(ctx.project, alice)
    membership_fixture(ctx.project, bob)
    alice_scope = user_scope_fixture(alice)
    bob_scope = user_scope_fixture(bob)
    {:ok, original} = create_comment(ctx)
    {:ok, alice_reply} = reply(%{ctx | scope: alice_scope}, original)
    alice_message = List.last(alice_reply.messages)
    {:ok, bob_reply} = reply(%{ctx | scope: bob_scope}, original)
    bob_message = List.last(bob_reply.messages)

    refute Enum.any?(
             Platform.list_notifications(alice_scope),
             &(&1.entity_type == "comment" and &1.entity_id == bob_message.id)
           )

    assert Enum.any?(
             Platform.list_notifications(ctx.scope),
             &(&1.entity_type == "comment" and &1.entity_id == bob_message.id and &1.kind == "comment_reply")
           )

    request = %{reply_attrs(original) | parent_id: alice_message.id, mention_user_ids: [ctx.owner.id]}
    {:ok, explicit_reply} = Projects.reply_to_comment_thread(bob_scope, ctx.project.id, original.thread.id, request)
    explicit_message = List.last(explicit_reply.messages)

    assert Enum.any?(
             Platform.list_notifications(alice_scope),
             &(&1.entity_type == "comment" and &1.entity_id == explicit_message.id and &1.kind == "comment_reply")
           )

    assert Enum.any?(
             Platform.list_notifications(ctx.scope),
             &(&1.entity_type == "comment" and &1.entity_id == explicit_message.id and &1.kind == "comment_mention")
           )

    refute Enum.any?(
             Platform.list_notifications(bob_scope),
             &(&1.entity_type == "comment" and &1.entity_id == explicit_message.id)
           )
  end

  test "soft-deleted source remains readable and becomes available on same-row restore", ctx do
    {:ok, detail} = create_comment(ctx)
    assert {:ok, _node, _meta} = Flows.delete_node(ctx.node)
    assert {:ok, unavailable} = Projects.get_comment_thread(ctx.scope, ctx.project.id, detail.thread.id)
    assert unavailable.thread.source.status == "unavailable"
    assert {:error, :source_unavailable} = reply(ctx, detail)

    assert {:error, :source_unavailable} =
             Projects.set_comment_thread_status(
               ctx.scope,
               ctx.project.id,
               detail.thread.id,
               "resolved",
               detail.thread.revision
             )

    assert {:error, :not_found} = Projects.comment_destination(ctx.scope, ctx.project.id, hd(detail.messages).id)
    assert {:ok, %{}} = Projects.flow_comment_counts(ctx.scope, ctx.project.id, ctx.flow.id)
    assert {:ok, _node} = Flows.restore_node(ctx.flow.id, ctx.node.id)
    assert {:ok, available} = Projects.get_comment_thread(ctx.scope, ctx.project.id, detail.thread.id)
    assert available.thread.source.status == "available"
  end

  test "source label follows current content while stored origin survives deletion", ctx do
    {:ok, detail} = create_comment(ctx)
    assert {:ok, updated_node, _meta} = Flows.update_node_data(ctx.node, %{"text" => "<p>Updated source</p>"})
    assert {:ok, current} = Projects.get_comment_thread(ctx.scope, ctx.project.id, detail.thread.id)
    assert current.thread.source.label == "Updated source"
    assert {:ok, _node, _meta} = Flows.delete_node(updated_node)
    assert {:ok, missing} = Projects.get_comment_thread(ctx.scope, ctx.project.id, detail.thread.id)
    assert missing.thread.source.label == "A source worth reviewing"
  end

  test "thread and message pages preserve roots without losing older replies", ctx do
    {:ok, first} = create_comment(ctx)
    {:ok, second} = create_comment(ctx)

    assert {:ok, %{threads: [latest], next_cursor: cursor}} =
             Projects.list_flow_comment_threads(ctx.scope, ctx.project.id, ctx.flow.id, limit: 1)

    assert latest.id == second.thread.id

    assert {:ok, %{threads: [oldest], next_cursor: nil}} =
             Projects.list_flow_comment_threads(ctx.scope, ctx.project.id, ctx.flow.id, limit: 1, cursor: cursor)

    assert oldest.id == first.thread.id
    {:ok, _} = reply(ctx, first)
    {:ok, _} = reply(ctx, first)

    assert {:ok, %{messages: [root, newest], next_cursor: message_cursor}} =
             Projects.get_comment_thread(ctx.scope, ctx.project.id, first.thread.id, limit: 1)

    assert root.id == hd(first.messages).id
    assert newest.id > root.id

    assert {:ok, %{messages: [older], next_cursor: _}} =
             Projects.get_comment_thread(ctx.scope, ctx.project.id, first.thread.id, limit: 1, cursor: message_cursor)

    assert older.id < newest.id and older.id > root.id
  end

  test "review metadata does not change the Flow content snapshot", ctx do
    before = Flows.build_version_snapshot(ctx.flow)
    {:ok, detail} = create_comment(ctx)
    {:ok, _} = reply(ctx, detail)
    assert Flows.build_version_snapshot(ctx.flow) == before
  end

  test "project hard deletion cascades threads, replies and mentions", ctx do
    {:ok, detail} = create_comment(ctx, %{attrs() | mention_user_ids: [ctx.owner.id]})
    {:ok, _} = reply(ctx, detail)
    Repo.delete!(ctx.project)
    refute Repo.exists?(from(t in Thread, where: t.project_id == ^ctx.project.id))
    refute Repo.exists?(from(m in Message, where: m.project_id == ^ctx.project.id))
    assert Repo.aggregate(Mention, :count) == 0
  end

  test "empty, oversized and invalid requests are rejected before persistence", ctx do
    for body <- ["  ", String.duplicate("a", 10_001), nil, <<255>>, "Comment\0body"] do
      assert {:error, :invalid_comment} = create_comment(ctx, %{attrs() | body: body})
    end

    for request_id <- ["", <<255>>, "request\0id"] do
      assert {:error, :invalid_comment} = create_comment(ctx, %{attrs() | client_request_id: request_id})
    end

    assert {:error, :invalid_comment} = create_comment(ctx, %{attrs() | mention_user_ids: ["1"]})
    assert Repo.aggregate(Thread, :count) == 0
  end

  test "outer transactions cannot publish uncommitted comments", ctx do
    assert {:ok, {:error, :comment_requires_outer_transaction}} = Repo.transaction(fn -> create_comment(ctx) end)
    assert Repo.aggregate(Message, :count) == 0
  end

  test "body limits count Unicode code points and reject oversized bytes", ctx do
    combined = String.duplicate("a\u0301", 5_000)
    assert String.length(combined) == 5_000
    assert {:ok, detail} = create_comment(ctx, %{attrs() | body: combined})
    assert hd(detail.messages).body == combined

    assert {:error, :invalid_comment} = create_comment(ctx, %{attrs() | body: combined <> "a"})
    assert {:error, :invalid_comment} = create_comment(ctx, %{attrs() | body: String.duplicate(" ", 40_001)})
    assert Repo.aggregate(Message, :count) == 1
  end

  defp attrs do
    %{body: "Please review this line", client_request_id: Ecto.UUID.generate(), mention_user_ids: []}
  end

  defp create_comment(ctx, request \\ attrs()) do
    Projects.create_flow_node_comment(ctx.scope, ctx.project.id, ctx.flow.id, ctx.node.id, request)
  end

  defp reply_attrs(detail) do
    Map.merge(attrs(), %{body: "Here is my reply", parent_id: hd(detail.messages).id})
  end

  defp reply(ctx, detail) do
    Projects.reply_to_comment_thread(ctx.scope, ctx.project.id, detail.thread.id, reply_attrs(detail))
  end
end
