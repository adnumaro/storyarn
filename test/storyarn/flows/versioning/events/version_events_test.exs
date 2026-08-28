defmodule Storyarn.Flows.Versioning.EventsTest do
  use ExUnit.Case, async: true

  alias Storyarn.Flows.Versioning.Events

  @event_types [:version_compared, :version_created, :version_panel_opened, :version_restored]

  test "owns only the versioning event vocabulary" do
    assert Events.event_types() == @event_types
  end

  test "accepts the exact Flow-version payload and rejects malformed facts" do
    for event_type <- @event_types do
      assert Events.valid_payload?(event_type, %{entity_type: "flow", project_id: 2})
    end

    refute Events.valid_payload?(:version_created, %{entity_type: "sheet", project_id: 2})
    refute Events.valid_payload?(:version_restored, %{entity_type: "flow", project_id: -1})
    refute Events.valid_payload?(:node_created, %{entity_type: "flow", project_id: 2})
  end

  test "unknown and malformed version facts remain best-effort" do
    assert Events.emit(nil, :unknown, %{}) == :ok
    assert Events.emit(nil, :version_created, :invalid_payload) == :ok
    assert Events.emit(nil, :version_created, %{entity_type: "sheet", project_id: 2}) == :ok
  end
end
