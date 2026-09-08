defmodule Storyarn.Ideation.TimerRecoveryTest do
  use Storyarn.DataCase, async: true

  import Ecto.Query
  import Storyarn.IdeationFixtures

  alias Storyarn.Ideation
  alias Storyarn.Ideation.Recovery.Capsule
  alias Storyarn.Ideation.Recovery.Records
  alias Storyarn.Ideation.Sessions.Session
  alias Storyarn.Ideation.Sessions.Timer
  alias Storyarn.Platform.Vault
  alias Storyarn.Projects.Versioning.Builders.ProjectSnapshotBuilder

  setup do
    ideation_fixture()
  end

  test "running timers restore paused with preserved settings, actor and a fenced deadline", ctx do
    {:ok, _} = Ideation.set_private_mode(ctx.facilitator, ctx.project.id, ctx.session.id, ctx.session.revision, true)
    {:ok, session} = Ideation.get_session(ctx.facilitator, ctx.project.id, ctx.session.id)
    ctx = %{ctx | session: session}
    idea = idea_fixture(ctx, %{configuration_version: ctx.session.configuration_version})
    {ctx, timer} = start(ctx, %{reveal_on_expiry: true, close_contributions_on_expiry: true})
    capsule = capture(ctx)
    Repo.delete_all(from s in Session, where: s.project_id == ^ctx.project.id)
    maps = restore(ctx, capsule)
    session_id = maps["sessions"][ctx.session.id]

    assert {:ok, restored} = Ideation.get_timer(ctx.viewer, ctx.project.id, session_id)
    assert restored.id == maps["timers"][timer.id]
    assert restored.id != timer.id
    assert restored.recovery_identity == timer.recovery_identity
    assert restored.actor_id == ctx.facilitator.user.id
    assert restored.status == :paused
    assert restored.version == timer.version + 1
    assert restored.deadline_at == nil
    assert restored.remaining_seconds == timer.remaining_seconds
    assert restored.reveal_on_expiry
    assert restored.close_contributions_on_expiry
    assert {:ok, %{outcome: :not_found}} = Ideation.expire_timer(timer.id, timer.version)
    assert {:ok, %{outcome: :stale}} = Ideation.expire_timer(restored.id, timer.version)
    assert {:ok, session} = Ideation.get_session(ctx.facilitator, ctx.project.id, session_id)
    assert session.configuration.private_mode
    assert session.contributions_open
    assert {:error, :not_found} = Ideation.get_idea(ctx.owner, ctx.project.id, session_id, maps["ideas"][idea.id])

    assert {:ok, _} =
             Ideation.resume_timer(ctx.facilitator, ctx.project.id, session_id, session.revision, restored.version)

    assert {:ok, resumed} = Ideation.get_timer(ctx.viewer, ctx.project.id, session_id)
    assert resumed.status == :running
    assert resumed.version == restored.version + 1
    assert resumed.deadline_at
  end

  test "restoring an unchanged live generation pauses it and repeated restore does not multiply timers", ctx do
    {ctx, timer} = start(ctx)
    capsule = capture(ctx)
    maps = restore(ctx, capsule)
    assert maps["sessions"][ctx.session.id] == ctx.session.id
    assert maps["timers"][timer.id] == timer.id
    assert {:ok, restored} = Ideation.get_timer(ctx.viewer, ctx.project.id, ctx.session.id)
    assert restored.status == :paused
    assert restored.version == timer.version + 1
    assert {:ok, %{outcome: :stale}} = Ideation.expire_timer(timer.id, timer.version)

    for _ <- 1..3, do: assert(restore(ctx, capsule) == maps)
    assert Repo.aggregate(Timer, :count) == 1
    assert Repo.aggregate(Session, :count) == 1
  end

  for status <- [:running, :paused] do
    @tag timer_status: status
    test "recovering and reopening a replaced session cancels its #{status} timer", ctx do
      {:ok, _} =
        Ideation.set_private_mode(ctx.facilitator, ctx.project.id, ctx.session.id, ctx.session.revision, true)

      {:ok, session} = Ideation.get_session(ctx.facilitator, ctx.project.id, ctx.session.id)
      ctx = %{ctx | session: session}
      idea = idea_fixture(ctx, %{configuration_version: session.configuration_version})
      {ctx, timer} = start(ctx, %{reveal_on_expiry: true, close_contributions_on_expiry: true})

      if ctx.timer_status == :paused do
        assert {:ok, _} =
                 Ideation.pause_timer(ctx.facilitator, ctx.project.id, session.id, ctx.session.revision, timer.version)
      end

      assert {:ok, timer} = Ideation.get_timer(ctx.facilitator, ctx.project.id, session.id)
      assert {:ok, session} = Ideation.get_session(ctx.facilitator, ctx.project.id, session.id)
      capsule = capture(ctx)

      assert {:ok, replaced} =
               Ideation.update_session(ctx.facilitator, ctx.project.id, session.id, session.revision, %{
                 title: "Changed after the timer snapshot"
               })

      maps = restore(ctx, capsule)
      refute maps["sessions"][session.id] == session.id
      assert {:error, :not_found} = Ideation.get_session(ctx.owner, ctx.project.id, session.id)

      assert {:ok, recovered} =
               Ideation.recover_session(ctx.owner, ctx.project.id, replaced.id, replaced.revision)

      assert recovered.status == :archived
      assert {:ok, reopened} = Ideation.reopen_session(ctx.owner, ctx.project.id, recovered.id, recovered.revision)

      # Deliver the old job after its deadline. A cancelled timer has no deadline;
      # only a timer incorrectly left running needs to be made due for this probe.
      Repo.update_all(from(t in Timer, where: t.id == ^timer.id and t.status == :running),
        set: [deadline_at: timer.started_at]
      )

      assert {:ok, %{outcome: :stale}} = Ideation.expire_timer(timer.id, timer.version)
      assert {:ok, cancelled} = Ideation.get_timer(ctx.owner, ctx.project.id, reopened.id)
      assert cancelled.status == :cancelled
      assert cancelled.version == timer.version + 1
      assert cancelled.deadline_at == nil
      assert cancelled.remaining_seconds == 0

      assert {:ok, current} = Ideation.get_session(ctx.owner, ctx.project.id, reopened.id)
      assert current.contributions_open
      assert current.configuration.private_mode
      assert {:error, :not_found} = Ideation.get_idea(ctx.owner, ctx.project.id, reopened.id, idea.id)
      assert {:ok, _} = Ideation.get_idea(ctx.author, ctx.project.id, reopened.id, idea.id)
    end
  end

  test "canonical capture is stable while a countdown is running", ctx do
    {ctx, _timer} = start(ctx)
    assert {:ok, first} = Repo.transact(fn -> Records.capture(ctx.project.id) end)
    assert {:ok, second} = Repo.transact(fn -> Records.capture(ctx.project.id) end)
    assert first == second
    assert first["version"] == 3
    assert capture(ctx) == capture(ctx)
  end

  test "a paused timer preserves remaining time and contribution closure through physical recovery", ctx do
    {ctx, timer} = start(ctx)

    assert {:ok, paused} =
             Ideation.pause_timer(ctx.facilitator, ctx.project.id, ctx.session.id, ctx.session.revision, timer.version)

    assert {:ok, closed} =
             Ideation.set_contributions_open(ctx.facilitator, ctx.project.id, ctx.session.id, paused.revision, false)

    ctx = %{ctx | session: closed}
    assert {:ok, timer} = Ideation.get_timer(ctx.viewer, ctx.project.id, ctx.session.id)
    capsule = capture(ctx)
    Repo.delete_all(from s in Session, where: s.project_id == ^ctx.project.id)
    maps = restore(ctx, capsule)
    id = maps["sessions"][ctx.session.id]
    assert {:ok, restored} = Ideation.get_timer(ctx.viewer, ctx.project.id, id)
    assert restored.status == :paused
    assert restored.version == timer.version
    assert restored.remaining_seconds == timer.remaining_seconds
    assert {:ok, session} = Ideation.get_session(ctx.facilitator, ctx.project.id, id)
    refute session.contributions_open
    assert {:error, :contributions_closed} = Ideation.create_idea(ctx.author, ctx.project.id, id, idea_attrs())
    assert {:ok, _} = Ideation.set_contributions_open(ctx.facilitator, ctx.project.id, id, session.revision, true)
    assert {:ok, _} = Ideation.create_idea(ctx.author, ctx.project.id, id, idea_attrs())
  end

  test "terminal cancellation and elapsed outcomes survive snapshots", ctx do
    for state <- [:cancelled, :elapsed] do
      {ctx, timer} = start(ctx)

      case state do
        :cancelled ->
          assert {:ok, _} =
                   Ideation.cancel_timer(
                     ctx.facilitator,
                     ctx.project.id,
                     ctx.session.id,
                     ctx.session.revision,
                     timer.version
                   )

        :elapsed ->
          Repo.update_all(from(t in Timer, where: t.id == ^timer.id), set: [deadline_at: timer.started_at])
          assert {:ok, %{outcome: :completed}} = Ideation.expire_timer(timer.id, timer.version)
      end

      capsule = capture(ctx)
      maps = restore(ctx, capsule)
      assert {:ok, restored} = Ideation.get_timer(ctx.viewer, ctx.project.id, maps["sessions"][ctx.session.id])
      assert restored.status == state
      assert restored.completed_at
      assert restored.remaining_seconds == 0
      assert restored.expiry_outcome == if(state == :elapsed, do: :completed)
    end
  end

  test "version two capsules remain restorable without a timer or contribution gate", ctx do
    {:ok, data} = ctx |> capture() |> Capsule.open()

    legacy =
      data
      |> Map.put("version", 2)
      |> update_in(["rows"], &Map.delete(&1, "timers"))
      |> update_in(["rows", "sessions"], &Enum.map(&1, fn row -> Map.delete(row, "contributions_open") end))

    assert {:ok, capsule} = Capsule.seal(legacy)
    {_ctx, _timer} = start(ctx)
    maps = restore(ctx, capsule)
    id = maps["sessions"][ctx.session.id]
    assert {:ok, nil} = Ideation.get_timer(ctx.viewer, ctx.project.id, id)
    assert {:ok, session} = Ideation.get_session(ctx.facilitator, ctx.project.id, id)
    assert session.contributions_open
    assert restore(ctx, capsule) == maps
  end

  test "malformed authenticated timer inventories fail before touching the project", ctx do
    {ctx, _timer} = start(ctx)
    {:ok, data} = ctx |> capture() |> Capsule.open()

    mutations = [
      fn data -> put_in(data, ["rows", "timers", Access.at(0), "session_id"], -1) end,
      fn data -> put_in(data, ["rows", "timers", Access.at(0), "deadline_at"], "invalid") end,
      fn data -> put_in(data, ["rows", "timers", Access.at(0), "deadline_at"], nil) end,
      fn data -> put_in(data, ["rows", "timers", Access.at(0), "status"], "elapsed") end,
      fn data -> put_in(data, ["rows", "timers", Access.at(0), "remaining_seconds"], 0) end,
      fn data -> put_in(data, ["rows", "timers", Access.at(0), "duration_seconds"], 86_401) end,
      fn data -> put_in(data, ["rows", "timers", Access.at(0), "version"], 0) end,
      fn data -> put_in(data, ["rows", "timers", Access.at(0), "reveal_on_expiry"], "yes") end,
      fn data -> put_in(data, ["rows", "sessions", Access.at(0), "contributions_open"], nil) end,
      fn data -> update_in(data, ["rows", "timers"], fn [row] -> [row, %{row | "id" => row["id"] + 1}] end) end,
      fn data -> put_in(data, ["rows", "session_revisions", Access.at(1), "snapshot", "timer", "status"], "unknown") end
    ]

    for mutate <- mutations do
      {:ok, bytes} = data |> mutate.() |> Jason.encode!() |> Vault.encrypt()

      assert {:error, :invalid_ideation_recovery} =
               restore_result(ctx, %{"version" => 1, "ciphertext" => Base.encode64(bytes)})

      assert {:ok, unchanged} = Ideation.get_session(ctx.owner, ctx.project.id, ctx.session.id)
      assert unchanged.revision == ctx.session.revision
    end
  end

  defp start(ctx, opts \\ %{}) do
    {:ok, session} = Ideation.get_session(ctx.facilitator, ctx.project.id, ctx.session.id)

    {:ok, session} =
      Ideation.start_timer(ctx.facilitator, ctx.project.id, session.id, session.revision, Map.put(opts, :seconds, 300))

    {:ok, timer} = Ideation.get_timer(ctx.viewer, ctx.project.id, session.id)
    {%{ctx | session: session}, timer}
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
    assert {:ok, :ok} = Repo.transact(fn -> {:ok, Ideation.verify_recovery(ctx.project.id, capsule, maps)} end)
    maps
  end

  defp restore_result(ctx, capsule) do
    Repo.transact(fn ->
      Repo.one!(from p in "projects", where: p.id == ^ctx.project.id, select: p.id, lock: "FOR UPDATE")
      Ideation.restore_recovery(ctx.project.id, capsule)
    end)
  end
end
