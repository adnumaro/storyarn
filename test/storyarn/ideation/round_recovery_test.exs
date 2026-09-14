defmodule Storyarn.Ideation.RoundRecoveryTest do
  use Storyarn.DataCase, async: true

  import Ecto.Query
  import Storyarn.IdeationFixtures

  alias Storyarn.Ideation
  alias Storyarn.Ideation.Recovery.Capsule
  alias Storyarn.Ideation.Sessions.Round
  alias Storyarn.Ideation.Sessions.Session
  alias Storyarn.Platform.Vault
  alias Storyarn.Projects.Versioning.Builders.ProjectSnapshotBuilder

  setup do
    ideation_fixture()
  end

  test "snapshot restores round provenance, header offsets, late notes and cross-round links after physical deletion",
       ctx do
    first = first_round(ctx)
    ordinary = idea_fixture(ctx, %{round_id: first.id})
    {ctx, active} = new_round(ctx, %{prompt: "What stands in their way?", canvas_offset_y: 720})
    late = idea_fixture(ctx, %{round_id: first.id})
    next = idea_fixture(ctx, %{round_id: active.id})
    assert {:ok, _} = Ideation.connect_ideas(ctx.author, ctx.project.id, ctx.session.id, ordinary.id, next.id, true)
    capsule = capture(ctx)

    assert {:ok, %{"version" => 7, "rows" => rows}} = Capsule.open(capsule)
    assert length(rows["rounds"]) == 2
    assert Enum.map(rows["rounds"], & &1["canvas_offset_y"]) == [0, 720]
    Repo.delete_all(from s in Session, where: s.project_id == ^ctx.project.id)
    maps = restore(ctx, capsule)
    session_id = maps["sessions"][ctx.session.id]
    assert {:ok, rounds} = Ideation.list_rounds(ctx.viewer, ctx.project.id, session_id)
    assert Enum.map(rounds, & &1.status) == [:active, :closed]
    assert Enum.map(rounds, & &1.id) == Enum.map([active, first], &maps["rounds"][&1.id])
    assert Enum.map(rounds, & &1.prompt) == [active.prompt, nil]
    assert Enum.map(rounds, & &1.canvas_offset_y) == [720, 0]

    for {original, round_id, late?} <- [
          {ordinary, maps["rounds"][first.id], false},
          {late, maps["rounds"][first.id], true},
          {next, maps["rounds"][active.id], false}
        ] do
      assert {:ok, idea} = Ideation.get_idea(ctx.author, ctx.project.id, session_id, maps["ideas"][original.id])
      assert idea.round_id == round_id
      assert idea.late_contribution == late?
      assert idea.body == original.body
      assert idea.visibility == :private
      assert {:error, :not_found} = Ideation.get_idea(ctx.owner, ctx.project.id, session_id, idea.id)
    end

    assert {:ok, linked} = Ideation.get_idea(ctx.author, ctx.project.id, session_id, maps["ideas"][ordinary.id])
    assert linked.canvas["links"] == [maps["ideas"][next.id]]
    assert {:ok, :ok} = Repo.transact(fn -> {:ok, Ideation.verify_recovery(ctx.project.id, capsule, maps)} end)

    # Stable round identities participate in generation matching; restore cannot
    # multiply an unchanged round and all of its notes on each recovery.
    for _ <- 1..3, do: assert(restore(ctx, capsule) == maps)
    assert Repo.aggregate(Round, :count) == 2
  end

  test "legacy version-one capsules normalize round defaults and remain verifiable", ctx do
    idea = idea_fixture(ctx)
    {:ok, data} = ctx |> capture() |> Capsule.open()

    legacy =
      data
      |> Map.put("version", 1)
      |> update_in(
        ["rows"],
        &Map.drop(
          &1,
          ~w(rounds timers groups group_memberships group_revisions references reference_revisions decisions decision_revisions)
        )
      )
      |> update_in(["rows", "sessions"], &Enum.map(&1, fn row -> Map.delete(row, "contributions_open") end))
      |> update_in(["rows", "ideas"], fn rows ->
        Enum.map(rows, &Map.drop(&1, ["round_id", "late_contribution", "canvas", "deleted_at"]))
      end)

    {:ok, capsule} = Capsule.seal(legacy)
    assert {:ok, normalized} = Capsule.open(capsule)
    assert normalized["version"] == 7
    assert normalized["rows"]["rounds"] == []
    {ctx, _round} = new_round(ctx, %{prompt: "Created after the old snapshot"})
    maps = restore(ctx, capsule)
    session_id = maps["sessions"][ctx.session.id]
    assert {:ok, []} = Ideation.list_rounds(ctx.author, ctx.project.id, session_id)
    assert {:ok, restored} = Ideation.get_idea(ctx.author, ctx.project.id, session_id, maps["ideas"][idea.id])
    assert restored.round_id == nil
    assert restored.late_contribution == false
    assert {:ok, :ok} = Repo.transact(fn -> {:ok, Ideation.verify_recovery(ctx.project.id, capsule, maps)} end)
    assert restore(ctx, capsule) == maps
  end

  test "version-six capsules drop prepared and cancelled rounds and start every header at zero", ctx do
    idea = idea_fixture(ctx)
    {:ok, data} = ctx |> capture() |> Capsule.open()
    [round] = data["rows"]["rounds"]
    now = round["started_at"]

    legacy =
      data
      |> Map.put("version", 6)
      |> put_in(["rows", "rounds"], [
        Map.delete(round, "canvas_offset_y"),
        round
        |> Map.delete("canvas_offset_y")
        |> Map.merge(%{"id" => round["id"] + 1, "number" => 2, "status" => "planned", "started_at" => nil}),
        round
        |> Map.delete("canvas_offset_y")
        |> Map.merge(%{
          "id" => round["id"] + 2,
          "number" => 3,
          "status" => "cancelled",
          "started_at" => nil,
          "recovery_identity" => Base.encode64(:crypto.strong_rand_bytes(16))
        })
      ])
      |> put_in(["rows", "rounds", Access.at(1), "recovery_identity"], Base.encode64(:crypto.strong_rand_bytes(16)))
      |> put_in(["rows", "rounds", Access.at(1), "closed_at"], nil)
      |> put_in(["rows", "rounds", Access.at(2), "closed_at"], nil)

    assert {:ok, capsule} = Capsule.seal(legacy)
    assert {:ok, normalized} = Capsule.open(capsule)
    assert normalized["version"] == 7
    assert [%{"number" => 1, "status" => "active", "canvas_offset_y" => 0}] = normalized["rows"]["rounds"]
    assert now
    maps = restore(ctx, capsule)
    session_id = maps["sessions"][ctx.session.id]
    assert {:ok, [restored_round]} = Ideation.list_rounds(ctx.author, ctx.project.id, session_id)
    assert restored_round.canvas_offset_y == 0
    assert {:ok, restored} = Ideation.get_idea(ctx.author, ctx.project.id, session_id, maps["ideas"][idea.id])
    assert restored.round_id == restored_round.id
    assert {:ok, :ok} = Repo.transact(fn -> {:ok, Ideation.verify_recovery(ctx.project.id, capsule, maps)} end)
  end

  test "the question of the round in progress and the band layout survive recovery with their audit", ctx do
    first = first_round(ctx)

    assert {:ok, updated} =
             Ideation.update_round(ctx.facilitator, ctx.project.id, ctx.session.id, first.id, ctx.session.revision, %{
               prompt: "Corrected question"
             })

    ctx = %{ctx | session: updated}
    {ctx, second} = new_round(ctx, %{prompt: "Next", canvas_offset_y: 500})
    capsule = capture(ctx)
    assert {:ok, data} = Capsule.open(capsule)
    assert data["version"] == 7
    assert [saved_first, saved_second] = data["rows"]["rounds"]
    assert saved_first["status"] == "closed"
    assert saved_first["prompt"] == "Corrected question"
    assert saved_second["canvas_offset_y"] == 500
    Repo.delete_all(from s in Session, where: s.project_id == ^ctx.project.id)
    maps = restore(ctx, capsule)
    session_id = maps["sessions"][ctx.session.id]
    assert {:ok, [current, previous]} = Ideation.list_rounds(ctx.viewer, ctx.project.id, session_id)
    assert previous.id == maps["rounds"][first.id]
    assert previous.recovery_identity == first.recovery_identity
    assert previous.status == :closed
    assert previous.prompt == "Corrected question"
    assert current.id == maps["rounds"][second.id]
    assert current.status == :active
    assert current.canvas_offset_y == 500

    assert {:ok, [started_revision, update_revision, _original]} =
             Ideation.list_session_revisions(ctx.viewer, ctx.project.id, session_id)

    assert started_revision.action == :round_started
    assert started_revision.snapshot["round"]["number"] == 2
    assert update_revision.action == :round_updated
    assert update_revision.snapshot["round"]["prompt"] == "Corrected question"

    assert {:ok, :ok} = Repo.transact(fn -> {:ok, Ideation.verify_recovery(ctx.project.id, capsule, maps)} end)
    assert restore(ctx, capsule) == maps

    for mutation <- [
          fn data -> put_in(data, ["rows", "rounds", Access.at(1), "started_at"], nil) end,
          fn data -> put_in(data, ["rows", "rounds", Access.at(1), "closed_at"], "2026-09-08T12:00:00.000000") end,
          fn data -> put_in(data, ["rows", "rounds", Access.at(0), "status"], "planned") end,
          fn data -> put_in(data, ["rows", "rounds", Access.at(0), "canvas_offset_y"], "0") end,
          fn data -> put_in(data, ["rows", "rounds", Access.at(1), "canvas_offset_y"], 2_000_000) end,
          fn data -> put_in(data, ["rows", "session_revisions", Access.at(1), "snapshot", "round", "number"], -1) end,
          fn data ->
            put_in(
              data,
              ["rows", "session_revisions", Access.at(2), "snapshot", "round", "started_at"],
              "not-a-date"
            )
          end
        ] do
      assert {:error, :ideation_recovery_capture_failed} = Capsule.seal(mutation.(data))
    end
  end

  test "authenticated invalid round graphs fail before changing the project", ctx do
    first = first_round(ctx)
    _idea = idea_fixture(ctx, %{round_id: first.id})
    {ctx, _second} = new_round(ctx, %{prompt: "Second"})
    {:ok, data} = ctx |> capture() |> Capsule.open()

    mutations = [
      fn data -> put_in(data, ["rows", "ideas", Access.at(0), "round_id"], -1) end,
      fn data -> put_in(data, ["rows", "ideas", Access.at(0), "late_contribution"], "yes") end,
      fn data -> put_in(data, ["rows", "rounds", Access.at(0), "session_id"], -1) end,
      fn data -> put_in(data, ["rows", "rounds", Access.at(0), "started_at"], "not-a-date") end,
      fn data -> put_in(data, ["rows", "rounds", Access.at(0), "started_at"], nil) end,
      fn data ->
        update_in(
          data,
          ["rows", "rounds", Access.at(0)],
          &Map.merge(&1, %{"status" => "cancelled", "started_at" => nil, "closed_at" => nil})
        )
      end,
      fn data -> put_in(data, ["rows", "rounds", Access.at(0), "prompt"], String.duplicate("a", 2001)) end,
      fn data -> put_in(data, ["rows", "rounds", Access.at(1), "number"], first.number) end,
      fn data -> put_in(data, ["rows", "rounds", Access.at(1), "canvas_offset_y"], nil) end,
      fn data ->
        update_in(
          data,
          ["rows", "rounds", Access.at(0)],
          &Map.merge(&1, %{"status" => "active", "closed_at" => nil})
        )
      end
    ]

    for mutate <- mutations do
      {:ok, bytes} = data |> mutate.() |> Jason.encode!() |> Vault.encrypt()
      capsule = %{"version" => 1, "ciphertext" => Base.encode64(bytes)}
      assert {:error, :invalid_ideation_recovery} = restore_result(ctx, capsule)
      assert {:ok, unchanged} = Ideation.get_session(ctx.owner, ctx.project.id, ctx.session.id)
      assert unchanged.revision == ctx.session.revision
    end
  end

  test "a round belonging to another captured session is rejected", ctx do
    round = first_round(ctx)
    idea_fixture(ctx, %{round_id: round.id})
    {:ok, other} = Ideation.create_session(ctx.facilitator, ctx.project.id, %{title: "Different session"})
    {:ok, data} = ctx |> capture() |> Capsule.open()
    invalid = put_in(data, ["rows", "ideas", Access.at(0), "session_id"], other.id)
    {:ok, bytes} = invalid |> Jason.encode!() |> Vault.encrypt()

    assert {:error, :invalid_ideation_recovery} =
             restore_result(ctx, %{"version" => 1, "ciphertext" => Base.encode64(bytes)})
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
    assert {:ok, maps} = restore_result(ctx, capsule)
    maps
  end

  defp restore_result(ctx, capsule) do
    Repo.transact(fn ->
      Repo.one!(from p in "projects", where: p.id == ^ctx.project.id, select: p.id, lock: "FOR UPDATE")
      Ideation.restore_recovery(ctx.project.id, capsule)
    end)
  end
end
