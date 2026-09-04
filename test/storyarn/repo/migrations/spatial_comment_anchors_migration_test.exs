defmodule Storyarn.Repo.Migrations.SpatialCommentAnchorsMigrationTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Projects
  alias Storyarn.Projects.Comments.Message
  alias Storyarn.Projects.Comments.Thread
  alias Storyarn.Repo.Migrations.AddSpatialCommentAnchors

  if !Code.ensure_loaded?(AddSpatialCommentAnchors) do
    Code.require_file(
      Path.expand("../../../../priv/repo/migrations/20260904170000_add_spatial_comment_anchors.exs", __DIR__)
    )
  end

  setup do
    owner = user_fixture()
    scope = user_scope_fixture(owner)
    project = project_fixture(owner)
    flow = flow_fixture(project)
    node = node_fixture(flow)

    {:ok, node_detail} =
      Projects.create_flow_node_comment(scope, project.id, flow.id, node.id, attrs())

    {:ok, canvas_detail} = Projects.create_flow_canvas_comment(scope, project.id, flow.id, attrs())

    %{
      project: project,
      flow: flow,
      node: node,
      node_thread: Repo.get!(Thread, node_detail.thread.id),
      canvas_thread: Repo.get!(Thread, canvas_detail.thread.id)
    }
  end

  test "node anchors cannot point to a different existing node", ctx do
    other_node = node_fixture(ctx.flow)

    assert_anchor_violation(
      "UPDATE comment_threads SET flow_node_id = $1 WHERE id = $2",
      [other_node.id, ctx.node_thread.id]
    )

    assert Repo.get!(Thread, ctx.node_thread.id) == ctx.node_thread
    assert Repo.aggregate(Message, :count) == 2
  end

  test "canvas anchors cannot point to a different existing flow or change their source identity", ctx do
    other_flow = flow_fixture(ctx.project)

    assert_anchor_violation(
      "UPDATE comment_threads SET flow_canvas_id = $1 WHERE id = $2",
      [other_flow.id, ctx.canvas_thread.id]
    )

    assert_anchor_violation(
      "UPDATE comment_threads SET source_id = $1, container_id = $1 WHERE id = $2",
      [other_flow.id, ctx.canvas_thread.id]
    )

    assert Repo.get!(Thread, ctx.canvas_thread.id) == ctx.canvas_thread
    assert Repo.aggregate(Message, :count) == 2
  end

  test "hard deletion permits null anchors while preserving source identity, positions and messages", ctx do
    messages = Repo.all(from message in Message, order_by: message.id)
    Repo.delete!(ctx.node)
    Repo.delete!(ctx.flow)

    assert Repo.get!(Thread, ctx.node_thread.id) == %{ctx.node_thread | flow_node_id: nil}
    assert Repo.get!(Thread, ctx.canvas_thread.id) == %{ctx.canvas_thread | flow_canvas_id: nil}
    assert Repo.all(from message in Message, order_by: message.id) == messages
  end

  test "spatial rollback fails explicitly before touching existing comments or spatial metadata", ctx do
    messages = Repo.all(from message in Message, order_by: message.id)

    assert_raise Ecto.MigrationError, ~r/irreversible.*Preserve comment threads and their history/, fn ->
      AddSpatialCommentAnchors.down()
    end

    assert Repo.get!(Thread, ctx.node_thread.id) == ctx.node_thread
    assert Repo.get!(Thread, ctx.canvas_thread.id) == ctx.canvas_thread
    assert Repo.all(from message in Message, order_by: message.id) == messages
  end

  defp attrs do
    %{
      body: "Keep the source and discussion history",
      position: %{x: 12.5, y: -30.0},
      client_request_id: Ecto.UUID.generate(),
      mention_user_ids: []
    }
  end

  defp assert_anchor_violation(sql, params) do
    assert {:error, %Postgrex.Error{postgres: %{code: :check_violation, constraint: "comment_threads_anchor_identity"}}} =
             Repo.query(sql, params, mode: :savepoint)
  end
end
