defmodule StoryarnWeb.Live.DashboardAsyncStateTest do
  use ExUnit.Case, async: true

  alias Phoenix.LiveView.Socket
  alias StoryarnWeb.FlowLive.Index, as: FlowDashboard
  alias StoryarnWeb.SceneLive.Index, as: SceneDashboard
  alias StoryarnWeb.SheetLive.Index, as: SheetDashboard

  @dashboards [
    {:sheets, SheetDashboard, :sheet_table_data, :sheet_issues, :all_sheet_issues},
    {:flows, FlowDashboard, :flow_table_data, :flow_issues, :all_flow_issues},
    {:scenes, SceneDashboard, :scene_table_data, :scene_issues, :all_scene_issues}
  ]

  test "overview and issues expose independent initial error states" do
    for {name, dashboard, _table_key, issues_key, _all_issues_key} <- @dashboards do
      {:noreply, overview} =
        handle_dashboard_async(
          dashboard,
          :load_dashboard_overview,
          {:exit, :overview_boom},
          socket(%{overview_status: :loading})
        )

      {:noreply, issues} =
        handle_dashboard_async(
          dashboard,
          :load_dashboard_issues,
          {:exit, :issues_boom},
          socket(%{issues_key => [], issues_status: :loading})
        )

      assert overview.assigns.overview_status == :error, "#{name} overview"
      assert overview.assigns.dashboard_stats == nil, "#{name} overview fabricated stats"
      assert issues.assigns.issues_status == :error, "#{name} issues"
      assert issues.assigns[issues_key] == [], "#{name} issues fabricated rows"
    end
  end

  test "refresh failures mark only their own data stale and preserve loaded content" do
    for {name, dashboard, table_key, issues_key, all_issues_key} <- @dashboards do
      {:noreply, overview} =
        handle_dashboard_async(
          dashboard,
          :load_dashboard_overview,
          {:exit, :overview_boom},
          socket(%{
            table_key => [%{id: 1}],
            overview_status: :refreshing,
            dashboard_stats: %{loaded: true}
          })
        )

      {:noreply, issues} =
        handle_dashboard_async(
          dashboard,
          :load_dashboard_issues,
          {:exit, :issues_boom},
          socket(%{
            issues_key => [%{id: "loaded"}],
            all_issues_key => [%{id: "loaded"}],
            issues_status: :refreshing
          })
        )

      assert overview.assigns.overview_status == :stale, "#{name} overview"
      assert overview.assigns.dashboard_stats == %{loaded: true}, "#{name} overview stats"
      assert overview.assigns[table_key] == [%{id: 1}], "#{name} overview rows"
      assert issues.assigns.issues_status == :stale, "#{name} issues"
      assert issues.assigns[issues_key] == [%{id: "loaded"}], "#{name} visible issues"
      assert issues.assigns[all_issues_key] == [%{id: "loaded"}], "#{name} all issues"
    end
  end

  test "each retry targets only its own task and reflects whether content exists" do
    for {name, dashboard, _table_key, _issues_key, _all_issues_key} <- @dashboards do
      {:noreply, initial_overview} =
        handle_dashboard_event(
          dashboard,
          "retry_dashboard_overview",
          socket(%{overview_status: :error})
        )

      assert initial_overview.assigns.overview_status == :loading, "#{name} initial overview retry"
      assert initial_overview.assigns.dashboard_overview_running?, "#{name} overview task"
      refute initial_overview.assigns.dashboard_overview_reload_pending?, "#{name} overview pending"
      assert_async_started(initial_overview, :load_dashboard_overview, name)

      {:noreply, stale_overview} =
        handle_dashboard_event(
          dashboard,
          "retry_dashboard_overview",
          socket(%{overview_status: :stale})
        )

      assert stale_overview.assigns.overview_status == :refreshing, "#{name} stale overview retry"
      assert stale_overview.assigns.dashboard_overview_running?, "#{name} stale overview task"
      refute stale_overview.assigns.dashboard_overview_reload_pending?, "#{name} stale overview pending"

      {:noreply, initial_issues} =
        handle_dashboard_event(
          dashboard,
          "retry_dashboard_issues",
          socket(%{issues_status: :error})
        )

      assert initial_issues.assigns.issues_status == :loading, "#{name} initial issues retry"
      assert initial_issues.assigns.dashboard_issues_running?, "#{name} issues task"
      refute initial_issues.assigns.dashboard_issues_reload_pending?, "#{name} issues pending"
      assert_async_started(initial_issues, :load_dashboard_issues, name)

      {:noreply, stale_issues} =
        handle_dashboard_event(
          dashboard,
          "retry_dashboard_issues",
          socket(%{issues_status: :stale})
        )

      assert stale_issues.assigns.issues_status == :refreshing, "#{name} stale issues retry"
      assert stale_issues.assigns.dashboard_issues_running?, "#{name} stale issues task"
      refute stale_issues.assigns.dashboard_issues_reload_pending?, "#{name} stale issues pending"
    end
  end

  test "retry events are no-ops unless their section is in error or stale" do
    for {name, dashboard, _table_key, _issues_key, _all_issues_key} <- @dashboards,
        status <- [:ready, :loading, :refreshing] do
      overview_socket =
        socket(%{
          overview_status: status,
          dashboard_overview_running?: status in [:loading, :refreshing]
        })

      {:noreply, overview_result} =
        handle_dashboard_event(
          dashboard,
          "retry_dashboard_overview",
          overview_socket
        )

      assert overview_result == overview_socket, "#{name} overview #{status}"

      issues_socket =
        socket(%{
          issues_status: status,
          dashboard_issues_running?: status in [:loading, :refreshing]
        })

      {:noreply, issues_result} =
        handle_dashboard_event(
          dashboard,
          "retry_dashboard_issues",
          issues_socket
        )

      assert issues_result == issues_socket, "#{name} issues #{status}"
    end
  end

  test "repeated retry events cannot replace an in-flight retry task" do
    for {name, dashboard, _table_key, _issues_key, _all_issues_key} <- @dashboards do
      {:noreply, first_overview} =
        handle_dashboard_event(
          dashboard,
          "retry_dashboard_overview",
          socket(%{overview_status: :error})
        )

      {:noreply, repeated_overview} =
        handle_dashboard_event(
          dashboard,
          "retry_dashboard_overview",
          first_overview
        )

      assert repeated_overview == first_overview, "#{name} repeated overview"

      {:noreply, first_issues} =
        handle_dashboard_event(
          dashboard,
          "retry_dashboard_issues",
          socket(%{issues_status: :error})
        )

      {:noreply, repeated_issues} =
        handle_dashboard_event(
          dashboard,
          "retry_dashboard_issues",
          first_issues
        )

      assert repeated_issues == first_issues, "#{name} repeated issues"
    end
  end

  test "a fast retry failure is rate-limited before another task can start" do
    for {name, dashboard, _table_key, issues_key, all_issues_key} <- @dashboards do
      {:noreply, overview_retry} =
        handle_dashboard_event(
          dashboard,
          "retry_dashboard_overview",
          socket(%{overview_status: :error})
        )

      {:noreply, failed_overview_retry} =
        handle_dashboard_async(
          dashboard,
          :load_dashboard_overview,
          {:exit, :overview_boom},
          overview_retry
        )

      assert failed_overview_retry.assigns.overview_status == :error,
             "#{name} overview retry failure"

      assert is_integer(failed_overview_retry.assigns.dashboard_overview_retry_after),
             "#{name} overview retry timestamp"

      overview_in_cooldown =
        put_retry_after(
          failed_overview_retry,
          :dashboard_overview_retry_after
        )

      {:noreply, blocked_overview_retry} =
        handle_dashboard_event(
          dashboard,
          "retry_dashboard_overview",
          overview_in_cooldown
        )

      assert blocked_overview_retry == overview_in_cooldown,
             "#{name} overview retry cooldown"

      {:noreply, issues_retry} =
        handle_dashboard_event(
          dashboard,
          "retry_dashboard_issues",
          socket(%{
            issues_key => [],
            all_issues_key => [],
            issues_status: :error
          })
        )

      {:noreply, failed_issues_retry} =
        handle_dashboard_async(
          dashboard,
          :load_dashboard_issues,
          {:exit, :issues_boom},
          issues_retry
        )

      assert failed_issues_retry.assigns.issues_status == :error,
             "#{name} issues retry failure"

      assert is_integer(failed_issues_retry.assigns.dashboard_issues_retry_after),
             "#{name} issues retry timestamp"

      issues_in_cooldown =
        put_retry_after(
          failed_issues_retry,
          :dashboard_issues_retry_after
        )

      {:noreply, blocked_issues_retry} =
        handle_dashboard_event(
          dashboard,
          "retry_dashboard_issues",
          issues_in_cooldown
        )

      assert blocked_issues_retry == issues_in_cooldown,
             "#{name} issues retry cooldown"
    end
  end

  test "a failed refresh clears a pending invalidation instead of entering an automatic retry loop" do
    for {name, dashboard, _table_key, issues_key, all_issues_key} <- @dashboards do
      {:noreply, overview} =
        handle_dashboard_async(
          dashboard,
          :load_dashboard_overview,
          {:exit, :overview_boom},
          socket(%{
            overview_status: :refreshing,
            dashboard_overview_running?: true,
            dashboard_overview_reload_pending?: true
          })
        )

      assert overview.assigns.overview_status == :stale, "#{name} overview failure status"
      refute overview.assigns.dashboard_overview_running?, "#{name} overview stopped"
      refute overview.assigns.dashboard_overview_reload_pending?, "#{name} overview pending cleared"

      {:noreply, issues} =
        handle_dashboard_async(
          dashboard,
          :load_dashboard_issues,
          {:exit, :issues_boom},
          socket(%{
            issues_key => [%{id: "loaded"}],
            all_issues_key => [%{id: "loaded"}],
            issues_status: :refreshing,
            dashboard_issues_running?: true,
            dashboard_issues_reload_pending?: true
          })
        )

      assert issues.assigns.issues_status == :stale, "#{name} issues failure status"
      refute issues.assigns.dashboard_issues_running?, "#{name} issues stopped"
      refute issues.assigns.dashboard_issues_reload_pending?, "#{name} issues pending cleared"
    end
  end

  defp handle_dashboard_async(SheetDashboard, task, result, socket), do: SheetDashboard.handle_async(task, result, socket)

  defp handle_dashboard_async(FlowDashboard, task, result, socket), do: FlowDashboard.handle_async(task, result, socket)

  defp handle_dashboard_async(SceneDashboard, task, result, socket), do: SceneDashboard.handle_async(task, result, socket)

  defp handle_dashboard_event(SheetDashboard, event, socket), do: SheetDashboard.handle_event(event, %{}, socket)

  defp handle_dashboard_event(FlowDashboard, event, socket), do: FlowDashboard.handle_event(event, %{}, socket)

  defp handle_dashboard_event(SceneDashboard, event, socket), do: SceneDashboard.handle_event(event, %{}, socket)

  defp put_retry_after(socket, key) do
    retry_after = System.monotonic_time(:millisecond) + 60_000
    %{socket | assigns: Map.put(socket.assigns, key, retry_after)}
  end

  defp assert_async_started(socket, task, dashboard) do
    assert {_ref, pid, :start} = socket.private[:live_async][task],
           "#{dashboard} #{task} did not start a LiveView async task"

    assert is_pid(pid)
  end

  defp socket(extra_assigns) do
    %Socket{
      transport_pid: self(),
      assigns:
        Map.merge(
          %{
            __changed__: %{},
            project: %{id: 42},
            workspace: %{slug: "workspace"},
            locale: "en",
            dashboard_stats: nil,
            issues: [],
            dashboard_overview_running?: false,
            dashboard_overview_reload_pending?: false,
            dashboard_issues_running?: false,
            dashboard_issues_reload_pending?: false
          },
          extra_assigns
        )
    }
  end
end
