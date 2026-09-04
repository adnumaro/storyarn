defmodule StoryarnWeb.FlowLive.CommentsTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Flows
  alias Storyarn.Platform.Collaboration
  alias Storyarn.Projects
  alias Storyarn.Repo

  setup :register_and_log_in_user

  setup %{user: user} do
    project = user |> project_fixture() |> Repo.preload(:workspace)
    flow = flow_fixture(project)
    node = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Hello"}})
    %{project: project, flow: flow, node: node, scope: user_scope_fixture(user)}
  end

  test "creates and resolves a contextual conversation without acquiring an editor lock", context do
    view = open_flow(context)
    render_hook(view, "comments_open", %{node_id: context.node.id})
    assert panel(view)["canComment"]

    attrs = %{
      node_id: context.node.id,
      body: "Could this choice change the ending?",
      client_request_id: Ecto.UUID.generate()
    }

    render_hook(view, "comments_create", attrs)
    state = panel(view)
    assert state["open"]
    assert state["thread"]["source"]["id"] == context.node.id
    assert [message] = state["messages"]
    assert message["body"] == attrs.body
    assert {:error, :not_locked} = Collaboration.get_lock({:flow, context.flow.id}, context.node.id)

    render_hook(view, "comments_create", attrs)
    assert panel(view)["thread"]["message_count"] == 1

    render_hook(view, "comments_set_status", %{
      thread_id: state["thread"]["id"],
      status: "resolved",
      expected_revision: state["thread"]["revision"]
    })

    assert panel(view)["thread"]["status"] == "resolved"
  end

  test "a cold notification deep link waits for the Flow and focuses without selecting for editing", context do
    detail = create_comment(context)
    view = open_flow(context, "?thread=#{detail.thread.id}")
    assert panel(view)["thread"]["id"] == detail.thread.id

    surface = LiveVue.Test.get_vue(view, name: "live/flow/show/FlowSurface")
    assert surface.props["surface"]["canvas"]["commentFocusNodeId"] == context.node.id
    assert surface.props["surface"]["canvas"]["commentFocusThreadId"] == detail.thread.id
    assert panel(view)["presentation"] == "canvas"
    assert surface.props["surface"]["canvas"]["commentCounts"][to_string(context.node.id)] == 1
    assert {:error, :not_locked} = Collaboration.get_lock({:flow, context.flow.id}, context.node.id)
  end

  test "a canvas comment is placed, moved and restored by its deep link", context do
    view = open_flow(context)
    render_hook(view, "comments_mode", %{active: true})
    assert panel(view)["placing"]
    render_hook(view, "comments_place", %{node_id: nil, x: 140.5, y: -80})
    assert panel(view)["draftPosition"] == %{"x" => 140.5, "y" => -80}
    assert panel(view)["presentation"] == "canvas"
    refute panel(view)["placing"]

    attrs = %{
      node_id: nil,
      position: %{x: 140.5, y: -80},
      body: "Explore another path here",
      client_request_id: Ecto.UUID.generate()
    }

    render_hook(view, "comments_create", attrs)
    thread = panel(view)["thread"]
    assert thread["source"]["type"] == "flow_canvas"
    assert panel(view)["selectedNodeId"] == nil
    assert panel(view)["draftPosition"] == nil
    assert [pin] = canvas(view)["commentPins"]
    assert pin["id"] == thread["id"]
    assert canvas(view)["commentCounts"] == %{}

    render_hook(view, "comments_close", %{})
    render_hook(view, "comments_move", %{thread_id: thread["id"], x: 300, y: 120, expected_revision: thread["revision"]})
    refute panel(view)["open"]
    assert canvas(view)["commentFocusThreadId"] == nil
    assert [%{"position" => %{"x" => 300.0, "y" => 120.0}}] = canvas(view)["commentPins"]

    render_hook(view, "comments_move", %{thread_id: thread["id"], x: 1, y: 2, expected_revision: thread["revision"]})
    assert is_binary(panel(view)["error"])
    assert [%{"position" => %{"x" => 300.0, "y" => 120.0}}] = canvas(view)["commentPins"]

    reloaded = open_flow(context, "?thread=#{thread["id"]}")
    assert canvas(reloaded)["commentFocusThreadId"] == thread["id"]
    assert canvas(reloaded)["commentFocusNodeId"] == nil
    assert panel(reloaded)["thread"]["position"] == %{"x" => 300.0, "y" => 120.0}
  end

  test "node placement retains its relative anchor and Escape cancels placement", context do
    view = open_flow(context)
    render_hook(view, "comments_place", %{node_id: context.node.id, x: 25, y: 30})
    assert panel(view)["selectedNodeId"] == context.node.id
    assert panel(view)["draftPosition"] == %{"x" => 25, "y" => 30}

    render_hook(view, "comments_create", %{
      node_id: context.node.id,
      position: %{x: 25, y: 30},
      body: "Review this exact point",
      client_request_id: Ecto.UUID.generate()
    })

    assert [%{"source" => %{"type" => "flow_node"}, "position" => %{"x" => 25.0, "y" => 30.0}}] =
             canvas(view)["commentPins"]

    render_hook(view, "comments_mode", %{active: true})
    render_hook(view, "comments_mode", %{active: false})
    refute panel(view)["placing"]
    refute panel(view)["open"]
    assert {:error, :not_locked} = Collaboration.get_lock({:flow, context.flow.id}, context.node.id)
  end

  test "forged placement and movement cannot cross Flow boundaries or bypass viewer permissions", context do
    other_flow = flow_fixture(context.project)
    other_node = node_fixture(other_flow)
    other = create_comment(%{context | flow: other_flow, node: other_node})
    view = open_flow(context)
    render_hook(view, "comments_place", %{node_id: other_node.id, x: 10, y: 20})
    assert panel(view)["draftPosition"] == nil
    render_hook(view, "comments_place", %{node_id: nil, x: 100_000_000, y: 20})
    assert panel(view)["draftPosition"] == nil

    render_hook(view, "comments_move", %{
      thread_id: other.thread.id,
      x: 10,
      y: 20,
      expected_revision: other.thread.revision
    })

    assert {:ok, %{thread: %{position: nil}}} =
             Projects.get_comment_thread(context.scope, context.project.id, other.thread.id)

    own = create_comment(context)
    viewer = user_fixture()
    membership_fixture(context.project, viewer, "viewer")
    viewer_view = open_flow(%{context | conn: log_in_user(build_conn(), viewer)})
    render_hook(viewer_view, "comments_mode", %{active: true})
    refute panel(viewer_view)["placing"]
    render_hook(viewer_view, "comments_place", %{node_id: nil, x: 10, y: 20})
    assert panel(viewer_view)["draftPosition"] == nil

    render_hook(viewer_view, "comments_move", %{
      thread_id: own.thread.id,
      x: 10,
      y: 20,
      expected_revision: own.thread.revision
    })

    assert {:ok, %{thread: %{position: nil}}} =
             Projects.get_comment_thread(context.scope, context.project.id, own.thread.id)
  end

  test "another Flow's thread cannot be read or mutated through this Flow", context do
    other_flow = flow_fixture(context.project)
    other_node = node_fixture(other_flow)
    other = create_comment(%{context | flow: other_flow, node: other_node})
    view = open_flow(context, "?thread=#{other.thread.id}")
    assert panel(view)["thread"] == nil
    assert panel(view)["messages"] == []

    render_hook(view, "comments_reply", %{
      thread_id: other.thread.id,
      parent_id: hd(other.messages).id,
      body: "Wrong flow",
      client_request_id: Ecto.UUID.generate()
    })

    assert {:ok, detail} = Projects.get_comment_thread(context.scope, context.project.id, other.thread.id)
    assert detail.thread.message_count == 1
  end

  test "viewers can open a conversation but cannot post forged events", context do
    detail = create_comment(context)
    viewer = user_fixture()
    membership_fixture(context.project, viewer, "viewer")
    conn = log_in_user(build_conn(), viewer)
    view = open_flow(%{context | conn: conn}, "?thread=#{detail.thread.id}")
    assert panel(view)["thread"]["id"] == detail.thread.id
    refute panel(view)["canComment"]

    render_hook(view, "comments_reply", %{
      thread_id: detail.thread.id,
      parent_id: hd(detail.messages).id,
      body: "Forged viewer write",
      client_request_id: Ecto.UUID.generate()
    })

    assert {:ok, unchanged} = Projects.get_comment_thread(context.scope, context.project.id, detail.thread.id)
    assert unchanged.thread.message_count == 1
  end

  test "commenting works while another member holds the node edit lock", context do
    editor = user_fixture()
    membership_fixture(context.project, editor)
    assert {:ok, _lock} = Collaboration.acquire_lock({:flow, context.flow.id}, context.node.id, editor)
    view = open_flow(context)
    render_hook(view, "comments_open", %{node_id: context.node.id})

    render_hook(view, "comments_create", %{
      node_id: context.node.id,
      body: "Review while you edit",
      client_request_id: Ecto.UUID.generate()
    })

    assert panel(view)["thread"]["message_count"] == 1
    assert {:ok, %{user_id: editor_id}} = Collaboration.get_lock({:flow, context.flow.id}, context.node.id)
    assert editor_id == editor.id
  end

  test "a committed reply refreshes an open conversation through invalidation", context do
    detail = create_comment(context)
    view = open_flow(context, "?thread=#{detail.thread.id}")

    assert {:ok, _reply} =
             Projects.reply_to_comment_thread(context.scope, context.project.id, detail.thread.id, %{
               body: "Another window replied",
               parent_id: hd(detail.messages).id,
               client_request_id: Ecto.UUID.generate()
             })

    assert panel(view)["thread"]["message_count"] == 2
    assert List.last(panel(view)["messages"])["body"] == "Another window replied"
  end

  test "a remote graph refresh updates comment counts and source availability after deletion", context do
    hub = node_fixture(context.flow, %{type: "hub", data: %{"hub_id" => "reviewed_hub", "label" => "Reviewed hub"}})
    jump = node_fixture(context.flow, %{type: "jump", data: %{"target_hub_id" => "reviewed_hub"}})
    detail = create_comment(%{context | node: hub})
    view = open_flow(context, "?thread=#{detail.thread.id}")

    assert panel(view)["thread"]["source"]["status"] == "available"
    surface = LiveVue.Test.get_vue(view, name: "live/flow/show/FlowSurface")
    assert surface.props["surface"]["canvas"]["commentCounts"][to_string(hub.id)] == 1

    assert {:ok, _deleted, %{graph_changed?: true, orphaned_jumps: 1}} = Flows.delete_node(hub)
    assert Flows.get_node(context.flow.id, jump.id).data["target_hub_id"] == ""

    send(view.pid, {:remote_change, :flow_refresh, %{node_id: hub.id}})

    state = panel(view)
    assert state["thread"]["id"] == detail.thread.id
    assert state["thread"]["source"]["status"] == "unavailable"
    assert [%{"body" => "Review this beat"}] = state["messages"]

    surface = LiveVue.Test.get_vue(view, name: "live/flow/show/FlowSurface")
    assert surface.props["surface"]["canvas"]["commentCounts"] == %{}
    assert surface.props["surface"]["canvas"]["commentFocusNodeId"] == nil
  end

  test "malformed node and revision payloads fail without crashing", context do
    view = open_flow(context)
    render_hook(view, "comments_open", %{node_id: "1 OR 1=1"})
    assert panel(view)["thread"] == nil
    render_hook(view, "comments_set_status", %{thread_id: "bad", status: "resolved", expected_revision: "bad"})
    assert is_binary(panel(view)["error"])
  end

  test "losing access before loading older replies clears every conversation projection", context do
    detail = create_comment(context)
    editor = user_fixture()
    membership = membership_fixture(context.project, editor)

    for number <- 1..31 do
      assert {:ok, _detail} =
               Projects.reply_to_comment_thread(context.scope, context.project.id, detail.thread.id, %{
                 body: "Reply #{number}",
                 parent_id: hd(detail.messages).id,
                 client_request_id: Ecto.UUID.generate()
               })
    end

    conn = log_in_user(build_conn(), editor)
    view = open_flow(%{context | conn: conn}, "?thread=#{detail.thread.id}")
    assert panel(view)["messageNextCursor"]
    Repo.delete!(membership)
    render_hook(view, "comments_load_messages", %{})

    assert %{"thread" => nil, "threads" => [], "messages" => [], "members" => [], "canComment" => false} = panel(view)
    surface = LiveVue.Test.get_vue(view, name: "live/flow/show/FlowSurface")
    assert surface.props["surface"]["canvas"]["commentCounts"] == %{}
    assert surface.props["surface"]["canvas"]["commentPins"] == []
    assert surface.props["surface"]["canvas"]["commentFocusThreadId"] == nil
  end

  defp create_comment(context) do
    {:ok, detail} =
      Projects.create_flow_node_comment(context.scope, context.project.id, context.flow.id, context.node.id, %{
        body: "Review this beat",
        client_request_id: Ecto.UUID.generate()
      })

    detail
  end

  defp open_flow(context, query \\ "") do
    path = ~p"/workspaces/#{context.project.workspace.slug}/projects/#{context.project.slug}/flows/#{context.flow.id}"
    {:ok, view, _html} = live(context.conn, path <> query)
    render_async(view, 5000)
    view
  end

  defp panel(view) do
    render(view)
    LiveVue.Test.get_vue(view, name: "live/flow/show/FlowPanels").props["panels"]["comments"]
  end

  defp canvas(view) do
    render(view)
    LiveVue.Test.get_vue(view, name: "live/flow/show/FlowSurface").props["surface"]["canvas"]
  end
end
