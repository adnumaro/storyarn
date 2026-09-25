defmodule Storyarn.Ideation.DecisionNotificationsTest do
  use Storyarn.DataCase, async: true

  import Ecto.Query, only: [from: 2]
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

  test "a request to accept stays unread until the decision stops waiting for it", ctx do
    {:ok, proposed} = propose(ctx, %{})
    assert [%{read_at: nil}] = requests(ctx.peer)
    assert :ok = Storyarn.Platform.subscribe_notifications(ctx.peer)

    # A revision settles the earlier request and asks again.
    {:ok, revised} =
      Ideation.revise_decision(ctx.author, ctx.project.id, ctx.session.id, proposed.id, proposed.version, %{
        title: "Mara leaves the guild",
        conclusion: "Mara breaks with the guild before the storm.",
        verb: "change",
        targets: [],
        responsible_id: ctx.peer.user.id,
        sources: Enum.map(proposed.proposal.sources, &Map.take(&1, [:type, :id, :version, :identity])),
        request_key: Ecto.UUID.generate()
      })

    assert_receive :notifications_changed
    assert [%{read_at: nil}, %{read_at: %DateTime{}}] = requests(ctx.peer)

    {:ok, _} =
      Ideation.accept_decision(
        ctx.peer,
        ctx.project.id,
        ctx.session.id,
        revised.id,
        revised.version,
        Ecto.UUID.generate()
      )

    assert_receive :notifications_changed
    assert Enum.all?(requests(ctx.peer), &match?(%DateTime{}, &1.read_at))

    {:ok, other} = propose(ctx, %{title: "Another ending"})
    assert Enum.any?(requests(ctx.peer), &(&1.entity_id == other.id and is_nil(&1.read_at)))

    {:ok, _} =
      Ideation.withdraw_decision(
        ctx.author,
        ctx.project.id,
        ctx.session.id,
        other.id,
        other.version,
        Ecto.UUID.generate()
      )

    assert Enum.all?(requests(ctx.peer), &match?(%DateTime{}, &1.read_at))
  end

  test "a decision notification carries the reader's compact card and one action", ctx do
    keeper = sheet_fixture(ctx.project, %{name: "The keeper"})

    {:ok, proposed} =
      propose(ctx, %{
        targets: [%{type: "sheet", id: ctx.mara.id}, %{type: "sheet", id: keeper.id}],
        next_action: "Update both sheets",
        next_action_owner_id: ctx.facilitator.user.id
      })

    project = Storyarn.Repo.preload(ctx.project, :workspace)
    base = "/workspaces/#{project.workspace.slug}/projects/#{project.slug}"

    %{items: [asked]} = NotificationHelpers.client_state(ctx.peer)
    assert %{type: "decision", data: %{decision: card, action: open, sessionName: session_name}} = asked.attachment
    assert card.canAccept
    assert card.proposal.title == "Mara leaves the guild"
    assert session_name == ctx.session.title
    assert open == %{kind: "open", href: "#{base}/brainstorming/#{ctx.session.id}?decision=#{proposed.id}"}

    {:ok, accepted} =
      Ideation.accept_decision(
        ctx.peer,
        ctx.project.id,
        ctx.session.id,
        proposed.id,
        proposed.version,
        Ecto.UUID.generate()
      )

    [mara, _keeper] = accepted.application.targets

    %{items: [next]} = NotificationHelpers.client_state(ctx.facilitator)
    assert next.kind == "decision_next_action"
    assert next.attachment.data.target == "Mara"
    assert next.attachment.data.decision.application.pending == 2

    assert next.attachment.data.action == %{
             kind: "apply",
             href: "#{base}/sheets/#{ctx.mara.id}?decision=#{proposed.id}&session=#{ctx.session.id}"
           }

    assert {:ok, _} =
             Ideation.declare_decision_application(ctx.facilitator, ctx.project.id, ctx.session.id, accepted.id, 2, %{
               target_key: mara.key,
               state: "applied",
               request_key: Ecto.UUID.generate()
             })

    applied = Enum.find(NotificationHelpers.client_state(ctx.author).items, &(&1.kind == "decision_applied"))
    assert applied.attachment.data.target == "Mara"
    assert applied.attachment.data.action.kind == "open"

    # The next action now points at what is still pending.
    %{items: [next]} = NotificationHelpers.client_state(ctx.facilitator)
    assert next.attachment.data.target == "The keeper"

    # A reader who can no longer see the decision keeps only the sentence.
    Storyarn.Repo.update_all(from(s in "ideation_sessions", where: s.id == ^ctx.session.id),
      set: [deleted_at: Storyarn.Platform.Shared.TimeHelpers.now()]
    )

    %{items: items} = NotificationHelpers.client_state(ctx.author)
    assert Enum.all?(items, &is_nil(&1.attachment))
    assert Enum.all?(items, &(&1.kind in ~w(decision_accepted decision_applied)))
  end

  test "superseding a decision settles the request its pending revision waited on", ctx do
    {:ok, earlier} = propose(ctx, %{})

    {:ok, agreed} =
      Ideation.accept_decision(
        ctx.peer,
        ctx.project.id,
        ctx.session.id,
        earlier.id,
        earlier.version,
        Ecto.UUID.generate()
      )

    {:ok, pending} =
      Ideation.revise_decision(ctx.author, ctx.project.id, ctx.session.id, agreed.id, agreed.version, %{
        title: "Mara leaves the guild",
        conclusion: "Mara leaves later.",
        verb: "change",
        targets: [],
        responsible_id: ctx.peer.user.id,
        sources: Enum.map(agreed.accepted.sources, &Map.take(&1, [:type, :id, :version, :identity])),
        request_key: Ecto.UUID.generate()
      })

    assert Enum.any?(requests(ctx.peer), &(&1.entity_id == pending.id and is_nil(&1.read_at)))

    {:ok, replacement} = propose(ctx, %{title: "Mara stays", replaces_id: earlier.id})

    {:ok, accepted} =
      Ideation.accept_decision(
        ctx.peer,
        ctx.project.id,
        ctx.session.id,
        replacement.id,
        replacement.version,
        Ecto.UUID.generate()
      )

    assert accepted.supersedes.id == earlier.id
    assert Enum.all?(requests(ctx.peer), &match?(%DateTime{}, &1.read_at))
  end

  test "each applied notification names the content its own declaration marked", ctx do
    keeper = sheet_fixture(ctx.project, %{name: "The keeper"})

    {:ok, proposed} =
      propose(ctx, %{targets: [%{type: "sheet", id: ctx.mara.id}, %{type: "sheet", id: keeper.id}]})

    {:ok, accepted} =
      Ideation.accept_decision(
        ctx.peer,
        ctx.project.id,
        ctx.session.id,
        proposed.id,
        proposed.version,
        Ecto.UUID.generate()
      )

    [mara, keeper_target] = accepted.application.targets
    declare(ctx, accepted, mara, "applied")
    declare(ctx, accepted, keeper_target, "applied")
    assert applied_targets(ctx.author) == ["The keeper", "Mara"]

    # Changing one declaration later does not rewrite what earlier notifications said.
    declare(ctx, accepted, mara, "partially_applied")
    assert applied_targets(ctx.author) == ["The keeper", "Mara"]
  end

  test "Go apply is offered only while the reader can still declare", ctx do
    {:ok, proposed} =
      propose(ctx, %{
        targets: [%{type: "sheet", id: ctx.mara.id}],
        next_action: "Schedule the playtest",
        next_action_owner_id: ctx.facilitator.user.id
      })

    {:ok, _} =
      Ideation.accept_decision(
        ctx.peer,
        ctx.project.id,
        ctx.session.id,
        proposed.id,
        proposed.version,
        Ecto.UUID.generate()
      )

    [next] = NotificationHelpers.client_state(ctx.facilitator).items
    assert next.attachment.data.action.kind == "apply"
    assert next.attachment.data.decision.accepted.nextAction.text == "Schedule the playtest"

    {:ok, replacement} = propose(ctx, %{title: "Mara stays", replaces_id: proposed.id})

    {:ok, _} =
      Ideation.accept_decision(
        ctx.peer,
        ctx.project.id,
        ctx.session.id,
        replacement.id,
        replacement.version,
        Ecto.UUID.generate()
      )

    next = Enum.find(NotificationHelpers.client_state(ctx.facilitator).items, &(&1.kind == "decision_next_action"))
    assert next.attachment.data.decision.status == :superseded
    assert next.attachment.data.action.kind == "open"
  end

  test "reading the inbox costs the same for one decision or several of a session", ctx do
    {:ok, _} = propose(ctx, %{})
    one = count_queries(fn -> NotificationHelpers.client_state(ctx.peer) end)

    for n <- 1..4, do: {:ok, _} = propose(ctx, %{title: "Ending #{n}"})
    %{items: items} = NotificationHelpers.client_state(ctx.peer)
    assert length(items) == 5 and Enum.all?(items, & &1.attachment)
    five = count_queries(fn -> NotificationHelpers.client_state(ctx.peer) end)

    assert five - one <= 2, "one decision: #{one} queries, five: #{five}"
  end

  defp declare(ctx, decision, target, state) do
    {:ok, _} =
      Ideation.declare_decision_application(ctx.facilitator, ctx.project.id, ctx.session.id, decision.id, 2, %{
        target_key: target.key,
        state: state,
        request_key: Ecto.UUID.generate()
      })
  end

  defp applied_targets(actor) do
    actor
    |> NotificationHelpers.client_state()
    |> Map.fetch!(:items)
    |> Enum.filter(&(&1.kind == "decision_applied"))
    |> Enum.map(& &1.attachment.data.target)
  end

  defp count_queries(fun) do
    ref = make_ref()
    parent = self()
    handler = "count-queries-#{inspect(ref)}"

    :telemetry.attach(handler, [:storyarn, :repo, :query], fn _, _, _, _ -> send(parent, {ref, :query}) end, nil)
    fun.()
    :telemetry.detach(handler)
    drain(ref, 0)
  end

  defp drain(ref, count) do
    receive do
      {^ref, :query} -> drain(ref, count + 1)
    after
      0 -> count
    end
  end

  defp requests(actor) do
    actor
    |> NotificationInbox.list_notifications()
    |> Enum.filter(&(&1.kind == "decision_to_accept"))
    |> Enum.sort_by(& &1.id, :desc)
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
