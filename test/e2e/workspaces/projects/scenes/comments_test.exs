defmodule StoryarnWeb.E2E.SceneCommentsTest do
  use PhoenixTest.Playwright.Case, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
  import StoryarnWeb.E2EHelpers

  alias PlaywrightEx.Page
  alias Storyarn.Platform.Collaboration
  alias Storyarn.Projects
  alias Storyarn.Repo
  alias Storyarn.Scenes

  @moduletag :e2e

  test "a spatial Scene discussion preserves its draft and position across moves and deep links", %{conn: conn} do
    user = user_fixture()
    project = user |> project_fixture() |> Repo.preload(:workspace)
    scene = scene_fixture(project, %{name: "Canvas review"})
    path = "/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
    feedback = "Clarify what the player discovers in this part of the map."

    session =
      conn
      |> authenticate(user)
      |> visit(path)
      |> assert_has("[data-testid='scene-canvas-comments']", timeout: 20_000)
      |> click("#scene-comments-create-mode")
      |> assert_has("#scene-comments-create-mode[aria-pressed='true']")
      |> click_at("#scene-canvas-#{scene.id}", 140, 120)
      |> assert_has("#scene-comment-draft-pin")
      |> fill_in("#scene-comment-body", "New thread", with: feedback)
      |> drag_pin("#scene-comment-draft-pin", 70, 40)
      |> assert_has("#scene-comment-body", value: feedback)
      |> click("#scene-comment-send")
      |> assert_has("#scene-comment-popover", text: feedback)

    scope = user_scope_fixture(user)
    assert {:ok, [thread]} = Projects.list_scene_comment_pins(scope, project.id, scene.id)
    assert thread.source.type == "scene_canvas"
    assert thread.source.scene_id == scene.id

    initial_position = thread.position

    session =
      session
      |> click("#scene-comment-popover-close")
      |> drag_pin("#scene-comment-pin-#{thread.id}", 80, 40)
      |> click("#scene-comment-pin-#{thread.id}")
      |> assert_has("#scene-comment-popover", text: feedback)

    assert {:ok, [moved]} = Projects.list_scene_comment_pins(scope, project.id, scene.id)
    assert moved.position.x > initial_position.x
    assert moved.position.y > initial_position.y

    session
    |> visit(path <> "?thread=#{thread.id}")
    |> assert_has("#scene-comment-popover", text: feedback, timeout: 20_000)
    |> assert_has("#scene-comment-pin-#{thread.id}[aria-expanded='true']")
  end

  test "magnetic dragging previews context before saving and detaches without replacing the conversation", %{conn: conn} do
    user = user_fixture()
    scope = user_scope_fixture(user)
    project = user |> project_fixture() |> Repo.preload(:workspace)
    scene = scene_fixture(project, %{name: "Magnetic Scene review"})
    target = pin_fixture(scene, %{"label" => "Northern gate"})
    feedback = "Explain how the player can enter the northern gate."
    created = create_comment(scope, project, scene, feedback, %{x: 20, y: 30})
    thread_id = created.thread.id
    pin = "#scene-comment-pin-#{thread_id}"
    path = scene_path(project, scene)

    session =
      conn
      |> authenticate(user)
      |> visit(path)
      |> assert_has("#{pin}[aria-busy=false]", timeout: 20_000)
      |> assert_has("#scene-comment-magnetism-toggle[aria-pressed=true]")
      |> drag_over_scene_pin(pin, target.label)
      |> assert_has("#scene-comment-snap-preview", text: target.label)

    assert {:ok, previewing} = Projects.get_comment_thread(scope, project.id, thread_id)
    assert previewing.thread.position == created.thread.position
    assert previewing.thread.revision == created.thread.revision
    assert is_nil(previewing.thread.context)

    session =
      session
      |> release_pin()
      |> assert_has("#{pin}[aria-busy=false]")
      |> click(pin)
      |> assert_has("#scene-comment-popover", text: feedback)
      |> assert_has("#scene-comment-context", text: target.label)

    assert {:ok, attached} = Projects.get_comment_thread(scope, project.id, thread_id)
    assert attached.thread.source.type == "scene_canvas"
    assert attached.thread.source.scene_id == scene.id
    assert attached.thread.context.type == "scene_pin"
    assert attached.thread.context.id == to_string(target.id)
    assert attached.thread.revision == created.thread.revision + 1
    assert_in_delta attached.thread.position.x, target.position_x + attached.thread.context.offset.x, 0.001
    assert_in_delta attached.thread.position.y, target.position_y + attached.thread.context.offset.y, 0.001

    session =
      session
      |> reload_page()
      |> assert_has("#{pin}[aria-busy=false]", timeout: 20_000)
      |> click(pin)
      |> assert_has("#scene-comment-context", text: target.label)
      |> click("#scene-comment-popover-close")
      |> click("#scene-comment-magnetism-toggle")
      |> assert_has("#scene-comment-magnetism-toggle[aria-pressed=false]")
      |> press(pin, "ArrowRight")

    assert {:ok, previewing_detach} = Projects.get_comment_thread(scope, project.id, thread_id)
    assert previewing_detach.thread.revision == attached.thread.revision
    assert previewing_detach.thread.context == attached.thread.context

    session
    |> press(pin, "Enter")
    |> assert_has("#{pin}[aria-busy=false]")
    |> visit(path <> "?thread=#{thread_id}")
    |> assert_has("#{pin}[aria-expanded=true]", timeout: 20_000)
    |> assert_has("#scene-comment-message-#{created.thread.root_message_id}", text: feedback)
    |> refute_has("#scene-comment-context")

    assert {:ok, [detached]} = Projects.list_scene_comment_pins(scope, project.id, scene.id)
    assert detached.id == thread_id
    assert detached.root_message_id == created.thread.root_message_id
    assert detached.message_count == 1
    assert detached.revision == attached.thread.revision + 1
    assert detached.position.x > attached.thread.position.x
    assert is_nil(detached.context)
  end

  test "a draft keeps its text when its magnetic context is deleted by a collaborator", %{conn: conn} do
    user = user_fixture()
    scope = user_scope_fixture(user)
    project = user |> project_fixture() |> Repo.preload(:workspace)
    scene = scene_fixture(project, %{name: "Recoverable Scene draft"})
    target = pin_fixture(scene, %{"label" => "Replaced entrance"})
    feedback = "Keep this discussion even if the entrance moves elsewhere."

    session =
      conn
      |> authenticate(user)
      |> visit(scene_path(project, scene))
      |> assert_has("[data-testid='scene-canvas-comments']", timeout: 20_000)
      |> click("#scene-comments-create-mode")
      |> assert_has("#scene-comments-create-mode[aria-pressed=true]")
      |> click_at("#scene-canvas-#{scene.id}", 140, 120)
      |> assert_has("#scene-comment-draft-pin")
      |> fill_in("#scene-comment-body", "New thread", with: feedback)
      |> drag_over_scene_pin("#scene-comment-draft-pin", target.label)
      |> assert_has("#scene-comment-snap-preview", text: target.label)
      |> release_pin()
      |> assert_has("#scene-comment-draft-pin[aria-busy=false]")
      |> assert_has("#scene-comment-body", value: feedback)

    assert {:ok, _deleted} = Scenes.delete_pin(target)
    Collaboration.broadcast_change({:scene, scene.id}, :pin_deleted, %{id: target.id})

    session
    |> assert_scene_pin_visibility(target.label, false)
    |> assert_has("#scene-comment-draft-pin[aria-busy=false]")
    |> assert_has("#scene-comment-body", value: feedback)
    |> click("#scene-comment-send")
    |> assert_has("#scene-comment-popover", text: feedback)
    |> refute_has("#scene-comment-context")

    assert {:ok, [thread]} = Projects.list_scene_comment_pins(scope, project.id, scene.id)
    assert thread.source.type == "scene_canvas"
    assert thread.source.scene_id == scene.id
    assert is_nil(thread.context)
    assert thread.message_count == 1
  end

  test "a snapped draft restores its text and context after reload", %{conn: conn} do
    user = user_fixture()
    scope = user_scope_fixture(user)
    project = user |> project_fixture() |> Repo.preload(:workspace)
    scene = scene_fixture(project, %{name: "Recoverable magnetic draft"})
    target = pin_fixture(scene, %{"label" => "Arrival point"})
    feedback = "Introduce the village as soon as the player arrives."

    conn
    |> authenticate(user)
    |> visit(scene_path(project, scene))
    |> assert_has("[data-testid='scene-canvas-comments']", timeout: 20_000)
    |> click("#scene-comments-create-mode")
    |> assert_has("#scene-comments-create-mode[aria-pressed=true]")
    |> click_at("#scene-canvas-#{scene.id}", 140, 120)
    |> assert_has("#scene-comment-draft-pin")
    |> fill_in("#scene-comment-body", "New thread", with: feedback)
    |> drag_over_scene_pin("#scene-comment-draft-pin", target.label)
    |> assert_has("#scene-comment-snap-preview", text: target.label)
    |> release_pin()
    |> assert_has("#scene-comment-draft-pin[aria-busy=false]")
    |> reload_page()
    |> assert_has("#scene-comment-draft-pin[aria-busy=false]", timeout: 20_000)
    |> assert_has("#scene-comment-body", value: feedback)
    |> click("#scene-comment-send")
    |> assert_has("#scene-comment-popover", text: feedback)
    |> assert_has("#scene-comment-context", text: target.label)

    assert {:ok, [thread]} = Projects.list_scene_comment_pins(scope, project.id, scene.id)
    assert thread.source.type == "scene_canvas"
    assert thread.source.scene_id == scene.id
    assert thread.context.type == "scene_pin"
    assert thread.context.id == to_string(target.id)
    assert thread.message_count == 1
  end

  test "a contextual badge follows its Scene pin through dragging zoom and pan", %{conn: conn} do
    user = user_fixture()
    scope = user_scope_fixture(user)
    project = user |> project_fixture() |> Repo.preload(:workspace)
    scene = scene_fixture(project, %{name: "Moving Scene context"})
    target = pin_fixture(scene, %{"label" => "Movable landmark", "position_x" => 20, "position_y" => 20})
    offset = %{x: 5, y: 4}

    created =
      create_comment(scope, project, scene, "Keep this observation near the landmark.", %{x: 25, y: 24}, %{
        type: "scene_pin",
        id: target.id,
        offset: offset
      })

    pin = "#scene-comment-pin-#{created.thread.id}"

    session =
      conn
      |> authenticate(user)
      |> visit(scene_path(project, scene))
      |> assert_has("#{pin}[aria-busy=false]", timeout: 20_000)
      |> assert_pin_offset(target.label, pin, offset)
      |> drag_scene_pin(target.label, 65, 35)
      |> assert_pin_offset(target.label, pin, offset)
      |> zoom_scene(scene.id)
      |> assert_pin_offset(target.label, pin, offset)
      |> click("button[aria-label='Pan']")
      |> assert_has("button[aria-label='Pan'].dock-btn-active")
      |> pan_scene(scene.id, pin, 35, -25)
      |> assert_pin_offset(target.label, pin, offset)
      |> visit(scene_path(project, scene) <> "?thread=#{created.thread.id}")
      |> assert_has("#{pin}[aria-expanded=true]", timeout: 20_000)
      |> assert_has("#scene-comment-context", text: target.label)
      |> assert_pin_offset(target.label, pin, offset)

    moved_target = Scenes.get_pin!(scene.id, target.id)
    assert moved_target.position_x > target.position_x
    assert moved_target.position_y > target.position_y
    assert {:ok, [persisted]} = Projects.list_scene_comment_pins(scope, project.id, scene.id)
    assert persisted.id == created.thread.id
    assert persisted.context.offset == offset
    assert persisted.revision == created.thread.revision

    assert {:ok, _deleted} = Scenes.delete_pin(moved_target)
    Collaboration.broadcast_change({:scene, scene.id}, :pin_deleted, %{id: target.id})

    session
    |> assert_scene_pin_visibility(target.label, false)
    |> assert_has("#scene-comment-message-#{created.thread.root_message_id}")
    |> assert_has("#scene-comment-context", text: "unavailable")
    |> reload_page()
    |> assert_has("#{pin}[aria-expanded=true]", timeout: 20_000)
    |> assert_has("#scene-comment-context", text: "unavailable")

    assert {:ok, [orphaned]} = Projects.list_scene_comment_pins(scope, project.id, scene.id)
    assert orphaned.id == created.thread.id
    assert orphaned.context.status == "unavailable"
    assert orphaned.message_count == 1
    assert_in_delta orphaned.position.x, moved_target.position_x + offset.x, 0.001
    assert_in_delta orphaned.position.y, moved_target.position_y + offset.y, 0.001
  end

  test "revealing hidden context affects only the current canvas and preserves layer settings", %{conn: conn} do
    user = user_fixture()
    scope = user_scope_fixture(user)
    project = user |> project_fixture() |> Repo.preload(:workspace)
    scene = scene_fixture(project, %{name: "Hidden Scene context"})
    layer = layer_fixture(scene, %{"name" => "Spoilers", "visible" => false})
    target = pin_fixture(scene, %{"label" => "Secret passage", "layer_id" => layer.id})

    created =
      create_comment(scope, project, scene, "Review the secret passage without exposing the layer.", %{x: 55, y: 54}, %{
        type: "scene_pin",
        id: target.id,
        offset: %{x: 5, y: 4}
      })

    path = scene_path(project, scene) <> "?thread=#{created.thread.id}"

    session =
      conn
      |> authenticate(user)
      |> visit(path)
      |> assert_has("#scene-comment-popover", text: created.thread.preview, timeout: 20_000)
      |> assert_scene_pin_visibility(target.label, false)
      |> assert_has("#scene-comment-reveal-context")
      |> click("#scene-comment-reveal-context")
      |> assert_scene_pin_visibility(target.label, true)

    assert Scenes.get_layer!(scene.id, layer.id).visible == false
    assert {:ok, unchanged} = Projects.get_comment_thread(scope, project.id, created.thread.id)
    assert unchanged.thread.revision == created.thread.revision
    assert unchanged.thread.context == created.thread.context

    session
    |> reload_page()
    |> assert_has("#scene-comment-popover", timeout: 20_000)
    |> assert_scene_pin_visibility(target.label, false)
    |> assert_has("#scene-comment-reveal-context")
  end

  defp create_comment(scope, project, scene, body, position, context \\ nil) do
    {:ok, created} =
      Projects.create_scene_canvas_comment(scope, project.id, scene.id, %{
        body: body,
        position: position,
        context: context,
        client_request_id: Ecto.UUID.generate()
      })

    created
  end

  defp scene_path(project, scene) do
    "/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
  end

  # Konva exposes its rendered scene graph publicly. Read it to locate painted
  # elements, then interact through the browser mouse rather than firing events.
  defp scene_pin_point(label) do
    """
    (() => {
      const stage = window.Konva?.stages.find(stage => stage.container().isConnected);
      const text = stage?.find('Text').find(text => text.text() === #{Jason.encode!(label)});
      if (!text || !text.isVisible()) return null;
      const point = text.getParent().getAbsolutePosition();
      const bounds = stage.container().getBoundingClientRect();
      return { x: bounds.left + point.x, y: bounds.top + point.y };
    })()
    """
  end

  defp assert_scene_pin_visibility(session, label, visible) do
    evaluate(
      session,
      """
      (async () => {
        for (let attempt = 0; attempt < 120; attempt++) {
          const visible = Boolean(#{scene_pin_point(label)});
          if (visible === #{visible}) return visible;
          await new Promise(requestAnimationFrame);
        }
        return Boolean(#{scene_pin_point(label)});
      })()
      """,
      fn actual -> assert actual == visible end
    )
  end

  defp drag_over_scene_pin(session, pin, label) do
    session
    |> assert_scene_pin_visibility(label, true)
    |> hover_pin(pin)
    |> evaluate(scene_pin_point(label), fn point ->
      {:ok, _} = Page.mouse_down(session.page_id, timeout: 10_000)
      {:ok, _} = Page.mouse_move(session.page_id, x: point["x"], y: point["y"], steps: 8, timeout: 10_000)
    end)
  end

  defp drag_scene_pin(session, label, dx, dy) do
    evaluate(session, scene_pin_point(label), fn point ->
      {:ok, _} = Page.mouse_move(session.page_id, x: point["x"], y: point["y"], timeout: 10_000)
      {:ok, _} = Page.mouse_down(session.page_id, timeout: 10_000)

      {:ok, _} =
        Page.mouse_move(session.page_id, x: point["x"] + dx, y: point["y"] + dy, steps: 8, timeout: 10_000)

      {:ok, _} = Page.mouse_up(session.page_id, timeout: 10_000)

      evaluate(
        session,
        """
        (async () => {
          let position;
          for (let attempt = 0; attempt < 120; attempt++) {
            position = #{scene_pin_point(label)};
            if (Math.abs(position.x - #{point["x"]} - #{dx}) < 2 &&
                Math.abs(position.y - #{point["y"]} - #{dy}) < 2) break;
            await new Promise(requestAnimationFrame);
          }
          return position;
        })()
        """,
        fn after_drag ->
          assert_in_delta after_drag["x"] - point["x"], dx, 2
          assert_in_delta after_drag["y"] - point["y"], dy, 2
        end
      )
    end)
  end

  defp release_pin(session) do
    {:ok, _} = Page.mouse_up(session.page_id, timeout: 10_000)
    session
  end

  defp assert_pin_offset(session, label, pin, offset) do
    evaluate(
      session,
      """
      (async () => {
        let delta;
        for (let attempt = 0; attempt < 120; attempt++) {
          const stage = window.Konva.stages.find(stage => stage.container().isConnected);
          const point = #{scene_pin_point(label)};
          const badge = document.querySelector(#{Jason.encode!(pin)}).getBoundingClientRect();
          delta = {
            x: badge.left + badge.width / 2 - point.x - #{offset.x} / 100 * stage.width() * 0.95 * stage.scaleX(),
            y: badge.top + badge.height / 2 - point.y - #{offset.y} / 100 * stage.height() * 0.95 * stage.scaleY()
          };
          if (Math.abs(delta.x) < 2 && Math.abs(delta.y) < 2) break;
          await new Promise(requestAnimationFrame);
        }
        return delta;
      })()
      """,
      fn delta ->
        assert_in_delta delta["x"], 0, 2
        assert_in_delta delta["y"], 0, 2
      end
    )
  end

  defp zoom_scene(session, scene_id) do
    session
    |> evaluate("document.querySelector('#scene-canvas-#{scene_id}').getBoundingClientRect().toJSON()", fn canvas ->
      {:ok, _} =
        Page.mouse_move(session.page_id,
          x: canvas["x"] + canvas["width"] * 0.75,
          y: canvas["y"] + canvas["height"] * 0.25,
          timeout: 10_000
        )
    end)
    |> tap(fn session ->
      # PlaywrightEx has no wheel wrapper, so use the same protocol connection as
      # its mouse helpers to send an actual browser wheel input.
      {:ok, _} =
        PlaywrightEx.Supervisor.Connection
        |> PlaywrightEx.Connection.send(
          %{guid: session.page_id, method: :mouse_wheel, params: %{delta_y: -200, delta_x: 0}},
          10_000
        )
        |> PlaywrightEx.ChannelResponse.unwrap(& &1)
    end)
    |> evaluate(
      """
      (async () => {
        const stage = window.Konva.stages.find(stage => stage.container().isConnected);
        for (let attempt = 0; attempt < 120 && stage.scaleX() <= 1; attempt++) {
          await new Promise(requestAnimationFrame);
        }
        return stage.scaleX();
      })()
      """,
      fn scale -> assert scale > 1 end
    )
  end

  defp pan_scene(session, scene_id, pin, dx, dy) do
    evaluate(
      session,
      """
      (async () => {
        const stage = window.Konva.stages.find(stage => stage.container().isConnected);
        for (let attempt = 0; attempt < 120 && !stage.draggable(); attempt++) {
          await new Promise(requestAnimationFrame);
        }
        return {
          canvas: document.querySelector('#scene-canvas-#{scene_id}').getBoundingClientRect().toJSON(),
          pin: document.querySelector(#{Jason.encode!(pin)}).getBoundingClientRect().toJSON()
        };
      })()
      """,
      fn before ->
        x = before["canvas"]["x"] + before["canvas"]["width"] * 0.75
        y = before["canvas"]["y"] + before["canvas"]["height"] * 0.7
        {:ok, _} = Page.mouse_move(session.page_id, x: x, y: y, timeout: 10_000)
        {:ok, _} = Page.mouse_down(session.page_id, timeout: 10_000)
        {:ok, _} = Page.mouse_move(session.page_id, x: x + dx, y: y + dy, steps: 8, timeout: 10_000)
        {:ok, _} = Page.mouse_up(session.page_id, timeout: 10_000)

        evaluate(
          session,
          """
          (async () => {
            let position;
            for (let attempt = 0; attempt < 120; attempt++) {
              position = document.querySelector(#{Jason.encode!(pin)}).getBoundingClientRect().toJSON();
              if (Math.abs(position.x - #{before["pin"]["x"]} - #{dx}) < 2 &&
                  Math.abs(position.y - #{before["pin"]["y"]} - #{dy}) < 2) break;
              await new Promise(requestAnimationFrame);
            }
            return position;
          })()
          """,
          fn after_pan ->
            assert_in_delta after_pan["x"] - before["pin"]["x"], dx, 2
            assert_in_delta after_pan["y"] - before["pin"]["y"], dy, 2
          end
        )
      end
    )
  end
end
