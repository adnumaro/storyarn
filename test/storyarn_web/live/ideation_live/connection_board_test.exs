defmodule StoryarnWeb.IdeationLive.ConnectionBoardTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.IdeationFixtures

  alias Storyarn.Ideation
  alias Storyarn.Repo

  setup do
    ctx = ideation_fixture()
    %{ctx | project: Repo.preload(ctx.project, :workspace)}
  end

  test "JSON connection commands return undo versions and refresh every participant's canvas", ctx do
    [first, second, target] = for _ <- 1..3, do: idea_fixture(ctx, %{visibility: :shared})
    {:ok, author, _} = live(log_in_user(ctx.conn, ctx.author.user), board_path(ctx))
    {:ok, peer, _} = live(log_in_user(build_conn(), ctx.peer.user), board_path(ctx))
    attrs = command([{first, target, true}, {second, target, true}], [{first, 0}, {second, 0}])

    render_hook(author, "update_idea_connections", payload(author, attrs))
    assert_reply(author, %{status: "ok", value: result})
    assert result.changes == [edge(first, target, true), edge(second, target, true)]
    assert result.versions == [%{id: first.id, version: 1}, %{id: second.id, version: 1}]

    for view <- [author, peer] do
      assert_board_eventually(view, fn board ->
        for source <- [first, second] do
          assert note(board, source.id)["canvas"]["links"] == [target.id]
          assert note(board, source.id)["canvas"]["links_version"] == 1
        end

        assert_public_canvas(board)
      end)
    end

    render_hook(author, "update_idea_connections", payload(author, attrs))
    assert_reply(author, %{status: "ok", value: ^result})

    undo = %{
      request_key: Ecto.UUID.generate(),
      changes: Enum.map(result.changes, &%{&1 | connected: false}),
      versions: result.versions
    }

    render_hook(author, "update_idea_connections", payload(author, undo))
    assert_reply(author, %{status: "ok", value: %{versions: versions}})
    assert versions == [%{id: first.id, version: 2}, %{id: second.id, version: 2}]

    for view <- [author, peer] do
      assert_board_eventually(view, fn board ->
        for source <- [first, second] do
          assert note(board, source.id)["canvas"]["links"] == []
          assert note(board, source.id)["canvas"]["links_version"] == 2
        end
      end)
    end
  end

  test "stale connection undo preserves a collaborator's links and leaves the board usable", ctx do
    [source, first, second] = for _ <- 1..3, do: idea_fixture(ctx, %{visibility: :shared})
    {:ok, author, _} = live(log_in_user(ctx.conn, ctx.author.user), board_path(ctx))
    {:ok, peer, _} = live(log_in_user(build_conn(), ctx.peer.user), board_path(ctx))
    epoch = data(author)["epoch"]

    render_hook(author, "update_idea_connections", payload(author, command([{source, first, true}], [{source, 0}])))
    assert_reply(author, %{status: "ok", value: %{versions: versions}})

    render_hook(peer, "connect_ideas", payload(peer, edge(source, second, true)))
    assert_reply(peer, %{status: "ok"})

    render_hook(
      author,
      "update_idea_connections",
      payload(author, %{request_key: Ecto.UUID.generate(), changes: [edge(source, first, false)], versions: versions})
    )

    assert_reply(author, %{status: "error", code: "stale_connections"})

    assert_board_eventually(author, fn board ->
      assert note(board, source.id)["canvas"]["links"] == [first.id, second.id]
      assert board["epoch"] == epoch
      assert board["can_edit"]
      assert board["error"] == nil
    end)

    refute_push_event(author, "brainstorming_reset", %{reason: "access_changed"})
  end

  test "viewer and stale-board requests cannot use connection writes or connected creation", ctx do
    [source, target] = for _ <- 1..2, do: idea_fixture(ctx, %{visibility: :shared})
    {:ok, viewer, _} = live(log_in_user(ctx.conn, ctx.viewer.user), board_path(ctx))
    attrs = command([{source, target, true}], [{source, 0}])

    render_hook(viewer, "update_idea_connections", payload(viewer, attrs))
    assert_reply(viewer, %{status: "error", code: "unauthorized"})

    render_hook(viewer, "create_idea", payload(viewer, idea_attrs(%{connection: %{source_ids: [source.id]}})))
    assert_reply(viewer, %{status: "error", code: "unauthorized"})

    {:ok, author, _} = live(log_in_user(build_conn(), ctx.author.user), board_path(ctx))
    stale = author |> payload(attrs) |> Map.put("epoch", Ecto.UUID.generate())
    render_hook(author, "update_idea_connections", stale)
    assert_reply(author, %{status: "error", code: "stale_board"})

    assert {:ok, ideas} = Ideation.list_ideas(ctx.author, ctx.project.id, ctx.session.id)
    assert length(ideas) == 2
    assert Enum.find(ideas, &(&1.id == source.id)).canvas["links"] in [nil, []]
    assert length(data(viewer)["ideas"]) == 2
    refute data(viewer)["can_edit"]
  end

  test "a private or foreign endpoint rejects the whole batch without leaking or hiding readable notes", ctx do
    [source, target] = for _ <- 1..2, do: idea_fixture(ctx, %{visibility: :shared})
    private = idea_fixture(ctx, %{body: "A private connection endpoint"})
    {:ok, other_session} = Ideation.create_session(ctx.author, ctx.project.id, %{title: "Another board"})
    foreign = idea_fixture(%{ctx | session: other_session}, %{visibility: :shared})
    {:ok, peer, _} = live(log_in_user(ctx.conn, ctx.peer.user), board_path(ctx))

    for inaccessible <- [private, foreign] do
      attrs = command([{source, target, true}, {target, inaccessible, true}], [{source, 0}, {target, 0}])
      render_hook(peer, "update_idea_connections", payload(peer, attrs))
      assert_reply(peer, %{status: "error", code: "not_found"})

      assert_board_eventually(peer, fn board ->
        assert Enum.sort(Enum.map(board["ideas"], & &1["id"])) == [source.id, target.id]
        assert note(board, source.id)["canvas"]["links"] in [nil, []]
        assert note(board, target.id)["canvas"]["links"] in [nil, []]
        assert board["can_edit"]
        assert board["error"] == nil
      end)
    end
  end

  test "connected creation preserves JSON placement and returns its source versions on replay", ctx do
    first = idea_fixture(ctx, %{visibility: :shared})
    second = idea_fixture(ctx, %{visibility: :shared}, ctx.peer)
    {:ok, author, _} = live(log_in_user(ctx.conn, ctx.author.user), board_path(ctx))
    {:ok, peer, _} = live(log_in_user(build_conn(), ctx.peer.user), board_path(ctx))

    attrs =
      idea_attrs(%{
        body: "<p>Continue this thought</p>",
        connection: %{source_ids: [first.id, second.id]},
        canvas: %{x: 540, y: -120, width: 260, color: "yellow"}
      })

    render_hook(author, "create_idea", payload(author, attrs))
    assert_reply(author, %{status: "ok", value: created})
    assert created.body == "<p>Continue this thought</p>"
    assert created.canvas["x"] == 540
    assert created.canvas["y"] == -120

    assert created.connected_from == [
             %{id: first.id, before_version: 0, version: 1},
             %{id: second.id, before_version: 0, version: 1}
           ]

    render_hook(author, "create_idea", payload(author, attrs))
    assert_reply(author, %{status: "ok", value: ^created})

    for view <- [author, peer] do
      assert_board_eventually(view, fn board ->
        assert length(board["ideas"]) == 3
        assert note(board, created.id)["body"] == created.body

        for source <- [first, second] do
          assert note(board, source.id)["canvas"]["links"] == [created.id]
          assert note(board, source.id)["canvas"]["links_version"] == 1
        end

        assert_public_canvas(board)
      end)
    end
  end

  test "invalid connected creation leaves no note and does not consume the retry key", ctx do
    source = idea_fixture(ctx, %{visibility: :shared})
    private = idea_fixture(ctx)
    {:ok, peer, _} = live(log_in_user(ctx.conn, ctx.peer.user), board_path(ctx))
    attrs = idea_attrs(%{connection: %{source_ids: [source.id, private.id]}})

    render_hook(peer, "create_idea", payload(peer, attrs))
    assert_reply(peer, %{status: "error", code: "not_found"})
    assert {:ok, ideas} = Ideation.list_ideas(ctx.author, ctx.project.id, ctx.session.id)
    assert length(ideas) == 2
    assert Enum.find(ideas, &(&1.id == source.id)).canvas["links"] in [nil, []]

    malformed = %{attrs | connection: %{source_ids: [to_string(source.id)]}}
    render_hook(peer, "create_idea", payload(peer, malformed))
    assert_reply(peer, %{status: "error", code: "invalid_connections"})

    render_hook(peer, "create_idea", payload(peer, %{attrs | connection: %{source_ids: [source.id]}}))
    assert_reply(peer, %{status: "ok", value: %{id: id}})

    assert_board_eventually(peer, fn board ->
      assert length(board["ideas"]) == 2
      assert note(board, source.id)["canvas"]["links"] == [id]
      assert note(board, id)["author_id"] == ctx.peer.user.id
      refute Enum.any?(board["ideas"], &(&1["id"] == private.id))
    end)
  end

  defp command(edges, versions) do
    %{
      request_key: Ecto.UUID.generate(),
      changes: Enum.map(edges, fn {source, target, connected} -> edge(source, target, connected) end),
      versions: Enum.map(versions, fn {source, version} -> %{id: source.id, version: version} end)
    }
  end

  defp edge(source, target, connected), do: %{source_id: source.id, target_id: target.id, connected: connected}

  defp board_path(ctx),
    do: ~p"/workspaces/#{ctx.project.workspace.slug}/projects/#{ctx.project.slug}/brainstorming/#{ctx.session.id}"

  defp data(view), do: LiveVue.Test.get_vue(view, name: "live/ideation/BrainstormingBoard").props["board"]

  defp payload(view, attrs) do
    attrs
    |> Map.merge(%{epoch: data(view)["epoch"], session_id: data(view)["session"]["id"]})
    |> Jason.encode!()
    |> Jason.decode!()
  end

  defp note(board, id), do: Enum.find(board["ideas"], &(&1["id"] == id))

  defp assert_public_canvas(board) do
    for idea <- board["ideas"] do
      refute Map.has_key?(idea["canvas"], "links_receipt")
      refute Map.has_key?(idea["canvas"], "request_key")
      refute Map.has_key?(idea, "connected_from")
    end
  end

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
