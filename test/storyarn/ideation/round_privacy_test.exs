defmodule Storyarn.Ideation.RoundPrivacyTest do
  use Storyarn.DataCase, async: true

  import Ecto.Query
  import Storyarn.IdeationFixtures

  alias Storyarn.Ideation
  alias Storyarn.Projects

  setup do
    ideation_fixture()
  end

  defp revision(ctx) do
    {:ok, session} = Ideation.get_session(ctx.facilitator, ctx.project.id, ctx.session.id)
    session.revision
  end

  defp canvas_note(ctx, actor, x) do
    {:ok, idea} =
      Ideation.create_canvas_idea(actor, ctx.project.id, ctx.session.id, %{
        request_key: Ecto.UUID.generate(),
        body: "<p>Written on the canvas</p>",
        canvas: %{"x" => x, "y" => 80, "width" => 280, "color" => "mint"}
      })

    idea
  end

  test "placeholders stand only for what the reveal will show: a draft nobody consented to publish has none", ctx do
    draft = idea_fixture(ctx)
    contribution = canvas_note(ctx, ctx.author, 400)
    assert {:ok, _} = set_private_mode(ctx.facilitator, ctx.project.id, ctx.session.id, revision(ctx), true)

    assert {:ok, [placeholder]} = Ideation.list_masked_ideas(ctx.peer, ctx.project.id, ctx.session.id)
    assert placeholder.id == contribution.id
    assert placeholder.canvas == %{"x" => 400, "y" => 80, "width" => 280}
    # Geometry only: no author, state, colour, text or timestamps travel with a mask.
    assert %{id: _, round_id: _, canvas: _} = placeholder
    assert map_size(placeholder) == 3
    refute placeholder.id == draft.id
  end

  test "a group of a private round is hidden with its comment thread, for everyone, until the reveal", ctx do
    first =
      idea_fixture(ctx, %{visibility: :shared, canvas: %{"x" => 20, "y" => 100, "width" => 280, "color" => "mint"}})

    second =
      idea_fixture(ctx, %{visibility: :shared, canvas: %{"x" => 340, "y" => 100, "width" => 280, "color" => "mint"}})

    {:ok, group} =
      Ideation.create_group(ctx.author, ctx.project.id, ctx.session.id, %{
        request_key: Ecto.UUID.generate(),
        title: "Motivations",
        synthesis: "",
        idea_ids: [first.id, second.id],
        canvas: %{x: 0, y: 0, width: 650, height: 450}
      })

    assert {:ok, _} = Ideation.group_comment_source(ctx.peer, ctx.project.id, ctx.session.id, group.id)

    assert {:ok, %{thread: thread}} =
             Projects.create_ideation_comment(ctx.peer, ctx.project.id, ctx.session.id, {:group, group.id}, comment())

    assert {:ok, _} = set_private_mode(ctx.facilitator, ctx.project.id, ctx.session.id, revision(ctx), true)

    for actor <- [ctx.peer, ctx.author, ctx.facilitator] do
      assert {:error, :not_found} = Ideation.group_comment_source(actor, ctx.project.id, ctx.session.id, group.id)
    end

    # Nothing lands on the hidden thread, not even a reply from the peer who
    # opened it: the thread is no parent at all for the time being.
    assert {:error, :not_found} = Projects.get_comment_thread(ctx.peer, ctx.project.id, thread.id)
    assert {:error, :invalid_parent} = Projects.reply_to_comment_thread(ctx.peer, ctx.project.id, thread.id, comment())

    round = first_round(ctx)
    assert {:ok, _} = Ideation.reveal_round(ctx.facilitator, ctx.project.id, ctx.session.id, round.id, revision(ctx))
    assert {:ok, %{id: id}} = Ideation.group_comment_source(ctx.peer, ctx.project.id, ctx.session.id, group.id)
    assert id == group.id
    assert {:ok, _} = Projects.get_comment_thread(ctx.peer, ctx.project.id, thread.id)
    assert Storyarn.Repo.aggregate(from(c in "comment_messages", where: c.thread_id == ^thread.id), :count) == 1
  end

  defp comment, do: %{body: "Discuss this group", client_request_id: Ecto.UUID.generate(), mention_user_ids: []}

  test "when time runs out, every private round that asked to be revealed is, the closed ones too", ctx do
    first = first_round(ctx)

    assert {:ok, _} =
             Ideation.set_round_privacy(ctx.facilitator, ctx.project.id, ctx.session.id, first.id, revision(ctx), %{
               private: true,
               reveal_on_expiry: true
             })

    assert {:ok, _} =
             Ideation.start_timer(ctx.facilitator, ctx.project.id, ctx.session.id, revision(ctx), %{seconds: 60})

    {:ok, timer} = Ideation.get_timer(ctx.facilitator, ctx.project.id, ctx.session.id)

    secret = canvas_note(ctx, ctx.peer, 20)
    assert {:error, :not_found} = Ideation.get_idea(ctx.facilitator, ctx.project.id, ctx.session.id, secret.id)

    {ctx, second} = new_round(ctx)

    assert {:ok, _} =
             Ideation.set_round_privacy(ctx.facilitator, ctx.project.id, ctx.session.id, second.id, revision(ctx), %{
               private: true,
               reveal_on_expiry: true
             })

    second_secret = canvas_note(ctx, ctx.peer, 40)
    draft = idea_fixture(ctx)

    # The clock reaches 0:00.
    Repo.update_all(from(t in "ideation_timers", where: t.id == ^timer.id),
      set: [deadline_at: DateTime.shift(Storyarn.Platform.Shared.TimeHelpers.now(), second: -1)]
    )

    assert {:ok, %{outcome: :completed, revealed: true}} = Ideation.expire_timer(timer.id, timer.version)

    assert {:ok, rounds} = Ideation.list_rounds(ctx.facilitator, ctx.project.id, ctx.session.id)
    revealed = Enum.find(rounds, &(&1.id == first.id))
    assert revealed.status == :closed
    refute revealed.private
    assert revealed.revealed_at
    assert {:ok, _} = Ideation.get_idea(ctx.facilitator, ctx.project.id, ctx.session.id, secret.id)

    active = Enum.find(rounds, &(&1.id == second.id))
    assert active.status == :active
    refute active.private
    assert active.revealed_at
    assert {:ok, _} = Ideation.get_idea(ctx.facilitator, ctx.project.id, ctx.session.id, second_secret.id)
    assert {:error, :not_found} = Ideation.get_idea(ctx.facilitator, ctx.project.id, ctx.session.id, draft.id)
    assert {:ok, %{status: :elapsed}} = Ideation.get_timer(ctx.facilitator, ctx.project.id, ctx.session.id)
  end

  test "archiving ends a round's mask for good: reopened, it cannot hide again", ctx do
    first = first_round(ctx)
    assert {:ok, _} = set_private_mode(ctx.facilitator, ctx.project.id, ctx.session.id, revision(ctx), true)
    assert {:ok, archived} = Ideation.archive_session(ctx.facilitator, ctx.project.id, ctx.session.id, revision(ctx))

    assert {:ok, [%{private: false, revealed_at: revealed_at}]} =
             Ideation.list_rounds(ctx.facilitator, ctx.project.id, ctx.session.id)

    assert revealed_at

    assert {:ok, reopened} = Ideation.reopen_session(ctx.facilitator, ctx.project.id, ctx.session.id, archived.revision)

    assert {:error, :round_revealed} =
             Ideation.set_round_privacy(ctx.facilitator, ctx.project.id, ctx.session.id, first.id, reopened.revision, %{
               private: true
             })
  end
end
