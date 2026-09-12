defmodule Storyarn.Projects.SceneContextCommentsTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures

  alias Storyarn.Projects
  alias Storyarn.Projects.Comments.Thread
  alias Storyarn.Scenes

  setup do
    owner = user_fixture()
    project = project_fixture(owner)
    scene = scene_fixture(project)
    %{scope: user_scope_fixture(owner), project: project, scene: scene}
  end

  test "draft context validation checks ownership and availability without creating threads", ctx do
    pin = pin_fixture(ctx.scene)
    other_scene = scene_fixture(ctx.project)
    outsider = user_scope_fixture(user_fixture())
    reference = %{type: "scene_pin", id: pin.id, offset: %{x: 2, y: 3}}

    assert {:ok, %{type: "scene_pin", id: id, offset: %{x: 2.0, y: 3.0}}} =
             Projects.validate_scene_comment_context(ctx.scope, ctx.project.id, ctx.scene.id, reference)

    assert id == to_string(pin.id)
    assert {:ok, nil} = Projects.validate_scene_comment_context(ctx.scope, ctx.project.id, ctx.scene.id, nil)

    assert {:error, :not_found} =
             Projects.validate_scene_comment_context(outsider, ctx.project.id, ctx.scene.id, reference)

    assert {:error, :context_unavailable} =
             Projects.validate_scene_comment_context(ctx.scope, ctx.project.id, other_scene.id, reference)

    assert Repo.aggregate(Thread, :count) == 0

    Repo.delete!(pin)

    assert {:error, :context_unavailable} =
             Projects.validate_scene_comment_context(ctx.scope, ctx.project.id, ctx.scene.id, reference)

    assert {:ok, _} = Scenes.delete_scene(ctx.scene)

    assert {:error, :source_unavailable} =
             Projects.validate_scene_comment_context(ctx.scope, ctx.project.id, ctx.scene.id, nil)
  end

  test "deleting a moved pin preserves the final position, identity and messages", ctx do
    pin = pin_fixture(ctx.scene, %{"position_x" => 20, "position_y" => 30})
    detail = create(ctx, "scene_pin", pin, %{x: 2, y: -3})
    assert {:ok, moved} = Scenes.move_pin(pin, 70, 80)
    assert {:ok, _} = Scenes.delete_pin(moved)
    assert_retained(ctx, detail, %{x: 72.0, y: 77.0})

    replacement = pin_fixture(ctx.scene, %{"position_x" => 70, "position_y" => 80, "label" => pin.label})
    refute replacement.id == pin.id
    assert_retained(ctx, detail, %{x: 72.0, y: 77.0})
    assert {:ok, [thread]} = Projects.list_scene_comment_pins(ctx.scope, ctx.project.id, ctx.scene.id)
    assert thread.id == detail.thread.id
  end

  test "zone and annotation deletion use the same canonical origins as the canvas", ctx do
    zone = zone_fixture(ctx.scene)
    annotation = annotation_fixture(ctx.scene)
    zone_detail = create(ctx, "scene_zone", zone, %{x: 4, y: 5})
    annotation_detail = create(ctx, "scene_annotation", annotation, %{x: -2, y: 3})

    assert {:ok, moved_zone} =
             Scenes.update_zone_vertices(zone, %{
               vertices: [
                 %{"x" => 40, "y" => 35},
                 %{"x" => 80, "y" => 30},
                 %{"x" => 50, "y" => 90}
               ]
             })

    assert {:ok, moved_annotation} = Scenes.move_annotation(annotation, 65, 70)
    assert {:ok, _} = Scenes.delete_zone(moved_zone)
    assert {:ok, _} = Scenes.delete_annotation(moved_annotation)
    assert_retained(ctx, zone_detail, %{x: 44.0, y: 35.0})
    assert_retained(ctx, annotation_detail, %{x: 63.0, y: 73.0})
  end

  test "connection deletion and endpoint cascades preserve the final origin before either pin disappears", ctx do
    for deletion <- [:connection, :from_pin, :to_pin] do
      from_pin = pin_fixture(ctx.scene, %{"position_x" => 10, "position_y" => 20})
      to_pin = pin_fixture(ctx.scene, %{"position_x" => 80, "position_y" => 90})
      connection = connection_fixture(ctx.scene, from_pin, to_pin)
      detail = create(ctx, "scene_connection", connection, %{x: 5, y: -4})
      assert {:ok, moved} = Scenes.move_pin(from_pin, 50, 60)

      case deletion do
        :connection -> assert {:ok, _} = Scenes.delete_connection(connection)
        :from_pin -> assert {:ok, _} = Scenes.delete_pin(moved)
        :to_pin -> assert {:ok, _} = Scenes.delete_pin(to_pin)
      end

      assert_retained(ctx, detail, %{x: 55.0, y: 56.0})
    end
  end

  test "free connection paths preserve their moved first waypoint on deletion", ctx do
    assert {:ok, connection} =
             Scenes.create_connection(ctx.scene.id, %{
               "waypoints" => [%{"x" => 10, "y" => 20}, %{"x" => 80, "y" => 90}]
             })

    detail = create(ctx, "scene_connection", connection, %{x: 3, y: 4})

    assert {:ok, moved} =
             Scenes.update_connection_waypoints(connection, %{
               waypoints: [
                 %{"x" => 50, "y" => 60},
                 %{"x" => 80, "y" => 90}
               ]
             })

    assert {:ok, _} = Scenes.delete_connection(moved)
    assert_retained(ctx, detail, %{x: 53.0, y: 64.0})
  end

  test "deletion clamps out of bounds origins while contexts without offsets retain their saved position", ctx do
    pin = pin_fixture(ctx.scene, %{"position_x" => 200, "position_y" => -100})
    offset_detail = create(ctx, "scene_pin", pin, %{x: 5, y: 5})
    absolute_detail = create(ctx, "scene_pin", pin, nil)
    assert {:ok, _} = Scenes.delete_pin(pin)
    assert_retained(ctx, offset_detail, %{x: 100.0, y: 0.0})
    assert_retained(ctx, absolute_detail, %{x: 25.0, y: 35.0})
  end

  test "restoring the same Scene restores access to context without duplicating its thread", ctx do
    pin = pin_fixture(ctx.scene)
    detail = create(ctx, "scene_pin", pin, %{x: 2, y: 3})
    assert {:ok, deleted} = Scenes.delete_scene(ctx.scene)
    assert {:ok, hidden} = Projects.get_comment_thread(ctx.scope, ctx.project.id, detail.thread.id)
    assert hidden.thread.source.status == "unavailable"
    assert {:ok, _} = Scenes.restore_scene(deleted)
    assert {:ok, restored} = Projects.get_comment_thread(ctx.scope, ctx.project.id, detail.thread.id)
    assert restored.thread.source.status == "available"
    assert restored.thread.context.status == "available"
    assert restored.messages == detail.messages
    assert Repo.aggregate(Thread, :count) == 1
  end

  defp create(ctx, type, target, offset) do
    assert {:ok, detail} =
             Projects.create_scene_canvas_comment(ctx.scope, ctx.project.id, ctx.scene.id, %{
               body: "Keep this discussion",
               client_request_id: Ecto.UUID.generate(),
               position: %{x: 25, y: 35},
               context: %{type: type, id: target.id, offset: offset}
             })

    detail
  end

  defp assert_retained(ctx, detail, position) do
    assert {:ok, retained} = Projects.get_comment_thread(ctx.scope, ctx.project.id, detail.thread.id)
    assert retained.thread.position == position
    assert retained.thread.context.status == "unavailable"
    assert retained.thread.context.id == detail.thread.context.id
    assert retained.thread.source.status == "available"
    assert retained.thread.revision == detail.thread.revision
    assert retained.messages == detail.messages
    assert {:ok, destination} = Projects.comment_destination(ctx.scope, ctx.project.id, detail.thread.root_message_id)
    assert destination.scene_id == ctx.scene.id
    assert destination.thread_id == detail.thread.id
  end
end
