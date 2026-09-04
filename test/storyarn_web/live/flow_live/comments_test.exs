defmodule StoryarnWeb.FlowLive.CommentsTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

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
    assert surface.props["surface"]["canvas"]["commentCounts"][to_string(context.node.id)] == 1
    assert {:error, :not_locked} = Collaboration.get_lock({:flow, context.flow.id}, context.node.id)
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
end
