defmodule Storyarn.Platform.Adapters.Oban.OperationalMetricsTest do
  use Storyarn.DataCase, async: true

  import ExUnit.CaptureLog

  alias Storyarn.Application, as: StoryarnApplication
  alias Storyarn.Platform.Adapters.Oban.OperationalMetrics
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Workers.ImportProjectWorker

  @poll_event [:storyarn, :oban, :queue, :poll, :stop]
  @queue_snapshot_event [:storyarn, :oban, :queue, :snapshot]

  test "aggregates only bounded operational values for one recovery queue" do
    now = ~U[2026-09-02 20:00:00.000000Z]

    rows = [
      {"imports", "available", 2, 2, DateTime.add(now, -90, :second), DateTime.add(now, -90, :second), nil, 0},
      {"imports", "retryable", 3, 1, DateTime.add(now, -30, :second), DateTime.add(now, -30, :second), nil, 4},
      {"imports", "scheduled", 1, 0, nil, DateTime.add(now, -7_200, :second), nil, 0},
      {"imports", "executing", 1, 0, nil, DateTime.add(now, -300, :second), DateTime.add(now, -5, :second), 2},
      {"snapshot_archives", "available", 99, 99, DateTime.add(now, -900, :second), DateTime.add(now, -900, :second), nil,
       8}
    ]

    assert OperationalMetrics.measurements_for_queue(rows, :imports, 2, now) == %{
             backlog_count: 6,
             configured_capacity: 2,
             due_count: 3,
             executing_count: 1,
             max_recorded_error_count: 4,
             oldest_due_age_seconds: 90,
             oldest_executing_age_seconds: 5,
             oldest_waiting_age_seconds: 7_200,
             retryable_count: 3
           }
  end

  test "emits zeroes for an empty queue snapshot" do
    now = ~U[2026-09-02 20:00:00.000000Z]

    assert OperationalMetrics.measurements_for_queue([], :snapshot_restores, 1, now) == %{
             backlog_count: 0,
             configured_capacity: 1,
             due_count: 0,
             executing_count: 0,
             max_recorded_error_count: 0,
             oldest_due_age_seconds: 0,
             oldest_executing_age_seconds: 0,
             oldest_waiting_age_seconds: 0,
             retryable_count: 0
           }
  end

  test "the monitored queue list is fixed and contains no identifiers" do
    assert OperationalMetrics.queue_names() == [
             "imports",
             "imports_maintenance",
             "snapshot_archives",
             "snapshot_restores",
             "snapshot_imports",
             "snapshots_maintenance",
             "storage_inventory",
             "storage_cleanup"
           ]
  end

  test "poller is opt-in and has an immediate first measurement" do
    interval = to_timeout(minute: 15)

    assert OperationalMetrics.child_specs(
             enabled: false,
             oban_poll_interval: interval
           ) == []

    assert [%{id: OperationalMetrics, start: {:telemetry_poller, :start_link, [options]}}] =
             OperationalMetrics.child_specs(
               enabled: true,
               oban_poll_interval: interval
             )

    assert Keyword.fetch!(options, :period) == interval
    assert Keyword.fetch!(options, :init_delay) == 0
    assert Keyword.fetch!(options, :measurements) == [{OperationalMetrics, :emit, []}]
  end

  test "application starts the poller only after Repo and Oban" do
    operational_metrics_config =
      :storyarn
      |> Application.fetch_env!(:operational_metrics)
      |> Keyword.put(:enabled, true)

    children = StoryarnApplication.children(operational_metrics_config)

    repo_index = Enum.find_index(children, &(&1 == Storyarn.Repo))
    reporter_index = Enum.find_index(children, &match?(%{id: :storyarn_operational_metrics}, &1))

    listener_index =
      Enum.find_index(
        children,
        &match?(%{id: Storyarn.Platform.Adapters.Telemetry.PrometheusEndpoint}, &1)
      )

    oban_index = Enum.find_index(children, &match?({Oban, _opts}, &1))
    poller_index = Enum.find_index(children, &match?(%{id: OperationalMetrics}, &1))

    assert is_integer(repo_index)
    assert is_integer(reporter_index)
    assert is_integer(listener_index)
    assert is_integer(oban_index)
    assert is_integer(poller_index)
    assert reporter_index < listener_index
    assert listener_index < repo_index
    assert reporter_index < repo_index
    assert repo_index < oban_index
    assert oban_index < poller_index
  end

  test "runtime capacity distinguishes a paused queue from missing runtime state" do
    assert OperationalMetrics.runtime_queue_measurements(2, %{limit: 2, paused: false}) == %{
             effective_capacity: 2,
             paused: 0,
             runtime_available: 1
           }

    assert OperationalMetrics.runtime_queue_measurements(2, %{limit: 2, paused: true}) == %{
             effective_capacity: 0,
             paused: 1,
             runtime_available: 1
           }

    assert OperationalMetrics.runtime_queue_measurements(2, nil) == %{
             effective_capacity: 0,
             paused: 0,
             runtime_available: 0
           }
  end

  test "a polling exception is bounded, observable, and never disables future polls" do
    private_message = "postgres://private-user:secret@private-host/database"
    handler_id = "oban-operational-poll-failure-#{System.unique_integer([:positive])}"
    test_pid = self()

    :ok =
      :telemetry.attach(
        handler_id,
        @poll_event,
        fn event, measurements, metadata, pid -> send(pid, {event, measurements, metadata}) end,
        test_pid
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    log =
      capture_log(fn ->
        assert :ok =
                 OperationalMetrics.emit_with(
                   fn -> raise private_message end,
                   ~U[2026-09-02 20:00:00Z]
                 )
      end)

    assert_receive {@poll_event, %{success: 0, failure_count: 1}, %{failure: :exception}}
    assert log =~ "failure=exception"
    assert log =~ "exception_module=RuntimeError"
    refute log =~ private_message
    refute log =~ "private-user"
    refute log =~ "private-host"
  end

  test "the production aggregate query emits a successful poll" do
    handler_id = "oban-operational-poll-query-#{System.unique_integer([:positive])}"
    test_pid = self()

    :ok =
      :telemetry.attach(
        handler_id,
        @poll_event,
        fn event, measurements, metadata, pid -> send(pid, {event, measurements, metadata}) end,
        test_pid
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    assert :ok = OperationalMetrics.emit()

    assert_receive {
      @poll_event,
      %{success: 1, failure_count: 0, last_success_unix_seconds: timestamp},
      %{failure: :none}
    }

    assert is_integer(timestamp)
  end

  test "the production SQL separates future scheduled, overdue retryable, and executing jobs" do
    now = %{TimeHelpers.now() | microsecond: {0, 6}}

    insert_import_job!(
      state: "scheduled",
      inserted_at: DateTime.add(now, -7_200, :second),
      scheduled_at: DateTime.add(now, 3_600, :second),
      attempted_at: nil,
      attempt: 0,
      errors: []
    )

    insert_import_job!(
      state: "retryable",
      inserted_at: DateTime.add(now, -600, :second),
      scheduled_at: DateTime.add(now, -90, :second),
      attempted_at: DateTime.add(now, -120, :second),
      attempt: 4,
      max_attempts: 5,
      errors: Enum.map(1..4, &%{"attempt" => &1})
    )

    insert_import_job!(
      state: "executing",
      inserted_at: DateTime.add(now, -300, :second),
      scheduled_at: DateTime.add(now, -300, :second),
      attempted_at: DateTime.add(now, -5, :second),
      attempt: 3,
      max_attempts: 5,
      errors: Enum.map(1..2, &%{"attempt" => &1})
    )

    handler_id = "oban-operational-production-aggregate-#{System.unique_integer([:positive])}"
    test_pid = self()

    :ok =
      :telemetry.attach(
        handler_id,
        @queue_snapshot_event,
        fn event, measurements, metadata, pid ->
          if metadata.queue == "imports", do: send(pid, {event, measurements, metadata})
        end,
        test_pid
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    assert :ok = OperationalMetrics.emit()

    assert_receive {
      @queue_snapshot_event,
      %{
        backlog_count: 2,
        due_count: 1,
        executing_count: 1,
        retryable_count: 1,
        max_recorded_error_count: 4,
        oldest_due_age_seconds: oldest_due_age_seconds,
        oldest_waiting_age_seconds: oldest_waiting_age_seconds,
        oldest_executing_age_seconds: oldest_executing_age_seconds
      },
      %{queue: "imports"}
    }

    assert oldest_due_age_seconds in 90..92
    assert oldest_waiting_age_seconds in 7_200..7_202
    assert oldest_executing_age_seconds in 5..7
  end

  defp insert_import_job!(changes) do
    %{"attempt_id" => Ecto.UUID.generate()}
    |> ImportProjectWorker.new()
    |> Oban.insert!()
    |> Ecto.Changeset.change(changes)
    |> Repo.update!()
  end
end
