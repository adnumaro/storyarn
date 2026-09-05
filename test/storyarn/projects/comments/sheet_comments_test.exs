defmodule Storyarn.Projects.SheetCommentsTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.Platform
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Projects
  alias Storyarn.Projects.Comments.DTO
  alias Storyarn.Projects.Comments.Message
  alias Storyarn.Projects.Comments.Projections.SheetBlockRecord
  alias Storyarn.Projects.Comments.Thread
  alias Storyarn.Projects.Persistence.FlowRecord
  alias Storyarn.Sheets

  setup do
    owner = user_fixture()
    workspace = workspace_fixture(owner)
    project = project_fixture(owner, %{workspace: workspace})
    sheet = sheet_fixture(project, %{name: "Character"})
    block = block_fixture(sheet, %{config: %{"label" => "Motivation", "placeholder" => ""}})

    %{
      owner: owner,
      scope: user_scope_fixture(owner),
      workspace: workspace,
      project: project,
      sheet: sheet,
      block: block
    }
  end

  test "creates a block-relative Sheet anchor and resolves its destinations", ctx do
    recipient = user_fixture()
    membership_fixture(ctx.project, recipient, "viewer")
    recipient_scope = user_scope_fixture(recipient)
    assert :ok = Projects.subscribe_sheet_comments(ctx.scope, ctx.project.id, ctx.sheet.id)

    request = %{attrs() | mention_user_ids: [recipient.id]}
    assert {:ok, detail} = create_sheet_comment(ctx, request)
    sheet_id = ctx.sheet.id
    block_id = ctx.block.id
    assert_receive {:sheet_comments_changed, ^sheet_id}

    assert {:ok, repeated} = create_sheet_comment(ctx, request)
    assert repeated.thread.id == detail.thread.id
    refute_receive {:sheet_comments_changed, _}
    assert Repo.aggregate(Thread, :count) == 1
    assert Repo.aggregate(Message, :count) == 1

    assert detail.thread.position == %{x: 25.5, y: 75.0}

    assert detail.thread.source == %{
             type: "sheet_block",
             id: block_id,
             sheet_id: sheet_id,
             label: "Motivation",
             status: "available"
           }

    stored = Repo.get!(Thread, detail.thread.id)
    assert stored.sheet_block_id == block_id
    assert stored.flow_node_id == nil
    assert stored.flow_canvas_id == nil
    assert stored.scene_canvas_id == nil
    assert stored.container_id == sheet_id
    assert stored.source_inserted_at == ctx.block.inserted_at

    message = hd(detail.messages)
    thread_id = detail.thread.id

    assert {:ok, %{surface: "sheet", sheet_id: ^sheet_id, block_id: ^block_id, thread_id: ^thread_id}} =
             Projects.comment_destination(recipient_scope, ctx.project.id, message.id)

    key = {ctx.project.id, message.id}

    assert %{
             ^key => %{
               surface: "sheet",
               sheet_id: ^sheet_id,
               block_id: ^block_id,
               thread_id: ^thread_id,
               project_slug: project_slug,
               workspace_slug: workspace_slug
             }
           } = Projects.comment_destinations(recipient_scope, [message.id])

    assert project_slug == ctx.project.slug
    assert workspace_slug == ctx.workspace.slug
    assert Enum.any?(Platform.list_notifications(recipient_scope), &(&1.entity_id == message.id))

    assert {:ok, %{threads: [listed], next_cursor: nil}} =
             Projects.list_sheet_comment_threads(ctx.scope, ctx.project.id, sheet_id)

    assert listed.id == thread_id

    assert {:ok, %{threads: [filtered]}} =
             Projects.list_sheet_comment_threads(ctx.scope, ctx.project.id, sheet_id, block_id: block_id)

    assert filtered.id == thread_id

    assert {:ok, %{threads: []}} =
             Projects.list_sheet_comment_threads(ctx.scope, ctx.project.id, sheet_id, block_id: block_id + 1)

    assert {:ok, [pin]} = Projects.list_sheet_comment_pins(ctx.scope, ctx.project.id, sheet_id)
    assert pin.id == thread_id
    assert :ok = Projects.unsubscribe_sheet_comments(ctx.project.id, sheet_id)
  end

  test "uses a stable fallback label when historical block config has no label" do
    assert DTO.source_label(%SheetBlockRecord{id: 42, type: "rich_text", config: nil}) == "Rich_text #42"

    assert DTO.source_label(%SheetBlockRecord{id: 43, type: "text", config: %{"label" => " <b> </b> "}}) ==
             "Text #43"
  end

  test "requires normalized positions and moves only within the original block", ctx do
    for position <- [
          nil,
          [],
          %{},
          %{x: 1},
          %{x: "1", y: 2},
          %{x: -0.1, y: 50},
          %{x: 50, y: 100.1},
          %{x: :infinity, y: 50}
        ] do
      assert {:error, :invalid_position} = create_sheet_comment(ctx, %{attrs() | position: position})
    end

    assert Repo.aggregate(Thread, :count) == 0
    assert {:ok, detail} = create_sheet_comment(ctx, %{attrs() | position: %{x: 0, y: 100}})
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
               %{x: 80, y: 20},
               detail.thread.revision
             )

    assert moved.position == %{x: 80.0, y: 20.0}
    assert moved.source == original_source
    assert moved.revision == detail.thread.revision + 1
    assert_receive {:sheet_comments_changed, sheet_id} when sheet_id == ctx.sheet.id

    stored = Repo.get!(Thread, detail.thread.id)
    assert stored.sheet_block_id == ctx.block.id
    assert stored.source_id == ctx.block.id
    assert stored.container_id == ctx.sheet.id
    assert :ok = Projects.unsubscribe_sheet_comments(ctx.project.id, ctx.sheet.id)
  end

  test "accepts inherited local instances and rejects blocks outside the Sheet", ctx do
    other_sheet = sheet_fixture(ctx.project)
    other_block = block_fixture(other_sheet)

    assert {:error, :source_unavailable} =
             Projects.create_sheet_block_comment(
               ctx.scope,
               ctx.project.id,
               ctx.sheet.id,
               other_block.id,
               attrs()
             )

    child = child_sheet_fixture(ctx.project, ctx.sheet)
    source = inheritable_block_fixture(ctx.sheet, label: "Inherited field")
    local_instance = Enum.find(Sheets.list_blocks(child.id), &(&1.inherited_from_block_id == source.id))
    assert local_instance

    assert {:error, :source_unavailable} =
             Projects.create_sheet_block_comment(ctx.scope, ctx.project.id, child.id, source.id, attrs())

    assert {:ok, detail} =
             Projects.create_sheet_block_comment(ctx.scope, ctx.project.id, child.id, local_instance.id, attrs())

    assert detail.thread.source.id == local_instance.id
    assert detail.thread.source.sheet_id == child.id
    assert detail.thread.source.label == "Inherited field"

    other_project = project_fixture()
    foreign_sheet = sheet_fixture(other_project)
    foreign_block = block_fixture(foreign_sheet)

    assert {:error, :source_unavailable} =
             Projects.create_sheet_block_comment(
               ctx.scope,
               ctx.project.id,
               ctx.sheet.id,
               foreign_block.id,
               attrs()
             )
  end

  test "soft deletion hides a block anchor, restore revives it and hard deletion preserves history", ctx do
    assert {:ok, detail} = create_sheet_comment(ctx)
    root_message_id = detail.thread.root_message_id
    assert {:ok, deleted_block} = Sheets.delete_block(ctx.block)

    assert {:ok, unavailable} = Projects.get_comment_thread(ctx.scope, ctx.project.id, detail.thread.id)
    assert unavailable.thread.source.status == "unavailable"
    assert unavailable.thread.source.label == "Motivation"
    assert {:ok, []} = Projects.list_sheet_comment_pins(ctx.scope, ctx.project.id, ctx.sheet.id)
    assert Projects.comment_destinations(ctx.scope, [root_message_id]) == %{}

    assert {:error, :source_unavailable} =
             Projects.move_comment_thread(
               ctx.scope,
               ctx.project.id,
               detail.thread.id,
               %{x: 30, y: 30},
               detail.thread.revision
             )

    assert {:ok, restored_block} = Sheets.restore_block(deleted_block)
    assert {:ok, [pin]} = Projects.list_sheet_comment_pins(ctx.scope, ctx.project.id, ctx.sheet.id)
    assert pin.id == detail.thread.id
    assert pin.source.status == "available"

    messages = Repo.all(Message)
    assert {:ok, _deleted} = Sheets.permanently_delete_block(restored_block)
    stored = Repo.get!(Thread, detail.thread.id)
    assert stored.sheet_block_id == nil
    assert stored.source_id == ctx.block.id
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
               | client_request_id: Ecto.UUID.generate()
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
    assert listed_sheet.source.type == "sheet_block"

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

  defp attrs do
    %{
      body: "Review this field",
      position: %{x: 25.5, y: 75},
      client_request_id: Ecto.UUID.generate(),
      mention_user_ids: []
    }
  end

  defp create_sheet_comment(ctx, request \\ attrs()) do
    Projects.create_sheet_block_comment(ctx.scope, ctx.project.id, ctx.sheet.id, ctx.block.id, request)
  end
end
