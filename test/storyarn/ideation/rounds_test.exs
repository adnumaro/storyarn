defmodule Storyarn.Ideation.RoundsTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.IdeationFixtures

  alias Storyarn.Ideation
  alias Storyarn.Ideation.Sessions.Round
  alias Storyarn.Projects

  setup do
    ideation_fixture()
  end

  test "a session starts with its first round in progress and the next round closes it in one step", ctx do
    assert {:ok, [first]} = Ideation.list_rounds(ctx.viewer, ctx.project.id, ctx.session.id)
    assert first.number == 1
    assert first.status == :active
    assert first.prompt == nil
    assert first.canvas_offset_y == 0
    assert first.started_at
    assert first.closed_at == nil
    assert first.recovery_identity
    assert ctx.session.revision == 1

    assert {:ok, started} =
             Ideation.new_round(ctx.facilitator, ctx.project.id, ctx.session.id, 1, %{
               prompt: "  Explore the antagonist  ",
               canvas_offset_y: 640,
               number: 99,
               status: :closed,
               session_id: -1,
               started_at: ~U[2026-09-01 00:00:00Z]
             })

    assert started.revision == 2
    assert started.configuration_version == 1
    assert started.configuration == ctx.session.configuration
    assert {:ok, [second, closed]} = Ideation.list_rounds(ctx.viewer, ctx.project.id, ctx.session.id)
    assert closed.id == first.id
    assert closed.status == :closed
    assert closed.started_at == first.started_at
    assert DateTime.compare(closed.closed_at, closed.started_at) in [:eq, :gt]
    assert second.number == 2
    assert second.prompt == "Explore the antagonist"
    assert second.status == :active
    assert second.canvas_offset_y == 640
    assert second.started_at
    assert second.closed_at == nil
    assert second.session_id == ctx.session.id

    assert {:ok, [^second]} = Ideation.list_rounds(ctx.author, ctx.project.id, ctx.session.id, status: :active)
    assert {:ok, [^closed]} = Ideation.list_rounds(ctx.author, ctx.project.id, ctx.session.id, status: :closed)

    assert {:ok, [started_revision, _original]} =
             Ideation.list_session_revisions(ctx.viewer, ctx.project.id, ctx.session.id)

    assert started_revision.action == :round_started

    assert started_revision.snapshot["round"] == %{
             "number" => 2,
             "prompt" => "Explore the antagonist",
             "status" => "active",
             "started_at" => DateTime.to_iso8601(second.started_at),
             "closed_at" => nil
           }

    assert {:ok, ended} = Ideation.close_round(ctx.owner, ctx.project.id, ctx.session.id, second.id, 2)
    assert ended.revision == 3
    assert ended.status == :open
    assert {:ok, ^ended} = Ideation.close_round(ctx.owner, ctx.project.id, ctx.session.id, second.id, 3)
    assert {:ok, []} = Ideation.list_rounds(ctx.viewer, ctx.project.id, ctx.session.id, status: :active)
    assert {:ok, [closed_revision | _]} = Ideation.list_session_revisions(ctx.viewer, ctx.project.id, ctx.session.id)
    assert closed_revision.action == :round_closed
    assert closed_revision.snapshot["round"]["number"] == 2
  end

  test "the header of a new round is placed below the previous band, never inside it", ctx do
    assert {:ok, _} = Ideation.new_round(ctx.facilitator, ctx.project.id, ctx.session.id, 1, %{})
    assert {:ok, [second, _first]} = Ideation.list_rounds(ctx.viewer, ctx.project.id, ctx.session.id)
    assert second.canvas_offset_y == 320

    for offset <- [second.canvas_offset_y + 119, -1, 1.5, "900", 1_000_001] do
      assert {:error, :invalid_round_offset} =
               Ideation.new_round(ctx.facilitator, ctx.project.id, ctx.session.id, 2, %{canvas_offset_y: offset})
    end

    assert {:ok, _} =
             Ideation.new_round(ctx.facilitator, ctx.project.id, ctx.session.id, 2, %{
               "canvas_offset_y" => second.canvas_offset_y + 120
             })

    assert {:ok, [third | _]} = Ideation.list_rounds(ctx.viewer, ctx.project.id, ctx.session.id)
    assert third.number == 3
    assert third.canvas_offset_y == second.canvas_offset_y + 120
    assert {:error, :invalid_round} = Ideation.new_round(ctx.facilitator, ctx.project.id, ctx.session.id, 3, nil)
  end

  test "session managers alone can start, edit and close rounds with current revisions", ctx do
    round = first_round(ctx)

    for actor <- [ctx.author, ctx.peer, ctx.viewer] do
      assert {:error, :unauthorized} = Ideation.new_round(actor, ctx.project.id, ctx.session.id, 1, %{})
      assert {:error, :unauthorized} = Ideation.close_round(actor, ctx.project.id, ctx.session.id, round.id, 1)
      assert {:error, :unauthorized} = Ideation.update_round(actor, ctx.project.id, ctx.session.id, round.id, 1, %{})
    end

    assert {:ok, updated} =
             Ideation.update_round(ctx.owner, ctx.project.id, ctx.session.id, round.id, 1, %{prompt: "Why?"})

    assert updated.revision == 2
    assert {:error, :stale_revision} = Ideation.new_round(ctx.facilitator, ctx.project.id, ctx.session.id, 1, %{})

    assert {:error, :stale_revision} =
             Ideation.close_round(ctx.facilitator, ctx.project.id, ctx.session.id, round.id, 1)

    assert {:error, :stale_revision} =
             Ideation.update_round(ctx.owner, ctx.project.id, ctx.session.id, round.id, 1, %{prompt: "Again"})

    assert {:error, :invalid_revision} =
             Ideation.close_round(ctx.facilitator, ctx.project.id, ctx.session.id, round.id, nil)

    assert {:ok, ^updated} = Ideation.get_session(ctx.owner, ctx.project.id, ctx.session.id)

    membership = Projects.get_membership(ctx.project.id, ctx.facilitator.user.id)
    assert {:ok, _} = Projects.update_member_role(ctx.owner, ctx.project.id, membership.id, "viewer")
    assert {:error, :unauthorized} = Ideation.new_round(ctx.facilitator, ctx.project.id, ctx.session.id, 2, %{})
    assert {:error, :unauthorized} = Ideation.close_round(ctx.facilitator, ctx.project.id, ctx.session.id, round.id, 2)

    assert {:error, :unauthorized} =
             Ideation.update_round(ctx.facilitator, ctx.project.id, ctx.session.id, round.id, 2, %{})
  end

  test "rounds cannot cross sessions or projects and inaccessible sessions expose no round metadata", ctx do
    round = first_round(ctx)
    assert {:ok, other} = Ideation.create_session(ctx.facilitator, ctx.project.id, %{title: "Other session"})
    stranger = user_scope_fixture()

    assert {:error, :round_not_found} = Ideation.close_round(ctx.facilitator, ctx.project.id, other.id, round.id, 1)

    assert {:error, :round_not_found} =
             Ideation.update_round(ctx.facilitator, ctx.project.id, other.id, round.id, 1, %{})

    assert {:ok, [own]} = Ideation.list_rounds(ctx.author, ctx.project.id, other.id)
    assert own.session_id == other.id
    assert own.number == 1
    assert {:error, :not_found} = Ideation.list_rounds(stranger, ctx.project.id, ctx.session.id)
    assert {:error, :not_found} = Ideation.list_rounds(ctx.owner, ctx.project.id, -1)
  end

  test "closing without a new round leaves the session in convergence where new notes are late", ctx do
    round = first_round(ctx)
    assert {:ok, _} = Ideation.close_round(ctx.facilitator, ctx.project.id, ctx.session.id, round.id, 1)
    assert {:ok, %{active_round: nil}} = Ideation.get_round_context(ctx.viewer, ctx.project.id, ctx.session.id)

    assert {:error, :round_required} = Ideation.create_idea(ctx.author, ctx.project.id, ctx.session.id, idea_attrs())

    assert {:error, :round_required} =
             Ideation.create_idea(ctx.author, ctx.project.id, ctx.session.id, idea_attrs(%{round_id: nil}))

    late = idea_fixture(ctx, %{round_id: round.id})
    assert late.round_id == round.id
    assert late.late_contribution

    assert {:ok, _} = Ideation.new_round(ctx.facilitator, ctx.project.id, ctx.session.id, 2, %{})
    fresh = idea_fixture(ctx)
    assert fresh.round_id != round.id
    refute fresh.late_contribution
  end

  test "archiving retains rounds but rejects ordinary round mutations until reopen", ctx do
    round = first_round(ctx)
    assert {:ok, _} = Ideation.archive_session(ctx.facilitator, ctx.project.id, ctx.session.id, 1)
    assert {:error, :session_archived} = Ideation.new_round(ctx.owner, ctx.project.id, ctx.session.id, 2, %{})
    assert {:error, :session_archived} = Ideation.close_round(ctx.owner, ctx.project.id, ctx.session.id, round.id, 2)

    assert {:error, :session_archived} =
             Ideation.update_round(ctx.owner, ctx.project.id, ctx.session.id, round.id, 2, %{})

    assert {:ok, [^round]} = Ideation.list_rounds(ctx.viewer, ctx.project.id, ctx.session.id)
  end

  test "round input and reads are bounded", ctx do
    for prompt <- [String.duplicate("a", 2001), 12, %{}] do
      assert {:error, %Ecto.Changeset{valid?: false}} =
               Ideation.new_round(ctx.facilitator, ctx.project.id, ctx.session.id, 1, %{prompt: prompt})
    end

    assert {:ok, _} = Ideation.new_round(ctx.facilitator, ctx.project.id, ctx.session.id, 1, %{prompt: " "})
    assert {:ok, [second, first]} = Ideation.list_rounds(ctx.owner, ctx.project.id, ctx.session.id)
    assert second.prompt == nil

    now = DateTime.utc_now()

    for number <- 3..4 do
      Repo.insert!(%Round{
        session_id: ctx.session.id,
        number: number,
        status: :closed,
        started_at: now,
        closed_at: now,
        canvas_offset_y: number * 400
      })
    end

    assert {:ok, [fourth, third]} = Ideation.list_rounds(ctx.viewer, ctx.project.id, ctx.session.id, limit: 2)
    assert [fourth.number, third.number] == [4, 3]

    assert {:ok, [%{number: 2}, %{number: 1}]} =
             Ideation.list_rounds(ctx.viewer, ctx.project.id, ctx.session.id, before_id: third.id, limit: 2)

    assert {:ok, [%{id: active_id}]} =
             Ideation.list_rounds(ctx.viewer, ctx.project.id, ctx.session.id, status: :active, limit: 1)

    assert active_id == second.id
    assert {:ok, [^third]} = Ideation.list_rounds(ctx.viewer, ctx.project.id, ctx.session.id, ids: [third.id])
    assert {:ok, %{rounds: rounds}} = Ideation.get_round_context(ctx.viewer, ctx.project.id, ctx.session.id)
    assert Enum.map(rounds, & &1.number) == [1, 2, 3, 4]
    assert hd(rounds).id == first.id

    for opts <- [
          [limit: 201],
          [before_id: -1],
          [status: :unknown],
          [status: :planned],
          [ids: [-1]],
          [ids: Enum.to_list(1..201)],
          %{}
        ] do
      assert {:error, :invalid_options} = Ideation.list_rounds(ctx.viewer, ctx.project.id, ctx.session.id, opts)
    end
  end

  test "round mutations notify existing session subscribers only on success", ctx do
    assert :ok = Ideation.subscribe_sessions(ctx.author, ctx.project.id)
    assert {:ok, _} = Ideation.new_round(ctx.facilitator, ctx.project.id, ctx.session.id, 1, %{})
    assert_receive {:ideation_sessions_changed, project_id}
    assert project_id == ctx.project.id
    assert {:error, :stale_revision} = Ideation.new_round(ctx.facilitator, ctx.project.id, ctx.session.id, 1, %{})
    refute_receive {:ideation_sessions_changed, _}
  end

  test "the question of the round in progress can be corrected or removed, closed questions are history", ctx do
    round = first_round(ctx)
    assert :ok = Ideation.subscribe_sessions(ctx.author, ctx.project.id)

    assert {:ok, updated} =
             Ideation.update_round(ctx.facilitator, ctx.project.id, ctx.session.id, round.id, 1, %{
               prompt: "  Correct question?  ",
               number: 99,
               status: :closed,
               session_id: -1,
               canvas_offset_y: 500,
               started_at: ~U[2026-09-01 00:00:00Z]
             })

    assert_receive {:ideation_sessions_changed, _}
    assert updated.revision == 2
    assert updated.configuration == ctx.session.configuration
    assert updated.configuration_version == 1
    assert {:ok, [corrected]} = Ideation.list_rounds(ctx.viewer, ctx.project.id, ctx.session.id)
    assert corrected.prompt == "Correct question?"
    assert corrected.number == 1
    assert corrected.status == :active
    assert corrected.canvas_offset_y == 0
    assert corrected.started_at == round.started_at
    assert corrected.recovery_identity == round.recovery_identity

    assert {:ok, ^updated} =
             Ideation.update_round(ctx.owner, ctx.project.id, ctx.session.id, round.id, 2, %{prompt: corrected.prompt})

    for prompt <- [String.duplicate("x", 2001), 12, %{}] do
      assert {:error, %Ecto.Changeset{valid?: false}} =
               Ideation.update_round(ctx.owner, ctx.project.id, ctx.session.id, round.id, 2, %{prompt: prompt})
    end

    assert {:error, :invalid_round} = Ideation.update_round(ctx.owner, ctx.project.id, ctx.session.id, round.id, 2, nil)

    assert {:ok, cleared} =
             Ideation.update_round(ctx.owner, ctx.project.id, ctx.session.id, round.id, 2, %{prompt: nil})

    assert cleared.revision == 3
    assert {:ok, [%{prompt: nil}]} = Ideation.list_rounds(ctx.viewer, ctx.project.id, ctx.session.id)

    assert {:ok, [cleared_revision, corrected_revision, _original]} =
             Ideation.list_session_revisions(ctx.viewer, ctx.project.id, ctx.session.id)

    assert cleared_revision.action == :round_updated
    assert cleared_revision.snapshot["round"]["prompt"] == nil
    assert corrected_revision.action == :round_updated
    assert corrected_revision.snapshot["round"]["prompt"] == corrected.prompt
    assert corrected_revision.snapshot["round"]["status"] == "active"

    assert {:ok, closed} = Ideation.close_round(ctx.owner, ctx.project.id, ctx.session.id, round.id, 3)

    for actor <- [ctx.owner, ctx.facilitator] do
      assert {:error, :round_not_active} =
               Ideation.update_round(actor, ctx.project.id, ctx.session.id, round.id, closed.revision, %{
                 prompt: "Changed"
               })
    end

    assert {:ok, [%{prompt: nil, status: :closed}]} = Ideation.list_rounds(ctx.viewer, ctx.project.id, ctx.session.id)
  end
end
