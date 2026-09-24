defmodule Storyarn.Ideation.DecisionsAboutTest do
  use Storyarn.DataCase, async: true

  import Storyarn.FlowsFixtures
  import Storyarn.IdeationFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Ideation
  alias Storyarn.Sheets

  setup do
    ctx = ideation_fixture()
    idea = idea_fixture(ctx, %{visibility: :shared, title: "Keep her", body: "<p>Mara keeps the light</p>"})
    Map.merge(ctx, %{idea: idea, mara: sheet_fixture(ctx.project, %{name: "Mara"})})
  end

  test "content finds the decisions that name it and those of the sessions exploring it", ctx do
    act = flow_fixture(ctx.project, %{name: "Act 3 endings"})
    {:ok, named} = propose(ctx, ctx.session, %{targets: [%{type: "sheet", id: ctx.mara.id}]})
    {:ok, _elsewhere} = propose(ctx, ctx.session, %{targets: [%{type: "flow", id: act.id}]})

    {:ok, %{target: target}} = Ideation.get_contextual_brainstorming(ctx.author, ctx.project.id, "sheet", ctx.mara.id)

    {:ok, explored} =
      Ideation.create_contextual_session(ctx.author, ctx.project.id, %{
        title: "Explore Mara",
        target_type: "sheet",
        target_id: target.id,
        target_identity: target.identity,
        target_fingerprint: target.fingerprint,
        request_key: Ecto.UUID.generate()
      })

    idea = idea_fixture(%{ctx | session: explored.session}, %{visibility: :shared, body: "<p>A second path</p>"})
    {:ok, unnamed} = propose(ctx, explored.session, %{targets: []}, idea)

    assert {:ok, about} = Ideation.list_decisions_about(ctx.viewer, ctx.project.id, "sheet", ctx.mara.id)
    assert Enum.sort(Enum.map(about, & &1.decision.id)) == Enum.sort([named.id, unnamed.id])

    by_id = Map.new(about, &{&1.decision.id, &1})
    assert by_id[named.id].target_key == hd(named.proposal.targets).key
    assert by_id[named.id].session.title == ctx.session.title
    assert by_id[unnamed.id].target_key == nil
    assert by_id[unnamed.id].session.title == "Explore Mara"

    assert {:ok, [only]} = Ideation.list_decisions_about(ctx.viewer, ctx.project.id, "flow", act.id)
    refute only.decision.id in [named.id, unnamed.id]
  end

  test "a replaced target does not inherit decisions through a recycled identity", ctx do
    {:ok, _} = propose(ctx, ctx.session, %{targets: [%{type: "sheet", id: ctx.mara.id}]})
    assert {:ok, [_]} = Ideation.list_decisions_about(ctx.viewer, ctx.project.id, "sheet", ctx.mara.id)
    assert {:ok, _} = Sheets.delete_sheet(ctx.author, ctx.mara)
    assert {:error, _} = Ideation.list_decisions_about(ctx.viewer, ctx.project.id, "sheet", ctx.mara.id)

    other = sheet_fixture(ctx.project, %{name: "Another Mara"})
    assert {:ok, []} = Ideation.list_decisions_about(ctx.viewer, ctx.project.id, "sheet", other.id)
  end

  test "the project list groups readable sessions with decisions and outsiders read nothing", ctx do
    {:ok, decision} = propose(ctx, ctx.session, %{targets: [%{type: "sheet", id: ctx.mara.id}]})
    {:ok, _quiet} = Ideation.create_session(ctx.facilitator, ctx.project.id, %{title: "No decisions yet"})

    assert {:ok, [%{session: %{id: session_id}, decisions: [%{id: id}]}]} =
             Ideation.list_project_decisions(ctx.viewer, ctx.project.id)

    assert session_id == ctx.session.id
    assert id == decision.id

    outsider = Storyarn.AccountsFixtures.user_scope_fixture()
    assert {:error, _} = Ideation.list_project_decisions(outsider, ctx.project.id)
    assert {:error, _} = Ideation.list_decisions_about(outsider, ctx.project.id, "sheet", ctx.mara.id)
  end

  defp propose(ctx, session, changes, idea \\ nil) do
    idea = idea || ctx.idea

    {:ok, sources} =
      Ideation.preview_decision_sources(ctx.author, ctx.project.id, session.id, [%{type: "idea", id: idea.id}])

    attrs =
      Map.merge(
        %{
          title: "Choose a direction",
          conclusion: "Keep the original direction",
          verb: "change",
          targets: [],
          responsible_id: ctx.peer.user.id,
          sources: Enum.map(sources, &Map.take(&1, [:type, :id, :version, :identity])),
          request_key: Ecto.UUID.generate()
        },
        changes
      )

    Ideation.propose_decision(ctx.author, ctx.project.id, session.id, attrs)
  end
end
