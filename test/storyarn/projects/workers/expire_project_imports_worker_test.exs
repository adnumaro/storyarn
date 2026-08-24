defmodule Storyarn.Workers.ExpireProjectImportsWorkerTest do
  use ExUnit.Case, async: true

  alias Storyarn.Projects.Workers.ExpireProjectImportsWorker
  alias Storyarn.Projects.Workers.ImportProjectWorker
  alias StoryarnWeb.Telemetry

  @event [:storyarn, :import, :expiration, :stop]

  setup do
    handler_id = "project-import-expiration-#{System.unique_integer([:positive])}"
    test_pid = self()

    :ok =
      :telemetry.attach(
        handler_id,
        @event,
        fn event, measurements, metadata, _config ->
          send(test_pid, {:expiration_stop, event, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
    :ok
  end

  describe "queue isolation" do
    test "the sweep does not share a queue with the imports it expires" do
      import_queue = Keyword.fetch!(ImportProjectWorker.__opts__(), :queue)

      assert import_queue == :imports
      assert Keyword.fetch!(ExpireProjectImportsWorker.__opts__(), :queue) == :imports_maintenance

      refute Keyword.fetch!(ExpireProjectImportsWorker.__opts__(), :queue) == import_queue
    end

    test "the maintenance queue is configured with serial concurrency" do
      queues = :storyarn |> Application.fetch_env!(Oban) |> Keyword.fetch!(:queues)

      assert Keyword.fetch!(queues, :imports_maintenance) == 1
      assert Keyword.fetch!(queues, :imports) == 2
    end
  end

  test "reports expired plans, failures, and duration without identifying metadata" do
    assert :ok = ExpireProjectImportsWorker.perform_expiration(fn -> {:ok, 7} end)

    assert_receive {:expiration_stop, @event, measurements, metadata}
    assert measurements.expired_count == 7
    assert measurements.failure_count == 0
    assert measurements.continuation_count == 0
    assert is_integer(measurements.duration)
    assert measurements.duration >= 0
    assert metadata == %{status: :ok, error_code: "none"}
  end

  test "schedules a bounded continuation when the expiration batch reports more work" do
    test_pid = self()

    assert :ok =
             ExpireProjectImportsWorker.perform_expiration(
               fn ->
                 {:ok, %{expired_count: 100, failure_count: 0, more?: true}}
               end,
               fn ->
                 send(test_pid, :scheduled_followup)
                 :ok
               end
             )

    assert_receive :scheduled_followup
    assert_receive {:expiration_stop, @event, measurements, metadata}
    assert measurements.expired_count == 100
    assert measurements.failure_count == 0
    assert measurements.continuation_count == 1
    assert metadata == %{status: :ok, error_code: "none"}
  end

  test "fails closed with a bounded code when continuation scheduling fails" do
    private_reason = "private project and user identifiers"

    assert {:error, :project_import_expiration_followup_failed} =
             ExpireProjectImportsWorker.perform_expiration(
               fn ->
                 {:ok, %{expired_count: 100, failure_count: 0, more?: true}}
               end,
               fn -> {:error, private_reason} end
             )

    assert_receive {:expiration_stop, @event, measurements, metadata}
    assert measurements.expired_count == 100
    assert measurements.failure_count == 1
    assert measurements.continuation_count == 0
    assert metadata == %{status: :error, error_code: "followup_schedule_failed"}
    refute inspect({measurements, metadata}) =~ private_reason
  end

  test "reports a bounded failure code and asks Oban to retry a failed batch" do
    assert {:error, :project_import_expiration_failed} =
             ExpireProjectImportsWorker.perform_expiration(fn ->
               {:error, {:storage_unavailable, "private storage key"}}
             end)

    assert_receive {:expiration_stop, @event, measurements, metadata}
    assert measurements.expired_count == 0
    assert measurements.failure_count == 1
    assert measurements.continuation_count == 0
    assert metadata == %{status: :error, error_code: "storage_unavailable"}
    refute inspect({measurements, metadata}) =~ "private storage key"
  end

  test "converts exceptions into a retryable bounded result without exposing their message" do
    private_message = "Jane Doe imported private-dialogue.yarn"

    assert {:error, :project_import_expiration_failed} =
             ExpireProjectImportsWorker.perform_expiration(fn ->
               raise private_message
             end)

    assert_receive {:expiration_stop, @event, measurements, metadata}
    assert measurements.expired_count == 0
    assert measurements.failure_count == 1
    assert measurements.continuation_count == 0
    assert metadata == %{status: :exception, error_code: "exception"}
    refute inspect({measurements, metadata}) =~ private_message
  end

  test "reports partial row failures and asks Oban to retry the incomplete batch" do
    assert {:error, :project_import_expiration_incomplete} =
             ExpireProjectImportsWorker.perform_expiration(fn -> {:ok, 4, 2} end)

    assert_receive {:expiration_stop, @event, measurements, metadata}
    assert measurements.expired_count == 4
    assert measurements.failure_count == 2
    assert measurements.continuation_count == 0
    assert metadata == %{status: :partial, error_code: "row_failure"}
  end

  test "backs failed sweeps off until deferred rows are eligible again" do
    assert ExpireProjectImportsWorker.backoff(%Oban.Job{attempt: 1}) == 300
    assert ExpireProjectImportsWorker.backoff(%Oban.Job{attempt: 2}) == 600
    assert ExpireProjectImportsWorker.backoff(%Oban.Job{attempt: 10}) == 3_600
  end

  test "registers the four expiration metrics with privacy-safe tags" do
    metrics =
      Enum.filter(Telemetry.metrics(), fn metric ->
        Enum.take(metric.name, 4) == [:storyarn, :import, :expiration, :stop]
      end)

    assert metrics |> Enum.map(&List.last(&1.name)) |> Enum.sort() ==
             [:continuation_count, :duration, :expired_count, :failure_count]

    assert Enum.all?(metrics, fn metric -> metric.tags == [:status, :error_code] end)
  end
end
