defmodule StoryarnTest.PlatformEventReaction do
  @moduledoc false

  @behaviour Storyarn.Platform.EventReaction

  @impl true
  def events do
    case Process.get(:platform_event_reaction_mode) do
      :discovery_failure -> raise "discovery failed"
      :invalid_routes -> [{:flows, :node_created}, {:flows, "invalid"}, :invalid]
      _mode -> [{:flows, :node_created}]
    end
  end

  @impl true
  def handle(_scope_or_user, source, event_type, _payload) do
    case Process.get(:platform_event_reaction_mode) do
      :execution_failure -> throw(:execution_failed)
      _mode -> send(Process.get(:platform_event_tracker_test_pid), {:reaction_ran, source, event_type})
    end

    :ok
  end
end
