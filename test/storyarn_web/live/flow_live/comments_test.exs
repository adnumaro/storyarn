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

  test "Sequence workspace uses the dialogue's shared thread and preserves its presentation", context do
    detail = create_comment(context)
    view = open_flow(context)
    render_hook(view, "comments_open", %{node_id: context.node.id, presentation: "workspace"})
    assert panel(view)["presentation"] == "workspace"
    assert panel(view)["selectedNodeId"] == context.node.id
    render_hook(view, "comments_select_thread", %{thread_id: detail.thread.id})
    assert panel(view)["presentation"] == "workspace"
    assert panel(view)["thread"]["id"] == detail.thread.id
    render_hook(view, "comments_open", %{node_id: context.node.id, presentation: "workspace"})

    render_hook(view, "comments_create", %{
      node_id: context.node.id,
      body: "Move this character to the left",
      client_request_id: Ecto.UUID.generate()
    })

    state = panel(view)
    assert state["presentation"] == "workspace"
    assert state["thread"]["source"]["id"] == context.flow.id
    assert state["thread"]["context"]["id"] == to_string(context.node.id)
    render_hook(view, "comments_close", %{})
    render_hook(view, "comments_select_thread", %{thread_id: state["thread"]["id"], presentation: "canvas"})
    assert panel(view)["presentation"] == "canvas"
    assert [%{"body" => "Move this character to the left"}] = panel(view)["messages"]
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
    assert state["thread"]["source"]["id"] == context.flow.id
    assert state["thread"]["context"]["id"] == to_string(context.node.id)
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

  test "a cold link to deleted context still focuses the surface pin and allows replies", context do
    detail = create_comment(context)
    Repo.delete!(context.node)

    view = open_flow(context, "?thread=#{detail.thread.id}")

    assert panel(view)["thread"]["id"] == detail.thread.id
    assert panel(view)["thread"]["source"]["status"] == "available"
    assert panel(view)["thread"]["context"]["status"] == "unavailable"
    assert panel(view)["presentation"] == "canvas"
    assert [%{"body" => "Review this beat"}] = panel(view)["messages"]
    assert canvas(view)["commentFocusThreadId"] == detail.thread.id
    assert canvas(view)["commentFocusNodeId"] == nil
    assert [%{"id" => thread_id, "context" => %{"status" => "unavailable"}}] = canvas(view)["commentPins"]
    assert thread_id == detail.thread.id

    render_hook(view, "comments_reply", %{
      thread_id: detail.thread.id,
      parent_id: hd(detail.messages).id,
      body: "Continue the discussion after removing the node",
      client_request_id: Ecto.UUID.generate()
    })

    assert panel(view)["thread"]["message_count"] == 2
    assert panel(view)["thread"]["context"]["status"] == "unavailable"
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

  test "node placement stores surface coordinates and a context offset, and Escape cancels placement", context do
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

    assert [pin] = canvas(view)["commentPins"]
    assert pin["source"]["type"] == "flow_canvas"
    assert pin["source"]["id"] == context.flow.id
    assert pin["position"] == %{"x" => context.node.position_x + 25.0, "y" => context.node.position_y + 30.0}
    assert pin["context"]["type"] == "flow_node"
    assert pin["context"]["id"] == to_string(context.node.id)
    assert pin["context"]["offset"] == %{"x" => 25.0, "y" => 30.0}

    render_hook(view, "comments_mode", %{active: true})
    render_hook(view, "comments_mode", %{active: false})
    refute panel(view)["placing"]
    refute panel(view)["open"]
    assert {:error, :not_locked} = Collaboration.get_lock({:flow, context.flow.id}, context.node.id)
  end

  test "a magnetic draft keeps absolute coordinates and context through movement, creation, retry and reload", context do
    view = open_flow(context)
    reference = %{type: "flow_node", id: to_string(context.node.id), offset: %{x: 25, y: 30}}
    position = %{x: context.node.position_x + 25, y: context.node.position_y + 30}
    render_hook(view, "comments_place", Map.merge(position, %{node_id: nil, context: reference}))

    placed = panel(view)
    assert placed["selectedNodeId"] == nil
    assert placed["draftPosition"] == %{"x" => position.x, "y" => position.y}
    assert placed["draftContext"] == %{"type" => "flow_node", "id" => reference.id, "offset" => %{"x" => 25, "y" => 30}}

    other_node = node_fixture(context.flow)
    moved_reference = %{type: "flow_node", id: to_string(other_node.id), offset: %{x: 50, y: -20}}
    moved_position = %{x: other_node.position_x + 50, y: other_node.position_y - 20}

    render_hook(
      view,
      "comments_place",
      Map.merge(moved_position, %{
        node_id: nil,
        context: moved_reference,
        moving_draft: true,
        draft_id: placed["draftId"]
      })
    )

    moved = panel(view)
    assert moved["draftId"] == placed["draftId"]
    assert moved["draftContext"]["id"] == to_string(other_node.id)
    assert moved["selectedNodeId"] == nil

    attrs = %{
      node_id: nil,
      position: moved["draftPosition"],
      context: moved["draftContext"],
      body: "A draft snapped to a different beat",
      client_request_id: Ecto.UUID.generate()
    }

    render_hook(view, "comments_create", attrs)
    thread = panel(view)["thread"]
    assert thread["source"]["type"] == "flow_canvas"
    assert thread["source"]["id"] == context.flow.id
    assert thread["position"] == %{"x" => moved_position.x, "y" => moved_position.y}
    assert thread["context"]["id"] == to_string(other_node.id)
    assert thread["context"]["offset"] == %{"x" => 50.0, "y" => -20.0}
    assert panel(view)["draftContext"] == nil

    render_hook(view, "comments_create", attrs)
    assert panel(view)["thread"]["id"] == thread["id"]
    assert panel(view)["thread"]["message_count"] == 1
    assert [pin] = canvas(view)["commentPins"]
    assert pin["id"] == thread["id"]

    reloaded = open_flow(context, "?thread=#{thread["id"]}")
    assert panel(reloaded)["thread"]["context"] == thread["context"]
    assert panel(reloaded)["thread"]["position"] == thread["position"]
  end

  test "a remote node deletion detaches an open draft without replacing its composer or position", context do
    reference = %{type: "flow_node", id: to_string(context.node.id), offset: %{x: 25, y: 30}}
    position = %{x: context.node.position_x + 25, y: context.node.position_y + 30}
    view = open_flow(context)
    render_hook(view, "comments_place", Map.put(position, :context, reference))
    assert_reply(view, %{ok: true})
    placed = panel(view)

    render_hook(view, "comments_refresh", %{})
    assert panel(view)["draftContext"] == placed["draftContext"]
    assert panel(view)["draftId"] == placed["draftId"]

    assert {:ok, _deleted, _meta} = Flows.delete_node(context.node)
    send(view.pid, {:remote_change, :node_deleted, %{node_id: context.node.id}})

    detached = panel(view)
    assert detached["open"]
    assert detached["presentation"] == "canvas"
    assert detached["draftId"] == placed["draftId"]
    assert detached["draftPosition"] == placed["draftPosition"]
    assert detached["draftContext"] == nil
    assert detached["selectedNodeId"] == nil
    assert detached["error"] == nil

    render_hook(view, "comments_create", %{
      position: detached["draftPosition"],
      context: detached["draftContext"],
      body: "Continue writing after the collaborator removes the beat",
      client_request_id: Ecto.UUID.generate()
    })

    assert_reply(view, %{ok: true})
    assert panel(view)["thread"]["source"]["id"] == context.flow.id
    assert panel(view)["thread"]["context"] == nil
    assert panel(view)["thread"]["position"] == placed["draftPosition"]
    assert [%{"body" => "Continue writing after the collaborator removes the beat"}] = panel(view)["messages"]
  end

  test "a draft submission racing node deletion explains the context failure and can retry in place", context do
    reference = %{type: "flow_node", id: to_string(context.node.id), offset: %{x: 25, y: 30}}
    position = %{x: context.node.position_x + 25, y: context.node.position_y + 30}
    view = open_flow(context)
    render_hook(view, "comments_place", Map.put(position, :context, reference))
    assert_reply(view, %{ok: true})
    placed = panel(view)

    attrs = %{
      position: placed["draftPosition"],
      context: placed["draftContext"],
      body: "Keep the text when sending races the deletion",
      client_request_id: Ecto.UUID.generate()
    }

    # Delete without a collaboration notification so create sees the stale context first.
    Repo.delete!(context.node)
    render_hook(view, "comments_create", attrs)

    assert_reply(view, %{
      ok: false,
      context_unavailable: true,
      error: "The comment context is no longer available. Review the pin's position and try again."
    })

    detached = panel(view)
    assert detached["open"]
    assert detached["presentation"] == "canvas"
    assert detached["draftId"] == placed["draftId"]
    assert detached["draftPosition"] == placed["draftPosition"]
    assert detached["draftContext"] == nil
    assert detached["thread"] == nil

    render_hook(view, "comments_create", %{attrs | context: detached["draftContext"]})
    assert_reply(view, %{ok: true})
    assert panel(view)["thread"]["context"] == nil
    assert panel(view)["thread"]["position"] == placed["draftPosition"]
    assert [%{"body" => "Keep the text when sending races the deletion"}] = panel(view)["messages"]
  end

  test "a restored draft whose node disappeared can recover as a free comment", context do
    reference = %{type: "flow_node", id: to_string(context.node.id), offset: %{x: 25, y: 30}}
    position = %{x: context.node.position_x + 25, y: context.node.position_y + 30}
    view = open_flow(context)
    render_hook(view, "comments_place", Map.put(position, :context, reference))
    assert_reply(view, %{ok: true})
    assert panel(view)["draftContext"]["id"] == reference.id

    assert {:ok, _deleted, _meta} = Flows.delete_node(context.node)
    reloaded = open_flow(context)
    render_hook(reloaded, "comments_place", Map.put(position, :context, reference))
    assert_reply(reloaded, %{ok: false, context_unavailable: true})
    assert panel(reloaded)["draftPosition"] == nil

    render_hook(reloaded, "comments_place", Map.put(position, :context, nil))
    assert_reply(reloaded, %{ok: true})
    assert panel(reloaded)["draftPosition"] == %{"x" => position.x, "y" => position.y}
    assert panel(reloaded)["draftContext"] == nil

    render_hook(reloaded, "comments_create", %{
      position: position,
      context: nil,
      body: "Keep the draft after its beat disappears",
      client_request_id: Ecto.UUID.generate()
    })

    assert panel(reloaded)["thread"]["source"]["id"] == context.flow.id
    assert panel(reloaded)["thread"]["context"] == nil
    assert [%{"body" => "Keep the draft after its beat disappears"}] = panel(reloaded)["messages"]
  end

  test "a magnetic draft can become free and late moves cannot reopen it or replace another draft", context do
    view = open_flow(context)
    reference = %{type: "flow_node", id: to_string(context.node.id)}
    render_hook(view, "comments_place", %{x: 100, y: 200, context: reference})
    draft_id = panel(view)["draftId"]
    move = %{x: 300, y: 400, context: nil, moving_draft: true, draft_id: draft_id}
    render_hook(view, "comments_place", move)
    assert panel(view)["draftId"] == draft_id
    assert panel(view)["draftContext"] == nil
    assert panel(view)["draftPosition"] == %{"x" => 300, "y" => 400}

    render_hook(view, "comments_close", %{})
    render_hook(view, "comments_place", move)
    refute panel(view)["open"]
    assert panel(view)["draftPosition"] == nil
    assert panel(view)["draftContext"] == nil

    render_hook(view, "comments_place", %{x: 600, y: 700, context: reference})
    new_id = panel(view)["draftId"]
    refute new_id == draft_id
    render_hook(view, "comments_place", move)
    render_hook(view, "comments_place", Map.delete(move, :draft_id))
    assert panel(view)["draftId"] == new_id
    assert panel(view)["draftPosition"] == %{"x" => 600, "y" => 700}
    assert panel(view)["draftContext"]["id"] == reference.id

    render_hook(view, "comments_open", %{node_id: context.node.id, presentation: "workspace"})
    assert panel(view)["draftContext"] == nil
    assert panel(view)["draftPosition"] == nil
    assert panel(view)["selectedNodeId"] == context.node.id
  end

  test "draft context rejects foreign, deleted, malformed and ambiguous node references", context do
    view = open_flow(context)
    foreign_node = context.project |> flow_fixture() |> node_fixture()
    deleted_node = node_fixture(context.flow)
    Repo.delete!(deleted_node)

    invalid_references = [
      %{type: "flow_node", id: to_string(foreign_node.id)},
      %{type: "flow_node", id: to_string(deleted_node.id)},
      %{type: "flow_node", id: "not-a-node"},
      %{type: "sheet_header", id: to_string(context.flow.id)},
      %{type: "flow_node", id: to_string(context.node.id), offset: %{x: 10_000_001, y: 0}},
      %{type: "flow_node", id: to_string(context.node.id), offset: %{x: "NaN", y: 0}},
      %{type: "flow_node", id: to_string(context.node.id), offset: []}
    ]

    for reference <- invalid_references do
      render_hook(view, "comments_place", %{x: 100, y: 200, context: reference})
      assert panel(view)["draftPosition"] == nil
      assert panel(view)["draftContext"] == nil
      assert is_binary(panel(view)["error"])
    end

    render_hook(view, "comments_place", %{
      node_id: context.node.id,
      x: 100,
      y: 200,
      context: %{type: "flow_node", id: to_string(context.node.id)}
    })

    assert panel(view)["draftPosition"] == nil
    assert panel(view)["draftContext"] == nil
  end

  test "a surface comment can change and detach its context without changing its owner", context do
    view = open_flow(context)

    render_hook(view, "comments_create", %{
      position: %{x: 300, y: 200},
      context: %{type: "flow_node", id: to_string(context.node.id)},
      body: "A contextual surface comment",
      client_request_id: Ecto.UUID.generate()
    })

    thread = panel(view)["thread"]
    assert thread["source"]["id"] == context.flow.id
    assert thread["context"]["id"] == to_string(context.node.id)
    assert thread["context"]["offset"] == %{"x" => 300 - context.node.position_x, "y" => 200 - context.node.position_y}

    other_node = node_fixture(context.flow)

    render_hook(view, "comments_move", %{
      thread_id: thread["id"],
      x: 500,
      y: 300,
      context: %{type: "flow_node", id: to_string(other_node.id)},
      expected_revision: thread["revision"]
    })

    moved = panel(view)["thread"]
    assert moved["context"]["id"] == to_string(other_node.id)
    assert moved["source"] == thread["source"]
    assert canvas(view)["commentCounts"] == %{to_string(other_node.id) => 1}
    assert canvas(view)["commentFocusNodeId"] == other_node.id

    render_hook(view, "comments_move", %{
      thread_id: moved["id"],
      x: 600,
      y: 400,
      context: nil,
      expected_revision: moved["revision"]
    })

    detached = panel(view)["thread"]
    assert detached["context"] == nil
    assert detached["source"] == thread["source"]
    assert detached["position"] == %{"x" => 600.0, "y" => 400.0}
    assert canvas(view)["commentCounts"] == %{}
    assert canvas(view)["commentFocusNodeId"] == nil
  end

  test "Sequence filters follow reassociation and detachment without changing the conversation", context do
    detail = create_comment(context)
    other_node = node_fixture(context.flow, %{type: "dialogue"})
    view = open_flow(context)
    render_hook(view, "comments_open", %{node_id: context.node.id, presentation: "workspace"})
    assert [%{"id" => id}] = panel(view)["threads"]
    assert id == detail.thread.id

    render_hook(view, "comments_move", %{
      thread_id: id,
      x: 500,
      y: 600,
      context: %{type: "flow_node", id: to_string(other_node.id)},
      expected_revision: detail.thread.revision
    })

    render_hook(view, "comments_open", %{node_id: context.node.id, presentation: "workspace"})
    assert panel(view)["threads"] == []
    render_hook(view, "comments_open", %{node_id: other_node.id, presentation: "workspace"})
    assert [%{"id" => ^id} = moved] = panel(view)["threads"]
    render_hook(view, "comments_select_thread", %{thread_id: id})
    assert panel(view)["presentation"] == "workspace"
    assert [%{"body" => "Review this beat"}] = panel(view)["messages"]

    render_hook(view, "comments_move", %{
      thread_id: id,
      x: 700,
      y: 800,
      context: nil,
      expected_revision: moved["revision"]
    })

    render_hook(view, "comments_open", %{node_id: other_node.id, presentation: "workspace"})
    assert panel(view)["threads"] == []
    render_hook(view, "comments_open", %{})
    assert [%{"id" => ^id, "context" => nil}] = panel(view)["threads"]

    reloaded = open_flow(context, "?thread=#{id}")
    assert panel(reloaded)["thread"]["id"] == id
    assert panel(reloaded)["thread"]["source"]["id"] == context.flow.id
    assert [%{"body" => "Review this beat"}] = panel(reloaded)["messages"]
  end

  test "invalid and stale magnetic moves preserve both context and position and return authoritative state", context do
    detail = create_comment(context)
    foreign_node = context.project |> flow_fixture() |> node_fixture()
    view = open_flow(context, "?thread=#{detail.thread.id}")
    original = panel(view)["thread"]

    render_hook(view, "comments_move", %{
      thread_id: detail.thread.id,
      x: 500,
      y: 600,
      context: %{type: "flow_node", id: to_string(foreign_node.id)},
      expected_revision: detail.thread.revision
    })

    assert_reply(view, %{ok: false, context_unavailable: true})
    assert panel(view)["thread"] == original

    render_hook(view, "comments_move", %{
      thread_id: detail.thread.id,
      x: detail.thread.position.x,
      y: detail.thread.position.y,
      context: %{type: "flow_node", id: to_string(context.node.id)},
      expected_revision: detail.thread.revision
    })

    revision = detail.thread.revision
    assert_reply(view, %{ok: true, thread: %{revision: ^revision}})
    assert panel(view)["thread"] == original

    render_hook(view, "comments_move", %{
      thread_id: detail.thread.id,
      x: 800,
      y: 900,
      context: nil,
      expected_revision: revision
    })

    assert_reply(view, %{ok: true})
    detached = panel(view)["thread"]
    assert detached["context"] == nil

    render_hook(view, "comments_move", %{
      thread_id: detail.thread.id,
      x: 100,
      y: 200,
      context: %{type: "flow_node", id: to_string(context.node.id)},
      expected_revision: revision
    })

    assert_reply(view, %{ok: false, context_unavailable: false})
    assert panel(view)["thread"] == detached
    assert [%{"id" => id, "position" => %{"x" => 800.0, "y" => 900.0}, "context" => nil}] = canvas(view)["commentPins"]
    assert id == detail.thread.id
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

    assert {:ok, %{thread: unchanged_other}} =
             Projects.get_comment_thread(context.scope, context.project.id, other.thread.id)

    assert unchanged_other.position == other.thread.position
    assert unchanged_other.context == other.thread.context

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

    assert {:ok, %{thread: unchanged_own}} =
             Projects.get_comment_thread(context.scope, context.project.id, own.thread.id)

    assert unchanged_own.position == own.thread.position
    assert unchanged_own.context == own.thread.context
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

  test "a remote graph refresh removes node counts while preserving surface comment availability", context do
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
    assert state["thread"]["source"]["status"] == "available"
    assert state["thread"]["context"]["status"] == "unavailable"
    assert [%{"body" => "Review this beat"}] = state["messages"]

    surface = LiveVue.Test.get_vue(view, name: "live/flow/show/FlowSurface")
    assert surface.props["surface"]["canvas"]["commentCounts"] == %{}
    assert surface.props["surface"]["canvas"]["commentFocusNodeId"] == nil
    assert [%{"id" => pin_id}] = surface.props["surface"]["canvas"]["commentPins"]
    assert pin_id == detail.thread.id
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
