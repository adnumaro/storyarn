defmodule Storyarn.Scenes.Exploration.EventsTest do
  use ExUnit.Case, async: false

  alias Storyarn.Platform
  alias Storyarn.Scenes.Exploration.Events
  alias Storyarn.Scenes.Scene

  test "preserves the exploration-started event contract" do
    test_pid = self()
    tracer = spawn_link(fn -> forward_traces(test_pid) end)

    :erlang.trace(test_pid, true, [:call, {:tracer, tracer}])
    :erlang.trace_pattern({Platform, :react_to_event, 4}, true, [])

    on_exit(fn ->
      :erlang.trace_pattern({Platform, :react_to_event, 4}, false, [])
      send(tracer, :stop)
    end)

    scene = %Scene{id: 9, project_id: 4}

    assert :ok = Events.exploration_started(:system, scene, true)

    assert_receive {:trace, ^test_pid, :call,
                    {Platform, :react_to_event,
                     [
                       :system,
                       :scenes,
                       :exploration_started,
                       %{has_saved_session: true, project_id: 4, scene_id: 9}
                     ]}}
  end

  test "malformed exploration events still fail closed" do
    assert :ok = Events.exploration_started(:system, %Scene{id: 0, project_id: 4}, true)
    assert :ok = Events.exploration_started(:system, %Scene{id: 9, project_id: nil}, true)
    assert :ok = Events.exploration_started(:system, %Scene{id: 9, project_id: 4}, "true")
    assert :ok = Events.exploration_started(:system, %{}, true)
  end

  defp forward_traces(test_pid) do
    receive do
      :stop ->
        :ok

      message ->
        send(test_pid, message)
        forward_traces(test_pid)
    end
  end
end
