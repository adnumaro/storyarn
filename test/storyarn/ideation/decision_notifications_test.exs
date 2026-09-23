defmodule Storyarn.Ideation.DecisionNotificationsTest do
  use Storyarn.DataCase, async: true

  import Storyarn.IdeationFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Ideation
  alias Storyarn.NotificationInbox
  alias Storyarn.Projects
  alias StoryarnWeb.Live.Shared.NotificationHelpers

  setup do
    ctx = ideation_fixture()
    idea = idea_fixture(ctx, %{visibility: :shared, title: "Keep her", body: "<p>Mara keeps the light</p>"})
    Map.merge(ctx, %{idea: idea, mara: sheet_fixture(ctx.project, %{name: "Mara"})})
  end

  test "the responsible person is asked to accept and the proposer hears it was accepted", ctx do
    {:ok, proposed} =
      propose(ctx, %{
        targets: [%{type: "sheet", id: ctx.mara.id}],
        next_action: "Update her sheet",
        next_action_owner_id: ctx.facilitator.user.id
      })

    assert [%{kind: "decision_to_accept", entity_type: "decision", entity_name: title} = asked] =
             NotificationInbox.list_notifications(ctx.peer)

    assert title == ctx.session.title
    assert asked.entity_id == proposed.id
    assert NotificationInbox.list_notifications(ctx.author) == []

    assert {:ok, _} =
             Projects.create_ideation_comment(ctx.owner, ctx.project.id, ctx.session.id, {:decision, proposed.id}, %{
               body: "Does this hold?",
               client_request_id: Ecto.UUID.generate(),
               mention_user_ids: []
             })

    {:ok, accepted} =
      Ideation.accept_decision(
        ctx.peer,
        ctx.project.id,
        ctx.session.id,
        proposed.id,
        proposed.version,
        Ecto.UUID.generate()
      )

    assert ["decision_accepted"] = kinds(ctx.author)
    assert "decision_accepted" in kinds(ctx.owner)
    assert ["decision_next_action"] = kinds(ctx.facilitator)
    refute "decision_accepted" in kinds(ctx.peer)

    [mara] = accepted.application.targets

    assert {:ok, _} =
             Ideation.declare_decision_application(ctx.facilitator, ctx.project.id, ctx.session.id, accepted.id, 2, %{
               target_key: mara.key,
               state: "applied",
               request_key: Ecto.UUID.generate()
             })

    assert "decision_applied" in kinds(ctx.peer)
    assert "decision_applied" in kinds(ctx.author)
    refute "decision_applied" in kinds(ctx.facilitator)
  end

  test "registering tells nobody to accept and a partial mark is not an application", ctx do
    {:ok, registered} =
      propose(ctx, %{responsible_id: ctx.author.user.id, register: true, targets: [%{type: "sheet", id: ctx.mara.id}]})

    assert NotificationInbox.list_notifications(ctx.peer) == []
    [mara] = registered.application.targets

    assert {:ok, _} =
             Ideation.declare_decision_application(ctx.peer, ctx.project.id, ctx.session.id, registered.id, 2, %{
               target_key: mara.key,
               state: "partially_applied",
               request_key: Ecto.UUID.generate()
             })

    assert NotificationInbox.list_notifications(ctx.author) == []
  end

  test "a decision notification links to the project route that opens its session", ctx do
    {:ok, proposed} = propose(ctx, %{})
    %{items: [item]} = NotificationHelpers.client_state(ctx.peer)
    assert item.kind == "decision_to_accept"
    project = Storyarn.Repo.preload(ctx.project, :workspace)

    assert item.href ==
             "/workspaces/#{project.workspace.slug}/projects/#{project.slug}/brainstorming?decision=#{proposed.id}"

    assert {:ok, session_id} = Ideation.get_decision_session_id(ctx.peer, ctx.project.id, proposed.id)
    assert session_id == ctx.session.id
    assert {:error, _} = Ideation.get_decision_session_id(ctx.peer, ctx.project.id, proposed.id + 1_000_000)
  end

  defp kinds(actor), do: actor |> NotificationInbox.list_notifications() |> Enum.map(& &1.kind)

  defp propose(ctx, changes) do
    {:ok, sources} =
      Ideation.preview_decision_sources(ctx.author, ctx.project.id, ctx.session.id, [%{type: "idea", id: ctx.idea.id}])

    Ideation.propose_decision(
      ctx.author,
      ctx.project.id,
      ctx.session.id,
      Map.merge(
        %{
          title: "Mara leaves the guild",
          conclusion: "Mara breaks with the harbor guild.",
          verb: "change",
          targets: [],
          responsible_id: ctx.peer.user.id,
          sources: Enum.map(sources, &Map.take(&1, [:type, :id, :version, :identity])),
          request_key: Ecto.UUID.generate()
        },
        changes
      )
    )
  end
end
