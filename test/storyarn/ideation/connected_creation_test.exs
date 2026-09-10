defmodule Storyarn.Ideation.ConnectedCreationTest do
  use Storyarn.DataCase, async: true

  import Storyarn.IdeationFixtures

  alias Storyarn.Ideation
  alias Storyarn.Ideation.Ideas.Edit
  alias Storyarn.Ideation.Ideas.Idea
  alias Storyarn.Ideation.Ideas.Publication
  alias Storyarn.Ideation.Ideas.Revision

  setup do: ideation_fixture()

  test "first persistence connects every source and returns original versions on retry", ctx do
    [first, second] = for _ <- 1..2, do: idea_fixture(ctx, %{visibility: :shared})
    assert {:ok, _} = Ideation.connect_ideas(ctx.author, ctx.project.id, ctx.session.id, first.id, second.id, true)
    attrs = attributes([first, second])

    assert {:ok, note} = create_connected(ctx, attrs)
    assert note.visibility == :shared
    assert note.author_id == ctx.author.user.id

    assert note.connected_from == [
             %{id: first.id, before_version: 1, version: 2},
             %{id: second.id, before_version: 0, version: 1}
           ]

    assert Repo.get!(Idea, first.id).canvas["links"] == [second.id, note.id]
    assert Repo.get!(Idea, second.id).canvas["links"] == [note.id]
    assert Repo.aggregate(from(r in Revision, where: r.idea_id == ^note.id), :count) == 1
    assert Repo.aggregate(from(e in Edit, where: e.idea_id == ^note.id), :count) == 1
    assert Repo.aggregate(from(p in Publication, where: p.idea_id == ^note.id), :count) == 1
    refute Map.has_key?(note.canvas, "creation_links_receipt")
    assert {:ok, ^note} = create_connected(ctx, attrs)

    assert {:ok, normal} = Ideation.get_idea(ctx.author, ctx.project.id, ctx.session.id, note.id)
    refute Map.has_key?(normal, :connected_from)
    refute Map.has_key?(normal.canvas, "creation_links_receipt")
  end

  test "lost creation acknowledgement cannot recreate an edge another editor removed", ctx do
    source = idea_fixture(ctx, %{visibility: :shared})
    attrs = attributes([source])
    assert {:ok, note} = create_connected(ctx, attrs)
    assert {:ok, _} = Ideation.connect_ideas(ctx.peer, ctx.project.id, ctx.session.id, source.id, note.id, false)
    assert {:ok, replayed} = create_connected(ctx, attrs)
    assert replayed.id == note.id
    assert replayed.connected_from == note.connected_from
    assert Repo.get!(Idea, source.id).canvas["links"] == []
    assert Repo.get!(Idea, source.id).canvas["links_version"] == 2
    assert Repo.aggregate(from(i in Idea, where: i.creation_key == ^attrs.request_key), :count) == 1
  end

  test "creation receipt belongs to the exact original source selection", ctx do
    [first, second] = for _ <- 1..2, do: idea_fixture(ctx)
    attrs = attributes([first])
    assert {:ok, note} = create_connected(ctx, attrs)
    changed = put_in(attrs, [:connection, :source_ids], [second.id])
    assert {:error, :idempotency_conflict} = create_connected(ctx, changed)
    assert Repo.get!(Idea, first.id).canvas["links"] == [note.id]
    assert Repo.get!(Idea, second.id).canvas["links"] == nil
  end

  test "one hidden or deleted source leaves neither note, publication nor partial connections", ctx do
    public = idea_fixture(ctx, %{visibility: :shared})
    private = idea_fixture(ctx)
    deleted = idea_fixture(ctx, %{visibility: :shared})
    assert {:ok, _} = Ideation.delete_idea(ctx.author, ctx.project.id, ctx.session.id, deleted.id, 1)

    for source <- [private, deleted] do
      attrs = attributes([public, source])
      assert {:error, :not_found} = create_connected(%{ctx | author: ctx.peer}, attrs)
      assert Repo.aggregate(from(i in Idea, where: i.creation_key == ^attrs.request_key), :count) == 0
      assert Repo.get!(Idea, public.id).canvas["links"] == nil
    end
  end

  test "source capacity failure does not create an orphan or change other sources", ctx do
    [source, full] = for _ <- 1..2, do: idea_fixture(ctx)
    existing = for _ <- 1..100, do: idea_fixture(ctx).id
    Idea |> Repo.get!(full.id) |> Ecto.Changeset.change(canvas: %{"links" => existing}) |> Repo.update!()
    attrs = attributes([source, full])
    assert {:error, :invalid_connections} = create_connected(ctx, attrs)
    assert Repo.aggregate(from(i in Idea, where: i.creation_key == ^attrs.request_key), :count) == 0
    assert Repo.get!(Idea, source.id).canvas["links"] == nil
    assert Repo.get!(Idea, full.id).canvas["links"] == existing
  end

  test "connected creation uses the current privacy and round rules", ctx do
    {:ok, _} = Ideation.set_private_mode(ctx.facilitator, ctx.project.id, ctx.session.id, 1, true)
    {:ok, private_session} = Ideation.get_session(ctx.facilitator, ctx.project.id, ctx.session.id)

    {:ok, _} =
      Ideation.create_round(ctx.facilitator, ctx.project.id, ctx.session.id, private_session.revision, %{prompt: "Why?"})

    {:ok, [round]} = Ideation.list_rounds(ctx.facilitator, ctx.project.id, ctx.session.id)
    {:ok, current_session} = Ideation.get_session(ctx.facilitator, ctx.project.id, ctx.session.id)
    {:ok, _} = Ideation.start_round(ctx.facilitator, ctx.project.id, ctx.session.id, round.id, current_session.revision)
    source = idea_fixture(ctx, %{configuration_version: private_session.configuration_version})
    assert {:ok, note} = create_connected(ctx, attributes([source]))
    assert note.visibility == :private
    assert note.round_id == round.id
    assert {:error, :not_found} = Ideation.get_idea(ctx.peer, ctx.project.id, ctx.session.id, note.id)
    assert Repo.get!(Idea, source.id).canvas["links"] == [note.id]
  end

  test "undo hides connected creation and restore cannot recreate a removed edge", ctx do
    source = idea_fixture(ctx, %{visibility: :shared})
    {:ok, note} = create_connected(ctx, attributes([source]))
    {:ok, deleted} = Ideation.delete_idea(ctx.author, ctx.project.id, ctx.session.id, note.id, note.revision)
    {:ok, view} = Ideation.get_idea(ctx.author, ctx.project.id, ctx.session.id, source.id)
    assert view.canvas["links"] == []

    {:ok, restored} =
      Ideation.restore_idea(ctx.author, ctx.project.id, ctx.session.id, note.id, deleted.revision, deleted.deleted_at)

    {:ok, view} = Ideation.get_idea(ctx.author, ctx.project.id, ctx.session.id, source.id)
    assert view.canvas["links"] == [restored.id]
    {:ok, _} = Ideation.connect_ideas(ctx.peer, ctx.project.id, ctx.session.id, source.id, restored.id, false)
    {:ok, deleted} = Ideation.delete_idea(ctx.author, ctx.project.id, ctx.session.id, note.id, restored.revision)

    {:ok, _} =
      Ideation.restore_idea(ctx.author, ctx.project.id, ctx.session.id, note.id, deleted.revision, deleted.deleted_at)

    {:ok, view} = Ideation.get_idea(ctx.author, ctx.project.id, ctx.session.id, source.id)
    assert view.canvas["links"] == []
  end

  test "malformed connection input never persists a contribution", ctx do
    source = idea_fixture(ctx)

    for connection <- [
          false,
          %{},
          %{source_ids: []},
          %{source_ids: [source.id, source.id]},
          %{source_ids: ["1"]},
          %{source_ids: [-1]},
          %{source_ids: List.duplicate(source.id, 101)}
        ] do
      attrs = Map.put(attributes([source]), :connection, connection)
      assert {:error, :invalid_connections} = create_connected(ctx, attrs)
      assert Repo.aggregate(from(i in Idea, where: i.creation_key == ^attrs.request_key), :count) == 0
    end
  end

  defp attributes(sources),
    do: idea_attrs(%{canvas: %{"x" => 200, "y" => 400}, connection: %{source_ids: Enum.map(sources, & &1.id)}})

  defp create_connected(ctx, attrs), do: Ideation.create_canvas_idea(ctx.author, ctx.project.id, ctx.session.id, attrs)
end
