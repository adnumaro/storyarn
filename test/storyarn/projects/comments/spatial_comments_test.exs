defmodule Storyarn.Projects.SpatialCommentsTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Flows
  alias Storyarn.Platform
  alias Storyarn.Projects
  alias Storyarn.Projects.Comments.Message
  alias Storyarn.Projects.Comments.Thread

  setup do
    owner = user_fixture()
    project = project_fixture(owner)
    flow = flow_fixture(project, %{name: "Canvas origin"})
    node = node_fixture(flow)
    %{scope: user_scope_fixture(owner), owner: owner, project: project, flow: flow, node: node}
  end

  test "canvas creates retain absolute coordinates and resolve notifications without a node", ctx do
    recipient = user_fixture()
    membership_fixture(ctx.project, recipient, "viewer")
    recipient_scope = user_scope_fixture(recipient)
    request = Map.put(attrs(), :mention_user_ids, [recipient.id])
    assert {:ok, detail} = create_canvas(ctx, request)
    assert detail.thread.position == %{x: 120.5, y: -80.0}
    assert detail.thread.source.type == "flow_canvas"
    assert detail.thread.source.id == ctx.flow.id
    assert detail.thread.source.flow_id == ctx.flow.id
    assert detail.thread.source.label == "Canvas origin"
    assert detail.thread.source.status == "available"
    stored = Repo.get!(Thread, detail.thread.id)
    assert stored.flow_canvas_id == ctx.flow.id
    assert stored.flow_node_id == nil
    assert stored.source_inserted_at == ctx.flow.inserted_at
    message = hd(detail.messages)

    assert {:ok, %{flow_id: flow_id, node_id: nil, thread_id: thread_id}} =
             Projects.comment_destination(recipient_scope, ctx.project.id, message.id)

    assert flow_id == ctx.flow.id
    assert thread_id == detail.thread.id
    key = {ctx.project.id, message.id}

    assert %{^key => %{node_id: nil, thread_id: ^thread_id}} =
             Projects.comment_destinations(recipient_scope, [message.id])

    assert Enum.any?(Platform.list_notifications(recipient_scope), &(&1.entity_id == message.id))
    assert {:ok, %{}} = Projects.flow_comment_counts(ctx.scope, ctx.project.id, ctx.flow.id)
  end

  test "node offsets stay relative when the node moves and omitted positions stay nil", ctx do
    assert {:ok, legacy} =
             Projects.create_flow_node_comment(ctx.scope, ctx.project.id, ctx.flow.id, ctx.node.id, body_attrs())

    assert legacy.thread.position == nil
    position = %{x: 25, y: -10}

    assert {:ok, pinned} =
             Projects.create_flow_node_comment(
               ctx.scope,
               ctx.project.id,
               ctx.flow.id,
               ctx.node.id,
               Map.put(body_attrs(), :position, position)
             )

    assert {:ok, moved_node} = Flows.update_node_position(ctx.node, %{position_x: 700, position_y: -400})
    assert moved_node.position_x == 700
    assert {:ok, retained} = Projects.get_comment_thread(ctx.scope, ctx.project.id, pinned.thread.id)
    assert retained.thread.position == %{x: 25.0, y: -10.0}
    assert retained.thread.source.id == ctx.node.id
  end

  test "canvas create retries include normalized position and reject reuse at another point", ctx do
    request = %{attrs() | position: %{x: 12, y: 34}}
    assert {:ok, first} = create_canvas(ctx, request)
    assert {:ok, repeated} = create_canvas(ctx, %{request | position: %{"x" => 12.0, "y" => 34.0}})
    assert repeated.thread.id == first.thread.id
    assert {:error, :idempotency_conflict} = create_canvas(ctx, %{request | position: %{x: 13, y: 34}})
    assert Repo.aggregate(Message, :count) == 1

    assert {:ok, node_comment} =
             Projects.create_flow_node_comment(ctx.scope, ctx.project.id, ctx.flow.id, ctx.node.id, attrs())

    assert node_comment.thread.position == attrs().position
  end

  test "legacy node requests still match their original persisted fingerprint", ctx do
    request = body_attrs()

    assert {:ok, original} =
             Projects.create_flow_node_comment(ctx.scope, ctx.project.id, ctx.flow.id, ctx.node.id, request)

    legacy_fingerprint =
      {{:create, ctx.flow.id, ctx.node.id}, request.body, []}
      |> :erlang.term_to_binary()
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)

    assert Repo.get!(Message, hd(original.messages).id).request_hash == legacy_fingerprint

    assert {:ok, repeated} =
             Projects.create_flow_node_comment(
               ctx.scope,
               ctx.project.id,
               ctx.flow.id,
               ctx.node.id,
               Map.put(request, :position, nil)
             )

    assert repeated.thread.id == original.thread.id
  end

  test "positions reject nonnumeric, partial and out-of-bounds values before persistence", ctx do
    for position <- [
          nil,
          [],
          %{},
          %{x: 1},
          %{x: "1", y: 2},
          %{x: 1, y: :infinity},
          %{x: 10_000_001, y: 0},
          %{x: 0, y: -10_000_001}
        ] do
      assert {:error, :invalid_position} = create_canvas(ctx, %{attrs() | position: position})
    end

    assert Repo.aggregate(Thread, :count) == 0
    assert {:ok, detail} = create_canvas(ctx, %{attrs() | position: %{x: -10_000_000, y: 10_000_000}})
    assert detail.thread.position == %{x: -10_000_000.0, y: 10_000_000.0}

    assert {:error, :invalid_position} =
             Projects.move_comment_thread(
               ctx.scope,
               ctx.project.id,
               detail.thread.id,
               %{x: 0, y: "NaN"},
               detail.thread.revision
             )
  end

  test "moves preserve the anchor, compare revisions and publish only committed position changes", ctx do
    assert {:ok, detail} = create_canvas(ctx)
    assert :ok = Projects.subscribe_flow_comments(ctx.scope, ctx.project.id, ctx.flow.id)
    flow_id = ctx.flow.id
    next_position = %{x: -50, y: 60}

    assert {:ok, moved} =
             Projects.move_comment_thread(
               ctx.scope,
               ctx.project.id,
               detail.thread.id,
               next_position,
               detail.thread.revision
             )

    assert moved.position == %{x: -50.0, y: 60.0}
    assert moved.source == detail.thread.source
    assert moved.revision == detail.thread.revision + 1
    assert moved.message_count == detail.thread.message_count
    assert_receive {:flow_comments_changed, ^flow_id}

    assert {:error, :stale} =
             Projects.move_comment_thread(ctx.scope, ctx.project.id, moved.id, %{x: 0, y: 0}, detail.thread.revision)

    assert {:ok, unchanged} =
             Projects.move_comment_thread(ctx.scope, ctx.project.id, moved.id, next_position, moved.revision)

    assert unchanged.revision == moved.revision
    refute_receive {:flow_comments_changed, _}
    assert Repo.aggregate(Message, :count) == 1
    assert :ok = Projects.unsubscribe_flow_comments(ctx.project.id, ctx.flow.id)
  end

  test "viewers read pins while move and create recheck editor access and revocation", ctx do
    member = user_fixture()
    scope = user_scope_fixture(member)
    membership = membership_fixture(ctx.project, member, "viewer")
    assert {:ok, detail} = create_canvas(ctx)
    assert {:ok, [_pin]} = Projects.list_flow_comment_pins(scope, ctx.project.id, ctx.flow.id)
    assert {:error, :unauthorized} = create_canvas(%{ctx | scope: scope})

    assert {:error, :unauthorized} =
             Projects.move_comment_thread(scope, ctx.project.id, detail.thread.id, %{x: 1, y: 2}, detail.thread.revision)

    membership |> change(role: "editor") |> Repo.update!()

    assert {:ok, moved} =
             Projects.move_comment_thread(scope, ctx.project.id, detail.thread.id, %{x: 1, y: 2}, detail.thread.revision)

    Repo.delete!(membership)

    assert {:error, :not_found} =
             Projects.move_comment_thread(scope, ctx.project.id, moved.id, %{x: 2, y: 3}, moved.revision)

    assert {:error, :not_found} = Projects.list_flow_comment_pins(scope, ctx.project.id, ctx.flow.id)
  end

  test "canvas replies and state changes work but a deleted Flow is read only until restored", ctx do
    assert {:ok, detail} = create_canvas(ctx)
    reply = Map.put(body_attrs(), :parent_id, detail.thread.root_message_id)
    assert {:ok, replied} = Projects.reply_to_comment_thread(ctx.scope, ctx.project.id, detail.thread.id, reply)

    assert {:ok, resolved} =
             Projects.set_comment_thread_status(
               ctx.scope,
               ctx.project.id,
               detail.thread.id,
               "resolved",
               replied.thread.revision
             )

    assert {:ok, []} = Projects.list_flow_comment_pins(ctx.scope, ctx.project.id, ctx.flow.id)

    assert {:ok, reopened} =
             Projects.set_comment_thread_status(ctx.scope, ctx.project.id, detail.thread.id, "open", resolved.revision)

    assert {:ok, deleted_flow} = Flows.delete_flow(ctx.flow)
    assert {:ok, unavailable} = Projects.get_comment_thread(ctx.scope, ctx.project.id, detail.thread.id)
    assert unavailable.thread.source.status == "unavailable"

    assert {:error, :source_unavailable} =
             Projects.move_comment_thread(ctx.scope, ctx.project.id, detail.thread.id, %{x: 5, y: 6}, reopened.revision)

    assert {:error, :source_unavailable} =
             Projects.reply_to_comment_thread(
               ctx.scope,
               ctx.project.id,
               detail.thread.id,
               Map.put(reply, :client_request_id, Ecto.UUID.generate())
             )

    assert {:ok, []} = Projects.list_flow_comment_pins(ctx.scope, ctx.project.id, ctx.flow.id)
    assert Projects.comment_destinations(ctx.scope, [detail.thread.root_message_id]) == %{}
    assert {:ok, _restored} = Flows.restore_flow(deleted_flow)
    assert {:ok, [pin]} = Projects.list_flow_comment_pins(ctx.scope, ctx.project.id, ctx.flow.id)
    assert pin.id == detail.thread.id
  end

  test "canvas anchors cannot cross projects and node filters never match a canvas ID", ctx do
    other_project = project_fixture()
    other_flow = flow_fixture(other_project)

    assert {:error, :source_unavailable} =
             Projects.create_flow_canvas_comment(ctx.scope, ctx.project.id, other_flow.id, attrs())

    assert {:ok, _detail} = create_canvas(ctx)

    assert {:ok, %{threads: []}} =
             Projects.list_flow_comment_threads(ctx.scope, ctx.project.id, ctx.flow.id, node_id: ctx.flow.id)
  end

  test "pin queries include all open threads beyond one hundred and keep query count constant", ctx do
    assert {:ok, first} = create_canvas(ctx)
    {single, single_count} = measured_pins(ctx)
    assert length(single) == 1

    for _index <- 1..100 do
      assert {:ok, _detail} = create_canvas(ctx)
    end

    {pins, larger_count} = measured_pins(ctx)
    assert length(pins) == 101
    assert hd(pins).id == first.thread.id
    assert Enum.all?(pins, &(&1.preview == "A spatial discussion" and &1.source.status == "available"))
    assert larger_count == single_count
  end

  defp body_attrs, do: %{body: "A spatial discussion", client_request_id: Ecto.UUID.generate(), mention_user_ids: []}
  defp attrs, do: Map.put(body_attrs(), :position, %{x: 120.5, y: -80.0})

  defp create_canvas(ctx, request \\ attrs()),
    do: Projects.create_flow_canvas_comment(ctx.scope, ctx.project.id, ctx.flow.id, request)

  defp measured_pins(ctx) do
    marker = make_ref()
    handler_id = "spatial-comment-pins-#{System.unique_integer([:positive])}"
    :ok = :telemetry.attach(handler_id, [:storyarn, :repo, :query], &record_query/4, {self(), marker})

    try do
      assert {:ok, pins} = Projects.list_flow_comment_pins(ctx.scope, ctx.project.id, ctx.flow.id)
      {pins, query_count(marker, 0)}
    after
      :telemetry.detach(handler_id)
    end
  end

  defp record_query(_event, _measurements, _metadata, {pid, marker}) do
    if self() == pid, do: send(pid, {marker, :query})
  end

  defp query_count(marker, count) do
    receive do
      {^marker, :query} -> query_count(marker, count + 1)
    after
      0 -> count
    end
  end
end
