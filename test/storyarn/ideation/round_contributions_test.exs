defmodule Storyarn.Ideation.RoundContributionsTest do
  use Storyarn.DataCase, async: true

  import Storyarn.IdeationFixtures

  alias Storyarn.Ideation
  alias Storyarn.Ideation.Ideas.Edit
  alias Storyarn.Ideation.Ideas.Idea

  setup do
    ideation_fixture()
  end

  test "contributions need no round and explicit nil stays unround while a round is active", ctx do
    unround = idea_fixture(ctx)
    assert unround.round_id == nil
    refute unround.late_contribution

    round = active_round(ctx)
    implicit = idea_fixture(ctx)
    explicit = idea_fixture(ctx, %{round_id: round.id})
    outside = idea_fixture(ctx, %{round_id: nil, late_contribution: true})
    assert implicit.round_id == round.id
    assert explicit.round_id == round.id
    refute implicit.late_contribution
    assert outside.round_id == nil
    refute outside.late_contribution
  end

  test "a first save after close retains its captured round and records lateness without moving existing ideas", ctx do
    first = active_round(ctx)
    early = idea_fixture(ctx, %{round_id: first.id})
    close_round(ctx, first)
    second = active_round(ctx)

    late = idea_fixture(ctx, %{round_id: first.id, late_contribution: false})
    implicit = idea_fixture(ctx)
    assert late.round_id == first.id
    assert late.late_contribution
    assert implicit.round_id == second.id
    refute implicit.late_contribution

    assert {:ok, edited} =
             Ideation.update_idea(
               ctx.author,
               ctx.project.id,
               ctx.session.id,
               early.id,
               early.revision,
               edit_attrs(%{body: "Edited after close", round_id: second.id, late_contribution: true})
             )

    assert edited.round_id == first.id
    refute edited.late_contribution
    assert Repo.get!(Idea, early.id).round_id == first.id
  end

  test "planned, cancelled, foreign and malformed rounds cannot accept a contribution", ctx do
    assert {:ok, _} = Ideation.create_round(ctx.facilitator, ctx.project.id, ctx.session.id, 1, %{})
    assert {:ok, [planned]} = Ideation.list_rounds(ctx.author, ctx.project.id, ctx.session.id)

    assert {:error, :round_not_started} =
             Ideation.create_idea(ctx.author, ctx.project.id, ctx.session.id, idea_attrs(%{round_id: planned.id}))

    assert {:ok, _} = Ideation.cancel_round(ctx.facilitator, ctx.project.id, ctx.session.id, planned.id, 2)

    assert {:error, :round_cancelled} =
             Ideation.create_idea(ctx.author, ctx.project.id, ctx.session.id, idea_attrs(%{round_id: planned.id}))

    assert {:ok, other} = Ideation.create_session(ctx.facilitator, ctx.project.id, %{title: "Other session"})

    assert {:error, :round_not_found} =
             Ideation.create_idea(ctx.author, ctx.project.id, other.id, idea_attrs(%{round_id: planned.id}))

    for invalid <- [-1, 0, 1.5, "1", :active, %{}, 9_223_372_036_854_775_808] do
      assert {:error, :invalid_round} =
               Ideation.create_idea(ctx.author, ctx.project.id, ctx.session.id, idea_attrs(%{round_id: invalid}))
    end

    assert Repo.aggregate(Idea, :count) == 0
    assert Repo.aggregate(Edit, :count) == 0
  end

  test "creation replay freezes round assignment and preserves receipts from requests without a round field", ctx do
    legacy_attrs = idea_attrs()
    assert {:ok, legacy} = Ideation.create_idea(ctx.author, ctx.project.id, ctx.session.id, legacy_attrs)
    legacy_receipt = Repo.get_by!(Edit, idea_id: legacy.id, request_key: legacy_attrs.request_key)

    assert legacy_receipt.fingerprint ==
             :crypto.hash(
               :sha256,
               :erlang.term_to_binary(
                 {:ideation_edit_v1, {:create, nil, [body: legacy_attrs.body, configuration_version: 1]}}
               )
             )

    first = active_round(ctx)
    attrs = idea_attrs(%{round_id: first.id})
    assert {:ok, created} = Ideation.create_idea(ctx.author, ctx.project.id, ctx.session.id, attrs)
    close_round(ctx, first)
    second = active_round(ctx)

    assert {:ok, ^legacy} = Ideation.create_idea(ctx.author, ctx.project.id, ctx.session.id, legacy_attrs)
    assert {:ok, ^created} = Ideation.create_idea(ctx.author, ctx.project.id, ctx.session.id, attrs)
    refute created.late_contribution

    for modified <- [Map.put(attrs, :round_id, second.id), Map.put(attrs, :round_id, nil), Map.delete(attrs, :round_id)] do
      assert {:error, :idempotency_conflict} =
               Ideation.create_idea(ctx.author, ctx.project.id, ctx.session.id, modified)
    end

    assert Repo.aggregate(Idea, :count) == 2
  end

  test "closing a private round neither reveals drafts nor prevents later edits or saves", ctx do
    assert {:ok, _} = Ideation.set_private_mode(ctx.facilitator, ctx.project.id, ctx.session.id, 1, true)
    round = active_round(ctx)
    attrs = %{request_key: Ecto.UUID.generate(), round_id: round.id, body: "Private contribution"}
    assert {:ok, idea} = Ideation.create_canvas_idea(ctx.author, ctx.project.id, ctx.session.id, attrs)
    closed = close_round(ctx, round)
    assert closed.configuration.private_mode
    assert closed.configuration_version == 2

    assert {:ok, changed} =
             Ideation.update_canvas_idea(
               ctx.author,
               ctx.project.id,
               ctx.session.id,
               idea.id,
               1,
               edit_attrs(%{body: "Still private after closing"})
             )

    assert changed.round_id == round.id
    refute changed.late_contribution
    assert {:error, :not_found} = Ideation.get_idea(ctx.owner, ctx.project.id, ctx.session.id, idea.id)

    assert {:ok, late} =
             Ideation.create_canvas_idea(ctx.author, ctx.project.id, ctx.session.id, %{
               attrs
               | request_key: Ecto.UUID.generate(),
                 body: "Late private note"
             })

    assert late.late_contribution
    assert late.visibility == :private
    assert {:ok, []} = Ideation.list_ideas(ctx.viewer, ctx.project.id, ctx.session.id, round_id: round.id)
  end

  test "late ideas never alter a frozen reveal manifest and remain private until another explicit reveal", ctx do
    ctx = configure_session(ctx, %{publication_policy: :facilitator_assisted})
    round = active_round(ctx)
    attrs = %{round_id: round.id, configuration_version: 2, publication_consent: :facilitator_assisted}
    early = idea_fixture(ctx, attrs)

    assert {:ok, operation} =
             Ideation.prepare_idea_reveal(ctx.facilitator, ctx.project.id, ctx.session.id, Ecto.UUID.generate())

    close_round(ctx, round)
    late = idea_fixture(ctx, attrs)
    assert late.late_contribution
    assert {:ok, completed} = Ideation.reveal_ideas(ctx.facilitator, ctx.project.id, ctx.session.id, operation.id)
    assert completed.manifest == [%{"idea_id" => early.id, "revision" => 1}]
    assert {:ok, visible} = Ideation.get_idea(ctx.viewer, ctx.project.id, ctx.session.id, early.id)
    assert visible.round_id == round.id
    refute visible.late_contribution
    assert {:error, :not_found} = Ideation.get_idea(ctx.viewer, ctx.project.id, ctx.session.id, late.id)

    assert {:ok, next} =
             Ideation.prepare_idea_reveal(ctx.facilitator, ctx.project.id, ctx.session.id, Ecto.UUID.generate())

    assert next.manifest == [%{"idea_id" => late.id, "revision" => 1}]
  end

  test "round filters and counts apply before pagination and never expose inaccessible drafts", ctx do
    unround = idea_fixture(ctx, %{round_id: nil, visibility: :shared})
    first = active_round(ctx)
    early = idea_fixture(ctx, %{visibility: :shared})
    parked = idea_fixture(ctx, %{visibility: :shared, state: :parked})
    close_round(ctx, first)
    second = active_round(ctx)
    idea_fixture(ctx, %{visibility: :shared})
    idea_fixture(ctx, %{round_id: first.id}, ctx.peer)

    assert {:ok, [^unround]} = Ideation.list_ideas(ctx.author, ctx.project.id, ctx.session.id, round_id: nil)

    assert {:ok, [^parked]} =
             Ideation.list_ideas(ctx.author, ctx.project.id, ctx.session.id, round_id: first.id, state: :all, limit: 1)

    assert {:ok, [^early]} =
             Ideation.list_ideas(ctx.author, ctx.project.id, ctx.session.id,
               round_id: first.id,
               state: :all,
               limit: 1,
               before_id: parked.id
             )

    assert {:ok, %{active: 1, parked: 1, discarded: 0}} =
             Ideation.count_ideas(ctx.viewer, ctx.project.id, ctx.session.id, round_id: first.id)

    assert {:ok, %{active: 1, parked: 0, discarded: 0}} =
             Ideation.count_ideas(ctx.viewer, ctx.project.id, ctx.session.id, round_id: nil)

    assert {:ok, %{active: 3, parked: 1, discarded: 0}} =
             Ideation.count_ideas(ctx.viewer, ctx.project.id, ctx.session.id)

    assert {:ok, other} = Ideation.create_session(ctx.facilitator, ctx.project.id, %{title: "Other session"})
    assert {:error, :round_not_found} = Ideation.list_ideas(ctx.author, ctx.project.id, other.id, round_id: second.id)
    assert {:error, :round_not_found} = Ideation.count_ideas(ctx.author, ctx.project.id, other.id, round_id: second.id)
    assert {:error, :invalid_options} = Ideation.list_ideas(ctx.author, ctx.project.id, ctx.session.id, round_id: "1")
  end

  test "connections and existing source provenance survive round changes without creating derived ideas", ctx do
    first = active_round(ctx)
    original = idea_fixture(ctx)
    close_round(ctx, first)
    second = active_round(ctx)
    later = idea_fixture(ctx)
    stored = Repo.get!(Idea, later.id)
    stored |> Ecto.Changeset.change(source_idea_id: original.id, source_revision: 1) |> Repo.update!()

    assert {:ok, _} = Ideation.connect_ideas(ctx.author, ctx.project.id, ctx.session.id, later.id, original.id, true)
    assert {:ok, connected} = Ideation.get_idea(ctx.author, ctx.project.id, ctx.session.id, later.id)
    assert connected.canvas["links"] == [original.id]
    assert connected.source_idea_id == original.id
    assert connected.source_revision == 1
    assert connected.round_id == second.id
    assert Repo.aggregate(Idea, :count) == 2
  end

  defp active_round(ctx) do
    {:ok, current} = Ideation.get_session(ctx.facilitator, ctx.project.id, ctx.session.id)
    {:ok, prepared} = Ideation.create_round(ctx.facilitator, ctx.project.id, current.id, current.revision, %{})
    {:ok, [round]} = Ideation.list_rounds(ctx.facilitator, ctx.project.id, current.id, limit: 1)
    {:ok, _started} = Ideation.start_round(ctx.facilitator, ctx.project.id, current.id, round.id, prepared.revision)
    round
  end

  defp close_round(ctx, round) do
    {:ok, current} = Ideation.get_session(ctx.facilitator, ctx.project.id, ctx.session.id)
    {:ok, closed} = Ideation.close_round(ctx.facilitator, ctx.project.id, current.id, round.id, current.revision)
    closed
  end
end
