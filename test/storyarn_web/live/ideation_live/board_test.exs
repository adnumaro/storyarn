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
    socket = %Socket{
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
      assert_patch(view, board_path(ctx, id))
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
      private_board = put_in(socket.assigns.board.session.configuration.private_mode, true)
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
          session: %{id: ctx.session.id, configuration: %{private_mode: false}},
          members: [%{id: ctx.author.user.id}]
        }
      }
    }
  end

  test "round controls share metadata and preserve private mode and editing after closing", ctx do
    assert {:ok, _} = Ideation.set_private_mode(ctx.facilitator, ctx.project.id, ctx.session.id, 1, true)
    assert {:ok, session} = Ideation.get_session(ctx.facilitator, ctx.project.id, ctx.session.id)
    {:ok, view, _} = live(log_in_user(ctx.conn, ctx.facilitator.user), board_path(ctx, session.id))
    {:ok, participant, _} = live(log_in_user(build_conn(), ctx.author.user), board_path(ctx, session.id))
    render_hook(view, "create_round", payload(view, %{revision: session.revision, prompt: "What motivates the rival?"}))
    assert_reply(view, %{status: "ok"})
    assert_board_eventually(view, fn board -> assert [%{"status" => "planned"}] = board["rounds"] end)
    [round] = data(view)["rounds"]
    refute Map.has_key?(round, "recovery_identity")

    render_hook(
      view,
      "start_round",
      payload(view, %{revision: data(view)["session"]["revision"], round_id: round["id"]})
    )

    assert_reply(view, %{status: "ok"})
    assert_board_eventually(participant, fn board -> assert board["active_round"]["id"] == round["id"] end)
    assert_board_eventually(view, fn board -> assert board["active_round"]["id"] == round["id"] end)
    # Read initial header props; subsequent updates use production prop diffs.
    {:ok, header_view, _} = live(log_in_user(build_conn(), ctx.author.user), board_path(ctx, session.id))
    assert_board_eventually(header_view, fn board -> assert board["active_round"]["id"] == round["id"] end)
    header = LiveVue.Test.get_vue(header_view, name: "live/ideation/BoardHeader")
    assert header.props["active-round"]["prompt"] == round["prompt"]
    epoch = data(participant)["epoch"]

    render_hook(
      view,
      "close_round",
      payload(view, %{revision: data(view)["session"]["revision"], round_id: round["id"]})
    )

    assert_reply(view, %{status: "ok"})

    assert_board_eventually(participant, fn board ->
      assert board["active_round"] == nil
      assert [%{"status" => "closed"}] = board["rounds"]
      assert board["session"]["configuration"]["private_mode"]
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
    round = active_round(ctx)
    {:ok, view, _} = live(log_in_user(ctx.conn, ctx.author.user), board_path(ctx, ctx.session.id))

    for event <- ["create_round", "update_round", "cancel_round", "start_round", "close_round"] do
      render_hook(view, event, payload(view, %{revision: 3, round_id: round.id}))
      assert_reply(view, %{status: "error", code: "unauthorized"})
    end

    {:ok, manager, _} = live(log_in_user(build_conn(), ctx.facilitator.user), board_path(ctx, ctx.session.id))
    render_hook(manager, "close_round", payload(manager, %{revision: 1, round_id: round.id}))
    assert_reply(manager, %{status: "error", code: "stale_revision"})
    render_hook(manager, "create_round", %{epoch: data(manager)["epoch"], session_id: -1, revision: 3})
    assert_reply(manager, %{status: "error", code: "stale_board"})
    {:ok, readonly, _} = live(log_in_user(build_conn(), ctx.viewer.user), board_path(ctx, ctx.session.id))
    render_hook(readonly, "close_round", payload(readonly, %{revision: 3, round_id: round.id}))
    assert_reply(readonly, %{status: "error", code: "unauthorized"})
    assert data(readonly)["active_round"]["id"] == round.id
  end

  test "prepared questions can be corrected and cancelled in every participant's context", ctx do
    {:ok, _} = Ideation.create_round(ctx.facilitator, ctx.project.id, ctx.session.id, 1, %{prompt: "A typo"})
    {:ok, [round]} = Ideation.list_rounds(ctx.facilitator, ctx.project.id, ctx.session.id)
    {:ok, manager, _} = live(log_in_user(ctx.conn, ctx.facilitator.user), board_path(ctx, ctx.session.id))
    {:ok, peer, _} = live(log_in_user(build_conn(), ctx.peer.user), board_path(ctx, ctx.session.id))
    epoch = data(peer)["epoch"]

    render_hook(
      manager,
      "update_round",
      payload(manager, %{revision: "2", round_id: "#{round.id}", prompt: "Corrected"})
    )

    assert_reply(manager, %{status: "ok"})
    assert_board_eventually(manager, fn board -> assert board["session"]["revision"] == 3 end)
    assert_board_eventually(peer, fn board -> assert [%{"prompt" => "Corrected"}] = board["rounds"] end)

    render_hook(manager, "cancel_round", payload(manager, %{revision: 3, round_id: round.id}))
    assert_reply(manager, %{status: "ok"})

    assert_board_eventually(peer, fn board ->
      assert [%{"status" => "cancelled", "prompt" => "Corrected"}] = board["rounds"]
      assert board["epoch"] == epoch
      assert board["can_edit"]
      assert board["active_round"] == nil
    end)

    assert_board_eventually(manager, fn board -> assert board["session"]["revision"] == 4 end)
    render_hook(manager, "start_round", payload(manager, %{revision: 4, round_id: round.id}))
    assert_reply(manager, %{status: "error", code: "round_cancelled"})
  end

  test "creation preserves explicit no-round while omitted round uses active and malformed IDs fail", ctx do
    round = active_round(ctx)
    {:ok, view, _} = live(log_in_user(ctx.conn, ctx.author.user), board_path(ctx, ctx.session.id))
    render_hook(view, "create_idea", payload(view, idea_attrs(%{round_id: nil})))
    assert_reply(view, %{status: "ok", value: %{round_id: nil, late_contribution: false}})
    render_hook(view, "create_idea", payload(view, idea_attrs()))
    assert_reply(view, %{status: "ok", value: %{round_id: id, late_contribution: false}})
    assert id == round.id

    for invalid <- ["all", "", "1.0", -1, 0, %{}, "9007199254740992"] do
      render_hook(view, "create_idea", payload(view, idea_attrs(%{round_id: invalid})))
      assert_reply(view, %{status: "error", code: "invalid_parameters"})
    end
  end

  test "round filtering pages the selected round, rejects foreign IDs and never resets the board", ctx do
    outside = idea_fixture(ctx, %{visibility: :shared})
    first = active_round(ctx)
    first_notes = for _ <- 1..52, do: idea_fixture(ctx, %{visibility: :shared})
    {:ok, _} = Ideation.close_round(ctx.facilitator, ctx.project.id, ctx.session.id, first.id, 3)
    second = active_round(ctx)
    for _ <- 1..51, do: idea_fixture(ctx, %{visibility: :shared})
    private = idea_fixture(ctx)
    {:ok, view, _} = live(log_in_user(ctx.conn, ctx.viewer.user), board_path(ctx, ctx.session.id))
    epoch = data(view)["epoch"]
    render_hook(view, "filter_round", payload(view, %{round_id: first.id}))
    assert_reply(view, %{status: "ok"})

    assert_board_eventually(view, fn board ->
      assert board["round_filter"] == first.id
      assert length(board["ideas"]) == 50
      assert Enum.all?(board["ideas"], &(&1["round_id"] == first.id))
      assert board["counts"]["active"] == 52
      assert board["active_round"]["id"] == second.id
    end)

    render_hook(view, "browse_ideas", payload(view, %{before_id: data(view)["ideas_next"]}))
    assert_reply(view, %{status: "ok"})

    assert_board_eventually(view, fn board ->
      assert Enum.map(board["ideas"], & &1["id"]) == Enum.reverse(Enum.map(first_notes, & &1.id))
    end)

    # Undo after filtering can request the previously loaded range. It must not
    # lose an older command at the first page or include another author's draft.
    oldest = hd(first_notes).id
    render_hook(view, "filter_round", payload(view, %{round_id: "all", before_id: to_string(oldest)}))
    assert_reply(view, %{status: "ok"})

    assert_board_eventually(view, fn board ->
      assert board["round_filter"] == "all"
      assert board["idea_before"] == oldest
      assert length(board["ideas"]) == 104
      assert Enum.any?(board["ideas"], &(&1["id"] == oldest))
      refute Enum.any?(board["ideas"], &(&1["id"] == private.id))
      assert board["epoch"] == epoch
    end)

    render_hook(view, "filter_round", payload(view, %{round_id: nil}))
    assert_reply(view, %{status: "ok"})

    assert_board_eventually(view, fn board ->
      assert [%{"id" => id}] = board["ideas"]
      assert id == outside.id
      assert board["round_filter"] == nil
      assert board["epoch"] == epoch
    end)

    render_hook(view, "filter_round", payload(view, %{round_id: -1}))
    assert_reply(view, %{status: "error", code: "invalid_parameters"})
    render_hook(view, "filter_round", payload(view, %{round_id: "all", before_id: "invalid"}))
    assert_reply(view, %{status: "error", code: "invalid_parameters"})
    render_hook(view, "filter_round", payload(view, %{round_id: 9_007_199_254_740_991}))
    assert_reply(view, %{status: "error", code: "round_not_found"})
    assert data(view)["round_filter"] == nil
    refute Enum.any?(data(view)["ideas"], &(&1["id"] == private.id))
    refute_push_event(view, "brainstorming_reset", %{reason: "access_changed"})

    render_hook(view, "filter_round", payload(view, %{round_id: first.id}))
    assert_reply(view, %{status: "ok"})
    send(view.pid, {:project_restored, 1})
    render(view)
    assert_board_eventually(view, fn board -> assert board["round_filter"] == "all" end)
  end

  test "active and selected rounds remain available beyond the loaded history page", ctx do
    active = active_round(ctx)

    Enum.reduce(1..51, 3, fn number, revision ->
      {:ok, session} =
        Ideation.create_round(ctx.facilitator, ctx.project.id, ctx.session.id, revision, %{prompt: "Planned #{number}"})

      session.revision
    end)

    {:ok, view, _} = live(log_in_user(ctx.conn, ctx.author.user), board_path(ctx, ctx.session.id))
    assert data(view)["active_round"]["id"] == active.id
    assert length(data(view)["rounds"]) == 51

    render_hook(view, "filter_round", payload(view, %{round_id: active.id}))
    assert_reply(view, %{status: "ok"})
    assert_board_eventually(view, fn board -> assert board["round_filter"] == active.id end)
    {:ok, current} = Ideation.get_session(ctx.facilitator, ctx.project.id, ctx.session.id)
    {:ok, _} = Ideation.close_round(ctx.facilitator, ctx.project.id, ctx.session.id, active.id, current.revision)

    assert_board_eventually(view, fn board ->
      assert board["active_round"] == nil
      assert board["round_filter"] == active.id
      assert board["ideas"] == []
      assert Enum.any?(board["rounds"], &(&1["id"] == active.id and &1["status"] == "closed"))
    end)

    render_hook(view, "browse_rounds", payload(view, %{before_id: data(view)["rounds_next"]}))
    assert_reply(view, %{status: "ok"})

    assert_board_eventually(view, fn board ->
      assert length(board["rounds"]) == 52
      assert board["rounds_next"] == nil
    end)
  end

  defp active_round(ctx) do
    {:ok, session} = Ideation.get_session(ctx.facilitator, ctx.project.id, ctx.session.id)
    {:ok, prepared} = Ideation.create_round(ctx.facilitator, ctx.project.id, session.id, session.revision, %{})
    {:ok, [round]} = Ideation.list_rounds(ctx.facilitator, ctx.project.id, session.id, limit: 1)
    {:ok, _} = Ideation.start_round(ctx.facilitator, ctx.project.id, session.id, round.id, prepared.revision)
    round
  end

  defp board_path(ctx, id \\ nil) do
    base = ~p"/workspaces/#{ctx.project.workspace.slug}/projects/#{ctx.project.slug}/brainstorming"
    if id, do: "#{base}/#{id}", else: base
  end

  defp data(view), do: LiveVue.Test.get_vue(view, name: "live/ideation/BrainstormingBoard").props["board"]

  defp payload(view, attrs),
    do: Map.merge(attrs, %{epoch: data(view)["epoch"], session_id: data(view)["session"]["id"]})

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
