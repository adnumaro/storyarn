defmodule Storyarn.Ideation.CanvasConnectionsTest do
  use Storyarn.DataCase, async: true

  import Storyarn.IdeationFixtures

  alias Storyarn.Ideation
  alias Storyarn.Ideation.Ideas.Idea
  alias Storyarn.Ideation.Ideas.Revision

  setup do: ideation_fixture()

  test "a batch changes only requested edges and retries its exact acknowledged delta", ctx do
    [first, second, third] = for _ <- 1..3, do: idea_fixture(ctx)
    assert {:ok, _} = connect(ctx, first, second, true)
    request = command([{first, second, true}, {first, third, true}, {second, third, true}], [{first, 1}, {second, 0}])
    assert :ok = Ideation.subscribe_ideas(ctx.author, ctx.project.id, ctx.session.id)

    assert {:ok, result} = apply_batch(ctx, request)
    assert result.changes == [edge(first, third, true), edge(second, third, true)]
    assert result.versions == [%{id: first.id, version: 2}, %{id: second.id, version: 1}]
    assert links(first) == [second.id, third.id]
    assert links(second) == [third.id]
    assert_receive {:ideation_changed, _}
    refute_receive {:ideation_changed, _}

    assert {:ok, ^result} = apply_batch(ctx, request)
    refute_receive {:ideation_changed, _}
    assert Repo.aggregate(from(r in Revision, where: r.idea_id in ^[first.id, second.id]), :count) == 2
  end

  test "no-op acknowledgements preserve versions and never become undoable changes", ctx do
    [source, target] = for _ <- 1..2, do: idea_fixture(ctx)
    request = command([{source, target, false}], [{source, 0}])
    assert :ok = Ideation.subscribe_ideas(ctx.author, ctx.project.id, ctx.session.id)
    assert {:ok, %{changes: [], versions: [%{version: 0}]} = result} = apply_batch(ctx, request)
    assert {:ok, ^result} = apply_batch(ctx, request)
    assert links(source) == []
    refute_receive {:ideation_changed, _}
  end

  test "undo and redo use independent acknowledged versions and reject ABA", ctx do
    [source, target, other] = for _ <- 1..3, do: idea_fixture(ctx, %{visibility: :shared})
    request = command([{source, target, true}], [{source, 0}])
    assert {:ok, %{versions: [%{version: 1}]}} = apply_batch(ctx, request)

    undo = command([{source, target, false}], [{source, 1}])
    assert {:ok, %{versions: [%{version: 2}]}} = apply_batch(ctx, undo)
    assert {:ok, %{versions: [%{version: 3}]}} = apply_batch(ctx, command([{source, target, true}], [{source, 2}]))

    # The compatibility writer participates in the same fencing protocol.
    assert {:ok, _} = connect(%{ctx | author: ctx.peer}, source, other, true)
    assert {:ok, _} = connect(%{ctx | author: ctx.peer}, source, other, false)
    assert links(source) == [target.id]
    assert {:error, :stale_connections} = apply_batch(ctx, command([{source, target, false}], [{source, 3}]))
    assert {:error, :stale_connections} = apply_batch(ctx, request)
    assert links(source) == [target.id]
  end

  test "a reused retained key cannot change targets, direction or acting user", ctx do
    [source, target, other] = for _ <- 1..3, do: idea_fixture(ctx, %{visibility: :shared})
    request = command([{source, target, true}], [{source, 0}])
    assert {:ok, _} = apply_batch(ctx, request)

    for changes <- [[edge(source, other, true)], [edge(source, target, false)]] do
      assert {:error, :idempotency_conflict} = apply_batch(ctx, %{request | changes: changes})
    end

    assert {:error, :idempotency_conflict} = apply_batch(%{ctx | author: ctx.peer}, request)
    assert links(source) == [target.id]
  end

  test "placement and text retain their receipts across connection writes and vice versa", ctx do
    [source, target] = for _ <- 1..2, do: idea_fixture(ctx)
    placement = %{"x" => 40, "y" => 60, "request_key" => Ecto.UUID.generate()}

    assert {:ok, %{"version" => 1}} =
             Ideation.update_idea_canvas(ctx.author, ctx.project.id, ctx.session.id, source.id, 0, placement)

    request = command([{source, target, true}], [{source, 0}])
    assert {:ok, result} = apply_batch(ctx, request)

    assert {:ok, moved} =
             Ideation.update_idea_canvas(ctx.author, ctx.project.id, ctx.session.id, source.id, 0, placement)

    assert moved["links_version"] == 1
    assert moved["links"] == [target.id]
    refute Map.has_key?(moved, "links_receipt")
    refute Map.has_key?(moved, "request_key")

    assert {:ok, _} =
             Ideation.update_idea(
               ctx.author,
               ctx.project.id,
               ctx.session.id,
               source.id,
               1,
               edit_attrs(%{body: "Updated"})
             )

    assert {:ok, ^result} = apply_batch(ctx, request)
    assert {:ok, current} = Ideation.get_idea(ctx.author, ctx.project.id, ctx.session.id, source.id)
    assert current.body == "Updated"
    refute Map.has_key?(current.canvas, "links_receipt")
    assert {:ok, _} = apply_batch(ctx, command([{source, target, false}], [{source, 1}]))
  end

  test "one stale source aborts every change and a partially superseded retry cannot reapply", ctx do
    [first, second, target] = for _ <- 1..3, do: idea_fixture(ctx)
    request = command([{first, target, true}, {second, target, true}], [{first, 0}, {second, 0}])
    assert {:ok, _} = apply_batch(ctx, request)
    assert {:ok, _} = connect(ctx, second, target, false)
    assert {:error, :stale_connections} = apply_batch(ctx, request)
    assert links(first) == [target.id]
    assert links(second) == []

    stale = command([{first, target, false}, {second, target, true}], [{first, 1}, {second, 1}])
    assert {:error, :stale_connections} = apply_batch(ctx, stale)
    assert links(first) == [target.id]
    assert links(second) == []
  end

  test "a batch cannot mutate visible sources when any endpoint is hidden, deleted or foreign", ctx do
    shared = idea_fixture(ctx, %{visibility: :shared})
    target = idea_fixture(ctx, %{visibility: :shared})
    private = idea_fixture(ctx)
    deleted = idea_fixture(ctx, %{visibility: :shared})
    assert {:ok, _} = Ideation.delete_idea(ctx.author, ctx.project.id, ctx.session.id, deleted.id, 1)
    {:ok, other_session} = Ideation.create_session(ctx.author, ctx.project.id, %{title: "Other"})
    foreign = idea_fixture(%{ctx | session: other_session}, %{visibility: :shared})

    for inaccessible <- [private, deleted, foreign] do
      request = command([{shared, target, true}, {target, inaccessible, true}], [{shared, 0}, {target, 0}])
      assert {:error, :not_found} = apply_batch(%{ctx | author: ctx.peer}, request)
      assert links(shared) == []
    end

    request = command([{shared, target, true}], [{shared, 0}])
    assert {:error, :unauthorized} = apply_batch(%{ctx | author: ctx.viewer}, request)
    {:ok, _} = Ideation.set_private_mode(ctx.facilitator, ctx.project.id, ctx.session.id, 1, true)
    assert {:error, :not_found} = apply_batch(%{ctx | author: ctx.peer}, request)
    {:ok, session} = Ideation.get_session(ctx.facilitator, ctx.project.id, ctx.session.id)
    {:ok, _} = Ideation.archive_session(ctx.facilitator, ctx.project.id, ctx.session.id, session.revision)
    assert {:error, :session_archived} = apply_batch(ctx, request)
  end

  test "hidden outgoing edges are preserved and absent from public projections", ctx do
    source = idea_fixture(ctx, %{visibility: :shared})
    private = idea_fixture(ctx)
    public = idea_fixture(ctx, %{visibility: :shared})
    assert {:ok, _} = connect(ctx, source, private, true)
    request = command([{source, public, true}], [{source, 1}])
    assert {:ok, %{changes: changes}} = apply_batch(%{ctx | author: ctx.peer}, request)
    assert changes == [edge(source, public, true)]
    assert links(source) == [private.id, public.id]
    assert {:ok, peer_view} = Ideation.get_idea(ctx.peer, ctx.project.id, ctx.session.id, source.id)
    assert peer_view.canvas["links"] == [public.id]
    refute Map.has_key?(peer_view.canvas, "links_receipt")
  end

  test "connection limit failure rolls back the entire batch", ctx do
    [first, full, target] = for _ <- 1..3, do: idea_fixture(ctx)
    existing = for _ <- 1..100, do: idea_fixture(ctx).id
    Idea |> Repo.get!(full.id) |> Ecto.Changeset.change(canvas: %{"links" => existing}) |> Repo.update!()
    request = command([{first, target, true}, {full, target, true}], [{first, 0}, {full, 0}])
    assert {:error, :invalid_connections} = apply_batch(ctx, request)
    assert links(first) == []
    assert links(full) == existing
  end

  test "malformed operations are typed failures before persistence", ctx do
    [source, target] = for _ <- 1..2, do: idea_fixture(ctx)
    valid = command([{source, target, true}], [{source, 0}])

    for invalid <- [
          nil,
          %{},
          %{valid | changes: []},
          %{valid | changes: [edge(source, source, true)]},
          %{valid | changes: [edge(source, target, true), edge(source, target, false)]},
          %{valid | changes: [%{source_id: "1", target_id: target.id, connected: true}]},
          %{valid | changes: [%{source_id: source.id, target_id: target.id, connected: "true"}]},
          %{valid | versions: []},
          %{valid | versions: [%{id: target.id, version: 0}]},
          %{valid | versions: [%{id: source.id, version: -1}]},
          %{valid | versions: valid.versions ++ valid.versions},
          %{valid | changes: List.duplicate(hd(valid.changes), 101)}
        ] do
      assert {:error, _} = apply_batch(ctx, invalid)
      assert links(source) == []
    end

    assert {:ok, _} = apply_batch(ctx, valid |> Jason.encode!() |> Jason.decode!())
  end

  defp apply_batch(ctx, attrs), do: Ideation.update_idea_connections(ctx.author, ctx.project.id, ctx.session.id, attrs)

  defp connect(ctx, source, target, connected),
    do: Ideation.connect_ideas(ctx.author, ctx.project.id, ctx.session.id, source.id, target.id, connected)

  defp links(idea), do: Repo.get!(Idea, idea.id).canvas["links"] || []

  defp edge(source, target, connected), do: %{source_id: source.id, target_id: target.id, connected: connected}

  defp command(edges, versions) do
    %{
      request_key: Ecto.UUID.generate(),
      changes: Enum.map(edges, fn {source, target, connected} -> edge(source, target, connected) end),
      versions: Enum.map(versions, fn {source, version} -> %{id: source.id, version: version} end)
    }
  end
end
