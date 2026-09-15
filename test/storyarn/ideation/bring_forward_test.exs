defmodule Storyarn.Ideation.BringForwardTest do
  use Storyarn.DataCase, async: true

  import Storyarn.IdeationFixtures

  alias Storyarn.Ideation
  alias Storyarn.Ideation.Ideas.Idea

  setup do
    ideation_fixture()
  end

  defp bring(ctx, source, attrs \\ %{}, actor \\ nil) do
    attrs = Map.put_new(attrs, :request_key, Ecto.UUID.generate())
    Ideation.bring_idea_forward(actor || ctx.author, ctx.project.id, ctx.session.id, source.id, attrs)
  end

  test "brings a note of an earlier round into the one in progress as a linked copy of the actor's own", ctx do
    first = first_round(ctx)

    original =
      idea_fixture(ctx, %{
        title: "Keep the light",
        body: "<p>Mara keeps the light</p>",
        canvas: %{"x" => 40, "y" => 120, "width" => 320, "color" => "mint", "shape" => "ellipse"}
      })

    {ctx, second} = new_round(ctx)

    assert {:ok, copy} = bring(ctx, original, %{canvas: %{x: 60, y: 24}})
    assert copy.round_id == second.id
    refute copy.late_contribution
    assert copy.author_id == ctx.author.user.id
    assert copy.title == "Keep the light"
    assert copy.body == "<p>Mara keeps the light</p>"
    assert copy.state == :active
    assert copy.visibility == :shared
    assert copy.source_idea_id == original.id
    assert copy.source_revision == 1

    assert Map.take(copy.canvas, ~w(x y width color shape)) == %{
             "x" => 60,
             "y" => 24,
             "width" => 320,
             "color" => "mint",
             "shape" => "ellipse"
           }

    assert {:ok, untouched} = Ideation.get_idea(ctx.author, ctx.project.id, ctx.session.id, original.id)
    assert untouched.round_id == first.id
    assert untouched.canvas["x"] == 40
    assert Repo.aggregate(Idea, :count) == 2

    # Everyone reads the copy; its link to a private original stays with the author.
    assert {:ok, seen} = Ideation.get_idea(ctx.peer, ctx.project.id, ctx.session.id, copy.id)
    assert seen.body == "<p>Mara keeps the light</p>"
    assert seen.source_idea_id == nil
    publish_idea(ctx, original)
    assert {:ok, attributed} = Ideation.get_idea(ctx.peer, ctx.project.id, ctx.session.id, copy.id)
    assert attributed.source_idea_id == original.id
  end

  test "a parked note leaves the For later count once brought, and the request replays", ctx do
    %{project: %{id: project_id}, session: %{id: session_id}} = ctx
    original = idea_fixture(ctx)

    assert {:ok, parked} =
             Ideation.update_idea(ctx.author, project_id, session_id, original.id, 1, edit_attrs(%{state: :parked}))

    publish_idea(ctx, parked)
    {ctx, second} = new_round(ctx)
    assert {:ok, %{^session_id => 1}} = Ideation.count_parked_ideas(ctx.author, project_id, [session_id])

    assert {:ok, _} =
             Ideation.set_round_privacy(ctx.facilitator, project_id, session_id, second.id, ctx.session.revision, %{
               private: true
             })

    key = Ecto.UUID.generate()
    assert {:ok, copy} = bring(ctx, parked, %{request_key: key, canvas: %{x: 0, y: 10}})
    assert {:ok, counts} = Ideation.count_parked_ideas(ctx.author, project_id, [session_id])
    assert Map.get(counts, session_id, 0) == 0

    assert {:ok, still} = Ideation.get_idea(ctx.author, project_id, session_id, original.id)
    assert still.state == :parked

    # A copy the reader cannot see does not take the original off their list: tree and list agree.
    assert {:ok, %{^session_id => 1}} = Ideation.count_parked_ideas(ctx.peer, project_id, [session_id])
    assert {:ok, [%{id: original_id}]} = Ideation.list_ideas(ctx.peer, project_id, session_id, state: :parked)
    assert original_id == original.id

    assert {:ok, replayed} = bring(ctx, parked, %{request_key: key, canvas: %{x: 0, y: 10}})
    assert replayed.id == copy.id
    assert {:error, :idempotency_conflict} = bring(ctx, parked, %{request_key: key, canvas: %{x: 5, y: 10}})
    assert Repo.aggregate(Idea, :count) == 2
  end

  test "refuses the round in progress, unreadable sources, bad placement, readers and closed contributions", ctx do
    %{project: %{id: project_id}, session: %{id: session_id}} = ctx
    original = idea_fixture(ctx)
    assert {:error, :same_round} = bring(ctx, original)

    {ctx, _second} = new_round(ctx)
    assert {:error, :outside_band} = bring(ctx, original, %{canvas: %{x: 0, y: -5}})
    assert {:error, :invalid_canvas} = bring(ctx, original, %{canvas: "nope"})
    assert {:error, :invalid_request_key} = bring(ctx, original, %{request_key: "nope"})
    assert {:error, :not_found} = bring(ctx, original, %{}, ctx.peer)

    assert {:ok, discarded} =
             Ideation.update_idea(ctx.author, project_id, session_id, original.id, 1, edit_attrs(%{state: :discarded}))

    assert {:error, :source_discarded} = bring(ctx, discarded)

    assert {:ok, _} =
             Ideation.update_idea(ctx.author, project_id, session_id, original.id, 2, edit_attrs(%{state: :active}))

    assert {:error, :not_found} = bring(ctx, %{id: original.id + 1000})
    assert {:error, :unauthorized} = bring(ctx, original, %{}, ctx.viewer)

    {:ok, current} = Ideation.get_session(ctx.facilitator, project_id, session_id)
    {:ok, _} = Ideation.set_contributions_open(ctx.facilitator, project_id, session_id, current.revision, false)
    assert {:error, :contributions_closed} = bring(ctx, original)
    assert Repo.aggregate(Idea, :count) == 1
  end
end
