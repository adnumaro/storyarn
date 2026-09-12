defmodule StoryarnWeb.E2E.FlowCommentsTest do
  use PhoenixTest.Playwright.Case, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import StoryarnWeb.E2EHelpers

  alias PlaywrightEx.Page
  alias Storyarn.Flows
  alias Storyarn.Projects
  alias Storyarn.Repo

  @moduletag :e2e

  test "an editor starts a node discussion, resolves it and finds it after reloading", %{conn: conn} do
    user = user_fixture()
    project = user |> project_fixture() |> Repo.preload(:workspace)
    flow = flow_fixture(project, %{name: "Reviewable encounter"})

    node =
      node_fixture(flow, %{
        type: "hub",
        position_x: 480,
        position_y: 180,
        data: %{"label" => "Guard encounter", "hub_id" => "guard_encounter"}
      })

    path = "/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
    feedback = "Give the player a reason to trust the guard before this encounter."

    conn
    |> authenticate(user)
    |> visit(path)
    |> assert_has("[data-testid='flow-canvas-comments']", timeout: 20_000)
    |> assert_has("[data-flow-comment-node='#{node.id}']", timeout: 20_000)
    |> right_click("[data-flow-comment-node='#{node.id}']")
    |> click("[data-testid='flow-context-menu'] [data-key='add_comment']")
    |> assert_has("#flow-comment-draft-pin")
    |> fill_in("#flow-comment-body", "New thread", with: feedback)
    |> click("#flow-comment-send")
    |> assert_has("#flow-comments-content", text: feedback)
    |> assert_has("#flow-comment-status", text: "Resolve")
    |> click("#flow-comment-status")
    |> assert_has("#flow-comment-status", text: "Reopen")
    |> assert_has("#flow-comments-content", text: "This thread is resolved.")
    |> visit(path)
    |> assert_has("[data-flow-comment-node='#{node.id}']", timeout: 20_000)
    |> click("#flow-comments-toggle")
    |> select("#flow-comments-filter", "Filter threads", option: "Resolved")
    |> assert_has("#flow-comments-content", text: "Give the player a reason to trust the guard")
  end

  test "a moved node's discussion stays reachable and replyable after its context is deleted", %{conn: conn} do
    user = user_fixture()
    scope = user_scope_fixture(user)
    project = user |> project_fixture() |> Repo.preload(:workspace)
    flow = flow_fixture(project, %{name: "Discussion survives its context"})

    node =
      node_fixture(flow, %{
        type: "hub",
        position_x: 120,
        position_y: 160,
        data: %{"label" => "Retired guard beat", "hub_id" => "retired_guard_beat"}
      })

    feedback = "Keep the trust-building question open while we rewrite this beat."
    reply = "We can move this conversation forward even after removing the beat."

    assert {:ok, detail} =
             Projects.create_flow_node_comment(scope, project.id, flow.id, node.id, %{
               body: feedback,
               client_request_id: Ecto.UUID.generate(),
               position: %{x: 28, y: 16}
             })

    assert {:ok, moved_node} = Flows.update_node_position(node, %{position_x: 480, position_y: 260})
    assert {:ok, _deleted_node, _metadata} = Flows.delete_node(moved_node)

    thread_id = detail.thread.id
    root_message_id = detail.thread.root_message_id

    path =
      "/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}?thread=#{thread_id}"

    session =
      conn
      |> authenticate(user)
      |> visit(path)
      |> assert_has("#flow-comment-pin-#{thread_id}[aria-expanded='true']", timeout: 20_000)
      |> assert_has("#flow-comment-context", text: "Retired guard beat")
      |> assert_has("#flow-comment-context", text: "Context unavailable")
      |> assert_has("#flow-comment-message-#{root_message_id}", text: feedback)
      |> fill_in("#flow-comment-body", "Reply", with: reply)
      |> click("#flow-comment-send")
      |> assert_has("#flow-comment-popover", text: reply)

    assert {:ok, replied} = Projects.get_comment_thread(scope, project.id, thread_id)
    assert replied.thread.id == thread_id
    assert replied.thread.message_count == 2
    assert replied.thread.source.type == "flow_canvas"
    assert replied.thread.source.status == "available"
    assert replied.thread.context.status == "unavailable"
    assert replied.thread.position == %{x: 508.0, y: 276.0}
    assert [root_message, reply_message] = replied.messages
    assert root_message.id == root_message_id
    assert reply_message.thread_id == thread_id
    assert reply_message.parent_id == root_message_id
    assert reply_message.body == reply

    session
    |> visit(path)
    |> assert_has("#flow-comment-pin-#{thread_id}[aria-expanded='true']", timeout: 20_000)
    |> assert_has("#flow-comment-context", text: "Context unavailable")
    |> assert_has("#flow-comment-message-#{root_message_id}", text: feedback)
    |> assert_has("#flow-comment-message-#{reply_message.id}", text: reply)

    assert {:ok, [pin]} = Projects.list_flow_comment_pins(scope, project.id, flow.id)
    assert pin.id == thread_id
    assert pin.message_count == 2
    assert pin.position == replied.thread.position
  end

  test "a free canvas pin preserves its draft when dragged and exposes preview and conversation", %{conn: conn} do
    user = user_fixture()
    project = user |> project_fixture() |> Repo.preload(:workspace)
    flow = flow_fixture(project, %{name: "Canvas review"})
    path = "/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
    feedback = "Consider a parallel storyline in this region."

    session =
      conn
      |> authenticate(user)
      |> visit(path)
      |> assert_has("[data-testid='flow-canvas-comments']", timeout: 20_000)
      |> click("#flow-comments-create-mode")
      |> assert_has("#flow-comments-create-mode[aria-pressed='true']")
      |> assert_has("#flow-comment-placement-hint")
      |> click_at("#flow-canvas-#{flow.id}", 100, 100)
      |> assert_has("#flow-comment-draft-pin")
      |> fill_in("#flow-comment-body", "New thread", with: feedback)
      |> drag_pin("#flow-comment-draft-pin", 70, 40)
      |> assert_has("#flow-comment-body", value: feedback)
      |> click("#flow-comment-send")
      |> assert_has("#flow-comment-popover", text: feedback)
      |> click("#flow-comment-popover-close")
      |> refute_has("#flow-comment-popover")
      |> hover_pin("[id^='flow-comment-pin-']")
      |> assert_has("#flow-comment-preview", text: feedback)

    scope = user_scope_fixture(user)
    assert {:ok, [thread]} = Projects.list_flow_comment_pins(scope, project.id, flow.id)
    assert thread.source.type == "flow_canvas"

    session =
      session
      |> drag_pin("#flow-comment-pin-#{thread.id}", 80, 40)
      |> click("#flow-comment-pin-#{thread.id}")
      |> assert_has("#flow-comment-popover", text: feedback)

    assert {:ok, [moved]} = Projects.list_flow_comment_pins(scope, project.id, flow.id)
    assert moved.position.x > thread.position.x
    assert moved.position.y > thread.position.y

    session
    |> visit(path <> "?thread=#{thread.id}")
    |> assert_has("#flow-comment-popover", text: feedback, timeout: 20_000)
    |> assert_has("#flow-comment-pin-#{thread.id}[aria-expanded='true']")
  end

  test "magnetic dragging attaches context and a free keyboard move detaches it without replacing the thread",
       %{conn: conn} do
    user = user_fixture()
    scope = user_scope_fixture(user)
    project = user |> project_fixture() |> Repo.preload(:workspace)
    flow = flow_fixture(project, %{name: "Magnetic review"})

    node =
      node_fixture(flow, %{
        type: "hub",
        position_x: 480,
        position_y: 180,
        data: %{"label" => "Guard motivation", "hub_id" => "guard_motivation"}
      })

    feedback = "Clarify the guard's motivation here."

    assert {:ok, created} =
             Projects.create_flow_canvas_comment(scope, project.id, flow.id, %{
               body: feedback,
               client_request_id: Ecto.UUID.generate(),
               position: %{x: 300, y: 120}
             })

    thread_id = created.thread.id
    pin = "#flow-comment-pin-#{thread_id}"
    path = "/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
    deep_link = path <> "?thread=#{thread_id}"

    session =
      conn
      |> authenticate(user)
      |> visit(path)
      |> assert_has("#{pin}[aria-busy=false]", timeout: 20_000)
      |> assert_has("[data-flow-comment-node='#{node.id}'][data-flow-comment-label='Guard motivation']")
      |> assert_has("#flow-comment-magnetism-toggle[aria-pressed=true]")
      |> drag_pin_over_node(pin, node.id)
      |> assert_has("#flow-comment-snap-preview", text: "Guard motivation")

    # Previewing a target must not save an intermediate position or association.
    assert {:ok, previewing} = Projects.get_comment_thread(scope, project.id, thread_id)
    assert previewing.thread.position == created.thread.position
    assert previewing.thread.revision == created.thread.revision
    assert is_nil(previewing.thread.context)

    session =
      session
      |> release_pin()
      |> assert_has("#{pin}[aria-busy=false]")
      |> click(pin)
      |> assert_has("#flow-comment-popover", text: feedback)
      |> assert_has("#flow-comment-context", text: "Guard motivation")

    assert {:ok, attached} = Projects.get_comment_thread(scope, project.id, thread_id)
    assert attached.thread.source.type == "flow_canvas"
    assert attached.thread.source.id == flow.id
    assert attached.thread.context.type == "flow_node"
    assert attached.thread.context.id == to_string(node.id)
    assert attached.thread.context.status == "available"
    assert attached.thread.revision == created.thread.revision + 1
    assert_in_delta attached.thread.position.x, node.position_x + attached.thread.context.offset.x, 0.001
    assert_in_delta attached.thread.position.y, node.position_y + attached.thread.context.offset.y, 0.001

    session =
      session
      |> visit(deep_link)
      |> assert_has("#{pin}[aria-expanded=true]", timeout: 20_000)
      |> assert_has("#flow-comment-context", text: "Guard motivation")
      |> click("#flow-comment-popover-close")
      |> click("#flow-comment-magnetism-toggle")
      |> assert_has("#flow-comment-magnetism-toggle[aria-pressed=false]")
      |> press(pin, "ArrowRight")

    assert {:ok, nudging} = Projects.get_comment_thread(scope, project.id, thread_id)
    assert nudging.thread.revision == attached.thread.revision
    assert nudging.thread.context == attached.thread.context

    session =
      session
      |> press(pin, "Enter")
      |> assert_has("#{pin}[aria-busy=false]")
      |> click(pin)
      |> assert_has("#flow-comment-popover", text: feedback)
      |> refute_has("#flow-comment-context")

    assert {:ok, detached} = Projects.get_comment_thread(scope, project.id, thread_id)
    assert is_nil(detached.thread.context)
    assert detached.thread.source == attached.thread.source
    assert detached.thread.revision == attached.thread.revision + 1
    assert detached.thread.position.x > attached.thread.position.x
    assert_in_delta detached.thread.position.y, attached.thread.position.y, 0.001

    session
    |> visit(deep_link)
    |> assert_has("#{pin}[aria-expanded=true]", timeout: 20_000)
    |> assert_has("#flow-comment-message-#{created.thread.root_message_id}", text: feedback)
    |> refute_has("#flow-comment-context")

    assert {:ok, [persisted]} = Projects.list_flow_comment_pins(scope, project.id, flow.id)
    assert persisted.id == thread_id
    assert persisted.message_count == 1
    assert persisted.position == detached.thread.position
    assert persisted.source.type == "flow_canvas"
    assert is_nil(persisted.context)
  end

  test "a draft keeps its text when magnetically moved onto a node and saves that context", %{conn: conn} do
    user = user_fixture()
    scope = user_scope_fixture(user)
    project = user |> project_fixture() |> Repo.preload(:workspace)
    flow = flow_fixture(project, %{name: "Draft context"})

    node =
      node_fixture(flow, %{
        type: "hub",
        position_x: 480,
        position_y: 180,
        data: %{"label" => "First encounter", "hub_id" => "first_encounter"}
      })

    path = "/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
    feedback = "The first encounter should establish what the guard wants."

    session =
      conn
      |> authenticate(user)
      |> visit(path)
      |> assert_has("[data-flow-comment-node='#{node.id}']", timeout: 20_000)
      |> click("#flow-comments-create-mode")
      |> assert_has("#flow-comments-create-mode[aria-pressed=true]")
      |> assert_has("#flow-comment-placement-hint")
      |> click_at("#flow-canvas-#{flow.id}", 100, 100)
      |> assert_has("#flow-comment-draft-pin")
      |> fill_in("#flow-comment-body", "New thread", with: feedback)
      |> drag_pin_over_node("#flow-comment-draft-pin", node.id)
      |> assert_has("#flow-comment-snap-preview", text: "First encounter")
      |> release_pin()
      |> assert_has("#flow-comment-draft-pin[aria-busy=false]")
      |> assert_has("#flow-comment-body", value: feedback)
      |> reload_page()
      |> assert_has("#flow-comment-draft-pin[aria-busy=false]", timeout: 20_000)
      |> assert_has("#flow-comment-body", value: feedback)
      |> click("#flow-comment-send")
      |> assert_has("#flow-comment-popover", text: feedback)
      |> assert_has("#flow-comment-context", text: "First encounter")

    assert {:ok, [thread]} = Projects.list_flow_comment_pins(scope, project.id, flow.id)
    assert thread.source.type == "flow_canvas"
    assert thread.context.type == "flow_node"
    assert thread.context.id == to_string(node.id)
    assert thread.message_count == 1

    session
    |> visit(path <> "?thread=#{thread.id}")
    |> assert_has("#flow-comment-pin-#{thread.id}[aria-expanded=true]", timeout: 20_000)
    |> assert_has("#flow-comment-popover", text: feedback)
    |> assert_has("#flow-comment-context", text: "First encounter")
  end

  test "a draft whose node was deleted recovers its text as a free Flow comment", %{conn: conn} do
    user = user_fixture()
    scope = user_scope_fixture(user)
    project = user |> project_fixture() |> Repo.preload(:workspace)
    flow = flow_fixture(project, %{name: "Recoverable draft context"})

    node =
      node_fixture(flow, %{
        type: "hub",
        position_x: 480,
        position_y: 180,
        data: %{"label" => "Replaced encounter", "hub_id" => "replaced_encounter"}
      })

    path = "/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
    feedback = "Keep this observation even if the encounter is replaced."

    session =
      conn
      |> authenticate(user)
      |> visit(path)
      |> assert_has("[data-flow-comment-node='#{node.id}']", timeout: 20_000)
      |> right_click("[data-flow-comment-node='#{node.id}']")
      |> click("[data-testid='flow-context-menu'] [data-key='add_comment']")
      |> assert_has("#flow-comment-draft-pin[aria-busy=false]")
      |> fill_in("#flow-comment-body", "New thread", with: feedback)

    assert {:ok, _deleted_node, _metadata} = Flows.delete_node(node)

    session
    |> reload_page()
    |> assert_has("#flow-comment-draft-pin[aria-busy=false]", timeout: 20_000)
    |> refute_has("[data-flow-comment-node='#{node.id}']")
    |> assert_has("#flow-comment-body", value: feedback)
    |> click("#flow-comment-send")
    |> assert_has("#flow-comment-popover", text: feedback)
    |> refute_has("#flow-comment-context")

    assert {:ok, [thread]} = Projects.list_flow_comment_pins(scope, project.id, flow.id)
    assert thread.source.type == "flow_canvas"
    assert thread.source.id == flow.id
    assert is_nil(thread.context)
    assert thread.message_count == 1
  end

  test "a contextual pin follows node dragging, zoom and pan without changing its stored offset", %{conn: conn} do
    user = user_fixture()
    scope = user_scope_fixture(user)
    project = user |> project_fixture() |> Repo.preload(:workspace)
    flow = flow_fixture(project, %{name: "Moving context"})

    node =
      node_fixture(flow, %{
        type: "hub",
        position_x: 360,
        position_y: 180,
        data: %{"label" => "Moving encounter", "hub_id" => "moving_encounter"}
      })

    offset = %{x: 20, y: 16}

    assert {:ok, created} =
             Projects.create_flow_node_comment(scope, project.id, flow.id, node.id, %{
               body: "Keep this discussion attached while arranging the encounter.",
               client_request_id: Ecto.UUID.generate(),
               position: offset
             })

    thread_id = created.thread.id
    pin = "#flow-comment-pin-#{thread_id}"
    path = "/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"

    conn
    |> authenticate(user)
    |> visit(path)
    |> assert_has("#{pin}[aria-busy=false]", timeout: 20_000)
    |> assert_pin_offset(node.id, pin, offset)
    |> drag_pin("[data-flow-comment-node='#{node.id}'] [data-testid='node']", 80, 40)
    |> assert_pin_offset(node.id, pin, offset)
    |> click("button[title='Zoom in']")
    |> assert_pin_offset(node.id, pin, offset)
    |> pan_canvas(flow.id, pin, 50, -30)
    |> assert_pin_offset(node.id, pin, offset)
    |> click("button[title='Zoom out']")
    |> assert_pin_offset(node.id, pin, offset)
    |> visit(path <> "?thread=#{thread_id}")
    |> assert_has("#{pin}[aria-expanded=true]", timeout: 20_000)
    |> assert_has("#flow-comment-context", text: "Moving encounter")
    |> assert_pin_offset(node.id, pin, offset)

    moved_node = Flows.get_node!(flow.id, node.id)
    assert moved_node.position_x > node.position_x
    assert moved_node.position_y > node.position_y
    assert {:ok, [persisted]} = Projects.list_flow_comment_pins(scope, project.id, flow.id)
    assert persisted.id == thread_id
    assert persisted.context.id == to_string(node.id)
    assert persisted.context.offset == offset
    assert persisted.source.type == "flow_canvas"
    assert persisted.position == created.thread.position
    assert persisted.revision == created.thread.revision
  end

  test "Sequence replies to the same contextual conversation created on the Flow canvas", %{conn: conn} do
    user = user_fixture()
    scope = user_scope_fixture(user)
    project = user |> project_fixture() |> Repo.preload(:workspace)
    flow = flow_fixture(project, %{name: "Shared Flow and Sequence discussion"})

    node =
      node_fixture(flow, %{
        type: "dialogue",
        position_x: 480,
        position_y: 180,
        data: %{"text" => "The guard opens the eastern gate.", "responses" => []}
      })

    path = "/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
    feedback = "Show why the guard trusts us before opening the gate."
    reply = "The preceding dialogue will establish that trust."

    session =
      conn
      |> authenticate(user)
      |> visit(path)
      |> assert_has("[data-flow-comment-node='#{node.id}']", timeout: 20_000)
      |> right_click("[data-flow-comment-node='#{node.id}']")
      |> click("[data-testid='flow-context-menu'] [data-key='add_comment']")
      |> assert_has("#flow-comment-draft-pin[aria-busy=false]")
      |> fill_in("#flow-comment-body", "New thread", with: feedback)
      |> click("#flow-comment-send")
      |> assert_has("#flow-comment-popover", text: feedback)

    assert {:ok, [thread]} = Projects.list_flow_comment_pins(scope, project.id, flow.id)
    assert thread.source.type == "flow_canvas"
    assert thread.context.id == to_string(node.id)

    session =
      session
      |> click("#flow-comment-popover-close")
      |> click_at("[data-flow-comment-node='#{node.id}'] [data-testid='node']", 40, 20)
      |> click("[data-toggle-visual-editor]")
      |> assert_has("[data-sequence-intervention]", text: "The guard opens the eastern gate.")
      |> click("[data-sequence-comments-toggle]")
      |> assert_has("#sequence-comment-thread-#{thread.id}", text: feedback)
      |> click("#sequence-comment-thread-#{thread.id}")
      |> assert_has("#sequence-comment-message-#{thread.root_message_id}", text: feedback)
      |> fill_in("#sequence-comment-body", "Reply", with: reply)
      |> click("#sequence-comment-send")
      |> assert_has("#sequence-comments-content", text: reply)

    assert {:ok, replied} = Projects.get_comment_thread(scope, project.id, thread.id)
    assert replied.thread.root_message_id == thread.root_message_id
    assert replied.thread.message_count == 2
    assert replied.thread.source == thread.source
    assert replied.thread.context == thread.context
    assert [_, reply_message] = replied.messages
    assert reply_message.thread_id == thread.id
    assert reply_message.parent_id == thread.root_message_id

    session
    |> click("#sequence-comments button[aria-label='Close comments']")
    |> click("[data-toggle-visual-editor]")
    |> refute_has("[data-sequence-workspace]")
    |> visit(path <> "?thread=#{thread.id}")
    |> assert_has("#flow-comment-pin-#{thread.id}[aria-expanded=true]", timeout: 20_000)
    |> assert_has("#flow-comment-message-#{thread.root_message_id}", text: feedback)
    |> assert_has("#flow-comment-message-#{reply_message.id}", text: reply)

    assert {:ok, [persisted]} = Projects.list_flow_comment_pins(scope, project.id, flow.id)
    assert persisted.id == thread.id
    assert persisted.message_count == 2
  end

  defp assert_pin_offset(session, node_id, pin, offset) do
    evaluate(
      session,
      """
      (async () => {
        const node = document.querySelector('[data-flow-comment-node="#{node_id}"]');
        const pin = document.querySelector(#{Jason.encode!(pin)});
        let delta;
        for (let attempt = 0; attempt < 120; attempt++) {
          const bounds = node.getBoundingClientRect();
          const badge = pin.getBoundingClientRect();
          const scale = bounds.width / node.offsetWidth;
          delta = {
            x: badge.left + badge.width / 2 - bounds.left - #{offset.x} * scale,
            y: badge.top + badge.height / 2 - bounds.top - #{offset.y} * scale
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

  defp pan_canvas(session, flow_id, pin, dx, dy) do
    evaluate(
      session,
      """
      ({
        canvas: document.querySelector('#flow-canvas-#{flow_id}').getBoundingClientRect().toJSON(),
        pin: document.querySelector(#{Jason.encode!(pin)}).getBoundingClientRect().toJSON()
      })
      """,
      fn before ->
        x = before["canvas"]["x"] + before["canvas"]["width"] * 0.55
        y = before["canvas"]["y"] + before["canvas"]["height"] * 0.8
        {:ok, _} = Page.mouse_move(session.page_id, x: x, y: y, timeout: 10_000)
        {:ok, _} = Page.mouse_down(session.page_id, timeout: 10_000)
        {:ok, _} = Page.mouse_move(session.page_id, x: x + dx, y: y + dy, steps: 8, timeout: 10_000)
        {:ok, _} = Page.mouse_up(session.page_id, timeout: 10_000)

        evaluate(
          session,
          "document.querySelector(#{Jason.encode!(pin)}).getBoundingClientRect().toJSON()",
          fn after_pan ->
            assert_in_delta after_pan["x"] - before["pin"]["x"], dx, 2
            assert_in_delta after_pan["y"] - before["pin"]["y"], dy, 2
          end
        )
      end
    )
  end

  defp drag_pin_over_node(session, pin, node_id) do
    selector = "[data-flow-comment-node='#{node_id}']"

    session
    |> hover_pin(pin)
    |> evaluate("document.querySelector(#{Jason.encode!(selector)}).getBoundingClientRect().toJSON()", fn box ->
      {:ok, _} = Page.mouse_down(session.page_id, timeout: 10_000)

      {:ok, _} =
        Page.mouse_move(session.page_id,
          x: box["x"] + box["width"] / 2,
          y: box["y"] + box["height"] / 2,
          steps: 8,
          timeout: 10_000
        )
    end)
  end

  defp release_pin(session) do
    {:ok, _} = Page.mouse_up(session.page_id, timeout: 10_000)
    session
  end
end
