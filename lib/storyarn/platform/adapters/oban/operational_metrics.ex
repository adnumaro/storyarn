defmodule Storyarn.Platform.Adapters.Oban.OperationalMetrics do
  @moduledoc """
  Emits low-cardinality operational measurements for recovery queues.

  The query selects only queue state and timestamps. Job arguments, worker
  payloads, entity identifiers, storage keys, and error messages never leave
  PostgreSQL through this adapter.
  """

  import Ecto.Query

  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Repo

  require Logger

  @queues ~w(
    imports
    imports_maintenance
    snapshot_archives
    snapshot_restores
    snapshot_imports
    snapshots_maintenance
    storage_inventory
    storage_cleanup
  )a
  @queue_names Enum.map(@queues, &Atom.to_string/1)
  @waiting_states ~w(available retryable scheduled)
  @active_states @waiting_states ++ ["executing"]

  @type aggregate_row :: {
          queue :: String.t(),
          state :: String.t(),
          count :: non_neg_integer(),
          due_count :: non_neg_integer(),
          oldest_due_at :: DateTime.t() | nil,
          oldest_inserted_at :: DateTime.t() | nil,
          oldest_attempted_at :: DateTime.t() | nil,
          max_recorded_error_count :: non_neg_integer()
        }

  @doc false
  @spec child_specs(keyword()) :: [Supervisor.child_spec()]
  def child_specs(config) when is_list(config) do
    if Keyword.fetch!(config, :enabled) do
      interval = Keyword.fetch!(config, :oban_poll_interval)

      [
        Supervisor.child_spec(
          {:telemetry_poller, measurements: [{__MODULE__, :emit, []}], period: interval, init_delay: 0},
          id: __MODULE__
        )
      ]
    else
      []
    end
  end

  @spec emit() :: :ok
  def emit do
    now = TimeHelpers.now()

    emit_with(
      fn -> {aggregate_rows(now), configured_capacities()} end,
      now
    )
  end

  @doc false
  @spec emit_with((-> {[aggregate_row()], %{required(atom()) => non_neg_integer()}}), DateTime.t()) :: :ok
  def emit_with(snapshot, %DateTime{} = now) when is_function(snapshot, 0) do
    {rows, capacities} = snapshot.()

    Enum.each(@queues, fn queue ->
      configured_capacity = Map.fetch!(capacities, queue)

      measurements =
        rows
        |> measurements_for_queue(queue, configured_capacity, now)
        |> Map.merge(runtime_queue_measurements(configured_capacity, Oban.check_queue(queue: queue)))

      :telemetry.execute(
        [:storyarn, :oban, :queue, :snapshot],
        measurements,
        %{queue: Atom.to_string(queue)}
      )
    end)

    emit_poll_stop(%{success: 1, failure_count: 0, last_success_unix_seconds: DateTime.to_unix(now)}, :none)
    :ok
  rescue
    exception ->
      Logger.error(
        "Oban operational metrics poll failed failure=exception " <>
          "exception_module=#{inspect(exception.__struct__)}"
      )

      emit_poll_stop(%{success: 0, failure_count: 1}, :exception)
      :ok
  catch
    kind, _reason when kind in [:exit, :throw] ->
      Logger.error("Oban operational metrics poll failed failure=#{kind}")
      emit_poll_stop(%{success: 0, failure_count: 1}, kind)
      :ok
  end

  @doc false
  @spec queue_names() :: [String.t()]
  def queue_names, do: @queue_names

  @doc false
  @spec measurements_for_queue([aggregate_row()], atom(), non_neg_integer(), DateTime.t()) :: map()
  def measurements_for_queue(rows, queue, capacity, now)
      when queue in @queues and is_integer(capacity) and capacity >= 0 do
    queue_name = Atom.to_string(queue)
    queue_rows = Enum.filter(rows, &(elem(&1, 0) == queue_name))

    %{
      backlog_count: count_states(queue_rows, @waiting_states),
      due_count: sum_field(queue_rows, 3),
      executing_count: count_states(queue_rows, ["executing"]),
      retryable_count: count_states(queue_rows, ["retryable"]),
      max_recorded_error_count: max_recorded_error_count(queue_rows),
      oldest_due_age_seconds: oldest_due_age_seconds(queue_rows, now),
      oldest_waiting_age_seconds: oldest_waiting_age_seconds(queue_rows, now),
      oldest_executing_age_seconds: oldest_executing_age_seconds(queue_rows, now),
      configured_capacity: capacity
    }
  end

  @doc false
  @spec runtime_queue_measurements(non_neg_integer(), nil | map()) :: map()
  def runtime_queue_measurements(configured_capacity, %{limit: limit, paused: paused})
      when is_integer(configured_capacity) and configured_capacity >= 0 and is_integer(limit) and limit >= 0 and
             is_boolean(paused) do
    %{
      effective_capacity: if(paused, do: 0, else: limit),
      paused: boolean_measurement(paused),
      runtime_available: 1
    }
  end

  def runtime_queue_measurements(configured_capacity, nil)
      when is_integer(configured_capacity) and configured_capacity >= 0 do
    %{effective_capacity: 0, paused: 0, runtime_available: 0}
  end

  defp aggregate_rows(now) do
    Repo.all(
      from(job in Oban.Job,
        where: job.queue in ^@queue_names and job.state in ^@active_states,
        group_by: [job.queue, job.state],
        select:
          {job.queue, job.state, count(job.id),
           filter(count(job.id), job.state != "executing" and job.scheduled_at <= ^now),
           filter(min(job.scheduled_at), job.state != "executing" and job.scheduled_at <= ^now), min(job.inserted_at),
           min(job.attempted_at), max(fragment("COALESCE(cardinality(?), 0)", job.errors))}
      )
    )
  end

  defp configured_capacities do
    configured_queues = :storyarn |> Application.fetch_env!(Oban) |> Keyword.fetch!(:queues)

    Map.new(@queues, fn queue ->
      capacity = Keyword.fetch!(configured_queues, queue)

      if is_integer(capacity) and capacity > 0 do
        {queue, capacity}
      else
        raise "Oban recovery queue #{queue} must have a positive integer capacity"
      end
    end)
  end

  defp count_states(rows, states) do
    rows
    |> Enum.filter(&(elem(&1, 1) in states))
    |> Enum.reduce(0, &(elem(&1, 2) + &2))
  end

  defp sum_field(rows, index), do: Enum.reduce(rows, 0, &(elem(&1, index) + &2))

  defp boolean_measurement(true), do: 1
  defp boolean_measurement(false), do: 0

  defp max_recorded_error_count([]), do: 0
  defp max_recorded_error_count(rows), do: rows |> Enum.map(&elem(&1, 7)) |> Enum.max()

  defp oldest_due_age_seconds(rows, now) do
    rows
    |> Enum.map(&elem(&1, 4))
    |> oldest_age_seconds(now)
  end

  defp oldest_waiting_age_seconds(rows, now) do
    rows
    |> Enum.filter(&(elem(&1, 1) in @waiting_states))
    |> Enum.map(&elem(&1, 5))
    |> oldest_age_seconds(now)
  end

  defp oldest_executing_age_seconds(rows, now) do
    rows
    |> Enum.filter(&(elem(&1, 1) == "executing"))
    |> Enum.map(&elem(&1, 6))
    |> oldest_age_seconds(now)
  end

  defp oldest_age_seconds(timestamps, now) do
    timestamps
    |> Enum.reject(&is_nil/1)
    |> Enum.min_by(&DateTime.to_unix(&1, :microsecond), fn -> nil end)
    |> case do
      nil -> 0
      oldest -> max(DateTime.diff(now, oldest, :second), 0)
    end
  end

  defp emit_poll_stop(measurements, failure) do
    :telemetry.execute(
      [:storyarn, :oban, :queue, :poll, :stop],
      measurements,
      %{failure: failure}
    )
  end
end
