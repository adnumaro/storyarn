defmodule StoryarnWeb.E2E.ContextualExplorationsTest do
  use PhoenixTest.Playwright.Case, async: false

  import Ecto.Query
  import Storyarn.FlowsFixtures
  import Storyarn.IdeationFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.SheetsFixtures
  import StoryarnWeb.E2EHelpers

  alias Storyarn.Ideation
  alias Storyarn.Projects.Project
  alias Storyarn.Repo
  alias Storyarn.Sheets

  @moduletag :e2e

  for source_type <- ~w(sheet flow scene) do
    @source_type source_type

    test "#{source_type} creates an exploration, returns to its source and resumes the same session", %{conn: conn} do
      ctx = context()
      source = source_fixture(@source_type, ctx.project)
      path = source_path(ctx, @source_type, source.id)
      title = "Alternatives for #{source.name}"
      objective = "Explore a different motivation without changing the current design."

      browser =
        conn
        |> authenticate(ctx.author.user)
        |> visit(path)
        |> assert_has("#explore-changes", timeout: 20_000)
        |> assert_has("##{@source_type}-comments-toggle", timeout: 20_000)
        |> click("#explore-changes")
        |> assert_has("#exploration-dialog", text: source.name)
        |> assert_has("#exploration-dialog", text: source.description)
        |> fill_in("#exploration-title", "Title", with: title)
        |> fill_in("#exploration-objective", "What would you like to explore? (optional)", with: objective)
        |> click("#exploration-create")
        |> assert_has("#brainstorming-canvas", timeout: 20_000)
        |> assert_has("#brainstorming-origins", text: source.name)
        |> assert_has("#brainstorming-session-title", text: title)

      assert {:ok, sessions} = Ideation.list_sessions(ctx.author, ctx.project.id)
      assert length(sessions) == 2
      created = Enum.find(sessions, &(&1.title == title))
      assert created
      assert created.objective == objective
      reference = origin(ctx, created.id)
      assert reference.target_type == @source_type
      assert reference.target_id == source.id
      assert reference.base["overview"]["description"] == source.description

      browser
      |> assert_path(board_path(ctx, created.id))
      |> assert_has("#brainstorming-origin-#{reference.id}[data-status=current]")
      |> click("#brainstorming-origin-return-#{reference.id}")
      |> assert_path(path)
      |> assert_has("#explore-changes", timeout: 20_000)
      |> click("#explore-changes")
      |> assert_has("#exploration-resume-#{created.id}")
      |> click("#exploration-resume-#{created.id}")
      |> assert_path(board_path(ctx, created.id))
      |> assert_has("#brainstorming-origin-#{reference.id}", timeout: 20_000)

      assert {:ok, after_resume} = Ideation.list_sessions(ctx.author, ctx.project.id)
      assert length(after_resume) == 2
      unchanged = Repo.get!(source.__struct__, source.id)
      assert unchanged.name == source.name
      assert unchanged.description == source.description
    end
  end

  test "linking an existing exploration preserves its contributions and offers it for resuming", %{conn: conn} do
    ctx = context()
    source = source_fixture("sheet", ctx.project)
    idea = idea_fixture(ctx, %{body: "<p>Keep the open ending.</p>", visibility: :shared})
    path = source_path(ctx, "sheet", source.id)

    browser =
      conn
      |> authenticate(ctx.author.user)
      |> visit(path)
      |> assert_has("#explore-changes", timeout: 20_000)
      |> click("#explore-changes")
      |> click("#exploration-link-existing")
      |> fill_in("#exploration-search-query", "Search explorations", with: ctx.session.title)
      |> click("#exploration-search")
      |> assert_has("#exploration-link-#{ctx.session.id}")
      |> click("#exploration-link-#{ctx.session.id}")
      |> assert_path(board_path(ctx, ctx.session.id))
      |> assert_has("#canvas-note-#{idea.id}", text: "Keep the open ending.", timeout: 20_000)

    reference = origin(ctx, ctx.session.id)

    browser
    |> assert_has("#brainstorming-origin-#{reference.id}")
    |> click("#brainstorming-origin-return-#{reference.id}")
    |> assert_path(path)
    |> assert_has("#explore-changes", timeout: 20_000)
    |> click("#explore-changes")
    |> assert_has("#exploration-resume-#{ctx.session.id}", count: 1)

    assert {:ok, [%{id: session_id}]} = Ideation.list_sessions(ctx.author, ctx.project.id)
    assert session_id == ctx.session.id
  end

  test "changed and deleted origins are distinguished without rewriting or exposing saved context", %{conn: conn} do
    ctx = context()
    sheet = source_fixture("sheet", ctx.project)
    reference = add_origin(ctx, sheet)
    path = board_path(ctx, ctx.session.id) <> "?context_reference=#{reference.id}"
    selector = "#brainstorming-origin-#{reference.id}"

    browser =
      conn
      |> authenticate(ctx.author.user)
      |> visit(path)
      |> assert_has("#{selector}[data-status=current]", text: sheet.name, timeout: 20_000)

    assert {:ok, updated} = Sheets.update_sheet(sheet, %{name: "Revised character"})

    browser =
      browser
      |> visit(path)
      |> assert_has("#{selector}[data-status=changed]", timeout: 20_000)
      |> assert_has("#brainstorming-origin-return-#{reference.id}")

    changed = origin(ctx, ctx.session.id)
    assert changed.base == reference.base
    assert changed.current.name == "Revised character"
    assert {:ok, _} = Sheets.delete_sheet(ctx.author, updated)

    browser
    |> visit(path)
    |> assert_has("#{selector}[data-status=unavailable]", timeout: 20_000)
    |> assert_has("#brainstorming-origin-return-#{reference.id}[disabled]")
    |> refute_has("#brainstorming-origins", text: sheet.name)
    |> refute_has("#brainstorming-origins", text: "Revised character")

    assert %{status: "unavailable", base: nil, current: nil} = origin(ctx, ctx.session.id)
  end

  test "a recovered exploration resumes through its restored reference and returns to the correct source", %{conn: conn} do
    ctx = context()
    sheet = source_fixture("sheet", ctx.project)
    path = source_path(ctx, "sheet", sheet.id)

    browser =
      conn
      |> authenticate(ctx.author.user)
      |> visit(path)
      |> assert_has("#explore-changes", timeout: 20_000)
      |> click("#explore-changes")
      |> fill_in("#exploration-title", "Title", with: "Recovered exploration")
      |> click("#exploration-create")
      |> assert_has("#brainstorming-origins", text: sheet.name, timeout: 20_000)

    assert {:ok, sessions} = Ideation.list_sessions(ctx.author, ctx.project.id)
    created = Enum.find(sessions, &(&1.title == "Recovered exploration"))
    assert created
    original = origin(ctx, created.id)

    assert {:ok, capsule} =
             Repo.transact(fn ->
               lock_project(ctx.project.id)
               Ideation.capture_recovery(ctx.project.id)
             end)

    browser = browser |> visit(path) |> assert_has("#explore-changes", timeout: 20_000)

    # Remove this fixture's session so recovery must allocate new session and
    # reference identities, rather than passing by reusing the old live rows.
    Repo.delete!(created)

    assert {:ok, restored} =
             Repo.transact(fn ->
               lock_project(ctx.project.id)
               Ideation.restore_recovery(ctx.project.id, capsule)
             end)

    session_id = restored["sessions"][created.id]
    reference_id = restored["references"][original.id]
    assert session_id != created.id
    assert reference_id != original.id
    reference = origin(ctx, session_id)
    assert reference.id == reference_id
    assert reference.target_id == sheet.id
    assert reference.base == original.base

    browser
    |> visit(path)
    |> assert_has("#explore-changes", timeout: 20_000)
    |> click("#explore-changes")
    |> refute_has("#exploration-resume-#{created.id}")
    |> assert_has("#exploration-resume-#{session_id}")
    |> click("#exploration-resume-#{session_id}")
    |> assert_path(board_path(ctx, session_id))
    |> assert_has("#brainstorming-origin-#{reference_id}[data-status=current]", text: sheet.name, timeout: 20_000)
    |> click("#brainstorming-origin-return-#{reference_id}")
    |> assert_path(path)
    |> assert_has("#explore-changes", timeout: 20_000)
  end

  test "viewers can resume a linked exploration without creation or linking controls", %{conn: conn} do
    ctx = context()
    sheet = source_fixture("sheet", ctx.project)
    reference = add_origin(ctx, sheet)

    conn
    |> authenticate(ctx.viewer.user)
    |> visit(source_path(ctx, "sheet", sheet.id))
    |> assert_has("#explore-changes", timeout: 20_000)
    |> click("#explore-changes")
    |> assert_has("#exploration-resume-#{ctx.session.id}")
    |> refute_has("#exploration-create")
    |> refute_has("#exploration-link-existing")
    |> click("#exploration-resume-#{ctx.session.id}")
    |> assert_path(board_path(ctx, ctx.session.id))
    |> assert_has("#brainstorming-origin-#{reference.id}", timeout: 20_000)

    assert {:ok, [_]} = Ideation.list_sessions(ctx.author, ctx.project.id)
  end

  defp context do
    ctx = ideation_fixture()
    %{ctx | project: Repo.preload(ctx.project, :workspace)}
  end

  defp source_fixture(type, project) do
    attrs = %{name: "Origin #{type}", description: "A bounded #{type} overview."}

    case type do
      "sheet" -> sheet_fixture(project, attrs)
      "flow" -> flow_fixture(project, attrs)
      "scene" -> scene_fixture(project, attrs)
    end
  end

  defp add_origin(ctx, sheet) do
    assert {:ok, reference} =
             Ideation.add_reference(ctx.author, ctx.project.id, ctx.session.id, nil, %{
               target_type: "sheet",
               target_id: sheet.id,
               relation: "origin",
               request_key: Ecto.UUID.generate()
             })

    reference
  end

  defp origin(ctx, session_id) do
    assert {:ok, %{references: [reference]}} = Ideation.list_references(ctx.author, ctx.project.id, session_id, nil)
    assert reference.relation == "origin"
    reference
  end

  defp project_path(ctx), do: "/workspaces/#{ctx.project.workspace.slug}/projects/#{ctx.project.slug}"
  defp source_path(ctx, type, id), do: "#{project_path(ctx)}/#{type}s/#{id}"
  defp board_path(ctx, id), do: "#{project_path(ctx)}/brainstorming/#{id}"

  defp lock_project(id), do: Repo.one!(from p in Project, where: p.id == ^id, select: p.id, lock: "FOR UPDATE")
end
