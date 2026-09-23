defmodule StoryarnWeb.E2E.IdeationDecisionsTest do
  use PhoenixTest.Playwright.Case, async: false

  import Ecto.Query, only: [from: 2]
  import PhoenixTest.Playwright, only: [press: 3, type: 3]
  import Storyarn.IdeationFixtures
  import StoryarnWeb.E2EHelpers

  alias PhoenixTest.Playwright.Case
  alias PhoenixTest.Playwright.Config
  alias Storyarn.Ideation
  alias Storyarn.Repo

  @moduletag :e2e

  setup do
    previous = Application.fetch_env!(:live_vue, :enable_props_diff)
    Application.put_env(:live_vue, :enable_props_diff, true)
    on_exit(fn -> Application.put_env(:live_vue, :enable_props_diff, previous) end)
    :ok
  end

  test "a team proposes from a shared idea and the responsible person accepts a traceable revision",
       %{conn: conn} = context do
    ctx = ideation_fixture()

    idea =
      idea_fixture(ctx, %{title: "A quieter ending", body: "<p>The player chooses to stay.</p>", visibility: :shared})

    facilitator = member_name(ctx, ctx.facilitator)
    author = conn |> authenticate(ctx.author.user) |> visit(path(ctx)) |> assert_has("#brainstorming-canvas")
    author = author |> press("#brainstorming-canvas", "1") |> click("#canvas-note-#{idea.id}")
    author = author |> click("#brainstorming-propose-decision") |> assert_has("#decision-proposal-form")

    author =
      author
      |> type("#decision-conclusion", "Let the player choose to stay. The keeper leaves.")
      |> click("#decision-verb-change")
      |> type("#decision-reason", "It resolves the character's promise.")
      |> assert_has("#decision-title", value: "Let the player choose to stay")
      |> assert_has("#decision-save-proposal", text: "Register decision")

    # Someone else accepts it, so it becomes a proposal.
    author =
      author
      |> click("#decision-owner")
      |> click("[role=option]:has-text('#{facilitator}')")
      |> assert_has("#decision-save-proposal", text: "Propose")

    # Background controls cannot silently replace an unsaved proposal.
    author =
      author
      |> click("#brainstorming-decisions-open")
      |> assert_has("#decision-title", value: "Let the player choose to stay")

    author =
      author
      |> click("#decision-save-proposal")
      |> refute_has("#decision-proposal-form")
      |> refute_has("#decision-accept")

    assert {:ok, [proposed]} = Ideation.list_decisions(ctx.author, ctx.project.id, ctx.session.id)

    config = context |> Map.take(Config.setup_keys()) |> Config.validate!()
    responsible = config |> Case.new_session(context) |> authenticate(ctx.facilitator.user) |> visit(path(ctx))

    responsible =
      responsible
      |> click("#brainstorming-decisions-open")
      |> click("#decision-open-#{proposed.id}")
      |> assert_has("#decision-status", text: "Waiting for you")
      |> click("#decision-accept")
      |> refute_has("#decision-accept")

    author = assert_has(author, "#brainstorming-decisions-panel", text: "Accepted decision")

    assert {:ok, accepted} = Ideation.get_decision(ctx.author, ctx.project.id, ctx.session.id, proposed.id)
    assert accepted.status == :accepted
    assert accepted.accepted.actor_id == ctx.facilitator.user.id

    {:ok, edited} =
      Ideation.update_idea(
        ctx.author,
        ctx.project.id,
        ctx.session.id,
        idea.id,
        idea.revision,
        edit_attrs(%{body: "<p>The player can leave a final note.</p>"})
      )

    publish_idea(ctx, edited)

    author =
      author
      |> click("#decision-revise")
      |> assert_has("#decision-refresh-sources")

    author =
      author
      |> press("#decision-conclusion", "ControlOrMeta+a")
      |> type("#decision-conclusion", "Let the player leave a final note.")
      |> assert_has("#decision-owner-preview", text: "Waiting for #{facilitator} to accept")

    author =
      author
      |> click("#decision-refresh-sources")
      |> assert_has("#decision-conclusion", value: "Let the player leave a final note.")

    capture(author, "decisions-proposal-desktop")
    author = author |> click("#decision-save-proposal") |> assert_has("#decision-previous-agreement")

    assert {:ok, revised} = Ideation.get_decision(ctx.author, ctx.project.id, ctx.session.id, proposed.id)
    assert revised.accepted.number == accepted.accepted.number
    assert hd(revised.proposal.sources).version > hd(accepted.proposal.sources).version

    responsible =
      responsible |> assert_has("#decision-accept") |> click("#decision-accept") |> refute_has("#decision-accept")

    responsible =
      responsible
      |> click("#decision-history summary")
      |> assert_has("#decision-history [data-operation=accept]")

    capture(responsible, "decisions-agreement-desktop")

    viewer = config |> Case.new_session(context) |> authenticate(ctx.viewer.user) |> visit(path(ctx))

    viewer
    |> click("#brainstorming-decisions-open")
    |> refute_has("#decision-new")
    |> click("#decision-open-#{proposed.id}")
    |> refute_has("#decision-accept")
    |> refute_has("#decision-revise")

    author
    |> visit(path(ctx))
    |> click("#brainstorming-decisions-open")
    |> assert_has("#decision-open-#{proposed.id}[data-status='accepted']")
  end

  defp path(ctx) do
    project = Repo.preload(ctx.project, :workspace)
    "/workspaces/#{project.workspace.slug}/projects/#{project.slug}/brainstorming/#{ctx.session.id}"
  end

  @tag browser_context_opts: [viewport: %{width: 390, height: 844}]
  test "a mobile proposal starts from a group and keeps its text while adding a source", %{conn: conn} do
    ctx = ideation_fixture()

    first =
      idea_fixture(ctx, %{visibility: :shared, title: "Loyalty", body: "<p>She stays to protect the village.</p>"})

    second = idea_fixture(ctx, %{visibility: :shared, title: "Regret", body: "<p>She wants to repair the past.</p>"})

    {:ok, group} =
      Ideation.create_group(ctx.author, ctx.project.id, ctx.session.id, %{
        request_key: Ecto.UUID.generate(),
        title: "Guilt and loyalty",
        synthesis: "Her loyalty repairs the harm she caused.",
        idea_ids: [first.id, second.id],
        canvas: %{x: 0, y: 0, width: 650, height: 450}
      })

    browser =
      conn
      |> authenticate(ctx.author.user)
      |> visit(path(ctx))
      |> assert_has("#brainstorming-canvas")
      |> press("#brainstorming-canvas", "1")

    browser =
      browser
      |> click("#canvas-group-#{group.id} > header")
      |> click("#group-propose-decision-#{group.id}")
      |> assert_has("#decision-proposal-form")

    # The group's words start the proposal.
    browser =
      browser
      |> assert_has("#decision-conclusion", value: "Her loyalty repairs the harm she caused.")
      |> assert_has("#decision-title", value: "Guilt and loyalty")
      |> press("#decision-conclusion", "ControlOrMeta+a")
      |> type("#decision-conclusion", "Her loyalty comes from regret.")
      |> click("#decision-verb-keep")

    browser =
      browser
      |> click("#decision-add-sources")
      |> type("#decision-source-query", "Loyalty")
      |> click("#decision-source-search")
      |> click("#decision-source-option-idea-#{first.id}")

    browser =
      browser
      |> assert_has("#decision-title", value: "Guilt and loyalty")
      |> assert_has("#decision-conclusion", value: "Her loyalty comes from regret.")

    browser =
      browser
      |> click("#decisions-close")
      |> assert_has("[role=dialog]")
      |> click_button("Keep editing")
      |> refute_has("[role=dialog]")

    capture(browser, "decisions-proposal-mobile")

    browser =
      browser
      |> assert_has("#decision-save-proposal", text: "Register decision")
      |> click("#decision-save-proposal")
      |> refute_has("#decision-proposal-form")
      |> assert_has("#decision-status", text: "Accepted decision")

    {:ok, [decision]} = Ideation.list_decisions(ctx.author, ctx.project.id, ctx.session.id)
    assert decision.status == :accepted
    assert decision.accepted.verb == "keep"
    assert Enum.map(decision.proposal.sources, & &1.type) == ["group", "idea"]
    capture(browser, "decisions-detail-mobile")
  end

  test "decisions close their band and each one carries its discussion", %{conn: conn} = context do
    ctx = ideation_fixture()

    idea =
      idea_fixture(ctx, %{title: "A quieter ending", body: "<p>The player chooses to stay.</p>", visibility: :shared})

    {:ok, [source]} =
      Ideation.preview_decision_sources(ctx.author, ctx.project.id, ctx.session.id, [%{type: "idea", id: idea.id}])

    {:ok, decision} =
      Ideation.propose_decision(ctx.author, ctx.project.id, ctx.session.id, %{
        title: "Keep the ending quiet",
        conclusion: "Let the player choose to stay.",
        verb: "keep",
        targets: [],
        responsible_id: ctx.author.user.id,
        register: true,
        sources: [Map.take(source, [:type, :id, :version, :identity])],
        request_key: Ecto.UUID.generate()
      })

    author =
      conn
      |> authenticate(ctx.author.user)
      |> visit(path(ctx))
      |> assert_has("#brainstorming-canvas")
      |> press("#brainstorming-canvas", "1")
      |> assert_has("#decision-lane-card-#{decision.id}", text: "Keep the ending quiet")
      |> assert_has("[data-decision-link='#{decision.id}']")

    # Resting on a note that supports a decision shows it.
    {:ok, _} = PlaywrightEx.Frame.hover(author.frame_id, selector: "#canvas-note-#{idea.id}", timeout: 10_000)

    author =
      author
      |> assert_has("[data-decision-hover-card='#{decision.id}']")
      |> click("[data-decision-hover-card='#{decision.id}']")

    author =
      author
      |> assert_has("#decision-status", text: "Accepted decision")
      |> assert_has("#decision-discussion", text: "Discussion")
      |> type("#decision-discussion-comment-body", "Does the keeper still leave?")
      |> click("#decision-discussion-comment-send")
      |> assert_has("#decision-discussion", text: "Does the keeper still leave?")
      |> assert_has("#decision-lane-card-#{decision.id} [data-decision-comments]", text: "1")
      |> refute_has("#brainstorming-comment-popover")

    capture(author, "decisions-discussion-desktop")

    [thread] =
      Repo.all(
        from(t in Storyarn.Projects.Comments.Thread,
          where: t.source_type == "ideation_decision" and t.source_id == ^decision.id
        )
      )

    config = context |> Map.take(Config.setup_keys()) |> Config.validate!()

    config
    |> Case.new_session(context)
    |> authenticate(ctx.peer.user)
    |> visit(path(ctx) <> "?thread=#{thread.id}")
    |> assert_has("#decision-status", text: "Accepted decision")
    |> assert_has("#decision-discussion", text: "Does the keeper still leave?")

    # The keyboard opens a lane card too, and leaving the detail ends its discussion.
    author
    |> click("#decisions-close")
    |> refute_has("#decision-discussion")
    |> press("#decision-lane-card-#{decision.id}", "Enter")
    |> assert_has("#decision-discussion", text: "Does the keeper still leave?")
  end

  test "Go apply opens the content with the decision and marking it is reflected in the decision",
       %{conn: conn} do
    ctx = ideation_fixture()
    mara = Storyarn.SheetsFixtures.sheet_fixture(ctx.project, %{name: "Mara"})

    idea =
      idea_fixture(ctx, %{title: "A quieter ending", body: "<p>The player chooses to stay.</p>", visibility: :shared})

    {:ok, [source]} =
      Ideation.preview_decision_sources(ctx.author, ctx.project.id, ctx.session.id, [%{type: "idea", id: idea.id}])

    {:ok, decision} =
      Ideation.propose_decision(ctx.author, ctx.project.id, ctx.session.id, %{
        title: "Mara stays",
        conclusion: "Mara stays at the lighthouse.",
        verb: "change",
        targets: [%{type: "sheet", id: mara.id}],
        responsible_id: ctx.author.user.id,
        register: true,
        sources: [Map.take(source, [:type, :id, :version, :identity])],
        request_key: Ecto.UUID.generate()
      })

    [target] = decision.accepted.targets

    browser =
      conn
      |> authenticate(ctx.author.user)
      |> visit(path(ctx) <> "?decision=#{decision.id}")
      |> assert_has("#decision-status", text: "1 of 1 to apply")
      |> click("#decision-go-apply-#{target.key}")
      |> assert_has("#decision-banner", text: "Mara stays")
      |> assert_has("#explore-changes-decisions", text: "1")

    capture(browser, "decisions-apply-banner")

    browser
    |> click("#decision-banner-applied")
    |> type("#decision-banner-mark-note", "Her sheet says she stays.")
    |> click("#decision-banner-mark-confirm")
    |> assert_has("#decision-banner", text: "Marked applied")
    |> refute_has("#explore-changes-decisions")

    assert {:ok, current} = Ideation.get_decision(ctx.author, ctx.project.id, ctx.session.id, decision.id)
    assert [%{application: %{state: "applied", note: "Her sheet says she stays."}}] = current.application.targets
  end

  # Fixture members all read "Member"; the responsible person needs a name to be picked.
  defp member_name(_ctx, actor) do
    actor.user |> Ecto.Changeset.change(display_name: "Fern Facilitator") |> Repo.update!()
    "Fern Facilitator"
  end

  defp click(browser, selector) do
    {:ok, _} = PlaywrightEx.Frame.click(browser.frame_id, selector: selector, timeout: 10_000)
    browser
  end

  defp capture(browser, name) do
    {:ok, encoded} = PlaywrightEx.Page.screenshot(browser.page_id, full_page: false, timeout: 10_000)
    File.mkdir_p!("test/tmp/decisions-review")
    File.write!("test/tmp/decisions-review/#{name}.png", Base.decode64!(encoded))
  end
end
