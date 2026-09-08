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

  test "snapshot restores round provenance, late notes and cross-round links after physical deletion", ctx do
    unround = idea_fixture(ctx)
    {ctx, closed} = add_round(ctx, "What drives the antagonist?")
    ctx = start_round(ctx, closed)
    ordinary = idea_fixture(ctx, %{round_id: closed.id})
    ctx = close_round(ctx, closed)
    late = idea_fixture(ctx, %{round_id: closed.id})
    {ctx, active} = add_round(ctx, "What stands in their way?")
    ctx = start_round(ctx, active)
    next = idea_fixture(ctx, %{round_id: active.id})
    {ctx, planned} = add_round(ctx, "What could change?")
    assert {:ok, _} = Ideation.connect_ideas(ctx.author, ctx.project.id, ctx.session.id, ordinary.id, next.id, true)
    capsule = capture(ctx)

    assert {:ok, %{"version" => 3, "rows" => rows}} = Capsule.open(capsule)
    assert length(rows["rounds"]) == 3
    Repo.delete_all(from s in Session, where: s.project_id == ^ctx.project.id)
    maps = restore(ctx, capsule)
    session_id = maps["sessions"][ctx.session.id]
    assert {:ok, rounds} = Ideation.list_rounds(ctx.viewer, ctx.project.id, session_id)
    assert Enum.map(rounds, & &1.status) == [:planned, :active, :closed]
    assert Enum.map(rounds, & &1.id) == Enum.map([planned, active, closed], &maps["rounds"][&1.id])
    assert Enum.map(rounds, & &1.prompt) == [planned.prompt, active.prompt, closed.prompt]

    for {original, round_id, late?} <- [
          {unround, nil, false},
          {ordinary, maps["rounds"][closed.id], false},
          {late, maps["rounds"][closed.id], true},
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
    assert Repo.aggregate(Round, :count) == 3
  end

  test "legacy version-one capsules normalize round defaults and remain verifiable", ctx do
    idea = idea_fixture(ctx)
    {:ok, data} = ctx |> capture() |> Capsule.open()

    legacy =
      data
      |> Map.put("version", 1)
      |> update_in(["rows"], &Map.drop(&1, ["rounds", "timers"]))
      |> update_in(["rows", "sessions"], &Enum.map(&1, fn row -> Map.delete(row, "contributions_open") end))
      |> update_in(["rows", "ideas"], fn rows ->
        Enum.map(rows, &Map.drop(&1, ["round_id", "late_contribution", "canvas", "deleted_at"]))
      end)

    {:ok, capsule} = Capsule.seal(legacy)
    assert {:ok, normalized} = Capsule.open(capsule)
    assert normalized["rows"]["rounds"] == []
    {ctx, round} = add_round(ctx, "Created after the old snapshot")
    _ctx = start_round(ctx, round)
    maps = restore(ctx, capsule)
    session_id = maps["sessions"][ctx.session.id]
    assert {:ok, []} = Ideation.list_rounds(ctx.author, ctx.project.id, session_id)
    assert {:ok, restored} = Ideation.get_idea(ctx.author, ctx.project.id, session_id, maps["ideas"][idea.id])
    assert restored.round_id == nil
    assert restored.late_contribution == false
    assert {:ok, :ok} = Repo.transact(fn -> {:ok, Ideation.verify_recovery(ctx.project.id, capsule, maps)} end)
    assert restore(ctx, capsule) == maps
  end

  test "edited and cancelled planned rounds survive recovery with their audit and cannot accept notes", ctx do
    {ctx, planned} = add_round(ctx, "Typo")

    assert {:ok, updated} =
             Ideation.update_round(ctx.facilitator, ctx.project.id, ctx.session.id, planned.id, ctx.session.revision, %{
               prompt: "Corrected question"
             })

    assert {:ok, cancelled} =
             Ideation.cancel_round(ctx.owner, ctx.project.id, ctx.session.id, planned.id, updated.revision)

    ctx = %{ctx | session: cancelled}
    capsule = capture(ctx)
    assert {:ok, data} = Capsule.open(capsule)
    assert data["version"] == 3
    assert [saved] = data["rows"]["rounds"]
    assert saved["status"] == "cancelled"
    assert saved["started_at"] == nil
    assert saved["closed_at"] == nil
    Repo.delete_all(from s in Session, where: s.project_id == ^ctx.project.id)
    maps = restore(ctx, capsule)
    session_id = maps["sessions"][ctx.session.id]
    assert {:ok, [round]} = Ideation.list_rounds(ctx.viewer, ctx.project.id, session_id)
    assert round.id == maps["rounds"][planned.id]
    assert round.recovery_identity == planned.recovery_identity
    assert round.status == :cancelled
    assert round.prompt == "Corrected question"
    assert round.started_at == nil
    assert round.closed_at == nil

    assert {:ok, [cancel_revision, update_revision, _prepared, _original]} =
             Ideation.list_session_revisions(ctx.viewer, ctx.project.id, session_id)

    assert cancel_revision.action == :round_cancelled
    assert update_revision.action == :round_updated
    assert update_revision.snapshot["round"]["prompt"] == "Corrected question"

    assert {:error, :round_cancelled} =
             Ideation.create_idea(ctx.author, ctx.project.id, session_id, idea_attrs(%{round_id: round.id}))

    assert {:ok, :ok} = Repo.transact(fn -> {:ok, Ideation.verify_recovery(ctx.project.id, capsule, maps)} end)
    assert restore(ctx, capsule) == maps

    for mutation <- [
          fn data -> put_in(data, ["rows", "rounds", Access.at(0), "started_at"], "2026-09-08T12:00:00.000000") end,
          fn data -> put_in(data, ["rows", "rounds", Access.at(0), "closed_at"], "2026-09-08T12:00:00.000000") end,
          fn data -> put_in(data, ["rows", "session_revisions", Access.at(2), "snapshot", "round", "number"], -1) end,
          fn data ->
            put_in(
              data,
              ["rows", "session_revisions", Access.at(3), "snapshot", "round", "started_at"],
              "2026-09-08T12:00:00.000000"
            )
          end
        ] do
      assert {:error, :ideation_recovery_capture_failed} = Capsule.seal(mutation.(data))
    end
  end

  test "authenticated invalid round graphs fail before changing the project", ctx do
    {ctx, first} = add_round(ctx, "First")
    ctx = start_round(ctx, first)
    _idea = idea_fixture(ctx, %{round_id: first.id})
    {ctx, _second} = add_round(ctx, "Second")
    {:ok, data} = ctx |> capture() |> Capsule.open()

    mutations = [
      fn data -> put_in(data, ["rows", "ideas", Access.at(0), "round_id"], -1) end,
      fn data -> put_in(data, ["rows", "ideas", Access.at(0), "late_contribution"], "yes") end,
      fn data -> put_in(data, ["rows", "ideas", Access.at(0), "late_contribution"], true) end,
      fn data -> put_in(data, ["rows", "rounds", Access.at(0), "session_id"], -1) end,
      fn data -> put_in(data, ["rows", "rounds", Access.at(0), "started_at"], "not-a-date") end,
      fn data -> put_in(data, ["rows", "rounds", Access.at(0), "started_at"], nil) end,
      fn data ->
        update_in(data, ["rows", "rounds", Access.at(0)], &Map.merge(&1, %{"status" => "cancelled", "started_at" => nil}))
      end,
      fn data -> put_in(data, ["rows", "rounds", Access.at(0), "prompt"], String.duplicate("é", 1500)) end,
      fn data -> put_in(data, ["rows", "rounds", Access.at(1), "number"], first.number) end,
      fn data ->
        started = get_in(data, ["rows", "rounds", Access.at(0), "started_at"])

        update_in(
          data,
          ["rows", "rounds", Access.at(1)],
          &Map.merge(&1, %{"status" => "active", "started_at" => started})
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
    {ctx, round} = add_round(ctx, "Original session")
    ctx = start_round(ctx, round)
    idea_fixture(ctx, %{round_id: round.id})
    {:ok, other} = Ideation.create_session(ctx.facilitator, ctx.project.id, %{title: "Different session"})
    {:ok, data} = ctx |> capture() |> Capsule.open()
    invalid = put_in(data, ["rows", "ideas", Access.at(0), "session_id"], other.id)
    {:ok, bytes} = invalid |> Jason.encode!() |> Vault.encrypt()

    assert {:error, :invalid_ideation_recovery} =
             restore_result(ctx, %{"version" => 1, "ciphertext" => Base.encode64(bytes)})
  end

  defp add_round(ctx, prompt) do
    {:ok, session} =
      Ideation.create_round(ctx.facilitator, ctx.project.id, ctx.session.id, ctx.session.revision, %{prompt: prompt})

    {:ok, [round | _]} = Ideation.list_rounds(ctx.facilitator, ctx.project.id, session.id)
    {%{ctx | session: session}, round}
  end

  defp start_round(ctx, round) do
    {:ok, session} = Ideation.start_round(ctx.facilitator, ctx.project.id, ctx.session.id, round.id, ctx.session.revision)
    %{ctx | session: session}
  end

  defp close_round(ctx, round) do
    {:ok, session} = Ideation.close_round(ctx.facilitator, ctx.project.id, ctx.session.id, round.id, ctx.session.revision)
    %{ctx | session: session}
  end

  defp capture(ctx) do
    {:ok, snapshot} =
      Repo.transact(fn ->
        {:ok, ProjectSnapshotBuilder.build_canonical_snapshot_in_transaction(ctx.project.id, localization_scope: :active)}
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
