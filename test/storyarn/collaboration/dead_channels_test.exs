defmodule Storyarn.Collaboration.DeadChannelsTest do
  @moduledoc """
  The `project:{id}:flow_graph` channel existed for one subscriber: the
  structural-analysis panel, which used it to mark its snapshot stale. The panel
  is gone. The handler never reloaded flow data, so nothing observable depended
  on the broadcast.

  The three functions were also mis-filed under the `# Project Restoration`
  banner, which is why they read as load-bearing. The restoration channel below
  is the real occupant of that section and stays.
  """
  use ExUnit.Case, async: true

  alias Storyarn.Collaboration

  describe "the flow_graph channel is gone" do
    test "Collaboration exports none of its three functions" do
      exported = exported_functions(Collaboration)

      for {name, arity} <- [
            {:flow_graph_topic, 1},
            {:subscribe_flow_graph, 1},
            {:broadcast_flow_graph_changed_from, 3}
          ] do
        refute {name, arity} in exported,
               "Collaboration.#{name}/#{arity} has no subscriber and no broadcaster left in lib/"
      end
    end
  end

  describe "the restoration channel it was filed under is untouched" do
    test "the restoration topic, subscribe and broadcast all survive" do
      exported = exported_functions(Collaboration)

      assert {:restoration_topic, 1} in exported
      assert {:subscribe_restoration, 1} in exported
    end

    test "the restoration topic still names the project channel" do
      assert Collaboration.restoration_topic(42) == "project:42:restoration"
    end
  end

  defp exported_functions(module) do
    {:module, ^module} = Code.ensure_loaded(module)
    module.__info__(:functions)
  end
end
