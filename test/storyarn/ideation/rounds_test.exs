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

  test "optional rounds prepare, start and close independently of timer and privacy", ctx do
    assert {:ok, prepared} =
             Ideation.create_round(ctx.facilitator, ctx.project.id, ctx.session.id, 1, %{
               prompt: "  Explore the antagonist  ",
               number: 99,
               status: :active,
               session_id: -1,
               started_at: ~U[2026-09-01 00:00:00Z]
             })

    assert prepared.revision == 2
    assert prepared.configuration_version == 1
    assert prepared.configuration == ctx.session.configuration
    assert {:ok, [round]} = Ideation.list_rounds(ctx.viewer, ctx.project.id, ctx.session.id)
    assert round.number == 1
    assert round.prompt == "Explore the antagonist"
    assert round.status == :planned
    assert round.started_at == nil
    assert round.closed_at == nil
    assert round.recovery_identity

    assert {:ok, started} = Ideation.start_round(ctx.facilitator, ctx.project.id, ctx.session.id, round.id, 2)
    assert started.revision == 3
    assert {:ok, [active]} = Ideation.list_rounds(ctx.author, ctx.project.id, ctx.session.id, status: :active)
    assert active.started_at
    assert active.closed_at == nil
    assert {:ok, ^started} = Ideation.start_round(ctx.facilitator, ctx.project.id, ctx.session.id, round.id, 3)

    assert {:ok, closed} = Ideation.close_round(ctx.owner, ctx.project.id, ctx.session.id, round.id, 3)
    assert closed.revision == 4
    assert closed.configuration == ctx.session.configuration
    assert closed.configuration_version == 1
    assert closed.status == :open
    assert {:ok, ^closed} = Ideation.close_round(ctx.owner, ctx.project.id, ctx.session.id, round.id, 4)
    assert {:ok, [finished]} = Ideation.list_rounds(ctx.viewer, ctx.project.id, ctx.session.id, status: :closed)
    assert finished.started_at == active.started_at
    assert DateTime.compare(finished.closed_at, finished.started_at) in [:eq, :gt]

    assert {:ok, [closed_revision, started_revision, prepared_revision, _original]} =
             Ideation.list_session_revisions(ctx.viewer, ctx.project.id, ctx.session.id)

    assert closed_revision.action == :round_closed
    assert closed_revision.snapshot["round"]["closed_at"] == DateTime.to_iso8601(finished.closed_at)
    assert started_revision.action == :round_started
    assert started_revision.snapshot["round"]["closed_at"] == nil
    assert prepared_revision.action == :round_created

    assert prepared_revision.snapshot["round"] == %{
             "number" => 1,
             "prompt" => round.prompt,
             "status" => "planned",
             "started_at" => nil,
             "closed_at" => nil
           }
  end

  test "session managers alone can create and transition rounds with current revisions", ctx do
    for actor <- [ctx.author, ctx.peer, ctx.viewer] do
      assert {:error, :unauthorized} = Ideation.create_round(actor, ctx.project.id, ctx.session.id, 1, %{})
    end

    assert {:ok, prepared} = Ideation.create_round(ctx.owner, ctx.project.id, ctx.session.id, 1, %{})
    assert {:ok, [round]} = Ideation.list_rounds(ctx.owner, ctx.project.id, ctx.session.id)

    for actor <- [ctx.author, ctx.peer, ctx.viewer] do
      assert {:error, :unauthorized} = Ideation.start_round(actor, ctx.project.id, ctx.session.id, round.id, 2)
      assert {:error, :unauthorized} = Ideation.close_round(actor, ctx.project.id, ctx.session.id, round.id, 2)
      assert {:error, :unauthorized} = Ideation.update_round(actor, ctx.project.id, ctx.session.id, round.id, 2, %{})
      assert {:error, :unauthorized} = Ideation.cancel_round(actor, ctx.project.id, ctx.session.id, round.id, 2)
    end

    assert {:error, :stale_revision} = Ideation.create_round(ctx.facilitator, ctx.project.id, ctx.session.id, 1, %{})
    assert {:error, :stale_revision} = Ideation.start_round(ctx.facilitator, ctx.project.id, ctx.session.id, round.id, 1)
    assert {:error, :stale_revision} = Ideation.update_round(ctx.owner, ctx.project.id, ctx.session.id, round.id, 1, %{})
    assert {:error, :stale_revision} = Ideation.cancel_round(ctx.owner, ctx.project.id, ctx.session.id, round.id, 1)

    assert {:error, :invalid_revision} =
             Ideation.close_round(ctx.facilitator, ctx.project.id, ctx.session.id, round.id, nil)

    assert {:ok, ^prepared} = Ideation.get_session(ctx.owner, ctx.project.id, ctx.session.id)

    membership = Projects.get_membership(ctx.project.id, ctx.facilitator.user.id)
    assert {:ok, _} = Projects.update_member_role(ctx.owner, ctx.project.id, membership.id, "viewer")
    assert {:error, :unauthorized} = Ideation.start_round(ctx.facilitator, ctx.project.id, ctx.session.id, round.id, 2)

    assert {:error, :unauthorized} =
             Ideation.update_round(ctx.facilitator, ctx.project.id, ctx.session.id, round.id, 2, %{})

    assert {:error, :unauthorized} = Ideation.cancel_round(ctx.facilitator, ctx.project.id, ctx.session.id, round.id, 2)
  end

  test "rounds cannot cross sessions or projects and inaccessible sessions expose no round metadata", ctx do
    assert {:ok, _} = Ideation.create_round(ctx.facilitator, ctx.project.id, ctx.session.id, 1, %{})
    assert {:ok, [round]} = Ideation.list_rounds(ctx.author, ctx.project.id, ctx.session.id)
    assert {:ok, other} = Ideation.create_session(ctx.facilitator, ctx.project.id, %{title: "Other session"})
    stranger = user_scope_fixture()

    assert {:error, :round_not_found} = Ideation.start_round(ctx.facilitator, ctx.project.id, other.id, round.id, 1)
    assert {:error, :round_not_found} = Ideation.close_round(ctx.facilitator, ctx.project.id, other.id, round.id, 1)
    assert {:error, :round_not_found} = Ideation.update_round(ctx.facilitator, ctx.project.id, other.id, round.id, 1, %{})
    assert {:error, :round_not_found} = Ideation.cancel_round(ctx.facilitator, ctx.project.id, other.id, round.id, 1)
    assert {:error, :not_found} = Ideation.list_rounds(stranger, ctx.project.id, ctx.session.id)
    assert {:error, :not_found} = Ideation.list_rounds(ctx.owner, ctx.project.id, -1)
  end

  test "planned and completed rounds have explicit transitions and only one round can be active", ctx do
    assert {:ok, _} = Ideation.create_round(ctx.facilitator, ctx.project.id, ctx.session.id, 1, %{})
    assert {:ok, _} = Ideation.create_round(ctx.facilitator, ctx.project.id, ctx.session.id, 2, %{})
    assert {:ok, [second, first]} = Ideation.list_rounds(ctx.owner, ctx.project.id, ctx.session.id)
    assert first.prompt == nil
    assert second.number == 2

    assert {:error, :round_not_active} =
             Ideation.close_round(ctx.facilitator, ctx.project.id, ctx.session.id, first.id, 3)

    assert {:ok, _} = Ideation.start_round(ctx.facilitator, ctx.project.id, ctx.session.id, first.id, 3)

    assert {:error, :round_already_active} =
             Ideation.start_round(ctx.facilitator, ctx.project.id, ctx.session.id, second.id, 4)

    assert {:ok, _} = Ideation.close_round(ctx.facilitator, ctx.project.id, ctx.session.id, first.id, 4)
    assert {:error, :round_closed} = Ideation.start_round(ctx.facilitator, ctx.project.id, ctx.session.id, first.id, 5)
    assert {:ok, _} = Ideation.start_round(ctx.facilitator, ctx.project.id, ctx.session.id, second.id, 5)
    assert {:ok, [%{id: id}]} = Ideation.list_rounds(ctx.viewer, ctx.project.id, ctx.session.id, status: :active)
    assert id == second.id
  end

  test "archiving retains rounds but rejects ordinary round mutations until reopen", ctx do
    assert {:ok, _} = Ideation.create_round(ctx.facilitator, ctx.project.id, ctx.session.id, 1, %{})
    assert {:ok, [round]} = Ideation.list_rounds(ctx.owner, ctx.project.id, ctx.session.id)
    assert {:ok, _} = Ideation.archive_session(ctx.facilitator, ctx.project.id, ctx.session.id, 2)
    assert {:error, :session_archived} = Ideation.create_round(ctx.owner, ctx.project.id, ctx.session.id, 3, %{})
    assert {:error, :session_archived} = Ideation.start_round(ctx.owner, ctx.project.id, ctx.session.id, round.id, 3)
    assert {:error, :session_archived} = Ideation.close_round(ctx.owner, ctx.project.id, ctx.session.id, round.id, 3)

    assert {:error, :session_archived} =
             Ideation.update_round(ctx.owner, ctx.project.id, ctx.session.id, round.id, 3, %{})

    assert {:error, :session_archived} = Ideation.cancel_round(ctx.owner, ctx.project.id, ctx.session.id, round.id, 3)
    assert {:ok, [^round]} = Ideation.list_rounds(ctx.viewer, ctx.project.id, ctx.session.id)
  end

  test "round input and reads are bounded while the current round remains queryable beyond the newest page", ctx do
    for prompt <- [String.duplicate("a", 2001), 12, %{}] do
      assert {:error, %Ecto.Changeset{valid?: false}} =
               Ideation.create_round(ctx.facilitator, ctx.project.id, ctx.session.id, 1, %{prompt: prompt})
    end

    assert {:ok, _} = Ideation.create_round(ctx.facilitator, ctx.project.id, ctx.session.id, 1, %{prompt: " "})
    assert {:ok, [first]} = Ideation.list_rounds(ctx.owner, ctx.project.id, ctx.session.id)
    assert first.prompt == nil
    assert {:ok, _} = Ideation.start_round(ctx.facilitator, ctx.project.id, ctx.session.id, first.id, 2)

    for number <- 2..4 do
      Repo.insert!(%Round{session_id: ctx.session.id, number: number})
    end

    assert {:ok, [fourth, third]} = Ideation.list_rounds(ctx.viewer, ctx.project.id, ctx.session.id, limit: 2)
    assert [fourth.number, third.number] == [4, 3]

    assert {:ok, [%{number: 2}, %{number: 1}]} =
             Ideation.list_rounds(ctx.viewer, ctx.project.id, ctx.session.id, before_id: third.id, limit: 2)

    assert {:ok, [%{id: active_id}]} =
             Ideation.list_rounds(ctx.viewer, ctx.project.id, ctx.session.id, status: :active, limit: 1)

    assert active_id == first.id
    assert {:ok, [^third]} = Ideation.list_rounds(ctx.viewer, ctx.project.id, ctx.session.id, ids: [third.id])

    for opts <- [[limit: 201], [before_id: -1], [status: :unknown], [ids: [-1]], [ids: Enum.to_list(1..201)], %{}] do
      assert {:error, :invalid_options} = Ideation.list_rounds(ctx.viewer, ctx.project.id, ctx.session.id, opts)
    end
  end

  test "round mutations notify existing session subscribers only on success", ctx do
    assert :ok = Ideation.subscribe_sessions(ctx.author, ctx.project.id)
    assert {:ok, _} = Ideation.create_round(ctx.facilitator, ctx.project.id, ctx.session.id, 1, %{})
    assert_receive {:ideation_sessions_changed, project_id}
    assert project_id == ctx.project.id
    assert {:error, :stale_revision} = Ideation.create_round(ctx.facilitator, ctx.project.id, ctx.session.id, 1, %{})
    refute_receive {:ideation_sessions_changed, _}
  end

  test "a prepared prompt can be corrected or removed without changing lifecycle or session policy", ctx do
    assert {:ok, _} = Ideation.create_round(ctx.owner, ctx.project.id, ctx.session.id, 1, %{prompt: "Typo"})
    assert {:ok, [round]} = Ideation.list_rounds(ctx.viewer, ctx.project.id, ctx.session.id)
    assert :ok = Ideation.subscribe_sessions(ctx.author, ctx.project.id)

    assert {:ok, updated} =
             Ideation.update_round(ctx.facilitator, ctx.project.id, ctx.session.id, round.id, 2, %{
               prompt: "  Correct question?  ",
               number: 99,
               status: :active,
               session_id: -1,
               started_at: ~U[2026-09-01 00:00:00Z]
             })

    assert_receive {:ideation_sessions_changed, _}
    assert updated.revision == 3
    assert updated.configuration == ctx.session.configuration
    assert updated.configuration_version == 1
    assert {:ok, [corrected]} = Ideation.list_rounds(ctx.viewer, ctx.project.id, ctx.session.id)
    assert corrected.prompt == "Correct question?"
    assert corrected.number == 1
    assert corrected.status == :planned
    assert corrected.started_at == nil
    assert corrected.closed_at == nil
    assert corrected.recovery_identity == round.recovery_identity

    assert {:ok, ^updated} =
             Ideation.update_round(ctx.owner, ctx.project.id, ctx.session.id, round.id, 3, %{prompt: corrected.prompt})

    for prompt <- [String.duplicate("x", 2001), 12, %{}] do
      assert {:error, %Ecto.Changeset{valid?: false}} =
               Ideation.update_round(ctx.owner, ctx.project.id, ctx.session.id, round.id, 3, %{prompt: prompt})
    end

    assert {:error, :invalid_round} = Ideation.update_round(ctx.owner, ctx.project.id, ctx.session.id, round.id, 3, nil)
    assert {:ok, cleared} = Ideation.update_round(ctx.owner, ctx.project.id, ctx.session.id, round.id, 3, %{prompt: nil})
    assert cleared.revision == 4
    assert {:ok, [%{prompt: nil}]} = Ideation.list_rounds(ctx.viewer, ctx.project.id, ctx.session.id)

    assert {:ok, [cleared_revision, corrected_revision, _prepared, _original]} =
             Ideation.list_session_revisions(ctx.viewer, ctx.project.id, ctx.session.id)

    assert cleared_revision.action == :round_updated
    assert cleared_revision.snapshot["round"]["prompt"] == nil
    assert corrected_revision.action == :round_updated
    assert corrected_revision.snapshot["round"]["prompt"] == corrected.prompt
    assert corrected_revision.snapshot["round"]["status"] == "planned"
  end

  test "cancelling a prepared round preserves its identity without starting it or changing the active round", ctx do
    assert {:ok, _} = Ideation.create_round(ctx.owner, ctx.project.id, ctx.session.id, 1, %{prompt: "Ongoing"})
    assert {:ok, [active]} = Ideation.list_rounds(ctx.owner, ctx.project.id, ctx.session.id)
    assert {:ok, _} = Ideation.start_round(ctx.owner, ctx.project.id, ctx.session.id, active.id, 2)
    assert {:ok, _} = Ideation.create_round(ctx.owner, ctx.project.id, ctx.session.id, 3, %{prompt: "Accidental"})
    assert {:ok, [planned, _]} = Ideation.list_rounds(ctx.owner, ctx.project.id, ctx.session.id)
    assert :ok = Ideation.subscribe_sessions(ctx.author, ctx.project.id)
    assert {:ok, cancelled} = Ideation.cancel_round(ctx.facilitator, ctx.project.id, ctx.session.id, planned.id, 4)
    assert_receive {:ideation_sessions_changed, _}
    assert cancelled.revision == 5
    assert cancelled.configuration == ctx.session.configuration
    assert cancelled.configuration_version == 1
    assert {:ok, [round]} = Ideation.list_rounds(ctx.viewer, ctx.project.id, ctx.session.id, status: :cancelled)
    assert round.id == planned.id
    assert round.number == 2
    assert round.prompt == planned.prompt
    assert round.started_at == nil
    assert round.closed_at == nil
    assert round.recovery_identity == planned.recovery_identity
    assert {:ok, ^cancelled} = Ideation.cancel_round(ctx.owner, ctx.project.id, ctx.session.id, planned.id, 5)
    assert {:error, :stale_revision} = Ideation.cancel_round(ctx.owner, ctx.project.id, ctx.session.id, planned.id, 4)
    assert {:error, :round_cancelled} = Ideation.start_round(ctx.owner, ctx.project.id, ctx.session.id, planned.id, 5)
    assert {:error, :round_not_active} = Ideation.close_round(ctx.owner, ctx.project.id, ctx.session.id, planned.id, 5)

    assert {:error, :round_not_planned} =
             Ideation.update_round(ctx.owner, ctx.project.id, ctx.session.id, planned.id, 5, %{})

    assert idea_fixture(ctx).round_id == active.id

    assert {:ok, [cancel_revision | _]} = Ideation.list_session_revisions(ctx.viewer, ctx.project.id, ctx.session.id)
    assert cancel_revision.number == 5
    assert cancel_revision.action == :round_cancelled
    assert cancel_revision.snapshot["round"]["status"] == "cancelled"

    assert {:ok, _} = Ideation.create_round(ctx.owner, ctx.project.id, ctx.session.id, 5, %{})

    assert {:ok, [%{number: 3}, %{number: 2}, %{number: 1}]} =
             Ideation.list_rounds(ctx.viewer, ctx.project.id, ctx.session.id)
  end

  test "editing and cancellation cannot change rounds that have already started", ctx do
    assert {:ok, _} = Ideation.create_round(ctx.owner, ctx.project.id, ctx.session.id, 1, %{prompt: "Keep context"})
    assert {:ok, [round]} = Ideation.list_rounds(ctx.owner, ctx.project.id, ctx.session.id)
    assert {:ok, active} = Ideation.start_round(ctx.owner, ctx.project.id, ctx.session.id, round.id, 2)

    for actor <- [ctx.owner, ctx.facilitator] do
      assert {:error, :round_not_planned} =
               Ideation.update_round(actor, ctx.project.id, ctx.session.id, round.id, active.revision, %{
                 prompt: "Changed"
               })

      assert {:error, :round_not_planned} =
               Ideation.cancel_round(actor, ctx.project.id, ctx.session.id, round.id, active.revision)
    end

    assert {:ok, closed} = Ideation.close_round(ctx.owner, ctx.project.id, ctx.session.id, round.id, active.revision)

    assert {:error, :round_not_planned} =
             Ideation.update_round(ctx.owner, ctx.project.id, ctx.session.id, round.id, closed.revision, %{})

    assert {:error, :round_not_planned} =
             Ideation.cancel_round(ctx.owner, ctx.project.id, ctx.session.id, round.id, closed.revision)

    assert {:ok, [%{prompt: "Keep context", status: :closed}]} =
             Ideation.list_rounds(ctx.viewer, ctx.project.id, ctx.session.id)
  end
end
