defmodule StoryarnWeb.TelemetryTest do
  use ExUnit.Case, async: true

  alias StoryarnWeb.Telemetry

  # Fully qualified to avoid alias conflict with StoryarnWeb.Telemetry
  @summary_mod :"Elixir.Telemetry.Metrics.Summary"
  @sum_mod :"Elixir.Telemetry.Metrics.Sum"

  # ── metrics/0 ───────────────────────────────────────────────────────

  describe "metrics/0" do
    test "returns a non-empty list of telemetry metric structs" do
      metrics = Telemetry.metrics()

      assert is_list(metrics)
      assert length(metrics) > 0
      assert Enum.all?(metrics, &is_struct/1)
    end

    test "all metrics are Telemetry.Metrics summary or sum types" do
      metrics = Telemetry.metrics()

      assert Enum.all?(metrics, fn metric ->
               metric.__struct__ in [@summary_mod, @sum_mod]
             end)
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

      assert handled_in != nil
      assert :event in handled_in.tags
    end

    test "includes socket drain as a sum metric" do
      metrics = Telemetry.metrics()

      drain =
        Enum.find(metrics, fn m ->
          m.name == [:phoenix, :socket_drain, :count]
        end)

      assert drain != nil
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

    # -- VM metrics --

    test "includes VM memory metric with kilobyte unit" do
      metrics = Telemetry.metrics()

      vm_memory =
        Enum.find(metrics, fn m ->
          m.name == [:vm, :memory, :total]
        end)

      assert vm_memory != nil
      assert vm_memory.unit == :kilobyte
    end

    test "includes VM run queue metrics" do
      names = metric_names()

      assert [:vm, :total_run_queue_lengths, :total] in names
      assert [:vm, :total_run_queue_lengths, :cpu] in names
      assert [:vm, :total_run_queue_lengths, :io] in names
    end

    # -- Total count --

    test "defines exactly the expected number of metrics" do
      metrics = Telemetry.metrics()

      # 9 Phoenix (endpoint 2 + router 3 + socket 2 + channel 2) + 5 DB + 4 VM = 18
      assert length(metrics) == 18
    end
  end

  # ── Supervisor behavior ─────────────────────────────────────────────

  describe "supervisor" do
    test "process is registered and alive" do
      pid = Process.whereis(Telemetry)
      assert pid != nil
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
    Telemetry.metrics() |> Enum.map(& &1.name)
  end
end
