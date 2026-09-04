defmodule Storyarn.Repo.Migrations.SceneCommentAnchorsMigrationTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures

  alias Storyarn.Projects
  alias Storyarn.Projects.Comments.Message
  alias Storyarn.Projects.Comments.Thread
  alias Storyarn.Repo.Migrations.AddSceneCommentAnchors
  alias Storyarn.Scenes

  if !Code.ensure_loaded?(AddSceneCommentAnchors) do
    Code.require_file(
      Path.expand("../../../../priv/repo/migrations/20260904210000_add_scene_comment_anchors.exs", __DIR__)
    )
  end

  setup do
    owner = user_fixture()
    scope = user_scope_fixture(owner)
    project = project_fixture(owner)
    scene = scene_fixture(project)

    {:ok, detail} =
      Projects.create_scene_canvas_comment(scope, project.id, scene.id, attrs())

    %{
      project: project,
      scene: scene,
      thread: Repo.get!(Thread, detail.thread.id)
    }
  end

  test "Scene anchors cannot point to another existing Scene", ctx do
    other_scene = scene_fixture(ctx.project)

    assert_constraint_violation(
      "UPDATE comment_threads SET scene_canvas_id = $1 WHERE id = $2",
      [other_scene.id, ctx.thread.id],
      "comment_threads_anchor_identity"
    )

    assert Repo.get!(Thread, ctx.thread.id) == ctx.thread
    assert Repo.aggregate(Message, :count) == 1
  end

  test "Scene anchors cannot acquire a Flow pointer or out-of-range position", ctx do
    flow = flow_fixture(ctx.project)

    assert_constraint_violation(
      "UPDATE comment_threads SET flow_canvas_id = $1 WHERE id = $2",
      [flow.id, ctx.thread.id],
      "comment_threads_anchor_shape"
    )

    assert_constraint_violation(
      "UPDATE comment_threads SET position_x = 100.01 WHERE id = $1",
      [ctx.thread.id],
      "comment_threads_position"
    )

    assert Repo.get!(Thread, ctx.thread.id) == ctx.thread
    assert Repo.aggregate(Message, :count) == 1
  end

  test "hard deletion nulls only the Scene pointer and preserves immutable context and messages", ctx do
    messages = Repo.all(from message in Message, order_by: message.id)
    assert {:ok, _deleted_scene} = Scenes.hard_delete_scene(ctx.scene)

    assert Repo.get!(Thread, ctx.thread.id) == %{ctx.thread | scene_canvas_id: nil}
    assert Repo.all(from message in Message, order_by: message.id) == messages
  end

  test "Scene anchor rollback fails before removing discussion metadata", ctx do
    messages = Repo.all(from message in Message, order_by: message.id)

    assert_raise Ecto.MigrationError, ~r/irreversible.*Preserve comment threads and their history/, fn ->
      AddSceneCommentAnchors.down()
    end

    assert Repo.get!(Thread, ctx.thread.id) == ctx.thread
    assert Repo.all(from message in Message, order_by: message.id) == messages
  end

  defp attrs do
    %{
      body: "Keep this Scene discussion",
      position: %{x: 10, y: 90},
      client_request_id: Ecto.UUID.generate(),
      mention_user_ids: []
    }
  end

  defp assert_constraint_violation(sql, params, constraint) do
    assert {:error, %Postgrex.Error{postgres: %{code: :check_violation, constraint: ^constraint}}} =
             Repo.query(sql, params, mode: :savepoint)
  end
end
