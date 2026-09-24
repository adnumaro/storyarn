defmodule StoryarnWeb.IdeationLive.ContextualDecisionsTest do
  use StoryarnWeb.ConnCase, async: true

  import Ecto.Query, only: [from: 2]
  import Phoenix.LiveViewTest
  import Storyarn.FlowsFixtures
  import Storyarn.IdeationFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Ideation
  alias Storyarn.Repo

  setup do
    ctx = ideation_fixture()
    idea = idea_fixture(ctx, %{visibility: :shared, title: "Keep her", body: "<p>Mara keeps the light</p>"})
    mara = sheet_fixture(ctx.project, %{name: "Mara"})
    Map.merge(ctx, %{project: Repo.preload(ctx.project, :workspace), idea: idea, mara: mara})
  end

  test "the lightbulb counts what is still to apply and the dialog lists the decisions about the content", ctx do
    act = flow_fixture(ctx.project, %{name: "Act 3 endings"})
    {:ok, applying} = register(ctx, [%{type: "sheet", id: ctx.mara.id}])
    {:ok, _proposal} = propose(ctx, [%{type: "sheet", id: ctx.mara.id}])
    {:ok, _elsewhere} = register(ctx, [%{type: "flow", id: act.id}])

    view = open(ctx, ctx.author)
    assert launcher(view)["decisions"] == %{"total" => 2, "toApply" => 1, "name" => "Mara"}
    assert [first, second] = launcher(view)["about"]
    assert first["decision"]["id"] == applying.id
    assert first["toApply"]
    assert first["sessionTitle"] == ctx.session.title
    refute second["toApply"]
    assert launcher(view)["banner"] == nil
  end

  test "Go apply brings the decision under the header, and marking and undo are statements", ctx do
    {:ok, decision} = register(ctx, [%{type: "sheet", id: ctx.mara.id}])
    view = open(ctx, ctx.author, "?decision=#{decision.id}&session=#{ctx.session.id}")
    banner = launcher(view)["banner"]
    assert banner["decision"]["id"] == decision.id
    assert banner["targetKey"] == hd(decision.accepted.targets).key
    assert banner["sessionUrl"] =~ "/brainstorming/#{ctx.session.id}?decision=#{decision.id}"

    render_hook(view, "exploration_decision_declare", declare(ctx, decision, banner["targetKey"], "applied"))
    assert launcher(view)["banner"]["marked"] == %{"state" => "applied"}
    assert launcher(view)["decisions"]["toApply"] == 0
    assert state(ctx, decision) == "applied"

    render_hook(view, "exploration_decision_undo", %{
      source_key: "sheet:#{ctx.mara.id}",
      request_key: Ecto.UUID.generate()
    })

    assert launcher(view)["banner"]["marked"] == nil
    assert launcher(view)["decisions"]["toApply"] == 1
    assert state(ctx, decision) == "not_applied"

    render_hook(view, "exploration_decision_dismiss", %{source_key: "sheet:#{ctx.mara.id}"})
    assert launcher(view)["banner"] == nil
  end

  test "a viewer reads the banner but cannot mark, and other content never shows it", ctx do
    {:ok, decision} = register(ctx, [%{type: "sheet", id: ctx.mara.id}])
    other = sheet_fixture(ctx.project, %{name: "The keeper"})

    view = open(ctx, ctx.viewer, "?decision=#{decision.id}&session=#{ctx.session.id}")
    banner = launcher(view)["banner"]
    refute banner["decision"]["canDeclare"]
    render_hook(view, "exploration_decision_declare", declare(ctx, decision, banner["targetKey"], "applied"))
    assert state(ctx, decision) == "not_applied"

    {:ok, elsewhere, _} =
      live(
        log_in_user(ctx.conn, ctx.author.user),
        "#{base_path(ctx)}/sheets/#{other.id}?decision=#{decision.id}&session=#{ctx.session.id}"
      )

    render_async(elsewhere)
    assert launcher(elsewhere)["banner"] == nil
    assert launcher(elsewhere)["decisions"]["total"] == 0
  end

  test "a pending revision keeps the agreement's work to apply in the count", ctx do
    {:ok, decision} = register(ctx, [%{type: "sheet", id: ctx.mara.id}])
    {:ok, sources} = sources(ctx)

    {:ok, _revised} =
      Ideation.revise_decision(ctx.author, ctx.project.id, ctx.session.id, decision.id, decision.version, %{
        title: "Mara leaves the guild",
        conclusion: "Mara leaves the guild and the harbor.",
        verb: "change",
        targets: [%{type: "sheet", id: ctx.mara.id}],
        responsible_id: ctx.peer.user.id,
        sources: sources,
        request_key: Ecto.UUID.generate()
      })

    view = open(ctx, ctx.author)
    assert launcher(view)["decisions"]["toApply"] == 1
    assert [%{"toApply" => true}] = launcher(view)["about"]
  end

  test "moving to other content drops the banner that arrived with the first", ctx do
    {:ok, decision} = register(ctx, [%{type: "sheet", id: ctx.mara.id}])
    other = sheet_fixture(ctx.project, %{name: "The keeper"})
    view = open(ctx, ctx.author, "?decision=#{decision.id}&session=#{ctx.session.id}")
    assert launcher(view)["banner"]

    render_patch(view, "#{base_path(ctx)}/sheets/#{other.id}")
    render_async(view)
    assert launcher(view)["banner"] == nil
    assert launcher(view)["decisions"]["total"] == 0
  end

  test "another person's step on a decision reaches an editor that is already open", ctx do
    {:ok, decision} = register(ctx, [%{type: "sheet", id: ctx.mara.id}])
    view = open(ctx, ctx.author)
    assert launcher(view)["decisions"]["toApply"] == 1
    [target] = decision.accepted.targets

    {:ok, _} =
      Ideation.declare_decision_application(ctx.peer, ctx.project.id, ctx.session.id, decision.id, 2, %{
        target_key: target.key,
        state: "applied",
        request_key: Ecto.UUID.generate()
      })

    render(view)
    assert launcher(view)["decisions"]["toApply"] == 0
  end

  test "Undo never writes on an agreement accepted after the mark", ctx do
    {:ok, decision} = register(ctx, [%{type: "sheet", id: ctx.mara.id}])
    view = open(ctx, ctx.author, "?decision=#{decision.id}&session=#{ctx.session.id}")
    key = launcher(view)["banner"]["targetKey"]
    render_hook(view, "exploration_decision_declare", declare(ctx, decision, key, "applied"))
    assert launcher(view)["banner"]["marked"] == %{"state" => "applied"}

    {:ok, sources} = sources(ctx)

    {:ok, again} =
      Ideation.revise_decision(ctx.author, ctx.project.id, ctx.session.id, decision.id, decision.version, %{
        title: "Mara leaves the guild",
        conclusion: "Mara leaves the guild at dawn.",
        verb: "change",
        targets: [%{type: "sheet", id: ctx.mara.id}],
        responsible_id: ctx.author.user.id,
        register: true,
        sources: sources,
        request_key: Ecto.UUID.generate()
      })

    render(view)
    assert launcher(view)["banner"]["marked"] == nil

    render_hook(view, "exploration_decision_undo", %{
      source_key: "sheet:#{ctx.mara.id}",
      request_key: Ecto.UUID.generate()
    })

    assert Repo.aggregate(
             from(a in Storyarn.Ideation.Decisions.Application,
               where: a.decision_id == ^decision.id and a.agreement == ^again.accepted_version
             ),
             :count
           ) == 0
  end

  defp declare(ctx, decision, key, state) do
    %{
      source_key: "sheet:#{ctx.mara.id}",
      session_id: ctx.session.id,
      decision_id: decision.id,
      target_key: key,
      state: state,
      request_key: Ecto.UUID.generate()
    }
  end

  defp state(ctx, decision) do
    {:ok, current} = Ideation.get_decision(ctx.author, ctx.project.id, ctx.session.id, decision.id)
    [target] = current.application.targets
    (target.application && target.application.state) || "not_applied"
  end

  defp open(ctx, actor, query \\ "") do
    {:ok, view, _} = live(log_in_user(ctx.conn, actor.user), "#{base_path(ctx)}/sheets/#{ctx.mara.id}#{query}")
    render_async(view)
    view
  end

  defp launcher(view),
    do: LiveVue.Test.get_vue(view, name: "live/shared/ContextualSourceHeader").props["exploration-state"]

  defp register(ctx, targets), do: propose(ctx, targets, %{responsible_id: ctx.author.user.id, register: true})

  defp sources(ctx) do
    with {:ok, sources} <-
           Ideation.preview_decision_sources(ctx.author, ctx.project.id, ctx.session.id, [
             %{type: "idea", id: ctx.idea.id}
           ]),
         do: {:ok, Enum.map(sources, &Map.take(&1, [:type, :id, :version, :identity]))}
  end

  defp propose(ctx, targets, changes \\ %{}) do
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
          targets: targets,
          responsible_id: ctx.peer.user.id,
          sources: Enum.map(sources, &Map.take(&1, [:type, :id, :version, :identity])),
          request_key: Ecto.UUID.generate()
        },
        changes
      )
    )
  end

  defp base_path(ctx), do: "/workspaces/#{ctx.project.workspace.slug}/projects/#{ctx.project.slug}"
end
