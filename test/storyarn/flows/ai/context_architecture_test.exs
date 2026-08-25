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
    durable_targets = Enum.map(policy.additional_durable_contract_targets, & &1.target)

    assert Enum.all?(@spi_targets, &(&1 in durable_targets))
    refute Enum.any?(@spi_targets, &(&1 in policy.globally_allowed_technical_targets))
    refute "lib/storyarn/ai/" in policy.globally_allowed_technical_targets
    refute "lib/storyarn/ai/context/" in policy.globally_allowed_technical_targets

    graph = %{
      "lib/storyarn/flows/ai/context_contract.ex" => %{
        "lib/storyarn/ai/context/contract.ex" => "runtime",
        "lib/storyarn/ai/context/policy.ex" => "export",
        "lib/storyarn/ai/context/subject_ref.ex" => "export",
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
