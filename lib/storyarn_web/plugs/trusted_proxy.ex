defmodule StoryarnWeb.Plugs.TrustedProxy do
  @moduledoc """
  Conditionally applies `RemoteIp` to set `conn.remote_ip` from
  trusted proxy headers (`Fly-Client-IP`, `X-Forwarded-For`).

  Only active when `config :storyarn, trust_proxy: true` (set via
  `TRUST_PROXY=true` env var in production). Without it, the raw
  TCP peer address is used — safe default for development.
  """

  @behaviour Plug

  @impl true
  def init(_opts), do: RemoteIp.init(headers: ~w[fly-client-ip x-forwarded-for])

  @impl true
  def call(conn, remote_ip_opts) do
    if Application.get_env(:storyarn, :trust_proxy, false) do
      RemoteIp.call(conn, remote_ip_opts)
    else
      conn
    end
  end
end
