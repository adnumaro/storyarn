defmodule Storyarn.Flows.EventsTest do
  use ExUnit.Case, async: true

  alias Storyarn.Flows.Events

  @event_types [
    :debug_started,
    :node_created,
    :player_started,
    :sequence_track_updated,
    :sequence_visual_layer_created,
    :sequence_visual_layer_updated,
    :version_compared,
    :version_created,
    :version_panel_opened,
    :version_restored
  ]

  test "the complete Flow business event vocabulary is Flow-owned" do
    assert Events.event_types() == @event_types
  end

  test "unknown or malformed Flow events fail closed" do
    assert Events.emit(nil, :unknown, %{}) == :ok
    assert Events.emit(nil, :node_created, :invalid_payload) == :ok
    refute Events.valid_payload?(:node_created, %{flow_id: 1, project_id: 2})

    refute Events.valid_payload?(:node_created, %{
             creation_method: "create",
             flow_id: 1,
             has_parent: false,
             node_type: "private user-authored content",
             project_id: 2
           })

    refute Events.valid_payload?(:version_created, %{entity_type: "sheet", project_id: 2})
    refute Events.valid_payload?(:debug_started, %{flow_id: 0, project_id: 2})
    refute Events.valid_payload?(:version_created, %{entity_type: "flow", project_id: -1})
  end

  test "Flow validates the shape of the fact before handing it to Platform" do
    assert Events.valid_payload?(:node_created, %{
             creation_method: "create",
             flow_id: 1,
             has_parent: false,
             node_type: "dialogue",
             project_id: 2
           })

    assert Events.valid_payload?(:sequence_track_updated, %{
             changed_asset: true,
             changed_volume: false,
             flow_id: 1,
             has_asset: true,
             project_id: 2,
             sequence_id: 3,
             track_kind: "music"
           })

    assert Events.valid_payload?(:version_restored, %{
             entity_type: "flow",
             project_id: 2
           })
  end
end
