defmodule Storyarn.Projects.ContextualCommentsTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Flows
  alias Storyarn.Projects
  alias Storyarn.Projects.Comments.Context
  alias Storyarn.Projects.Comments.Thread
  alias Storyarn.Projects.Persistence.SheetRecord
  alias Storyarn.Sheets

  setup do
    owner = user_fixture()
    project = project_fixture(owner)
    sheet = sheet_fixture(project, %{name: "Character"})
    %{owner: owner, scope: user_scope_fixture(owner), project: project, sheet: sheet}
  end

  test "fixed Sheet references keep ownership on the whole Sheet and ignore client labels", ctx do
    for type <- ~w(sheet_cover sheet_header sheet_title) do
      context = %{"type" => type, "id" => ctx.sheet.id, "label" => "Forged context", "status" => "unavailable"}
      assert {:ok, detail} = create_sheet(ctx, context)
      assert detail.thread.source.type == "sheet_canvas"
      assert detail.thread.source.id == ctx.sheet.id
      assert detail.thread.context.type == type
      assert detail.thread.context.id == to_string(ctx.sheet.id)
      assert detail.thread.context.status == "available"
      refute detail.thread.context.label == "Forged context"
      assert detail.thread.position == %{x: 40.0, y: 600.0}
    end
  end

  test "moving can preserve, replace, or remove context without replacing the conversation", ctx do
    block = block_fixture(ctx.sheet, %{config: %{"label" => "Motivation"}})
    assert {:ok, detail} = create_sheet(ctx, %{type: :sheet_block, id: block.id})
    assert detail.thread.context.label == "Motivation"

    assert {:ok, moved} = move(ctx, detail.thread, %{x: 80, y: 950})
    assert moved.context.id == to_string(block.id)

    assert {:ok, title} =
             move(ctx, moved, %{x: 12, y: 250}, context: %{type: "sheet_title", id: to_string(ctx.sheet.id)})

    assert title.context.type == "sheet_title"
    assert {:ok, detached} = move(ctx, title, %{x: 97, y: 1300}, context: nil)
    assert detached.context == nil
    assert detached.position == %{x: 97.0, y: 1300.0}
    assert detached.id == detail.thread.id

    assert {:ok, retained} = Projects.get_comment_thread(ctx.scope, ctx.project.id, detached.id)
    assert retained.messages == detail.messages
    assert retained.thread.source == detail.thread.source
  end

  test "fixed Sheet parts cannot bind to a reconstructed Sheet with the same identity", ctx do
    assert {:ok, detail} = create_sheet(ctx, %{type: "sheet_title", id: ctx.sheet.id})
    original = Repo.get!(SheetRecord, ctx.sheet.id)
    Repo.delete!(original)

    Repo.insert!(%SheetRecord{
      id: original.id,
      project_id: original.project_id,
      name: original.name,
      shortcut: original.shortcut,
      inserted_at: original.inserted_at,
      updated_at: original.updated_at
    })

    stored = Repo.get!(Thread, detail.thread.id)
    assert stored.sheet_canvas_id == nil
    assert Context.available(stored) == nil
    assert Context.available_many([stored])[stored.id] == nil
    assert {:ok, retained} = Projects.get_comment_thread(ctx.scope, ctx.project.id, detail.thread.id)
    assert retained.thread.source.status == "unavailable"
    assert retained.thread.context.status == "unavailable"
  end

  test "stale context changes cannot partially move or reassociate the pin", ctx do
    assert {:ok, detail} = create_sheet(ctx, %{type: "sheet_header", id: ctx.sheet.id})
    assert {:ok, moved} = move(ctx, detail.thread, %{x: 60, y: 700})

    assert {:error, :stale} = move(ctx, detail.thread, %{x: 20, y: 900}, context: nil)
    assert {:ok, retained} = Projects.get_comment_thread(ctx.scope, ctx.project.id, moved.id)
    assert retained.thread.position == moved.position
    assert retained.thread.context == moved.context
    assert retained.thread.revision == moved.revision
  end

  test "context must belong to the exact surface, even when its project is accessible", ctx do
    other_sheet = sheet_fixture(ctx.project)
    other_block = block_fixture(other_sheet)
    other_project = project_fixture(ctx.owner)
    foreign_sheet = sheet_fixture(other_project)
    foreign_block = block_fixture(foreign_sheet)
    flow = flow_fixture(ctx.project)
    node = node_fixture(flow)

    for context <- [
          %{type: "sheet_header", id: other_sheet.id},
          %{type: "sheet_block", id: other_block.id},
          %{type: "sheet_block", id: foreign_block.id},
          %{type: "flow_node", id: node.id}
        ] do
      assert {:error, :context_unavailable} = create_sheet(ctx, context)
    end

    assert Repo.aggregate(Thread, :count) == 0
  end

  test "an inherited block instance gives context without inheriting the conversation", ctx do
    parent_block = inheritable_block_fixture(ctx.sheet, label: "Inherited field")
    child = child_sheet_fixture(ctx.project, ctx.sheet)
    inherited = Enum.find(Sheets.list_blocks(child.id), &(&1.inherited_from_block_id == parent_block.id))
    assert inherited
    child_ctx = %{ctx | sheet: child}

    assert {:ok, detail} = create_sheet(child_ctx, %{type: "sheet_block", id: inherited.id})
    assert detail.thread.source.id == child.id
    assert detail.thread.context.id == to_string(inherited.id)
    assert {:ok, []} = Projects.list_sheet_comment_pins(ctx.scope, ctx.project.id, ctx.sheet.id)
    assert {:ok, [%{id: thread_id}]} = Projects.list_sheet_comment_pins(ctx.scope, ctx.project.id, child.id)
    assert thread_id == detail.thread.id
    assert {:error, :context_unavailable} = create_sheet(child_ctx, %{type: "sheet_block", id: parent_block.id})
  end

  test "a row of three blocks uses its persistent UUID and resolves as one context", ctx do
    blocks = for _ <- 1..3, do: block_fixture(ctx.sheet)
    assert {:ok, group_id} = Sheets.create_column_group(ctx.sheet.id, Enum.map(blocks, & &1.id))
    assert {:ok, detail} = create_sheet(ctx, %{type: "sheet_column_group", id: group_id})
    assert detail.thread.context.id == group_id
    assert detail.thread.context.type == "sheet_column_group"
    assert detail.thread.context.label == "Row of 3 blocks"
    assert detail.thread.context.status == "available"

    stored = Repo.get!(Thread, detail.thread.id)
    assert stored.context_sheet_column_group_id == group_id
    assert Context.available_many([stored])[stored.id].id == group_id
  end

  test "lost block context leaves the Sheet discussion available for replies and repositioning", ctx do
    block = block_fixture(ctx.sheet, %{config: %{"label" => "Deleted field"}})
    assert {:ok, detail} = create_sheet(ctx, %{type: "sheet_block", id: block.id})
    assert {:ok, _deleted} = Sheets.delete_block(block)

    assert {:ok, retained} = Projects.get_comment_thread(ctx.scope, ctx.project.id, detail.thread.id)
    assert retained.thread.source.status == "available"
    assert retained.thread.context.status == "unavailable"
    assert retained.thread.context.label == "Deleted field"

    assert {:ok, replied} =
             Projects.reply_to_comment_thread(ctx.scope, ctx.project.id, detail.thread.id, %{
               body: "Keep discussing the Sheet",
               parent_id: detail.thread.root_message_id,
               client_request_id: Ecto.UUID.generate()
             })

    assert length(replied.messages) == 2
    assert {:ok, moved} = move(ctx, replied.thread, %{x: 30, y: 500}, context: nil)
    assert moved.context == nil
  end

  test "Flow node creation keeps relative offset while ownership and position use its canvas", ctx do
    flow = flow_fixture(ctx.project)
    node = node_fixture(flow, %{position_x: 400, position_y: 200})

    assert {:ok, detail} =
             Projects.create_flow_node_comment(ctx.scope, ctx.project.id, flow.id, node.id, %{
               body: "Check the dialogue",
               client_request_id: Ecto.UUID.generate(),
               position: %{x: 25, y: -10}
             })

    assert detail.thread.source.type == "flow_canvas"
    assert detail.thread.source.id == flow.id
    assert detail.thread.position == %{x: 425.0, y: 190.0}
    assert detail.thread.context.type == "flow_node"
    assert detail.thread.context.id == to_string(node.id)
    assert detail.thread.context.offset == %{x: 25.0, y: -10.0}

    assert {:ok, moved} = move(ctx, detail.thread, %{x: 450, y: 250})
    assert moved.context.offset == %{x: 50.0, y: 50.0}
    assert {:ok, detached} = move(ctx, moved, %{x: 600, y: 700}, context: nil)
    assert detached.context == nil
    assert {:ok, %{}} = Projects.flow_comment_counts(ctx.scope, ctx.project.id, flow.id)
  end

  test "deleting a moved Flow node retains the pin's final canvas position and conversation", ctx do
    flow = flow_fixture(ctx.project)

    for deletion <- [:soft, :hard] do
      node = node_fixture(flow, %{position_x: 100, position_y: 200})

      assert {:ok, detail} =
               Projects.create_flow_node_comment(ctx.scope, ctx.project.id, flow.id, node.id, %{
                 body: "Keep this discussion here",
                 client_request_id: Ecto.UUID.generate(),
                 position: %{x: 25, y: -10}
               })

      assert {:ok, moved_node} = Flows.update_node_position(node, %{position_x: 800, position_y: 900})

      case deletion do
        :soft ->
          assert {:ok, deleted_node, _meta} = Flows.delete_node(moved_node)
          assert_final_node_position(ctx, detail)
          Repo.delete!(deleted_node)

        :hard ->
          Repo.delete!(moved_node)
      end

      assert_final_node_position(ctx, detail)

      assert {:ok, replied} =
               Projects.reply_to_comment_thread(ctx.scope, ctx.project.id, detail.thread.id, %{
                 body: "We can continue after removing the node",
                 parent_id: detail.thread.root_message_id,
                 client_request_id: Ecto.UUID.generate()
               })

      assert replied.thread.message_count == 2
      assert replied.thread.position == %{x: 825.0, y: 890.0}
    end
  end

  test "Scene context supports pins, zones, connections, and annotations on the owning Scene", ctx do
    scene = scene_fixture(ctx.project)
    pin = pin_fixture(scene, %{"label" => "North gate"})
    second_pin = pin_fixture(scene)
    zone = zone_fixture(scene, %{"name" => "Market"})
    connection = Storyarn.ScenesFixtures.connection_fixture(scene, pin, second_pin, %{"label" => "Road"})
    annotation = annotation_fixture(scene, %{"text" => "Needs lighting"})

    for {type, target, label} <- [
          {"scene_pin", pin, "North gate"},
          {"scene_zone", zone, "Market"},
          {"scene_connection", connection, "Road"},
          {"scene_annotation", annotation, "Needs lighting"}
        ] do
      assert {:ok, detail} =
               Projects.create_scene_canvas_comment(ctx.scope, ctx.project.id, scene.id, %{
                 body: "Review this element",
                 client_request_id: Ecto.UUID.generate(),
                 position: %{x: 40, y: 50},
                 context: %{type: type, id: target.id}
               })

      assert detail.thread.source.id == scene.id
      assert detail.thread.context.type == type
      assert detail.thread.context.id == to_string(target.id)
      assert detail.thread.context.label == label
      assert detail.thread.context.status == "available"
    end

    other_scene = scene_fixture(ctx.project)

    assert {:error, :context_unavailable} =
             Projects.create_scene_canvas_comment(ctx.scope, ctx.project.id, other_scene.id, %{
               body: "Wrong Scene",
               client_request_id: Ecto.UUID.generate(),
               position: %{x: 40, y: 50},
               context: %{type: "scene_pin", id: pin.id}
             })
  end

  test "context identity participates in idempotency and malformed references are rejected", ctx do
    request = attrs(%{type: "sheet_title", id: ctx.sheet.id})
    assert {:ok, original} = Projects.create_sheet_canvas_comment(ctx.scope, ctx.project.id, ctx.sheet.id, request)
    assert {:ok, retry} = Projects.create_sheet_canvas_comment(ctx.scope, ctx.project.id, ctx.sheet.id, request)
    assert retry.thread.id == original.thread.id

    changed = %{request | context: %{type: "sheet_header", id: ctx.sheet.id}}

    assert {:error, :idempotency_conflict} =
             Projects.create_sheet_canvas_comment(ctx.scope, ctx.project.id, ctx.sheet.id, changed)

    for context <- [
          %{},
          %{type: "sheet_block", id: "1oops"},
          %{type: "sheet_block", id: -1},
          %{type: "sheet_column_group", id: 123},
          %{type: "sheet_column_group", id: "invalid-uuid"},
          %{type: "unknown", id: 1},
          %{type: "sheet_title", id: ctx.sheet.id, offset: %{x: 1}},
          %{type: "sheet_title", id: ctx.sheet.id, offset: %{x: 1, y: "2"}}
        ] do
      assert {:error, :invalid_context} = create_sheet(ctx, context)
    end
  end

  test "batch context resolution matches individual resolution after a rename and missing target", ctx do
    block = block_fixture(ctx.sheet, %{config: %{"label" => "Old field"}})
    assert {:ok, block_detail} = create_sheet(ctx, %{type: "sheet_block", id: block.id})
    assert {:ok, title_detail} = create_sheet(ctx, %{type: "sheet_title", id: ctx.sheet.id})
    assert {:ok, _renamed} = Sheets.update_block_config(block, %{"label" => "New field"})
    block_thread = Repo.get!(Thread, block_detail.thread.id)
    title_thread = Repo.get!(Thread, title_detail.thread.id)
    resolved = Context.available_many([block_thread, title_thread])
    assert Context.to_dto(block_thread, resolved[block_thread.id]).label == "New field"
    assert resolved[title_thread.id] == Context.available(title_thread)

    Repo.delete!(block)
    missing = Repo.get!(Thread, block_thread.id)
    assert Context.available_many([missing])[missing.id] == nil
    assert Context.available(missing) == nil
  end

  defp assert_final_node_position(ctx, detail) do
    assert {:ok, retained} = Projects.get_comment_thread(ctx.scope, ctx.project.id, detail.thread.id)
    assert retained.thread.position == %{x: 825.0, y: 890.0}
    assert retained.thread.source.status == "available"
    assert retained.thread.context.status == "unavailable"
    assert retained.thread.revision == detail.thread.revision
    assert retained.messages == detail.messages
  end

  defp create_sheet(ctx, context) do
    Projects.create_sheet_canvas_comment(ctx.scope, ctx.project.id, ctx.sheet.id, attrs(context))
  end

  defp attrs(context) do
    %{
      body: "Review the context",
      client_request_id: Ecto.UUID.generate(),
      position: %{x: 40, y: 600},
      context: context
    }
  end

  defp move(ctx, thread, position, opts \\ []) do
    Projects.move_comment_thread(ctx.scope, ctx.project.id, thread.id, position, thread.revision, opts)
  end
end
