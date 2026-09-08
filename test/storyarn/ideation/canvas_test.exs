defmodule Storyarn.Ideation.CanvasTest do
  use Storyarn.DataCase, async: true

  import Storyarn.IdeationFixtures

  alias Storyarn.Ideation

  setup do
    ideation_fixture()
  end

  defp placement(attrs \\ %{}),
    do:
      Map.merge(
        %{"x" => -100.5, "y" => 220, "width" => 280, "color" => "mint", "request_key" => Ecto.UUID.generate()},
        attrs
      )

  test "placement is atomic on creation and shared movement preserves text revision", ctx do
    {:ok, idea} =
      Ideation.create_idea(
        ctx.author,
        ctx.project.id,
        ctx.session.id,
        idea_attrs(%{canvas: placement(), visibility: :shared})
      )

    assert idea.canvas["x"] == -100.5
    attrs = placement(%{"x" => 300})

    assert {:ok, %{"version" => 1}} =
             Ideation.update_idea_canvas(ctx.peer, ctx.project.id, ctx.session.id, idea.id, 0, attrs)

    assert {:ok, %{"version" => 1}} =
             Ideation.update_idea_canvas(ctx.peer, ctx.project.id, ctx.session.id, idea.id, 0, attrs)

    assert {:error, :idempotency_conflict} =
             Ideation.update_idea_canvas(ctx.peer, ctx.project.id, ctx.session.id, idea.id, 0, Map.put(attrs, "x", 500))

    assert {:error, :stale_canvas} =
             Ideation.update_idea_canvas(ctx.author, ctx.project.id, ctx.session.id, idea.id, 0, placement())

    assert {:ok, updated} = Ideation.get_idea(ctx.author, ctx.project.id, ctx.session.id, idea.id)
    assert updated.revision == idea.revision
    assert updated.body == idea.body
    assert updated.canvas["x"] == 300
  end

  test "viewers, foreign sessions and private ideas are protected", ctx do
    idea = idea_fixture(ctx)

    assert {:error, :not_found} =
             Ideation.update_idea_canvas(ctx.peer, ctx.project.id, ctx.session.id, idea.id, 0, placement())

    assert {:error, :unauthorized} =
             Ideation.update_idea_canvas(ctx.viewer, ctx.project.id, ctx.session.id, idea.id, 0, placement())

    {:ok, other} = Ideation.create_session(ctx.author, ctx.project.id, %{title: "Other"})

    assert {:error, :not_found} =
             Ideation.update_idea_canvas(ctx.author, ctx.project.id, other.id, idea.id, 0, placement())

    for invalid <- [nil, %{}, placement(%{"width" => -1}), placement(%{"x" => "3"}), placement(%{"color" => "url(evil)"})] do
      assert {:error, _} = Ideation.update_idea_canvas(ctx.author, ctx.project.id, ctx.session.id, idea.id, 0, invalid)
    end

    {:ok, _} = Ideation.archive_session(ctx.facilitator, ctx.project.id, ctx.session.id, ctx.session.revision)

    assert {:error, :session_archived} =
             Ideation.update_idea_canvas(ctx.author, ctx.project.id, ctx.session.id, idea.id, 0, placement())
  end

  test "connecting and disconnecting preserve the acknowledged placement request", ctx do
    source = idea_fixture(ctx)
    target = idea_fixture(ctx)
    attrs = placement()

    assert {:ok, %{"version" => 1}} =
             Ideation.update_idea_canvas(ctx.author, ctx.project.id, ctx.session.id, source.id, 0, attrs)

    for connected? <- [true, false] do
      assert {:ok, _} =
               Ideation.connect_ideas(ctx.author, ctx.project.id, ctx.session.id, source.id, target.id, connected?)

      assert {:ok, placement} =
               Ideation.update_idea_canvas(ctx.author, ctx.project.id, ctx.session.id, source.id, 0, attrs)

      assert placement["version"] == 1
      assert placement["x"] == attrs["x"]
      assert placement["links"] == if(connected?, do: [target.id], else: [])
    end
  end

  test "notes without canvas appearance can move using the displayed defaults", ctx do
    idea = idea_fixture(ctx)
    attrs = %{"x" => 30, "y" => 50, "request_key" => Ecto.UUID.generate()}

    for _ <- 1..2 do
      assert {:ok, %{"x" => 30, "y" => 50, "width" => 280, "color" => "yellow", "version" => 1}} =
               Ideation.update_idea_canvas(ctx.author, ctx.project.id, ctx.session.id, idea.id, 0, attrs)
    end

    assert {:ok, note} =
             Ideation.create_canvas_idea(
               ctx.author,
               ctx.project.id,
               ctx.session.id,
               idea_attrs(%{canvas: %{"x" => 0, "y" => 0, "width" => 320}})
             )

    assert note.canvas["width"] == 320
    assert note.canvas["color"] == "yellow"
  end

  test "connections never expose private endpoints, including after source publication", ctx do
    source = idea_fixture(ctx)
    target = idea_fixture(ctx)
    assert {:ok, _} = Ideation.connect_ideas(ctx.author, ctx.project.id, ctx.session.id, source.id, target.id, true)
    source = publish_idea(ctx, source)
    assert source.canvas["links"] == [target.id]
    {:ok, peer_view} = Ideation.get_idea(ctx.peer, ctx.project.id, ctx.session.id, source.id)
    assert peer_view.canvas["links"] == []

    assert {:error, :not_found} =
             Ideation.connect_ideas(ctx.peer, ctx.project.id, ctx.session.id, source.id, target.id, true)

    # A collaborator moving the shared source must preserve its private edges.
    assert {:ok, _} = Ideation.update_idea_canvas(ctx.peer, ctx.project.id, ctx.session.id, source.id, 0, placement())
    {:ok, owned} = Ideation.get_idea(ctx.author, ctx.project.id, ctx.session.id, source.id)
    assert owned.canvas["links"] == [target.id]
    publish_idea(ctx, target)
    {:ok, peer_view} = Ideation.get_idea(ctx.peer, ctx.project.id, ctx.session.id, source.id)
    assert peer_view.canvas["links"] == [target.id]
    assert {:ok, _} = Ideation.connect_ideas(ctx.peer, ctx.project.id, ctx.session.id, source.id, target.id, false)
    assert {:ok, _} = Ideation.connect_ideas(ctx.peer, ctx.project.id, ctx.session.id, source.id, target.id, false)
    {:ok, peer_view} = Ideation.get_idea(ctx.peer, ctx.project.id, ctx.session.id, source.id)
    assert peer_view.canvas["links"] == []
  end
end
