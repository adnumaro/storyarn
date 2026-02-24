defmodule Storyarn.Flows.SceneResolverTest do
  use Storyarn.DataCase

  alias Storyarn.Flows.SceneResolver

  describe "resolve_scene_id/2" do
    test "returns flow's own scene_id when set" do
      flow = %Storyarn.Flows.Flow{
        id: 1,
        scene_id: 42,
        parent_id: nil
      }

      assert SceneResolver.resolve_scene_id(flow) == 42
    end

    test "returns caller_scene_id when flow has no scene_id" do
      flow = %Storyarn.Flows.Flow{
        id: 1,
        scene_id: nil,
        parent_id: nil
      }

      assert SceneResolver.resolve_scene_id(flow, caller_scene_id: 99) == 99
    end

    test "flow's own scene_id takes priority over caller" do
      flow = %Storyarn.Flows.Flow{
        id: 1,
        scene_id: 42,
        parent_id: nil
      }

      assert SceneResolver.resolve_scene_id(flow, caller_scene_id: 99) == 42
    end

    test "returns nil when no scene_id and no parent" do
      flow = %Storyarn.Flows.Flow{
        id: 1,
        scene_id: nil,
        parent_id: nil
      }

      assert SceneResolver.resolve_scene_id(flow) == nil
    end
  end
end
