defmodule Storyarn.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      StoryarnWeb.Telemetry,
      Storyarn.Repo,
      Storyarn.Vault,
      {DNSCluster, query: Application.get_env(:storyarn, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Storyarn.PubSub},
      Storyarn.Collaboration.Presence,
      Storyarn.Collaboration.Locks,
      Storyarn.Flows.DebugSessionStore,
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
