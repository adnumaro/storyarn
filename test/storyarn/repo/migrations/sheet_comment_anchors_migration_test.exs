defmodule Storyarn.Repo.Migrations.SheetCommentAnchorsMigrationTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Projects
  alias Storyarn.Projects.Comments.Message
  alias Storyarn.Projects.Comments.Thread
  alias Storyarn.Repo.Migrations.ConvertSheetCommentsToCanvas
  alias Storyarn.Sheets

  if !Code.ensure_loaded?(ConvertSheetCommentsToCanvas) do
    Code.require_file(
      Path.expand("../../../../priv/repo/migrations/20260905120000_convert_sheet_comments_to_canvas.exs", __DIR__)
    )
  end

  setup do
    owner = user_fixture()
    scope = user_scope_fixture(owner)
    project = project_fixture(owner)
    sheet = sheet_fixture(project)

    {:ok, detail} = Projects.create_sheet_canvas_comment(scope, project.id, sheet.id, attrs())

    %{
      project: project,
      sheet: sheet,
      thread: Repo.get!(Thread, detail.thread.id)
    }
  end

  test "Sheet canvas anchors cannot point to another existing Sheet", ctx do
    other_sheet = sheet_fixture(ctx.project)

    assert_constraint_violation(
      "UPDATE comment_threads SET sheet_canvas_id = $1 WHERE id = $2",
      [other_sheet.id, ctx.thread.id],
      "comment_threads_anchor_identity"
    )

    assert Repo.get!(Thread, ctx.thread.id) == ctx.thread
    assert Repo.aggregate(Message, :count) == 1
  end

  test "Sheet canvas anchors cannot acquire another source pointer or an invalid position", ctx do
    flow = flow_fixture(ctx.project)

    assert_constraint_violation(
      "UPDATE comment_threads SET flow_canvas_id = $1 WHERE id = $2",
      [flow.id, ctx.thread.id],
      "comment_threads_anchor_shape"
    )

    assert_constraint_violation(
      "UPDATE comment_threads SET position_x = $1 WHERE id = $2",
      [100.01, ctx.thread.id],
      "comment_threads_position"
    )

    assert_constraint_violation(
      "UPDATE comment_threads SET position_y = $1 WHERE id = $2",
      [-0.01, ctx.thread.id],
      "comment_threads_position"
    )

    assert_constraint_violation(
      "UPDATE comment_threads SET position_y = $1 WHERE id = $2",
      [10_000_000.01, ctx.thread.id],
      "comment_threads_position"
    )

    assert Repo.get!(Thread, ctx.thread.id) == ctx.thread
    assert Repo.aggregate(Message, :count) == 1
  end

  test "hard deletion nulls only the Sheet pointer and preserves immutable context and messages", ctx do
    messages = Repo.all(from message in Message, order_by: message.id)
    assert {:ok, _deleted_sheet} = Sheets.permanently_delete_sheet(ctx.sheet)

    assert Repo.get!(Thread, ctx.thread.id) == %{ctx.thread | sheet_canvas_id: nil}
    assert Repo.all(from message in Message, order_by: message.id) == messages
  end

  test "Sheet canvas conversion rollback fails before removing discussion metadata", ctx do
    messages = Repo.all(from message in Message, order_by: message.id)

    assert_raise Ecto.MigrationError, ~r/irreversible.*Preserve comment threads and their history/, fn ->
      ConvertSheetCommentsToCanvas.down()
    end

    assert Repo.get!(Thread, ctx.thread.id) == ctx.thread
    assert Repo.all(from message in Message, order_by: message.id) == messages
  end

  test "the final schema keeps only the Sheet canvas pointer" do
    assert %{rows: [[true, false]]} =
             Repo.query!("""
             SELECT
               EXISTS (
                 SELECT 1 FROM information_schema.columns
                 WHERE table_schema = current_schema()
                   AND table_name = 'comment_threads'
                   AND column_name = 'sheet_canvas_id'
               ),
               EXISTS (
                 SELECT 1 FROM information_schema.columns
                 WHERE table_schema = current_schema()
                   AND table_name = 'comment_threads'
                   AND column_name = 'sheet_block_id'
               )
             """)
  end

  defp attrs do
    %{
      body: "Keep this Sheet discussion",
      position: %{x: 10, y: 900},
      client_request_id: Ecto.UUID.generate(),
      mention_user_ids: []
    }
  end

  defp assert_constraint_violation(sql, params, constraint) do
    assert {:error, %Postgrex.Error{postgres: %{code: :check_violation, constraint: ^constraint}}} =
             Repo.query(sql, params, mode: :savepoint)
  end
end
