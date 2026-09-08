defmodule StoryarnWeb.IdeationLive.TimerBoardTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.IdeationFixtures

  alias Storyarn.Ideation
  alias Storyarn.Repo

  setup do
    ctx = ideation_fixture()
    %{ctx | project: Repo.preload(ctx.project, :workspace)}
  end

  test "timer controls cast integers and share only the public timer projection", ctx do
    {:ok, manager, _} = live(log_in_user(ctx.conn, ctx.facilitator.user), board_path(ctx))
    {:ok, viewer, _} = live(log_in_user(build_conn(), ctx.viewer.user), board_path(ctx))
    assert data(manager)["timer"] == nil
    assert data(manager)["session"]["contributions_open"]

    render_hook(
      manager,
      "start_timer",
      payload(manager, %{
        revision: "1",
        seconds: "600",
        reveal_on_expiry: false,
        close_contributions_on_expiry: false,
        actor_id: ctx.viewer.user.id,
        recovery_identity: Ecto.UUID.generate()
      })
    )

    assert_reply(manager, %{status: "ok", value: %{id: id, revision: 2}})
    assert id == ctx.session.id
    assert_board_eventually(manager, fn board -> assert board["timer"]["status"] == "running" end)
    assert_board_eventually(viewer, fn board -> assert board["timer"]["version"] == 1 end)
    timer = data(viewer)["timer"]

    assert Enum.sort(Map.keys(timer)) ==
             Enum.sort(
               ~w(id version status deadline_at remaining_seconds duration_seconds reveal_on_expiry close_contributions_on_expiry outcome server_now)
             )

    assert timer["duration_seconds"] == 600
    refute timer["reveal_on_expiry"]
    refute timer["close_contributions_on_expiry"]
    assert timer["outcome"] == nil
    assert {:ok, deadline, 0} = DateTime.from_iso8601(timer["deadline_at"])
    assert {:ok, server_now, 0} = DateTime.from_iso8601(timer["server_now"])
    assert DateTime.diff(deadline, server_now, :second) in 0..600
    # The header uses production prop diffs; inspect a fresh mount's full state.
    {:ok, fresh_viewer, _} = live(log_in_user(build_conn(), ctx.viewer.user), board_path(ctx))
    assert_board_eventually(fresh_viewer, fn board -> assert board["timer"]["status"] == "running" end)
    header = LiveVue.Test.get_vue(fresh_viewer, name: "live/ideation/BoardHeader")
    assert Map.delete(header.props["timer"], "server_now") == Map.delete(timer, "server_now")
    refute header.props["can-manage"]
    assert {:ok, stored} = Ideation.get_timer(ctx.facilitator, ctx.project.id, ctx.session.id)
    assert stored.actor_id == ctx.facilitator.user.id
    refute Jason.encode!(data(viewer)) =~ stored.recovery_identity
  end

  test "pause, extension, resume and cancellation synchronize versions without changing session privacy", ctx do
    {:ok, manager, _} = live(log_in_user(ctx.conn, ctx.facilitator.user), board_path(ctx))
    {:ok, peer, _} = live(log_in_user(build_conn(), ctx.peer.user), board_path(ctx))
    render_hook(manager, "start_timer", payload(manager, %{revision: "1", seconds: "600"}))
    assert_reply(manager, %{status: "ok"})
    assert_board_eventually(manager, fn board -> assert board["session"]["revision"] == 2 end)

    for {event, version, status, extra} <- [
          {"pause_timer", 1, "paused", %{}},
          {"extend_timer", 2, "paused", %{seconds: "60"}},
          {"resume_timer", 3, "running", %{}},
          {"cancel_timer", 4, "cancelled", %{}}
        ] do
      attrs =
        Map.merge(extra, %{revision: to_string(data(manager)["session"]["revision"]), timer_version: to_string(version)})

      render_hook(manager, event, payload(manager, attrs))
      expected_revision = version + 2
      assert_reply(manager, %{status: "ok", value: %{revision: ^expected_revision}})

      assert_board_eventually(manager, fn board ->
        assert board["timer"]["version"] == version + 1
        assert board["timer"]["status"] == status
      end)

      assert_board_eventually(peer, fn board -> assert board["timer"]["version"] == version + 1 end)
    end

    assert data(peer)["timer"]["duration_seconds"] == 660
    assert data(peer)["session"]["contributions_open"]
    assert data(peer)["session"]["configuration"]["private_mode"] == ctx.session.configuration.private_mode
    assert data(peer)["session"]["status"] == "open"
    assert data(peer)["can_edit"]
  end

  test "timer writes reject stale boards, revisions, versions and non-manager participants", ctx do
    shared = idea_fixture(ctx, %{visibility: :shared})
    assert {:ok, started} = Ideation.start_timer(ctx.facilitator, ctx.project.id, ctx.session.id, 1, %{seconds: 600})

    for actor <- [ctx.author, ctx.viewer] do
      {:ok, view, _} = live(log_in_user(build_conn(), actor.user), board_path(ctx))
      epoch = data(view)["epoch"]

      for event <- ~w(start_timer pause_timer resume_timer extend_timer cancel_timer set_contributions_open) do
        params = payload(view, %{revision: started.revision, timer_version: 1, seconds: 60, open: false})
        render_hook(view, event, params)
        assert_reply(view, %{status: "error", code: "unauthorized"})
      end

      assert data(view)["epoch"] == epoch
      assert [%{"id" => id}] = data(view)["ideas"]
      assert id == shared.id
      refute_push_event(view, "brainstorming_reset", %{reason: "access_changed"})
    end

    {:ok, manager, _} = live(log_in_user(ctx.conn, ctx.facilitator.user), board_path(ctx))
    attrs = payload(manager, %{revision: started.revision, timer_version: 1})
    render_hook(manager, "pause_timer", Map.put(attrs, :epoch, "old-board"))
    assert_reply(manager, %{status: "error", code: "stale_board"})
    render_hook(manager, "pause_timer", Map.put(attrs, :session_id, -1))
    assert_reply(manager, %{status: "error", code: "stale_board"})
    render_hook(manager, "pause_timer", Map.put(attrs, :revision, 1))
    assert_reply(manager, %{status: "error", code: "stale_revision"})
    render_hook(manager, "pause_timer", Map.put(attrs, :timer_version, 99))
    assert_reply(manager, %{status: "error", code: "stale_timer"})
    assert data(manager)["timer"]["status"] == "running"
  end

  test "malformed durations, versions and option types return typed errors without changing the timer", ctx do
    {:ok, manager, _} = live(log_in_user(ctx.conn, ctx.facilitator.user), board_path(ctx))

    for invalid <- ["15x", "1.5", 0, -1, nil, %{}, "9007199254740992"] do
      render_hook(manager, "start_timer", payload(manager, %{revision: "1", seconds: invalid}))
      assert_reply(manager, %{status: "error", code: "invalid_parameters"})
    end

    for invalid <- [14, 86_401] do
      render_hook(manager, "start_timer", payload(manager, %{revision: 1, seconds: invalid}))
      assert_reply(manager, %{status: "error", code: "invalid_timer_duration"})
    end

    render_hook(manager, "start_timer", payload(manager, %{revision: 1, seconds: 60, reveal_on_expiry: "true"}))
    assert_reply(manager, %{status: "error", code: "invalid_timer_options"})
    render_hook(manager, "start_timer", payload(manager, %{revision: 1, seconds: 60, reveal_on_expiry: true}))
    assert_reply(manager, %{status: "error", code: "timer_reveal_requires_private"})
    render_hook(manager, "set_contributions_open", payload(manager, %{revision: 1, open: "false"}))
    assert_reply(manager, %{status: "error", code: "invalid_parameters"})
    render_hook(manager, "pause_timer", payload(manager, %{revision: "1", timer_version: "1x"}))
    assert_reply(manager, %{status: "error", code: "invalid_parameters"})
    assert data(manager)["timer"] == nil
    assert data(manager)["session"]["revision"] == 1
  end

  test "closed contributions reject new creation while replay, editing, deletion and restoration keep the board usable",
       ctx do
    {:ok, author, _} = live(log_in_user(ctx.conn, ctx.author.user), board_path(ctx))
    {:ok, manager, _} = live(log_in_user(build_conn(), ctx.facilitator.user), board_path(ctx))
    creation = idea_attrs(%{body: "<p>Started before closing</p>"})
    render_hook(author, "create_idea", payload(author, creation))
    assert_reply(author, %{status: "ok", value: %{id: id}})
    epoch = data(author)["epoch"]
    render_hook(manager, "set_contributions_open", payload(manager, %{revision: "1", open: false}))
    assert_reply(manager, %{status: "ok"})

    assert_board_eventually(author, fn board ->
      refute board["session"]["contributions_open"]
      assert board["can_edit"]
      assert board["epoch"] == epoch
      assert [%{"id" => ^id}] = board["ideas"]
    end)

    render_hook(author, "create_idea", payload(author, creation))
    assert_reply(author, %{status: "ok", value: %{id: ^id}})
    render_hook(author, "create_idea", payload(author, idea_attrs()))
    assert_reply(author, %{status: "error", code: "contributions_closed"})
    assert data(author)["epoch"] == epoch
    assert [%{"id" => ^id}] = data(author)["ideas"]
    refute_push_event(author, "brainstorming_reset", %{reason: "access_changed"})

    render_hook(
      author,
      "save_idea",
      payload(author, edit_attrs(%{idea_id: id, revision: 1, body: "<p>Still editable</p>"}))
    )

    assert_reply(author, %{status: "ok", value: %{revision: 2}})
    render_hook(author, "delete_idea", payload(author, %{idea_id: id, revision: 2}))
    assert_reply(author, %{status: "ok", value: %{id: ^id, revision: revision, deleted_at: deleted_at}})
    render_hook(author, "restore_idea", payload(author, %{idea_id: id, revision: revision, deleted_at: deleted_at}))
    assert_reply(author, %{status: "ok", value: %{id: ^id, body: "<p>Still editable</p>"}})

    assert_board_eventually(manager, fn board -> assert board["session"]["revision"] == 2 end)
    render_hook(manager, "set_contributions_open", payload(manager, %{revision: 2, open: true}))
    assert_reply(manager, %{status: "ok"})
    assert_board_eventually(author, fn board -> assert board["session"]["contributions_open"] end)
    render_hook(author, "create_idea", payload(author, idea_attrs(%{body: "<p>After reopening</p>"})))
    assert_reply(author, %{status: "ok"})
  end

  defp board_path(ctx),
    do: ~p"/workspaces/#{ctx.project.workspace.slug}/projects/#{ctx.project.slug}/brainstorming/#{ctx.session.id}"

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
