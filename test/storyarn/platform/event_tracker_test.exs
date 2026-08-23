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

  test "routes a Scene fact through the historical metric contract" do
    Platform.react_to_event(%User{id: 42}, :scenes, :exploration_started, %{
      authored_scene_name: "private",
      has_saved_session: false,
      project_id: 7,
      scene_id: 11
    })

    assert_receive {:analytics_capture,
                    %{
                      event: "scene exploration started",
                      distinct_id: "user:42",
                      properties: %{
                        "has_saved_session" => false,
                        "project_id" => 7,
                        "scene_id" => 11
                      }
                    }}
  end

  test "routes Scene-owned asset facts from scalar and system actors" do
    payload = %{
      asset_type: "image",
      content_type: "image/png",
      created_variant: false,
      filename: "private-background.png",
      project_id: 7,
      purpose: "scene_background",
      size_bucket: "under_100kb"
    }

    Platform.react_to_event({:user_id, 42}, :scenes, :asset_uploaded, payload)

    assert_receive {:analytics_capture,
                    %{
                      event: "asset uploaded",
                      distinct_id: "user:42",
                      properties: %{
                        "asset_type" => "image",
                        "content_type" => "image/png",
                        "created_variant" => false,
                        "project_id" => 7,
                        "purpose" => "scene_background",
                        "size_bucket" => "under_100kb"
                      }
                    }}

    Platform.react_to_event(:system, :scenes, :asset_uploaded, %{payload | purpose: nil})

    assert_receive {:analytics_capture,
                    %{
                      event: "asset uploaded",
                      distinct_id: "system",
                      properties: %{
                        "asset_type" => "image",
                        "content_type" => "image/png",
                        "created_variant" => false,
                        "project_id" => 7,
                        "purpose" => nil,
                        "size_bucket" => "under_100kb"
                      }
                    }}
  end

  test "invalid scalar actors and authored asset dimensions fail closed" do
    payload = %{
      asset_type: "image",
      content_type: "image/png",
      created_variant: false,
      project_id: 7,
      purpose: "private-purpose",
      size_bucket: "under_100kb"
    }

    Platform.react_to_event({:user_id, 0}, :scenes, :asset_uploaded, %{payload | purpose: nil})
    Platform.react_to_event({:user_id, 42}, :scenes, :asset_uploaded, payload)

    refute_receive {:analytics_capture, _payload}
  end

  test "routes Scene version facts through the historical metric contracts" do
    for {event_type, event_name} <- [
          version_compared: "version compared",
          version_created: "version created",
          version_panel_opened: "version panel opened",
          version_restored: "version restored"
        ] do
      Platform.react_to_event(%User{id: 42}, :scenes, event_type, %{
        entity_type: "scene",
        project_id: 7,
        version_name: "private"
      })

      assert_receive {:analytics_capture,
                      %{
                        event: ^event_name,
                        distinct_id: "user:42",
                        properties: %{
                          "entity_type" => "scene",
                          "project_id" => 7
                        }
                      }}
    end
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
