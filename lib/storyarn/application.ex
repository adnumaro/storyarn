defmodule Storyarn.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        StoryarnWeb.Telemetry,
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
          {Oban, Application.fetch_env!(:storyarn, Oban)},
          # Start to serve requests, typically the last entry
          StoryarnWeb.Endpoint
        ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Storyarn.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    StoryarnWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
