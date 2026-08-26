defmodule Storyarn.Scenes.ExplorationFacadeTest do
  use ExUnit.Case, async: true

  alias Storyarn.Scenes.Exploration
  alias Storyarn.Scenes.FlowRuntime.Engine

  test "preserves the stable runtime state identity" do
    state = Exploration.runtime_init(%{}, 17)

    assert %Storyarn.Scenes.FlowRuntime.State{} = state

    assert %{state | started_at: nil} ==
             %{Engine.init(%{}, 17) | started_at: nil}
  end

  test "finds the runtime entry node with the root-facade semantics" do
    nodes = %{
      3 => %{type: "dialogue"},
      9 => %{type: "entry"}
    }

    assert Exploration.runtime_entry_node(nodes) == 9
  end
end
