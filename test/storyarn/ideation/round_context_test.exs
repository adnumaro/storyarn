defmodule Storyarn.Ideation.RoundContextTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.IdeationFixtures

  alias Storyarn.Ideation
  alias Storyarn.Ideation.Sessions.Round

  setup do
    ideation_fixture()
  end

  test "history, the current round and referenced context share one authorization", ctx do
    active = active_round(ctx)
    next = Repo.insert!(%Round{session_id: ctx.session.id, number: 2, prompt: "Next question"})

    {single_read, single_queries} =
      queries(fn -> Ideation.list_rounds(ctx.viewer, ctx.project.id, ctx.session.id) end)

    {_, separate_queries} =
      queries(fn ->
        Ideation.list_rounds(ctx.viewer, ctx.project.id, ctx.session.id)

        Ideation.list_rounds(ctx.viewer, ctx.project.id, ctx.session.id,
          status: :active,
          limit: 1
        )
      end)

    {result, combined_queries} =
      queries(fn ->
        Ideation.get_round_context(ctx.viewer, ctx.project.id, ctx.session.id,
          round_ids: [active.id],
          selected_id: next.id
        )
      end)

    assert {:ok, [^next, ^active]} = single_read
    assert {:ok, %{rounds: [^next, ^active], active_round: ^active, rounds_next: nil}} = result
    assert combined_queries == single_queries
    assert combined_queries < separate_queries
  end

  test "older active, referenced and selected rounds do not change the history cursor", ctx do
    active = active_round(ctx)
    old = Repo.insert!(%Round{session_id: ctx.session.id, number: 2, prompt: "Earlier context"})

    selected =
      Repo.insert!(%Round{session_id: ctx.session.id, number: 3, prompt: "Selected context"})

    newest = Repo.insert!(%Round{session_id: ctx.session.id, number: 4})

    assert {:ok, context} =
             Ideation.get_round_context(ctx.viewer, ctx.project.id, ctx.session.id,
               limit: 1,
               round_ids: [old.id, old.id],
               selected_id: selected.id
             )

    assert context.rounds_next == newest.id
    assert context.active_round == active

    assert MapSet.new(context.rounds, & &1.id) ==
             MapSet.new([active.id, old.id, selected.id, newest.id])

    assert {:ok, expanded} =
             Ideation.get_round_context(ctx.viewer, ctx.project.id, ctx.session.id,
               limit: 1,
               through_id: selected.id
             )

    assert expanded.rounds_next == old.id
    assert expanded.rounds == [newest, selected, old, active]
  end

  test "references from more than one page are loaded without truncating their context", ctx do
    rounds =
      for number <- 1..203, do: Repo.insert!(%Round{session_id: ctx.session.id, number: number})

    ids = Enum.map(rounds, & &1.id)

    assert {:ok, context} =
             Ideation.get_round_context(ctx.viewer, ctx.project.id, ctx.session.id,
               limit: 1,
               round_ids: ids
             )

    assert context.active_round == nil
    assert context.rounds_next == List.last(rounds).id
    assert MapSet.new(context.rounds, & &1.id) == MapSet.new(ids)
  end

  test "round metadata never crosses session or access boundaries", ctx do
    active = active_round(ctx)

    assert {:ok, other} =
             Ideation.create_session(ctx.facilitator, ctx.project.id, %{title: "Other session"})

    stranger = user_scope_fixture()

    assert {:ok, %{rounds: [], active_round: nil, rounds_next: nil}} =
             Ideation.get_round_context(ctx.author, ctx.project.id, other.id, round_ids: [active.id])

    assert {:error, :round_not_found} =
             Ideation.get_round_context(ctx.author, ctx.project.id, other.id, selected_id: active.id)

    assert {:error, :not_found} =
             Ideation.get_round_context(stranger, ctx.project.id, ctx.session.id, selected_id: active.id)

    assert {:error, :not_found} =
             Ideation.get_round_context(stranger, ctx.project.id, ctx.session.id, %{})

    assert {:error, :not_found} = Ideation.get_round_context(ctx.owner, ctx.project.id, -1)
  end

  test "round context validates typed options and id bounds", ctx do
    for opts <- [
          %{},
          ["invalid"],
          [limit: 0],
          [limit: 201],
          [through_id: "1"],
          [through_id: 9_223_372_036_854_775_808],
          [selected_id: -1],
          [selected_id: 9_223_372_036_854_775_808],
          [round_ids: nil],
          [round_ids: [nil]],
          [round_ids: [-1]],
          [round_ids: [9_223_372_036_854_775_808]]
        ] do
      assert {:error, :invalid_options} =
               Ideation.get_round_context(ctx.viewer, ctx.project.id, ctx.session.id, opts)
    end
  end

  test "idea counts validate their filter without depending on unused pagination options", ctx do
    active = active_round(ctx)
    idea_fixture(ctx, %{visibility: :shared})
    idea_fixture(ctx, %{}, ctx.peer)

    assert {:ok, %{active: 1, parked: 0, discarded: 0}} =
             Ideation.count_ideas(ctx.viewer, ctx.project.id, ctx.session.id,
               round_id: active.id,
               before_id: "unused",
               limit: 0
             )

    for opts <- [%{}, ["invalid"], [round_id: "1"]] do
      assert {:error, :invalid_options} =
               Ideation.count_ideas(ctx.viewer, ctx.project.id, ctx.session.id, opts)
    end
  end

  defp active_round(ctx) do
    assert {:ok, _} =
             Ideation.create_round(ctx.facilitator, ctx.project.id, ctx.session.id, 1, %{
               prompt: "Question"
             })

    assert {:ok, [round]} = Ideation.list_rounds(ctx.owner, ctx.project.id, ctx.session.id)

    assert {:ok, _} =
             Ideation.start_round(ctx.facilitator, ctx.project.id, ctx.session.id, round.id, 2)

    assert {:ok, [active]} = Ideation.list_rounds(ctx.owner, ctx.project.id, ctx.session.id)
    active
  end

  defp queries(fun) do
    owner = self()
    marker = make_ref()

    :ok =
      :telemetry.attach(
        marker,
        [:storyarn, :repo, :query],
        fn _, _, _, _ ->
          if self() == owner, do: send(owner, {:round_context_query, marker})
        end,
        nil
      )

    try do
      result = fun.()
      {result, query_count(marker, 0)}
    after
      :telemetry.detach(marker)
    end
  end

  defp query_count(marker, count) do
    receive do
      {:round_context_query, ^marker} -> query_count(marker, count + 1)
    after
      0 -> count
    end
  end
end
