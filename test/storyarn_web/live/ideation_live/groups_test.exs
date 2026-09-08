defmodule StoryarnWeb.IdeationLive.GroupsTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.IdeationFixtures

  alias Storyarn.Ideation
  alias Storyarn.Repo

  setup do
    ctx = ideation_fixture()
    first = idea_fixture(ctx, %{visibility: :shared})
    second = idea_fixture(ctx, %{visibility: :shared}, ctx.peer)
    Map.merge(ctx, %{project: Repo.preload(ctx.project, :workspace), idea_ids: [first.id, second.id]})
  end

  test "shared groups synchronize through the existing board and keep their synthesis when separated", ctx do
    {:ok, author, _} = live(log_in_user(ctx.conn, ctx.author.user), path(ctx))
    {:ok, viewer, _} = live(log_in_user(build_conn(), ctx.viewer.user), path(ctx))

    render_hook(author, "create_group", payload(author, creation(ctx)))
    assert_reply(author, %{status: "ok", value: %{id: id, version: version}})
    eventually(viewer, fn board -> assert [%{"id" => ^id, "title" => "What drives the character?"}] = board["groups"] end)

    render_hook(
      author,
      "update_group",
      payload(author, %{
        group_id: id,
        version: version,
        request_key: Ecto.UUID.generate(),
        synthesis: "Both choices come from a fear of abandonment.",
        idea_ids: []
      })
    )

    assert_reply(author, %{status: "ok", value: %{id: ^id, idea_ids: []}})

    eventually(viewer, fn board ->
      assert [%{"id" => ^id, "idea_ids" => [], "synthesis" => "Both choices come from a fear of abandonment."}] =
               board["groups"]

      assert Enum.sort(Enum.map(board["ideas"], & &1["id"])) == Enum.sort(ctx.idea_ids)
    end)
  end

  test "readonly and stale board writes cannot change groups", ctx do
    {:ok, viewer, _} = live(log_in_user(ctx.conn, ctx.viewer.user), path(ctx))
    render_hook(viewer, "create_group", payload(viewer, creation(ctx)))
    assert_reply(viewer, %{status: "error", code: "unauthorized"})
    assert data(viewer)["ideas"] != []

    {:ok, author, _} = live(log_in_user(build_conn(), ctx.author.user), path(ctx))
    render_hook(author, "create_group", Map.put(payload(author, creation(ctx)), :epoch, "old"))
    assert_reply(author, %{status: "error", code: "stale_board"})
    assert {:ok, []} = Ideation.list_groups(ctx.author, ctx.project.id, ctx.session.id)

    for event <- ~w(update_group move_group delete_group restore_group) do
      render_hook(author, event, payload(author, %{group_id: "bad", version: 1}))
      assert_reply(author, %{status: "error", code: "invalid_parameters"})
    end
  end

  test "private mode removes group content from every participant's board props", ctx do
    {:ok, _} = Ideation.create_group(ctx.author, ctx.project.id, ctx.session.id, creation(ctx))
    {:ok, viewer, _} = live(log_in_user(ctx.conn, ctx.viewer.user), path(ctx))
    assert length(data(viewer)["groups"]) == 1

    {:ok, session} = Ideation.get_session(ctx.facilitator, ctx.project.id, ctx.session.id)
    assert {:ok, _} = Ideation.set_private_mode(ctx.facilitator, ctx.project.id, session.id, session.revision, true)

    eventually(viewer, fn board ->
      assert board["session"]["configuration"]["private_mode"]
      assert board["groups"] == []
      refute Jason.encode!(board) =~ "What drives the character?"
    end)
  end

  defp creation(ctx),
    do: %{
      request_key: Ecto.UUID.generate(),
      title: "What drives the character?",
      idea_ids: ctx.idea_ids,
      canvas: %{x: 0, y: 0, width: 700, height: 400}
    }

  defp path(ctx),
    do: ~p"/workspaces/#{ctx.project.workspace.slug}/projects/#{ctx.project.slug}/brainstorming/#{ctx.session.id}"

  defp data(view), do: LiveVue.Test.get_vue(view, name: "live/ideation/BrainstormingBoard").props["board"]
  defp payload(view, attrs), do: Map.merge(attrs, %{epoch: data(view)["epoch"], session_id: data(view)["session"]["id"]})

  defp eventually(view, assertion, attempts \\ 150)
  defp eventually(view, assertion, 1), do: assertion.(data(view))

  defp eventually(view, assertion, attempts) do
    render_async(view)

    try do
      assertion.(data(view))
    rescue
      ExUnit.AssertionError ->
        Process.sleep(10)
        eventually(view, assertion, attempts - 1)
    end
  end
end
