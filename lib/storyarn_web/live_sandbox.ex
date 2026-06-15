defmodule StoryarnWeb.LiveSandbox do
  @moduledoc """
  on_mount hook that allows LiveView processes to use the Ecto SQL Sandbox.

  Required for async Playwright e2e tests where each test has its own
  isolated sandbox connection. The sandbox metadata is passed via the
  user-agent header from the browser context.

  Only compiled when `:sql_sandbox` is enabled (test environment).
  """

  import Phoenix.Component
  import Phoenix.LiveView

  def on_mount(:default, _params, _session, socket) do
    sandbox_metadata =
      if connected?(socket) do
        get_connect_info(socket, :user_agent)
      else
        socket.assigns[:phoenix_ecto_sandbox]
      end

    socket = assign(socket, :phoenix_ecto_sandbox, sandbox_metadata)

    if sandbox_metadata do
      Phoenix.Ecto.SQL.Sandbox.allow(
        sandbox_metadata,
        Ecto.Adapters.SQL.Sandbox
      )
    end

    {:cont, socket}
  end
end
