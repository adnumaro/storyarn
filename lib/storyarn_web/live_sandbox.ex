defmodule StoryarnWeb.LiveSandbox do
  @moduledoc """
  on_mount hook that allows LiveView processes to use the Ecto SQL Sandbox.

  Required for async Playwright e2e tests where each test has its own
  isolated sandbox connection. The sandbox metadata is passed via the
  user-agent header from the browser context.

  Only compiled when `:sql_sandbox` is enabled (test environment).
  """

  import Phoenix.LiveView
  import Phoenix.Component

  def on_mount(:default, _params, _session, socket) do
    socket =
      assign_new(socket, :phoenix_ecto_sandbox, fn ->
        if connected?(socket), do: get_connect_info(socket, :user_agent)
      end)

    Phoenix.Ecto.SQL.Sandbox.allow(
      socket.assigns.phoenix_ecto_sandbox,
      Ecto.Adapters.SQL.Sandbox
    )

    {:cont, socket}
  end
end
