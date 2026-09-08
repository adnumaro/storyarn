defmodule Storyarn.Ideation.TimerRuntimeTest do
  use ExUnit.Case, async: false

  alias Storyarn.Ideation.Sessions.Execution.TimerRuntime
  alias Storyarn.Workers.ExpireIdeationTimerWorker

  @now 1_800_000_000_000

  setup do
    store = start_supervised!({Agent, fn -> %{rows: [], clock: @now, monotonic: 0} end})
    %{store: store, owner: self()}
  end

  test "an empty runtime reads once, then schedules no idle polls", ctx do
    pid = runtime(ctx)
    assert_receive {:read, _}
    assert %{timers: timers, alarm: nil, read_alarm: nil} = settled(pid)
    assert timers == %{}
    refute_receive {:read, _}, 50
    refute_receive {:armed, _, _, _, _}, 50
    assert TimerRuntime.child_specs() == []
  end

  @tag capture_log: true
  test "a delivery that fails its first database access wakes an empty runtime into recovery", ctx do
    Agent.update(ctx.store, &Map.put(&1, :unavailable, false))

    read = fn ->
      send(ctx.owner, :schedule_read)
      data = Agent.get(ctx.store, & &1)
      if data.unavailable, do: raise("database unavailable"), else: data.rows
    end

    pid = runtime(ctx, read: read)
    assert_receive :schedule_read
    assert %{timers: timers, alarm: nil, read_alarm: nil} = settled(pid)
    assert timers == %{}

    # The original schedule notification was lost. The durable delivery is the
    # only remaining wakeup, and its first database access fails. This case has
    # no sandbox checkout, deliberately making Repo.get fail before any query.
    Agent.update(ctx.store, &%{&1 | rows: [timer(1, 1, 0)], unavailable: true})

    assert_raise DBConnection.OwnershipError, fn ->
      ExpireIdeationTimerWorker.perform(%Oban.Job{args: %{"timer_id" => 1, "version" => 1}})
    end

    assert_receive :schedule_read
    assert_receive {:armed, ^pid, retry, 1_000, _}
    refute_receive :schedule_read, 50

    # No further delivery or PubSub event is needed after the database recovers.
    Agent.update(ctx.store, &%{&1 | unavailable: false})
    advance(ctx, 1_000)
    send(pid, retry)
    assert_receive :schedule_read
    assert_receive {:armed, ^pid, deadline, 0, _}
    send(pid, deadline)
    assert_receive {:expired, 1, 1, _}
    assert_receive :schedule_read

    state = await_state(pid, &(map_size(&1.timers) == 0 and is_nil(&1.reader)))
    assert state.alarm == nil
    assert state.read_alarm == nil
    refute_receive :schedule_read, 50
  end

  test "startup discovers a deadline and expires it without a connected browser", ctx do
    put_rows(ctx, [timer(1, 1, 1_500)])
    pid = runtime(ctx)
    assert_receive {:armed, ^pid, message, 1_500, _}
    advance(ctx, 1_500)
    send(pid, message)
    assert_receive {:expired, 1, 1, _}
    state = await_state(pid, &(map_size(&1.timers) == 0 and is_nil(&1.reader)))
    assert state.alarm == nil
    assert state.expirations == %{}
  end

  test "reprogramming ignores an already delivered wakeup for the earlier version", ctx do
    put_rows(ctx, [timer(1, 1, 1_000)])
    pid = runtime(ctx)
    assert_receive {:armed, ^pid, old_message, 1_000, _}
    put_rows(ctx, [timer(1, 2, 5_000)])
    notify()
    assert_receive {:armed, ^pid, new_message, 5_000, _}
    advance(ctx, 1_000)
    send(pid, old_message)
    refute_receive {:expired, _, _, _}, 50
    advance(ctx, 4_000)
    send(pid, new_message)
    assert_receive {:expired, 1, 2, _}
  end

  test "pause or cancellation clears the local deadline without a periodic reread", ctx do
    put_rows(ctx, [timer(1, 1, 1_000)])
    pid = runtime(ctx)
    assert_receive {:armed, ^pid, old_message, 1_000, _}
    put_rows(ctx, [])
    notify()
    assert %{alarm: nil} = await_state(pid, &(map_size(&1.timers) == 0 and is_nil(&1.reader)))
    advance(ctx, 1_000)
    send(pid, old_message)
    refute_receive {:expired, _, _, _}, 50
  end

  test "clock corrections rearm cached deadlines and an early wake never expires a timer", ctx do
    put_rows(ctx, [timer(1, 1, 1_000)])
    pid = runtime(ctx)
    assert_receive {:armed, ^pid, original, 1_000, _}
    assert_receive {:read, _}
    Agent.update(ctx.store, &%{&1 | clock: @now - 1_000})
    send(pid, original)
    assert_receive {:armed, ^pid, _, 2_000, _}
    refute_receive {:expired, _, _, _}, 50
    refute_receive {:read, _}, 50

    monitor = :sys.get_state(pid).clock_monitor
    Agent.update(ctx.store, &%{&1 | clock: @now + 1_000})
    send(pid, {:CHANGE, monitor, :time_offset, :clock_service, 0})
    assert_receive {:armed, ^pid, due, 0, _}
    send(pid, due)
    assert_receive {:expired, 1, 1, _}
  end

  test "the supervisor restart reloads the durable deadline instead of resetting its duration", ctx do
    put_rows(ctx, [timer(1, 1, 2_000)])
    pid = runtime(ctx)
    assert_receive {:armed, ^pid, _, 2_000, _}
    advance(ctx, 1_500)
    monitor = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^pid, :killed}
    assert_receive {:armed, restarted, message, 500, _}
    refute restarted == pid
    advance(ctx, 500)
    send(restarted, message)
    assert_receive {:expired, 1, 1, _}
  end

  test "a blocked expiry does not prevent reprogramming and expiring another timer", ctx do
    put_rows(ctx, [timer(1, 1, 0), timer(2, 1, 10_000)])

    expire = fn
      1, version ->
        send(ctx.owner, {:blocked_expiry, self()})
        receive do: (:release -> complete(ctx, 1, version))

      id, version ->
        complete(ctx, id, version)
    end

    pid = runtime(ctx, expire: expire)
    assert_receive {:armed, ^pid, first, 0, _}
    send(pid, first)
    assert_receive {:blocked_expiry, blocked}
    put_rows(ctx, [timer(1, 1, 0), timer(2, 2, 2_000)])
    notify()
    assert_receive {:armed, ^pid, updated, 2_000, _}
    advance(ctx, 2_000)
    send(pid, updated)
    assert_receive {:expired, 2, 2, _}
    assert Process.alive?(blocked)
    send(blocked, :release)
    assert_receive {:expired, 1, 1, _}
  end

  test "events during a blocked read coalesce into one fresh read", ctx do
    read = fn ->
      send(ctx.owner, {:blocked_read, self()})
      receive do: ({:rows, rows} -> rows)
    end

    pid = runtime(ctx, read: read)
    assert_receive {:blocked_read, first}
    for _ <- 1..10, do: send(pid, :ideation_timers_changed)
    assert :sys.get_state(pid).refresh_again
    refute_receive {:blocked_read, _}, 50
    send(first, {:rows, []})
    assert_receive {:blocked_read, second}
    send(second, {:rows, []})
    assert %{reader: nil, refresh_again: false, alarm: nil} = settled(pid)
    refute_receive {:blocked_read, _}, 50
  end

  test "not-due receipts back off instead of repeatedly expiring the same version", ctx do
    put_rows(ctx, [timer(1, 1, 0)])

    expire = fn id, version ->
      send(ctx.owner, {:attempt, id, version})
      {:ok, %{outcome: :not_due}}
    end

    pid = runtime(ctx, expire: expire)
    assert_receive {:armed, ^pid, first, 0, _}
    send(pid, first)
    assert_receive {:attempt, 1, 1}

    for attempt <- 1..8 do
      state = await_state(pid, &(get_in(&1.retries, [{1, 1}, :failures]) == attempt and is_nil(&1.reader)))
      expected = min(1_000 * Integer.pow(2, attempt - 1), 60_000)
      now = Agent.get(ctx.store, & &1.monotonic)
      assert state.retries[{1, 1}].at - now == expected
      refute_receive {:attempt, _, _}, 10

      if attempt < 8 do
        advance(ctx, expected)
        {_ref, token} = state.alarm
        send(pid, {:timer_deadline, token})
        assert_receive {:attempt, 1, 1}
      end
    end
  end

  @tag capture_log: true
  test "failed schedule reads retry with backoff and return to idle after recovery", ctx do
    Agent.update(ctx.store, &Map.put(&1, :fail, true))

    read = fn ->
      send(ctx.owner, :read_attempt)
      if Agent.get(ctx.store, & &1.fail), do: raise("temporarily unavailable"), else: []
    end

    pid = runtime(ctx, read: read)
    assert_receive :read_attempt
    assert_receive {:armed, ^pid, first, 1_000, _}
    send(pid, first)
    assert_receive :read_attempt
    assert_receive {:armed, ^pid, _, 2_000, _}
    Agent.update(ctx.store, &%{&1 | fail: false})
    notify()
    assert_receive :read_attempt
    assert %{read_failures: 0, read_alarm: nil, alarm: nil} = settled(pid)
    refute_receive :read_attempt, 50
  end

  defp runtime(ctx, opts \\ []) do
    defaults = [
      name: nil,
      read: fn ->
        send(ctx.owner, {:read, self()})
        Agent.get(ctx.store, & &1.rows)
      end,
      expire: fn id, version -> complete(ctx, id, version) end,
      clock: fn -> Agent.get(ctx.store, & &1.clock) end,
      monotonic: fn -> Agent.get(ctx.store, & &1.monotonic) end,
      schedule: fn message, delay ->
        ref = make_ref()
        send(ctx.owner, {:armed, self(), message, delay, ref})
        ref
      end,
      cancel: fn _ref -> false end
    ]

    start_supervised!({TimerRuntime, Keyword.merge(defaults, opts)})
  end

  defp complete(ctx, id, version) do
    Agent.update(ctx.store, fn data ->
      %{data | rows: Enum.reject(data.rows, &(&1.id == id and &1.version == version))}
    end)

    send(ctx.owner, {:expired, id, version, self()})
    {:ok, %{outcome: :completed}}
  end

  defp put_rows(ctx, rows), do: Agent.update(ctx.store, &%{&1 | rows: rows})

  defp advance(ctx, amount),
    do: Agent.update(ctx.store, &%{&1 | clock: &1.clock + amount, monotonic: &1.monotonic + amount})

  defp timer(id, version, after_ms),
    do: %{id: id, version: version, deadline_at: DateTime.from_unix!(@now + after_ms, :millisecond)}

  defp notify, do: Phoenix.PubSub.broadcast(Storyarn.PubSub, "ideation:timers", :ideation_timers_changed)
  defp settled(pid), do: await_state(pid, &is_nil(&1.reader))

  defp await_state(pid, condition, tries \\ 100) do
    state = :sys.get_state(pid)

    if condition.(state) or tries == 0 do
      assert condition.(state)
      state
    else
      receive do
      after
        1 -> await_state(pid, condition, tries - 1)
      end
    end
  end
end
