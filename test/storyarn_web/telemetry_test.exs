defmodule StoryarnWeb.TelemetryTest do
  use ExUnit.Case, async: true

  alias StoryarnWeb.Telemetry

  # Fully qualified to avoid alias conflict with StoryarnWeb.Telemetry
  @summary_mod :"Elixir.Telemetry.Metrics.Summary"
  @sum_mod :"Elixir.Telemetry.Metrics.Sum"
  @last_value_mod :"Elixir.Telemetry.Metrics.LastValue"
  @counter_mod :"Elixir.Telemetry.Metrics.Counter"

  # ── metrics/0 ───────────────────────────────────────────────────────

  describe "metrics/0" do
    test "returns a non-empty list of telemetry metric structs" do
      metrics = Telemetry.metrics()

      assert [_ | _] = metrics
      assert Enum.all?(metrics, &is_struct/1)
    end

    test "all metrics use supported Telemetry.Metrics types" do
      metrics = Telemetry.metrics()

      assert Enum.all?(metrics, fn metric ->
               metric.__struct__ in [@summary_mod, @sum_mod, @last_value_mod]
             end)
    end

    test "exposes accounted and provider storage measurements without workspace-id tags" do
      metrics = Telemetry.metrics()

      storage_metrics =
        Enum.filter(metrics, fn metric ->
          List.starts_with?(metric.name, [:storyarn, :storage, :accounting]) or
            List.starts_with?(metric.name, [:storyarn, :storage, :provider_footprint])
        end)

      assert length(storage_metrics) == 11
      assert Enum.all?(storage_metrics, &(&1.__struct__ == @last_value_mod))
      assert Enum.all?(storage_metrics, &(:workspace_id not in &1.tags))

      names = Enum.map(storage_metrics, & &1.name)
      assert [:storyarn, :storage, :accounting, :updated, :accounted_bytes] in names
      assert [:storyarn, :storage, :provider_footprint, :physical_bytes] in names
      assert [:storyarn, :storage, :provider_footprint, :drift_bytes] in names
    end

    # -- Phoenix metrics --

    test "includes endpoint start and stop metrics" do
      names = metric_names()

      assert [:phoenix, :endpoint, :start, :system_time] in names
      assert [:phoenix, :endpoint, :stop, :duration] in names
    end

    test "includes router dispatch metrics with route tags" do
      metrics = Telemetry.metrics()

      dispatch_metrics =
        Enum.filter(metrics, fn m ->
          match?([:phoenix, :router_dispatch, _, _], m.name)
        end)

      assert length(dispatch_metrics) >= 3

      tagged = Enum.filter(dispatch_metrics, &(:route in &1.tags))
      assert length(tagged) >= 2
    end

    test "includes socket and channel metrics" do
      names = metric_names()

      assert [:phoenix, :socket_connected, :duration] in names
      assert [:phoenix, :channel_joined, :duration] in names
    end

    test "includes channel_handled_in metric with event tag" do
      metrics = Telemetry.metrics()

      handled_in =
        Enum.find(metrics, fn m ->
          m.name == [:phoenix, :channel_handled_in, :duration]
        end)

      assert handled_in
      assert :event in handled_in.tags
    end

    test "includes socket drain as a sum metric" do
      metrics = Telemetry.metrics()

      drain =
        Enum.find(metrics, fn m ->
          m.name == [:phoenix, :socket_drain, :count]
        end)

      assert drain
      assert drain.__struct__ == @sum_mod
    end

    # -- Database metrics --

    test "includes all five database query metrics" do
      names = metric_names()

      assert [:storyarn, :repo, :query, :total_time] in names
      assert [:storyarn, :repo, :query, :decode_time] in names
      assert [:storyarn, :repo, :query, :query_time] in names
      assert [:storyarn, :repo, :query, :queue_time] in names
      assert [:storyarn, :repo, :query, :idle_time] in names
    end

    test "database metrics have descriptions" do
      metrics = Telemetry.metrics()

      db_metrics =
        Enum.filter(metrics, fn m ->
          match?([:storyarn, :repo, :query, _], m.name)
        end)

      assert length(db_metrics) == 5
      assert Enum.all?(db_metrics, &(is_binary(&1.description) and &1.description != ""))
    end

    test "database metrics use millisecond unit" do
      metrics = Telemetry.metrics()

      db_metrics =
        Enum.filter(metrics, fn m ->
          match?([:storyarn, :repo, :query, _], m.name)
        end)

      assert Enum.all?(db_metrics, &(&1.unit == :millisecond))
    end

    # -- Project template installation metrics --

    test "includes template installation throughput and duration metrics" do
      names = metric_names()

      assert [:storyarn, :project_template, :installation, :requested, :count] in names
      assert [:storyarn, :project_template, :installation, :stop, :count] in names
      assert [:storyarn, :project_template, :installation, :stop, :duration] in names
    end

    test "includes import metrics with privacy-safe tags" do
      metrics = Enum.filter(Telemetry.metrics(), &(Enum.take(&1.name, 2) == [:storyarn, :import]))

      assert length(metrics) == 11

      assert Enum.any?(metrics, fn metric ->
               metric.name == [:storyarn, :import, :expiration, :terminal, :count] and
                 metric.tags == [:format, :disposition]
             end)

      assert Enum.any?(metrics, fn metric ->
               metric.name == [:storyarn, :import, :snapshot, :transition, :count] and
                 metric.tags == [:format, :source_kind, :parser_version, :import_mode, :state]
             end)

      assert Enum.all?(
               Enum.filter(metrics, fn metric ->
                 Enum.take(metric.name, 4) in [
                   [:storyarn, :import, :execute, :stop],
                   [:storyarn, :import, :error, :count]
                 ]
               end),
               &(:import_mode in &1.tags)
             )

      refute Enum.any?(metrics, fn metric ->
               Enum.any?([:filename, :content, :user_id, :project_id], &(&1 in metric.tags))
             end)
    end

    # -- VM metrics --

    test "includes VM memory metric with kilobyte unit" do
      metrics = Telemetry.metrics()

      vm_memory =
        Enum.find(metrics, fn m ->
          m.name == [:vm, :memory, :total]
        end)

      assert vm_memory
      assert vm_memory.unit == :kilobyte
    end

    test "includes VM run queue metrics" do
      names = metric_names()

      assert [:vm, :total_run_queue_lengths, :total] in names
      assert [:vm, :total_run_queue_lengths, :cpu] in names
      assert [:vm, :total_run_queue_lengths, :io] in names
    end

    test "includes AI result expiration metrics with privacy-safe tags" do
      metrics = Enum.filter(Telemetry.metrics(), &(Enum.take(&1.name, 3) == [:storyarn, :ai, :expiration]))

      assert length(metrics) == 3
      assert Enum.all?(metrics, &(&1.tags == [:status]))
    end

    test "registers recoverable asset-trash metrics without identifier tags" do
      metrics =
        Enum.filter(Telemetry.metrics(), &(Enum.take(&1.name, 4) == [:storyarn, :assets, :trash, :stop]))

      assert Enum.map(metrics, & &1.name) == [[:storyarn, :assets, :trash, :stop, :count]]

      assert Enum.all?(metrics, &(&1.__struct__ == @sum_mod))
      assert Enum.all?(metrics, &(&1.tags == [:action, :outcome]))
    end

    test "registers durable storage-cleanup retry outcomes" do
      metrics =
        Enum.filter(
          Telemetry.metrics(),
          &(Enum.take(&1.name, 4) == [:storyarn, :assets, :storage_compensation, :persisted_retry])
        )

      assert metrics |> Enum.map(& &1.name) |> Enum.sort() ==
               Enum.sort([
                 [:storyarn, :assets, :storage_compensation, :persisted_retry, :count],
                 [:storyarn, :assets, :storage_compensation, :persisted_retry, :failed_count]
               ])

      assert Enum.all?(metrics, &(&1.__struct__ == @sum_mod))
      assert Enum.all?(metrics, &(&1.tags == []))
    end

    test "registers durable storage-cleanup backlog gauges without tags" do
      metrics =
        Enum.filter(
          Telemetry.metrics(),
          &(Enum.take(&1.name, 4) == [:storyarn, :assets, :storage_compensation, :backlog])
        )

      assert metrics |> Enum.map(& &1.name) |> Enum.sort() ==
               Enum.sort([
                 [:storyarn, :assets, :storage_compensation, :backlog, :pending_count],
                 [:storyarn, :assets, :storage_compensation, :backlog, :due_count],
                 [:storyarn, :assets, :storage_compensation, :backlog, :deferred_multipart_count],
                 [:storyarn, :assets, :storage_compensation, :backlog, :oldest_age_seconds],
                 [:storyarn, :assets, :storage_compensation, :backlog, :oldest_due_age_seconds],
                 [:storyarn, :assets, :storage_compensation, :backlog, :observed_at_unix_seconds]
               ])

      assert Enum.all?(metrics, &(&1.__struct__ == @last_value_mod))
      assert Enum.all?(metrics, &(&1.tags == []))
    end

    test "registers global multipart inventory with only the bounded failure label" do
      metrics =
        Enum.filter(
          Telemetry.metrics(),
          &(Enum.take(&1.name, 4) == [:storyarn, :storage, :multipart_inventory, :snapshot])
        )

      assert length(metrics) == 5

      count = Enum.find(metrics, &(&1.name == [:storyarn, :storage, :multipart_inventory, :snapshot, :count]))

      assert count.tags == []

      safe_metadata = %{failure: :none, storage_key: "private/path"}
      assert count.keep.(safe_metadata)
      assert count.tag_values.(safe_metadata) == %{}

      refute count.keep.(%{failure: :private_path})

      failure =
        Enum.find(
          metrics,
          &(&1.name == [:storyarn, :storage, :multipart_inventory, :snapshot, :failure_count])
        )

      assert failure.tags == [:failure]
      refute failure.keep.(safe_metadata)
      assert failure.keep.(%{failure: :provider_error})
    end

    test "registers snapshot lifecycle, recovery, retention, and reset metrics without identifier tags" do
      metrics =
        Enum.filter(Telemetry.metrics(), &(Enum.take(&1.name, 2) == [:storyarn, :snapshot]))

      assert length(metrics) == 78

      names = Enum.map(metrics, & &1.name)
      assert [:storyarn, :snapshot, :cleanup, :intent, :count] in names
      assert [:storyarn, :snapshot, :cleanup, :stop, :terminal_failure_count] in names
      assert [:storyarn, :snapshot, :cleanup, :recovery, :stop, :recovered_count] in names
      assert [:storyarn, :snapshot, :cleanup, :backlog, :oldest_age_seconds] in names
      assert [:storyarn, :snapshot, :cleanup, :backlog, :observed_at_unix_seconds] in names
      assert [:storyarn, :snapshot, :cleanup, :backlog, :terminal_retry_count] in names
      assert [:storyarn, :snapshot, :cleanup, :backlog, :repeated_terminal_failures] in names
      assert [:storyarn, :snapshot, :retention, :stop, :deleted_count] in names
      assert [:storyarn, :snapshot, :retention, :stop, :expired_export_lease_candidate_count] in names
      assert [:storyarn, :snapshot, :retention, :stop, :expired_export_lease_count] in names
      assert [:storyarn, :snapshot, :retention, :stop, :expired_export_lease_changed_count] in names
      assert [:storyarn, :snapshot, :retention, :stop, :purged_export_lease_candidate_count] in names
      assert [:storyarn, :snapshot, :retention, :stop, :purged_export_lease_count] in names
      assert [:storyarn, :snapshot, :retention, :stop, :purged_export_lease_changed_count] in names
      assert [:storyarn, :snapshot, :retention, :stop, :orphaned_build_count] in names
      assert [:storyarn, :snapshot, :build, :heartbeat, :count] in names
      assert [:storyarn, :snapshot, :download, :lease, :count] in names
      assert [:storyarn, :snapshot, :download, :stop, :count] in names
      assert [:storyarn, :snapshot, :download, :stop, :bytes] in names
      assert [:storyarn, :snapshot, :download, :stop, :artifact_bytes] in names
      assert [:storyarn, :snapshot, :download, :stop, :duration] in names
      assert [:storyarn, :snapshot, :reset, :stop, :object_count] in names
      assert [:storyarn, :snapshot, :reconciliation, :start, :count] in names
      assert [:storyarn, :snapshot, :reconciliation, :page, :finding_count] in names
      assert [:storyarn, :snapshot, :reconciliation, :stop, :count] in names
      assert [:storyarn, :snapshot, :reconciliation, :repair, :stop, :count] in names
      assert [:storyarn, :snapshot, :reconciliation, :repair, :stop, :bytes] in names
      assert [:storyarn, :snapshot, :reconciliation, :repair, :recovery, :stop, :requeued_count] in names
      assert [:storyarn, :snapshot, :reconciliation, :repair, :recovery, :stop, :failure_count] in names
      assert [:storyarn, :snapshot, :reconciliation, :repair, :recovery, :stop, :continuation_count] in names
      assert [:storyarn, :snapshot, :reconciliation, :summary, :stale_reservation_bytes] in names
      assert [:storyarn, :snapshot, :reconciliation, :summary, :orphan_object_bytes] in names
      assert [:storyarn, :snapshot, :reconciliation, :summary, :missing_ready_snapshot_count] in names
      assert [:storyarn, :snapshot, :reconciliation, :summary, :corrupt_ready_snapshot_count] in names
      assert [:storyarn, :snapshot, :reconciliation, :summary, :terminal_cleanup_failure_count] in names
      assert [:storyarn, :snapshot, :reconciliation, :summary, :terminal_cleanup_retry_count] in names
      assert [:storyarn, :snapshot, :reconciliation, :projection, :stop, :success] in names
      assert [:storyarn, :snapshot, :reconciliation, :projection, :stop, :failure_count] in names

      projection_metrics =
        Enum.filter(
          metrics,
          &(Enum.take(&1.name, 5) == [:storyarn, :snapshot, :reconciliation, :projection, :stop])
        )

      assert length(projection_metrics) == 12
      assert Enum.all?(projection_metrics, &(&1.tags == []))

      repair_metrics =
        Enum.filter(metrics, &(Enum.take(&1.name, 5) == [:storyarn, :snapshot, :reconciliation, :repair, :stop]))

      assert Enum.all?(repair_metrics, &(&1.tags == [:action, :outcome]))

      repair_recovery_metrics =
        Enum.filter(
          metrics,
          &(Enum.take(&1.name, 6) == [:storyarn, :snapshot, :reconciliation, :repair, :recovery, :stop])
        )

      assert length(repair_recovery_metrics) == 7
      assert Enum.all?(repair_recovery_metrics, &(&1.tags == [:status]))

      download_metrics =
        Enum.filter(metrics, &(Enum.take(&1.name, 4) == [:storyarn, :snapshot, :download, :stop]))

      assert length(download_metrics) == 4
      assert Enum.all?(download_metrics, &(&1.tags == [:outcome, :phase, :error_code]))

      summary_metrics =
        Enum.filter(metrics, &(Enum.take(&1.name, 4) == [:storyarn, :snapshot, :reconciliation, :summary]))

      assert Enum.all?(
               summary_metrics,
               &(&1.tags == [:contract_version, :mode, :multipart_inventory_state])
             )

      refute Enum.any?(metrics, fn metric ->
               Enum.any?([:user_id, :workspace_id, :project_id, :snapshot_id, :inventory_digest], &(&1 in metric.tags))
             end)
    end

    # -- Total count --

    test "defines exactly the expected number of metrics" do
      metrics = Telemetry.metrics()

      # 9 Phoenix + 5 DB + 3 template installation + 11 import + 11 storage +
      # 1 asset trash + 2 storage cleanup retry + 6 storage cleanup backlog +
      # 5 global multipart inventory + 78 snapshot lifecycle +
      # 3 AI expiration + 4 VM = 138
      assert length(metrics) == 138
    end

    test "exports a Prometheus-compatible allowlist with recovery queue telemetry" do
      metrics = Telemetry.prometheus_metrics()

      refute Enum.any?(metrics, &(&1.__struct__ == @summary_mod))
      assert Enum.all?(metrics, &(&1.__struct__ in [@sum_mod, @last_value_mod, @counter_mod]))

      assert Enum.any?(metrics, fn metric ->
               metric.name == [:storyarn, :import, :execute, :stop, :count] and
                 metric.__struct__ == @sum_mod and
                 metric.tags == [:format, :status, :import_mode]
             end)

      assert Enum.any?(metrics, fn metric ->
               metric.name == [:storyarn, :import, :expiration, :terminal, :count] and
                 metric.__struct__ == @sum_mod and
                 metric.tags == [:format, :disposition]
             end)

      refute Enum.any?(metrics, &(&1.name == [:storyarn, :import, :execute, :stop, :duration]))
      refute Enum.any?(metrics, &(&1.name == [:storyarn, :snapshot, :download, :stop, :duration]))

      assert Enum.any?(metrics, fn metric ->
               metric.name == [:storyarn, :oban, :job, :stop, :count] and
                 metric.__struct__ == @counter_mod and metric.tags == [:queue, :state]
             end)

      queue_metrics =
        Enum.filter(metrics, &(Enum.take(&1.name, 4) == [:storyarn, :oban, :queue, :snapshot]))

      assert length(queue_metrics) == 12
      assert Enum.all?(queue_metrics, &(&1.__struct__ == @last_value_mod))
      assert Enum.all?(queue_metrics, &(&1.tags == [:queue]))

      poll_metrics =
        Enum.filter(metrics, &(Enum.take(&1.name, 4) == [:storyarn, :oban, :queue, :poll]))

      assert length(poll_metrics) == 3

      projection_metrics =
        Enum.filter(
          metrics,
          &(Enum.take(&1.name, 5) == [:storyarn, :snapshot, :reconciliation, :projection, :stop])
        )

      assert length(projection_metrics) == 12
      assert Enum.all?(projection_metrics, &(&1.tags == []))

      refute Enum.any?(metrics, fn metric ->
               Enum.take(metric.name, 4) == [:storyarn, :snapshot, :reconciliation, :summary] or
                 Enum.take(metric.name, 4) == [:storyarn, :snapshot, :reconciliation, :page] or
                 metric.name == [:storyarn, :snapshot, :reconciliation, :stop, :finding_count]
             end)

      refute Enum.any?(metrics, fn metric ->
               List.first(metric.name) in [:phoenix, :vm] or
                 Enum.take(metric.name, 2) in [[:storyarn, :repo], [:storyarn, :ai]] or
                 Enum.take(metric.name, 3) == [:storyarn, :project_template, :installation] or
                 Enum.take(metric.name, 3) in [
                   [:storyarn, :storage, :accounting],
                   [:storyarn, :storage, :provider_footprint]
                 ]
             end)
    end

    test "Oban metric functions retain only bounded queue and result labels" do
      metric =
        Enum.find(Telemetry.prometheus_metrics(), fn metric ->
          metric.name == [:storyarn, :oban, :job, :stop, :count]
        end)

      metadata = %{
        job: %Oban.Job{
          queue: "imports",
          args: %{"filename" => "private-story.yarn", "project_id" => 999},
          worker: "Storyarn.Workers.ImportProjectWorker"
        },
        state: :snoozed,
        reason: "private provider failure"
      }

      assert metric.keep.(metadata)
      assert metric.tag_values.(metadata) == %{queue: "imports", state: "snoozed"}

      refute metric.keep.(put_in(metadata.job.queue, "default"))
    end
  end

  # ── Supervisor behavior ─────────────────────────────────────────────

  describe "supervisor" do
    test "process is registered and alive" do
      pid = Process.whereis(Telemetry)
      assert pid
      assert Process.alive?(pid)
    end

    test "module implements Supervisor child_spec" do
      spec = Telemetry.child_spec([])
      assert spec.id == Telemetry
      assert spec.type == :supervisor
    end

    test "Prometheus reporter is opt-in and attaches synchronously" do
      assert Telemetry.prometheus_reporter_child_specs(enabled: false) == []

      assert [
               %{
                 id: :storyarn_operational_metrics,
                 start: {TelemetryMetricsPrometheus.Core.Registry, :start_link, [options]}
               }
             ] = Telemetry.prometheus_reporter_child_specs(enabled: true)

      assert Keyword.fetch!(options, :name) == Telemetry.prometheus_reporter_name()
      assert Keyword.fetch!(options, :start_async) == false
      assert Keyword.fetch!(options, :metrics) == Telemetry.prometheus_metrics()
    end

    test "Prometheus core records a bounded metric without private metadata" do
      start_supervised!(
        {TelemetryMetricsPrometheus.Core,
         metrics: Telemetry.prometheus_metrics(), name: :storyarn_operational_metrics_test, start_async: false}
      )

      private_canary = "author@example.com/private/project.yarn"

      :telemetry.execute(
        [:storyarn, :import, :expiration, :terminal],
        %{count: 1},
        %{format: "yarn", disposition: "accepted", private_value: private_canary}
      )

      scrape = TelemetryMetricsPrometheus.Core.scrape(:storyarn_operational_metrics_test)

      assert scrape =~ "storyarn_import_expiration_terminal_count"
      assert scrape =~ ~s(disposition="accepted")
      assert scrape =~ ~s(format="yarn")
      refute scrape =~ private_canary
    end
  end

  # ── Helpers ─────────────────────────────────────────────────────────

  defp metric_names do
    Enum.map(Telemetry.metrics(), & &1.name)
  end
end
