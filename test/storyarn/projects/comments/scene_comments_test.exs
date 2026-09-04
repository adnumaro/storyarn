defmodule Storyarn.Projects.SceneCommentsTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.Platform
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Projects
  alias Storyarn.Projects.Comments.Message
  alias Storyarn.Projects.Comments.Thread
  alias Storyarn.Projects.Persistence.FlowRecord
  alias Storyarn.Projects.Persistence.SceneRecord
  alias Storyarn.Scenes

  setup do
    owner = user_fixture()
    workspace = workspace_fixture(owner)
    project = project_fixture(owner, %{workspace: workspace})
    scene = scene_fixture(project, %{name: "Review map"})

    %{
      owner: owner,
      scope: user_scope_fixture(owner),
      workspace: workspace,
      project: project,
      scene: scene
    }
  end

  test "creates a percentage Scene anchor and resolves its destinations", ctx do
    recipient = user_fixture()
    membership_fixture(ctx.project, recipient, "viewer")
    recipient_scope = user_scope_fixture(recipient)
    assert :ok = Projects.subscribe_scene_comments(ctx.scope, ctx.project.id, ctx.scene.id)

    request = %{attrs() | mention_user_ids: [recipient.id]}
    assert {:ok, detail} = create_scene(ctx, request)
    scene_id = ctx.scene.id
    assert_receive {:scene_comments_changed, ^scene_id}

    assert {:ok, repeated} = create_scene(ctx, request)
    assert repeated.thread.id == detail.thread.id
    refute_receive {:scene_comments_changed, _}
    assert Repo.aggregate(Thread, :count) == 1
    assert Repo.aggregate(Message, :count) == 1

    assert detail.thread.position == %{x: 25.5, y: 75.0}
    assert detail.thread.source.type == "scene_canvas"
    assert detail.thread.source.id == ctx.scene.id
    assert detail.thread.source.scene_id == ctx.scene.id
    refute Map.has_key?(detail.thread.source, :flow_id)
    assert detail.thread.source.label == "Review map"
    assert detail.thread.source.status == "available"

    stored = Repo.get!(Thread, detail.thread.id)
    assert stored.scene_canvas_id == ctx.scene.id
    assert stored.flow_canvas_id == nil
    assert stored.flow_node_id == nil
    assert stored.source_inserted_at == ctx.scene.inserted_at

    message = hd(detail.messages)

    assert {:ok, %{surface: "scene", scene_id: ^scene_id, thread_id: thread_id}} =
             Projects.comment_destination(recipient_scope, ctx.project.id, message.id)

    assert thread_id == detail.thread.id
    key = {ctx.project.id, message.id}

    assert %{
             ^key => %{
               surface: "scene",
               scene_id: ^scene_id,
               thread_id: ^thread_id,
               project_slug: project_slug,
               workspace_slug: workspace_slug
             }
           } = Projects.comment_destinations(recipient_scope, [message.id])

    assert project_slug == ctx.project.slug
    assert workspace_slug == ctx.workspace.slug
    assert Enum.any?(Platform.list_notifications(recipient_scope), &(&1.entity_id == message.id))
    assert {:ok, %{threads: [listed]}} = Projects.list_scene_comment_threads(ctx.scope, ctx.project.id, scene_id)
    assert listed.id == detail.thread.id
    assert {:ok, [pin]} = Projects.list_scene_comment_pins(ctx.scope, ctx.project.id, scene_id)
    assert pin.id == detail.thread.id
    assert :ok = Projects.unsubscribe_scene_comments(ctx.project.id, scene_id)
  end

  test "requires finite percentage positions on create and move", ctx do
    for position <- [
          nil,
          [],
          %{},
          %{x: 1},
          %{x: "1", y: 2},
          %{x: -0.1, y: 50},
          %{x: 50, y: 100.1},
          %{x: :infinity, y: 50}
        ] do
      assert {:error, :invalid_position} = create_scene(ctx, %{attrs() | position: position})
    end

    assert Repo.aggregate(Thread, :count) == 0
    assert Repo.aggregate(Message, :count) == 0

    assert {:ok, detail} = create_scene(ctx, %{attrs() | position: %{x: 0, y: 100}})
    assert detail.thread.position == %{x: 0.0, y: 100.0}

    assert {:error, :invalid_position} =
             Projects.move_comment_thread(
               ctx.scope,
               ctx.project.id,
               detail.thread.id,
               %{x: 101, y: 50},
               detail.thread.revision
             )

    assert {:ok, retained} = Projects.get_comment_thread(ctx.scope, ctx.project.id, detail.thread.id)
    assert retained.thread.position == %{x: 0.0, y: 100.0}
    assert retained.thread.revision == detail.thread.revision
  end

  test "publishes committed Scene moves once and preserves optimistic revisions", ctx do
    assert {:ok, detail} = create_scene(ctx)
    assert :ok = Projects.subscribe_scene_comments(ctx.scope, ctx.project.id, ctx.scene.id)
    scene_id = ctx.scene.id

    assert {:ok, moved} =
             Projects.move_comment_thread(
               ctx.scope,
               ctx.project.id,
               detail.thread.id,
               %{x: 90, y: 10},
               detail.thread.revision
             )

    assert moved.position == %{x: 90.0, y: 10.0}
    assert moved.revision == detail.thread.revision + 1
    assert moved.source == detail.thread.source
    assert_receive {:scene_comments_changed, ^scene_id}

    assert {:error, :stale} =
             Projects.move_comment_thread(
               ctx.scope,
               ctx.project.id,
               detail.thread.id,
               %{x: 20, y: 20},
               detail.thread.revision
             )

    assert {:ok, unchanged} =
             Projects.move_comment_thread(
               ctx.scope,
               ctx.project.id,
               detail.thread.id,
               %{x: 90, y: 10},
               moved.revision
             )

    assert unchanged.revision == moved.revision
    refute_receive {:scene_comments_changed, _}
    assert :ok = Projects.unsubscribe_scene_comments(ctx.project.id, scene_id)
  end

  test "viewers read Scene discussions while every mutation rechecks editor access", ctx do
    viewer = user_fixture()
    membership_fixture(ctx.project, viewer, "viewer")
    viewer_scope = user_scope_fixture(viewer)
    assert {:ok, detail} = create_scene(ctx)

    assert {:ok, %{threads: [_]}} =
             Projects.list_scene_comment_threads(viewer_scope, ctx.project.id, ctx.scene.id)

    assert {:ok, [_]} = Projects.list_scene_comment_pins(viewer_scope, ctx.project.id, ctx.scene.id)
    assert {:ok, _} = Projects.get_comment_thread(viewer_scope, ctx.project.id, detail.thread.id)
    assert {:error, :unauthorized} = create_scene(%{ctx | scope: viewer_scope})

    assert {:error, :unauthorized} =
             Projects.move_comment_thread(
               viewer_scope,
               ctx.project.id,
               detail.thread.id,
               %{x: 30, y: 30},
               detail.thread.revision
             )

    assert {:error, :unauthorized} =
             Projects.reply_to_comment_thread(viewer_scope, ctx.project.id, detail.thread.id, %{
               body: "A reply",
               parent_id: detail.thread.root_message_id,
               client_request_id: Ecto.UUID.generate(),
               mention_user_ids: []
             })

    assert {:error, :unauthorized} =
             Projects.set_comment_thread_status(
               viewer_scope,
               ctx.project.id,
               detail.thread.id,
               "resolved",
               detail.thread.revision
             )
  end

  test "soft deletion hides a Scene source and restoring the same row revives it", ctx do
    assert {:ok, detail} = create_scene(ctx)
    root_message_id = detail.thread.root_message_id
    assert {:ok, deleted_scene} = Scenes.delete_scene(ctx.scene)

    assert {:ok, unavailable} = Projects.get_comment_thread(ctx.scope, ctx.project.id, detail.thread.id)
    assert unavailable.thread.source.status == "unavailable"
    assert unavailable.thread.source.label == "Review map"
    assert {:ok, []} = Projects.list_scene_comment_pins(ctx.scope, ctx.project.id, ctx.scene.id)
    assert Projects.comment_destinations(ctx.scope, [root_message_id]) == %{}

    assert {:error, :source_unavailable} =
             Projects.move_comment_thread(
               ctx.scope,
               ctx.project.id,
               detail.thread.id,
               %{x: 30, y: 30},
               detail.thread.revision
             )

    assert {:error, :source_unavailable} =
             Projects.reply_to_comment_thread(ctx.scope, ctx.project.id, detail.thread.id, %{
               body: "A reply",
               parent_id: root_message_id,
               client_request_id: Ecto.UUID.generate(),
               mention_user_ids: []
             })

    assert {:error, :source_unavailable} =
             Projects.set_comment_thread_status(
               ctx.scope,
               ctx.project.id,
               detail.thread.id,
               "resolved",
               detail.thread.revision
             )

    assert {:ok, _restored_scene} = Scenes.restore_scene(deleted_scene)
    assert {:ok, [pin]} = Projects.list_scene_comment_pins(ctx.scope, ctx.project.id, ctx.scene.id)
    assert pin.id == detail.thread.id
    assert pin.source.status == "available"
  end

  test "equal Flow and Scene IDs remain isolated in lists, pins, topics and destinations", ctx do
    shared_id = 2_000_000_000 + rem(System.unique_integer([:positive]), 100_000_000)
    now = TimeHelpers.now()

    Repo.insert!(%FlowRecord{
      id: shared_id,
      project_id: ctx.project.id,
      name: "Colliding flow",
      shortcut: "collision-flow-#{shared_id}",
      inserted_at: now,
      updated_at: now
    })

    Repo.insert!(%SceneRecord{
      id: shared_id,
      project_id: ctx.project.id,
      name: "Colliding scene",
      shortcut: "collision-scene-#{shared_id}",
      inserted_at: now,
      updated_at: now
    })

    assert :ok = Projects.subscribe_flow_comments(ctx.scope, ctx.project.id, shared_id)
    assert :ok = Projects.subscribe_scene_comments(ctx.scope, ctx.project.id, shared_id)

    flow_attrs = %{attrs() | client_request_id: Ecto.UUID.generate()}
    scene_attrs = %{attrs() | client_request_id: Ecto.UUID.generate()}

    assert {:ok, flow_detail} =
             Projects.create_flow_canvas_comment(ctx.scope, ctx.project.id, shared_id, flow_attrs)

    assert_receive {:flow_comments_changed, ^shared_id}

    assert {:ok, scene_detail} =
             Projects.create_scene_canvas_comment(ctx.scope, ctx.project.id, shared_id, scene_attrs)

    assert_receive {:scene_comments_changed, ^shared_id}

    assert {:ok, %{threads: [listed_flow]}} =
             Projects.list_flow_comment_threads(ctx.scope, ctx.project.id, shared_id)

    assert listed_flow.id == flow_detail.thread.id
    assert listed_flow.source.type == "flow_canvas"

    assert {:ok, %{threads: [listed_scene]}} =
             Projects.list_scene_comment_threads(ctx.scope, ctx.project.id, shared_id)

    assert listed_scene.id == scene_detail.thread.id
    assert listed_scene.source.type == "scene_canvas"

    assert {:ok, [flow_pin]} = Projects.list_flow_comment_pins(ctx.scope, ctx.project.id, shared_id)
    assert flow_pin.id == flow_detail.thread.id
    assert {:ok, [scene_pin]} = Projects.list_scene_comment_pins(ctx.scope, ctx.project.id, shared_id)
    assert scene_pin.id == scene_detail.thread.id

    flow_message_id = flow_detail.thread.root_message_id
    scene_message_id = scene_detail.thread.root_message_id
    project_id = ctx.project.id
    destinations = Projects.comment_destinations(ctx.scope, [flow_message_id, scene_message_id])

    assert %{
             {^project_id, ^flow_message_id} => %{surface: "flow", flow_id: ^shared_id},
             {^project_id, ^scene_message_id} => %{surface: "scene", scene_id: ^shared_id}
           } = destinations

    assert :ok = Projects.unsubscribe_flow_comments(ctx.project.id, shared_id)
    assert :ok = Projects.unsubscribe_scene_comments(ctx.project.id, shared_id)
  end

  test "cannot create a Scene anchor across project boundaries", ctx do
    other_project = project_fixture()
    other_scene = scene_fixture(other_project)

    assert {:error, :source_unavailable} =
             Projects.create_scene_canvas_comment(ctx.scope, ctx.project.id, other_scene.id, attrs())
  end

  defp attrs do
    %{
      body: "Review this place",
      position: %{x: 25.5, y: 75},
      client_request_id: Ecto.UUID.generate(),
      mention_user_ids: []
    }
  end

  defp create_scene(ctx, request \\ attrs()) do
    Projects.create_scene_canvas_comment(ctx.scope, ctx.project.id, ctx.scene.id, request)
  end
end
