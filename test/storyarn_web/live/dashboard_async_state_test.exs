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
      assert_receive :load_dashboard_overview
      refute_receive :load_dashboard_issues, 0

      {:noreply, stale_overview} =
        handle_dashboard_event(
          dashboard,
          "retry_dashboard_overview",
          socket(%{overview_status: :stale})
        )

      assert stale_overview.assigns.overview_status == :refreshing, "#{name} stale overview retry"
      assert_receive :load_dashboard_overview
      refute_receive :load_dashboard_issues, 0

      {:noreply, initial_issues} =
        handle_dashboard_event(
          dashboard,
          "retry_dashboard_issues",
          socket(%{issues_status: :error})
        )

      assert initial_issues.assigns.issues_status == :loading, "#{name} initial issues retry"
      assert_receive :load_dashboard_issues
      refute_receive :load_dashboard_overview, 0

      {:noreply, stale_issues} =
        handle_dashboard_event(
          dashboard,
          "retry_dashboard_issues",
          socket(%{issues_status: :stale})
        )

      assert stale_issues.assigns.issues_status == :refreshing, "#{name} stale issues retry"
      assert_receive :load_dashboard_issues
      refute_receive :load_dashboard_overview, 0
    end
  end

  defp handle_dashboard_async(SheetDashboard, task, result, socket), do: SheetDashboard.handle_async(task, result, socket)

  defp handle_dashboard_async(FlowDashboard, task, result, socket), do: FlowDashboard.handle_async(task, result, socket)

  defp handle_dashboard_async(SceneDashboard, task, result, socket), do: SceneDashboard.handle_async(task, result, socket)

  defp handle_dashboard_event(SheetDashboard, event, socket), do: SheetDashboard.handle_event(event, %{}, socket)

  defp handle_dashboard_event(FlowDashboard, event, socket), do: FlowDashboard.handle_event(event, %{}, socket)

  defp handle_dashboard_event(SceneDashboard, event, socket), do: SceneDashboard.handle_event(event, %{}, socket)

  defp socket(extra_assigns) do
    %Socket{
      assigns:
        Map.merge(
          %{
            __changed__: %{},
            project: %{id: 42},
            dashboard_stats: nil,
            issues: []
          },
          extra_assigns
        )
    }
  end
end
