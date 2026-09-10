defmodule Storyarn.Ideation.CanvasShapesTest do
  use Storyarn.DataCase, async: true

  import Storyarn.IdeationFixtures

  alias Storyarn.Ideation
  alias Storyarn.Ideation.Ideas.Idea
  alias Storyarn.Ideation.Recovery.Capsule
  alias Storyarn.Ideation.Sessions.Session
  alias Storyarn.Platform.Vault
  alias Storyarn.Projects.Versioning.Builders.ProjectSnapshotBuilder

  setup do
    ideation_fixture()
  end

  test "canvas creation preserves each supported shape and its idempotent intent", ctx do
    for shape <- ~w(plain rectangle ellipse diamond) do
      attrs = idea_attrs(%{canvas: placement(%{"shape" => shape})})
      assert {:ok, note} = Ideation.create_canvas_idea(ctx.author, ctx.project.id, ctx.session.id, attrs)
      assert note.canvas["shape"] == shape
      assert {:ok, replay} = Ideation.create_canvas_idea(ctx.author, ctx.project.id, ctx.session.id, attrs)
      assert replay == note

      changed = put_in(attrs, [:canvas, "shape"], if(shape == "ellipse", do: "diamond", else: "ellipse"))

      assert {:error, :idempotency_conflict} =
               Ideation.create_canvas_idea(ctx.author, ctx.project.id, ctx.session.id, changed)
    end

    assert Repo.aggregate(Idea, :count) == 4
  end

  test "reshaping uses the existing canvas version and supports undo and redo without changing text or links", ctx do
    note = create_note(ctx)
    target = create_note(ctx)
    assert {:ok, _} = Ideation.connect_ideas(ctx.author, ctx.project.id, ctx.session.id, note.id, target.id, true)
    attrs = placement(%{"shape" => "ellipse"})
    assert {:ok, changed} = reshape(ctx, note, 0, attrs)
    assert changed["shape"] == "ellipse"
    assert changed["links"] == [target.id]
    assert changed["links_version"] == 1
    assert changed["version"] == 1
    assert {:ok, ^changed} = reshape(ctx, note, 0, attrs)
    assert {:error, :idempotency_conflict} = reshape(ctx, note, 0, Map.put(attrs, "shape", "diamond"))
    assert {:error, :stale_canvas} = reshape(ctx, note, 0, placement(%{"shape" => "diamond"}))
    assert {:ok, %{"shape" => "rectangle", "version" => 2}} = reshape(ctx, note, 1, placement(%{"shape" => "rectangle"}))
    assert {:ok, %{"shape" => "ellipse", "version" => 3}} = reshape(ctx, note, 2, placement(%{"shape" => "ellipse"}))

    assert {:ok, saved} = Ideation.get_idea(ctx.author, ctx.project.id, ctx.session.id, note.id)
    assert saved.revision == note.revision
    assert saved.body == note.body
    assert saved.canvas["links"] == [target.id]
  end

  test "old clients can move and recolor shaped notes without resetting shape, including retries", ctx do
    note = create_note(ctx, %{"shape" => "diamond"})
    attrs = placement(%{"x" => 330, "color" => "violet"})

    for _ <- 1..2 do
      assert {:ok, %{"x" => 330, "color" => "violet", "shape" => "diamond", "version" => 1}} =
               reshape(ctx, note, 0, attrs)
    end

    legacy = create_note(ctx)
    refute Map.has_key?(legacy.canvas, "shape")
    assert {:ok, moved} = reshape(ctx, legacy, 0, placement(%{"x" => 400}))
    refute Map.has_key?(moved, "shape")
  end

  test "invalid explicit shapes cannot create or alter a note", ctx do
    note = create_note(ctx, %{"shape" => "ellipse"})
    original = Repo.get!(Idea, note.id).canvas

    for invalid <- [nil, false, "", "circle", "ELLIPSE", :diamond, [], %{}] do
      attrs = placement(%{"shape" => invalid})
      assert {:error, :invalid_canvas} = reshape(ctx, note, 0, attrs)

      assert {:error, :invalid_canvas} =
               Ideation.create_canvas_idea(ctx.author, ctx.project.id, ctx.session.id, idea_attrs(%{canvas: attrs}))
    end

    assert Repo.aggregate(Idea, :count) == 1
    assert Repo.get!(Idea, note.id).canvas == original
  end

  test "group movement preserves and projects each member shape, including legacy notes", ctx do
    notes = [create_note(ctx, %{"shape" => "ellipse"}), create_note(ctx, %{"shape" => "diamond"}), create_note(ctx)]

    assert {:ok, group} =
             Ideation.create_group(ctx.author, ctx.project.id, ctx.session.id, %{
               request_key: Ecto.UUID.generate(),
               title: "Shared theme",
               synthesis: "Related ideas",
               idea_ids: Enum.map(notes, & &1.id),
               canvas: %{x: 0, y: 0, width: 650, height: 450}
             })

    assert Enum.map(group.members, & &1.canvas["shape"]) == ["ellipse", "diamond", nil]

    attrs = %{
      request_key: Ecto.UUID.generate(),
      x: 200,
      y: 300,
      member_versions: Enum.map(notes, &%{id: &1.id, version: 0})
    }

    assert {:ok, moved} = Ideation.move_group(ctx.peer, ctx.project.id, ctx.session.id, group.id, group.version, attrs)
    assert {:ok, ^moved} = Ideation.move_group(ctx.peer, ctx.project.id, ctx.session.id, group.id, group.version, attrs)
    assert Enum.map(moved.members, & &1.canvas["shape"]) == ["ellipse", "diamond", nil]

    for note <- notes do
      assert {:ok, saved} = Ideation.get_idea(ctx.author, ctx.project.id, ctx.session.id, note.id)
      assert saved.canvas["shape"] == note.canvas["shape"]
      assert saved.canvas["x"] == note.canvas["x"] + 200
      assert saved.canvas["y"] == note.canvas["y"] + 300
      assert saved.canvas["version"] == 1
    end
  end

  test "project snapshot restores all shapes and legacy canvases after physical deletion", ctx do
    notes = Enum.map(~w(plain rectangle ellipse diamond), &create_note(ctx, %{"shape" => &1})) ++ [create_note(ctx)]
    capsule = capture(ctx)
    Repo.delete_all(from s in Session, where: s.project_id == ^ctx.project.id)
    assert {:ok, maps} = restore_result(ctx, capsule)
    session_id = maps["sessions"][ctx.session.id]
    assert session_id != ctx.session.id

    for note <- notes do
      assert {:ok, saved} = Ideation.get_idea(ctx.author, ctx.project.id, session_id, maps["ideas"][note.id])
      assert saved.canvas == note.canvas
    end

    assert {:ok, :ok} = Repo.transact(fn -> {:ok, Ideation.verify_recovery(ctx.project.id, capsule, maps)} end)
  end

  test "recovery rejects malformed shapes before replacing live data", ctx do
    note = create_note(ctx, %{"shape" => "ellipse"})
    original = Repo.get!(Idea, note.id).canvas
    assert {:ok, inventory} = ctx |> capture() |> Capsule.open()

    for invalid <- [nil, false, "circle", 4, [], %{}] do
      malformed =
        update_in(inventory, ["rows", "ideas"], &Enum.map(&1, fn row -> put_in(row, ["canvas", "shape"], invalid) end))

      assert {:error, :ideation_recovery_capture_failed} = Capsule.seal(malformed)
      assert {:error, :invalid_ideation_recovery} = restore_result(ctx, authenticate(malformed))
    end

    assert Repo.get!(Idea, note.id).canvas == original
    assert is_nil(Repo.get!(Session, ctx.session.id).deleted_at)
  end

  defp placement(attrs),
    do:
      Map.merge(%{"x" => 40, "y" => 60, "width" => 280, "color" => "mint", "request_key" => Ecto.UUID.generate()}, attrs)

  defp create_note(ctx, canvas \\ %{}) do
    {:ok, note} =
      Ideation.create_canvas_idea(ctx.author, ctx.project.id, ctx.session.id, idea_attrs(%{canvas: placement(canvas)}))

    note
  end

  defp reshape(ctx, note, version, attrs),
    do: Ideation.update_idea_canvas(ctx.author, ctx.project.id, ctx.session.id, note.id, version, attrs)

  defp capture(ctx) do
    {:ok, snapshot} =
      Repo.transact(fn ->
        {:ok, ProjectSnapshotBuilder.build_canonical_snapshot_in_transaction(ctx.project.id, localization_scope: :active)}
      end)

    snapshot["ideation"]
  end

  defp restore_result(ctx, capsule) do
    Repo.transact(fn ->
      Repo.one!(from p in "projects", where: p.id == ^ctx.project.id, select: p.id, lock: "FOR UPDATE")
      Ideation.restore_recovery(ctx.project.id, capsule)
    end)
  end

  defp authenticate(data) do
    {:ok, bytes} = data |> Jason.encode!() |> Vault.encrypt()
    %{"version" => 1, "ciphertext" => Base.encode64(bytes)}
  end
end
