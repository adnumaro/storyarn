defmodule StoryarnWeb.E2E.FlowCommentsTest do
  use PhoenixTest.Playwright.Case, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import StoryarnWeb.E2EHelpers

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
end
