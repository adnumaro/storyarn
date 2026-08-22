defmodule Storyarn.Platform.ProductMetricsTest do
  use ExUnit.Case, async: true

  alias Storyarn.Analytics.EventContract
  alias Storyarn.Platform.ProductMetrics

  @events %{
    {:flows, :debug_started} => {"flow debug started", ~w(flow_id project_id)},
    {:flows, :node_created} => {"flow node created", ~w(creation_method flow_id has_parent node_type project_id)},
    {:flows, :player_started} => {"flow player started", ~w(flow_id project_id)},
    {:flows, :sequence_track_updated} =>
      {"sequence track updated", ~w(changed_asset changed_volume flow_id has_asset project_id sequence_id track_kind)},
    {:flows, :sequence_visual_layer_created} =>
      {"sequence visual layer created", ~w(flow_id has_asset layer_kind project_id sequence_id slot)},
    {:flows, :sequence_visual_layer_updated} =>
      {"sequence visual layer updated", ~w(changed_asset flow_id has_asset layer_kind project_id sequence_id slot)},
    {:flows, :version_compared} => {"version compared", ~w(entity_type project_id)},
    {:flows, :version_created} => {"version created", ~w(entity_type project_id)},
    {:flows, :version_panel_opened} => {"version panel opened", ~w(entity_type project_id)},
    {:flows, :version_restored} => {"version restored", ~w(entity_type project_id)}
  }

  test "Platform owns the complete Flow metric vocabulary and privacy allowlist" do
    expected_events = @events |> Map.keys() |> Enum.sort()
    assert ProductMetrics.events() == expected_events

    assert Map.new(@events, fn {event, {name, keys}} ->
             assert {:ok, ^name, allowed_keys} = EventContract.resolve(ProductMetrics, event)
             assert allowed_keys == MapSet.new(keys)
             {event, {name, keys}}
           end) == @events
  end

  test "unknown product metric reactions fail closed" do
    assert ProductMetrics.event({:flows, :unknown}) == :error
    assert EventContract.resolve(ProductMetrics, {:flows, :unknown}) == :error
  end

  test "Platform independently validates and projects values before analytics" do
    payload = %{
      content: "private story content",
      creation_method: "create",
      flow_id: 11,
      has_parent: true,
      node_type: "dialogue",
      project_id: 7
    }

    assert {:ok,
            %{
              creation_method: "create",
              flow_id: 11,
              has_parent: true,
              node_type: "dialogue",
              project_id: 7
            }} = EventContract.sanitize(ProductMetrics, {:flows, :node_created}, payload)

    assert EventContract.sanitize(
             ProductMetrics,
             {:flows, :node_created},
             %{payload | node_type: "private user-authored content"}
           ) == :error
  end
end
