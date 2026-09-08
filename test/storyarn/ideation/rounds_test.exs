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
    end

    assert {:error, :stale_revision} = Ideation.create_round(ctx.facilitator, ctx.project.id, ctx.session.id, 1, %{})
    assert {:error, :stale_revision} = Ideation.start_round(ctx.facilitator, ctx.project.id, ctx.session.id, round.id, 1)

    assert {:error, :invalid_revision} =
             Ideation.close_round(ctx.facilitator, ctx.project.id, ctx.session.id, round.id, nil)

    assert {:ok, ^prepared} = Ideation.get_session(ctx.owner, ctx.project.id, ctx.session.id)

    membership = Projects.get_membership(ctx.project.id, ctx.facilitator.user.id)
    assert {:ok, _} = Projects.update_member_role(ctx.owner, ctx.project.id, membership.id, "viewer")
    assert {:error, :unauthorized} = Ideation.start_round(ctx.facilitator, ctx.project.id, ctx.session.id, round.id, 2)
  end

  test "rounds cannot cross sessions or projects and inaccessible sessions expose no round metadata", ctx do
    assert {:ok, _} = Ideation.create_round(ctx.facilitator, ctx.project.id, ctx.session.id, 1, %{})
    assert {:ok, [round]} = Ideation.list_rounds(ctx.author, ctx.project.id, ctx.session.id)
    assert {:ok, other} = Ideation.create_session(ctx.facilitator, ctx.project.id, %{title: "Other session"})
    stranger = user_scope_fixture()

    assert {:error, :round_not_found} = Ideation.start_round(ctx.facilitator, ctx.project.id, other.id, round.id, 1)
    assert {:error, :round_not_found} = Ideation.close_round(ctx.facilitator, ctx.project.id, other.id, round.id, 1)
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
end
