defmodule Storyarn.Platform.Adapters.Telemetry.PrometheusEndpoint do
  @moduledoc """
  Minimal private HTTP endpoint for Fly's Prometheus scraper.

  This adapter is not mounted in the Phoenix router and exposes only the
  aggregate reporter output. Fly binds its port through the dedicated
  `[metrics]` configuration rather than the public HTTP service.
  """

  @behaviour Plug

  import Plug.Conn

  require Logger

  @content_type "text/plain; version=0.0.4; charset=utf-8"

  @doc false
  @spec child_specs(keyword(), atom()) :: [Supervisor.child_spec()]
  def child_specs(config, reporter_name) when is_list(config) and is_atom(reporter_name) do
    if Keyword.fetch!(config, :enabled) do
      options =
        [
          plug: {__MODULE__, reporter_name: reporter_name},
          scheme: :http,
          ip: Keyword.fetch!(config, :listener_ip),
          port: Keyword.fetch!(config, :listener_port),
          startup_log: false,
          http_2_options: [enabled: false],
          websocket_options: [enabled: false],
          thousand_island_options: [
            num_acceptors: 2,
            num_connections: 16,
            read_timeout: to_timeout(second: 5),
            shutdown_timeout: to_timeout(second: 5)
          ]
        ]

      [Supervisor.child_spec({Bandit, options}, id: __MODULE__)]
    else
      []
    end
  end

  @impl Plug
  def init(options) do
    %{
      reporter_name: Keyword.fetch!(options, :reporter_name),
      scrape: Keyword.get(options, :scrape, &TelemetryMetricsPrometheus.Core.scrape/1)
    }
  end

  @impl Plug
  def call(%Plug.Conn{method: "GET", request_path: "/metrics"} = conn, options) do
    case safe_scrape(options) do
      {:ok, body} -> metrics_response(conn, body)
      {:error, _failure} -> unavailable_response(conn)
    end
  end

  def call(%Plug.Conn{} = conn, _options), do: not_found_response(conn)

  defp safe_scrape(%{reporter_name: reporter_name, scrape: scrape}) do
    case scrape.(reporter_name) do
      body when is_binary(body) -> {:ok, body}
      _invalid -> {:error, :invalid_response}
    end
  rescue
    exception ->
      Logger.error(
        "Prometheus scrape failed failure=exception " <>
          "exception_module=#{inspect(exception.__struct__)}"
      )

      {:error, :exception}
  catch
    kind, _reason when kind in [:exit, :throw] ->
      Logger.error("Prometheus scrape failed failure=#{kind}")
      {:error, kind}
  end

  defp metrics_response(conn, body) do
    conn
    |> put_private_headers()
    |> put_resp_header("content-type", @content_type)
    |> send_resp(200, body)
  end

  defp unavailable_response(conn) do
    conn
    |> put_private_headers()
    |> send_resp(503, "metrics unavailable\n")
  end

  defp not_found_response(conn) do
    conn
    |> put_private_headers()
    |> send_resp(404, "not found\n")
  end

  defp put_private_headers(conn) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_header("x-content-type-options", "nosniff")
  end
end
