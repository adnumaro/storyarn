defmodule StoryarnWeb.Live.Shared.DashboardEventContractTest do
  use ExUnit.Case, async: true

  alias Phoenix.LiveView.Socket
  alias StoryarnWeb.FlowLive
  alias StoryarnWeb.SceneLive
  alias StoryarnWeb.SheetLive

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
