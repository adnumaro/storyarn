defmodule StoryarnWeb.IdeationLive.ReferencesTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.IdeationFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Ideation
  alias Storyarn.Repo
  alias Storyarn.Sheets
  alias StoryarnWeb.IdeationLive.Board

  setup do
    ctx = ideation_fixture()
    %{ctx | project: Repo.preload(ctx.project, :workspace)}
  end

  test "opening an older reference pins it once without changing the normal pagination cursor", ctx do
    sheet = sheet_fixture(ctx.project, %{name: "Starting design"})
    reference = add_reference(ctx, sheet.id)

    for number <- 1..21 do
      newer = sheet_fixture(ctx.project, %{name: "Later design #{number}"})
      add_reference(ctx, newer.id)
    end

    {:ok, first_page} = Ideation.list_references(ctx.author, ctx.project.id, ctx.session.id, nil)
    refute Enum.any?(first_page.references, &(&1.id == reference.id))
    {:ok, view, _} = live(log_in_user(ctx.conn, ctx.author.user), path(ctx))
    render_hook(view, "references_open", payload(view, ctx, %{reference_id: reference.id}))
    assert_reply(view, %{status: "ok"})
    assert state(view)["focusedReferenceId"] == reference.id
    assert Enum.map(state(view)["items"], & &1["id"]) == [reference.id | Enum.map(first_page.references, & &1.id)]
    assert state(view)["nextCursor"] == first_page.next_cursor

    {:ok, second_page} =
      Ideation.list_references(ctx.author, ctx.project.id, ctx.session.id, nil, before_id: first_page.next_cursor)

    render_hook(view, "references_load_more", payload(view, ctx, %{}))
    assert state(view)["nextCursor"] == second_page.next_cursor
    assert hd(state(view)["items"])["id"] == reference.id
    assert Enum.count(state(view)["items"], &(&1["id"] == reference.id)) == 1
    assert Enum.sort(Enum.map(state(view)["items"], & &1["id"])) == Enum.sort(Enum.map(second_page.references, & &1.id))

    {:ok, _} = Sheets.update_sheet(sheet, %{name: "Revised starting design"})
    render_hook(view, "references_reload", payload(view, ctx, %{}))
    assert state(view)["nextCursor"] == first_page.next_cursor

    assert %{"id" => id, "status" => "changed", "current" => %{"name" => "Revised starting design"}} =
             hd(state(view)["items"])

    assert id == reference.id
  end

  test "focused references must belong to the requested session and shared idea scope", ctx do
    sheet = sheet_fixture(ctx.project)
    reference = add_reference(ctx, sheet.id)
    shared = ctx |> idea_fixture() |> then(&publish_idea(ctx, &1))
    idea_reference = add_reference(ctx, sheet.id, shared.id)
    {:ok, other_session} = Ideation.create_session(ctx.facilitator, ctx.project.id, %{title: "Another exploration"})
    other_reference = add_reference(%{ctx | session: other_session}, sheet.id)
    {:ok, view, _} = live(log_in_user(ctx.conn, ctx.author.user), path(ctx))

    for attrs <- [%{reference_id: idea_reference.id}, %{reference_id: other_reference.id}, %{reference_id: "invalid"}] do
      render_hook(view, "references_open", payload(view, ctx, %{reference_id: reference.id}))
      assert state(view)["focusedReferenceId"] == reference.id
      render_hook(view, "references_open", payload(view, ctx, attrs))
      assert_reply(view, %{status: "error"})
      refute state(view)["open"]
      assert state(view)["focusedReferenceId"] == nil
      assert state(view)["items"] == []
    end

    render_hook(view, "references_open", payload(view, ctx, %{idea_id: shared.id, reference_id: idea_reference.id}))
    assert_reply(view, %{status: "ok"})
    assert state(view)["focusedReferenceId"] == idea_reference.id
  end

  test "removing a focused reference clears its pinned details on reload", ctx do
    sheet = sheet_fixture(ctx.project)
    reference = add_reference(ctx, sheet.id)
    {:ok, view, _} = live(log_in_user(ctx.conn, ctx.author.user), path(ctx))
    render_hook(view, "references_open", payload(view, ctx, %{reference_id: reference.id}))
    assert state(view)["focusedReferenceId"] == reference.id

    {:ok, _} =
      Ideation.remove_reference(
        ctx.author,
        ctx.project.id,
        ctx.session.id,
        nil,
        reference.id,
        reference.version,
        Ecto.UUID.generate()
      )

    render_hook(view, "references_reload", payload(view, ctx, %{}))
    refute state(view)["open"]
    assert state(view)["focusedReferenceId"] == nil
    assert state(view)["items"] == []
  end

  test "links an existing sheet, compares saved context and explicitly refreshes it", ctx do
    sheet = sheet_fixture(ctx.project, %{name: "Original design", description: "Starting context"})
    {:ok, view, _} = live(log_in_user(ctx.conn, ctx.author.user), path(ctx))
    assert has_element?(view, "#brainstorming-panels[data-inject-slot=panels]")
    render_hook(view, "references_open", payload(view, ctx, %{}))
    assert state(view)["open"]
    assert state(view)["canEdit"]
    render_hook(view, "references_search", payload(view, ctx, %{type: "sheet", search: "Original"}))
    assert [%{"name" => "Original design"}] = state(view)["results"]

    request =
      payload(view, ctx, %{
        target_type: "sheet",
        target_id: sheet.id,
        relation: "origin",
        request_key: Ecto.UUID.generate()
      })

    render_hook(view, "references_add", request)
    assert_reply(view, %{status: "ok"})
    render_hook(view, "references_add", request)
    assert_reply(view, %{status: "ok"})
    assert [reference] = state(view)["items"]
    assert reference["current"]["href"] =~ "/sheets/#{sheet.id}"
    assert reference["base"]["name"] == "Original design"
    assert reference["status"] == "current"
    {:ok, _} = Sheets.update_sheet(sheet, %{name: "Revised design"})
    render_hook(view, "references_reload", payload(view, ctx, %{}))
    assert [changed] = state(view)["items"]
    assert changed["status"] == "changed"
    assert changed["base"]["name"] == "Original design"
    assert changed["current"]["name"] == "Revised design"

    render_hook(
      view,
      "references_refresh",
      payload(view, ctx, %{
        reference_id: changed["id"],
        version: changed["version"],
        request_key: Ecto.UUID.generate()
      })
    )

    assert_reply(view, %{status: "ok"})
    assert [updated] = state(view)["items"]
    assert updated["status"] == "current"
    assert updated["base"]["name"] == "Revised design"
    render_hook(view, "references_history", payload(view, ctx, %{reference_id: updated["id"]}))
    assert Enum.map(state(view)["history"], & &1["context"]["name"]) == ["Revised design", "Original design"]

    render_hook(
      view,
      "references_remove",
      payload(view, ctx, %{
        reference_id: updated["id"],
        version: updated["version"],
        request_key: Ecto.UUID.generate()
      })
    )

    assert_reply(view, %{status: "ok"})
    assert state(view)["items"] == []
    assert Sheets.get_sheet(ctx.project.id, sheet.id).name == "Revised design"
  end

  test "viewer can inspect existing references but cannot forge writes", ctx do
    sheet = sheet_fixture(ctx.project)
    reference = add_reference(ctx, sheet.id)
    {:ok, view, _} = live(log_in_user(ctx.conn, ctx.viewer.user), path(ctx))
    render_hook(view, "references_open", payload(view, ctx, %{}))
    assert [%{"id" => id}] = state(view)["items"]
    assert id == reference.id
    refute state(view)["canEdit"]

    render_hook(
      view,
      "references_remove",
      payload(view, ctx, %{reference_id: reference.id, version: reference.version, request_key: Ecto.UUID.generate()})
    )

    assert_reply(view, %{status: "error"})
    assert {:ok, %{references: [_]}} = Ideation.list_references(ctx.author, ctx.project.id, ctx.session.id, nil)
  end

  test "private ideas never expose references and private mode clears open idea context", ctx do
    sheet = sheet_fixture(ctx.project)
    private = idea_fixture(ctx)
    shared = ctx |> idea_fixture() |> then(&publish_idea(ctx, &1))
    reference = add_reference(ctx, sheet.id, shared.id)
    {:ok, view, _} = live(log_in_user(ctx.conn, ctx.author.user), path(ctx))
    render_hook(view, "references_open", payload(view, ctx, %{idea_id: private.id}))
    refute state(view)["open"]
    render_hook(view, "references_open", payload(view, ctx, %{idea_id: shared.id, reference_id: reference.id}))
    assert state(view)["open"]
    assert state(view)["items"] != []
    before_privacy_change = :sys.get_state(view.pid).socket
    {:ok, session} = Ideation.get_session(ctx.facilitator, ctx.project.id, ctx.session.id)
    {:ok, _} = Ideation.set_private_mode(ctx.facilitator, ctx.project.id, ctx.session.id, session.revision, true)

    # Even a board read completed before private mode changed must reauthorize
    # references when accepted, rather than keeping its older target previews.
    token = make_ref()
    pending = Phoenix.Component.assign(before_privacy_change, refresh_running: token, refresh_dirty: false)

    assert {:noreply, accepted} =
             Board.handle_async({:board, token}, {:ok, {:ok, before_privacy_change.assigns.board}}, pending)

    refute accepted.assigns.references.open
    assert accepted.assigns.references.items == []
    assert accepted.assigns.references.results == []
    assert accepted.assigns.references.history == []
    assert accepted.assigns.references.focusedReferenceId == nil

    send(view.pid, {:ideation_references_changed, ctx.session.id})
    render(view)
    refute state(view)["open"]
    assert state(view)["items"] == []
    assert state(view)["results"] == []
  end

  test "target deletion hides base, current details and history without deleting reference", ctx do
    sheet = sheet_fixture(ctx.project, %{name: "No stale previews"})
    reference = add_reference(ctx, sheet.id)
    {:ok, view, _} = live(log_in_user(ctx.conn, ctx.author.user), path(ctx))
    render_hook(view, "references_open", payload(view, ctx, %{reference_id: reference.id}))
    render_hook(view, "references_history", payload(view, ctx, %{reference_id: reference.id}))
    assert state(view)["history"] != []
    {:ok, _} = Sheets.delete_sheet(sheet)
    render_hook(view, "references_reload", payload(view, ctx, %{}))
    assert [%{"status" => "unavailable", "base" => nil, "current" => nil}] = state(view)["items"]
    assert state(view)["focusedReferenceId"] == reference.id
    assert state(view)["history"] == []
    render_hook(view, "references_history", payload(view, ctx, %{reference_id: reference.id}))
    assert_reply(view, %{status: "error"})
    assert state(view)["history"] == []
  end

  test "stale board and source contexts cannot retarget pending reference requests", ctx do
    sheet = sheet_fixture(ctx.project)
    idea = ctx |> idea_fixture() |> then(&publish_idea(ctx, &1))
    {:ok, view, _} = live(log_in_user(ctx.conn, ctx.author.user), path(ctx))
    render_hook(view, "references_open", payload(view, ctx, %{}))

    pending =
      payload(view, ctx, %{
        target_type: "sheet",
        target_id: sheet.id,
        relation: "reference",
        request_key: Ecto.UUID.generate()
      })

    render_hook(view, "references_open", payload(view, ctx, %{idea_id: idea.id}))
    render_hook(view, "references_add", pending)
    assert_reply(view, %{status: "error", code: "stale_board"})
    render_hook(view, "references_add", Map.put(payload(view, ctx, pending), :epoch, "old"))
    assert_reply(view, %{status: "error", code: "stale_board"})
    assert {:ok, %{references: []}} = Ideation.list_references(ctx.author, ctx.project.id, ctx.session.id, nil)
    assert {:ok, %{references: []}} = Ideation.list_references(ctx.author, ctx.project.id, ctx.session.id, idea.id)
  end

  test "opening comments clears reference details and vice versa", ctx do
    sheet = sheet_fixture(ctx.project)
    add_reference(ctx, sheet.id)
    {:ok, view, _} = live(log_in_user(ctx.conn, ctx.author.user), path(ctx))
    assert has_element?(view, "#brainstorming-panels[data-inject=project-layout][data-inject-slot=panels]")

    refute has_element?(
             view,
             "[data-inject=project-layout][data-inject-slot=panels]:not(#brainstorming-panels)"
           )

    render_hook(view, "references_open", payload(view, ctx, %{}))
    assert state(view)["open"]
    render_hook(view, "comments_open", payload(view, ctx, %{}))
    refute state(view)["open"]
    assert state(view)["items"] == []
    assert LiveVue.Test.get_vue(view, name: "live/ideation/BoardPanels").props["comments"]["open"]
    render_hook(view, "references_open", payload(view, ctx, %{}))
    assert state(view)["open"]
    refute LiveVue.Test.get_vue(view, name: "live/ideation/BoardPanels").props["comments"]["open"]
  end

  defp add_reference(ctx, target_id, idea_id \\ nil) do
    {:ok, reference} =
      Ideation.add_reference(ctx.author, ctx.project.id, ctx.session.id, idea_id, %{
        target_type: "sheet",
        target_id: target_id,
        relation: "reference",
        request_key: Ecto.UUID.generate()
      })

    reference
  end

  defp state(view), do: LiveVue.Test.get_vue(view, name: "live/ideation/BoardPanels").props["references"]

  defp payload(view, ctx, attrs) do
    board = LiveVue.Test.get_vue(view, name: "live/ideation/BrainstormingBoard").props["board"]
    Map.merge(attrs, %{epoch: board["epoch"], session_id: ctx.session.id, reference_context: state(view)["context"]})
  end

  defp path(ctx),
    do: ~p"/workspaces/#{ctx.project.workspace.slug}/projects/#{ctx.project.slug}/brainstorming/#{ctx.session.id}"
end
