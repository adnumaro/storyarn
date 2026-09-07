defmodule Storyarn.Ideation.CanvasModeTest do
  use Storyarn.DataCase, async: true

  import Storyarn.IdeationFixtures

  alias Storyarn.Ideation
  alias Storyarn.Ideation.Ideas.Idea
  alias Storyarn.Ideation.Ideas.Revision
  alias Storyarn.Repo

  setup do: ideation_fixture()

  test "the facilitator controls private mode for all authors and ends it with one atomic reveal", ctx do
    attrs = idea_attrs(%{visibility: :private})
    assert {:ok, first} = Ideation.create_canvas_idea(ctx.author, ctx.project.id, ctx.session.id, attrs)
    assert first.visibility == :shared
    assert {:ok, _} = Ideation.get_idea(ctx.peer, ctx.project.id, ctx.session.id, first.id)
    assert {:error, :unauthorized} = Ideation.set_private_mode(ctx.peer, ctx.project.id, ctx.session.id, 1, true)
    assert {:ok, _} = Ideation.set_private_mode(ctx.facilitator, ctx.project.id, ctx.session.id, 1, true)
    assert {:error, :not_found} = Ideation.get_idea(ctx.peer, ctx.project.id, ctx.session.id, first.id)

    assert {:ok, second} =
             Ideation.create_canvas_idea(ctx.peer, ctx.project.id, ctx.session.id, idea_attrs(%{visibility: :shared}))

    assert second.visibility == :private
    assert {:error, :not_found} = Ideation.get_idea(ctx.facilitator, ctx.project.id, ctx.session.id, second.id)

    assert {:error, :session_private} =
             Ideation.prepare_idea_reveal(ctx.peer, ctx.project.id, ctx.session.id, Ecto.UUID.generate(), [
               %{idea_id: second.id, revision: 1}
             ])

    assert {:ok, edited} =
             Ideation.update_canvas_idea(
               ctx.author,
               ctx.project.id,
               ctx.session.id,
               first.id,
               1,
               edit_attrs(%{body: "<p>Private revision</p>"})
             )

    assert edited.revision == 2
    assert {:ok, _} = Ideation.set_private_mode(ctx.facilitator, ctx.project.id, ctx.session.id, 2, false)

    assert {:ok, %{body: "<p>Private revision</p>", revision: 2}} =
             Ideation.get_idea(ctx.peer, ctx.project.id, ctx.session.id, first.id)

    assert {:ok, _} = Ideation.get_idea(ctx.author, ctx.project.id, ctx.session.id, second.id)

    assert {:ok, _} =
             Ideation.update_canvas_idea(
               ctx.peer,
               ctx.project.id,
               ctx.session.id,
               second.id,
               1,
               edit_attrs(%{body: "<p>Visible without a share button</p>"})
             )

    assert {:ok, %{body: "<p>Visible without a share button</p>"}} =
             Ideation.get_idea(ctx.author, ctx.project.id, ctx.session.id, second.id)

    assert {:ok, _} = Repo.transact(fn -> Ideation.capture_recovery(ctx.project.id) end)
  end

  test "delete is distinct from discard and keeps its history only for recovery", ctx do
    idea = idea_fixture(ctx, %{visibility: :shared})

    assert {:error, :invalid_parameters} =
             Ideation.delete_idea(ctx.author, ctx.project.id, ctx.session.id, 9_223_372_036_854_775_808, 1)

    assert {:error, :not_found} = Ideation.delete_idea(ctx.peer, ctx.project.id, ctx.session.id, idea.id, 1)
    assert {:error, :unauthorized} = Ideation.delete_idea(ctx.viewer, ctx.project.id, ctx.session.id, idea.id, 1)
    assert {:error, :stale_revision} = Ideation.delete_idea(ctx.author, ctx.project.id, ctx.session.id, idea.id, 2)
    assert {:ok, deleted} = Ideation.delete_idea(ctx.author, ctx.project.id, ctx.session.id, idea.id, 1)
    assert {:ok, ^deleted} = Ideation.delete_idea(ctx.author, ctx.project.id, ctx.session.id, idea.id, 1)
    assert Repo.get!(Idea, idea.id).state == :active
    assert Repo.get!(Idea, idea.id).deleted_at
    assert Repo.get_by!(Revision, idea_id: idea.id, number: 1).body == idea.body

    for actor <- [ctx.author, ctx.peer, ctx.facilitator] do
      assert {:error, :not_found} = Ideation.get_idea(actor, ctx.project.id, ctx.session.id, idea.id)
      assert {:ok, []} = Ideation.list_ideas(actor, ctx.project.id, ctx.session.id, state: :all)
      assert {:ok, %{active: 0, parked: 0, discarded: 0}} = Ideation.count_ideas(actor, ctx.project.id, ctx.session.id)
    end

    assert {:error, :not_found} =
             Ideation.update_canvas_idea(
               ctx.author,
               ctx.project.id,
               ctx.session.id,
               idea.id,
               1,
               edit_attrs(%{body: "<p>Deleted</p>"})
             )

    assert {:ok, _} = Repo.transact(fn -> Ideation.capture_recovery(ctx.project.id) end)
    discarded = idea_fixture(ctx, %{state: :discarded})
    assert {:ok, [%{id: id}]} = Ideation.list_ideas(ctx.author, ctx.project.id, ctx.session.id, state: :discarded)
    assert id == discarded.id
  end

  test "reveal excludes deleted notes, and archive and stale revisions block mode changes", ctx do
    assert {:ok, _} = Ideation.set_private_mode(ctx.facilitator, ctx.project.id, ctx.session.id, 1, true)
    assert {:ok, idea} = Ideation.create_canvas_idea(ctx.author, ctx.project.id, ctx.session.id, idea_attrs())
    assert {:ok, _} = Ideation.delete_idea(ctx.author, ctx.project.id, ctx.session.id, idea.id, 1)

    assert {:error, :stale_revision} =
             Ideation.set_private_mode(ctx.facilitator, ctx.project.id, ctx.session.id, 1, false)

    assert {:ok, _} = Ideation.set_private_mode(ctx.facilitator, ctx.project.id, ctx.session.id, 2, false)
    assert is_nil(Repo.get!(Idea, idea.id).published_revision)
    assert {:ok, _} = Ideation.archive_session(ctx.facilitator, ctx.project.id, ctx.session.id, 3)

    assert {:error, :session_archived} =
             Ideation.set_private_mode(ctx.facilitator, ctx.project.id, ctx.session.id, 4, true)
  end
end
