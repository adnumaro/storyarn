defmodule Storyarn.Ideation.RoundRecoveryTest do
  use Storyarn.DataCase, async: true

  import Ecto.Query
  import Storyarn.IdeationFixtures

  alias Storyarn.Ideation
  alias Storyarn.Ideation.Groups.Group
  alias Storyarn.Ideation.Recovery.Capsule
  alias Storyarn.Ideation.Sessions.Round
  alias Storyarn.Ideation.Sessions.Session
  alias Storyarn.Platform.Vault
  alias Storyarn.Projects.Versioning.Builders.ProjectSnapshotBuilder

  setup do
    ideation_fixture()
  end

  test "snapshot restores round provenance, late notes and cross-round links after physical deletion",
       ctx do
    first = first_round(ctx)
    ordinary = idea_fixture(ctx, %{round_id: first.id})
    {ctx, active} = new_round(ctx, %{prompt: "What stands in their way?"})
    late = idea_fixture(ctx, %{round_id: first.id})
    next = idea_fixture(ctx, %{round_id: active.id})
    assert {:ok, _} = Ideation.connect_ideas(ctx.author, ctx.project.id, ctx.session.id, ordinary.id, next.id, true)
    capsule = capture(ctx)

    assert {:ok, %{"version" => 12, "rows" => rows}} = Capsule.open(capsule)
    assert length(rows["rounds"]) == 2
    Repo.delete_all(from s in Session, where: s.project_id == ^ctx.project.id)
    maps = restore(ctx, capsule)
    session_id = maps["sessions"][ctx.session.id]
    assert {:ok, rounds} = Ideation.list_rounds(ctx.viewer, ctx.project.id, session_id)
    assert Enum.map(rounds, & &1.status) == [:active, :closed]
    assert Enum.map(rounds, & &1.id) == Enum.map([active, first], &maps["rounds"][&1.id])
    assert Enum.map(rounds, & &1.prompt) == [active.prompt, nil]

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

  test "the audit trail of rounds prepared or cancelled before bands still captures and restores", ctx do
    idea = idea_fixture(ctx)
    {:ok, [existing | _]} = Ideation.list_session_revisions(ctx.facilitator, ctx.project.id, ctx.session.id)

    audit = fn number, action, status ->
      %{
        session_id: ctx.session.id,
        actor_id: ctx.facilitator.user.id,
        number: number,
        action: action,
        snapshot:
          Map.put(existing.snapshot, "round", %{
            "number" => 2,
            "prompt" => "Prepared before bands",
            "status" => status,
            "started_at" => nil,
            "closed_at" => nil
          }),
        inserted_at: DateTime.utc_now()
      }
    end

    # What the old create_round / cancel_round commands recorded; the migration keeps these rows.
    Repo.insert_all("ideation_session_revisions", [
      audit.(existing.number + 1, "round_created", "planned"),
      audit.(existing.number + 2, "round_cancelled", "cancelled")
    ])

    Repo.update_all(from(s in "ideation_sessions", where: s.id == ^ctx.session.id), inc: [revision: 2])

    capsule = capture(ctx)
    assert {:ok, opened} = Capsule.open(capsule)
    assert Enum.count(opened["rows"]["session_revisions"], &(&1["action"] in ~w(round_created round_cancelled))) == 2

    {ctx, _round} = new_round(ctx, %{prompt: "Kept moving"})
    maps = restore(ctx, capsule)
    session_id = maps["sessions"][ctx.session.id]

    assert {:ok, %{round_id: round_id}} =
             Ideation.get_idea(ctx.author, ctx.project.id, session_id, maps["ideas"][idea.id])

    assert {:ok, [%{id: ^round_id, number: 1}]} = Ideation.list_rounds(ctx.author, ctx.project.id, session_id)
    assert {:ok, :ok} = Repo.transact(fn -> {:ok, Ideation.verify_recovery(ctx.project.id, capsule, maps)} end)
  end

  test "a private session before round privacy hides every round it had, and its clock's promise moves to the round in progress",
       ctx do
    idea_fixture(ctx)
    {ctx, _second} = new_round(ctx, %{prompt: "Second"})
    {:ok, session} = Ideation.get_session(ctx.facilitator, ctx.project.id, ctx.session.id)
    {:ok, _} = Ideation.start_timer(ctx.facilitator, ctx.project.id, ctx.session.id, session.revision, %{seconds: 300})
    {:ok, data} = ctx |> capture() |> Capsule.open()

    legacy =
      data
      |> Map.put("version", 7)
      |> update_in(["rows"], &Map.drop(&1, ~w(decision_applications decision_task_links)))
      |> update_in(
        ["rows", "rounds"],
        &Enum.map(&1, fn row -> Map.drop(row, ~w(private reveal_on_expiry revealed_at decision_lane)) end)
      )
      |> update_in(
        ["rows", "timers"],
        &Enum.map(&1, fn row -> row |> Map.put("reveal_on_expiry", true) |> Map.delete("round_id") end)
      )
      |> update_in(["rows", "groups"], &Enum.map(&1, fn row -> Map.delete(row, "round_id") end))
      |> update_in(["rows", "sessions"], fn rows ->
        Enum.map(rows, &put_in(&1, ["configuration", "private_mode"], true))
      end)

    {:ok, capsule} = Capsule.seal(legacy)
    assert {:ok, normalized} = Capsule.open(capsule)

    assert [
             %{"number" => 1, "status" => "closed", "private" => true, "reveal_on_expiry" => false},
             %{"number" => 2, "status" => "active", "private" => true, "reveal_on_expiry" => true}
           ] = Enum.sort_by(normalized["rows"]["rounds"], & &1["number"])

    refute Enum.any?(normalized["rows"]["sessions"], &Map.has_key?(&1["configuration"], "private_mode"))
    refute Enum.any?(normalized["rows"]["timers"], &Map.has_key?(&1, "reveal_on_expiry"))
    # The clock, once the session's, joins the round in progress.
    active = Enum.find(normalized["rows"]["rounds"], &(&1["status"] == "active"))
    assert [%{"round_id" => round_id}] = normalized["rows"]["timers"]
    assert round_id == active["id"]
  end

  test "a version-eight clock joins the last round when every round is closed, and restores there", ctx do
    {:ok, [first]} = Ideation.list_rounds(ctx.facilitator, ctx.project.id, ctx.session.id)
    {:ok, session} = Ideation.get_session(ctx.facilitator, ctx.project.id, ctx.session.id)
    {:ok, _} = Ideation.start_timer(ctx.facilitator, ctx.project.id, ctx.session.id, session.revision, %{seconds: 300})
    ctx = close_round(ctx, first)
    {:ok, data} = ctx |> capture() |> Capsule.open()

    legacy =
      data
      |> Map.put("version", 8)
      |> update_in(["rows"], &Map.drop(&1, ~w(decision_applications decision_task_links)))
      |> update_in(["rows", "rounds"], &Enum.map(&1, fn row -> Map.delete(row, "decision_lane") end))
      |> update_in(["rows", "timers"], &Enum.map(&1, fn row -> Map.delete(row, "round_id") end))

    {:ok, capsule} = Capsule.seal(legacy)
    assert {:ok, normalized} = Capsule.open(capsule)
    assert [%{"round_id" => round_id, "status" => "cancelled"}] = normalized["rows"]["timers"]
    assert round_id == first.id

    maps = restore(ctx, capsule)
    session_id = maps["sessions"][ctx.session.id]

    assert {:ok, [%{id: restored_round, status: :closed}]} =
             Ideation.list_rounds(ctx.author, ctx.project.id, session_id)

    assert {:ok, nil} = Ideation.get_timer(ctx.author, ctx.project.id, session_id)

    assert [[^restored_round, "cancelled"]] =
             Repo.all(from(t in "ideation_timers", where: t.session_id == ^session_id, select: [t.round_id, t.status]))
  end

  test "legacy separated synthesis keeps its source round and privacy through repeated recovery", ctx do
    {ctx, source_round} = new_round(ctx, %{prompt: "The source round"})
    group = separated_group(ctx)
    {:ok, data} = ctx |> capture() |> Capsule.open()
    legacy = legacy_private_groups(data, 7)
    {:ok, capsule} = Capsule.seal(legacy)
    maps = restore(ctx, capsule)
    session_id = maps["sessions"][ctx.session.id]
    round_id = maps["rounds"][source_round.id]
    restored = Repo.get!(Group, maps["groups"][group.id])

    assert restored.round_id == round_id
    assert restored.synthesis == group.synthesis
    assert {:ok, []} = Ideation.list_groups(ctx.viewer, ctx.project.id, session_id)
    assert {:ok, :ok} = Repo.transact(fn -> {:ok, Ideation.verify_recovery(ctx.project.id, capsule, maps)} end)
    assert restore(ctx, capsule) == maps

    {:ok, session} = Ideation.get_session(ctx.facilitator, ctx.project.id, session_id)
    assert {:ok, _} = Ideation.reveal_round(ctx.facilitator, ctx.project.id, session_id, round_id, session.revision)
    assert {:ok, [visible]} = Ideation.list_groups(ctx.viewer, ctx.project.id, session_id)
    assert visible.synthesis == group.synthesis
    assert visible.idea_ids == []
  end

  test "legacy separated synthesis without rounds joins the restored private first round", ctx do
    group = separated_group(ctx)
    {:ok, data} = ctx |> capture() |> Capsule.open()

    legacy =
      data
      |> legacy_private_groups(6)
      |> put_in(["rows", "rounds"], [])
      |> update_in(["rows", "ideas"], fn rows -> Enum.map(rows, &Map.put(&1, "round_id", nil)) end)

    {:ok, capsule} = Capsule.seal(legacy)
    maps = restore(ctx, capsule)
    session_id = maps["sessions"][ctx.session.id]
    assert {:ok, [%{id: round_id, private: true}]} = Ideation.list_rounds(ctx.viewer, ctx.project.id, session_id)
    assert Repo.get!(Group, maps["groups"][group.id]).round_id == round_id
    assert {:ok, []} = Ideation.list_groups(ctx.viewer, ctx.project.id, session_id)
    assert {:ok, :ok} = Repo.transact(fn -> {:ok, Ideation.verify_recovery(ctx.project.id, capsule, maps)} end)
    assert restore(ctx, capsule) == maps
  end

  test "legacy synthesis falls back to the first round when its retained sources have no round", ctx do
    group = separated_group(ctx)
    first = first_round(ctx)
    {ctx, _second} = new_round(ctx)
    {:ok, data} = ctx |> capture() |> Capsule.open()

    legacy =
      data
      |> legacy_private_groups(7)
      |> update_in(["rows", "ideas"], fn rows -> Enum.map(rows, &Map.put(&1, "round_id", nil)) end)

    {:ok, capsule} = Capsule.seal(legacy)
    maps = restore(ctx, capsule)
    session_id = maps["sessions"][ctx.session.id]
    assert Repo.get!(Group, maps["groups"][group.id]).round_id == maps["rounds"][first.id]
    assert {:ok, []} = Ideation.list_groups(ctx.viewer, ctx.project.id, session_id)
    assert {:ok, :ok} = Repo.transact(fn -> {:ok, Ideation.verify_recovery(ctx.project.id, capsule, maps)} end)
    assert restore(ctx, capsule) == maps
  end

  test "legacy version-one capsules normalize round defaults and remain verifiable", ctx do
    idea = idea_fixture(ctx)
    {:ok, data} = ctx |> capture() |> Capsule.open()

    legacy =
      data
      |> Map.put("version", 1)
      |> update_in(
        ["rows", "rounds"],
        &Enum.map(&1, fn row -> Map.drop(row, ~w(private reveal_on_expiry revealed_at decision_lane)) end)
      )
      |> update_in(
        ["rows", "timers"],
        &Enum.map(&1, fn row -> row |> Map.put("reveal_on_expiry", false) |> Map.delete("round_id") end)
      )
      |> update_in(["rows", "groups"], &Enum.map(&1, fn row -> Map.delete(row, "round_id") end))
      |> update_in(
        ["rows"],
        &Map.drop(
          &1,
          ~w(rounds timers groups group_memberships group_revisions references reference_revisions decisions decision_revisions decision_applications decision_task_links)
        )
      )
      |> update_in(["rows", "sessions"], &Enum.map(&1, fn row -> Map.delete(row, "contributions_open") end))
      |> update_in(["rows", "ideas"], fn rows ->
        Enum.map(rows, &Map.drop(&1, ["round_id", "late_contribution", "canvas", "deleted_at"]))
      end)

    {:ok, capsule} = Capsule.seal(legacy)
    assert {:ok, normalized} = Capsule.open(capsule)
    assert normalized["version"] == 12
    # A session that had no rounds is born its Round 1, in progress, and its notes join it.
    assert [%{"number" => 1, "status" => "active", "private" => false, "session_id" => born_session}] =
             normalized["rows"]["rounds"]

    assert born_session == ctx.session.id
    assert Enum.all?(normalized["rows"]["ideas"], &(&1["round_id"] != nil and &1["late_contribution"] == false))
    {ctx, _round} = new_round(ctx, %{prompt: "Created after the old snapshot"})
    maps = restore(ctx, capsule)
    session_id = maps["sessions"][ctx.session.id]
    assert {:ok, [%{number: 1, status: :active} = first]} = Ideation.list_rounds(ctx.author, ctx.project.id, session_id)
    assert {:ok, restored} = Ideation.get_idea(ctx.author, ctx.project.id, session_id, maps["ideas"][idea.id])
    assert restored.round_id == first.id
    assert restored.late_contribution == false
    assert {:ok, :ok} = Repo.transact(fn -> {:ok, Ideation.verify_recovery(ctx.project.id, capsule, maps)} end)
    assert restore(ctx, capsule) == maps
  end

  test "version-six capsules drop prepared and cancelled rounds and start every header at zero", ctx do
    idea = idea_fixture(ctx)
    {:ok, data} = ctx |> capture() |> Capsule.open()
    [round] = data["rows"]["rounds"]
    now = round["started_at"]
    # Rounds learnt their privacy in version 8; the legacy rows never carried it.
    round = Map.drop(round, ~w(private reveal_on_expiry revealed_at decision_lane))

    legacy =
      data
      |> Map.put("version", 6)
      |> update_in(["rows"], &Map.drop(&1, ~w(decision_applications decision_task_links)))
      |> update_in(
        ["rows", "rounds"],
        &Enum.map(&1, fn row -> Map.drop(row, ~w(private reveal_on_expiry revealed_at decision_lane)) end)
      )
      |> update_in(
        ["rows", "timers"],
        &Enum.map(&1, fn row -> row |> Map.put("reveal_on_expiry", false) |> Map.delete("round_id") end)
      )
      |> update_in(["rows", "groups"], &Enum.map(&1, fn row -> Map.delete(row, "round_id") end))
      |> put_in(["rows", "rounds"], [
        round,
        Map.merge(round, %{"id" => round["id"] + 1, "number" => 2, "status" => "planned", "started_at" => nil}),
        Map.merge(round, %{
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
    assert normalized["version"] == 12
    assert [%{"number" => 1, "status" => "active"} = normalized_round] = normalized["rows"]["rounds"]
    refute Map.has_key?(normalized_round, "canvas_offset_y")
    assert now
    maps = restore(ctx, capsule)
    session_id = maps["sessions"][ctx.session.id]
    assert {:ok, [restored_round]} = Ideation.list_rounds(ctx.author, ctx.project.id, session_id)
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

    assert {:ok, _} =
             Ideation.move_decision_lane(ctx.author, ctx.project.id, ctx.session.id, first.id, %{
               x: -40,
               y: 612.5,
               version: 0
             })

    {ctx, second} = new_round(ctx, %{prompt: "Next"})

    for attrs <- [%{x: 5, y: 5, version: 0}, %{x: nil, y: nil, version: 1}] do
      assert {:ok, _} = Ideation.move_decision_lane(ctx.author, ctx.project.id, ctx.session.id, second.id, attrs)
    end

    capsule = capture(ctx)
    assert {:ok, data} = Capsule.open(capsule)
    assert data["version"] == 12
    assert [saved_first, saved_second] = data["rows"]["rounds"]
    assert saved_first["status"] == "closed"
    assert saved_first["prompt"] == "Corrected question"
    assert saved_first["decision_lane"] == %{"x" => -40, "y" => 612.5, "version" => 1}
    assert saved_second["decision_lane"] == %{"version" => 2}
    Repo.delete_all(from s in Session, where: s.project_id == ^ctx.project.id)
    maps = restore(ctx, capsule)
    session_id = maps["sessions"][ctx.session.id]
    assert {:ok, [current, previous]} = Ideation.list_rounds(ctx.viewer, ctx.project.id, session_id)
    assert previous.id == maps["rounds"][first.id]
    assert previous.recovery_identity == first.recovery_identity
    assert previous.status == :closed
    assert previous.prompt == "Corrected question"
    assert previous.decision_lane == %{"x" => -40, "y" => 612.5, "version" => 1}
    assert current.id == maps["rounds"][second.id]
    assert current.decision_lane == %{"version" => 2}
    assert current.status == :active

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
          fn data -> put_in(data, ["rows", "rounds", Access.at(0), "decision_lane", "x"], "left") end,
          fn data -> put_in(data, ["rows", "rounds", Access.at(0), "decision_lane", "version"], 0) end,
          fn data -> put_in(data, ["rows", "rounds", Access.at(0), "decision_lane", "y"], -1) end,
          fn data -> put_in(data, ["rows", "rounds", Access.at(1), "decision_lane"], %{"version" => 0}) end,
          fn data -> put_in(data, ["rows", "rounds", Access.at(1), "decision_lane"], %{"x" => 0, "y" => 0}) end,
          fn data -> put_in(data, ["rows", "rounds", Access.at(1), "decision_lane"], nil) end,
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

  defp separated_group(ctx) do
    attrs = %{visibility: :shared, canvas: %{"x" => 0, "y" => 100, "width" => 280, "color" => "mint"}}
    first = idea_fixture(ctx, attrs)
    second = idea_fixture(ctx, attrs, ctx.peer)

    {:ok, group} =
      Ideation.create_group(ctx.author, ctx.project.id, ctx.session.id, %{
        request_key: Ecto.UUID.generate(),
        title: "Private strategy",
        synthesis: "A conclusion awaiting reveal",
        idea_ids: [first.id, second.id],
        canvas: %{x: 0, y: 80, width: 650, height: 450}
      })

    {:ok, separated} =
      Ideation.update_group(
        ctx.author,
        ctx.project.id,
        ctx.session.id,
        group.id,
        group.version,
        edit_attrs(%{idea_ids: []})
      )

    separated
  end

  defp legacy_private_groups(data, version) do
    data
    |> Map.put("version", version)
    |> update_in(["rows"], &Map.drop(&1, ~w(decision_applications decision_task_links)))
    |> update_in(
      ["rows", "rounds"],
      &Enum.map(&1, fn row -> Map.drop(row, ~w(private reveal_on_expiry revealed_at decision_lane)) end)
    )
    |> update_in(["rows", "groups"], &Enum.map(&1, fn row -> Map.delete(row, "round_id") end))
    |> update_in(
      ["rows", "timers"],
      &Enum.map(&1, fn row -> row |> Map.put("reveal_on_expiry", false) |> Map.delete("round_id") end)
    )
    |> update_in(["rows", "sessions"], fn rows ->
      Enum.map(rows, &put_in(&1, ["configuration", "private_mode"], true))
    end)
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
