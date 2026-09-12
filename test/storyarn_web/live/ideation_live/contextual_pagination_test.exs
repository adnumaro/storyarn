defmodule StoryarnWeb.IdeationLive.ContextualPaginationTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.IdeationFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Ideation
  alias Storyarn.Projects
  alias Storyarn.Repo

  setup do
    ctx = ideation_fixture()
    %{ctx | project: Repo.preload(ctx.project, :workspace)}
  end

  test "linked previous page is queried again and rejects repeated stale navigation", ctx do
    sheet = sheet_fixture(ctx.project)
    sessions = sessions(ctx, "Linked", 21)
    link_sessions(ctx, sheet, sessions)
    view = open_source(ctx, sheet)
    first = launcher(view)
    assert length(first["linked"]) == 20
    refute first["linkedPrevious"]
    assert is_integer(first["linkedNext"])

    next_page(view, sheet, "linked")
    assert [%{"id" => oldest_id}] = launcher(view)["linked"]
    assert oldest_id == hd(sessions).id
    assert launcher(view)["linkedPrevious"]
    assert launcher(view)["linkedNext"] == nil
    previous_request = previous_payload(view, sheet, "linked")

    newest = List.last(sessions)
    assert {:ok, newest} = Ideation.get_session(ctx.author, ctx.project.id, newest.id)

    assert {:ok, _} =
             Ideation.update_session(ctx.author, ctx.project.id, newest.id, newest.revision, %{
               title: "Updated while on the next page"
             })

    render_hook(view, "exploration_load_previous", previous_request)
    current = launcher(view)
    assert length(current["linked"]) == 20
    assert hd(current["linked"])["title"] == "Updated while on the next page"
    refute Enum.any?(current["linked"], &(&1["id"] == oldest_id))
    refute current["linkedPrevious"]
    assert current["linkedCursor"] == nil

    render_hook(view, "exploration_load_previous", previous_request)
    assert launcher(view)["error"] == "invalid_parameters"
    assert launcher(view)["linked"] == current["linked"]
  end

  test "available previous page excludes sessions archived since it was displayed", ctx do
    sheet = sheet_fixture(ctx.project)
    sessions = sessions(ctx, "Catalog", 21)
    view = open_source(ctx, sheet)
    search(view, sheet, "Catalog")
    assert length(launcher(view)["available"]) == 20
    next_page(view, sheet, "available")
    assert length(launcher(view)["available"]) == 1
    assert launcher(view)["availableNext"] == nil
    previous_request = previous_payload(view, sheet, "available")

    archived = List.last(sessions)
    assert {:ok, _} = Ideation.archive_session(ctx.author, ctx.project.id, archived.id, archived.revision)
    render_hook(view, "exploration_load_previous", previous_request)
    current = launcher(view)
    assert length(current["available"]) == 20
    refute Enum.any?(current["available"], &(&1["id"] == archived.id))
    refute current["availablePrevious"]
    assert current["availableNext"] == nil
    assert current["availableCursor"] == nil
  end

  test "search restarts available pagination without resetting the linked page", ctx do
    sheet = sheet_fixture(ctx.project)
    linked_sessions = sessions(ctx, "Linked", 21)
    link_sessions(ctx, sheet, linked_sessions)
    available_sessions = sessions(ctx, "Catalog", 21)
    view = open_source(ctx, sheet)
    search(view, sheet, "Catalog")
    next_page(view, sheet, "linked")
    next_page(view, sheet, "available")
    old_available_request = previous_payload(view, sheet, "available")
    linked_cursor = launcher(view)["linkedCursor"]
    assert launcher(view)["linkedPrevious"]
    assert launcher(view)["availablePrevious"]

    search(view, sheet, List.last(available_sessions).title)
    current = launcher(view)
    assert length(current["available"]) == 1
    refute current["availablePrevious"]
    assert current["availableCursor"] == nil
    assert current["linkedPrevious"]
    assert current["linkedCursor"] == linked_cursor

    render_hook(view, "exploration_load_previous", old_available_request)
    assert launcher(view)["error"] == "invalid_parameters"
    render_hook(view, "exploration_load_previous", previous_payload(view, sheet, "linked"))
    assert length(launcher(view)["linked"]) == 20
    refute launcher(view)["linkedPrevious"]
  end

  test "revoked access clears page history and cannot redisplay previously visible rows", ctx do
    sheet = sheet_fixture(ctx.project)
    sessions(ctx, "Catalog", 21)
    view = open_source(ctx, sheet)
    next_page(view, sheet, "available")
    request = previous_payload(view, sheet, "available")
    assert launcher(view)["availablePrevious"]

    membership = Projects.get_membership(ctx.project.id, ctx.author.user.id)
    assert {:ok, _} = Projects.remove_member(ctx.owner, ctx.project.id, membership.id)
    render_hook(view, "exploration_load_previous", request)
    current = launcher(view)
    assert current["target"] == nil
    assert current["linked"] == []
    assert current["available"] == []
    refute current["linkedPrevious"]
    refute current["availablePrevious"]
    assert current["linkedCursor"] == nil
    assert current["availableCursor"] == nil
    refute current["canEdit"]
  end

  test "navigating to another source resets both cursor histories and search", ctx do
    first_sheet = sheet_fixture(ctx.project)
    second_sheet = sheet_fixture(ctx.project)
    sessions(ctx, "Catalog", 21)
    view = open_source(ctx, first_sheet)
    search(view, first_sheet, "Catalog")
    next_page(view, first_sheet, "available")
    old_request = previous_payload(view, first_sheet, "available")

    render_patch(view, source_path(ctx, second_sheet))
    refute launcher(view)["open"]
    refute launcher(view)["linkedPrevious"]
    refute launcher(view)["availablePrevious"]
    assert launcher(view)["availableCursor"] == nil
    render_hook(view, "exploration_load_previous", old_request)
    assert launcher(view)["error"] == "stale_context"

    render_hook(view, "exploration_open", payload(view, second_sheet))
    assert launcher(view)["target"]["id"] == second_sheet.id
    refute launcher(view)["availablePrevious"]
    next_page(view, second_sheet, "available")
    assert Enum.any?(launcher(view)["available"], &(&1["id"] == ctx.session.id))
  end

  defp sessions(ctx, prefix, count) do
    for index <- 1..count do
      {:ok, session} = Ideation.create_session(ctx.author, ctx.project.id, %{title: "#{prefix} #{index}"})
      session
    end
  end

  defp link_sessions(ctx, sheet, sessions) do
    for session <- sessions do
      assert {:ok, _} =
               Ideation.add_reference(ctx.author, ctx.project.id, session.id, nil, %{
                 target_type: "sheet",
                 target_id: sheet.id,
                 relation: "origin",
                 request_key: Ecto.UUID.generate()
               })
    end
  end

  defp open_source(ctx, sheet) do
    {:ok, view, _} = live(log_in_user(ctx.conn, ctx.author.user), source_path(ctx, sheet))
    render_async(view)
    render_hook(view, "exploration_open", payload(view, sheet))
    view
  end

  defp launcher(view),
    do: LiveVue.Test.get_vue(view, name: "live/shared/ContextualSourceHeader").props["exploration-state"]

  defp payload(view, sheet, attrs \\ %{}) do
    Map.merge(%{source_key: "sheet:#{sheet.id}", exploration_context: launcher(view)["context"]}, attrs)
  end

  defp next_page(view, sheet, list) do
    render_hook(
      view,
      "exploration_load_more",
      payload(view, sheet, %{list: list, cursor: launcher(view)["#{list}Next"]})
    )
  end

  defp previous_payload(view, sheet, list),
    do: payload(view, sheet, %{list: list, cursor: launcher(view)["#{list}Cursor"]})

  defp search(view, sheet, query), do: render_hook(view, "exploration_search", payload(view, sheet, %{search: query}))

  defp source_path(ctx, sheet),
    do: "/workspaces/#{ctx.project.workspace.slug}/projects/#{ctx.project.slug}/sheets/#{sheet.id}"
end
