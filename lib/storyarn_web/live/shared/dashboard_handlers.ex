defmodule StoryarnWeb.Live.Shared.DashboardHandlers do
  @moduledoc """
  Shared `handle_info` clauses for dashboard invalidation with debounce.

  Subscribes via `Collaboration.subscribe_dashboard/1` in mount, then
  receives `{:dashboard_invalidate, scope}` messages. Debounces rapid
  invalidations (500ms) before triggering `:load_dashboard_data`.

  ## Usage

      use StoryarnWeb.Live.Shared.DashboardHandlers

  The using module must implement `handle_info(:load_dashboard_data, socket)`.
  """

  defmacro __using__(_opts) do
    quote do
      @impl true
      def handle_info({:dashboard_invalidate, _scope}, socket) do
        if timer = socket.assigns[:dashboard_reload_timer] do
          Process.cancel_timer(timer)
        end

        timer = Process.send_after(self(), :debounced_dashboard_reload, 500)
        {:noreply, Phoenix.Component.assign(socket, :dashboard_reload_timer, timer)}
      end

      @impl true
      def handle_info(:debounced_dashboard_reload, socket) do
        send(self(), :load_dashboard_data)
        {:noreply, Phoenix.Component.assign(socket, :dashboard_reload_timer, nil)}
      end
    end
  end
end
