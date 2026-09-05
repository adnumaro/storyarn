defmodule StoryarnWeb.SheetLive.CommentsTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Projects
  alias Storyarn.Repo

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
    LiveVue.Test.get_vue(view, name: "live/sheet/show/SheetHeader").props["comments"]
  end
end
