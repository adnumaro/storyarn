defmodule StoryarnWeb.SceneLive.Handlers.CollaborationHandlersTest do
  @moduledoc """
  Tests for ephemeral drag relay broadcasting and remote change handling
  in the scene collaboration handlers.
  """

  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.ScenesFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Collaboration
  alias Storyarn.Repo

  defp scene_url(project, scene) do
    ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
  end

  defp setup_scene(%{conn: conn, user: user}) do
    project = project_fixture(user) |> Repo.preload(:workspace)
    scene = scene_fixture(project)
    {:ok, project: project, scene: scene, conn: conn, user: user}
  end

  # =========================================================================
  # Drag relay events (handle_event → PubSub broadcast)
  # =========================================================================

  describe "drag_pin relay" do
    setup [:register_and_log_in_user, :setup_scene]

    test "broadcasts pin_dragging to PubSub subscribers", ctx do
      pin = pin_fixture(ctx.scene)
      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      # Subscribe to the scene's changes topic
      scope = {:scene, ctx.scene.id}
      Collaboration.subscribe_changes(scope)

      render_hook(view, "drag_pin", %{
        "id" => pin.id,
        "position_x" => 42.5,
        "position_y" => 73.1
      })

      assert_receive {:remote_change, :pin_dragging, payload}
      assert payload.id == pin.id
      assert payload.position_x == 42.5
      assert payload.position_y == 73.1
      assert payload.user_id
    end

    test "silently ignores malformed params", ctx do
      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      # Missing required fields — should not crash
      render_hook(view, "drag_pin", %{"id" => "abc"})

      # Non-numeric positions — should not crash
      render_hook(view, "drag_pin", %{
        "id" => "abc",
        "position_x" => "not_a_number",
        "position_y" => 1.0
      })

      # View still alive
      assert render(view) =~ "scene-canvas"
    end
  end

  describe "drag_annotation relay" do
    setup [:register_and_log_in_user, :setup_scene]

    test "broadcasts annotation_dragging to PubSub subscribers", ctx do
      annotation = annotation_fixture(ctx.scene)
      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      scope = {:scene, ctx.scene.id}
      Collaboration.subscribe_changes(scope)

      render_hook(view, "drag_annotation", %{
        "id" => annotation.id,
        "position_x" => 10.0,
        "position_y" => 20.0
      })

      assert_receive {:remote_change, :annotation_dragging, payload}
      assert payload.id == annotation.id
      assert payload.position_x == 10.0
      assert payload.position_y == 20.0
    end

    test "silently ignores malformed params", ctx do
      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      render_hook(view, "drag_annotation", %{})
      assert render(view) =~ "scene-canvas"
    end
  end

  describe "drag_zone relay" do
    setup [:register_and_log_in_user, :setup_scene]

    test "broadcasts zone_dragging to PubSub subscribers", ctx do
      zone = zone_fixture(ctx.scene)
      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      scope = {:scene, ctx.scene.id}
      Collaboration.subscribe_changes(scope)

      vertices = [%{"x" => 10.0, "y" => 20.0}, %{"x" => 30.0, "y" => 40.0}]

      render_hook(view, "drag_zone", %{
        "id" => zone.id,
        "vertices" => vertices
      })

      assert_receive {:remote_change, :zone_dragging, payload}
      assert payload.id == zone.id
      assert payload.vertices == vertices
    end

    test "silently ignores non-list vertices", ctx do
      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      render_hook(view, "drag_zone", %{"id" => "abc", "vertices" => "not_a_list"})
      assert render(view) =~ "scene-canvas"
    end
  end

  # =========================================================================
  # Remote change handling (handle_info → push_event to JS)
  # =========================================================================

  describe "remote drag change handling" do
    setup [:register_and_log_in_user, :setup_scene]

    test "pin_dragging remote change pushes pin_drag_update event", ctx do
      pin = pin_fixture(ctx.scene)
      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      # Simulate a remote change arriving via PubSub
      scope = {:scene, ctx.scene.id}

      Collaboration.broadcast_change(scope, :pin_dragging, %{
        id: pin.id,
        position_x: 55.0,
        position_y: 66.0
      })

      # The LiveView should push pin_drag_update to the client
      assert_push_event(view, "pin_drag_update", %{
        id: _,
        position_x: 55.0,
        position_y: 66.0
      })
    end

    test "annotation_dragging remote change pushes annotation_drag_update event", ctx do
      annotation = annotation_fixture(ctx.scene)
      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      scope = {:scene, ctx.scene.id}

      Collaboration.broadcast_change(scope, :annotation_dragging, %{
        id: annotation.id,
        position_x: 11.0,
        position_y: 22.0
      })

      assert_push_event(view, "annotation_drag_update", %{
        id: _,
        position_x: 11.0,
        position_y: 22.0
      })
    end

    test "zone_dragging remote change pushes zone_drag_update event", ctx do
      zone = zone_fixture(ctx.scene)
      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      scope = {:scene, ctx.scene.id}
      vertices = [%{x: 10.0, y: 20.0}, %{x: 30.0, y: 40.0}]

      Collaboration.broadcast_change(scope, :zone_dragging, %{
        id: zone.id,
        vertices: vertices
      })

      assert_push_event(view, "zone_drag_update", %{
        id: _,
        vertices: ^vertices
      })
    end
  end
end
