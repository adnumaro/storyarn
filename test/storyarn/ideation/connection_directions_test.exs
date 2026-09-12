defmodule Storyarn.Ideation.ConnectionDirectionsTest do
  use Storyarn.DataCase, async: true

  import Storyarn.IdeationFixtures

  alias Storyarn.Ideation
  alias Storyarn.Ideation.Ideas.Idea
  alias Storyarn.Ideation.Recovery.Capsule
  alias Storyarn.Ideation.Sessions.Session
  alias Storyarn.Platform.Vault
  alias Storyarn.Projects.Versioning.Builders.ProjectSnapshotBuilder

  setup do: ideation_fixture()

  test "associations are the default and direction edits return reversible exact receipts", ctx do
    [source, target] = for _ <- 1..2, do: idea_fixture(ctx)
    assert :ok = Ideation.subscribe_ideas(ctx.author, ctx.project.id, ctx.session.id)

    assert {:ok, %{changes: [created], versions: [%{version: 1}]}} = write(ctx, source, target, 0, true)
    assert created.direction == "none"
    refute created.previous_connected
    assert is_nil(created.previous_direction)
    assert_receive {:ideation_changed, _}

    request = command(source, target, 1, true, "both")
    assert {:ok, %{changes: [changed], versions: [%{version: 2}]} = result} = apply_command(ctx, request)
    assert changed.previous_connected
    assert changed.previous_direction == "none"
    assert changed.direction == "both"
    assert_receive {:ideation_changed, _}
    assert {:ok, ^result} = apply_command(ctx, request)
    refute_receive {:ideation_changed, _}

    assert {:ok, %{versions: [%{version: 3}]}} =
             write(ctx, source, target, 2, changed.previous_connected, changed.previous_direction)

    assert canvas(source)["link_directions"] == %{to_string(target.id) => "none"}
    assert {:ok, %{versions: [%{version: 4}]}} = write(ctx, source, target, 3, changed.connected, changed.direction)
    assert canvas(source)["link_directions"] == %{to_string(target.id) => "both"}
    assert canvas(source)["links"] == [target.id]
    assert Repo.get!(Idea, source.id).revision == source.revision
  end

  test "all explicit directions round-trip while omitted direction preserves current and legacy edges", ctx do
    [source, target] = for _ <- 1..2, do: idea_fixture(ctx)
    assert {:ok, _} = Ideation.connect_ideas(ctx.author, ctx.project.id, ctx.session.id, source.id, target.id, true)
    refute Map.has_key?(canvas(source)["link_directions"], to_string(target.id))
    assert {:ok, %{changes: [], versions: [%{version: 1}]}} = write(ctx, source, target, 1, true)

    for {direction, version} <- Enum.with_index(~w(backward both none forward), 1) do
      assert {:ok, %{changes: [changed], versions: [%{version: next}]}} =
               write(ctx, source, target, version, true, direction)

      assert changed.previous_connected
      assert changed.direction == direction
      assert next == version + 1
      assert canvas(source)["link_directions"] == %{to_string(target.id) => direction}
      assert {:ok, %{changes: [], versions: [%{version: ^next}]}} = write(ctx, source, target, next, true)
      assert {:ok, %{changes: [], versions: [%{version: ^next}]}} = write(ctx, source, target, next, true, direction)
    end
  end

  test "disconnect removes style metadata and its acknowledgement can restore a legacy arrow", ctx do
    [source, target] = for _ <- 1..2, do: idea_fixture(ctx)
    assert {:ok, _} = Ideation.connect_ideas(ctx.author, ctx.project.id, ctx.session.id, source.id, target.id, true)
    assert {:ok, %{changes: [removed]}} = write(ctx, source, target, 1, false)
    assert removed.previous_connected
    assert removed.previous_direction == "forward"
    assert is_nil(removed.direction)
    assert canvas(source)["link_directions"] == %{}
    assert {:ok, _} = write(ctx, source, target, 2, true, removed.previous_direction)
    assert canvas(source)["link_directions"] == %{to_string(target.id) => "forward"}
    assert {:ok, _} = Ideation.connect_ideas(ctx.author, ctx.project.id, ctx.session.id, source.id, target.id, false)
    assert canvas(source)["link_directions"] == %{}
  end

  test "direction changes cannot bypass stale versions or reuse a receipt with different meaning", ctx do
    [source, target, other] = for _ <- 1..3, do: idea_fixture(ctx, %{visibility: :shared})
    request = command(source, target, 0, true, "none")
    assert {:ok, _} = apply_command(ctx, request)
    altered = put_in(request, [:changes, Access.at(0), :direction], "forward")
    assert {:error, :idempotency_conflict} = apply_command(ctx, altered)
    assert {:ok, _} = write(%{ctx | author: ctx.peer}, source, target, 1, true, "both")

    assert {:error, :stale_connections} = write(ctx, source, target, 1, false)
    assert {:error, :stale_connections} = apply_command(ctx, request)
    assert canvas(source)["link_directions"] == %{to_string(target.id) => "both"}

    stale_batch = %{
      request_key: Ecto.UUID.generate(),
      changes: [
        %{source_id: other.id, target_id: target.id, connected: true, direction: "none"},
        %{source_id: source.id, target_id: target.id, connected: true, direction: "backward"}
      ],
      versions: [%{id: other.id, version: 0}, %{id: source.id, version: 1}]
    }

    assert {:error, :stale_connections} = apply_command(ctx, stale_batch)
    assert is_nil(canvas(other)["links"])
  end

  test "direction metadata cannot expose hidden endpoints through note or placement projections", ctx do
    source = idea_fixture(ctx, %{visibility: :shared})
    public = idea_fixture(ctx, %{visibility: :shared})
    private = idea_fixture(ctx)
    assert {:ok, _} = write(ctx, source, private, 0, true, "both")
    assert {:ok, _} = write(%{ctx | author: ctx.peer}, source, public, 1, true, "backward")
    assert {:ok, peer_view} = Ideation.get_idea(ctx.peer, ctx.project.id, ctx.session.id, source.id)
    assert peer_view.canvas["links"] == [public.id]
    assert peer_view.canvas["link_directions"] == %{to_string(public.id) => "backward"}
    assert {:ok, notes} = Ideation.list_ideas(ctx.peer, ctx.project.id, ctx.session.id)
    assert Enum.find(notes, &(&1.id == source.id)).canvas == peer_view.canvas

    placement = %{"x" => 30, "y" => 60, "request_key" => Ecto.UUID.generate()}

    assert {:ok, placed} =
             Ideation.update_idea_canvas(ctx.peer, ctx.project.id, ctx.session.id, source.id, 0, placement)

    assert placed["link_directions"] == peer_view.canvas["link_directions"]
    assert canvas(source)["link_directions"][to_string(private.id)] == "both"

    assert {:ok, deleted} = Ideation.delete_idea(ctx.author, ctx.project.id, ctx.session.id, public.id, public.revision)
    assert {:ok, hidden} = Ideation.get_idea(ctx.peer, ctx.project.id, ctx.session.id, source.id)
    assert hidden.canvas["link_directions"] == %{}

    assert {:ok, _} =
             Ideation.restore_idea(
               ctx.author,
               ctx.project.id,
               ctx.session.id,
               public.id,
               deleted.revision,
               deleted.deleted_at
             )

    assert {:ok, restored} = Ideation.get_idea(ctx.peer, ctx.project.id, ctx.session.id, source.id)
    assert restored.canvas["link_directions"] == peer_view.canvas["link_directions"]
  end

  test "connected creation appends an association and preserves earlier direction metadata", ctx do
    [source, target] = for _ <- 1..2, do: idea_fixture(ctx)
    assert {:ok, _} = write(ctx, source, target, 0, true, "backward")
    attrs = idea_attrs(%{canvas: %{"x" => 200, "y" => 400, "shape" => "plain"}, connection: %{source_ids: [source.id]}})
    assert {:ok, created} = Ideation.create_canvas_idea(ctx.author, ctx.project.id, ctx.session.id, attrs)
    assert canvas(source)["link_directions"] == %{to_string(target.id) => "backward", to_string(created.id) => "none"}
    assert {:ok, ^created} = Ideation.create_canvas_idea(ctx.author, ctx.project.id, ctx.session.id, attrs)
  end

  test "malformed explicit directions fail without persistence", ctx do
    [source, target] = for _ <- 1..2, do: idea_fixture(ctx)

    for invalid <- [nil, false, "", "arrow", :forward, [], %{}] do
      request = source |> command(target, 0, true, "none") |> put_in([:changes, Access.at(0), :direction], invalid)
      assert {:error, :invalid_connections} = apply_command(ctx, request)
      assert is_nil(canvas(source)["links"])
    end
  end

  test "snapshots remap direction keys and retain plain notes after physical row loss", ctx do
    source = idea_fixture(ctx, %{canvas: %{"x" => 10, "y" => 20, "shape" => "plain"}})
    targets = for _ <- 1..4, do: idea_fixture(ctx)

    for {{target, direction}, version} <- Enum.with_index(Enum.zip(targets, ~w(none forward backward both))) do
      assert {:ok, _} = write(ctx, source, target, version, true, direction)
    end

    capsule = capture(ctx)
    Repo.delete_all(from s in Session, where: s.project_id == ^ctx.project.id)
    assert {:ok, maps} = restore(ctx, capsule)
    saved = Repo.get!(Idea, maps["ideas"][source.id])
    assert saved.id != source.id
    assert saved.canvas["shape"] == "plain"

    assert saved.canvas["link_directions"] ==
             Map.new(Enum.zip(targets, ~w(none forward backward both)), fn {target, direction} ->
               {to_string(maps["ideas"][target.id]), direction}
             end)

    refute Map.has_key?(saved.canvas, "links_receipt")
    assert {:ok, :ok} = Repo.transact(fn -> {:ok, Ideation.verify_recovery(ctx.project.id, capsule, maps)} end)
  end

  test "malformed or detached direction keys reject recovery before live data is replaced", ctx do
    [source, target, detached] = for _ <- 1..3, do: idea_fixture(ctx)
    assert {:ok, _} = write(ctx, source, target, 0, true, "none")
    assert {:ok, inventory} = ctx |> capture() |> Capsule.open()

    for directions <- [
          nil,
          [],
          "none",
          %{to_string(target.id) => "unknown"},
          %{to_string(source.id) => "none"},
          %{to_string(detached.id) => "none"},
          %{"0#{target.id}" => "none"},
          %{"999999999999" => "none"}
        ] do
      malformed =
        update_in(inventory, ["rows", "ideas"], fn rows ->
          Enum.map(rows, fn row ->
            if row["id"] == source.id, do: put_in(row, ["canvas", "link_directions"], directions), else: row
          end)
        end)

      assert {:error, :ideation_recovery_capture_failed} = Capsule.seal(malformed)
      {:ok, bytes} = malformed |> Jason.encode!() |> Vault.encrypt()

      assert {:error, :invalid_ideation_recovery} =
               restore(ctx, %{"version" => 1, "ciphertext" => Base.encode64(bytes)})
    end

    assert is_nil(Repo.get!(Session, ctx.session.id).deleted_at)
    assert canvas(source)["link_directions"] == %{to_string(target.id) => "none"}
  end

  defp canvas(idea), do: Repo.get!(Idea, idea.id).canvas

  defp apply_command(ctx, attrs),
    do: Ideation.update_idea_connections(ctx.author, ctx.project.id, ctx.session.id, attrs)

  defp write(ctx, source, target, version, connected, direction \\ :omitted),
    do: apply_command(ctx, command(source, target, version, connected, direction))

  defp command(source, target, version, connected, direction) do
    change = %{source_id: source.id, target_id: target.id, connected: connected}
    change = if direction == :omitted, do: change, else: Map.put(change, :direction, direction)
    %{request_key: Ecto.UUID.generate(), changes: [change], versions: [%{id: source.id, version: version}]}
  end

  defp capture(ctx) do
    {:ok, snapshot} =
      Repo.transact(fn ->
        {:ok,
         ProjectSnapshotBuilder.build_canonical_snapshot_in_transaction(ctx.project.id, localization_scope: :active)}
      end)

    snapshot["ideation"]
  end

  defp restore(ctx, capsule) do
    Repo.transact(fn ->
      Repo.one!(from p in "projects", where: p.id == ^ctx.project.id, select: p.id, lock: "FOR UPDATE")
      Ideation.restore_recovery(ctx.project.id, capsule)
    end)
  end
end
