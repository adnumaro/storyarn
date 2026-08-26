defmodule Storyarn.Flows.Runtime.EventsTest do
  use ExUnit.Case, async: true

  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.Runtime.Events

  test "owns only the runtime event vocabulary" do
    assert Events.event_types() == [:debug_started, :player_started]
  end

  test "accepts the exact runtime payload contract and rejects malformed facts" do
    assert Events.valid_payload?(:debug_started, %{flow_id: 1, project_id: 2})
    assert Events.valid_payload?(:player_started, %{flow_id: 1, project_id: 2})

    refute Events.valid_payload?(:debug_started, %{flow_id: 0, project_id: 2})
    refute Events.valid_payload?(:player_started, %{flow_id: 1, project_id: nil})
    refute Events.valid_payload?(:node_created, %{flow_id: 1, project_id: 2})
  end

  test "malformed Flow wrappers remain best-effort" do
    flow = %Flow{id: nil, project_id: nil}

    assert Events.debug_started(nil, flow) == :ok
    assert Events.player_started(nil, flow) == :ok
  end
end
