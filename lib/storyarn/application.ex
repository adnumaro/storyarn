defmodule Storyarn.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # See https://hexdocs.pm/elixir/Supervisor.html
    # for more information on supervision trees
    opts = [strategy: :one_for_one, name: Storyarn.Supervisor]
    Supervisor.start_link(children(), opts)
  end

  @doc false
  def children(operational_metrics_config \\ Application.fetch_env!(:storyarn, :operational_metrics)) do
    [
      StoryarnWeb.Telemetry
    ] ++
      StoryarnWeb.Telemetry.prometheus_reporter_child_specs(operational_metrics_config) ++
      Storyarn.Platform.Adapters.Telemetry.PrometheusEndpoint.child_specs(
        operational_metrics_config,
        StoryarnWeb.Telemetry.prometheus_reporter_name()
      ) ++
      [
        Storyarn.Repo,
        Storyarn.Platform.Vault,
        Storyarn.Projects.import_error_deduplicator_child_spec(),
        Storyarn.Platform.RateLimiter.child_spec_for_backend(),
        {DNSCluster, query: Application.get_env(:storyarn, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Storyarn.PubSub},
        Storyarn.Platform.Collaboration.Presence,
        Storyarn.Platform.Collaboration.Locks,
        Storyarn.Platform.Dashboards.Cache,
        Storyarn.Flows,
        {Task.Supervisor, name: Storyarn.TaskSupervisor}
      ] ++
      Storyarn.Platform.ObjectStorage.child_specs() ++
      [
        {Oban, Application.fetch_env!(:storyarn, Oban)}
      ] ++
      Storyarn.Platform.Adapters.Oban.OperationalMetrics.child_specs(operational_metrics_config) ++
      Storyarn.Projects.project_snapshot_reconciliation_metrics_child_specs(operational_metrics_config) ++
      [
        {Storyarn.Platform.Adapters.Oban.QueueWakeup,
         queue: :invitation_delivery, interval: to_timeout(second: 15), repetitions: 20},
        # Start to serve requests, typically the last entry
        StoryarnWeb.Endpoint
      ]
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    StoryarnWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
