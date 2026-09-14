defmodule Storyarn.Ideation.RoundContextTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.IdeationFixtures

  alias Storyarn.Ideation

  setup do
    ideation_fixture()
  end

  test "the canvas context lists every round in band order with the current one after one authorization", ctx do
    first = first_round(ctx)
    {ctx, second} = new_round(ctx, %{prompt: "Second question"})
    {_ctx, third} = new_round(ctx, %{prompt: "Third question", canvas_offset_y: 900})

    {single_read, single_queries} =
      queries(fn -> Ideation.list_rounds(ctx.viewer, ctx.project.id, ctx.session.id) end)

    {_, separate_queries} =
      queries(fn ->
        Ideation.list_rounds(ctx.viewer, ctx.project.id, ctx.session.id)
        Ideation.list_rounds(ctx.viewer, ctx.project.id, ctx.session.id, status: :active, limit: 1)
      end)

    {result, combined_queries} =
      queries(fn -> Ideation.get_round_context(ctx.viewer, ctx.project.id, ctx.session.id) end)

    assert {:ok, [_, _, _]} = single_read
    assert {:ok, %{rounds: rounds, active_round: active}} = result
    assert Enum.map(rounds, & &1.id) == [first.id, second.id, third.id]
    assert Enum.map(rounds, & &1.canvas_offset_y) == [0, 320, 900]
    assert active.id == third.id
    refute result |> elem(1) |> Map.has_key?(:rounds_next)
    assert combined_queries == single_queries
    assert combined_queries < separate_queries

    assert {:ok, %{timer: nil, rounds: ^rounds, active_round: ^active}} =
             Ideation.get_canvas_context(ctx.viewer, ctx.project.id, ctx.session.id)
  end

  test "round metadata never crosses session or access boundaries", ctx do
    first = first_round(ctx)
    assert {:ok, other} = Ideation.create_session(ctx.facilitator, ctx.project.id, %{title: "Other session"})
    stranger = user_scope_fixture()

    assert {:ok, %{rounds: [own], active_round: own}} =
             Ideation.get_round_context(ctx.author, ctx.project.id, other.id)

    assert own.session_id == other.id
    refute own.id == first.id
    assert {:error, :not_found} = Ideation.get_round_context(stranger, ctx.project.id, ctx.session.id)
    assert {:error, :not_found} = Ideation.get_round_context(ctx.owner, ctx.project.id, -1)
    assert {:error, :invalid_options} = Ideation.get_round_context(ctx.viewer, ctx.project.id, ctx.session.id, %{})

    assert {:error, :invalid_options} =
             Ideation.get_round_context(ctx.viewer, ctx.project.id, ctx.session.id, ["invalid"])
  end

  test "the session tree reads rounds of several sessions of one project in a single query", ctx do
    first = first_round(ctx)
    {ctx, second} = new_round(ctx)
    assert {:ok, other} = Ideation.create_session(ctx.facilitator, ctx.project.id, %{title: "Other session"})
    {:ok, [other_round]} = Ideation.list_rounds(ctx.viewer, ctx.project.id, other.id)
    foreign = ideation_fixture()

    {result, count} =
      queries(fn ->
        Ideation.list_session_rounds(ctx.viewer, ctx.project.id, [ctx.session.id, other.id, foreign.session.id])
      end)

    assert {:ok, rounds} = result
    assert Enum.map(rounds[ctx.session.id], & &1.id) == [first.id, second.id]
    assert Enum.map(rounds[other.id], & &1.id) == [other_round.id]
    refute Map.has_key?(rounds, foreign.session.id)
    assert count <= 4

    assert {:ok, %{}} = Ideation.list_session_rounds(ctx.viewer, ctx.project.id, [])
    stranger = user_scope_fixture()
    assert {:error, _} = Ideation.list_session_rounds(stranger, ctx.project.id, [ctx.session.id])

    for invalid <- [[-1], ["1"], Enum.to_list(1..201), %{}] do
      assert {:error, :invalid_options} = Ideation.list_session_rounds(ctx.viewer, ctx.project.id, invalid)
    end
  end

  test "idea counts validate their filter without depending on unused pagination options", ctx do
    active = first_round(ctx)
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
