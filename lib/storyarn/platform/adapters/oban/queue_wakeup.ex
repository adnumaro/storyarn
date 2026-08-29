defmodule Storyarn.Platform.Adapters.Oban.QueueWakeup do
  @moduledoc """
  Best-effort, bounded wakeup for an Oban queue after application startup.

  This is a technical deployment adapter. It does not create, inspect, or
  interpret jobs. Repeating the signal for a bounded window covers a rolling
  cutover where an older node may persist a job after the replacement node's
  first queue signal.

  The adapter publishes an `:insert` notification rather than resuming the
  queue, so an operator-paused queue remains paused.
  """

  use GenServer

  require Logger

  @type notifier :: (String.t() -> :ok | {:error, term()})

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def child_spec(opts) do
    queue = Keyword.fetch!(opts, :queue)

    %{
      id: {__MODULE__, queue},
      start: {__MODULE__, :start_link, [opts]},
      restart: :temporary
    }
  end

  @impl GenServer
  def init(opts) do
    oban_name = Keyword.get(opts, :oban_name, Oban)
    queue = opts |> Keyword.fetch!(:queue) |> normalize_queue!()
    interval = Keyword.fetch!(opts, :interval)
    repetitions = Keyword.fetch!(opts, :repetitions)

    if !(is_integer(interval) and interval > 0) do
      raise ArgumentError, ":interval must be a positive integer"
    end

    if !(is_integer(repetitions) and repetitions >= 0) do
      raise ArgumentError, ":repetitions must be a non-negative integer"
    end

    notifier =
      Keyword.get(opts, :notifier, fn target_queue ->
        Oban.Notifier.notify(oban_name, :insert, %{queue: target_queue})
      end)

    send(self(), :wake)

    {:ok,
     %{
       interval: interval,
       notifier: notifier,
       queue: queue,
       remaining: repetitions
     }}
  end

  @impl GenServer
  def handle_info(:wake, %{remaining: 0} = state) do
    safely_notify(state)
    {:stop, :normal, state}
  end

  def handle_info(:wake, state) do
    safely_notify(state)
    Process.send_after(self(), :wake, state.interval)

    {:noreply, %{state | remaining: state.remaining - 1}}
  end

  defp safely_notify(%{notifier: notifier, queue: queue}) do
    case notifier.(queue) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning("Oban queue wakeup failed queue=#{queue} reason=#{inspect(reason)}")

      invalid ->
        Logger.warning("Oban queue wakeup returned queue=#{queue} result=#{inspect(invalid)}")
    end
  rescue
    exception ->
      Logger.warning("Oban queue wakeup raised queue=#{queue} reason=#{Exception.message(exception)}")
  catch
    kind, reason ->
      Logger.warning("Oban queue wakeup failed queue=#{queue} kind=#{kind} reason=#{inspect(reason)}")
  end

  defp normalize_queue!(queue) when is_atom(queue), do: Atom.to_string(queue)
  defp normalize_queue!(queue) when is_binary(queue) and byte_size(queue) > 0, do: queue

  defp normalize_queue!(queue) do
    raise ArgumentError, ":queue must be a non-empty atom or string, got: #{inspect(queue)}"
  end
end
