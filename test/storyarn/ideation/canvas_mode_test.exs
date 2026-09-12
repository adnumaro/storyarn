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

  test "deleting a never-published note only invalidates its author's subscription", ctx do
    note = idea_fixture(ctx)
    assert :ok = Ideation.subscribe_ideas(ctx.peer, ctx.project.id, ctx.session.id)
    assert {:ok, _} = Ideation.delete_idea(ctx.author, ctx.project.id, ctx.session.id, note.id, 1)
    refute_receive {:ideation_changed, _}
    Ideation.unsubscribe_ideas(ctx.peer, ctx.project.id, ctx.session.id)

    other = idea_fixture(ctx)
    assert :ok = Ideation.subscribe_ideas(ctx.author, ctx.project.id, ctx.session.id)
    assert {:ok, _} = Ideation.delete_idea(ctx.author, ctx.project.id, ctx.session.id, other.id, 1)
    assert_receive {:ideation_changed, _}
    refute_receive {:ideation_changed, _}
  end

  test "ending private mode excludes discarded heads and legacy author-only drafts", ctx do
    legacy = idea_fixture(ctx)
    {:ok, published} = Ideation.create_canvas_idea(ctx.author, ctx.project.id, ctx.session.id, idea_attrs())
    assert {:ok, _} = Ideation.set_private_mode(ctx.facilitator, ctx.project.id, ctx.session.id, 1, true)

    assert {:ok, _} =
             Ideation.update_canvas_idea(
               ctx.author,
               ctx.project.id,
               ctx.session.id,
               published.id,
               1,
               edit_attrs(%{state: :discarded, body: "<p>Discarded private rewrite</p>"})
             )

    notes =
      for state <- [:active, :parked, :discarded], into: %{} do
        {:ok, note} =
          Ideation.create_canvas_idea(ctx.author, ctx.project.id, ctx.session.id, idea_attrs(%{state: state}))

        {state, note}
      end

    assert {:ok, _} = Ideation.set_private_mode(ctx.facilitator, ctx.project.id, ctx.session.id, 2, false)
    assert {:ok, prior_publication} = Ideation.get_idea(ctx.peer, ctx.project.id, ctx.session.id, published.id)
    assert prior_publication.body == published.body
    assert prior_publication.revision == 1

    for note <- [notes.active, notes.parked] do
      assert {:ok, %{published_revision: 1}} = Ideation.get_idea(ctx.peer, ctx.project.id, ctx.session.id, note.id)
    end

    for note <- [notes.discarded, legacy] do
      assert {:error, :not_found} = Ideation.get_idea(ctx.peer, ctx.project.id, ctx.session.id, note.id)
      assert {:ok, %{published_revision: nil}} = Ideation.get_idea(ctx.author, ctx.project.id, ctx.session.id, note.id)
    end

    assert {:ok, selection} =
             Ideation.prepare_idea_reveal(ctx.facilitator, ctx.project.id, ctx.session.id, Ecto.UUID.generate(), [
               %{idea_id: notes.discarded.id, revision: 1}
             ])

    assert {:ok, _} = Ideation.reveal_ideas(ctx.facilitator, ctx.project.id, ctx.session.id, selection.id)
    assert {:ok, _} = Ideation.get_idea(ctx.peer, ctx.project.id, ctx.session.id, notes.discarded.id)
    assert {:error, :not_found} = Ideation.get_idea(ctx.peer, ctx.project.id, ctx.session.id, legacy.id)
  end

  test "archiving private work restores prior publications without publishing drafts", ctx do
    {:ok, published} = Ideation.create_canvas_idea(ctx.author, ctx.project.id, ctx.session.id, idea_attrs())
    legacy = idea_fixture(ctx)
    assert {:ok, _} = Ideation.set_private_mode(ctx.facilitator, ctx.project.id, ctx.session.id, 1, true)

    assert {:ok, _} =
             Ideation.update_canvas_idea(
               ctx.author,
               ctx.project.id,
               ctx.session.id,
               published.id,
               1,
               edit_attrs(%{body: "<p>Unpublished private rewrite</p>", state: :discarded})
             )

    {:ok, private} = Ideation.create_canvas_idea(ctx.author, ctx.project.id, ctx.session.id, idea_attrs())

    {:ok, discarded} =
      Ideation.create_canvas_idea(ctx.author, ctx.project.id, ctx.session.id, idea_attrs(%{state: :discarded}))

    assert {:error, :stale_revision} = Ideation.archive_session(ctx.facilitator, ctx.project.id, ctx.session.id, 1)
    assert {:error, :not_found} = Ideation.get_idea(ctx.peer, ctx.project.id, ctx.session.id, published.id)

    assert {:ok, archived} = Ideation.archive_session(ctx.facilitator, ctx.project.id, ctx.session.id, 2)
    refute archived.configuration.private_mode
    assert archived.configuration_version == 3

    assert {:ok, visible} = Ideation.get_idea(ctx.peer, ctx.project.id, ctx.session.id, published.id)
    assert visible.body == published.body
    assert visible.revision == 1

    for note <- [private, discarded, legacy] do
      assert {:error, :not_found} = Ideation.get_idea(ctx.peer, ctx.project.id, ctx.session.id, note.id)
      assert {:ok, %{published_revision: nil}} = Ideation.get_idea(ctx.author, ctx.project.id, ctx.session.id, note.id)
    end

    assert {:ok, reopened} = Ideation.reopen_session(ctx.facilitator, ctx.project.id, ctx.session.id, archived.revision)
    refute reopened.configuration.private_mode
    assert {:ok, _} = Ideation.archive_session(ctx.facilitator, ctx.project.id, ctx.session.id, reopened.revision)

    for note <- [private, discarded, legacy] do
      assert {:error, :not_found} = Ideation.get_idea(ctx.peer, ctx.project.id, ctx.session.id, note.id)
    end
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
