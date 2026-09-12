defmodule Storyarn.Ideation.DecisionsTest do
  use Storyarn.DataCase, async: true

  import Storyarn.IdeationFixtures

  alias Storyarn.Ideation
  alias Storyarn.Ideation.Decisions.Decision
  alias Storyarn.Ideation.Decisions.Revision
  alias Storyarn.Projects.ProjectMembership

  setup do
    ctx = ideation_fixture()
    first = idea_fixture(ctx, %{visibility: :shared, title: "Shared direction", body: "<p>Original basis</p>"})
    second = idea_fixture(ctx, %{visibility: :shared, title: "Other direction", body: "<p>Another basis</p>"}, ctx.peer)
    Map.merge(ctx, %{first: first, second: second})
  end

  test "explicit acceptance freezes an agreement while a revised proposal leaves it in force", ctx do
    attrs = attrs(ctx)
    assert {:ok, proposed} = Ideation.propose_decision(ctx.author, ctx.project.id, ctx.session.id, attrs)
    assert proposed.status == :proposed
    assert proposed.version == 1
    assert proposed.accepted == nil
    refute proposed.can_accept
    assert proposed.proposal.actor_id == ctx.author.user.id
    assert {:ok, responsible_view} = Ideation.get_decision(ctx.peer, ctx.project.id, ctx.session.id, proposed.id)
    assert responsible_view.can_accept

    assert {:ok, accepted} = accept(ctx, proposed)
    assert accepted.status == :accepted
    assert accepted.accepted.number == 2
    assert accepted.accepted.actor_id == ctx.peer.user.id
    assert accepted.accepted.reason == attrs.reason

    revised_attrs = fresh(attrs, %{conclusion: "A revised conclusion", reason: "New evidence"})
    assert {:ok, revised} = revise(ctx, accepted, revised_attrs)
    assert revised.status == :proposed
    assert revised.version == 3
    assert revised.accepted == accepted.accepted
    assert revised.proposal.conclusion == "A revised conclusion"
    assert {:ok, final} = accept(ctx, revised)
    assert final.accepted.number == 4
    assert final.accepted.conclusion == "A revised conclusion"

    assert {:ok, history} = Ideation.decision_history(ctx.viewer, ctx.project.id, ctx.session.id, final.id)
    assert Enum.map(history.revisions, & &1.operation) == ["accept", "revise", "accept", "propose"]
    assert Enum.map(history.revisions, & &1.reason) == ["New evidence", "New evidence", attrs.reason, attrs.reason]
    assert Enum.at(history.revisions, 2).conclusion == attrs.conclusion
  end

  test "owner and facilitator cannot accept another responsible editor's proposal", ctx do
    attrs = attrs(ctx)
    assert {:ok, decision} = Ideation.propose_decision(ctx.author, ctx.project.id, ctx.session.id, attrs)

    for actor <- [ctx.author, ctx.owner, ctx.facilitator] do
      assert {:ok, view} = Ideation.get_decision(actor, ctx.project.id, ctx.session.id, decision.id)
      refute view.can_accept
      assert {:error, :not_decision_responsible} = accept(ctx, decision, actor)
    end

    assert {:error, :ineligible_responsible} =
             Ideation.propose_decision(
               ctx.author,
               ctx.project.id,
               ctx.session.id,
               fresh(attrs, %{responsible_id: ctx.viewer.user.id})
             )

    assert {:error, :unauthorized} = accept(ctx, decision, ctx.viewer)

    membership = Repo.get_by!(ProjectMembership, project_id: ctx.project.id, user_id: ctx.peer.user.id)
    membership |> Ecto.Changeset.change(role: "viewer") |> Repo.update!()
    assert {:error, :unauthorized} = accept(ctx, decision)
    assert {:ok, view} = Ideation.get_decision(ctx.peer, ctx.project.id, ctx.session.id, decision.id)
    refute view.can_accept
    assert Repo.aggregate(Revision, :count) == 1
  end

  test "an editor cannot take responsibility through a text revision", ctx do
    attrs = attrs(ctx)
    assert {:ok, decision} = Ideation.propose_decision(ctx.author, ctx.project.id, ctx.session.id, attrs)
    refute decision.can_assign

    assert {:error, :cannot_assign_responsible} =
             revise(ctx, decision, fresh(attrs, %{responsible_id: ctx.author.user.id}))

    assert {:ok, changed} =
             revise(
               ctx,
               decision,
               fresh(attrs, %{responsible_id: ctx.author.user.id, reason: "Hand over review"}),
               ctx.peer
             )

    assert changed.proposal.responsible_id == ctx.author.user.id
    assert changed.proposal.actor_id == ctx.peer.user.id
    assert changed.status == :proposed
    assert changed.accepted == nil
    assert {:ok, history} = Ideation.decision_history(ctx.owner, ctx.project.id, ctx.session.id, decision.id)
    assert Enum.map(history.revisions, & &1.responsible_id) == [ctx.author.user.id, ctx.peer.user.id]
  end

  test "project owner repairs a deleted responsible user without accepting on their behalf", ctx do
    attrs = attrs(ctx)
    assert {:ok, decision} = Ideation.propose_decision(ctx.author, ctx.project.id, ctx.session.id, attrs)
    Repo.delete!(ctx.peer.user)
    assert {:ok, view} = Ideation.get_decision(ctx.owner, ctx.project.id, ctx.session.id, decision.id)
    assert view.can_assign
    refute view.can_accept
    assert view.proposal.responsible_id == nil

    assert {:ok, repaired} =
             revise(
               ctx,
               decision,
               fresh(attrs, %{responsible_id: ctx.facilitator.user.id, reason: "Replace departed reviewer"}),
               ctx.owner
             )

    assert repaired.status == :proposed
    assert repaired.proposal.responsible_id == ctx.facilitator.user.id
    assert repaired.proposal.actor_id == ctx.owner.user.id
    assert repaired.accepted == nil
    assert {:error, :not_decision_responsible} = accept(ctx, repaired, ctx.owner)
    assert {:ok, _} = accept(ctx, repaired, ctx.facilitator)
  end

  test "source preview and search never read an author's private head or private notes", ctx do
    private = idea_fixture(ctx, %{title: "PRIVATE SECRET", body: "<p>PRIVATE SECRET</p>"})

    assert {:ok, _} =
             Ideation.update_idea(
               ctx.author,
               ctx.project.id,
               ctx.session.id,
               ctx.first.id,
               1,
               edit_attrs(%{title: "PRIVATE HEAD", body: "<p>PRIVATE HEAD</p>"})
             )

    for actor <- [ctx.author, ctx.owner, ctx.viewer] do
      assert {:error, :sources_unavailable} =
               Ideation.preview_decision_sources(actor, ctx.project.id, ctx.session.id, [
                 %{type: "idea", id: private.id}
               ])

      assert {:ok, [preview]} =
               Ideation.preview_decision_sources(actor, ctx.project.id, ctx.session.id, [
                 %{type: "idea", id: ctx.first.id}
               ])

      assert preview.title == "Shared direction"
      assert preview.body == "<p>Original basis</p>"
      assert preview.version == 1

      assert {:ok, %{sources: []}} =
               Ideation.search_decision_sources(actor, ctx.project.id, ctx.session.id, type: "idea", search: "PRIVATE")
    end

    attrs = attrs(ctx)
    forged = update_in(attrs.sources, fn [source] -> [%{source | version: 2}] end)
    assert {:error, :stale_sources} = Ideation.propose_decision(ctx.author, ctx.project.id, ctx.session.id, forged)
    assert Repo.aggregate(Decision, :count) == 0
  end

  test "changed shared sources remain frozen through reason edits and acceptance", ctx do
    attrs = attrs(ctx)
    assert {:ok, decision} = Ideation.propose_decision(ctx.author, ctx.project.id, ctx.session.id, attrs)
    publish_changed_source(ctx)
    assert {:ok, view} = Ideation.get_decision(ctx.peer, ctx.project.id, ctx.session.id, decision.id)
    assert [source] = view.proposal.sources
    assert source.changed
    assert source.current_version == 2
    assert source.version == 1
    assert source.body == "<p>Original basis</p>"
    assert view.can_accept

    assert {:ok, revised} = revise(ctx, decision, fresh(attrs, %{reason: "Clarify without changing our basis"}))
    assert hd(revised.proposal.sources).body == source.body
    assert hd(revised.proposal.sources).version == 1
    assert {:ok, accepted} = accept(ctx, revised)
    assert hd(accepted.accepted.sources).body == source.body
    assert hd(accepted.accepted.sources).changed

    refreshed = attrs(ctx)
    assert {:ok, refreshed_decision} = revise(ctx, accepted, fresh(refreshed, %{reason: "Use the revised source"}))
    assert hd(refreshed_decision.proposal.sources).version == 2
    assert hd(refreshed_decision.accepted.sources).version == 1
  end

  test "new proposals reject stale source previews and source identity replacements", ctx do
    attrs = attrs(ctx)
    publish_changed_source(ctx)
    assert {:error, :stale_sources} = Ideation.propose_decision(ctx.author, ctx.project.id, ctx.session.id, attrs)
    current = attrs(ctx)
    forged = update_in(current.sources, fn [source] -> [%{source | identity: Ecto.UUID.generate()}] end)

    assert {:error, :sources_unavailable} =
             Ideation.propose_decision(ctx.author, ctx.project.id, ctx.session.id, forged)

    assert Repo.aggregate(Decision, :count) == 0
  end

  test "missing sources redact every historical preview and prevent acceptance", ctx do
    attrs = attrs(ctx)
    assert {:ok, decision} = Ideation.propose_decision(ctx.author, ctx.project.id, ctx.session.id, attrs)
    assert {:ok, _} = Ideation.delete_idea(ctx.author, ctx.project.id, ctx.session.id, ctx.first.id, 1)
    assert {:error, :sources_unavailable} = accept(ctx, decision)
    assert {:ok, view} = Ideation.get_decision(ctx.viewer, ctx.project.id, ctx.session.id, decision.id)
    assert view.proposal.conclusion == attrs.conclusion
    assert [source] = view.proposal.sources
    refute source.available
    assert source.id == nil
    assert source.identity == hd(attrs.sources).identity
    assert source.title == nil
    assert source.body == nil
    assert source.author_id == nil
    refute view.can_accept
    assert {:ok, history} = Ideation.decision_history(ctx.viewer, ctx.project.id, ctx.session.id, decision.id)
    refute Jason.encode!(history) =~ "Original basis"
  end

  test "shared groups freeze their own synthesis and retained version without publishing notes", ctx do
    {:ok, group} =
      Ideation.create_group(ctx.author, ctx.project.id, ctx.session.id, %{
        request_key: Ecto.UUID.generate(),
        title: "Group basis",
        synthesis: "Original synthesis",
        idea_ids: [ctx.first.id, ctx.second.id],
        canvas: %{x: 0, y: 0, width: 650, height: 450}
      })

    assert {:ok, [source]} =
             Ideation.preview_decision_sources(ctx.author, ctx.project.id, ctx.session.id, [
               %{type: "group", id: group.id}
             ])

    attrs = attrs(ctx, [source])
    assert {:ok, decision} = Ideation.propose_decision(ctx.author, ctx.project.id, ctx.session.id, attrs)

    assert {:ok, _} =
             Ideation.update_group(
               ctx.peer,
               ctx.project.id,
               ctx.session.id,
               group.id,
               1,
               edit_attrs(%{synthesis: "Later synthesis"})
             )

    assert {:ok, accepted} = accept(ctx, decision)
    assert hd(accepted.accepted.sources).body == "Original synthesis"
    assert hd(accepted.accepted.sources).current_version == 2
    assert hd(accepted.accepted.sources).changed
  end

  test "request identities replay without writing, while changed payloads and stale versions fail", ctx do
    attrs = attrs(ctx)
    assert {:ok, proposed} = Ideation.propose_decision(ctx.author, ctx.project.id, ctx.session.id, attrs)
    assert {:ok, ^proposed} = Ideation.propose_decision(ctx.author, ctx.project.id, ctx.session.id, attrs)

    assert {:error, :idempotency_conflict} =
             Ideation.propose_decision(ctx.author, ctx.project.id, ctx.session.id, %{attrs | reason: "Different reason"})

    key = Ecto.UUID.generate()
    assert {:ok, accepted} = Ideation.accept_decision(ctx.peer, ctx.project.id, ctx.session.id, proposed.id, 1, key)
    assert {:ok, ^accepted} = Ideation.accept_decision(ctx.peer, ctx.project.id, ctx.session.id, proposed.id, 1, key)
    assert {:error, :already_accepted} = accept(ctx, accepted)
    assert {:error, :stale_decision} = revise(ctx, proposed, fresh(attrs))

    revised_attrs = fresh(attrs, %{reason: "New proposal"})
    assert {:ok, revised} = revise(ctx, accepted, revised_attrs)
    assert {:ok, ^revised} = revise(ctx, accepted, revised_attrs)

    assert {:ok, retried_accept} =
             Ideation.accept_decision(ctx.peer, ctx.project.id, ctx.session.id, proposed.id, 1, key)

    assert retried_accept.status == :proposed
    assert retried_accept.accepted.number == 2
    assert Repo.aggregate(Decision, :count) == 1
    assert Repo.aggregate(Revision, :count) == 3
  end

  test "private mode, archival and revoked access fence writes and private reads", ctx do
    attrs = attrs(ctx)
    assert {:ok, decision} = Ideation.propose_decision(ctx.author, ctx.project.id, ctx.session.id, attrs)
    assert {:ok, session} = Ideation.get_session(ctx.facilitator, ctx.project.id, ctx.session.id)
    assert {:ok, _} = Ideation.set_private_mode(ctx.facilitator, ctx.project.id, ctx.session.id, session.revision, true)

    for actor <- [ctx.author, ctx.owner, ctx.viewer] do
      assert {:error, :private_mode} = Ideation.get_decision(actor, ctx.project.id, ctx.session.id, decision.id)
      assert {:error, :private_mode} = Ideation.list_decisions(actor, ctx.project.id, ctx.session.id)
      assert {:error, :private_mode} = Ideation.decision_history(actor, ctx.project.id, ctx.session.id, decision.id)
    end

    assert {:error, :private_mode} = accept(ctx, decision)
    assert {:ok, private} = Ideation.get_session(ctx.facilitator, ctx.project.id, ctx.session.id)

    assert {:ok, _} =
             Ideation.set_private_mode(ctx.facilitator, ctx.project.id, ctx.session.id, private.revision, false)

    assert {:ok, public} = Ideation.get_session(ctx.facilitator, ctx.project.id, ctx.session.id)
    assert {:ok, _} = Ideation.archive_session(ctx.facilitator, ctx.project.id, ctx.session.id, public.revision)
    assert {:error, :session_archived} = accept(ctx, decision)
    assert {:ok, archived} = Ideation.get_decision(ctx.viewer, ctx.project.id, ctx.session.id, decision.id)
    refute archived.can_revise

    Repo.delete_all(
      from m in ProjectMembership, where: m.project_id == ^ctx.project.id and m.user_id == ^ctx.author.user.id
    )

    assert {:error, _} = Ideation.get_decision(ctx.author, ctx.project.id, ctx.session.id, decision.id)
  end

  test "lists, history and source search retain bounded cursors", ctx do
    attrs = attrs(ctx)

    decisions =
      for number <- 1..3 do
        {:ok, decision} =
          Ideation.propose_decision(
            ctx.author,
            ctx.project.id,
            ctx.session.id,
            fresh(attrs, %{title: "Decision #{number}"})
          )

        decision
      end

    assert {:ok, first} = Ideation.list_decisions(ctx.viewer, ctx.project.id, ctx.session.id, limit: 2)
    expected_ids = decisions |> Enum.reverse() |> Enum.take(2) |> Enum.map(& &1.id)
    assert Enum.map(first.decisions, & &1.id) == expected_ids

    assert {:ok, %{decisions: [last], next_cursor: nil}} =
             Ideation.list_decisions(ctx.viewer, ctx.project.id, ctx.session.id, limit: 2, before_id: first.next_cursor)

    assert last.id == hd(decisions).id

    assert {:ok, accepted} = accept(ctx, last)
    assert {:ok, history} = Ideation.decision_history(ctx.viewer, ctx.project.id, ctx.session.id, accepted.id, limit: 1)
    assert history.next_cursor == 2

    assert {:ok, %{revisions: [%{number: 1}], next_cursor: nil}} =
             Ideation.decision_history(ctx.viewer, ctx.project.id, ctx.session.id, accepted.id, before_id: 2)

    assert {:ok, sources} = Ideation.search_decision_sources(ctx.viewer, ctx.project.id, ctx.session.id, limit: 1)
    assert length(sources.sources) == 1
    assert sources.next_cursor == ctx.second.id

    assert {:ok, %{sources: [%{id: id}], next_cursor: nil}} =
             Ideation.search_decision_sources(ctx.viewer, ctx.project.id, ctx.session.id,
               limit: 1,
               before_id: sources.next_cursor
             )

    assert id == ctx.first.id

    assert {:error, :invalid_pagination} =
             Ideation.list_decisions(ctx.viewer, ctx.project.id, ctx.session.id, limit: 51)

    assert {:error, :invalid_decision_sources} =
             Ideation.propose_decision(ctx.author, ctx.project.id, ctx.session.id, %{attrs | sources: []})
  end

  test "plaintext is encrypted at rest and failed writes or retries send no invalidation", ctx do
    assert :ok = Ideation.subscribe_ideas(ctx.peer, ctx.project.id, ctx.session.id)
    session_id = ctx.session.id
    attrs = attrs(ctx)
    assert {:ok, _} = Ideation.propose_decision(ctx.author, ctx.project.id, session_id, attrs)
    assert_receive {:ideation_decisions_changed, ^session_id}
    assert {:ok, _} = Ideation.propose_decision(ctx.author, ctx.project.id, session_id, attrs)
    refute_receive {:ideation_decisions_changed, ^session_id}

    assert {:error, :invalid_decision} =
             Ideation.propose_decision(ctx.author, ctx.project.id, session_id, fresh(attrs, %{conclusion: ""}))

    refute_receive {:ideation_decisions_changed, ^session_id}

    raw = Repo.one!(from r in "ideation_decision_revisions", where: r.session_id == ^session_id, select: r.conclusion)
    assert is_binary(raw)
    assert :binary.match(raw, attrs.conclusion) == :nomatch

    assert {:error, :decision_requires_outer_transaction} =
             Repo.transact(fn -> Ideation.propose_decision(ctx.author, ctx.project.id, session_id, fresh(attrs)) end)

    refute_receive {:ideation_decisions_changed, ^session_id}
  end

  defp attrs(ctx, sources \\ nil) do
    sources =
      sources ||
        elem(
          Ideation.preview_decision_sources(ctx.author, ctx.project.id, ctx.session.id, [
            %{type: "idea", id: ctx.first.id}
          ]),
          1
        )

    %{
      title: "Choose a direction",
      conclusion: "Keep the original direction",
      reason: "It supports the intended character arc",
      responsible_id: ctx.peer.user.id,
      sources: Enum.map(sources, &Map.take(&1, [:type, :id, :version, :identity])),
      request_key: Ecto.UUID.generate()
    }
  end

  defp fresh(attrs, changes \\ %{}), do: attrs |> Map.merge(changes) |> Map.put(:request_key, Ecto.UUID.generate())

  defp accept(ctx, decision, actor \\ nil) do
    Ideation.accept_decision(
      actor || ctx.peer,
      ctx.project.id,
      ctx.session.id,
      decision.id,
      decision.version,
      Ecto.UUID.generate()
    )
  end

  defp revise(ctx, decision, attrs, actor \\ nil) do
    Ideation.revise_decision(actor || ctx.author, ctx.project.id, ctx.session.id, decision.id, decision.version, attrs)
  end

  defp publish_changed_source(ctx) do
    {:ok, changed} =
      Ideation.update_idea(
        ctx.author,
        ctx.project.id,
        ctx.session.id,
        ctx.first.id,
        1,
        edit_attrs(%{body: "<p>New shared basis</p>"})
      )

    publish_idea(ctx, changed)
  end
end
