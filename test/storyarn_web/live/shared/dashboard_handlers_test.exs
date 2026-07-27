defmodule StoryarnWeb.Live.Shared.DashboardHandlersTest do
  use ExUnit.Case, async: true

  alias Phoenix.LiveView.Socket
  alias StoryarnWeb.Live.Shared.DashboardHandlers

  defmodule Harness do
    @moduledoc false
    use GenServer
    use DashboardHandlers

    @impl true
    def init(state), do: {:ok, state}

    @impl true
    def handle_info(:load_dashboard_data, socket), do: {:noreply, socket}
  end

  test "a stale debounce message cannot clear or execute the current timer" do
    first = DashboardHandlers.schedule_reload(socket_fixture())
    {_first_timer, first_token} = first.assigns.dashboard_reload_timer

    current = DashboardHandlers.schedule_reload(first)
    {current_timer, current_token} = current.assigns.dashboard_reload_timer
    Process.cancel_timer(current_timer)

    assert {:noreply, unchanged} =
             Harness.handle_info({:debounced_dashboard_reload, first_token}, current)

    assert unchanged.assigns.dashboard_reload_timer == {current_timer, current_token}
    refute_received :load_dashboard_data

    assert {:noreply, completed} =
             Harness.handle_info({:debounced_dashboard_reload, current_token}, unchanged)

    assert completed.assigns.dashboard_reload_timer == nil
    assert_received :load_dashboard_data
  end

  defp socket_fixture do
    %Socket{assigns: %{__changed__: %{}, dashboard_reload_timer: nil}}
  end
end
