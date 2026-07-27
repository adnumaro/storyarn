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
    first_timers = first.assigns.dashboard_reload_timer

    current = DashboardHandlers.schedule_reload(first)
    current_timers = current.assigns.dashboard_reload_timer
    cancel_reload_timers(current_timers)

    assert current_timers.max_wait == first_timers.max_wait
    assert current_timers.max_wait_token == first_timers.max_wait_token
    assert current_timers.quiet_token != first_timers.quiet_token

    assert {:noreply, unchanged} =
             Harness.handle_info(
               {:debounced_dashboard_reload, first_timers.quiet_token},
               current
             )

    assert unchanged.assigns.dashboard_reload_timer == current_timers
    refute_received :load_dashboard_data

    assert {:noreply, completed} =
             Harness.handle_info(
               {:debounced_dashboard_reload, current_timers.quiet_token},
               unchanged
             )

    assert completed.assigns.dashboard_reload_timer == nil
    assert_received :load_dashboard_data
  end

  test "the max-wait timer survives debounce rearming and forces the reload" do
    first = DashboardHandlers.schedule_reload(socket_fixture())
    first_timers = first.assigns.dashboard_reload_timer

    rearmed =
      Enum.reduce(1..5, first, fn _iteration, socket ->
        DashboardHandlers.schedule_reload(socket)
      end)

    current_timers = rearmed.assigns.dashboard_reload_timer
    cancel_reload_timers(current_timers)

    assert current_timers.max_wait == first_timers.max_wait
    assert current_timers.max_wait_token == first_timers.max_wait_token

    assert {:noreply, completed} =
             Harness.handle_info(
               {:max_wait_dashboard_reload, first_timers.max_wait_token},
               rearmed
             )

    assert completed.assigns.dashboard_reload_timer == nil
    assert_received :load_dashboard_data
  end

  test "a cache lifecycle reset schedules the same bounded reload" do
    assert {:noreply, scheduled} =
             Harness.handle_info(:dashboard_cache_reset, socket_fixture())

    assert %{quiet: quiet_timer, max_wait: max_wait_timer} =
             scheduled.assigns.dashboard_reload_timer

    Process.cancel_timer(quiet_timer)
    Process.cancel_timer(max_wait_timer)
  end

  test "overlapping loads coalesce into one pending restart without cancelling the running task" do
    started =
      %{
        overview_status: :ready,
        dashboard_overview_running?: false,
        dashboard_overview_reload_pending?: false
      }
      |> socket_fixture()
      |> DashboardHandlers.start_load(:overview, fn -> :first end)

    assert started.assigns.overview_status == :refreshing
    assert started.assigns.dashboard_overview_running?
    refute started.assigns.dashboard_overview_reload_pending?

    pending =
      Enum.reduce(1..5, started, fn _iteration, socket ->
        DashboardHandlers.start_load(socket, :overview, fn -> :overlap end)
      end)

    assert pending.assigns.dashboard_overview_running?
    assert pending.assigns.dashboard_overview_reload_pending?

    restarted =
      DashboardHandlers.finish_load(pending, :overview, fn socket ->
        send(self(), :overview_restarted)
        DashboardHandlers.start_load(socket, :overview, fn -> :second end)
      end)

    assert_received :overview_restarted
    refute_received :overview_restarted
    assert restarted.assigns.overview_status == :refreshing
    assert restarted.assigns.dashboard_overview_running?
    refute restarted.assigns.dashboard_overview_reload_pending?
  end

  test "overview and issues keep independent pending state" do
    socket =
      socket_fixture(%{
        overview_status: :ready,
        issues_status: :ready,
        dashboard_overview_running?: false,
        dashboard_overview_reload_pending?: false,
        dashboard_issues_running?: false,
        dashboard_issues_reload_pending?: false
      })

    overview = DashboardHandlers.start_load(socket, :overview, fn -> :overview end)
    both = DashboardHandlers.start_load(overview, :issues, fn -> :issues end)
    pending_overview = DashboardHandlers.start_load(both, :overview, fn -> :overlap end)

    assert pending_overview.assigns.dashboard_overview_reload_pending?
    refute pending_overview.assigns.dashboard_issues_reload_pending?
    assert pending_overview.assigns.dashboard_overview_running?
    assert pending_overview.assigns.dashboard_issues_running?
  end

  test "dashboard work runs under the application task supervisor" do
    parent = self()

    socket =
      socket_fixture(%{
        overview_status: :loading,
        dashboard_overview_running?: false,
        dashboard_overview_reload_pending?: false
      })

    _started =
      DashboardHandlers.start_load(%{socket | transport_pid: self()}, :overview, fn ->
        send(parent, {:dashboard_task_started, self()})

        receive do
          :finish -> :ok
        end
      end)

    assert_receive {:dashboard_task_started, task_pid}

    try do
      assert task_pid in Task.Supervisor.children(Storyarn.TaskSupervisor)
    after
      send(task_pid, :finish)
    end
  end

  defp socket_fixture(extra_assigns \\ %{}) do
    %Socket{
      assigns:
        Map.merge(
          %{__changed__: %{}, dashboard_reload_timer: nil},
          extra_assigns
        )
    }
  end

  defp cancel_reload_timers(timers) do
    Process.cancel_timer(timers.quiet)
    Process.cancel_timer(timers.max_wait)
  end
end
