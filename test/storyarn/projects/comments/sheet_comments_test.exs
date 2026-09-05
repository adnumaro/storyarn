defmodule Storyarn.Projects.SheetCommentsTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.Platform
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Projects
  alias Storyarn.Projects.Comments.Message
  alias Storyarn.Projects.Comments.Thread
  alias Storyarn.Projects.Persistence.FlowRecord
  alias Storyarn.Sheets

  setup do
    owner = user_fixture()
    workspace = workspace_fixture(owner)
    project = project_fixture(owner, %{workspace: workspace})
    sheet = sheet_fixture(project, %{name: "Character"})

    %{
      owner: owner,
      scope: user_scope_fixture(owner),
      workspace: workspace,
      project: project,
      sheet: sheet
    }
  end

  test "creates a Sheet-owned canvas anchor and resolves its destinations", ctx do
    recipient = user_fixture()
    membership_fixture(ctx.project, recipient, "viewer")
    recipient_scope = user_scope_fixture(recipient)
    assert :ok = Projects.subscribe_sheet_comments(ctx.scope, ctx.project.id, ctx.sheet.id)

    request = %{attrs() | mention_user_ids: [recipient.id]}
    assert {:ok, detail} = create_sheet_comment(ctx, request)
    sheet_id = ctx.sheet.id
    assert_receive {:sheet_comments_changed, ^sheet_id}

    assert {:ok, repeated} = create_sheet_comment(ctx, request)
    assert repeated.thread.id == detail.thread.id
    refute_receive {:sheet_comments_changed, _}
    assert Repo.aggregate(Thread, :count) == 1
    assert Repo.aggregate(Message, :count) == 1

    assert detail.thread.position == %{x: 25.5, y: 750.0}

    assert detail.thread.source == %{
             type: "sheet_canvas",
             id: sheet_id,
             sheet_id: sheet_id,
             label: "Character",
             status: "available"
           }

    stored = Repo.get!(Thread, detail.thread.id)
    assert stored.sheet_canvas_id == sheet_id
    assert stored.flow_node_id == nil
    assert stored.flow_canvas_id == nil
    assert stored.scene_canvas_id == nil
    assert stored.source_id == sheet_id
    assert stored.container_id == sheet_id
    assert stored.source_inserted_at == ctx.sheet.inserted_at

    message = hd(detail.messages)
    thread_id = detail.thread.id

    assert {:ok, %{surface: "sheet", sheet_id: ^sheet_id, thread_id: ^thread_id} = destination} =
             Projects.comment_destination(recipient_scope, ctx.project.id, message.id)

    refute Map.has_key?(destination, :block_id)
    key = {ctx.project.id, message.id}

    assert %{
             ^key => %{
               surface: "sheet",
               sheet_id: ^sheet_id,
               thread_id: ^thread_id,
               project_slug: project_slug,
               workspace_slug: workspace_slug
             }
           } = destinations = Projects.comment_destinations(recipient_scope, [message.id])

    refute Map.has_key?(destinations[key], :block_id)
    assert project_slug == ctx.project.slug
    assert workspace_slug == ctx.workspace.slug
    assert Enum.any?(Platform.list_notifications(recipient_scope), &(&1.entity_id == message.id))

    assert {:ok, %{threads: [listed], next_cursor: nil}} =
             Projects.list_sheet_comment_threads(ctx.scope, ctx.project.id, sheet_id)

    assert listed.id == thread_id
    assert {:ok, [pin]} = Projects.list_sheet_comment_pins(ctx.scope, ctx.project.id, sheet_id)
    assert pin.id == thread_id
    assert :ok = Projects.unsubscribe_sheet_comments(ctx.project.id, sheet_id)
  end

  test "uses normalized horizontal positions and stable vertical document offsets", ctx do
    for position <- [
          nil,
          [],
          %{},
          %{x: 1},
          %{x: "1", y: 2},
          %{x: -0.1, y: 50},
          %{x: 100.1, y: 50},
          %{x: 50, y: -0.1},
          %{x: 50, y: 10_000_000.1},
          %{x: :infinity, y: 50}
        ] do
      assert {:error, :invalid_position} = create_sheet_comment(ctx, %{attrs() | position: position})
    end

    assert Repo.aggregate(Thread, :count) == 0
    assert {:ok, detail} = create_sheet_comment(ctx, %{attrs() | position: %{x: 0, y: 10_000_000}})
    assert :ok = Projects.subscribe_sheet_comments(ctx.scope, ctx.project.id, ctx.sheet.id)
    original_source = detail.thread.source

    assert {:error, :invalid_position} =
             Projects.move_comment_thread(
               ctx.scope,
               ctx.project.id,
               detail.thread.id,
               %{x: 101, y: 50},
               detail.thread.revision
             )

    assert {:ok, moved} =
             Projects.move_comment_thread(
               ctx.scope,
               ctx.project.id,
               detail.thread.id,
               %{x: 80, y: 5_000},
               detail.thread.revision
             )

    assert moved.position == %{x: 80.0, y: 5_000.0}
    assert moved.source == original_source
    assert moved.revision == detail.thread.revision + 1
    assert_receive {:sheet_comments_changed, sheet_id} when sheet_id == ctx.sheet.id

    stored = Repo.get!(Thread, detail.thread.id)
    assert stored.sheet_canvas_id == ctx.sheet.id
    assert stored.source_id == ctx.sheet.id
    assert stored.container_id == ctx.sheet.id
    assert :ok = Projects.unsubscribe_sheet_comments(ctx.project.id, ctx.sheet.id)
  end

  test "comments belong only to the exact Sheet and are never inherited", ctx do
    child = child_sheet_fixture(ctx.project, ctx.sheet, %{name: "Child character"})
    assert {:ok, parent_detail} = create_sheet_comment(ctx)

    assert {:ok, %{threads: []}} =
             Projects.list_sheet_comment_threads(ctx.scope, ctx.project.id, child.id)

    assert {:ok, []} = Projects.list_sheet_comment_pins(ctx.scope, ctx.project.id, child.id)

    assert {:ok, child_detail} =
             Projects.create_sheet_canvas_comment(ctx.scope, ctx.project.id, child.id, %{
               attrs()
               | body: "Only the child Sheet sees this",
                 client_request_id: Ecto.UUID.generate()
             })

    assert parent_detail.thread.source.id == ctx.sheet.id
    assert child_detail.thread.source.id == child.id

    assert {:ok, %{threads: [listed_parent]}} =
             Projects.list_sheet_comment_threads(ctx.scope, ctx.project.id, ctx.sheet.id)

    assert {:ok, %{threads: [listed_child]}} =
             Projects.list_sheet_comment_threads(ctx.scope, ctx.project.id, child.id)

    assert listed_parent.id == parent_detail.thread.id
    assert listed_child.id == child_detail.thread.id
  end

  test "block lifecycle never changes a Sheet-owned comment", ctx do
    block = block_fixture(ctx.sheet)
    assert {:ok, detail} = create_sheet_comment(ctx)

    assert {:ok, deleted_block} = Sheets.delete_block(block)
    assert {:ok, [after_delete]} = Projects.list_sheet_comment_pins(ctx.scope, ctx.project.id, ctx.sheet.id)
    assert after_delete.id == detail.thread.id
    assert after_delete.source.status == "available"

    assert {:ok, _restored_block} = Sheets.restore_block(deleted_block)
    assert {:ok, [after_restore]} = Projects.list_sheet_comment_pins(ctx.scope, ctx.project.id, ctx.sheet.id)
    assert after_restore.id == detail.thread.id
    assert after_restore.position == detail.thread.position
  end

  test "soft deletion hides a Sheet canvas, restore revives it and hard deletion preserves history", ctx do
    assert {:ok, detail} = create_sheet_comment(ctx)
    root_message_id = detail.thread.root_message_id
    assert {:ok, deleted_sheet} = Sheets.delete_sheet(ctx.sheet)

    assert {:ok, unavailable} = Projects.get_comment_thread(ctx.scope, ctx.project.id, detail.thread.id)
    assert unavailable.thread.source.status == "unavailable"
    assert unavailable.thread.source.label == "Character"
    assert {:ok, []} = Projects.list_sheet_comment_pins(ctx.scope, ctx.project.id, ctx.sheet.id)
    assert Projects.comment_destinations(ctx.scope, [root_message_id]) == %{}

    assert {:error, :source_unavailable} =
             Projects.move_comment_thread(
               ctx.scope,
               ctx.project.id,
               detail.thread.id,
               %{x: 30, y: 300},
               detail.thread.revision
             )

    assert {:ok, restored_sheet} = Sheets.restore_sheet(deleted_sheet)
    assert {:ok, [pin]} = Projects.list_sheet_comment_pins(ctx.scope, ctx.project.id, ctx.sheet.id)
    assert pin.id == detail.thread.id
    assert pin.source.status == "available"

    messages = Repo.all(Message)
    assert {:ok, _deleted} = Sheets.permanently_delete_sheet(restored_sheet)
    stored = Repo.get!(Thread, detail.thread.id)
    assert stored.sheet_canvas_id == nil
    assert stored.source_id == ctx.sheet.id
    assert stored.container_id == ctx.sheet.id
    assert Repo.all(Message) == messages

    assert {:ok, hard_deleted} = Projects.get_comment_thread(ctx.scope, ctx.project.id, detail.thread.id)
    assert hard_deleted.thread.source.status == "unavailable"
  end

  test "equal Flow and Sheet IDs remain isolated in lists, pins, topics and destinations", ctx do
    shared_id = ctx.sheet.id
    now = TimeHelpers.now()

    Repo.insert!(%FlowRecord{
      id: shared_id,
      project_id: ctx.project.id,
      name: "Colliding Flow",
      shortcut: "collision-flow-#{shared_id}",
      inserted_at: now,
      updated_at: now
    })

    assert :ok = Projects.subscribe_flow_comments(ctx.scope, ctx.project.id, shared_id)
    assert :ok = Projects.subscribe_sheet_comments(ctx.scope, ctx.project.id, shared_id)

    assert {:ok, flow_detail} =
             Projects.create_flow_canvas_comment(ctx.scope, ctx.project.id, shared_id, %{
               attrs()
               | position: %{x: 25.5, y: 75},
                 client_request_id: Ecto.UUID.generate()
             })

    assert_receive {:flow_comments_changed, ^shared_id}

    assert {:ok, sheet_detail} = create_sheet_comment(ctx)
    assert_receive {:sheet_comments_changed, ^shared_id}

    assert {:ok, %{threads: [listed_flow]}} =
             Projects.list_flow_comment_threads(ctx.scope, ctx.project.id, shared_id)

    assert listed_flow.id == flow_detail.thread.id
    assert listed_flow.source.type == "flow_canvas"

    assert {:ok, %{threads: [listed_sheet]}} =
             Projects.list_sheet_comment_threads(ctx.scope, ctx.project.id, shared_id)

    assert listed_sheet.id == sheet_detail.thread.id
    assert listed_sheet.source.type == "sheet_canvas"

    assert {:ok, [flow_pin]} = Projects.list_flow_comment_pins(ctx.scope, ctx.project.id, shared_id)
    assert flow_pin.id == flow_detail.thread.id
    assert {:ok, [sheet_pin]} = Projects.list_sheet_comment_pins(ctx.scope, ctx.project.id, shared_id)
    assert sheet_pin.id == sheet_detail.thread.id

    flow_message_id = flow_detail.thread.root_message_id
    sheet_message_id = sheet_detail.thread.root_message_id
    project_id = ctx.project.id
    destinations = Projects.comment_destinations(ctx.scope, [flow_message_id, sheet_message_id])

    assert %{
             {^project_id, ^flow_message_id} => %{surface: "flow", flow_id: ^shared_id},
             {^project_id, ^sheet_message_id} => %{surface: "sheet", sheet_id: ^shared_id}
           } = destinations

    assert :ok = Projects.unsubscribe_flow_comments(ctx.project.id, shared_id)
    assert :ok = Projects.unsubscribe_sheet_comments(ctx.project.id, shared_id)
  end

  test "cannot create a Sheet anchor across project boundaries", ctx do
    other_project = project_fixture()
    other_sheet = sheet_fixture(other_project)

    assert {:error, :source_unavailable} =
             Projects.create_sheet_canvas_comment(ctx.scope, ctx.project.id, other_sheet.id, attrs())
  end

  defp attrs do
    %{
      body: "Review this Sheet",
      position: %{x: 25.5, y: 750},
      client_request_id: Ecto.UUID.generate(),
      mention_user_ids: []
    }
  end

  defp create_sheet_comment(ctx, request \\ attrs()) do
    Projects.create_sheet_canvas_comment(ctx.scope, ctx.project.id, ctx.sheet.id, request)
  end
end
