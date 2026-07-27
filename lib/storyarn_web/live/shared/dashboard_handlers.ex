defmodule StoryarnWeb.Live.Shared.DashboardHandlers do
  @moduledoc """
  Shared invalidation and async-load orchestration for project dashboards.

  Subscribes via `Collaboration.subscribe_dashboard/1` and
  `DashboardCache.subscribe_resets/0` in mount, then receives domain
  invalidations and local cache-lifecycle resets. Rapid invalidations use a
  trailing 500ms debounce capped by a two-second maximum wait before triggering
  `:load_dashboard_data`.

  Each of the independently rendered overview and issues tasks is coalesced.
  An invalidation that arrives while a task is running records one pending
  reload instead of cancelling useful work. When that task finishes, the
  pending reload starts immediately. This guarantees forward progress while
  still collapsing any number of overlapping invalidations into one refresh.

  The scope is intentionally not filtered here. Sheet, flow, and scene health
  findings depend on references owned by the other tools, so a change outside
  the active dashboard can still change its issue list.

  ## Usage

      use StoryarnWeb.Live.Shared.DashboardHandlers

  The using module must implement `handle_info(:load_dashboard_data, socket)`.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [start_async: 4]

  alias StoryarnWeb.Live.Shared.DashboardHelpers

  @debounce_ms 500
  @max_wait_ms 2_000
  @retry_cooldown_ms 1_000

  @type load_kind :: :overview | :issues

  def schedule_reload(socket) do
    case socket.assigns[:dashboard_reload_timer] do
      %{quiet: quiet_timer} = timers ->
        Process.cancel_timer(quiet_timer)
        quiet_token = make_ref()

        quiet_timer =
          Process.send_after(
            self(),
            {:debounced_dashboard_reload, quiet_token},
            @debounce_ms
          )

        assign(socket, :dashboard_reload_timer, %{
          timers
          | quiet: quiet_timer,
            quiet_token: quiet_token
        })

      _none ->
        quiet_token = make_ref()
        max_wait_token = make_ref()

        timers = %{
          quiet_token: quiet_token,
          quiet:
            Process.send_after(
              self(),
              {:debounced_dashboard_reload, quiet_token},
              @debounce_ms
            ),
          max_wait_token: max_wait_token,
          max_wait:
            Process.send_after(
              self(),
              {:max_wait_dashboard_reload, max_wait_token},
              @max_wait_ms
            )
        }

        assign(socket, :dashboard_reload_timer, timers)
    end
  end

  @doc false
  def fire_scheduled_reload(socket, timer_kind, token) when timer_kind in [:quiet, :max_wait] do
    case socket.assigns[:dashboard_reload_timer] do
      %{quiet: quiet_timer, max_wait: max_wait_timer} = timers
      when (timer_kind == :quiet and timers.quiet_token == token) or
             (timer_kind == :max_wait and timers.max_wait_token == token) ->
        Process.cancel_timer(quiet_timer)
        Process.cancel_timer(max_wait_timer)
        send(self(), :load_dashboard_data)
        assign(socket, :dashboard_reload_timer, nil)

      _stale_or_cancelled ->
        socket
    end
  end

  @doc false
  def start_load(socket, kind, fun) when kind in [:overview, :issues] and is_function(fun, 0) do
    config = load_config(kind)

    if socket.assigns[config.running] do
      assign(socket, config.pending, true)
    else
      status = begin_status(kind, socket.assigns[config.status])

      socket
      |> assign(config.status, status)
      |> assign(config.running, true)
      |> assign(config.pending, false)
      |> start_async(config.async, fun, supervisor: Storyarn.TaskSupervisor)
    end
  end

  @doc false
  def retry_load(socket, kind, restart_fun) when kind in [:overview, :issues] and is_function(restart_fun, 1) do
    config = load_config(kind)
    now = System.monotonic_time(:millisecond)
    retry_after = socket.assigns[config.retry_after]

    if is_nil(retry_after) or now >= retry_after do
      socket
      |> assign(config.retry_after, now + @retry_cooldown_ms)
      |> restart_fun.()
    else
      socket
    end
  end

  @doc false
  def finish_load(socket, kind, restart_fun) when kind in [:overview, :issues] and is_function(restart_fun, 1) do
    config = load_config(kind)
    pending? = socket.assigns[config.pending]

    socket =
      socket
      |> assign(config.running, false)
      |> assign(config.pending, false)

    if pending?, do: restart_fun.(socket), else: socket
  end

  defmacro __using__(_opts) do
    quote do
      alias StoryarnWeb.Live.Shared.DashboardHandlers, as: SharedDashboardHandlers

      @impl true
      def handle_info({:dashboard_invalidate, _scope}, socket) do
        {:noreply, SharedDashboardHandlers.schedule_reload(socket)}
      end

      @impl true
      def handle_info(:dashboard_cache_reset, socket) do
        {:noreply, SharedDashboardHandlers.schedule_reload(socket)}
      end

      @impl true
      def handle_info({:debounced_dashboard_reload, token}, socket) do
        {:noreply,
         SharedDashboardHandlers.fire_scheduled_reload(
           socket,
           :quiet,
           token
         )}
      end

      @impl true
      def handle_info({:max_wait_dashboard_reload, token}, socket) do
        {:noreply,
         SharedDashboardHandlers.fire_scheduled_reload(
           socket,
           :max_wait,
           token
         )}
      end
    end
  end

  defp begin_status(:overview, status), do: DashboardHelpers.begin_overview_load(status)
  defp begin_status(:issues, status), do: DashboardHelpers.begin_issues_load(status)

  defp load_config(:overview) do
    %{
      async: :load_dashboard_overview,
      status: :overview_status,
      running: :dashboard_overview_running?,
      pending: :dashboard_overview_reload_pending?,
      retry_after: :dashboard_overview_retry_after
    }
  end

  defp load_config(:issues) do
    %{
      async: :load_dashboard_issues,
      status: :issues_status,
      running: :dashboard_issues_running?,
      pending: :dashboard_issues_reload_pending?,
      retry_after: :dashboard_issues_retry_after
    }
  end
end
