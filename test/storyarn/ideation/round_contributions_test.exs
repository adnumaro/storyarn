defmodule Storyarn.Ideation.RoundContributionsTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.IdeationFixtures

  alias Storyarn.Ideation
  alias Storyarn.Ideation.Ideas.Edit
  alias Storyarn.Ideation.Ideas.Idea

  setup do
    ideation_fixture()
  end

  test "every contribution belongs to a round: omitted takes the one in progress, explicit nil is rejected", ctx do
    round = first_round(ctx)
    implicit = idea_fixture(ctx)
    explicit = idea_fixture(ctx, %{round_id: round.id})
    assert implicit.round_id == round.id
    assert explicit.round_id == round.id
    refute implicit.late_contribution
    refute explicit.late_contribution

    assert {:error, :round_required} =
             Ideation.create_idea(ctx.author, ctx.project.id, ctx.session.id, idea_attrs(%{round_id: nil}))

    assert Repo.aggregate(Idea, :count) == 2
  end

  test "a first save after close retains its captured round and records lateness without moving existing ideas", ctx do
    first = first_round(ctx)
    early = idea_fixture(ctx, %{round_id: first.id})
    {ctx, second} = new_round(ctx)

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

  test "foreign and malformed rounds cannot accept a contribution", ctx do
    round = first_round(ctx)
    assert {:ok, other} = Ideation.create_session(ctx.facilitator, ctx.project.id, %{title: "Other session"})

    assert {:error, :round_not_found} =
             Ideation.create_idea(ctx.author, ctx.project.id, other.id, idea_attrs(%{round_id: round.id}))

    for invalid <- [-1, 0, 1.5, "1", :active, %{}, 9_223_372_036_854_775_808] do
      assert {:error, :invalid_round} =
               Ideation.create_idea(ctx.author, ctx.project.id, ctx.session.id, idea_attrs(%{round_id: invalid}))
    end

    assert Repo.aggregate(Idea, :count) == 0
    assert Repo.aggregate(Edit, :count) == 0
  end

  test "creation replay freezes round assignment and preserves receipts from requests without a round field", ctx do
    first = first_round(ctx)
    legacy_attrs = idea_attrs()
    assert {:ok, legacy} = Ideation.create_idea(ctx.author, ctx.project.id, ctx.session.id, legacy_attrs)
    assert legacy.round_id == first.id
    legacy_receipt = Repo.get_by!(Edit, idea_id: legacy.id, request_key: legacy_attrs.request_key)

    assert legacy_receipt.fingerprint ==
             :crypto.hash(
               :sha256,
               :erlang.term_to_binary(
                 {:ideation_edit_v1, {:create, nil, [body: legacy_attrs.body, configuration_version: 1]}}
               )
             )

    attrs = idea_attrs(%{round_id: first.id})
    assert {:ok, created} = Ideation.create_idea(ctx.author, ctx.project.id, ctx.session.id, attrs)
    {ctx, second} = new_round(ctx)

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
    round = first_round(ctx)
    attrs = %{request_key: Ecto.UUID.generate(), round_id: round.id, body: "Private contribution"}
    assert {:ok, idea} = Ideation.create_canvas_idea(ctx.author, ctx.project.id, ctx.session.id, attrs)
    ctx = close_round(ctx, round)
    assert ctx.session.configuration.private_mode
    assert ctx.session.configuration_version == 2

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
    round = first_round(ctx)
    attrs = %{round_id: round.id, configuration_version: 2, publication_consent: :facilitator_assisted}
    early = idea_fixture(ctx, attrs)

    assert {:ok, operation} =
             Ideation.prepare_idea_reveal(ctx.facilitator, ctx.project.id, ctx.session.id, Ecto.UUID.generate())

    ctx = close_round(ctx, round)
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
    first = first_round(ctx)
    early = idea_fixture(ctx, %{visibility: :shared})
    parked = idea_fixture(ctx, %{visibility: :shared, state: :parked})
    {ctx, second} = new_round(ctx)
    idea_fixture(ctx, %{visibility: :shared})
    idea_fixture(ctx, %{round_id: first.id}, ctx.peer)

    assert {:ok, []} = Ideation.list_ideas(ctx.author, ctx.project.id, ctx.session.id, round_id: nil)

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

    assert {:ok, %{active: 0, parked: 0, discarded: 0}} =
             Ideation.count_ideas(ctx.viewer, ctx.project.id, ctx.session.id, round_id: nil)

    assert {:ok, %{active: 2, parked: 1, discarded: 0}} =
             Ideation.count_ideas(ctx.viewer, ctx.project.id, ctx.session.id)

    assert {:ok, other} = Ideation.create_session(ctx.facilitator, ctx.project.id, %{title: "Other session"})
    assert {:error, :round_not_found} = Ideation.list_ideas(ctx.author, ctx.project.id, other.id, round_id: second.id)
    assert {:error, :round_not_found} = Ideation.count_ideas(ctx.author, ctx.project.id, other.id, round_id: second.id)
    assert {:error, :invalid_options} = Ideation.list_ideas(ctx.author, ctx.project.id, ctx.session.id, round_id: "1")
  end

  test "parked counts for the session tree respect visibility and project boundaries", ctx do
    idea_fixture(ctx, %{visibility: :shared, state: :parked})
    idea_fixture(ctx, %{state: :parked})
    idea_fixture(ctx, %{state: :parked}, ctx.peer)
    idea_fixture(ctx, %{visibility: :shared})
    assert {:ok, other} = Ideation.create_session(ctx.facilitator, ctx.project.id, %{title: "Other session"})
    other_ctx = %{ctx | session: other}
    idea_fixture(other_ctx, %{visibility: :shared, state: :parked}, ctx.peer)
    ids = [ctx.session.id, other.id]

    assert {:ok, counts} = Ideation.count_parked_ideas(ctx.author, ctx.project.id, ids)
    assert counts == %{ctx.session.id => 2, other.id => 1}
    assert {:ok, counts} = Ideation.count_parked_ideas(ctx.viewer, ctx.project.id, ids)
    assert counts == %{ctx.session.id => 1, other.id => 1}
    assert {:ok, %{}} = Ideation.count_parked_ideas(ctx.viewer, ctx.project.id, [])

    stranger = user_scope_fixture()
    assert {:error, _} = Ideation.count_parked_ideas(stranger, ctx.project.id, ids)

    for invalid <- [[-1], ["1"], Enum.to_list(1..201), %{}] do
      assert {:error, :invalid_options} = Ideation.count_parked_ideas(ctx.viewer, ctx.project.id, invalid)
    end

    assert {:ok, _} = Ideation.set_private_mode(ctx.facilitator, ctx.project.id, ctx.session.id, 1, true)
    assert {:ok, counts} = Ideation.count_parked_ideas(ctx.viewer, ctx.project.id, ids)
    assert counts == %{other.id => 1}
  end

  test "parking, unparking, deleting or restoring a parked note wakes the session tree", ctx do
    idea = idea_fixture(ctx, %{visibility: :shared})
    assert :ok = Ideation.subscribe_sessions(ctx.author, ctx.project.id)

    assert {:ok, edited} =
             Ideation.update_idea(
               ctx.author,
               ctx.project.id,
               ctx.session.id,
               idea.id,
               1,
               edit_attrs(%{body: "Same state"})
             )

    refute_receive {:ideation_sessions_changed, _}

    assert {:ok, parked} =
             Ideation.update_idea(
               ctx.author,
               ctx.project.id,
               ctx.session.id,
               idea.id,
               edited.revision,
               edit_attrs(%{state: :parked})
             )

    assert_receive {:ideation_sessions_changed, project_id}
    assert project_id == ctx.project.id

    assert {:ok, deleted} = Ideation.delete_idea(ctx.author, ctx.project.id, ctx.session.id, idea.id, parked.revision)
    assert_receive {:ideation_sessions_changed, _}

    assert {:ok, _} =
             Ideation.restore_idea(
               ctx.author,
               ctx.project.id,
               ctx.session.id,
               idea.id,
               deleted.revision,
               deleted.deleted_at
             )

    assert_receive {:ideation_sessions_changed, _}
    assert {:ok, counts} = Ideation.count_parked_ideas(ctx.viewer, ctx.project.id, [ctx.session.id])
    assert counts == %{ctx.session.id => 1}
  end

  test "notes never rise above their header and a group holds notes of one round only", ctx do
    first = first_round(ctx)
    {ctx, second} = new_round(ctx)
    placed = fn round, y -> %{round_id: round.id, visibility: :shared, canvas: %{"x" => 0, "y" => y}} end

    assert {:error, :outside_band} =
             Ideation.create_idea(ctx.author, ctx.project.id, ctx.session.id, idea_attrs(placed.(first, -5)))

    assert {:error, :outside_band} =
             Ideation.create_idea(ctx.author, ctx.project.id, ctx.session.id, idea_attrs(placed.(second, -1)))

    a = idea_fixture(ctx, placed.(first, 100))
    c = idea_fixture(ctx, placed.(first, 300))
    b = idea_fixture(ctx, placed.(second, 50))
    assert b.canvas["y"] == 50

    move = fn idea, y, version ->
      Ideation.update_idea_canvas(ctx.author, ctx.project.id, ctx.session.id, idea.id, version, %{
        "request_key" => Ecto.UUID.generate(),
        "x" => 40,
        "y" => y
      })
    end

    assert {:error, :outside_band} = move.(a, -1, 0)
    # Bands grow with their content: nothing stops a note below.
    assert {:ok, moved} = move.(a, 550, 0)
    assert moved["y"] == 550

    group = fn ids ->
      Ideation.create_group(ctx.author, ctx.project.id, ctx.session.id, %{
        request_key: Ecto.UUID.generate(),
        idea_ids: ids,
        canvas: %{x: -28, y: 36, width: 600, height: 400}
      })
    end

    assert {:error, :mixed_rounds} = group.([a.id, b.id])
    assert {:ok, grouped} = group.([a.id, c.id])

    shift = fn dy ->
      Ideation.move_group(ctx.author, ctx.project.id, ctx.session.id, grouped.id, grouped.version, %{
        request_key: Ecto.UUID.generate(),
        x: grouped.canvas["x"],
        y: grouped.canvas["y"] + dy,
        member_versions: [%{id: a.id, version: 1}, %{id: c.id, version: 0}]
      })
    end

    assert {:error, :outside_band} = shift.(-600)
    assert {:ok, _} = shift.(-100)
    assert {:ok, lifted} = Ideation.get_idea(ctx.author, ctx.project.id, ctx.session.id, a.id)
    assert lifted.canvas["y"] == 450
  end

  test "connections and existing source provenance survive round changes without creating derived ideas", ctx do
    original = idea_fixture(ctx)
    {ctx, second} = new_round(ctx)
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
end
