defmodule Storyarn.Platform.Collaboration.DeadChannelsTest do
  @moduledoc """
  The `project:{id}:flow_graph` channel existed for one subscriber: the
  structural-analysis panel, which used it to mark its snapshot stale. The panel
  is gone. The handler never reloaded flow data, so nothing observable depended
  on the broadcast.

  """
  use ExUnit.Case, async: true

  alias Storyarn.Platform.Collaboration

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

  defp exported_functions(module) do
    {:module, ^module} = Code.ensure_loaded(module)
    module.__info__(:functions)
  end
end
