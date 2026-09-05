defmodule Storyarn.Repo.Migrations.SheetCommentAnchorsMigrationTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Flows
  alias Storyarn.Projects
  alias Storyarn.Projects.Comments.Message
  alias Storyarn.Projects.Comments.Thread
  alias Storyarn.Repo.Migrations.AddSheetCommentAnchors
  alias Storyarn.Sheets

  if !Code.ensure_loaded?(AddSheetCommentAnchors) do
    Code.require_file(
      Path.expand("../../../../priv/repo/migrations/20260905100000_add_sheet_comment_anchors.exs", __DIR__)
    )
  end

  setup do
    owner = user_fixture()
    scope = user_scope_fixture(owner)
    project = project_fixture(owner)
    sheet = sheet_fixture(project)
    block = block_fixture(sheet)

    {:ok, detail} =
      Projects.create_sheet_block_comment(scope, project.id, sheet.id, block.id, attrs())

    %{
      project: project,
      sheet: sheet,
      block: block,
      thread: Repo.get!(Thread, detail.thread.id)
    }
  end

  test "Sheet anchors cannot point to another existing block", ctx do
    other_block = block_fixture(ctx.sheet)

    assert_constraint_violation(
      "UPDATE comment_threads SET sheet_block_id = $1 WHERE id = $2",
      [other_block.id, ctx.thread.id],
      "comment_threads_anchor_identity"
    )

    assert Repo.get!(Thread, ctx.thread.id) == ctx.thread
    assert Repo.aggregate(Message, :count) == 1
  end

  test "Sheet anchors cannot acquire another source pointer or an out-of-range position", ctx do
    {:ok, flow} = Flows.create_flow(ctx.project, %{name: "Other source"})

    assert_constraint_violation(
      "UPDATE comment_threads SET flow_canvas_id = $1 WHERE id = $2",
      [flow.id, ctx.thread.id],
      "comment_threads_anchor_shape"
    )

    assert_constraint_violation(
      "UPDATE comment_threads SET position_y = -0.01 WHERE id = $1",
      [ctx.thread.id],
      "comment_threads_position"
    )

    assert Repo.get!(Thread, ctx.thread.id) == ctx.thread
    assert Repo.aggregate(Message, :count) == 1
  end

  test "hard deletion nulls only the block pointer and preserves immutable context and messages", ctx do
    messages = Repo.all(from message in Message, order_by: message.id)
    assert {:ok, _deleted_block} = Sheets.permanently_delete_block(ctx.block)

    assert Repo.get!(Thread, ctx.thread.id) == %{ctx.thread | sheet_block_id: nil}
    assert Repo.all(from message in Message, order_by: message.id) == messages
  end

  test "Sheet anchor rollback fails before removing discussion metadata", ctx do
    messages = Repo.all(from message in Message, order_by: message.id)

    assert_raise Ecto.MigrationError, ~r/irreversible.*Preserve comment threads and their history/, fn ->
      AddSheetCommentAnchors.down()
    end

    assert Repo.get!(Thread, ctx.thread.id) == ctx.thread
    assert Repo.all(from message in Message, order_by: message.id) == messages
  end

  defp attrs do
    %{
      body: "Keep this Sheet discussion",
      position: %{x: 10, y: 90},
      client_request_id: Ecto.UUID.generate(),
      mention_user_ids: []
    }
  end

  defp assert_constraint_violation(sql, params, constraint) do
    assert {:error, %Postgrex.Error{postgres: %{code: :check_violation, constraint: ^constraint}}} =
             Repo.query(sql, params, mode: :savepoint)
  end
end
