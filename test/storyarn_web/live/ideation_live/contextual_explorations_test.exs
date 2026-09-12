defmodule StoryarnWeb.IdeationLive.ContextualExplorationsTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.FlowsFixtures
  import Storyarn.IdeationFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Ideation
  alias Storyarn.Projects
  alias Storyarn.Repo
  alias Storyarn.Sheets

  setup do
    ctx = ideation_fixture()
    %{ctx | project: Repo.preload(ctx.project, :workspace)}
  end

  for type <- ~w(sheet flow scene) do
    @source_type type
    test "creates from #{@source_type}, preserves its source and returns through authorized navigation", ctx do
      source = source(ctx.project, @source_type)
      view = open_source(ctx, @source_type, source)
      assert has_element?(view, "##{@source_type}-header[data-inject-slot=top-left]")
      refute launcher(view)["open"]
      render_hook(view, "exploration_open", payload(view, @source_type, source))
      assert launcher(view)["target"]["name"] == source.name
      assert launcher(view)["linked"] == []
      assert {:ok, [existing]} = Ideation.list_sessions(ctx.author, ctx.project.id)
      assert existing.id == ctx.session.id

      render_hook(
        view,
        "exploration_create",
        payload(view, @source_type, source, %{
          title: "Explore a different motivation",
          objective: "",
          request_key: Ecto.UUID.generate(),
          target_type: "sheet",
          target_id: -1
        })
      )

      assert {:ok, [created, _]} = Ideation.list_sessions(ctx.author, ctx.project.id)
      assert created.title == "Explore a different motivation"
      assert {:ok, %{references: [reference]}} = Ideation.list_references(ctx.author, ctx.project.id, created.id, nil)
      assert reference.target_type == @source_type
      assert reference.target_id == source.id
      assert reference.base["name"] == source.name
      destination = board_path(ctx, created.id, reference.id)
      assert_redirect(view, destination)

      {:ok, board, _} = live(log_in_user(ctx.conn, ctx.author.user), destination)
      assert has_element?(board, "#brainstorming-header[data-inject-slot=top-left]")
      assert context_reference(board)["base"]["name"] == source.name

      render_hook(board, "exploration_return", board_payload(board, created.id, reference.id))
      assert_redirect(board, source_path(ctx, @source_type, source.id))
    end

    test "resumes linked #{@source_type} explorations and links another existing session", ctx do
      source = source(ctx.project, @source_type)
      reference = add_reference(ctx, @source_type, source.id)
      view = open_source(ctx, @source_type, source)
      render_hook(view, "exploration_open", payload(view, @source_type, source))
      assert [%{"id" => id, "contextStatus" => "current"}] = launcher(view)["linked"]
      assert id == ctx.session.id
      render_hook(view, "exploration_resume", payload(view, @source_type, source, %{session_id: id}))
      assert_redirect(view, board_path(ctx, id, reference.id))

      {:ok, other} = Ideation.create_session(ctx.author, ctx.project.id, %{title: "Another exploration"})
      view = open_source(ctx, @source_type, source)
      render_hook(view, "exploration_open", payload(view, @source_type, source))
      render_hook(view, "exploration_search", payload(view, @source_type, source, %{search: "Another"}))
      assert [%{"id" => other_id}] = launcher(view)["available"]
      assert other_id == other.id

      render_hook(
        view,
        "exploration_link",
        payload(view, @source_type, source, %{
          session_id: other.id,
          request_key: Ecto.UUID.generate()
        })
      )

      assert {:ok, %{references: [linked]}} = Ideation.list_references(ctx.author, ctx.project.id, other.id, nil)
      assert_redirect(view, board_path(ctx, other.id, linked.id))
      assert {:ok, sessions} = Ideation.list_sessions(ctx.author, ctx.project.id)
      assert length(sessions) == 2
    end
  end

  test "changed context rejects creation until the refreshed preview is reviewed", ctx do
    sheet = source(ctx.project, "sheet")
    view = open_source(ctx, "sheet", sheet)
    render_hook(view, "exploration_open", payload(view, "sheet", sheet))
    request = payload(view, "sheet", sheet, %{title: "Alternative", request_key: Ecto.UUID.generate()})
    {:ok, _} = Sheets.update_sheet(sheet, %{name: "Changed design"})
    render_hook(view, "exploration_create", request)
    assert launcher(view)["error"] == "stale_context"
    assert launcher(view)["target"]["name"] == "Changed design"
    assert {:ok, [_]} = Ideation.list_sessions(ctx.author, ctx.project.id)

    retry = Map.put(request, :exploration_context, launcher(view)["context"])
    render_hook(view, "exploration_create", retry)
    assert {:ok, [session, _]} = Ideation.list_sessions(ctx.author, ctx.project.id)
    assert {:ok, %{references: [reference]}} = Ideation.list_references(ctx.author, ctx.project.id, session.id, nil)
    assert reference.base["name"] == "Changed design"
  end

  test "viewer can resume but cannot create or link even with forged events", ctx do
    sheet = source(ctx.project, "sheet")
    reference = add_reference(ctx, "sheet", sheet.id)
    view = open_source(ctx, "sheet", sheet, ctx.viewer)
    render_hook(view, "exploration_open", payload(view, "sheet", sheet))
    refute launcher(view)["canEdit"]

    render_hook(
      view,
      "exploration_create",
      payload(view, "sheet", sheet, %{
        title: "Forbidden",
        request_key: Ecto.UUID.generate()
      })
    )

    assert launcher(view)["error"] == "unauthorized"
    assert {:ok, [_]} = Ideation.list_sessions(ctx.author, ctx.project.id)
    render_hook(view, "exploration_resume", payload(view, "sheet", sheet, %{session_id: ctx.session.id}))
    assert_redirect(view, board_path(ctx, ctx.session.id, reference.id))
  end

  test "revoking access clears an open launcher and denies pending creation", ctx do
    sheet = source(ctx.project, "sheet")
    view = open_source(ctx, "sheet", sheet)
    render_hook(view, "exploration_open", payload(view, "sheet", sheet))
    request = payload(view, "sheet", sheet, %{title: "Revoked", request_key: Ecto.UUID.generate()})
    membership = Projects.get_membership(ctx.project.id, ctx.author.user.id)
    assert {:ok, _} = Projects.remove_member(ctx.owner, ctx.project.id, membership.id)
    render_hook(view, "exploration_create", request)
    assert launcher(view)["target"] == nil
    assert launcher(view)["linked"] == []
    assert launcher(view)["available"] == []
    refute launcher(view)["canEdit"]
    assert {:ok, [_]} = Ideation.list_sessions(ctx.owner, ctx.project.id)
  end

  test "stale source identity, closed dialog and unlinked sessions cannot forge navigation or writes", ctx do
    sheet = source(ctx.project, "sheet")
    view = open_source(ctx, "sheet", sheet)
    render_hook(view, "exploration_open", payload(view, "sheet", sheet))
    render_hook(view, "exploration_resume", payload(view, "sheet", sheet, %{session_id: ctx.session.id}))
    assert launcher(view)["error"] == "not_found"
    request = payload(view, "sheet", sheet, %{title: "Forbidden", request_key: Ecto.UUID.generate()})
    render_hook(view, "exploration_create", Map.put(request, :source_key, "sheet:0"))
    assert launcher(view)["error"] == "stale_context"
    render_hook(view, "exploration_close", payload(view, "sheet", sheet))
    render_hook(view, "exploration_create", request)
    refute launcher(view)["open"]
    assert {:ok, [_]} = Ideation.list_sessions(ctx.author, ctx.project.id)
  end

  test "deleted origin redacts context and cannot be reopened from the board", ctx do
    sheet = source(ctx.project, "sheet")
    reference = add_reference(ctx, "sheet", sheet.id)
    {:ok, view, _} = live(log_in_user(ctx.conn, ctx.author.user), board_path(ctx, ctx.session.id, reference.id))
    request = board_payload(view, ctx.session.id, reference.id)
    {:ok, _} = Sheets.delete_sheet(sheet)
    render_hook(view, "exploration_return", request)
    assert_reply(view, %{status: "error", code: "not_found"})

    # BoardHeader sends production prop diffs; a fresh mount exposes full props.
    # The browser test separately verifies redaction on the already-open board.
    {:ok, view, _} = live(log_in_user(build_conn(), ctx.author.user), board_path(ctx, ctx.session.id, reference.id))
    assert context_reference(view)["status"] == "unavailable"
    assert context_reference(view)["base"] == nil
    assert context_reference(view)["current"] == nil
  end

  test "a private idea reference cannot expose a return banner", ctx do
    sheet = source(ctx.project, "sheet")
    idea = ctx |> idea_fixture() |> then(&publish_idea(ctx, &1))

    {:ok, reference} =
      Ideation.add_reference(ctx.author, ctx.project.id, ctx.session.id, idea.id, %{
        target_type: "sheet",
        target_id: sheet.id,
        relation: "origin",
        request_key: Ecto.UUID.generate()
      })

    {:ok, session} = Ideation.get_session(ctx.facilitator, ctx.project.id, ctx.session.id)
    {:ok, _} = Ideation.set_private_mode(ctx.facilitator, ctx.project.id, ctx.session.id, session.revision, true)
    {:ok, view, _} = live(log_in_user(ctx.conn, ctx.viewer.user), board_path(ctx, ctx.session.id, reference.id))
    assert context_reference(view) == nil
  end

  defp open_source(ctx, type, source, actor \\ nil) do
    {:ok, view, _} = live(log_in_user(ctx.conn, (actor || ctx.author).user), source_path(ctx, type, source.id))
    render_async(view)
    view
  end

  defp source(project, "sheet"),
    do: sheet_fixture(project, %{name: "Original character", description: "Design context"})

  defp source(project, "flow"), do: flow_fixture(project, %{name: "Original dialogue", description: "Design context"})
  defp source(project, "scene"), do: scene_fixture(project, %{name: "Original map", description: "Design context"})

  defp add_reference(ctx, type, id) do
    {:ok, reference} =
      Ideation.add_reference(ctx.author, ctx.project.id, ctx.session.id, nil, %{
        target_type: type,
        target_id: id,
        relation: "origin",
        request_key: Ecto.UUID.generate()
      })

    reference
  end

  defp launcher(view),
    do: LiveVue.Test.get_vue(view, name: "live/shared/ContextualSourceHeader").props["exploration-state"]

  defp context_reference(view),
    do: LiveVue.Test.get_vue(view, name: "live/ideation/BoardHeader").props["context-reference"]

  defp payload(view, type, source, attrs \\ %{}) do
    Map.merge(%{source_key: "#{type}:#{source.id}", exploration_context: launcher(view)["context"]}, attrs)
  end

  defp board_payload(view, session_id, reference_id) do
    props = LiveVue.Test.get_vue(view, name: "live/ideation/BoardHeader").props
    %{epoch: props["epoch"], session_id: session_id, reference_id: reference_id}
  end

  defp source_path(ctx, type, id), do: "#{base_path(ctx)}/#{type}s/#{id}"
  defp board_path(ctx, id, reference), do: "#{base_path(ctx)}/brainstorming/#{id}?context_reference=#{reference}"
  defp base_path(ctx), do: "/workspaces/#{ctx.project.workspace.slug}/projects/#{ctx.project.slug}"
end
