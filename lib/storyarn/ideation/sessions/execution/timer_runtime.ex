defmodule Storyarn.Ideation.Sessions.Execution.TimerRuntime do
  @moduledoc """
  Wakes running timers at their persisted deadlines without polling an idle database.

  Reads and expirations run outside the server so a slow transaction cannot block
  newer schedule notifications. Every expiry still checks its persisted version.
  Transactional Oban deliveries cover a lost post-commit notification; their
  exceptional recovery latency follows Oban's existing staging cadence.
  """
  use GenServer

  alias Storyarn.Ideation.Sessions.Commands.ExpireTimer
  alias Storyarn.Ideation.Sessions.Queries.Timers

  require Logger

  @topic "ideation:timers"
  @max_expirations 4
  @retry_min 1_000
  @retry_max 60_000

  def child_specs do
    if Application.get_env(:storyarn, :ideation_timer_runtime, true), do: [__MODULE__], else: []
  end

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, if(name, do: [name: name], else: []))
  end

  @impl GenServer
  def init(opts) do
    pubsub = Keyword.get(opts, :pubsub, Storyarn.PubSub)
    :ok = Phoenix.PubSub.subscribe(pubsub, @topic)

    state = %{
      read: Keyword.get(opts, :read, &Timers.scheduled/0),
      expire: Keyword.get(opts, :expire, &ExpireTimer.run/2),
      clock: Keyword.get(opts, :clock, fn -> System.system_time(:millisecond) end),
      monotonic: Keyword.get(opts, :monotonic, fn -> System.monotonic_time(:millisecond) end),
      schedule: Keyword.get(opts, :schedule, fn message, delay -> Process.send_after(self(), message, delay) end),
      cancel: Keyword.get(opts, :cancel, &Process.cancel_timer/1),
      supervisor: Keyword.get(opts, :task_supervisor, Storyarn.TaskSupervisor),
      clock_monitor: :erlang.monitor(:time_offset, :clock_service),
      timers: %{},
      reader: nil,
      refresh_again: false,
      read_failures: 0,
      read_alarm: nil,
      expirations: %{},
      retries: %{},
      alarm: nil
    }

    {:ok, state, {:continue, :read}}
  end

  @impl GenServer
  def handle_continue(:read, state), do: {:noreply, request_read(state)}

  @impl GenServer
  def handle_info(:ideation_timers_changed, state), do: {:noreply, request_read(state)}

  def handle_info({:CHANGE, monitor, :time_offset, :clock_service, _offset}, %{clock_monitor: monitor} = state),
    do: {:noreply, arm_deadline(state)}

  def handle_info({:timer_deadline, token}, %{alarm: {_ref, token}} = state) do
    state = %{state | alarm: nil}
    slots = @max_expirations - map_size(state.expirations)

    state =
      state
      |> waiting_timers()
      |> Enum.filter(&(delay(state, &1) == 0))
      |> Enum.take(slots)
      |> Enum.reduce(state, &start_expiration/2)
      |> arm_deadline()

    {:noreply, state}
  end

  def handle_info({:timer_read_retry, token}, %{read_alarm: {_ref, token}} = state),
    do: {:noreply, request_read(%{state | read_alarm: nil})}

  def handle_info({ref, result}, %{reader: %{ref: ref}} = state) do
    Process.demonitor(ref, [:flush])
    {:noreply, read_completed(%{state | reader: nil}, result)}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, %{reader: %{ref: ref}} = state),
    do: {:noreply, read_completed(%{state | reader: nil}, {:error, {:task_exit, reason}})}

  def handle_info({ref, result}, state) when is_reference(ref) do
    case Map.pop(state.expirations, ref) do
      {nil, _} ->
        {:noreply, state}

      {entry, remaining} ->
        Process.demonitor(ref, [:flush])
        {:noreply, expiration_completed(%{state | expirations: remaining}, entry.timer, result)}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    case Map.pop(state.expirations, ref) do
      {nil, _} ->
        {:noreply, state}

      {entry, remaining} ->
        {:noreply, expiration_completed(%{state | expirations: remaining}, entry.timer, {:error, {:task_exit, reason}})}
    end
  end

  # A cancelled alarm can already be in the mailbox. Its token no longer owns
  # the schedule, so it must not read the database or expire an older version.
  def handle_info(_message, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_reason, state) do
    cancel_alarm(state, state.alarm)
    cancel_alarm(state, state.read_alarm)
    if state.reader, do: Task.shutdown(state.reader, :brutal_kill)
    Enum.each(state.expirations, fn {_ref, entry} -> Task.shutdown(entry.task, :brutal_kill) end)
    :ok
  end

  defp request_read(%{reader: reader} = state) when not is_nil(reader), do: %{state | refresh_again: true}

  defp request_read(state) do
    cancel_alarm(state, state.read_alarm)
    task = Task.Supervisor.async_nolink(state.supervisor, fn -> safely(state.read) end)
    %{state | reader: task, refresh_again: false, read_alarm: nil}
  end

  defp read_completed(state, {:ok, rows}) when is_list(rows) do
    timers = Map.new(rows, &{key(&1), &1})
    retries = Map.take(state.retries, Map.keys(timers))
    state = arm_deadline(%{state | timers: timers, retries: retries, read_failures: 0})
    if state.refresh_again, do: request_read(state), else: state
  end

  defp read_completed(state, _failure) do
    Logger.warning("Ideation timer schedule read failed; retrying with backoff")
    failures = state.read_failures + 1
    token = make_ref()
    alarm = {state.schedule.({:timer_read_retry, token}, backoff(failures)), token}
    %{state | read_failures: failures, read_alarm: alarm, refresh_again: false}
  end

  defp start_expiration(timer, state) do
    task =
      Task.Supervisor.async_nolink(state.supervisor, fn -> safely(fn -> state.expire.(timer.id, timer.version) end) end)

    %{state | expirations: Map.put(state.expirations, task.ref, %{task: task, timer: timer})}
  end

  defp expiration_completed(state, timer, result) do
    case result do
      {:ok, {:ok, %{outcome: _}}} -> :ok
      _ -> Logger.warning("Ideation timer expiry failed; retrying with backoff")
    end

    # Even an early/stale receipt must not produce an immediate retry loop if
    # the next read still returns the same version. Successful transitions drop
    # this entry when the fresh schedule no longer contains that version.
    failures = get_in(state.retries, [key(timer), :failures]) || 0
    retry = %{failures: failures + 1, at: state.monotonic.() + backoff(failures + 1)}

    %{state | retries: Map.put(state.retries, key(timer), retry)}
    |> request_read()
    |> arm_deadline()
  end

  defp arm_deadline(state) do
    cancel_alarm(state, state.alarm)
    state = %{state | alarm: nil}

    if map_size(state.expirations) < @max_expirations do
      case waiting_timers(state) do
        [] ->
          state

        timers ->
          delay = timers |> Enum.map(&delay(state, &1)) |> Enum.min()
          token = make_ref()
          %{state | alarm: {state.schedule.({:timer_deadline, token}, delay), token}}
      end
    else
      state
    end
  end

  defp waiting_timers(state) do
    running = MapSet.new(state.expirations, fn {_ref, entry} -> key(entry.timer) end)

    state.timers
    |> Map.values()
    |> Enum.reject(&MapSet.member?(running, key(&1)))
    |> Enum.sort_by(&DateTime.to_unix(&1.deadline_at, :microsecond))
  end

  defp delay(state, timer) do
    retry = get_in(state.retries, [key(timer), :at])
    deadline_delay = DateTime.to_unix(timer.deadline_at, :millisecond) - state.clock.()
    retry_delay = if retry, do: retry - state.monotonic.(), else: 0
    max(max(deadline_delay, retry_delay), 0)
  end

  defp cancel_alarm(_state, nil), do: :ok
  defp cancel_alarm(state, {ref, _token}), do: state.cancel.(ref)
  defp key(timer), do: {timer.id, timer.version}
  defp backoff(failures), do: min(@retry_min * Integer.pow(2, min(failures - 1, 6)), @retry_max)

  defp safely(operation) do
    {:ok, operation.()}
  rescue
    exception -> {:error, {:exception, exception.__struct__}}
  catch
    kind, reason -> {:error, {kind, reason}}
  end
end
