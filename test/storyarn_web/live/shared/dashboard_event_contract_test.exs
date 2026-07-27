defmodule StoryarnWeb.Live.Shared.DashboardEventContractTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Phoenix.LiveView.Socket
  alias StoryarnWeb.FlowLive
  alias StoryarnWeb.SceneLive
  alias StoryarnWeb.SheetLive

  @dashboard_source_pairs [
    {"flows", "assets/app/live/flow/dashboard/FlowDashboard.vue", "lib/storyarn_web/live/flow_live/index.ex"},
    {"sheets", "assets/app/live/sheet/dashboard/SheetDashboard.vue", "lib/storyarn_web/live/sheet_live/index.ex"},
    {"scenes", "assets/app/live/scene/dashboard/SceneDashboard.vue", "lib/storyarn_web/live/scene_live/index.ex"}
  ]

  test "every literal dashboard pushEvent has a matching LiveView handler" do
    repo_root = Path.expand("../../../..", __DIR__)

    for {dashboard, client_path, server_path} <- @dashboard_source_pairs do
      client_source = File.read!(Path.join(repo_root, client_path))
      server_source = File.read!(Path.join(repo_root, server_path))

      client_events =
        ~r/live\.pushEvent\(\s*["']([^"']+)["']/
        |> Regex.scan(client_source, capture: :all_but_first)
        |> List.flatten()

      assert length(client_events) == length(Regex.scan(~r/live\.pushEvent\(/, client_source)),
             "#{dashboard} dashboard contains a non-literal pushEvent that the contract test cannot verify"

      literal_server_events =
        ~r/def handle_event\("([^"]+)"/
        |> Regex.scan(server_source, capture: :all_but_first)
        |> List.flatten()

      guarded_server_events =
        ~r/when event in ~w\(([^)]+)\)/
        |> Regex.scan(server_source, capture: :all_but_first)
        |> List.flatten()
        |> Enum.flat_map(&String.split/1)

      missing_events =
        client_events
        |> MapSet.new()
        |> MapSet.difference(MapSet.new(literal_server_events ++ guarded_server_events))
        |> MapSet.to_list()

      assert missing_events == [],
             "#{dashboard} dashboard pushes events without a matching handler: #{inspect(missing_events)}"
    end
  end

  test "dashboard LiveViews ignore malformed or unknown client events instead of crashing" do
    socket = %Socket{assigns: %{__changed__: %{}}}

    events = [
      {&FlowLive.Index.handle_event/3, "sort_flows", %{}},
      {&SheetLive.Index.handle_event/3, "filter_sheet_issues", %{"filter" => "code"}},
      {&SceneLive.Index.handle_event/3, "page_scene_issues", %{}},
      {&FlowLive.Index.handle_event/3, "unknown_dashboard_event", %{}},
      {&SheetLive.Index.handle_event/3, "unknown_dashboard_event", %{}},
      {&SceneLive.Index.handle_event/3, "unknown_dashboard_event", %{}}
    ]

    for {handler, event, params} <- events do
      assert {:noreply, ^socket} = handler.(event, params, socket)
    end
  end

  test "dashboard LiveViews warn when an unknown client event is ignored" do
    socket = %Socket{assigns: %{__changed__: %{}}}

    log =
      capture_log(fn ->
        for handler <- [
              &FlowLive.Index.handle_event/3,
              &SheetLive.Index.handle_event/3,
              &SceneLive.Index.handle_event/3
            ] do
          assert {:noreply, ^socket} =
                   handler.("unknown_dashboard_event", %{"private" => "must-not-be-logged"}, socket)
        end
      end)

    for dashboard <- ~w(flows sheets scenes) do
      assert log =~ "[#{dashboard} dashboard] ignored unknown event \"unknown_dashboard_event\""
    end

    refute log =~ "must-not-be-logged"
  end

  test "dashboard row actions clear malformed IDs instead of retaining a previous target" do
    socket = %Socket{assigns: %{__changed__: %{}, pending_delete_id: 42}}

    setters = [
      {&FlowLive.Index.handle_event/3, "set_pending_delete"},
      {&SheetLive.Index.handle_event/3, "set_pending_delete_sheet"},
      {&SceneLive.Index.handle_event/3, "set_pending_delete_scene"}
    ]

    for malformed_id <- [%{}, [], "not-a-number", "1.5", 0, -1, 9_223_372_036_854_775_808],
        {handler, event} <- setters do
      assert {:noreply, result} = handler.(event, %{"id" => malformed_id}, socket)
      assert result.assigns.pending_delete_id == nil
    end
  end

  test "direct flow mutations ignore malformed IDs before querying Ecto" do
    socket = %Socket{assigns: %{__changed__: %{}}}

    for event <- ~w(delete delete_flow set_main set_main_flow),
        malformed_id <- [%{}, [], "not-a-number", 0, -1, 9_223_372_036_854_775_808] do
      assert {:noreply, ^socket} =
               FlowLive.Index.handle_event(event, %{"id" => malformed_id}, socket)
    end
  end

  test "viewer confirmations return an explicit authorization flash" do
    socket = %Socket{
      assigns: %{
        __changed__: %{},
        flash: %{},
        membership: %{role: "viewer"},
        pending_delete_id: 42
      }
    }

    for {handler, event} <- [
          {&SheetLive.Index.handle_event/3, "confirm_delete_sheet"},
          {&SceneLive.Index.handle_event/3, "confirm_delete_scene"}
        ] do
      assert {:noreply, result} = handler.(event, %{}, socket)

      assert result.assigns.flash["error"] ==
               "You don't have permission to perform this action."
    end
  end
end
