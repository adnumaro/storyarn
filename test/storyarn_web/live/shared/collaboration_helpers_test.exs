defmodule StoryarnWeb.Live.Shared.CollaborationHelpersTest do
  use ExUnit.Case, async: true

  alias Storyarn.Platform.Collaboration
  alias StoryarnWeb.Live.Shared.CollaborationHelpers

  describe "teardown/2" do
    test "tells the other collaborators to remove the user's cursor" do
      scope = {:flow, System.unique_integer([:positive])}
      user_id = System.unique_integer([:positive])
      Phoenix.PubSub.subscribe(Storyarn.PubSub, Collaboration.cursors_topic(scope))

      # The broadcast skips its sender, so tear down from another process.
      Task.await(Task.async(fn -> CollaborationHelpers.teardown(scope, user_id) end))

      assert_receive {:cursor_leave, ^user_id}
    end
  end
end
