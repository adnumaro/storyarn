defmodule Storyarn.Platform.Adapters.Telemetry.PrometheusEndpointTest do
  use ExUnit.Case, async: false

  import Plug.Conn, only: [get_resp_header: 2]
  import Plug.Test
  import Telemetry.Metrics

  alias Storyarn.Platform.Adapters.Telemetry.PrometheusEndpoint

  @reporter_name :storyarn_prometheus_endpoint_test

  test "listener is opt-in and binds only the configured dedicated port" do
    config = [
      enabled: false,
      listener_ip: {0, 0, 0, 0},
      listener_port: 9091
    ]

    assert PrometheusEndpoint.child_specs(config, @reporter_name) == []

    assert [%{id: PrometheusEndpoint, start: {Bandit, :start_link, [options]}}] =
             PrometheusEndpoint.child_specs(Keyword.put(config, :enabled, true), @reporter_name)

    assert Keyword.fetch!(options, :ip) == {0, 0, 0, 0}
    assert Keyword.fetch!(options, :port) == 9091
    assert Keyword.fetch!(options, :plug) == {PrometheusEndpoint, reporter_name: @reporter_name}
    assert Keyword.fetch!(options, :http_2_options) == [enabled: false]
    assert Keyword.fetch!(options, :websocket_options) == [enabled: false]
  end

  test "serves only the aggregate scrape without caching" do
    options =
      PrometheusEndpoint.init(
        reporter_name: @reporter_name,
        scrape: fn @reporter_name -> "storyarn_recovery_queue_backlog 0\n" end
      )

    conn =
      :get
      |> conn("/metrics?ignored=true")
      |> PrometheusEndpoint.call(options)

    assert conn.status == 200
    assert conn.resp_body == "storyarn_recovery_queue_backlog 0\n"
    assert get_resp_header(conn, "content-type") == ["text/plain; version=0.0.4; charset=utf-8"]
    assert get_resp_header(conn, "cache-control") == ["no-store"]
    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
  end

  test "does not expose other paths or echo request data" do
    private_canary = "author@example.com/private/project.yarn"
    options = PrometheusEndpoint.init(reporter_name: @reporter_name, scrape: fn _name -> "unused" end)

    for conn <- [conn(:post, "/metrics"), conn(:get, "/#{private_canary}")] do
      conn = PrometheusEndpoint.call(conn, options)

      assert conn.status == 404
      assert conn.resp_body == "not found\n"
      refute conn.resp_body =~ private_canary
    end
  end

  test "returns a fixed response when scraping fails without exposing the exception" do
    private_canary = "author@example.com/private/object.zip?signature=secret"

    options =
      PrometheusEndpoint.init(
        reporter_name: @reporter_name,
        scrape: fn _name -> raise private_canary end
      )

    conn = PrometheusEndpoint.call(conn(:get, "/metrics"), options)

    assert conn.status == 503
    assert conn.resp_body == "metrics unavailable\n"
    refute conn.resp_body =~ private_canary
  end

  test "Bandit serves the registered reporter over HTTP" do
    private_canary = "author@example.com/private/project.yarn"

    start_supervised!(
      {TelemetryMetricsPrometheus.Core,
       name: @reporter_name, start_async: false, metrics: [counter("storyarn.metrics_listener.test.count")]}
    )

    :telemetry.execute(
      [:storyarn, :metrics_listener, :test],
      %{count: 1},
      %{private_value: private_canary}
    )

    [listener_spec] =
      PrometheusEndpoint.child_specs(
        [enabled: true, listener_ip: {127, 0, 0, 1}, listener_port: 0],
        @reporter_name
      )

    listener = start_supervised!(listener_spec)
    assert {:ok, {{127, 0, 0, 1}, port}} = ThousandIsland.listener_info(listener)

    response = Req.get!("http://127.0.0.1:#{port}/metrics", retry: false)

    assert response.status == 200
    assert response.body =~ "storyarn_metrics_listener_test_count"
    refute response.body =~ private_canary
  end
end
