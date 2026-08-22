defmodule Storyarn.Platform.EventTrackerTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Storyarn.Accounts.User
  alias Storyarn.Platform
  alias Storyarn.Platform.EventTracker
  alias Storyarn.Platform.ProductMetrics
  alias StoryarnTest.PlatformEventReaction

  defmodule TestAnalyticsAdapter do
    @moduledoc false

    def capture(payload) do
      send(Process.get(:platform_event_tracker_test_pid), {:analytics_capture, payload})
      :ok
    end

    def identify(_payload), do: :ok
  end

  setup do
    original_adapter = Application.get_env(:storyarn, :analytics_adapter)

    Process.put(:platform_event_tracker_test_pid, self())
    Application.put_env(:storyarn, :analytics_adapter, TestAnalyticsAdapter)

    on_exit(fn ->
      if is_nil(original_adapter) do
        Application.delete_env(:storyarn, :analytics_adapter)
      else
        Application.put_env(:storyarn, :analytics_adapter, original_adapter)
      end

      Process.delete(:platform_event_tracker_test_pid)
      Process.delete(:platform_event_reaction_mode)
    end)
  end

  test "routes a Flow fact to the Platform-owned metric reaction" do
    Platform.react_to_event(%User{id: 42}, :flows, :node_created, %{
      content: "private story content",
      creation_method: "create",
      flow_id: 11,
      has_parent: true,
      node_type: "sequence",
      project_id: 7,
      slug: "private-slug"
    })

    assert_receive {:analytics_capture,
                    %{
                      event: "flow node created",
                      distinct_id: "user:42",
                      properties: %{
                        "creation_method" => "create",
                        "flow_id" => 11,
                        "has_parent" => true,
                        "node_type" => "sequence",
                        "project_id" => 7
                      }
                    }}
  end

  test "ignores events without a declared Platform reaction" do
    assert Platform.react_to_event(%User{id: 42}, :flows, :unknown, %{flow_id: 11}) == :ok
    refute_receive {:analytics_capture, _payload}
  end

  test "EventTracker owns the reaction routing table" do
    routes = EventTracker.routes()

    assert routes |> Map.keys() |> Enum.sort() == ProductMetrics.events()

    assert Enum.all?(routes, fn {_event, handlers} ->
             handlers == [ProductMetrics]
           end)
  end

  test "discovery, routing, and execution failures remain best-effort" do
    handlers = [PlatformEventReaction, ProductMetrics]

    payload = %{
      creation_method: "create",
      flow_id: 11,
      has_parent: true,
      node_type: "sequence",
      project_id: 7
    }

    log =
      capture_log(fn ->
        Process.put(:platform_event_reaction_mode, :discovery_failure)

        assert Map.fetch!(EventTracker.routes(handlers), {:flows, :node_created}) == [ProductMetrics]

        assert EventTracker.react_with_handlers(
                 %User{id: 42},
                 :flows,
                 :node_created,
                 payload,
                 handlers
               ) == :ok

        Process.put(:platform_event_reaction_mode, :invalid_routes)

        assert EventTracker.routes([PlatformEventReaction]) == %{
                 {:flows, :node_created} => [PlatformEventReaction]
               }

        Process.put(:platform_event_reaction_mode, :execution_failure)

        assert EventTracker.react_with_handlers(
                 %User{id: 42},
                 :flows,
                 :node_created,
                 payload,
                 handlers
               ) == :ok
      end)

    assert_receive {:analytics_capture, %{event: "flow node created"}}
    assert_receive {:analytics_capture, %{event: "flow node created"}}
    assert log =~ "reaction discovery failed"
    assert log =~ "reaction routing failed"
    assert log =~ "reaction execution failed"
  end
end
