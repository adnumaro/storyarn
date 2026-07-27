defmodule StoryarnWeb.Live.Shared.DashboardHandlers do
  @moduledoc """
  Shared `handle_info` clauses for dashboard invalidation with debounce.

  Subscribes via `Collaboration.subscribe_dashboard/1` in mount, then
  receives `{:dashboard_invalidate, scope}` messages. Debounces rapid
  invalidations (500ms) before triggering `:load_dashboard_data`.

  The scope is intentionally not filtered here. Sheet, flow, and scene health
  findings depend on references owned by the other tools, so a change outside
  the active dashboard can still change its issue list.

  ## Usage

      use StoryarnWeb.Live.Shared.DashboardHandlers

  The using module must implement `handle_info(:load_dashboard_data, socket)`.
  """

  import Phoenix.Component, only: [assign: 3]

  def schedule_reload(socket) do
    case socket.assigns[:dashboard_reload_timer] do
      {timer, _token} -> Process.cancel_timer(timer)
      _none -> :ok
    end

    token = make_ref()
    timer = Process.send_after(self(), {:debounced_dashboard_reload, token}, 500)
    assign(socket, :dashboard_reload_timer, {timer, token})
  end

  defmacro __using__(_opts) do
    quote do
      @impl true
      def handle_info({:dashboard_invalidate, _scope}, socket) do
        {:noreply, StoryarnWeb.Live.Shared.DashboardHandlers.schedule_reload(socket)}
      end

      @impl true
      def handle_info({:debounced_dashboard_reload, token}, socket) do
        case socket.assigns[:dashboard_reload_timer] do
          {_timer, ^token} ->
            send(self(), :load_dashboard_data)
            {:noreply, Phoenix.Component.assign(socket, :dashboard_reload_timer, nil)}

          _stale_or_cancelled ->
            {:noreply, socket}
        end
      end
    end
  end
end
