defmodule StoryarnWeb.IdeationLive.BoardTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.IdeationFixtures

  alias Storyarn.Ideation
  alias Storyarn.Ideation.Sessions.Session
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Projects
  alias Storyarn.Repo
  alias StoryarnWeb.IdeationLive.Board
  alias StoryarnWeb.IdeationLive.Helpers.BoardData

  setup do
    ctx = ideation_fixture()
    %{ctx | project: Repo.preload(ctx.project, :workspace)}
  end

  test "project navigation exposes a usable board and title-only session creation", ctx do
    {:ok, view, _} = live(log_in_user(ctx.conn, ctx.author.user), board_path(ctx))
    assert data(view)["session"] == nil
    assert data(view)["can_edit"]
    layout = LiveVue.Test.get_vue(view, name: "live/layouts/project/Layout")
    assert layout.props["urls"]["tools"]["brainstorming"] == board_path(ctx)

    render_hook(view, "create_session", %{epoch: data(view)["epoch"], title: "A fresh question"})
    assert_reply(view, %{status: "ok", value: %{id: id}})
    render_hook(view, "open_session", %{epoch: data(view)["epoch"], id: id})
    assert_patch(view, board_path(ctx, id))
    assert data(view)["session"]["title"] == "A fresh question"
  end

  test "private data, counts and unpublished text never enter another member's props", ctx do
    idea_fixture(ctx, %{title: "Private secret"})
    shared = ctx |> idea_fixture(%{body: "<p>Published text</p>"}) |> then(&publish_idea(ctx, &1))

    {:ok, _} =
      Ideation.update_idea(
        ctx.author,
        ctx.project.id,
        ctx.session.id,
        shared.id,
        1,
        edit_attrs(%{body: "<p>New private draft</p>"})
      )

    {:ok, view, _} = live(log_in_user(ctx.conn, ctx.peer.user), board_path(ctx, ctx.session.id))
    board = data(view)
    assert [%{"id" => id, "preview" => "Published text", "revision" => 1}] = board["ideas"]
    assert id == shared.id
    assert board["counts"] == %{"active" => 1, "parked" => 0, "discarded" => 0}
    refute Jason.encode!(board) =~ "Private secret"
    refute Jason.encode!(board) =~ "New private draft"
    render_hook(view, "inspect_idea", payload(view, %{idea_id: shared.id}))
    assert_reply(view, %{status: "ok", value: %{history: [%{number: 1}], conflicts: []}})
  end

  test "viewer cannot bypass readonly controls and malformed routes do not retain old content", ctx do
    {:ok, view, _} = live(log_in_user(ctx.conn, ctx.viewer.user), board_path(ctx, ctx.session.id))
    refute data(view)["can_edit"]
    render_hook(view, "create_idea", payload(view, idea_attrs()))
    assert_reply(view, %{status: "error", code: "unauthorized"})
    assert data(view)["ideas"] == []
    render_patch(view, board_path(ctx, "invalid"))
    assert data(view)["error"] == "not_found"
    assert data(view)["session"] == nil
  end

  test "typed parameters remain strict while canvas contributions follow the current session mode", ctx do
    {:ok, view, _} = live(log_in_user(ctx.conn, ctx.author.user), board_path(ctx, ctx.session.id))
    ctx = Storyarn.IdeationFixtures.configure_session(ctx, %{default_visibility: :shared})

    for invalid <- ["1x", "1.0", 0, -1, nil, %{}, "9007199254740992"] do
      render_hook(view, "create_idea", payload(view, idea_attrs(%{configuration_version: invalid})))
      assert_reply(view, %{status: "error", code: "invalid_parameters"})
    end

    render_hook(view, "create_idea", payload(view, idea_attrs(%{configuration_version: "1"})))
    assert_reply(view, %{status: "ok", value: %{visibility: :shared}})

    render_hook(
      view,
      "create_idea",
      payload(view, idea_attrs(%{configuration_version: "#{ctx.session.configuration_version}"}))
    )

    assert_reply(view, %{status: "ok", value: %{visibility: :shared, author_id: id}})
    assert id == ctx.author.user.id
  end

  test "equivalent stale saves retain receipts without surfacing ghost conflicts", ctx do
    idea = idea_fixture(ctx)

    {:ok, current} =
      Ideation.update_idea(
        ctx.author,
        ctx.project.id,
        ctx.session.id,
        idea.id,
        1,
        edit_attrs(%{body: "<p>Current text</p>"})
      )

    {:ok, view, _} = live(log_in_user(ctx.conn, ctx.author.user), board_path(ctx, ctx.session.id))
    render_hook(view, "save_idea", payload(view, edit_attrs(%{idea_id: idea.id, revision: 1, body: current.body})))
    assert_reply(view, %{status: "ok", value: %{revision: 2}})
    {:ok, receipts} = Ideation.list_idea_conflicts(ctx.author, ctx.project.id, ctx.session.id, idea.id)
    assert length(receipts) == 1
    render_hook(view, "inspect_idea", payload(view, %{idea_id: idea.id}))
    assert_reply(view, %{status: "ok", value: %{conflicts: []}})

    render_hook(view, "save_idea", payload(view, edit_attrs(%{idea_id: idea.id, revision: 1, state: "parked"})))
    assert_reply(view, %{status: "conflict", value: %{receipt: %{attempted: %{state: :parked}}}})
    render_hook(view, "inspect_idea", payload(view, %{idea_id: idea.id}))
    assert_reply(view, %{status: "ok", value: %{conflicts: [_]}})
  end

  test "assisted preview exposes only a frozen count and excludes discarded ideas by default", ctx do
    ctx = Storyarn.IdeationFixtures.configure_session(ctx, %{publication_policy: :facilitator_assisted})
    attrs = %{publication_consent: :facilitator_assisted, configuration_version: ctx.session.configuration_version}
    active = idea_fixture(ctx, Map.put(attrs, :title, "Do not reveal before confirmation"))
    discarded = idea_fixture(ctx, Map.put(attrs, :state, :discarded))
    {:ok, view, _} = live(log_in_user(ctx.conn, ctx.facilitator.user), board_path(ctx, ctx.session.id))
    assert data(view)["ideas"] == []
    key = Ecto.UUID.generate()
    render_hook(view, "prepare_reveal", payload(view, %{mode: "eligible", request_key: key}))
    assert_reply(view, %{status: "ok", value: value})
    assert value |> Map.keys() |> Enum.sort() == [:count, :id, :status]
    assert value.count == 1
    idea_fixture(ctx, attrs)
    render_hook(view, "prepare_reveal", payload(view, %{mode: "eligible", request_key: key}))
    assert_reply(view, %{status: "ok", value: ^value})
    render_hook(view, "reveal_ideas", payload(view, %{operation_id: value.id}))
    assert_reply(view, %{status: "ok", value: %{count: 1}})
    assert {:ok, %{visibility: :shared}} = Ideation.get_idea(ctx.peer, ctx.project.id, ctx.session.id, active.id)
    assert {:error, :not_found} = Ideation.get_idea(ctx.peer, ctx.project.id, ctx.session.id, discarded.id)

    render_hook(
      view,
      "prepare_reveal",
      payload(view, %{mode: "eligible", include_discarded: true, request_key: Ecto.UUID.generate()})
    )

    assert_reply(view, %{status: "ok", value: %{count: 2}})
  end

  test "paste is sanitized on save and returned as inert content on reload", ctx do
    {:ok, view, _} = live(log_in_user(ctx.conn, ctx.author.user), board_path(ctx, ctx.session.id))
    render_hook(view, "create_idea", payload(view, idea_attrs(%{body: "<p>Hello<script>alert(1)</script></p>"})))
    assert_reply(view, %{status: "ok", value: %{id: id, body: body}})
    refute body =~ "<script"
    assert body =~ "alert(1)"
    render_hook(view, "inspect_idea", payload(view, %{idea_id: id}))
    assert_reply(view, %{status: "ok", value: %{idea: %{body: ^body}}})
  end

  test "restore invalidates the client epoch even when IDs remain the same", ctx do
    {:ok, view, _} = live(log_in_user(ctx.conn, ctx.author.user), board_path(ctx, ctx.session.id))
    old = payload(view, idea_attrs())
    send(view.pid, {:project_restored, 1})
    render(view)
    assert_push_event(view, "brainstorming_reset", %{reason: "project_restored", epoch: epoch})
    refute epoch == old.epoch
    render_hook(view, "create_idea", old)
    assert_reply(view, %{status: "error", code: "stale_board"})
    assert {:ok, []} = Ideation.list_ideas(ctx.author, ctx.project.id, ctx.session.id)
  end

  test "two connected authors keep distinct drafts and see only each other's published revisions", ctx do
    first = idea_fixture(ctx, %{visibility: :shared, title: "First"})
    second = idea_fixture(ctx, %{visibility: :shared, title: "Second"}, ctx.peer)
    {:ok, author, _} = live(log_in_user(ctx.conn, ctx.author.user), board_path(ctx, ctx.session.id))
    {:ok, peer, _} = live(log_in_user(ctx.conn, ctx.peer.user), board_path(ctx, ctx.session.id))
    render_hook(author, "save_idea", payload(author, edit_attrs(%{idea_id: first.id, revision: 1, title: "First draft"})))
    assert_reply(author, %{status: "ok", value: first_draft})
    render_hook(peer, "save_idea", payload(peer, edit_attrs(%{idea_id: second.id, revision: 1, title: "Second draft"})))
    assert_reply(peer, %{status: "ok", value: second_draft})
    refute Jason.encode!(data(peer)) =~ "First draft"
    refute Jason.encode!(data(author)) =~ "Second draft"
    publish_idea(ctx, first_draft)
    publish_idea(ctx, second_draft, ctx.peer)

    for view <- [author, peer] do
      assert_board_eventually(view, fn board ->
        assert Enum.sort(Enum.map(board["ideas"], & &1["title"])) == ["First draft", "Second draft"]
      end)
    end
  end

  test "revoked access clears old private props and blocks an already open editor", ctx do
    idea = idea_fixture(ctx)
    {:ok, view, _} = live(log_in_user(ctx.conn, ctx.author.user), board_path(ctx, ctx.session.id))
    old_payload = payload(view, %{idea_id: idea.id})
    membership = Projects.get_membership(ctx.project.id, ctx.author.user.id)
    assert {:ok, _} = Projects.remove_member(ctx.owner, ctx.project.id, membership.id)
    render_hook(view, "inspect_idea", old_payload)
    assert_reply(view, %{status: "error", code: "not_found"})
    assert data(view)["ideas"] == []
    assert data(view)["error"] == "unauthorized"
  end

  test "replaced sessions can be recovered archived; only the owner can purge", ctx do
    Repo.update!(Ecto.Changeset.change(ctx.session, deleted_at: %{TimeHelpers.now() | microsecond: {0, 6}}))
    {:ok, view, _} = live(log_in_user(ctx.conn, ctx.facilitator.user), board_path(ctx))
    render_hook(view, "purge_session", %{epoch: data(view)["epoch"], session_id: ctx.session.id, revision: 1})
    assert_reply(view, %{status: "error", code: "unauthorized"})
    render_hook(view, "recover_session", %{epoch: data(view)["epoch"], session_id: ctx.session.id, revision: 1})
    assert_reply(view, %{status: "ok"})
    assert %{status: :archived, deleted_at: nil} = Repo.get!(Session, ctx.session.id)
  end

  test "double invalidations coalesce and an invalidation during a read queues another read", ctx do
    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        refresh_running: nil,
        refresh_timer: nil,
        refresh_dirty: false,
        session_id: ctx.session.id,
        board: BoardData.empty()
      }
    }

    {:noreply, first} = Board.handle_info({:ideation_changed, ctx.session.id}, socket)
    {:noreply, second} = Board.handle_info({:ideation_changed, ctx.session.id}, first)
    assert first.assigns.refresh_timer == second.assigns.refresh_timer
    Process.cancel_timer(first.assigns.refresh_timer)
    token = make_ref()
    running = Phoenix.Component.assign(socket, refresh_running: token)
    {:noreply, dirty} = Board.handle_info({:ideation_changed, ctx.session.id}, running)
    assert dirty.assigns.refresh_dirty
    {:noreply, next} = Board.handle_async({:board, token}, {:ok, {:ok, %{secret: "stale"}}}, dirty)
    assert next.assigns.board == BoardData.empty()
    assert is_reference(next.assigns.refresh_timer)
    Process.cancel_timer(next.assigns.refresh_timer)
    assert {:noreply, ^next} = Board.handle_async({:board, make_ref()}, {:ok, {:ok, %{}}}, next)
  end

  defp board_path(ctx, id \\ nil) do
    base = ~p"/workspaces/#{ctx.project.workspace.slug}/projects/#{ctx.project.slug}/brainstorming"
    if id, do: "#{base}/#{id}", else: base
  end

  defp data(view), do: LiveVue.Test.get_vue(view, name: "live/ideation/BrainstormingBoard").props["board"]
  defp payload(view, attrs), do: Map.merge(attrs, %{epoch: data(view)["epoch"], session_id: data(view)["session"]["id"]})

  defp assert_board_eventually(view, assertion, attempts \\ 200)

  defp assert_board_eventually(view, assertion, attempts) when attempts > 1 do
    render_async(view)

    try do
      assertion.(data(view))
    rescue
      ExUnit.AssertionError ->
        Process.sleep(10)
        assert_board_eventually(view, assertion, attempts - 1)
    end
  end

  defp assert_board_eventually(view, assertion, 1), do: assertion.(data(view))
end
