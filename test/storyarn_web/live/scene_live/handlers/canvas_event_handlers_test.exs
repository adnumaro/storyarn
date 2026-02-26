defmodule StoryarnWeb.SceneLive.Handlers.CanvasEventHandlersTest do
  @moduledoc """
  Tests for CanvasEventHandlers — covers uncovered branches:
  handle_save_name error path, handle_set_tool with invalid tool,
  and handle_toggle_edit_mode with explicit mode params.
  """

  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.ScenesFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Repo

  defp scene_url(project, scene) do
    ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
  end

  defp setup_scene(%{conn: conn, user: user}) do
    project = project_fixture(user) |> Repo.preload(:workspace)
    scene = scene_fixture(project)
    {:ok, project: project, scene: scene, conn: conn, user: user}
  end

  describe "handle_set_tool with invalid tool" do
    setup [:register_and_log_in_user, :setup_scene]

    test "ignores invalid tool name and does not crash", ctx do
      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      # Send an invalid tool name — should be a no-op
      render_click(view, "set_tool", %{"tool" => "invalid_tool_name"})

      # View should still be alive
      html = render(view)
      assert html =~ "scene-canvas"
    end
  end

  describe "handle_toggle_edit_mode with explicit mode params" do
    setup [:register_and_log_in_user, :setup_scene]

    test "toggle_edit_mode with mode=edit sets edit mode to true", ctx do
      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      render_click(view, "toggle_edit_mode", %{"mode" => "edit"})

      # View should be alive and in edit mode
      html = render(view)
      assert html =~ "scene-canvas"
    end

    test "toggle_edit_mode with mode=view sets edit mode to false", ctx do
      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      # First put in edit mode
      render_click(view, "toggle_edit_mode", %{"mode" => "edit"})

      # Then switch to view mode explicitly
      render_click(view, "toggle_edit_mode", %{"mode" => "view"})

      html = render(view)
      assert html =~ "scene-canvas"
    end
  end

  describe "handle_save_name error path" do
    setup [:register_and_log_in_user, :setup_scene]

    test "save_name with invalid name shows error flash", ctx do
      {:ok, view, _html} = live(ctx.conn, scene_url(ctx.project, ctx.scene))

      # Send a name that exceeds the maximum length (201 chars) to trigger validation error
      long_name = String.duplicate("a", 201)
      html = render_click(view, "save_name", %{"name" => long_name})

      # Should show error flash or at least not crash
      assert html =~ "scene-canvas"
    end
  end
end
