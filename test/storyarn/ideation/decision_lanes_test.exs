defmodule Storyarn.Ideation.DecisionLanesTest do
  use Storyarn.DataCase, async: true

  import Storyarn.IdeationFixtures

  alias Storyarn.Ideation

  setup do
    ctx = ideation_fixture()
    Map.put(ctx, :round, first_round(ctx))
  end

  test "a contributor moves a round's lane and every reader of the session hears about it", ctx do
    Phoenix.PubSub.subscribe(Storyarn.PubSub, "ideation:#{ctx.project.id}:#{ctx.session.id}:shared")
    assert ctx.round.decision_lane == %{}

    assert {:ok, %{round_id: round_id, x: 120, y: 480.5, version: 1}} =
             Ideation.move_decision_lane(ctx.author, ctx.project.id, ctx.session.id, ctx.round.id, %{
               "x" => 120,
               "y" => 480.5,
               "version" => 0
             })

    assert round_id == ctx.round.id
    assert_receive {:ideation_changed, session_id}
    assert session_id == ctx.session.id
    assert first_round(ctx).decision_lane == %{"x" => 120, "y" => 480.5, "version" => 1}

    # Moving a lane is a placement, not a session edit.
    assert {:ok, session} = Ideation.get_session(ctx.viewer, ctx.project.id, ctx.session.id)
    assert session.revision == ctx.session.revision
  end

  test "a move made against an older version is rejected, and a retried move answers without a change", ctx do
    move = fn actor, x, version ->
      Ideation.move_decision_lane(actor, ctx.project.id, ctx.session.id, ctx.round.id, %{x: x, y: 40, version: version})
    end

    assert {:ok, %{version: 1}} = move.(ctx.author, 10, 0)
    Phoenix.PubSub.subscribe(Storyarn.PubSub, "ideation:#{ctx.project.id}:#{ctx.session.id}:shared")

    assert {:ok, %{x: 10, version: 1}} = move.(ctx.author, 10, 0)
    refute_receive {:ideation_changed, _}

    assert {:error, :stale_decision_lane} = move.(ctx.peer, 200, 0)
    assert first_round(ctx).decision_lane == %{"x" => 10, "y" => 40, "version" => 1}
    assert {:ok, %{x: 200, version: 2}} = move.(ctx.peer, 200, 1)
  end

  test "only contributors of an open session move lanes, and never those of a hidden round", ctx do
    attrs = %{x: 0, y: 0, version: 0}

    assert {:error, _} = Ideation.move_decision_lane(ctx.viewer, ctx.project.id, ctx.session.id, ctx.round.id, attrs)

    assert {:ok, _} =
             set_private_mode(ctx.facilitator, ctx.project.id, ctx.session.id, ctx.session.revision, true)

    assert {:error, :private_round} =
             Ideation.move_decision_lane(ctx.author, ctx.project.id, ctx.session.id, ctx.round.id, attrs)

    other = ideation_fixture()

    assert {:error, :round_not_found} =
             Ideation.move_decision_lane(ctx.author, ctx.project.id, ctx.session.id, first_round(other).id, attrs)

    assert first_round(ctx).decision_lane == %{}
  end

  test "an archived session keeps its lanes where they are", ctx do
    {:ok, archived} = Ideation.archive_session(ctx.facilitator, ctx.project.id, ctx.session.id, ctx.session.revision)
    assert archived.status == :archived

    assert {:error, :session_archived} =
             Ideation.move_decision_lane(ctx.author, ctx.project.id, ctx.session.id, ctx.round.id, %{
               x: 0,
               y: 0,
               version: 0
             })
  end

  test "a lane position must be a finite place on the board with a known version", ctx do
    for attrs <- [
          %{x: "10", y: 0, version: 0},
          %{x: 0, y: 2_000_000, version: 0},
          %{x: 0, y: 0, version: -1},
          %{x: 0, y: 0, version: 1.5},
          %{x: 0, y: 0}
        ] do
      assert {:error, :invalid_decision_lane} =
               Ideation.move_decision_lane(ctx.author, ctx.project.id, ctx.session.id, ctx.round.id, attrs)
    end

    assert {:error, :invalid_decision_lane} =
             Ideation.move_decision_lane(ctx.author, ctx.project.id, ctx.session.id, ctx.round.id, nil)
  end
end
