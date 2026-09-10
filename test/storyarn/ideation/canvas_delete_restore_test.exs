defmodule Storyarn.Ideation.CanvasDeleteRestoreTest do
  use Storyarn.DataCase, async: true

  import Storyarn.IdeationFixtures

  alias Storyarn.Ideation
  alias Storyarn.Ideation.Ideas.Idea
  alias Storyarn.Ideation.Ideas.Revision
  alias Storyarn.Projects

  setup do: ideation_fixture()

  test "undo restores the authored note, state and placement and preserves recovery", ctx do
    attrs = idea_attrs(%{state: :parked, canvas: %{"x" => 20, "y" => 40, "width" => 280, "color" => "mint"}})
    {:ok, note} = Ideation.create_canvas_idea(ctx.author, ctx.project.id, ctx.session.id, attrs)
    {:ok, deleted} = Ideation.delete_idea(ctx.author, ctx.project.id, ctx.session.id, note.id, note.revision)
    assert deleted.revision == note.revision
    assert {:error, :not_found} = Ideation.get_idea(ctx.author, ctx.project.id, ctx.session.id, note.id)

    assert {:ok, restored} = restore(ctx, deleted)
    assert restored.id == note.id
    assert restored.author_id == note.author_id
    assert restored.body == note.body
    assert restored.state == :parked
    assert restored.canvas == note.canvas
    assert restored.revision == note.revision + 1
    assert restored.deleted_at == nil
    assert {:ok, %{revision: 2}} = Ideation.get_idea(ctx.peer, ctx.project.id, ctx.session.id, note.id)
    assert {:ok, ^restored} = restore(ctx, deleted)
    assert Repo.aggregate(from(r in Revision, where: r.idea_id == ^note.id), :count) == 2
    assert {:ok, _} = Repo.transact(fn -> Ideation.capture_recovery(ctx.project.id) end)
  end

  test "an old undo or delete cannot change a later edit or deletion cycle", ctx do
    note = idea_fixture(ctx)
    {:ok, first_delete} = Ideation.delete_idea(ctx.author, ctx.project.id, ctx.session.id, note.id, 1)
    {:ok, restored} = restore(ctx, first_delete)
    assert {:error, :stale_revision} = Ideation.delete_idea(ctx.author, ctx.project.id, ctx.session.id, note.id, 1)
    {:ok, second_delete} = Ideation.delete_idea(ctx.author, ctx.project.id, ctx.session.id, note.id, restored.revision)

    assert {:error, :stale_revision} = restore(ctx, first_delete)
    assert Repo.get!(Idea, note.id).deleted_at == second_delete.deleted_at

    assert {:error, :stale_deletion} =
             restore(ctx, %{second_delete | deleted_at: DateTime.shift(second_delete.deleted_at, second: 1)})

    {:ok, second_restore} = restore(ctx, second_delete)

    {:ok, edited} =
      Ideation.update_canvas_idea(
        ctx.author,
        ctx.project.id,
        ctx.session.id,
        note.id,
        second_restore.revision,
        edit_attrs(%{body: "Later work"})
      )

    assert {:error, :stale_revision} = restore(ctx, second_delete)
    assert {:ok, ^edited} = Ideation.get_idea(ctx.author, ctx.project.id, ctx.session.id, note.id)
  end

  test "undo requires the current author's edit access and the exact session", ctx do
    note = idea_fixture(ctx)
    {:ok, deleted} = Ideation.delete_idea(ctx.author, ctx.project.id, ctx.session.id, note.id, 1)

    for actor <- [ctx.peer, ctx.facilitator, ctx.owner] do
      assert {:error, :not_found} = restore(%{ctx | author: actor}, deleted)
    end

    assert {:error, :unauthorized} = restore(%{ctx | author: ctx.viewer}, deleted)
    {:ok, other} = Ideation.create_session(ctx.author, ctx.project.id, %{title: "Other"})
    assert {:error, :not_found} = restore(%{ctx | session: other}, deleted)

    membership = Projects.get_membership(ctx.project.id, ctx.author.user.id)
    {:ok, _} = Projects.update_member_role(ctx.owner, ctx.project.id, membership.id, "viewer")
    assert {:error, :unauthorized} = restore(ctx, deleted)
    assert Repo.get!(Idea, note.id).deleted_at == deleted.deleted_at
  end

  test "undo respects current private mode and archived sessions", ctx do
    {:ok, _} = Ideation.set_private_mode(ctx.facilitator, ctx.project.id, ctx.session.id, 1, true)
    {:ok, note} = Ideation.create_canvas_idea(ctx.author, ctx.project.id, ctx.session.id, idea_attrs())
    {:ok, deleted} = Ideation.delete_idea(ctx.author, ctx.project.id, ctx.session.id, note.id, 1)
    {:ok, restored} = restore(ctx, deleted)
    assert restored.visibility == :private
    assert {:error, :not_found} = Ideation.get_idea(ctx.peer, ctx.project.id, ctx.session.id, note.id)
    {:ok, deleted} = Ideation.delete_idea(ctx.author, ctx.project.id, ctx.session.id, note.id, restored.revision)
    {:ok, _} = Ideation.archive_session(ctx.facilitator, ctx.project.id, ctx.session.id, 2)
    assert {:error, :session_archived} = restore(ctx, deleted)
  end

  test "malformed undo markers and identities are typed failures", ctx do
    note = idea_fixture(ctx)
    {:ok, deleted} = Ideation.delete_idea(ctx.author, ctx.project.id, ctx.session.id, note.id, 1)

    for marker <- [nil, "", "not a timestamp", %{}, 1] do
      assert {:error, :invalid_parameters} = restore(ctx, %{deleted | deleted_at: marker})
    end

    for id <- [0, -1, nil, 9_223_372_036_854_775_808] do
      assert {:error, :invalid_parameters} = restore(ctx, %{deleted | id: id})
    end

    assert {:ok, _} = restore(ctx, %{deleted | deleted_at: DateTime.to_iso8601(deleted.deleted_at)})
  end

  defp restore(ctx, deleted) do
    Ideation.restore_idea(ctx.author, ctx.project.id, ctx.session.id, deleted.id, deleted.revision, deleted.deleted_at)
  end
end
