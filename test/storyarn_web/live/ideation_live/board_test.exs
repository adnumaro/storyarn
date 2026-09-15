defmodule StoryarnWeb.IdeationLive.BoardTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.IdeationFixtures

  alias Phoenix.LiveView.Socket
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
    assert Repo.get_by!(Storyarn.Ideation.Ideas.Edit, idea_id: idea.id, outcome: :conflict)

    render_hook(view, "save_idea", payload(view, edit_attrs(%{idea_id: idea.id, revision: 1, state: "parked"})))
    assert_reply(view, %{status: "conflict", value: %{receipt: %{attempted: %{state: :parked}}}})
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

  test "bringing a note forward answers with the linked copy in the round in progress and refuses readers", ctx do
    original = idea_fixture(ctx)
    {ctx, second} = new_round(ctx)
    {:ok, view, _} = live(log_in_user(ctx.conn, ctx.author.user), board_path(ctx, ctx.session.id))

    render_hook(
      view,
      "bring_idea_forward",
      payload(view, %{idea_id: original.id, request_key: Ecto.UUID.generate(), canvas: %{x: 12, y: 30}})
    )

    assert_reply(view, %{status: "ok", value: %{id: id, source_idea_id: source, round_id: round_id, canvas: canvas}})
    assert id != original.id
    assert source == original.id
    assert round_id == second.id
    assert {12, 30} == {canvas["x"], canvas["y"]}
    assert_board_eventually(view, fn board -> assert length(board["ideas"]) == 2 end)

    {:ok, viewer, _} = live(log_in_user(ctx.conn, ctx.viewer.user), board_path(ctx, ctx.session.id))

    render_hook(
      viewer,
      "bring_idea_forward",
      payload(viewer, %{idea_id: original.id, request_key: Ecto.UUID.generate()})
    )

    assert_reply(viewer, %{status: "error", code: "unauthorized"})
    render_hook(view, "bring_idea_forward", payload(view, %{idea_id: "x", request_key: Ecto.UUID.generate()}))
    assert_reply(view, %{status: "error", code: "invalid_parameters"})
  end

  test "the session panel opens and closes through its event, and ignores anything else", ctx do
    {:ok, view, _} = live(log_in_user(ctx.conn, ctx.author.user), board_path(ctx, ctx.session.id))
    render_hook(view, "session_panel", payload(view, %{open: true}))
    assert panels(view)["session-panel"] == true
    render_hook(view, "session_panel", payload(view, %{open: false}))
    assert panels(view)["session-panel"] == false
    assert Process.alive?(view.pid)
  end

  test "paste is sanitized on save and returned as inert content on reload", ctx do
    {:ok, view, _} = live(log_in_user(ctx.conn, ctx.author.user), board_path(ctx, ctx.session.id))
    render_hook(view, "create_idea", payload(view, idea_attrs(%{body: "<p>Hello<script>alert(1)</script></p>"})))
    assert_reply(view, %{status: "ok", value: %{id: id, body: body}})
    refute body =~ "<script"
    assert body =~ "alert(1)"
    assert {:ok, %{body: ^body}} = Ideation.get_idea(ctx.author, ctx.project.id, ctx.session.id, id)
  end

  test "delete exposes an undo marker and restore returns the same authored note", ctx do
    idea = idea_fixture(ctx)
    {:ok, view, _} = live(log_in_user(ctx.conn, ctx.author.user), board_path(ctx, ctx.session.id))
    render_hook(view, "delete_idea", payload(view, %{idea_id: idea.id, revision: idea.revision}))
    assert_reply(view, %{status: "ok", value: %{id: id, revision: revision, deleted_at: marker}})
    assert id == idea.id

    render_hook(
      view,
      "restore_idea",
      payload(view, %{idea_id: id, revision: revision, deleted_at: DateTime.to_iso8601(marker)})
    )

    assert_reply(view, %{status: "ok", value: %{id: ^id, revision: 2, body: body, deleted_at: nil}})
    assert body == idea.body
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

    render_hook(
      author,
      "save_idea",
      payload(author, edit_attrs(%{idea_id: first.id, revision: 1, title: "First draft"}))
    )

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
    old_payload = payload(view, %{idea_id: idea.id, revision: idea.revision})
    membership = Projects.get_membership(ctx.project.id, ctx.author.user.id)
    assert {:ok, _} = Projects.remove_member(ctx.owner, ctx.project.id, membership.id)
    render_hook(view, "delete_idea", old_payload)
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
    references = %{open: true, items: [%{id: 1}], results: [%{name: "Current search"}], history: [%{number: 1}]}

    socket = %Socket{
      assigns: %{
        __changed__: %{},
        refresh_running: nil,
        refresh_timer: nil,
        refresh_dirty: false,
        session_id: ctx.session.id,
        references: references,
        board: BoardData.empty()
      }
    }

    {:noreply, first} = Board.handle_info({:ideation_changed, ctx.session.id}, socket)
    {:noreply, second} = Board.handle_info({:ideation_changed, ctx.session.id}, first)
    {:noreply, third} = Board.handle_info({:ideation_sessions_changed, ctx.project.id}, second)
    assert first.assigns.refresh_timer == second.assigns.refresh_timer
    assert second.assigns.refresh_timer == third.assigns.refresh_timer
    assert first.assigns.references == references
    assert second.assigns.references == references
    assert third.assigns.references == references
    Process.cancel_timer(first.assigns.refresh_timer)
    token = make_ref()
    running = Phoenix.Component.assign(socket, refresh_running: token)
    {:noreply, dirty} = Board.handle_info({:ideation_changed, ctx.session.id}, running)
    assert dirty.assigns.refresh_dirty
    assert dirty.assigns.references == references
    {:noreply, next} = Board.handle_async({:board, token}, {:ok, {:ok, %{secret: "stale"}}}, dirty)
    assert next.assigns.board == BoardData.empty()
    assert is_reference(next.assigns.refresh_timer)
    Process.cancel_timer(next.assigns.refresh_timer)
    assert {:noreply, ^next} = Board.handle_async({:board, make_ref()}, {:ok, {:ok, %{}}}, next)
  end

  test "board loading remains true for queued, active and follow-up reads", ctx do
    {:ok, view, _} = live(log_in_user(ctx.conn, ctx.author.user), board_path(ctx, ctx.session.id))
    socket = :sys.get_state(view.pid).socket

    for {timer, running, dirty, expected} <- [
          {nil, nil, false, false},
          {make_ref(), nil, false, true},
          {nil, make_ref(), false, true},
          {nil, nil, true, true}
        ] do
      assigns =
        Map.merge(socket.assigns, %{
          __changed__: nil,
          refresh_timer: timer,
          refresh_running: running,
          refresh_dirty: dirty
        })

      # Match the render-time socket shape used by LiveView for nested layouts.
      render_socket = %{socket | assigns: %Socket.AssignsNotInSocket{__assigns__: assigns}}
      html = render_component(&Board.render/1, Map.put(assigns, :socket, render_socket))
      board = LiveVue.Test.get_vue(html, name: "live/ideation/BrainstormingBoard").props["board"]
      assert board["loading"] == expected
    end
  end

  test "consecutive sidebar creations acknowledge each request and patch the existing board", ctx do
    {:ok, view, _} = live(log_in_user(ctx.conn, ctx.author.user), board_path(ctx))
    {:ok, another_tab, _} = live(log_in_user(ctx.conn, ctx.author.user), board_path(ctx, ctx.session.id))
    {:ok, peer, _} = live(log_in_user(ctx.conn, ctx.peer.user), board_path(ctx, ctx.session.id))
    transports = Enum.map([view, another_tab, peer], fn board -> :sys.get_state(board.pid).socket.transport_pid end)
    assert length(Enum.uniq(transports)) == 3
    sidebar = find_live_child(view, "sidebar-brainstorming-#{ctx.project.id}")
    epoch = LiveVue.Test.get_vue(sidebar, name: "live/ideation/BoardSidebar").props["board"]["epoch"]

    for _ <- 1..2 do
      render_hook(sidebar, "create_session", %{epoch: epoch, session_id: nil})
      assert_reply(sidebar, %{status: "ok", value: %{id: id}})
      assert_patch(view, board_path(ctx, id), 2_000)
      assert data(view)["session"]["id"] == id
      assert {:ok, %{title: "Untitled session"}} = Ideation.get_session(ctx.author, ctx.project.id, id)
      assert find_live_child(view, "sidebar-brainstorming-#{ctx.project.id}").pid == sidebar.pid

      for other <- [another_tab, peer] do
        render_async(other)
        assert data(other)["session"]["id"] == ctx.session.id
      end
    end
  end

  test "unknown board actions return a typed error without terminating the board", ctx do
    {:ok, view, _} = live(log_in_user(ctx.conn, ctx.author.user), board_path(ctx, ctx.session.id))

    for params <- [%{action: "unknown"}, %{}] do
      render_hook(view, "board_action", params)
      assert_reply(view, %{status: "error", code: "invalid_parameters"})
      assert data(view)["session"]["id"] == ctx.session.id
    end
  end

  test "the settings action opens the session panel in the dock and closing it puts it away", ctx do
    {:ok, view, _} = live(log_in_user(ctx.conn, ctx.author.user), board_path(ctx, ctx.session.id))
    refute panels(view)["session-panel"]
    render_hook(view, "board_action", payload(view, %{action: "settings"}))
    assert panels(view)["session-panel"]
    assert panels(view)["session"]["id"] == ctx.session.id
    assert panels(view)["can-manage"] == false
    render_hook(view, "session_panel", payload(view, %{open: false}))
    refute panels(view)["session-panel"]
  end

  test "a role downgrade preserves readable notes and the draft epoch after a rejected write", ctx do
    idea = idea_fixture(ctx)
    hidden = idea_fixture(ctx, %{body: "A peer's private text"}, ctx.peer)
    {:ok, view, _} = live(log_in_user(ctx.conn, ctx.author.user), board_path(ctx, ctx.session.id))
    old_epoch = data(view)["epoch"]
    membership = Projects.get_membership(ctx.project.id, ctx.author.user.id)
    assert {:ok, _} = Projects.update_member_role(ctx.owner, ctx.project.id, membership.id, "viewer")

    assert_board_eventually(view, fn board ->
      refute board["can_edit"]
      assert board["epoch"] == old_epoch
      assert [%{"id" => id}] = board["ideas"]
      assert id == idea.id
      refute Enum.any?(board["ideas"], &(&1["id"] == hidden.id))
      assert board["error"] == nil
    end)

    render_hook(
      view,
      "save_idea",
      payload(view, edit_attrs(%{idea_id: idea.id, revision: idea.revision, body: "Unsaved"}))
    )

    assert_reply(view, %{status: "error", code: "unauthorized"})
    assert data(view)["epoch"] == old_epoch
    assert [%{"id" => id}] = data(view)["ideas"]
    assert id == idea.id
    refute_push_event(view, "brainstorming_reset", %{reason: "access_changed"})
  end

  test "membership removal invalidates the board and sticky sidebar without polling or a write", ctx do
    idea_fixture(ctx)
    {:ok, view, _} = live(log_in_user(ctx.conn, ctx.author.user), board_path(ctx, ctx.session.id))
    sidebar = find_live_child(view, "sidebar-brainstorming-#{ctx.project.id}")
    membership = Projects.get_membership(ctx.project.id, ctx.author.user.id)
    assert {:ok, _} = Projects.remove_member(ctx.owner, ctx.project.id, membership.id)

    assert_board_eventually(view, fn board ->
      assert board["error"] == "unauthorized"
      assert board["session"] == nil
      assert board["ideas"] == []
    end)

    sidebar_board = LiveVue.Test.get_vue(sidebar, name: "live/ideation/BoardSidebar").props["board"]
    assert sidebar_board["error"] == "unauthorized"
    assert sidebar_board["sessions"] == []
  end

  test "workspace role changes invalidate inherited access", ctx do
    direct = Projects.get_membership(ctx.project.id, ctx.author.user.id)
    assert {:ok, _} = Projects.remove_member(ctx.owner, ctx.project.id, direct.id)

    inherited =
      Storyarn.WorkspacesFixtures.workspace_membership_fixture(ctx.project.workspace, ctx.author.user, "member")

    {:ok, view, _} = live(log_in_user(ctx.conn, ctx.author.user), board_path(ctx, ctx.session.id))
    assert data(view)["can_edit"]

    assert {:ok, _} =
             Storyarn.Workspaces.update_member_role(ctx.owner, ctx.project.workspace.id, inherited.id, "viewer")

    assert_board_eventually(view, fn board ->
      refute board["can_edit"]
      assert board["session"]["id"] == ctx.session.id
    end)

    assert {:ok, _} = Storyarn.Workspaces.remove_member(ctx.owner, ctx.project.workspace.id, inherited.id)
    assert_board_eventually(view, fn board -> assert board["error"] == "unauthorized" end)
  end

  test "cursor delivery uses the authorized board without queries and hides private-mode cursors", ctx do
    socket = cursor_socket(ctx)
    parent = self()
    marker = make_ref()

    listener =
      Task.async(fn ->
        Storyarn.Platform.Collaboration.subscribe_changes({:ideation, ctx.session.id})
        send(parent, :cursor_listener_ready)

        receive do
          {:remote_change, :brainstorming_cursor, payload} -> payload
        after
          1_000 -> :missing
        end
      end)

    assert_receive :cursor_listener_ready
    handler = "ideation-cursor-#{inspect(marker)}"

    :ok =
      :telemetry.attach(
        handler,
        [:storyarn, :repo, :query],
        fn _, _, _, _ ->
          if self() == parent, do: send(parent, {:cursor_query, marker})
        end,
        nil
      )

    try do
      params = %{"epoch" => "cursor-epoch", "session_id" => ctx.session.id, "x" => 20, "y" => 30}
      assert {:noreply, sent} = Board.handle_event("canvas_cursor", params, socket)
      assert sent.assigns.last_cursor_at != 0
      payload = Task.await(listener)
      assert payload.name == "Member"
      refute Jason.encode!(payload) =~ ctx.author.user.email
      assert {:noreply, received} = Board.handle_info({:remote_change, :brainstorming_cursor, payload}, socket)
      assert [["canvas_cursor", %{x: 20, y: 30}]] = Phoenix.LiveView.Utils.get_push_events(received)
      private_board = put_in(socket.assigns.board.active_round.private, true)
      assert {:noreply, ^private_board} = Board.handle_event("canvas_cursor", params, private_board)

      assert {:noreply, ^private_board} =
               Board.handle_info({:remote_change, :brainstorming_cursor, payload}, private_board)

      invalidated = Phoenix.Component.assign(socket, :canvas_ready, false)
      assert {:noreply, ^invalidated} = Board.handle_info({:remote_change, :brainstorming_cursor, payload}, invalidated)
      refute_receive {:cursor_query, ^marker}
    after
      :telemetry.detach(handler)
      Task.shutdown(listener, :brutal_kill)
    end
  end

  defp cursor_socket(ctx) do
    %Socket{
      private: %{live_temp: %{}},
      assigns: %{
        __changed__: %{},
        current_scope: ctx.author,
        session_id: ctx.session.id,
        epoch: "cursor-epoch",
        last_cursor_at: 0,
        canvas_scope: {:ideation, ctx.session.id},
        canvas_ready: true,
        board_error: nil,
        board: %{
          session: %{id: ctx.session.id},
          active_round: %{id: 1, private: false},
          members: [%{id: ctx.author.user.id}]
        }
      }
    }
  end

  test "round actions share metadata and preserve private mode and editing after closing", ctx do
    assert {:ok, _} =
             Storyarn.IdeationFixtures.set_private_mode(ctx.facilitator, ctx.project.id, ctx.session.id, 1, true)

    assert {:ok, session} = Ideation.get_session(ctx.facilitator, ctx.project.id, ctx.session.id)
    first = first_round(ctx)
    {:ok, view, _} = live(log_in_user(ctx.conn, ctx.facilitator.user), board_path(ctx, session.id))
    {:ok, participant, _} = live(log_in_user(build_conn(), ctx.author.user), board_path(ctx, session.id))
    assert [%{"status" => "active"}] = data(view)["rounds"]

    render_hook(
      view,
      "new_round",
      payload(view, %{revision: session.revision, prompt: "What motivates the rival?"})
    )

    assert_reply(view, %{status: "ok"})

    assert_board_eventually(view, fn board ->
      assert [%{"status" => "closed"}, %{"status" => "active"}] = board["rounds"]
    end)

    [closed, round] = data(view)["rounds"]
    assert closed["id"] == first.id
    refute Map.has_key?(round, "recovery_identity")

    # Privacy is not inherited: the new round is set private on its own.
    render_hook(
      view,
      "set_round_privacy",
      payload(view, %{revision: data(view)["session"]["revision"], round_id: round["id"], private: true})
    )

    assert_reply(view, %{status: "ok"})

    # Going private fences everyone's board; what follows must keep the new epoch.
    assert_board_eventually(view, fn board -> assert board["active_round"]["private"] end)
    assert_board_eventually(participant, fn board -> assert board["active_round"]["private"] end)
    assert data(participant)["active_round"]["id"] == round["id"]
    epoch = data(participant)["epoch"]

    render_hook(
      view,
      "close_round",
      payload(view, %{revision: data(view)["session"]["revision"], round_id: round["id"]})
    )

    assert_reply(view, %{status: "ok"})

    assert_board_eventually(participant, fn board ->
      assert board["active_round"] == nil
      assert [%{"status" => "closed"}, %{"status" => "closed"}] = board["rounds"]
      assert Enum.all?(board["rounds"], & &1["private"])
      assert board["can_edit"]
      assert board["epoch"] == epoch
    end)

    render_hook(
      participant,
      "create_idea",
      payload(participant, idea_attrs(%{round_id: "#{round["id"]}", body: "Late draft"}))
    )

    assert_reply(participant, %{
      status: "ok",
      value: %{id: id, round_id: round_id, late_contribution: true, visibility: :private}
    })

    assert round_id == round["id"]

    render_hook(
      participant,
      "save_idea",
      payload(participant, edit_attrs(%{idea_id: id, revision: 1, body: "Continued after closing"}))
    )

    assert_reply(participant, %{status: "ok", value: %{round_id: ^round_id, visibility: :private}})
    refute Jason.encode!(data(view)) =~ "Late draft"
    refute Jason.encode!(data(view)) =~ "Continued after closing"
  end

  test "round actions require the current board, current revision and managerial edit permission", ctx do
    round = first_round(ctx)
    {:ok, view, _} = live(log_in_user(ctx.conn, ctx.author.user), board_path(ctx, ctx.session.id))

    for event <- ["new_round", "update_round", "close_round"] do
      render_hook(view, event, payload(view, %{revision: 1, round_id: round.id}))
      assert_reply(view, %{status: "error", code: "unauthorized"})
    end

    {:ok, manager, _} = live(log_in_user(build_conn(), ctx.facilitator.user), board_path(ctx, ctx.session.id))
    render_hook(manager, "close_round", payload(manager, %{revision: 3, round_id: round.id}))
    assert_reply(manager, %{status: "error", code: "stale_revision"})
    render_hook(manager, "new_round", %{epoch: data(manager)["epoch"], session_id: -1, revision: 1})
    assert_reply(manager, %{status: "error", code: "stale_board"})
    {:ok, readonly, _} = live(log_in_user(build_conn(), ctx.viewer.user), board_path(ctx, ctx.session.id))
    render_hook(readonly, "close_round", payload(readonly, %{revision: 1, round_id: round.id}))
    assert_reply(readonly, %{status: "error", code: "unauthorized"})
    assert data(readonly)["active_round"]["id"] == round.id
  end

  test "the question of the round in progress can be corrected in every participant's context", ctx do
    round = first_round(ctx)
    {:ok, manager, _} = live(log_in_user(ctx.conn, ctx.facilitator.user), board_path(ctx, ctx.session.id))
    {:ok, peer, _} = live(log_in_user(build_conn(), ctx.peer.user), board_path(ctx, ctx.session.id))
    epoch = data(peer)["epoch"]

    render_hook(
      manager,
      "update_round",
      payload(manager, %{revision: "1", round_id: "#{round.id}", prompt: "Corrected"})
    )

    assert_reply(manager, %{status: "ok"})
    assert_board_eventually(manager, fn board -> assert board["session"]["revision"] == 2 end)

    assert_board_eventually(peer, fn board ->
      assert [%{"prompt" => "Corrected", "status" => "active"}] = board["rounds"]
      assert board["active_round"]["prompt"] == "Corrected"
      assert board["epoch"] == epoch
      assert board["can_edit"]
    end)

    render_hook(manager, "close_round", payload(manager, %{revision: 2, round_id: round.id}))
    assert_reply(manager, %{status: "ok"})
    assert_board_eventually(manager, fn board -> assert board["active_round"] == nil end)
    render_hook(manager, "update_round", payload(manager, %{revision: 3, round_id: round.id, prompt: "Later"}))
    assert_reply(manager, %{status: "error", code: "round_not_active"})
  end

  test "creation rejects explicit no-round, omitted round uses the one in progress and malformed IDs fail", ctx do
    round = first_round(ctx)
    {:ok, view, _} = live(log_in_user(ctx.conn, ctx.author.user), board_path(ctx, ctx.session.id))
    render_hook(view, "create_idea", payload(view, idea_attrs(%{round_id: nil})))
    assert_reply(view, %{status: "error", code: "round_required"})
    render_hook(view, "create_idea", payload(view, idea_attrs()))
    assert_reply(view, %{status: "ok", value: %{round_id: id, late_contribution: false}})
    assert id == round.id

    for invalid <- ["all", "", "1.0", -1, 0, %{}, "9007199254740992"] do
      render_hook(view, "create_idea", payload(view, idea_attrs(%{round_id: invalid})))
      assert_reply(view, %{status: "error", code: "invalid_parameters"})
    end
  end

  test "the canvas receives every round in band order and deep links focus a band or the parked list", ctx do
    first = first_round(ctx)
    idea_fixture(ctx, %{visibility: :shared, state: :parked})

    Enum.reduce(1..60, 1, fn number, revision ->
      {:ok, session} =
        Ideation.new_round(ctx.facilitator, ctx.project.id, ctx.session.id, revision, %{prompt: "Question #{number}"})

      session.revision
    end)

    {:ok, view, _} = live(log_in_user(ctx.conn, ctx.author.user), board_path(ctx, ctx.session.id))
    rounds = data(view)["rounds"]
    assert length(rounds) == 61
    assert Enum.map(rounds, & &1["number"]) == Enum.to_list(1..61)
    refute Enum.any?(rounds, &Map.has_key?(&1, "canvas_offset_y"))
    assert data(view)["active_round"]["number"] == 61
    refute Map.has_key?(data(view), "rounds_next")
    refute Map.has_key?(data(view), "round_filter")
    assert data(view)["counts"] == %{"active" => 0, "parked" => 1, "discarded" => 0}

    {:ok, linked, _} =
      live(log_in_user(build_conn(), ctx.author.user), board_path(ctx, ctx.session.id) <> "?round=#{first.id}")

    first_id = first.id
    assert %{"round_id" => ^first_id, "view" => nil, "seq" => 1} = link(linked)

    {:ok, list, _} =
      live(log_in_user(build_conn(), ctx.author.user), board_path(ctx, ctx.session.id) <> "?view=later")

    assert %{"round_id" => nil, "view" => "later", "seq" => 1} = link(list)

    {:ok, plain, _} =
      live(log_in_user(build_conn(), ctx.author.user), board_path(ctx, ctx.session.id) <> "?round=abc")

    assert %{"round_id" => nil, "view" => nil, "seq" => 1} = link(plain)
  end

  test "the session tree carries each session's rounds and its parked count", ctx do
    first = first_round(ctx)
    idea_fixture(ctx, %{visibility: :shared, state: :parked})
    {:ok, _} = Ideation.new_round(ctx.facilitator, ctx.project.id, ctx.session.id, 1, %{})
    {:ok, other} = Ideation.create_session(ctx.facilitator, ctx.project.id, %{title: "Other"})
    {:ok, view, _} = live(log_in_user(ctx.conn, ctx.viewer.user), board_path(ctx))
    sidebar = LiveVue.Test.get_vue(view, name: "live/ideation/BoardSidebar")
    sessions = sidebar.props["board"]["sessions"]
    mine = Enum.find(sessions, &(&1["id"] == ctx.session.id))
    assert Enum.map(mine["rounds"], & &1["number"]) == [1, 2]
    assert hd(mine["rounds"])["id"] == first.id
    assert mine["parked_count"] == 1
    assert Enum.find(sessions, &(&1["id"] == other.id))["parked_count"] == 0
    assert length(Enum.find(sessions, &(&1["id"] == other.id))["rounds"]) == 1
  end

  defp board_path(ctx, id \\ nil) do
    base = ~p"/workspaces/#{ctx.project.workspace.slug}/projects/#{ctx.project.slug}/brainstorming"
    if id, do: "#{base}/#{id}", else: base
  end

  defp data(view), do: LiveVue.Test.get_vue(view, name: "live/ideation/BrainstormingBoard").props["board"]
  defp link(view), do: LiveVue.Test.get_vue(view, name: "live/ideation/BrainstormingBoard").props["linked"]
  defp panels(view), do: LiveVue.Test.get_vue(view, name: "live/ideation/BoardPanels").props

  defp payload(view, attrs),
    do: Map.merge(attrs, %{epoch: data(view)["epoch"], session_id: data(view)["session"]["id"]})

  defp assert_board_eventually(view, assertion, attempts \\ 200)

  defp assert_board_eventually(view, assertion, attempts) when attempts > 1 do
    # The board loads asynchronously; under a full-suite load it can exceed the default 500 ms.
    render_async(view, 2_000)

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
