defmodule StoryarnWeb.E2E.IdeationDecisionsTest do
  use PhoenixTest.Playwright.Case, async: false

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

    author = conn |> authenticate(ctx.author.user) |> visit(path(ctx)) |> assert_has("#brainstorming-canvas")
    author = author |> press("#brainstorming-canvas", "1") |> click("#canvas-note-#{idea.id}")
    author = author |> click("#brainstorming-propose-decision") |> assert_has("#decision-proposal-form")

    author =
      author
      |> type("#decision-title", "Keep the ending quiet")
      |> type("#decision-conclusion", "Let the player choose to stay.")
      |> type("#decision-reason", "It resolves the character's promise.")

    # Background controls cannot silently replace an unsaved proposal.
    author =
      author |> click("#brainstorming-decisions-open") |> assert_has("#decision-title", value: "Keep the ending quiet")

    author =
      author
      |> click("#decision-save-proposal")
      |> refute_has("#decision-proposal-form")
      |> refute_has("#decision-accept")

    assert {:ok, %{decisions: [proposed]}} = Ideation.list_decisions(ctx.author, ctx.project.id, ctx.session.id)

    config = context |> Map.take(Config.setup_keys()) |> Config.validate!()
    responsible = config |> Case.new_session(context) |> authenticate(ctx.facilitator.user) |> visit(path(ctx))

    responsible =
      responsible
      |> click("#brainstorming-decisions-open")
      |> click("#decision-open-#{proposed.id}")
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
      |> assert_has("#decision-previous-agreement")
      |> assert_has("#decision-refresh-sources")

    author =
      author
      |> press("#decision-conclusion", "ControlOrMeta+a")
      |> type("#decision-conclusion", "Let the player leave a final note.")

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
      |> click("#decision-history")
      |> assert_has("#brainstorming-decisions-panel", text: "Decision accepted")

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

    browser =
      browser
      |> type("#decision-title", "Loyalty as repair")
      |> type("#decision-conclusion", "Her loyalty comes from regret.")
      |> type("#decision-reason", "It connects the two shared motives.")

    browser =
      browser
      |> click("#decision-add-sources")
      |> type("#decision-source-query", "Loyalty")
      |> click("#decision-source-search")
      |> click("#decision-source-option-idea-#{first.id}")

    browser =
      browser
      |> assert_has("#decision-title", value: "Loyalty as repair")
      |> assert_has("#decision-conclusion", value: "Her loyalty comes from regret.")

    browser =
      browser
      |> click("#decisions-close")
      |> assert_has("[role=dialog]")
      |> click_button("Keep editing")
      |> refute_has("[role=dialog]")

    capture(browser, "decisions-proposal-mobile")
    browser = browser |> click("#decision-save-proposal") |> refute_has("#decision-proposal-form")
    {:ok, %{decisions: [decision]}} = Ideation.list_decisions(ctx.author, ctx.project.id, ctx.session.id)
    assert Enum.map(decision.proposal.sources, & &1.type) == ["group", "idea"]
    capture(browser, "decisions-detail-mobile")
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
