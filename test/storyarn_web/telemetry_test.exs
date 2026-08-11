defmodule StoryarnWeb.TelemetryTest do
  use ExUnit.Case, async: true

  alias StoryarnWeb.Telemetry

  # Fully qualified to avoid alias conflict with StoryarnWeb.Telemetry
  @summary_mod :"Elixir.Telemetry.Metrics.Summary"
  @sum_mod :"Elixir.Telemetry.Metrics.Sum"
  @last_value_mod :"Elixir.Telemetry.Metrics.LastValue"

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
          List.starts_with?(metric.name, [:storyarn, :storage])
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

      assert length(metrics) == 9

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

    test "registers snapshot lifecycle, recovery, retention, and reset metrics without identifier tags" do
      metrics =
        Enum.filter(Telemetry.metrics(), &(Enum.take(&1.name, 2) == [:storyarn, :snapshot]))

      assert length(metrics) == 64

      names = Enum.map(metrics, & &1.name)
      assert [:storyarn, :snapshot, :cleanup, :intent, :count] in names
      assert [:storyarn, :snapshot, :cleanup, :stop, :terminal_failure_count] in names
      assert [:storyarn, :snapshot, :cleanup, :recovery, :stop, :recovered_count] in names
      assert [:storyarn, :snapshot, :cleanup, :backlog, :oldest_age_seconds] in names
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
               Enum.any?([:workspace_id, :project_id, :snapshot_id, :inventory_digest], &(&1 in metric.tags))
             end)
    end

    # -- Total count --

    test "defines exactly the expected number of metrics" do
      metrics = Telemetry.metrics()

      # 9 Phoenix + 5 DB + 3 template installation + 9 import + 11 storage +
      # 1 asset trash + 2 storage cleanup retry + 64 snapshot lifecycle +
      # 3 AI expiration + 4 VM = 111
      assert length(metrics) == 111
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
  end

  # ── Helpers ─────────────────────────────────────────────────────────

  defp metric_names do
    Enum.map(Telemetry.metrics(), & &1.name)
  end
end
