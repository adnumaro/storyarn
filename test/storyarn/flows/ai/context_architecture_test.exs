defmodule Storyarn.Flows.AI.ContextArchitectureTest do
  use ExUnit.Case, async: true

  alias Storyarn.Architecture.DependencyPolicy

  @spi_targets [
    "lib/storyarn/ai/context/contract.ex",
    "lib/storyarn/ai/context/policy.ex",
    "lib/storyarn/ai/context/subject_ref.ex"
  ]

  test "the AI context SPI is exact and does not open the AI internals to Flows" do
    {policy, _binding} = Code.eval_file("config/architecture_boundaries.exs")

    assert Enum.all?(@spi_targets, &(&1 in policy.always_allowed_targets))
    refute "lib/storyarn/ai/" in policy.always_allowed_targets
    refute "lib/storyarn/ai/context/" in policy.always_allowed_targets

    graph = %{
      "lib/storyarn/flows/ai/context_contract.ex" => %{
        "lib/storyarn/ai/context/contract.ex" => "compile",
        "lib/storyarn/ai/context/policy.ex" => "compile",
        "lib/storyarn/ai/context/subject_ref.ex" => "compile",
        "lib/storyarn/ai/context/finalizer.ex" => "runtime"
      }
    }

    assert DependencyPolicy.forbidden_edges(graph, policy).flows ==
             MapSet.new([
               {
                 "lib/storyarn/flows/ai/context_contract.ex",
                 "lib/storyarn/ai/context/finalizer.ex",
                 "runtime"
               }
             ])
  end
end
