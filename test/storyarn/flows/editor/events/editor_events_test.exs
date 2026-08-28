defmodule Storyarn.Flows.Editor.EventsTest do
  use ExUnit.Case, async: true

  alias Storyarn.Flows.Editor.Events

  @event_types [
    :node_created,
    :sequence_track_updated,
    :sequence_visual_layer_created,
    :sequence_visual_layer_updated
  ]

  test "the Editor event vocabulary contains only facts owned by Flow authoring" do
    assert Events.event_types() == @event_types
  end

  test "malformed Editor facts fail closed" do
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
  end

  test "valid Editor facts keep the legacy payload contract" do
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
  end
end
