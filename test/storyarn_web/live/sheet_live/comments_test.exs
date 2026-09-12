defmodule StoryarnWeb.SheetLive.CommentsTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Projects
  alias Storyarn.Repo
  alias Storyarn.Sheets

  setup :register_and_log_in_user

  setup %{user: user} do
    project = user |> project_fixture() |> Repo.preload(:workspace)
    sheet = sheet_fixture(project, %{name: "Reviewable character"})
    block = block_fixture(sheet, %{config: %{"label" => "Motivation", "placeholder" => ""}})

    %{project: project, sheet: sheet, block: block, scope: user_scope_fixture(user)}
  end

  test "an editor creates, moves, replies to and resolves a Sheet canvas conversation", context do
    view = open_sheet(context)

    render_hook(view, "comments_mode", %{active: true})
    assert panel(view)["placing"]

    render_hook(view, "comments_place", %{x: 25, y: 750})
    assert panel(view)["draftPosition"] == %{"x" => 25, "y" => 750}
    assert panel(view)["presentation"] == "canvas"

    render_hook(view, "comments_create", %{
      position: %{x: 25, y: 750},
      body: "Clarify this part of the Sheet",
      client_request_id: Ecto.UUID.generate()
    })

    state = panel(view)
    thread = state["thread"]
    assert thread["source"]["type"] == "sheet_canvas"
    assert thread["source"]["sheet_id"] == context.sheet.id
    assert thread["source"]["id"] == context.sheet.id
    assert [%{"body" => "Clarify this part of the Sheet"}] = state["messages"]

    assert [%{"id" => thread_id, "position" => %{"x" => 25.0, "y" => 750.0}}] =
             content(view)["commentPins"]

    assert thread_id == thread["id"]
    assert header_comments(view)["count"] == 1

    render_hook(view, "comments_move", %{
      thread_id: thread["id"],
      x: 40,
      y: 960,
      expected_revision: thread["revision"]
    })

    moved = panel(view)["thread"]
    assert moved["position"] == %{"x" => 40.0, "y" => 960.0}
    assert [%{"position" => %{"x" => 40.0, "y" => 960.0}}] = content(view)["commentPins"]

    render_hook(view, "comments_reply", %{
      thread_id: moved["id"],
      parent_id: hd(panel(view)["messages"])["id"],
      body: "The new position is clearer",
      client_request_id: Ecto.UUID.generate()
    })

    replied = panel(view)["thread"]
    assert replied["message_count"] == 2
    assert List.last(panel(view)["messages"])["body"] == "The new position is clearer"

    render_hook(view, "comments_set_status", %{
      thread_id: replied["id"],
      status: "resolved",
      expected_revision: replied["revision"]
    })

    assert panel(view)["thread"]["status"] == "resolved"
    assert content(view)["commentPins"] == []
    assert header_comments(view)["count"] == 0
  end

  test "a deep link opens the exact Sheet conversation and realtime refreshes it", context do
    detail = create_comment(context)
    view = open_sheet(context, "?thread=#{detail.thread.id}")

    assert panel(view)["thread"]["id"] == detail.thread.id
    assert panel(view)["presentation"] == "canvas"
    assert content(view)["commentFocusThreadId"] == detail.thread.id

    assert {:ok, _reply} =
             Projects.reply_to_comment_thread(context.scope, context.project.id, detail.thread.id, %{
               body: "Another window replied",
               parent_id: hd(detail.messages).id,
               client_request_id: Ecto.UUID.generate()
             })

    assert panel(view)["thread"]["message_count"] == 2
    assert List.last(panel(view)["messages"])["body"] == "Another window replied"
  end

  test "context can change from a block to the header and detach while the Sheet owns the thread", context do
    view = open_sheet(context)

    render_hook(view, "comments_create", %{
      position: %{x: 25, y: 750},
      context: %{type: "sheet_block", id: to_string(context.block.id), offset: %{x: 5, y: 10}},
      body: "A movable Sheet comment",
      client_request_id: Ecto.UUID.generate()
    })

    thread = panel(view)["thread"]
    assert thread["source"]["type"] == "sheet_canvas"
    assert thread["source"]["id"] == context.sheet.id
    assert thread["context"]["id"] == to_string(context.block.id)

    render_hook(view, "comments_move", %{
      thread_id: thread["id"],
      x: 40,
      y: 100,
      context: %{type: "sheet_header", id: to_string(context.sheet.id)},
      expected_revision: thread["revision"]
    })

    header = panel(view)["thread"]
    assert header["source"] == thread["source"]
    assert header["context"]["type"] == "sheet_header"
    assert header["context"]["status"] == "available"
    assert header_comments(view)["count"] == 1

    render_hook(view, "comments_move", %{
      thread_id: header["id"],
      x: 50,
      y: 500,
      context: nil,
      expected_revision: header["revision"]
    })

    detached = panel(view)["thread"]
    assert detached["context"] == nil
    assert detached["source"] == thread["source"]
    assert detached["position"] == %{"x" => 50.0, "y" => 500.0}
  end

  test "draft placement validates context and keeps its identity when moving between targets", context do
    view = open_sheet(context)
    block_context = %{type: "sheet_block", id: to_string(context.block.id), offset: %{x: -2, y: 12}}

    render_hook(view, "comments_place", %{x: 25, y: 750, context: block_context})
    draft_id = panel(view)["draftId"]
    assert is_binary(draft_id)

    assert panel(view)["draftContext"] == %{
             "type" => "sheet_block",
             "id" => to_string(context.block.id),
             "offset" => %{"x" => -2.0, "y" => 12.0}
           }

    title_context = %{type: "sheet_title", id: to_string(context.sheet.id), offset: %{x: 5, y: 10}}

    render_hook(view, "comments_place", %{
      x: 45,
      y: 100,
      moving_draft: true,
      draft_id: draft_id,
      context: title_context
    })

    assert panel(view)["draftId"] == draft_id
    assert panel(view)["draftContext"]["type"] == "sheet_title"
    assert panel(view)["draftPosition"] == %{"x" => 45, "y" => 100}

    render_hook(view, "comments_create", %{
      position: %{x: 45, y: 100},
      context: title_context,
      body: "This refers to the title",
      client_request_id: Ecto.UUID.generate()
    })

    assert panel(view)["thread"]["context"]["type"] == "sheet_title"
    assert panel(view)["thread"]["source"]["id"] == context.sheet.id
    assert panel(view)["draftContext"] == nil
    assert panel(view)["draftId"] == nil
  end

  test "invalid draft context and late movement cannot replace, move or reopen the current draft", context do
    other_sheet = sheet_fixture(context.project)
    other_block = block_fixture(other_sheet)
    view = open_sheet(context)
    render_hook(view, "comments_place", %{x: 25, y: 750, context: nil})
    draft_id = panel(view)["draftId"]

    for invalid_context <- [
          %{type: "sheet_block", id: to_string(other_block.id)},
          %{type: "sheet_header", id: to_string(other_sheet.id)},
          %{type: "sheet_column_group", id: Ecto.UUID.generate()},
          %{type: "sheet_title", id: to_string(context.sheet.id), offset: %{x: 1, y: "invalid"}}
        ] do
      render_hook(view, "comments_place", %{
        x: 50,
        y: 100,
        moving_draft: true,
        draft_id: draft_id,
        context: invalid_context
      })

      assert panel(view)["draftId"] == draft_id
      assert panel(view)["draftPosition"] == %{"x" => 25, "y" => 750}
      assert panel(view)["draftContext"] == nil
    end

    render_hook(view, "comments_place", %{x: 30, y: 900, context: nil})
    replacement_id = panel(view)["draftId"]
    refute replacement_id == draft_id

    late_move = %{x: 50, y: 100, moving_draft: true, draft_id: draft_id, context: nil}
    render_hook(view, "comments_place", late_move)
    assert panel(view)["draftId"] == replacement_id
    assert panel(view)["draftPosition"] == %{"x" => 30, "y" => 900}

    render_hook(view, "comments_close", %{})
    render_hook(view, "comments_place", %{late_move | draft_id: replacement_id})
    refute panel(view)["open"]
    assert panel(view)["draftId"] == nil
    assert panel(view)["draftPosition"] == nil
  end

  test "deleting and undoing a block refreshes context without losing the open conversation", context do
    view = open_sheet(context)

    render_hook(view, "comments_create", %{
      position: %{x: 25, y: 750},
      context: %{type: "sheet_block", id: to_string(context.block.id)},
      body: "Keep this discussion after editing the layout",
      client_request_id: Ecto.UUID.generate()
    })

    thread_id = panel(view)["thread"]["id"]
    render_hook(view, "delete_block", %{id: to_string(context.block.id)})
    assert panel(view)["thread"]["context"]["status"] == "unavailable"
    assert panel(view)["thread"]["source"]["status"] == "available"
    assert [%{"id" => ^thread_id, "context" => %{"status" => "unavailable"}}] = content(view)["commentPins"]

    render_hook(view, "undo", %{})
    assert panel(view)["thread"]["context"]["status"] == "available"
    assert panel(view)["thread"]["id"] == thread_id
    assert [%{"body" => "Keep this discussion after editing the layout"}] = panel(view)["messages"]
  end

  test "remote row dissolution refreshes an open comment while retaining the Sheet destination", context do
    second = block_fixture(context.sheet)
    assert {:ok, group_id} = Sheets.create_column_group(context.sheet.id, [context.block.id, second.id])
    view = open_sheet(context)

    render_hook(view, "comments_create", %{
      position: %{x: 25, y: 750},
      context: %{type: "sheet_column_group", id: group_id},
      body: "Review this row",
      client_request_id: Ecto.UUID.generate()
    })

    thread = panel(view)["thread"]
    assert {:ok, _deleted} = Sheets.delete_block(context.block)
    send(view.pid, {:remote_change, :block_deleted, %{}})
    assert panel(view)["thread"]["context"]["status"] == "unavailable"
    assert panel(view)["thread"]["context"]["id"] == group_id
    assert panel(view)["thread"]["source"] == thread["source"]
    assert panel(view)["thread"]["position"] == thread["position"]
    assert panel(view)["thread"]["id"] == thread["id"]
  end

  test "viewers can read Sheet conversations but cannot forge mutations", context do
    detail = create_comment(context)
    viewer = user_fixture()
    membership_fixture(context.project, viewer, "viewer")

    view =
      context
      |> Map.put(:conn, log_in_user(build_conn(), viewer))
      |> open_sheet("?thread=#{detail.thread.id}")

    assert panel(view)["thread"]["id"] == detail.thread.id
    refute panel(view)["canComment"]

    render_hook(view, "comments_place", %{x: 10, y: 200})
    assert panel(view)["draftPosition"] == nil

    render_hook(view, "comments_reply", %{
      thread_id: detail.thread.id,
      parent_id: hd(detail.messages).id,
      body: "Forged viewer reply",
      client_request_id: Ecto.UUID.generate()
    })

    render_hook(view, "comments_move", %{
      thread_id: detail.thread.id,
      x: 10,
      y: 200,
      expected_revision: detail.thread.revision
    })

    assert {:ok, unchanged} =
             Projects.get_comment_thread(context.scope, context.project.id, detail.thread.id)

    assert unchanged.thread.message_count == 1
    assert unchanged.thread.position == %{x: 20.0, y: 300.0}
  end

  test "compact Sheet layouts omit comment state and restore it when returning", context do
    detail = create_comment(context)
    path = sheet_path(context)

    {:ok, view, _html} = live(context.conn, path <> "?layout=compact")
    render_async(view, 5000)

    compact_content = content(view)
    refute Map.has_key?(compact_content, "commentPins")
    refute Map.has_key?(compact_content, "comments")
    refute Map.has_key?(panels(view), "comments")

    render_hook(view, "acquire_block_lock", %{"block_id" => context.block.id})

    assert %{"userId" => user_id} =
             content(view)["blockLocks"][to_string(context.block.id)]

    assert user_id == context.user.id

    render_patch(view, path)
    assert panel(view)["canComment"]
    assert [%{"id" => thread_id}] = content(view)["commentPins"]
    assert thread_id == detail.thread.id

    render_patch(view, path <> "?layout=compact")
    refute Map.has_key?(content(view), "commentPins")
    refute Map.has_key?(panels(view), "comments")
  end

  test "a Sheet never exposes a parent or sibling Sheet conversation", context do
    parent_detail = create_comment(context)
    child = child_sheet_fixture(context.project, context.sheet, %{name: "Child character"})
    sibling = sheet_fixture(context.project, %{name: "Sibling character"})

    for other_sheet <- [child, sibling] do
      other_context = Map.put(context, :sheet, other_sheet)
      view = open_sheet(other_context, "?thread=#{parent_detail.thread.id}")

      assert panel(view)["thread"] == nil
      assert panel(view)["messages"] == []
      assert content(view)["commentPins"] == []
    end

    assert {:ok, child_detail} =
             Projects.create_sheet_canvas_comment(context.scope, context.project.id, child.id, %{
               body: "Child-only comment",
               position: %{x: 50, y: 450},
               client_request_id: Ecto.UUID.generate()
             })

    child_view =
      context
      |> Map.put(:sheet, child)
      |> open_sheet("?thread=#{child_detail.thread.id}")

    assert panel(child_view)["thread"]["id"] == child_detail.thread.id
    assert panel(child_view)["thread"]["source"]["id"] == child.id
  end

  defp create_comment(context) do
    {:ok, detail} =
      Projects.create_sheet_canvas_comment(
        context.scope,
        context.project.id,
        context.sheet.id,
        %{
          body: "Review this part of the Sheet",
          position: %{x: 20, y: 300},
          client_request_id: Ecto.UUID.generate()
        }
      )

    detail
  end

  defp open_sheet(context, query \\ "") do
    {:ok, view, _html} = live(context.conn, sheet_path(context) <> query)
    render_async(view, 5000)
    view
  end

  defp sheet_path(context) do
    ~p"/workspaces/#{context.project.workspace.slug}/projects/#{context.project.slug}/sheets/#{context.sheet.id}"
  end

  defp panel(view), do: panels(view)["comments"]

  defp panels(view) do
    render(view)
    LiveVue.Test.get_vue(view, name: "live/sheet/show/SheetSurface").props["panels"]
  end

  defp content(view) do
    render(view)
    LiveVue.Test.get_vue(view, name: "live/sheet/show/SheetSurface").props["surface"]["content"]
  end

  defp header_comments(view) do
    render(view)
    LiveVue.Test.get_vue(view, name: "live/shared/ContextualSourceHeader").props["header"]["comments"]
  end
end
